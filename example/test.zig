const std = @import("std");
const bebop = @import("bebop");

test "tests:beforeAll" {
    bebop.testing.setup();
}

test "tests:beforeEach" {
    try bebop.testing.clear();
}

comptime {
    _ = @import("tests/category.zig");
    _ = @import("tests/product.zig");
    _ = @import("tests/order.zig");
}
