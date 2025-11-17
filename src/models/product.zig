const orm = @import("../lib/bebop.zig").orm;
const Category = @import("category.zig");

id: i32,
name: []const u8,
category: Category,

pub const table_name = "products";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .name = orm.FieldMeta([]const u8){ .max_length = 255 },
    .category = orm.FieldMeta(Category){},
};
