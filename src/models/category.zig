const orm = @import("../lib/bebop.zig").orm;

id: i32,
name: []const u8,

pub const table_name = "categories";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .name = orm.FieldMeta([]const u8){ .max_length = 255 },
};
