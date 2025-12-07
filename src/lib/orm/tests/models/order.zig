const utils = @import("../../utils.zig");
const OrderLine = @import("order_line.zig");

id: i32 = 0,
reference: []const u8,
order_lines: []OrderLine,

pub const table_name = "orders";

pub const field_meta = .{
    .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    .order_lines = utils.FieldMeta([]OrderLine){},
};
