const std = @import("std");
const pg = @import("pg");

const QueryBuilder = @import("query_builder.zig").QueryBuilder;
const utils = @import("utils.zig");

pub fn EntityManager(comptime Model: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        conn: *pg.Conn,

        tracked_entities: std.AutoHashMap(i32, EntityEntry),

        const EntityEntry = struct {
            entity: *Model,
            state: EntityState,
        };

        const EntityState = enum {
            new,
            managed,
            deleted,
        };

        pub fn init(allocator: std.mem.Allocator, conn: *pg.Conn) Self {
            return .{
                .allocator = allocator,
                .conn = conn,
                .tracked_entities = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.tracked_entities.valueIterator();
            while (it.next()) |entry| {
                self.allocator.destroy(entry.entity);
            }
            self.tracked_entities.deinit();
        }

        fn getPrimaryKey(entity: *const Model) i32 {
            const struct_info = @typeInfo(Model).@"struct";
            inline for (struct_info.fields) |field| {
                if (utils.get_field_meta(Model, field.name)) |meta| {
                    if (meta.is_primary_key) {
                        switch (@typeInfo(field.type)) {
                            .int => {
                                return @field(entity, field.name);
                            },
                            else => unreachable,
                        }
                        break;
                    }
                }
            }
            unreachable;
        }

        pub fn query(self: *Self) QueryBuilder(Model) {
            return QueryBuilder(Model).init(self.allocator);
        }

        pub fn find(self: *Self, qb: *QueryBuilder(Model)) ![]*Model {
            const results = try qb.execute(self.conn, Model);
            defer self.allocator.free(results);

            var result_ptrs = try self.allocator.alloc(*Model, results.len);

            for (results, 0..) |result, i| {
                const pk = blk: {
                    const struct_info = @typeInfo(Model).@"struct";
                    inline for (struct_info.fields) |field| {
                        if (utils.get_field_meta(Model, field.name)) |meta| {
                            if (meta.is_primary_key) {
                                switch (@typeInfo(field.type)) {
                                    .int => {
                                        break :blk @field(result, field.name);
                                    },
                                    else => unreachable,
                                }
                            }
                        }
                    }
                    unreachable;
                };

                if (self.tracked_entities.get(pk)) |existing| {
                    existing.entity.* = result;
                    result_ptrs[i] = existing.entity;
                } else {
                    const entity_ptr = try self.allocator.create(Model);
                    entity_ptr.* = result;
                    result_ptrs[i] = entity_ptr;

                    try self.tracked_entities.put(pk, .{
                        .entity = entity_ptr,
                        .state = .managed,
                    });
                }
            }

            return result_ptrs;
        }

        pub fn freeModels(self: *Self, models: []*Model) void {
            for (models) |model| {
                self.freeModel(model);
            }
            self.allocator.free(models);
        }

        pub fn freeModel(self: *Self, model: *Model) void {
            const struct_info = @typeInfo(Model).@"struct";
            inline for (struct_info.fields) |field| {
                self.freeField(field.type, @field(model, field.name));
            }
        }

        fn freeField(self: *Self, comptime T: type, value: T) void {
            return switch (@typeInfo(T)) {
                .pointer => |ptr_info| {
                    if (ptr_info.size == .slice) {
                        if (ptr_info.child == u8) {
                            if (@intFromPtr(value.ptr) != 0) {
                                self.allocator.free(value);
                            }
                        } else if (comptime utils.is_model(ptr_info.child)) {
                            if (@intFromPtr(value.ptr) != 0) {
                                for (value) |item| self.freeField(ptr_info.child, item);
                                self.allocator.free(value);
                            }
                        }
                    }
                },
                .@"struct" => |struct_info| {
                    inline for (struct_info.fields) |field| {
                        self.freeField(field.type, @field(value, field.name));
                    }
                },
                else => {},
            };
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
            defer self.allocator.free(models);

            if (models.len == 0) {
                return null;
            }

            if (models.len > 1) {
                self.freeModels(models);
                return error.GotMoreThenOneResult;
            }
            return models[0];
        }

        pub fn create(self: *Self, entity: Model) !*Model {
            const entity_ptr = try self.allocator.create(Model);
            entity_ptr.* = entity;

            const temp_key = @as(i32, @intCast(self.tracked_entities.count())) * -1 - 1;
            try self.tracked_entities.put(temp_key, .{
                .entity = entity_ptr,
                .state = .new,
            });
            return entity_ptr;
        }

        pub fn remove(self: *Self, entity: *Model) !void {
            const pk = Self.getPrimaryKey(entity);
            if (self.tracked_entities.getPtr(pk)) |entry| {
                entry.state = .deleted;
            }
        }

        pub fn clear(self: *Self) void {
            self.tracked_entities.clearRetainingCapacity();
        }

        pub fn flush(self: *Self) !void {
            try self.conn.begin();
            errdefer self.conn.rollback() catch {};

            var it = self.tracked_entities.iterator();

            var keys_to_remove = std.ArrayList(i32){};
            defer keys_to_remove.deinit(self.allocator);

            var keys_to_update = std.ArrayList(struct { old: i32, new: i32 }){};
            defer keys_to_update.deinit(self.allocator);

            while (it.next()) |entry| {
                const old_key = entry.key_ptr.*;
                const entity_entry = entry.value_ptr;

                switch (entity_entry.state) {
                    .new => {
                        const id = try self.insertEntity(Model, entity_entry.entity);
                        const struct_info = @typeInfo(Model).@"struct";

                        inline for (struct_info.fields) |field| {
                            const meta = comptime utils.get_field_meta(Model, field.name);
                            const is_pk = if (meta) |m| m.is_primary_key else false;
                            if (is_pk) {
                                switch (@typeInfo(field.type)) {
                                    .int => {
                                        @field(entity_entry.entity, field.name) = id;
                                    },
                                    else => unreachable,
                                }
                                break;
                            }
                        }

                        try keys_to_update.append(self.allocator, .{ .old = old_key, .new = id });
                        entity_entry.state = .managed;
                    },
                    .managed => {
                        try self.updateEntity(Model, entity_entry.entity);
                    },
                    .deleted => {
                        try self.deleteEntity(entity_entry.entity);
                        try keys_to_remove.append(self.allocator, old_key);
                        self.allocator.destroy(entity_entry.entity);
                    },
                }
            }

            for (keys_to_update.items) |update| {
                if (self.tracked_entities.fetchRemove(update.old)) |kv| {
                    try self.tracked_entities.put(update.new, kv.value);
                }
            }

            for (keys_to_remove.items) |key| {
                _ = self.tracked_entities.remove(key);
            }

            try self.conn.commit();
        }

        fn findBackReferenceField(comptime ChildType: type, comptime ParentType: type) []const u8 {
            const child_fields = @typeInfo(ChildType).@"struct".fields;
            inline for (child_fields) |field| {
                if (comptime utils.is_one_relation(field.type)) {
                    const base = switch (@typeInfo(field.type)) {
                        .optional => |opt| opt.child,
                        else => field.type,
                    };
                    if (base == ParentType) return field.name;
                }
            }
            @compileError("No back-reference field found in " ++ @typeName(ChildType) ++ " pointing to " ++ @typeName(ParentType));
        }

        fn getRelationPk(comptime FieldType: type, field_value: FieldType) i32 {
            const BaseType = comptime switch (@typeInfo(FieldType)) {
                .optional => |opt| opt.child,
                else => FieldType,
            };
            const pk_info = comptime utils.get_primary_key_info(BaseType);
            return switch (@typeInfo(FieldType)) {
                .optional => if (field_value) |v| @field(v, pk_info.name) else 0,
                else => @field(field_value, pk_info.name),
            };
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
            const is_relation = comptime utils.is_one_relation(field.type);

            if (is_relation) {
                if (relation_ids.get(field.name)) |id| {
                    try stmt.bind(id);
                } else {
                    const pk = getRelationPk(field.type, @field(entity, field.name));
                    try stmt.bind(pk);
                }
            } else {
                try stmt.bind(@field(entity, field.name));
            }
        }

        fn insertEntity(self: *Self, comptime T: type, entity: *T) anyerror!i32 {
            const struct_info = @typeInfo(T).@"struct";

            // First pass: insert any one-relations that need inserting
            var relation_ids = std.StringHashMap(i32).init(self.allocator);
            defer relation_ids.deinit();

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;

                const is_relation = comptime utils.is_one_relation(field.type);
                if (is_relation) {
                    const BaseType = comptime switch (@typeInfo(field.type)) {
                        .optional => |opt| opt.child,
                        else => field.type,
                    };
                    const pk_info = comptime utils.get_primary_key_info(BaseType);
                    const relation = &@field(entity, field.name);
                    const pk_val = getRelationPk(field.type, relation.*);
                    if (utils.is_falsy(pk_info.type, pk_val)) {
                        const id = try self.insertEntity(BaseType, switch (@typeInfo(field.type)) {
                            .optional => &(relation.*.?),
                            else => relation,
                        });
                        try relation_ids.put(field.name, id);
                        switch (@typeInfo(field.type)) {
                            .optional => @field(relation.*.?, pk_info.name) = id,
                            else => @field(relation.*, pk_info.name) = id,
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

                const is_one_rel = comptime utils.is_one_relation(field.type);
                const is_many_rel = comptime utils.is_many_relation(field.type);

                if (is_many_rel) continue;

                if (!first) {
                    try columns.appendSlice(self.allocator, ", ");
                    try placeholders.appendSlice(self.allocator, ", ");
                }

                if (is_one_rel) {
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

                if (is_pk) continue;
                if (comptime utils.is_many_relation(field.type)) continue;

                try self.bindRelationOrValue(T, field, entity, &stmt, &relation_ids);
            }

            var result = try stmt.execute();
            defer result.deinit();

            const id = if (try result.next()) |row|
                row.get(i32, 0)
            else
                return error.InsertFailed;

            while (try result.next()) |_| {}

            // Post-insert: cascade many-relation children
            inline for (struct_info.fields) |field| {
                if (comptime utils.is_many_relation(field.type)) {
                    const ChildType = @typeInfo(field.type).pointer.child;
                    const child_pk = comptime utils.get_primary_key_info(ChildType);

                    if (comptime utils.is_many_to_many(T, field.name)) {
                        const pivot_table = comptime utils.get_pivot_table_name(
                            T.table_name,
                            ChildType.table_name,
                        );
                        const owner_fk = comptime T.table_name ++ "_id";
                        const related_fk = comptime ChildType.table_name ++ "_id";
                        const pivot_sql = comptime "INSERT INTO " ++ pivot_table ++ " (" ++ owner_fk ++ ", " ++ related_fk ++ ") VALUES ($1, $2)";

                        for (@field(entity, field.name)) |*child| {
                            var child_id = @field(child.*, child_pk.name);
                            if (utils.is_falsy(child_pk.type, child_id)) {
                                child_id = try self.insertEntity(ChildType, child);
                                @field(child.*, child_pk.name) = child_id;
                            }

                            var pivot_stmt = try self.conn.prepare(pivot_sql);
                            errdefer pivot_stmt.deinit();
                            try pivot_stmt.bind(id);
                            try pivot_stmt.bind(child_id);
                            var pivot_result = try pivot_stmt.execute();
                            defer pivot_result.deinit();
                            while (try pivot_result.next()) |_| {}
                        }
                    } else {
                        const back_ref = comptime findBackReferenceField(ChildType, T);
                        const parent_pk = comptime utils.get_primary_key_info(T);

                        for (@field(entity, field.name)) |*child| {
                            @field(@field(child.*, back_ref), parent_pk.name) = id;
                            const child_id = try self.insertEntity(ChildType, child);
                            @field(child.*, child_pk.name) = child_id;
                        }
                    }
                }
            }

            return id;
        }

        fn updateEntity(self: *Self, comptime T: type, entity: *T) anyerror!void {
            const struct_info = @typeInfo(T).@"struct";

            var relation_ids = std.StringHashMap(i32).init(self.allocator);
            defer relation_ids.deinit();

            // First pass: insert any new one-relations (id == 0)
            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;

                const is_relation = comptime utils.is_one_relation(field.type);
                if (is_relation) {
                    const BaseType = comptime switch (@typeInfo(field.type)) {
                        .optional => |opt| opt.child,
                        else => field.type,
                    };
                    const pk_info = comptime utils.get_primary_key_info(BaseType);
                    const relation = &@field(entity, field.name);
                    const pk_val = getRelationPk(field.type, relation.*);
                    if (utils.is_falsy(pk_info.type, pk_val)) {
                        const id = try self.insertEntity(BaseType, switch (@typeInfo(field.type)) {
                            .optional => &(relation.*.?),
                            else => relation,
                        });
                        try relation_ids.put(field.name, id);
                        switch (@typeInfo(field.type)) {
                            .optional => @field(relation.*.?, pk_info.name) = id,
                            else => @field(relation.*, pk_info.name) = id,
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

                if (is_pk) continue;

                const column_name = utils.get_column_name(T, field.name);
                const is_one_rel = comptime utils.is_one_relation(field.type);
                const is_many_rel = comptime utils.is_many_relation(field.type);

                if (is_many_rel) continue;

                if (!first) try sql.appendSlice(self.allocator, ", ");
                if (is_one_rel) {
                    try sql.print(self.allocator, "{s}_id = ${d}", .{ column_name, param_index });
                } else {
                    try sql.print(self.allocator, "{s} = ${d}", .{ column_name, param_index });
                }
                param_index += 1;
                first = false;
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

                if (is_pk) continue;
                if (comptime utils.is_many_relation(field.type)) continue;

                try self.bindRelationOrValue(T, field, entity, &stmt, &relation_ids);
            }

            const update_pk = comptime utils.get_primary_key_info(T);
            try stmt.bind(@field(entity.*, update_pk.name));

            var result = try stmt.execute();
            defer result.deinit();

            while (try result.next()) |_| {}

            // Post-update: cascade many-relation children (insert new, update existing)
            const parent_pk = comptime utils.get_primary_key_info(T);
            const parent_id = @field(entity.*, parent_pk.name);

            inline for (struct_info.fields) |field| {
                if (comptime utils.is_many_relation(field.type)) {
                    const ChildType = @typeInfo(field.type).pointer.child;
                    const child_pk = comptime utils.get_primary_key_info(ChildType);

                    if (comptime utils.is_many_to_many(T, field.name)) {
                        const pivot_table = comptime utils.get_pivot_table_name(
                            T.table_name,
                            ChildType.table_name,
                        );
                        const owner_fk = comptime T.table_name ++ "_id";
                        const related_fk = comptime ChildType.table_name ++ "_id";

                        // Delete existing pivot rows
                        const delete_sql = comptime "DELETE FROM " ++ pivot_table ++ " WHERE " ++ owner_fk ++ " = $1";
                        var delete_stmt = try self.conn.prepare(delete_sql);
                        errdefer delete_stmt.deinit();
                        try delete_stmt.bind(parent_id);
                        var delete_result = try delete_stmt.execute();
                        defer delete_result.deinit();
                        while (try delete_result.next()) |_| {}

                        // Re-insert pivot rows
                        const pivot_sql = comptime "INSERT INTO " ++ pivot_table ++ " (" ++ owner_fk ++ ", " ++ related_fk ++ ") VALUES ($1, $2)";
                        for (@field(entity, field.name)) |*child| {
                            var child_id = @field(child.*, child_pk.name);
                            if (utils.is_falsy(child_pk.type, child_id)) {
                                child_id = try self.insertEntity(ChildType, child);
                                @field(child.*, child_pk.name) = child_id;
                            }

                            var pivot_stmt = try self.conn.prepare(pivot_sql);
                            errdefer pivot_stmt.deinit();
                            try pivot_stmt.bind(parent_id);
                            try pivot_stmt.bind(child_id);
                            var pivot_result = try pivot_stmt.execute();
                            defer pivot_result.deinit();
                            while (try pivot_result.next()) |_| {}
                        }
                    } else {
                        const back_ref = comptime findBackReferenceField(ChildType, T);

                        for (@field(entity, field.name)) |*child| {
                            @field(@field(child.*, back_ref), parent_pk.name) = parent_id;
                            if (utils.is_falsy(child_pk.type, @field(child.*, child_pk.name))) {
                                const child_id = try self.insertEntity(ChildType, child);
                                @field(child.*, child_pk.name) = child_id;
                            } else {
                                try self.updateEntity(ChildType, child);
                            }
                        }
                    }
                }
            }
        }

        fn deleteEntity(self: *Self, entity: *const Model) !void {
            const table_name = if (@hasDecl(Model, "table_name"))
                Model.table_name
            else
                unreachable;

            const delete_pk = comptime utils.get_primary_key_info(Model);
            const pk_column_name = utils.get_column_name(Model, delete_pk.name);

            // Delete pivot table rows for M2M relations before deleting the entity
            const struct_info = @typeInfo(Model).@"struct";
            inline for (struct_info.fields) |field| {
                if (comptime utils.is_many_relation(field.type) and utils.is_many_to_many(Model, field.name)) {
                    const ChildType = @typeInfo(field.type).pointer.child;
                    const pivot_table = comptime utils.get_pivot_table_name(table_name, ChildType.table_name);
                    const owner_fk = comptime table_name ++ "_id";
                    const pivot_delete_sql = comptime "DELETE FROM " ++ pivot_table ++ " WHERE " ++ owner_fk ++ " = $1";

                    var pivot_stmt = try self.conn.prepare(pivot_delete_sql);
                    errdefer pivot_stmt.deinit();
                    try pivot_stmt.bind(@field(entity.*, delete_pk.name));
                    var pivot_result = try pivot_stmt.execute();
                    defer pivot_result.deinit();
                    while (try pivot_result.next()) |_| {}
                }
            }

            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.print(self.allocator, "DELETE FROM {s} WHERE {s} = $1", .{ table_name, pk_column_name });

            var stmt = try self.conn.prepare(sql.items);
            errdefer stmt.deinit();

            try stmt.bind(@field(entity.*, delete_pk.name));

            var result = try stmt.execute();
            defer result.deinit();

            while (try result.next()) |_| {}
        }
    };
}
