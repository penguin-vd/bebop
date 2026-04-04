const orm = @import("bebop").orm;
const Category = @import("category.zig");

id: i32 = 0,
name: []const u8,
categories: []Category,

pub const table_name = "products";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .name = orm.FieldMeta([]const u8){ .max_length = 255 },
    .categories = orm.FieldMeta([]Category){ .many_to_many = true },
};

pub const indexes = &[_]orm.Index{
    .{ .fields = &.{"name"} },
};
