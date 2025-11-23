const App = @import("../app.zig");

const std = @import("std");
const httpz = @import("httpz");
const bebop = @import("../lib/bebop.zig");

const Product = @import("../models/product.zig");
const Category = @import("../models/category.zig");

const Router = @import("../routes.zig").Router;

pub fn register(router: *Router) void {
    var group = router.group("/api/products", .{});

    group.get("/", list, .{});
    group.post("/", create, .{});
    group.get("/:id", get, .{});
    group.post("/:id", update, .{});
    group.delete("/:id", delete, .{});
}

fn list(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
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

    const products = try em.find(&qb);
    defer res.arena.free(products);

    try res.json(products, .{});
}

fn create(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    var category_em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer category_em.deinit();

    var qb = em.query();
    defer qb.deinit();

    const body = req.json(struct {
        name: []const u8,
        category: i32,
    }) catch null;

    if (body) |dto| {
        const found_category = try category_em.get(dto.category);

        if (found_category) |category| {
            const product = try em.create(.{
                .name = dto.name,
                .category = category.*,
            });
            try em.flush();

            try res.json(product, .{});
            return;
        }

        res.setStatus(.not_found);
        try res.json(.{ .message = "Category not found" }, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn get(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |product| {
        try res.json(product, .{});
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Product not found" }, .{});
}

fn update(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    var category_em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer category_em.deinit();

    const body = req.json(struct {
        name: ?[]const u8 = null,
        category: ?i32 = null,
    }) catch null;

    if (body) |dto| {
        const found = try em.get(req.param("id"));
        if (found) |product| {
            if (dto.name) |name| {
                product.name = name;
            }

            if (dto.category) |category_id| {
                const found_category = try category_em.get(category_id);

                if (found_category) |category| {
                    product.category = category.*;
                } else {
                    res.setStatus(.not_found);
                    try res.json(.{ .message = "Category not found" }, .{});
                    return;
                }
            }

            try em.flush();

            try res.json(product, .{});
            return;
        }

        res.setStatus(.not_found);
        try res.json(.{ .message = "Product not found" }, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn delete(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |product| {
        try em.remove(product);

        try em.flush();

        res.setStatus(.no_content);
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Product not found" }, .{});
}
