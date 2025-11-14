const utils = @import("../orm/utils.zig");
const Category = @import("category.zig");

id: i32,
name: []const u8,
category: Category,

pub const table_name = "products";

pub const field_meta = .{
    .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    .category = utils.FieldMeta(Category){},
};
