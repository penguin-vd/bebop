const utils = @import("../../utils.zig");

const Order = @import("order.zig");

id: i32 = 0,
quantity: i32,
order: Order,

pub const table_name = "order_lines";

pub const field_meta = .{
    .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .quantity = utils.FieldMeta(i32){},
    .order = utils.FieldMeta(Order){},
};
