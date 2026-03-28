const std = @import("std");
const bebop = @import("bebop");
const httpz = bebop.httpz;

const Category = @import("../models/category.zig");

const Group = @import("../routes.zig").Group;

pub fn register(group: *Group) void {
    group.get("/", list);
    group.post("/", create);
    group.get("/:id", get);
    group.post("/:id", update);
    group.delete("/:id", delete);
}

fn list(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer em.deinit();

    var query_params = try req.query();
    defer query_params.deinit(req.arena);

    var qb = em.query();
    defer qb.deinit();

    qb.limit = 10;

    if (query_params.get("page")) |page| {
        qb.page = std.fmt.parseInt(usize, page, 10) catch {
            res.setStatus(.bad_request);
            try res.json(.{ .message = "Page needs to be a signed integer" }, .{});
            return;
        };
    }

    if (query_params.get("limit")) |limit| {
        qb.limit = std.fmt.parseInt(usize, limit, 10) catch {
            res.setStatus(.bad_request);
            try res.json(.{ .message = "Limit needs to be a signed integer" }, .{});
            return;
        };
    }

    const categories = try em.find(&qb);
    defer em.freeModels(categories);

    try res.json(categories, .{});
}

fn create(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer em.deinit();

    const body = req.json(struct {
        name: []const u8,
    }) catch null;

    if (body) |dto| {
        const category = try em.create(.{
            .name = dto.name,
        });
        try em.flush();

        try res.json(category, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn get(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |category| {
        defer em.freeModel(category);
        try res.json(category, .{});
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Category not found" }, .{});
}

fn update(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer em.deinit();

    const body = req.json(struct {
        name: ?[]const u8 = null,
    }) catch null;

    if (body) |dto| {
        const found = try em.get(req.param("id"));
        if (found) |category| {
            defer em.freeModel(category);

            if (dto.name) |name| {
                category.name = name;
            }

            try em.flush();

            try res.json(category, .{});
            return;
        }

        res.setStatus(.not_found);
        try res.json(.{ .message = "Category not found" }, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn delete(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |category| {
        defer em.freeModel(category);
        try em.remove(category);
        try em.flush();

        res.setStatus(.no_content);
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Category not found" }, .{});
}
