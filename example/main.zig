const bebop = @import("bebop");

const routes = @import("routes.zig");
const commands = @import("commands/cmd.zig");

pub fn main() !void {
    try bebop.start(.{
        .port = 8080,
        .address = "0.0.0.0",
    }, routes.register, commands.register);
}
