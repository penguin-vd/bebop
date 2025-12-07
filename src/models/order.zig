const orm = @import("../lib/bebop.zig").orm;
const OrderLine = @import("order_line.zig");

id: i32 = 0,
reference: []const u8,
order_lines: []OrderLine,

pub const table_name = "orders";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .reference = orm.FieldMeta([]const u8){ .max_length = 255 },
    .order_lines = orm.FieldMeta([]OrderLine){},
};
