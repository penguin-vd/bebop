const std = @import("std");

pub fn get_table_name(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    const input = @typeName(Model);
    const result = try allocator.alloc(u8, input.len);
    for (input, 0..) |char, i| {
        if (char == '.') {
            result[i] = '_';
        } else {
            result[i] = std.ascii.toLower(char);
        }
    }

    return result;
}

pub fn FieldMeta(comptime T: type) type {
    _ = T;
    return struct {
        is_primary_key: bool = false,
        is_unique: bool = false,
        is_auto_increment: bool = false,
        max_length: ?usize = null,
        column_name: ?[]const u8 = null,
        default_value: ?[]const u8 = null,
    };
}

pub fn get_field_meta(comptime Model: type, comptime field_name: []const u8) ?FieldMeta(void) {
    if (!@hasDecl(Model, "field_meta")) {
        return null;
    }

    const meta_decl = @field(Model, "field_meta");
    const meta_type_info = @typeInfo(@TypeOf(meta_decl));

    if (meta_type_info != .@"struct") {
        return null;
    }

    inline for (meta_type_info.@"struct".fields) |meta_field| {
        if (std.mem.eql(u8, meta_field.name, field_name)) {
            return @field(meta_decl, field_name);
        }
    }

    return null;
}

pub fn get_field_list(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    var fields = std.ArrayList(u8){};
    defer fields.deinit(allocator);

    const type_info = @typeInfo(Model);
    const struct_info = type_info.@"struct";

    var first = true;
    inline for (struct_info.fields) |field| {
        const sql_type = to_sql_type(field.type);

        if (!std.mem.eql(u8, sql_type, "SKIP")) {
            if (!first) {
                try fields.appendSlice(allocator, ", ");
            }
            first = false;

            if (std.mem.eql(u8, sql_type, "BELONGS_TO")) {
                try fields.print(allocator, "{s}_id", .{field.name});
            } else {
                const meta = get_field_meta(Model, field.name);
                const column_name = if (meta) |m| m.column_name orelse field.name else field.name;
                try fields.appendSlice(allocator, column_name);
            }
        }
    }

    return fields.toOwnedSlice(allocator);
}

pub fn is_relation(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => true,
        .optional => |opt| is_relation(opt.child),
        .pointer => |p| p.size == .slice and @typeInfo(p.child) == .@"struct",
        else => false,
    };
}

pub fn to_sql_type(comptime T: type) []const u8 {
    const info = @typeInfo(T);
    return switch (info) {
        .int => |int_info| {
            if (int_info.bits <= 32) return "INTEGER";
            return "BIGINT";
        },
        .float => "REAL",
        .bool => "BOOLEAN",
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                if (@typeInfo(ptr_info.child) == .@"struct") {
                    return "SKIP"; // This is a hasMany relation
                }
                if (ptr_info.child == u8) {
                    return "TEXT";
                }
            }
            return "BLOB";
        },
        .optional => |opt_info| to_sql_type(opt_info.child),
        .@"struct" => "BELONGS_TO",
        else => "TEXT",
    };
}

pub fn should_skip_field(comptime Model: type, comptime field_name: []const u8) bool {
    const meta = comptime get_field_meta(Model, field_name);
    return if (meta) |m| m.is_auto_increment else false;
}

pub fn get_column_name(comptime Model: type, comptime field_name: []const u8) []const u8 {
    const meta = comptime get_field_meta(Model, field_name);
    return if (meta) |m| m.column_name orelse field_name else field_name;
}

pub fn QueryFilter(comptime Model: type) type {
    const struct_info = @typeInfo(Model).@"struct";

    comptime var field_count: usize = 0;
    inline for (struct_info.fields) |field| {
        field_count += 1;

        switch (@typeInfo(field.type)) {
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    field_count += 3;
                }
            },
            .int, .float => {
                field_count += 4;
            },
            .optional => |opt_info| {
                switch (@typeInfo(opt_info.child)) {
                    .pointer => |ptr_info| {
                        if (ptr_info.size == .slice and ptr_info.child == u8) {
                            field_count += 3;
                        }
                    },
                    .int, .float => {
                        field_count += 4;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    comptime var filter_fields: [field_count]std.builtin.Type.StructField = undefined;
    comptime var idx: usize = 0;

    inline for (struct_info.fields) |field| {
        const base_type = switch (@typeInfo(field.type)) {
            .optional => |opt_info| opt_info.child,
            else => field.type,
        };

        filter_fields[idx] = .{
            .name = field.name,
            .type = ?field.type,
            .default_value_ptr = &@as(?field.type, null),
            .is_comptime = false,
            .alignment = @alignOf(?field.type),
        };
        idx += 1;

        switch (@typeInfo(base_type)) {
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    filter_fields[idx] = .{
                        .name = field.name ++ "__contains",
                        .type = ?[]const u8,
                        .default_value_ptr = &@as(?[]const u8, null),
                        .is_comptime = false,
                        .alignment = @alignOf(?[]const u8),
                    };
                    idx += 1;

                    filter_fields[idx] = .{
                        .name = field.name ++ "__startsWith",
                        .type = ?[]const u8,
                        .default_value_ptr = &@as(?[]const u8, null),
                        .is_comptime = false,
                        .alignment = @alignOf(?[]const u8),
                    };
                    idx += 1;

                    filter_fields[idx] = .{
                        .name = field.name ++ "__endsWith",
                        .type = ?[]const u8,
                        .default_value_ptr = &@as(?[]const u8, null),
                        .is_comptime = false,
                        .alignment = @alignOf(?[]const u8),
                    };
                    idx += 1;
                }
            },
            .int, .float => {
                const OptType = ?base_type;

                filter_fields[idx] = .{
                    .name = field.name ++ "__gt",
                    .type = OptType,
                    .default_value_ptr = &@as(OptType, null),
                    .is_comptime = false,
                    .alignment = @alignOf(OptType),
                };
                idx += 1;

                filter_fields[idx] = .{
                    .name = field.name ++ "__gte",
                    .type = OptType,
                    .default_value_ptr = &@as(OptType, null),
                    .is_comptime = false,
                    .alignment = @alignOf(OptType),
                };
                idx += 1;

                filter_fields[idx] = .{
                    .name = field.name ++ "__lt",
                    .type = OptType,
                    .default_value_ptr = &@as(OptType, null),
                    .is_comptime = false,
                    .alignment = @alignOf(OptType),
                };
                idx += 1;

                filter_fields[idx] = .{
                    .name = field.name ++ "__lte",
                    .type = OptType,
                    .default_value_ptr = &@as(OptType, null),
                    .is_comptime = false,
                    .alignment = @alignOf(OptType),
                };
                idx += 1;
            },
            else => {},
        }
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &filter_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}
