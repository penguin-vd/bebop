const std = @import("std");

pub const command = "example";

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = allocator;
    _ = io;
    std.debug.print("Example command ran\n", .{});
}
