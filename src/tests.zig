comptime {
    _ = @import("orm/tests/query_builder.zig");
    _ = @import("orm/tests/query_builder_recursive.zig");
    _ = @import("orm/tests/query_builder_m2m.zig");
    _ = @import("orm/tests/query_builder_where.zig");
    _ = @import("orm/tests/queries_create_table.zig");
    _ = @import("orm/tests/queries_alter_table.zig");
    _ = @import("orm/tests/queries_pivot_table.zig");
    _ = @import("orm/tests/queries_indexes.zig");
}
