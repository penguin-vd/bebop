const std = @import("std");
const utils = @import("utils.zig");
const ft = @import("fields.zig");
const pg = @import("pg");

pub fn QueryBuilder(comptime Model: type) type {
    return struct {
        const Self = @This();

        const ParsedField = struct {
            table_name: []const u8,
            column_name: []const u8,
            field_name: []const u8,
            relation_path: []const []const u8,
        };

        const WhereCondition = struct {
            table_name: []const u8,
            column: []const u8,
            operator: []const u8,
            value: []const u8,
            relation_path: []const []const u8,
        };

        const table_name = if (@hasDecl(Model, "table_name"))
            Model.table_name
        else
            unreachable;

        const all_fields = blk: {
            const count: usize = ft.count_total_fields(Model, null);
            var fields: [count]ft.FieldInfo = undefined;
            _ = ft.fill_field_info_slice(table_name, null, Model, null, &fields, 0, 0);
            break :blk fields;
        };

        const all_joins = blk: {
            const count: usize = ft.count_relations(Model, null);
            var joins: [count]ft.JoinInfo = undefined;
            _ = ft.fill_join_info(table_name, Model, null, &joins, 0, 0);
            break :blk joins;
        };

        allocator: std.mem.Allocator,
        select_columns: ?[]const ParsedField = null,
        where_conditions: std.ArrayList(WhereCondition),
        limit: usize = 0,
        page: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .where_conditions = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.select_columns) |columns| {
                for (columns) |col| {
                    self.allocator.free(col.relation_path);
                }
                self.allocator.free(columns);
            }
            for (self.where_conditions.items) |condition| {
                self.allocator.free(condition.column);
                self.allocator.free(condition.operator);
                self.allocator.free(condition.value);
                self.allocator.free(condition.relation_path);
            }
            self.where_conditions.deinit(self.allocator);
        }

        pub fn clear(self: *Self) void {
            if (self.select_columns) |columns| {
                for (columns) |col| {
                    self.allocator.free(col.relation_path);
                }
                self.allocator.free(columns);
                self.select_columns = null;
            }

            for (self.where_conditions.items) |condition| {
                self.allocator.free(condition.column);
                self.allocator.free(condition.operator);
                self.allocator.free(condition.value);
                self.allocator.free(condition.relation_path);
            }
            self.where_conditions.clearRetainingCapacity();

            self.limit = 0;
            self.page = 0;
        }

        pub fn select(self: *Self) void {
            if (self.select_columns) |columns| {
                self.allocator.free(columns);
            }
            self.select_columns = null;
        }

        fn getAliasedTableName(allocator: std.mem.Allocator, base_table: []const u8, relation_path: []const []const u8) ![]const u8 {
            if (relation_path.len == 0) {
                return base_table;
            }

            if (relation_path.len == 1) {
                return base_table;
            }

            var alias = std.ArrayList(u8){};
            defer alias.deinit(allocator);

            try alias.appendSlice(allocator, base_table);
            for (relation_path[1..]) |relation| {
                try alias.append(allocator, '_');
                try alias.appendSlice(allocator, relation);
            }

            return try alias.toOwnedSlice(allocator);
        }

        fn parseFieldNameRecursive(
            allocator: std.mem.Allocator,
            comptime CurrentType: type,
            field_str: []const u8,
            prefix_path: ?[]const []const u8,
        ) !ParsedField {
            if (std.mem.indexOf(u8, field_str, ".")) |dot_index| {
                const relation_name = field_str[0..dot_index];
                const remaining = field_str[dot_index + 1 ..];

                const current_fields = @typeInfo(CurrentType).@"struct".fields;
                inline for (current_fields) |field| {
                    if (std.mem.eql(u8, relation_name, field.name)) {
                        const FieldType = field.type;
                        const NextType = if (@typeInfo(FieldType) == .optional)
                            @typeInfo(FieldType).optional.child
                        else
                            FieldType;

                        switch (@typeInfo(NextType)) {
                            .@"struct" => {
                                const new_path_len = if (prefix_path) |p| p.len + 1 else 1;
                                var new_path = try allocator.alloc([]const u8, new_path_len);
                                errdefer allocator.free(new_path);

                                if (prefix_path) |p| {
                                    @memcpy(new_path[0..p.len], p);
                                    new_path[p.len] = relation_name;
                                    allocator.free(p);
                                } else {
                                    new_path[0] = relation_name;
                                }

                                return try parseFieldNameRecursive(allocator, NextType, remaining, new_path);
                            },
                            else => return error.InvalidRelationType,
                        }
                    }
                }
                return error.RelationNotFound;
            } else {
                const final_fields = @typeInfo(CurrentType).@"struct".fields;
                inline for (final_fields) |field| {
                    if (std.mem.eql(u8, field_str, field.name)) {
                        const column = utils.get_column_name(CurrentType, field.name);
                        const relation_path = if (prefix_path) |p| p else try allocator.alloc([]const u8, 0);
                        return ParsedField{
                            .table_name = CurrentType.table_name,
                            .column_name = column,
                            .field_name = field.name,
                            .relation_path = relation_path,
                        };
                    }
                }
                return error.InvalidFieldName;
            }
        }

        fn parseFieldName(allocator: std.mem.Allocator, field_str: []const u8) !ParsedField {
            return try parseFieldNameRecursive(allocator, Model, field_str, null);
        }

        pub fn selectFields(self: *Self, field_names: []const []const u8) !void {
            if (self.select_columns) |columns| {
                self.allocator.free(columns);
            }

            var parsed_fields = try std.ArrayList(ParsedField).initCapacity(self.allocator, field_names.len);
            errdefer parsed_fields.deinit(self.allocator);

            for (field_names) |field_str| {
                const parsed = try parseFieldName(self.allocator, field_str);
                try parsed_fields.append(self.allocator, parsed);
            }

            self.select_columns = try parsed_fields.toOwnedSlice(self.allocator);
        }

        pub fn where(self: *Self, field_name: []const u8, operator: []const u8, value: anytype) !void {
            const parsed = try parseFieldName(self.allocator, field_name);

            var value_str = std.ArrayList(u8){};
            defer value_str.deinit(self.allocator);

            const T = @TypeOf(value);
            switch (@typeInfo(T)) {
                .int, .comptime_int => {
                    try value_str.print(self.allocator, "{d}", .{value});
                },
                .float, .comptime_float => {
                    try value_str.print(self.allocator, "{d}", .{value});
                },
                .bool => {
                    try value_str.print(self.allocator, "{}", .{value});
                },
                .pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .slice => {
                            if (ptr_info.child == u8) {
                                try value_str.appendSlice(self.allocator, value);
                            } else {
                                @compileError("Unsupported slice type for WHERE value");
                            }
                        },
                        .one => {
                            if (ptr_info.child == u8) {
                                try value_str.appendSlice(self.allocator, value);
                            } else {
                                switch (@typeInfo(ptr_info.child)) {
                                    .array => |arr_info| {
                                        if (arr_info.child == u8) {
                                            try value_str.appendSlice(self.allocator, value);
                                        } else {
                                            @compileError("Unsupported array type for WHERE value");
                                        }
                                    },
                                    else => @compileError("Unsupported pointer type for WHERE value"),
                                }
                            }
                        },
                        else => @compileError("Unsupported pointer type for WHERE value"),
                    }
                },
                .optional => |opt_info| {
                    if (value) |v| {
                        switch (@typeInfo(opt_info.child)) {
                            .int => try value_str.print(self.allocator, "{d}", .{v}),
                            .float => try value_str.print(self.allocator, "{d}", .{v}),
                            .bool => try value_str.print(self.allocator, "{}", .{v}),
                            .pointer => try value_str.appendSlice(self.allocator, v),
                            else => @compileError("Unsupported optional type for WHERE value"),
                        }
                    } else {
                        try value_str.appendSlice(self.allocator, "NULL");
                    }
                },
                else => @compileError("Unsupported type for WHERE value: " ++ @typeName(T)),
            }

            try self.where_conditions.append(self.allocator, .{
                .table_name = parsed.table_name,
                .column = try self.allocator.dupe(u8, parsed.column_name),
                .operator = try self.allocator.dupe(u8, operator),
                .value = try value_str.toOwnedSlice(self.allocator),
                .relation_path = parsed.relation_path,
            });
        }

        pub fn whereILike(self: *Self, field_name: []const u8, value: []const u8) !void {
            const parsed = try parseFieldName(self.allocator, field_name);

            const wrapped_value = try std.fmt.allocPrint(self.allocator, "%{s}%", .{value});
            errdefer self.allocator.free(wrapped_value);

            try self.where_conditions.append(self.allocator, .{
                .table_name = parsed.table_name,
                .column = try self.allocator.dupe(u8, parsed.column_name),
                .operator = try self.allocator.dupe(u8, "ILIKE"),
                .value = wrapped_value,
                .relation_path = parsed.relation_path,
            });
        }

        pub fn whereStartsWith(self: *Self, field_name: []const u8, value: []const u8) !void {
            const parsed = try parseFieldName(self.allocator, field_name);

            const wrapped_value = try std.fmt.allocPrint(self.allocator, "{s}%", .{value});
            errdefer self.allocator.free(wrapped_value);

            try self.where_conditions.append(self.allocator, .{
                .table_name = parsed.table_name,
                .column = try self.allocator.dupe(u8, parsed.column_name),
                .operator = try self.allocator.dupe(u8, "ILIKE"),
                .value = wrapped_value,
                .relation_path = parsed.relation_path,
            });
        }

        pub fn whereEndsWith(self: *Self, field_name: []const u8, value: []const u8) !void {
            const parsed = try parseFieldName(self.allocator, field_name);

            const wrapped_value = try std.fmt.allocPrint(self.allocator, "%{s}", .{value});
            errdefer self.allocator.free(wrapped_value);

            try self.where_conditions.append(self.allocator, .{
                .table_name = parsed.table_name,
                .column = try self.allocator.dupe(u8, parsed.column_name),
                .operator = try self.allocator.dupe(u8, "ILIKE"),
                .value = wrapped_value,
                .relation_path = parsed.relation_path,
            });
        }

        fn isRelationInUse(self: *Self, join_table_name: []const u8) bool {
            if (self.select_columns == null) {
                return true;
            }

            for (self.select_columns.?) |parsed_field| {
                if (std.mem.eql(u8, parsed_field.table_name, join_table_name)) {
                    return true;
                }
            }

            for (self.where_conditions.items) |cond| {
                if (std.mem.eql(u8, cond.table_name, join_table_name)) {
                    return true;
                }
            }

            return false;
        }

        pub fn toSql(self: *Self) !struct { sql: []u8, params: []const []const u8 } {
            var sql = std.ArrayList(u8){};
            errdefer sql.deinit(self.allocator);

            var params = std.ArrayList([]const u8){};
            errdefer params.deinit(self.allocator);

            try sql.print(self.allocator, "SELECT ", .{});

            if (self.select_columns) |columns| {
                for (columns, 0..) |parsed_field, i| {
                    if (i > 0) try sql.print(self.allocator, ", ", .{});

                    const table_alias = try getAliasedTableName(self.allocator, parsed_field.table_name, parsed_field.relation_path);
                    const needs_free = parsed_field.relation_path.len > 1;

                    try sql.print(self.allocator, "{s}.{s}", .{ table_alias, parsed_field.column_name });

                    if (needs_free) {
                        self.allocator.free(table_alias);
                    }
                }
            } else {
                inline for (all_fields, 0..) |field_info, i| {
                    if (i > 0) try sql.print(self.allocator, ", ", .{});
                    const table_to_use = if (field_info.table_alias) |alias| alias else field_info.table_name;
                    try sql.print(self.allocator, "{s}.{s}", .{ table_to_use, field_info.column_name });
                }
            }

            try sql.print(self.allocator, " FROM {s}", .{table_name});

            inline for (all_joins) |join| {
                if (self.isRelationInUse(join.table_name)) {
                    const join_keyword = switch (join.join_type) {
                        .left => "LEFT JOIN",
                        .inner => "INNER JOIN",
                    };

                    if (join.alias) |alias| {
                        try sql.print(self.allocator, " {s} {s} AS {s} ON {s}.{s} = {s}.{s}", .{
                            join_keyword,
                            join.table_name,
                            alias,
                            join.foreign_table,
                            join.foreign_key,
                            alias,
                            join.primary_key,
                        });
                    } else {
                        try sql.print(self.allocator, " {s} {s} ON {s}.{s} = {s}.{s}", .{
                            join_keyword,
                            join.table_name,
                            join.foreign_table,
                            join.foreign_key,
                            join.table_name,
                            join.primary_key,
                        });
                    }
                }
            }

            if (self.where_conditions.items.len > 0) {
                try sql.print(self.allocator, " WHERE ", .{});
                for (self.where_conditions.items, 0..) |condition, i| {
                    if (i > 0) try sql.print(self.allocator, " AND ", .{});

                    const table_alias = try getAliasedTableName(self.allocator, condition.table_name, condition.relation_path);
                    const needs_free = condition.relation_path.len > 1;

                    try sql.print(self.allocator, "{s}.{s} {s} ${d}", .{
                        table_alias,
                        condition.column,
                        condition.operator,
                        params.items.len + 1,
                    });

                    const param_copy = try self.allocator.dupe(u8, condition.value);
                    try params.append(self.allocator, param_copy);

                    if (needs_free) {
                        self.allocator.free(table_alias);
                    }
                }
            }

            if (self.limit > 0) {
                try sql.print(self.allocator, " LIMIT {d}", .{self.limit});
                try sql.print(self.allocator, " OFFSET {d}", .{self.page * self.limit});
            }

            return .{
                .sql = try sql.toOwnedSlice(self.allocator),
                .params = try params.toOwnedSlice(self.allocator),
            };
        }

        fn getFieldValue(allocator: std.mem.Allocator, comptime T: type, row: pg.Row, index: usize) !T {
            return switch (@typeInfo(T)) {
                .int, .float, .bool => {
                    if (row.get(?T, index)) |result| {
                        return result;
                    }
                    return error.FoundNullValue;
                },
                .pointer => |ptr_info| blk: {
                    if (ptr_info.size == .slice and ptr_info.child == u8) {
                        const str = row.get([]const u8, index);
                        break :blk try allocator.dupe(u8, str);
                    }
                    @compileError("Unsupported pointer type: " ++ @typeName(T));
                },
                .optional => |opt_info| blk: {
                    if (row.get(T, index)) |_| {
                        break :blk try getFieldValue(allocator, opt_info.child, row, index);
                    }
                    break :blk null;
                },
                else => @compileError("Unsupported field type: " ++ @typeName(T)),
            };
        }

        fn getAllColumnNames(comptime T: type) []const []const u8 {
            const struct_info = @typeInfo(T).@"struct";

            comptime var count: usize = 0;
            inline for (struct_info.fields) |field| {
                if (!utils.is_relation(field.type)) {
                    count += 1;
                }
            }

            comptime var columns: [count][]const u8 = undefined;
            comptime var idx: usize = 0;
            inline for (struct_info.fields) |field| {
                if (!utils.is_relation(field.type)) {
                    columns[idx] = utils.get_column_name(T, field.name);
                    idx += 1;
                }
            }

            return &columns;
        }

        fn prepare(self: *Self, conn: *pg.Conn) !*pg.Result {
            const query = try self.toSql();
            defer self.allocator.free(query.sql);
            defer {
                for (query.params) |param| {
                    self.allocator.free(param);
                }
                self.allocator.free(query.params);
            }

            var stmt = try conn.prepare(query.sql);
            errdefer stmt.deinit();

            for (query.params) |param| {
                try stmt.bind(param);
            }

            return try stmt.execute();
        }

        pub fn execute(self: *Self, conn: *pg.Conn, comptime ResultType: type) ![]ResultType {
            var result = try self.prepare(conn);
            defer result.deinit();

            const pk = utils.get_primary_key_info(Model);

            var results = std.AutoHashMap(pk.type, ResultType).init(self.allocator);
            errdefer {
                var iter = results.valueIterator();
                while (iter.next()) |item| {
                    self.freeModel(ResultType, item.*);
                }
                results.deinit();
            }

            while (try result.next()) |row| {
                const model = try self.parseRow(row, ResultType);
                if (results.get(@field(model, pk.name))) |old| {
                    const merged = try self.mergeModels(ResultType, old, model);
                    try results.put(@field(model, pk.name), merged);
                } else {
                    try results.put(@field(model, pk.name), model);
                }
            }

            var list = std.ArrayList(ResultType){};
            var iter = results.valueIterator();
            while (iter.next()) |item| {
                try list.append(self.allocator, item.*);
            }

            return list.toOwnedSlice(self.allocator);
        }

        fn parseRow(self: *Self, row: anytype, comptime ResultType: type) !ResultType {
            var model = std.mem.zeroes(ResultType);

            if (self.select_columns) |selected| {
                var col_index: usize = 0;

                for (selected) |parsed_field| {
                    if (parsed_field.relation_path.len == 0) {
                        inline for (@typeInfo(ResultType).@"struct".fields) |field| {
                            if (std.mem.eql(u8, field.name, parsed_field.field_name)) {
                                if (comptime utils.is_one_relation(field.type)) {
                                    @field(model, field.name) = try parseOneRelationField(self.allocator, field.type, Model, row, &col_index);
                                } else if (comptime utils.is_many_relation(field.type)) {
                                    @field(model, field.name) = try parseManyRelationField(self.allocator, field.type, Model, row, &col_index);
                                } else {
                                    @field(model, field.name) = try getFieldValue(self.allocator, field.type, row, col_index);
                                    col_index += 1;
                                }
                                break;
                            }
                        }
                    }
                }
            } else {
                var col_index: usize = 0;
                inline for (@typeInfo(ResultType).@"struct".fields) |field| {
                    if (comptime utils.is_one_relation(field.type)) {
                        @field(model, field.name) = try parseOneRelationField(self.allocator, field.type, Model, row, &col_index);
                    } else if (comptime utils.is_many_relation(field.type)) {
                        @field(model, field.name) = try parseManyRelationField(self.allocator, field.type, Model, row, &col_index);
                    } else {
                        @field(model, field.name) = try getFieldValue(self.allocator, field.type, row, col_index);
                        col_index += 1;
                    }
                }
            }

            return model;
        }

        fn parseOneRelationField(allocator: std.mem.Allocator, comptime RelationType: type, comptime Parent: ?type, row: anytype, col_index: *usize) !RelationType {
            var relation_model: RelationType = std.mem.zeroes(RelationType);

            if (Parent) |p| {
                if (RelationType == p) {
                    return relation_model;
                }
            }

            inline for (@typeInfo(RelationType).@"struct".fields) |field| {
                if (comptime utils.is_one_relation(field.type)) {
                    @field(relation_model, field.name) = try parseOneRelationField(allocator, field.type, Parent, row, col_index);
                } else if (comptime utils.is_many_relation(field.type)) {
                    @field(relation_model, field.name) = try parseManyRelationField(allocator, field.type, Parent, row, col_index);
                } else {
                    @field(relation_model, field.name) = try getFieldValue(allocator, field.type, row, col_index.*);
                    col_index.* += 1;
                }
            }

            return relation_model;
        }

        fn parseManyRelationField(allocator: std.mem.Allocator, comptime RelationType: type, comptime Parent: ?type, row: anytype, col_index: *usize) !RelationType {
            const ChildType = @typeInfo(RelationType).pointer.child;
            var array = std.ArrayList(ChildType){};

            const model = parseOneRelationField(allocator, ChildType, Parent, row, col_index) catch |err| switch (err) {
                error.FoundNullValue => return try array.toOwnedSlice(allocator),
                else => return err,
            };

            try array.append(allocator, model);

            return try array.toOwnedSlice(allocator);
        }

        fn freeModel(self: *Self, comptime ResultType: type, model: ResultType) void {
            if (self.select_columns) |selected| {
                for (selected) |parsed_field| {
                    if (parsed_field.relation_path.len == 0) {
                        inline for (@typeInfo(ResultType).@"struct".fields) |field| {
                            if (std.mem.eql(u8, field.name, parsed_field.field_name)) {
                                switch (@typeInfo(field.type)) {
                                    .pointer => self.allocator.free(@field(model, field.name)),
                                    .optional => |opt_info| {
                                        if (@field(model, field.name)) |val| {
                                            if (@typeInfo(opt_info.child) == .pointer) {
                                                self.allocator.free(val);
                                            }
                                        }
                                    },
                                    else => {},
                                }
                                break;
                            }
                        }
                    }
                }
            } else {
                inline for (@typeInfo(ResultType).@"struct".fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .pointer => {
                            self.allocator.free(@field(model, field.name));
                        },
                        .optional => |opt_info| {
                            if (@field(model, field.name)) |val| {
                                if (@typeInfo(opt_info.child) == .pointer) {
                                    self.allocator.free(val);
                                }
                            }
                        },
                        else => {},
                    }
                }
            }
        }

        fn mergeModels(self: *Self, comptime Type: type, old: Type, new: Type) std.mem.Allocator.Error!Type {
            var result = new;

            inline for (@typeInfo(Type).@"struct".fields) |field| {
                if (comptime utils.is_one_relation(field.type)) {
                    @field(result, field.name) = try self.mergeModels(
                        field.type,
                        @field(old, field.name),
                        @field(new, field.name),
                    );
                } else if (comptime utils.is_many_relation(field.type)) {
                    const ChildType = @typeInfo(field.type).pointer.child;
                    const child_pk = utils.get_primary_key_info(ChildType);

                    const old_slice = @field(old, field.name);
                    const new_slice = @field(new, field.name);

                    var map = std.AutoHashMap(child_pk.type, ChildType).init(self.allocator);
                    defer map.deinit();

                    for (old_slice) |item| {
                        try map.put(@field(item, child_pk.name), item);
                    }

                    for (new_slice) |item| {
                        const key = @field(item, child_pk.name);
                        if (map.get(key)) |existing| {
                            const merged = try self.mergeModels(ChildType, existing, item);
                            try map.put(key, merged);
                        } else {
                            try map.put(key, item);
                        }
                    }

                    var list = std.ArrayList(ChildType){};
                    var iter = map.valueIterator();
                    while (iter.next()) |item| {
                        try list.append(self.allocator, item.*);
                    }

                    self.allocator.free(old_slice);
                    self.allocator.free(new_slice);

                    @field(result, field.name) = try list.toOwnedSlice(self.allocator);
                }
            }

            return result;
        }
    };
}
