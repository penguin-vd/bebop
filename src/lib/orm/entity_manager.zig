const std = @import("std");
const pg = @import("pg");

const QueryBuilder = @import("query_builder.zig").QueryBuilder;
const utils = @import("utils.zig");

pub fn EntityManager(comptime Model: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        conn: *pg.Conn,

        tracked_entities: std.AutoHashMap(*Model, EntityState),

        const EntityState = enum {
            new,
            managed,
            deleted,
        };

        pub fn init(allocator: std.mem.Allocator, conn: *pg.Conn) Self {
            return .{
                .allocator = allocator,
                .conn = conn,
                .tracked_entities = std.AutoHashMap(*Model, EntityState).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.tracked_entities.keyIterator();
            while (it.next()) |entity_ptr| {
                self.allocator.destroy(entity_ptr.*);
            }
            self.tracked_entities.deinit();
        }

        pub fn query(self: *Self) QueryBuilder(Model) {
            return QueryBuilder(Model).init(self.allocator);
        }

        pub fn find(self: *Self, qb: *QueryBuilder(Model)) ![]*Model {
            const results = try qb.execute(self.conn, Model);
            defer self.allocator.free(results);

            var result_ptrs = try self.allocator.alloc(*Model, results.len);

            for (results, 0..) |result, i| {
                const entity_ptr = try self.allocator.create(Model);
                entity_ptr.* = result;
                result_ptrs[i] = entity_ptr;

                try self.tracked_entities.put(entity_ptr, .managed);
            }

            return result_ptrs;
        }

        pub fn get(self: *Self, value: anytype) !?*Model {
            var qb = self.query();
            defer qb.deinit();

            const struct_info = @typeInfo(Model).@"struct";

            var pk_column_name: []const u8 = undefined;
            inline for (struct_info.fields) |field| {
                if (utils.get_field_meta(Model, field.name)) |meta| {
                    if (meta.is_primary_key) {
                        pk_column_name = utils.get_column_name(Model, field.name);
                        break;
                    }
                }
            }

            try qb.where(pk_column_name, "=", value);

            const models = try self.find(&qb);

            if (models.len == 0) {
                return null;
            }

            if (models.len > 1) {
                self.allocator.free(models);
                return error.GotMoreThenOneResult;
            }

            return models[0];
        }

        pub fn persist(self: *Self, entity: *Model) !void {
            try self.tracked_entities.put(entity, .new);
        }

        pub fn remove(self: *Self, entity: *Model) !void {
            try self.tracked_entities.put(entity, .deleted);
        }

        pub fn clear(self: *Self) void {
            self.tracked_entities.clearRetainingCapacity();
        }

        pub fn flush(self: *Self) !void {
            try self.conn.begin();
            errdefer self.conn.rollback() catch {};

            var it = self.tracked_entities.iterator();

            var keys_to_remove = std.ArrayList(*Model){};
            defer keys_to_remove.deinit(self.allocator);

            while (it.next()) |entry| {
                const entity = entry.key_ptr.*;
                const state = entry.value_ptr.*;

                switch (state) {
                    .new => {
                        const id = try self.insertEntity(Model, entity);
                        const struct_info = @typeInfo(Model).@"struct";

                        inline for (struct_info.fields) |field| {
                            const meta = comptime utils.get_field_meta(Model, field.name);
                            const is_pk = if (meta) |m| m.is_primary_key else false;
                            if (is_pk) {
                                switch (@typeInfo(field.type)) {
                                    .int => {
                                        @field(entity, field.name) = id;
                                    },
                                    else => unreachable,
                                }
                                break;
                            }
                        }
                        entry.value_ptr.* = .managed;
                    },
                    .managed => {
                        try self.updateEntity(Model, entity);
                    },
                    .deleted => {
                        try self.deleteEntity(entity);
                        try keys_to_remove.append(self.allocator, entry.key_ptr.*);
                        self.allocator.destroy(entity);
                    },
                }
            }

            for (keys_to_remove.items) |key| {
                _ = self.tracked_entities.remove(key);
            }

            try self.conn.commit();
        }

        fn bindRelationOrValue(
            self: *Self,
            comptime T: type,
            comptime field: std.builtin.Type.StructField,
            entity: *T,
            stmt: *pg.Stmt,
            relation_ids: *std.StringHashMap(i32),
        ) !void {
            _ = self;
            const is_relation = comptime utils.is_relation(field.type);

            if (is_relation) {
                if (relation_ids.get(field.name)) |id| {
                    try stmt.bind(id);
                } else {
                    const relation = @field(entity, field.name);
                    const relation_info = @typeInfo(field.type).@"struct";

                    inline for (relation_info.fields) |rfield| {
                        if (utils.get_field_meta(field.type, rfield.name)) |rmeta| {
                            if (rmeta.is_primary_key) {
                                const value = @field(relation, rfield.name);
                                try stmt.bind(value);
                                break;
                            }
                        }
                    }
                }
            } else {
                try stmt.bind(@field(entity, field.name));
            }
        }

        fn insertEntity(self: *Self, comptime T: type, entity: *T) !i32 {
            const struct_info = @typeInfo(T).@"struct";

            // First pass: insert any relations that need inserting
            var relation_ids = std.StringHashMap(i32).init(self.allocator);
            defer relation_ids.deinit();

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;

                const is_relation = comptime utils.is_relation(field.type);
                if (is_relation) {
                    var relation = &@field(entity, field.name);
                    const relation_info = @typeInfo(field.type).@"struct";

                    inline for (relation_info.fields) |rfield| {
                        if (utils.get_field_meta(field.type, rfield.name)) |rmeta| {
                            if (rmeta.is_primary_key) {
                                const value = @field(relation.*, rfield.name);
                                if (utils.is_falsy(rfield.type, value)) {
                                    const id = try self.insertEntity(field.type, relation);

                                    try relation_ids.put(field.name, id);

                                    switch (@typeInfo(rfield.type)) {
                                        .int => {
                                            @field(relation, rfield.name) = id;
                                        },
                                        else => unreachable,
                                    }
                                } else {}
                                break;
                            }
                        }
                    }
                }
            }

            const table_name = if (@hasDecl(T, "table_name"))
                T.table_name
            else
                unreachable;

            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            var columns = std.ArrayList(u8){};
            defer columns.deinit(self.allocator);

            var placeholders = std.ArrayList(u8){};
            defer placeholders.deinit(self.allocator);

            var param_index: usize = 1;
            var first = true;

            var pk_column_name: []const u8 = undefined;
            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                const column_name = utils.get_column_name(T, field.name);

                if (is_pk) {
                    pk_column_name = column_name;
                    continue;
                }

                const is_relation = comptime utils.is_relation(field.type);

                if (!first) {
                    try columns.appendSlice(self.allocator, ", ");
                    try placeholders.appendSlice(self.allocator, ", ");
                }

                if (is_relation) {
                    try columns.print(self.allocator, "{s}_id", .{column_name});
                } else {
                    try columns.appendSlice(self.allocator, column_name);
                }

                try placeholders.print(self.allocator, "${d}", .{param_index});
                param_index += 1;
                first = false;
            }

            try sql.print(self.allocator, "INSERT INTO {s} ({s}) VALUES ({s}) RETURNING {s}", .{ table_name, columns.items, placeholders.items, pk_column_name });

            var stmt = try self.conn.prepare(sql.items);
            errdefer stmt.deinit();

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;

                if (is_pk) {
                    continue;
                }

                try self.bindRelationOrValue(T, field, entity, &stmt, &relation_ids);
            }

            var result = try stmt.execute();
            defer result.deinit();

            const id = if (try result.next()) |row|
                row.get(i32, 0)
            else
                return error.InsertFailed;

            while (try result.next()) |_| {}

            return id;
        }

        fn updateEntity(self: *Self, comptime T: type, entity: *T) !void {
            const struct_info = @typeInfo(T).@"struct";

            var relation_ids = std.StringHashMap(i32).init(self.allocator);
            defer relation_ids.deinit();

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;

                const is_relation = comptime utils.is_relation(field.type);
                if (is_relation) {
                    var relation = &@field(entity, field.name);
                    const relation_info = @typeInfo(field.type).@"struct";

                    inline for (relation_info.fields) |rfield| {
                        if (utils.get_field_meta(field.type, rfield.name)) |rmeta| {
                            if (rmeta.is_primary_key) {
                                const value = @field(relation, rfield.name);
                                if (utils.is_falsy(rfield.type, value)) {
                                    const id = try self.insertEntity(field.type, relation);

                                    try relation_ids.put(field.name, id);
                                    switch (@typeInfo(rfield.type)) {
                                        .int => {
                                            @field(relation, rfield.name) = id;
                                        },
                                        else => unreachable,
                                    }
                                } else {}
                                // TODO: Handle updating existing relations?
                                break;
                            }
                        }
                    }
                }
            }

            const table_name = if (@hasDecl(T, "table_name"))
                T.table_name
            else
                unreachable;

            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.print(self.allocator, "UPDATE {s} SET ", .{table_name});

            var param_index: usize = 1;
            var first = true;

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;

                if (is_pk) {
                    continue;
                }

                const column_name = utils.get_column_name(T, field.name);
                const is_relation = comptime utils.is_relation(field.type);

                if (is_relation) {
                    if (!first) try sql.appendSlice(self.allocator, ", ");
                    try sql.print(self.allocator, "{s}_id = ${d}", .{ column_name, param_index });
                    param_index += 1;
                    first = false;
                } else {
                    if (!first) try sql.appendSlice(self.allocator, ", ");
                    try sql.print(self.allocator, "{s} = ${d}", .{ column_name, param_index });
                    param_index += 1;
                    first = false;
                }
            }

            var pk_column_name: []const u8 = undefined;
            inline for (struct_info.fields) |field| {
                if (utils.get_field_meta(T, field.name)) |meta| {
                    if (meta.is_primary_key) {
                        pk_column_name = utils.get_column_name(T, field.name);
                        break;
                    }
                }
            }

            try sql.print(self.allocator, " WHERE {s} = ${d}", .{ pk_column_name, param_index });

            var stmt = try self.conn.prepare(sql.items);
            errdefer stmt.deinit();

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;

                if (is_pk) {
                    continue;
                }

                try self.bindRelationOrValue(T, field, entity, &stmt, &relation_ids);
            }

            inline for (struct_info.fields) |field| {
                if (utils.get_field_meta(T, field.name)) |meta| {
                    if (meta.is_primary_key) {
                        try stmt.bind(@field(entity, field.name));
                        break;
                    }
                }
            }

            var result = try stmt.execute();
            defer result.deinit();

            while (try result.next()) |_| {}
        }

        fn deleteEntity(self: *Self, entity: *const Model) !void {
            const struct_info = @typeInfo(Model).@"struct";
            
            const table_name = if (@hasDecl(Model, "table_name"))
                Model.table_name
            else
                unreachable;

            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            var pk_column_name: []const u8 = undefined;
            var pk_found = false;
            
            inline for (struct_info.fields) |field| {
                if (utils.get_field_meta(Model, field.name)) |meta| {
                    if (meta.is_primary_key) {
                        pk_column_name = utils.get_column_name(Model, field.name);
                        pk_found = true;
                        break;
                    }
                }
            }

            if (!pk_found) {
                return error.NoPrimaryKeyFound;
            }

            try sql.print(self.allocator, "DELETE FROM {s} WHERE {s} = $1", .{ table_name, pk_column_name });

            var stmt = try self.conn.prepare(sql.items);
            errdefer stmt.deinit();

            inline for (struct_info.fields) |field| {
                if (utils.get_field_meta(Model, field.name)) |meta| {
                    if (meta.is_primary_key) {
                        try stmt.bind(@field(entity, field.name));
                        break;
                    }
                }
            }

            var result = try stmt.execute();
            defer result.deinit();

            while (try result.next()) |_| {}
        }
    };
}
