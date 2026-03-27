const std = @import("std");
const http = @import("../../http.zig");

pub fn DebugRouter(comptime Handler: type, comptime Action: type, comptime registerFn: anytype) type {
    return struct {
        pub const command = "debug:router";

        pub fn run(allocator: std.mem.Allocator) !void {
            var router = http.Router(Handler, Action).recording(allocator);
            defer router.deinit();

            try registerFn(&router);

            router.printRoutes();
        }
    };
}
