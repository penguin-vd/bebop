const orm = @import("bebop").orm;
const OrderLine = @import("order_line.zig");

id: i32 = 0,
reference: []const u8,
order_lines: []OrderLine,
customer: []const u8 = "Unknown",

pub const table_name = "orders";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .reference = orm.FieldMeta([]const u8){ .max_length = 255 },
    .order_lines = orm.FieldMeta([]OrderLine){},
    .customer = orm.FieldMeta([]const u8){ .max_length = 255, .default_value = "Unknown" },
};
