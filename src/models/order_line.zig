const Order = @import("order.zig");
const Product = @import("product.zig");
const orm = @import("../lib/bebop.zig").orm;

id: i32 = 0,
quantity: i32,
order: Order,
product: Product,

pub const table_name = "order_lines";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .quantity = orm.FieldMeta(i32){},
    .order = orm.FieldMeta(Order){},
    .product = orm.FieldMeta(Product){},
};
