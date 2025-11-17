const std = @import("std");
const bebop = @import("../lib/bebop.zig");

const CreateMigrations = @import("migrations/create.zig");
const ApplyMigrations = @import("migrations/apply.zig");
const Example = @import("example.zig");

pub fn handle(allocator: std.mem.Allocator) !void {
    defer bebop.cmd.deinit(allocator);

    try bebop.cmd.register(allocator, CreateMigrations);
    try bebop.cmd.register(allocator, ApplyMigrations);
    try bebop.cmd.register(allocator, Example);
    try bebop.cmd.handle(allocator);
}
