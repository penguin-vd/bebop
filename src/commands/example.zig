const std = @import("std");

pub const command = "example";

pub fn run(allocator: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    // First 2 arguments are not needed:
    // - arg 0: program name
    // - arg 1: command
    if (args.len <= 2) {
        std.debug.print("No arguments given\n", .{});
        return;
    }
    
    for (args[2..], 0..) |arg, i| {
        std.debug.print("Argument {d}: {s}\n", .{i, arg});
    }
}
