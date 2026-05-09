const std = @import("std");
const bebop = @import("bebop");

const routes = @import("routes.zig");
const commands = @import("commands/cmd.zig");

pub fn main(init: std.process.Init) !void {
    try bebop.start(init, .{
        .port = 8080,
        .address = "0.0.0.0",
    }, routes.register, commands.register);
}
