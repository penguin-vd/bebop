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

    inline for (struct_info.fields, 0..) |field, i| {
        const meta = get_field_meta(Model, field.name);
        const column_name = if (meta) |m| m.column_name orelse field.name else field.name;

        try fields.appendSlice(allocator, column_name);

        if (i < struct_info.fields.len - 1) {
            try fields.appendSlice(allocator, ", ");
        }
    }

    return fields.toOwnedSlice(allocator);
}

pub fn should_skip_field(comptime Model: type, comptime field_name: []const u8) bool {
    const meta = comptime get_field_meta(Model, field_name);
    return if (meta) |m| m.is_auto_increment else false;
}

pub fn get_column_name(comptime Model: type, comptime field_name: []const u8) []const u8 {
    const meta = comptime get_field_meta(Model, field_name);
    return if (meta) |m| m.column_name orelse field_name else field_name;
}
