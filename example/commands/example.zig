const std = @import("std");

pub const command = "example";

pub fn run(allocator: std.mem.Allocator, args: []const []const u8, io: std.Io) !void {
    _ = allocator;
    _ = args;
    _ = io;
    std.debug.print("Example command ran\n", .{});
}
