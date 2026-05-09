const std = @import("std");
const bebop = @import("bebop");

test "rollback and re-apply migrations" {
    const allocator = std.testing.allocator;
    const pool = bebop.testing.pool();

    // Rollback should succeed even when there's nothing to roll back
    try bebop.orm.rollback(allocator, std.testing.io, pool);

    // Re-apply should bring us back to a working state
    try bebop.orm.migrate(allocator, std.testing.io, pool);
}
