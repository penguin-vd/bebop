const std = @import("std");

var commands = std.ArrayList(struct { command: []const u8, run: *const fn (allocator: std.mem.Allocator) anyerror!void }){};

pub fn register(allocator: std.mem.Allocator, comptime Command: type) !void {
    if (!@hasDecl(Command, "command")) {
        @compileError("Missing command field on type " ++ @typeName(Command));
    }

    if (!@hasDecl(Command, "run")) {
        @compileError("Missing run function on type " ++ @typeName(Command));
    }

    try commands.append(allocator, .{ .command = Command.command, .run = Command.run });
}

pub fn deinit(allocator: std.mem.Allocator) void {
    commands.deinit(allocator);
}

pub fn handle(allocator: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return; // This means no arguments were given, and we run the server
    }

    const command = args[1];

    for (commands.items) |cmd| {
        if (std.mem.eql(u8, cmd.command, command)) {
            try cmd.run(allocator);
            std.process.exit(0);
        }
    }

    std.debug.print("Error: Unknown command '{s}'\n\n", .{command});
    printAvailableCommands();
    std.process.exit(1);
}

fn printAvailableCommands() void {
    if (commands.items.len == 0) {
        std.debug.print("No commands available\n", .{});
        return;
    }

    std.debug.print("Available commands:\n", .{});
    for (commands.items) |cmd| {
        std.debug.print("  - {s}\n", .{cmd.command});
    }
}
