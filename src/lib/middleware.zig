const std = @import("std");
const httpz = @import("httpz");
const jwt = @import("jwt.zig");

pub fn auth(allocator: std.mem.Allocator, req: *httpz.Request, res: *httpz.Response, secret: []const u8) !jwt.Claims {
    const header = req.header("authorization") orelse {
        res.status = 401;
        try res.json(.{ .message = "Unauthorized" }, .{});
        return error.Unauthorized;
    };

    if (!std.mem.startsWith(u8, header, "Bearer ")) {
        res.status = 401;
        try res.json(.{ .message = "Unauthorized" }, .{});
        return error.Unauthorized;
    }

    const token = header["Bearer ".len..];
    return jwt.verify(allocator, token, secret) catch {
        res.status = 401;
        try res.json(.{ .message = "Unauthorized" }, .{});
        return error.Unauthorized;
    };
}
