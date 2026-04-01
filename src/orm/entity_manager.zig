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

        pub fn query(self: *Self) QueryBuilder(Model) {
            return QueryBuilder(Model).init(self.allocator);
        }

        pub fn find(self: *Self, qb: *QueryBuilder(Model)) ![]*Model {
            const pk_info = comptime utils.get_primary_key_info(Model);
            const results = try qb.execute(self.conn, Model);
            defer self.allocator.free(results);

            var result_ptrs = try self.allocator.alloc(*Model, results.len);

            for (results, 0..) |result, i| {
                const pk = @field(result, pk_info.name);

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

        pub fn get(self: *Self, value: anytype) !?*Model {
            var qb = self.query();
            defer qb.deinit();

            const pk_info = comptime utils.get_primary_key_info(Model);
            const pk_column_name = comptime utils.get_column_name(Model, pk_info.name);
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
            const pk = getPrimaryKey(entity);
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

            const pk_info = comptime utils.get_primary_key_info(Model);

            while (it.next()) |entry| {
                const old_key = entry.key_ptr.*;
                const entity_entry = entry.value_ptr;

                switch (entity_entry.state) {
                    .new => {
                        const id = try self.insertEntity(Model, entity_entry.entity);
                        @field(entity_entry.entity, pk_info.name) = id;

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

        fn insertEntity(self: *Self, comptime T: type, entity: *T) anyerror!i32 {
            const struct_info = @typeInfo(T).@"struct";
            const pk_info = comptime utils.get_primary_key_info(T);
            const pk_column_name = comptime utils.get_column_name(T, pk_info.name);
            const table_name = T.table_name;

            try self.resolveOneRelations(T, entity);

            // Build INSERT SQL
            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            var columns = std.ArrayList(u8){};
            defer columns.deinit(self.allocator);

            var placeholders = std.ArrayList(u8){};
            defer placeholders.deinit(self.allocator);

            var param_index: usize = 1;
            var first = true;

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;
                if (comptime utils.is_many_relation(field.type)) continue;

                const column_name = utils.get_column_name(T, field.name);

                if (!first) {
                    try columns.appendSlice(self.allocator, ", ");
                    try placeholders.appendSlice(self.allocator, ", ");
                }

                if (comptime utils.is_one_relation(field.type)) {
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

            bindEntityValues(T, entity, &stmt);

            var result = try stmt.execute();
            defer result.deinit();

            const id = if (try result.next()) |row|
                row.get(i32, 0)
            else
                return error.InsertFailed;

            while (try result.next()) |_| {}

            try self.cascadeManyRelations(T, entity, id);

            return id;
        }

        fn updateEntity(self: *Self, comptime T: type, entity: *T) anyerror!void {
            const struct_info = @typeInfo(T).@"struct";
            const pk_info = comptime utils.get_primary_key_info(T);
            const pk_column_name = comptime utils.get_column_name(T, pk_info.name);
            const table_name = T.table_name;

            try self.resolveOneRelations(T, entity);

            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.print(self.allocator, "UPDATE {s} SET ", .{table_name});

            var param_index: usize = 1;
            var first = true;

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;
                if (comptime utils.is_many_relation(field.type)) continue;

                const column_name = utils.get_column_name(T, field.name);

                if (!first) try sql.appendSlice(self.allocator, ", ");
                if (comptime utils.is_one_relation(field.type)) {
                    try sql.print(self.allocator, "{s}_id = ${d}", .{ column_name, param_index });
                } else {
                    try sql.print(self.allocator, "{s} = ${d}", .{ column_name, param_index });
                }
                param_index += 1;
                first = false;
            }

            try sql.print(self.allocator, " WHERE {s} = ${d}", .{ pk_column_name, param_index });

            var stmt = try self.conn.prepare(sql.items);
            errdefer stmt.deinit();

            bindEntityValues(T, entity, &stmt);
            try stmt.bind(@field(entity.*, pk_info.name));

            var result = try stmt.execute();
            defer result.deinit();

            while (try result.next()) |_| {}

            // Post-update: cascade many-relation children
            const parent_id = @field(entity.*, pk_info.name);

            inline for (struct_info.fields) |field| {
                if (comptime utils.is_many_relation(field.type)) {
                    const ChildType = @typeInfo(field.type).pointer.child;
                    const child_pk = comptime utils.get_primary_key_info(ChildType);

                    if (comptime utils.is_many_to_many(T, field.name)) {
                        const pivot_table = comptime utils.get_pivot_table_name(T.table_name, ChildType.table_name);
                        const owner_fk = comptime T.table_name ++ "_id";

                        // Delete existing pivot rows
                        const delete_sql = comptime "DELETE FROM " ++ pivot_table ++ " WHERE " ++ owner_fk ++ " = $1";
                        var delete_stmt = try self.conn.prepare(delete_sql);
                        errdefer delete_stmt.deinit();
                        try delete_stmt.bind(parent_id);
                        var delete_result = try delete_stmt.execute();
                        defer delete_result.deinit();
                        while (try delete_result.next()) |_| {}

                        // Bulk re-insert pivot rows
                        var child_ids = try self.collectChildIds(ChildType, @field(entity, field.name));
                        defer child_ids.deinit(self.allocator);

                        try self.bulkInsertPivotRows(T.table_name, ChildType.table_name, parent_id, child_ids.items);
                    } else {
                        // One-to-many: insert new children, update existing
                        const back_ref = comptime findBackReferenceField(ChildType, T);

                        for (@field(entity, field.name)) |*child| {
                            @field(@field(child.*, back_ref), pk_info.name) = parent_id;
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
            const table_name = Model.table_name;
            const delete_pk = comptime utils.get_primary_key_info(Model);
            const pk_column_name = comptime utils.get_column_name(Model, delete_pk.name);

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

        fn bulkInsertEntitiesOfType(self: *Self, comptime T: type, entities: []T) anyerror!void {
            if (entities.len == 0) return;

            const struct_info = @typeInfo(T).@"struct";
            const child_pk = comptime utils.get_primary_key_info(T);
            const pk_column_name = comptime utils.get_column_name(T, child_pk.name);
            const table_name = T.table_name;

            // Pre-resolve one-relations for each entity
            for (entities) |*entity| {
                try self.resolveOneRelations(T, entity);
            }

            // Count columns (excluding PK and many-relations)
            comptime var col_count: usize = 0;
            inline for (struct_info.fields) |fld| {
                const m = comptime utils.get_field_meta(T, fld.name);
                const is_pk = if (m) |mv| mv.is_primary_key else false;
                if (is_pk) continue;
                if (comptime utils.is_many_relation(fld.type)) continue;
                col_count += 1;
            }

            // Build column list
            var columns = std.ArrayList(u8){};
            defer columns.deinit(self.allocator);

            {
                var first = true;
                inline for (struct_info.fields) |field| {
                    const meta = comptime utils.get_field_meta(T, field.name);
                    const is_pk = if (meta) |m| m.is_primary_key else false;
                    if (is_pk) continue;
                    if (comptime utils.is_many_relation(field.type)) continue;

                    const column_name = utils.get_column_name(T, field.name);
                    if (!first) try columns.appendSlice(self.allocator, ", ");
                    if (comptime utils.is_one_relation(field.type)) {
                        try columns.print(self.allocator, "{s}_id", .{column_name});
                    } else {
                        try columns.appendSlice(self.allocator, column_name);
                    }
                    first = false;
                }
            }

            // Build full INSERT SQL with multiple VALUE rows
            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.print(self.allocator, "INSERT INTO {s} ({s}) VALUES ", .{ table_name, columns.items });

            var param_idx: usize = 1;
            for (0..entities.len) |i| {
                if (i > 0) try sql.appendSlice(self.allocator, ", ");
                try sql.appendSlice(self.allocator, "(");
                for (0..col_count) |j| {
                    if (j > 0) try sql.appendSlice(self.allocator, ", ");
                    try sql.print(self.allocator, "${d}", .{param_idx});
                    param_idx += 1;
                }
                try sql.appendSlice(self.allocator, ")");
            }

            try sql.print(self.allocator, " RETURNING {s}", .{pk_column_name});

            // Prepare, bind all values, execute
            var stmt = try self.conn.prepare(sql.items);
            errdefer stmt.deinit();

            for (entities) |*entity| {
                bindEntityValues(T, entity, &stmt);
            }

            var result = try stmt.execute();
            defer result.deinit();

            // Assign returned IDs to entities
            var idx: usize = 0;
            while (try result.next()) |row| : (idx += 1) {
                @field(entities[idx], child_pk.name) = row.get(i32, 0);
            }

            // Post-insert: cascade many-relations on children
            for (entities) |*entity| {
                const entity_id = @field(entity, child_pk.name);
                try self.cascadeManyRelations(T, entity, entity_id);
            }
        }

        fn bulkInsertPivotRows(
            self: *Self,
            comptime owner_table: []const u8,
            comptime related_table: []const u8,
            owner_id: i32,
            child_ids: []const i32,
        ) !void {
            if (child_ids.len == 0) return;

            const pivot_table = comptime utils.get_pivot_table_name(owner_table, related_table);
            const owner_fk = comptime owner_table ++ "_id";
            const related_fk = comptime related_table ++ "_id";

            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.appendSlice(self.allocator, "INSERT INTO " ++ pivot_table ++ " (" ++ owner_fk ++ ", " ++ related_fk ++ ") VALUES ");

            for (0..child_ids.len) |i| {
                if (i > 0) try sql.appendSlice(self.allocator, ", ");
                try sql.print(self.allocator, "(${d}, ${d})", .{ i * 2 + 1, i * 2 + 2 });
            }

            var stmt = try self.conn.prepare(sql.items);
            errdefer stmt.deinit();

            for (child_ids) |child_id| {
                try stmt.bind(owner_id);
                try stmt.bind(child_id);
            }

            var result = try stmt.execute();
            defer result.deinit();
            while (try result.next()) |_| {}
        }

        fn resolveOneRelations(self: *Self, comptime T: type, entity: *T) anyerror!void {
            const struct_info = @typeInfo(T).@"struct";

            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;
                if (comptime !utils.is_one_relation(field.type)) continue;

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
                    switch (@typeInfo(field.type)) {
                        .optional => @field(relation.*.?, pk_info.name) = id,
                        else => @field(relation.*, pk_info.name) = id,
                    }
                }
            }
        }

        fn collectChildIds(self: *Self, comptime ChildType: type, children: []ChildType) anyerror!std.ArrayList(i32) {
            const child_pk = comptime utils.get_primary_key_info(ChildType);
            var ids = std.ArrayList(i32){};

            for (children) |*child| {
                var child_id = @field(child.*, child_pk.name);
                if (utils.is_falsy(child_pk.type, child_id)) {
                    child_id = try self.insertEntity(ChildType, child);
                    @field(child.*, child_pk.name) = child_id;
                }
                try ids.append(self.allocator, child_id);
            }

            return ids;
        }

        fn cascadeManyRelations(self: *Self, comptime T: type, entity: *T, parent_id: i32) anyerror!void {
            const struct_info = @typeInfo(T).@"struct";

            inline for (struct_info.fields) |field| {
                if (comptime utils.is_many_relation(field.type)) {
                    const ChildType = @typeInfo(field.type).pointer.child;

                    if (comptime utils.is_many_to_many(T, field.name)) {
                        var child_ids = try self.collectChildIds(ChildType, @field(entity, field.name));
                        defer child_ids.deinit(self.allocator);

                        try self.bulkInsertPivotRows(T.table_name, ChildType.table_name, parent_id, child_ids.items);
                    } else {
                        const back_ref = comptime findBackReferenceField(ChildType, T);
                        const parent_pk_info = comptime utils.get_primary_key_info(T);

                        for (@field(entity, field.name)) |*child| {
                            @field(@field(child.*, back_ref), parent_pk_info.name) = parent_id;
                        }
                        try self.bulkInsertEntitiesOfType(ChildType, @field(entity, field.name));
                    }
                }
            }
        }

        fn bindEntityValues(comptime T: type, entity: anytype, stmt: *pg.Stmt) void {
            const struct_info = @typeInfo(T).@"struct";
            inline for (struct_info.fields) |field| {
                const meta = comptime utils.get_field_meta(T, field.name);
                const is_pk = if (meta) |m| m.is_primary_key else false;
                if (is_pk) continue;
                if (comptime utils.is_many_relation(field.type)) continue;

                if (comptime utils.is_one_relation(field.type)) {
                    stmt.bind(getRelationPk(field.type, @field(entity, field.name))) catch unreachable;
                } else {
                    stmt.bind(@field(entity, field.name)) catch unreachable;
                }
            }
        }

        fn getPrimaryKey(entity: *const Model) i32 {
            const pk_info = comptime utils.get_primary_key_info(Model);
            return @field(entity, pk_info.name);
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
    };
}
