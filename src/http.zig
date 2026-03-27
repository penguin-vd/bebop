const std = @import("std");
const httpz = @import("httpz");

const RouteRecorder = struct {
    allocator: std.mem.Allocator,
    routes: std.ArrayList(Entry),

    const Entry = struct { method: []const u8, path: []const u8 };

    fn init(allocator: std.mem.Allocator) RouteRecorder {
        return .{ .allocator = allocator, .routes = std.ArrayList(Entry){} };
    }

    fn deinit(self: *RouteRecorder) void {
        for (self.routes.items) |e| self.allocator.free(e.path);
        self.routes.deinit(self.allocator);
    }

    fn record(self: *RouteRecorder, method: []const u8, prefix: []const u8, path: []const u8) void {
        const full = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, path }) catch return;
        self.routes.append(self.allocator, .{ .method = method, .path = full }) catch {
            self.allocator.free(full);
        };
    }

    fn print(self: *const RouteRecorder) void {
        std.debug.print("\nRegistered routes:\n\n", .{});
        for (self.routes.items) |e| {
            std.debug.print("  {s:<8} {s}\n", .{ e.method, e.path });
        }
        std.debug.print("\n", .{});
    }
};

pub fn Group(comptime Handler: type, comptime Action: type) type {
    const HttpzGroup = httpz.routing.Group(Handler, Action);

    return struct {
        httpz_group: ?HttpzGroup,
        recorder: ?*RouteRecorder,
        prefix: []const u8,

        const Self = @This();

        pub fn get(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |r| r.record("GET", self.prefix, path);
            if (self.httpz_group) |*g| g.get(path, action, .{});
        }

        pub fn post(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |r| r.record("POST", self.prefix, path);
            if (self.httpz_group) |*g| g.post(path, action, .{});
        }

        pub fn put(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |r| r.record("PUT", self.prefix, path);
            if (self.httpz_group) |*g| g.put(path, action, .{});
        }

        pub fn patch(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |r| r.record("PATCH", self.prefix, path);
            if (self.httpz_group) |*g| g.patch(path, action, .{});
        }

        pub fn delete(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |r| r.record("DELETE", self.prefix, path);
            if (self.httpz_group) |*g| g.delete(path, action, .{});
        }
    };
}

pub fn Router(comptime Handler: type, comptime Action: type) type {
    const HttpzRouter = httpz.Router(Handler, Action);

    return struct {
        httpz_router: ?*HttpzRouter,
        recorder: ?RouteRecorder,

        const Self = @This();

        pub fn from(httpz_router: *HttpzRouter) Self {
            return .{ .httpz_router = httpz_router, .recorder = null };
        }

        pub fn recording(allocator: std.mem.Allocator) Self {
            return .{ .httpz_router = null, .recorder = RouteRecorder.init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            if (self.recorder) |*r| r.deinit();
        }

        pub fn get(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |*r| r.record("GET", "", path);
            if (self.httpz_router) |router| router.get(path, action, .{});
        }

        pub fn post(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |*r| r.record("POST", "", path);
            if (self.httpz_router) |router| router.post(path, action, .{});
        }

        pub fn put(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |*r| r.record("PUT", "", path);
            if (self.httpz_router) |router| router.put(path, action, .{});
        }

        pub fn patch(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |*r| r.record("PATCH", "", path);
            if (self.httpz_router) |router| router.patch(path, action, .{});
        }

        pub fn delete(self: *Self, path: []const u8, action: Action) void {
            if (self.recorder) |*r| r.record("DELETE", "", path);
            if (self.httpz_router) |router| router.delete(path, action, .{});
        }

        pub fn group(self: *Self, prefix: []const u8) Group(Handler, Action) {
            const httpz_group = if (self.httpz_router) |r| r.group(prefix, .{}) else null;
            return .{
                .httpz_group = httpz_group,
                .recorder = if (self.recorder) |*r| r else null,
                .prefix = prefix,
            };
        }

        pub fn printRoutes(self: *const Self) void {
            if (self.recorder) |*r| r.print();
        }
    };
}
