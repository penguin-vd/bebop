const std = @import("std");
const bebop = @import("bebop");
const httpz = bebop.httpz;

const Product = @import("../models/product.zig");
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
    defer em.freeModels(products);

    try res.json(products, .{});
}

fn create(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
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
        categories: []const i32,
    }) catch null;

    if (body) |dto| {
        var categories = try res.arena.alloc(Category, dto.categories.len);

        for (dto.categories, 0..) |category_id, i| {
            const found_category = try category_em.get(category_id);

            if (found_category) |category| {
                categories[i] = category.*;
            } else {
                res.setStatus(.not_found);
                try res.json(.{ .message = "Category not found" }, .{});
                return;
            }
        }

        const product = try em.create(.{
            .name = dto.name,
            .categories = categories,
        });
        try em.flush();

        try res.json(product, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn get(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |product| {
        defer em.freeModel(product);
        try res.json(product, .{});
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Product not found" }, .{});
}

fn update(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    var category_em = bebop.orm.EntityManager(Category).init(res.arena, conn);
    defer category_em.deinit();

    const body = req.json(struct {
        name: ?[]const u8 = null,
        categories: ?[]const i32 = null,
    }) catch null;

    if (body) |dto| {
        const found = try em.get(req.param("id"));
        if (found) |product| {
            defer em.freeModel(product);
            if (dto.name) |name| {
                product.name = name;
            }

            if (dto.categories) |category_ids| {
                var categories = try res.arena.alloc(Category, category_ids.len);

                for (category_ids, 0..) |category_id, i| {
                    const found_category = try category_em.get(category_id);

                    if (found_category) |category| {
                        categories[i] = category.*;
                    } else {
                        res.setStatus(.not_found);
                        try res.json(.{ .message = "Category not found" }, .{});
                        return;
                    }
                }

                product.categories = categories;
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

fn delete(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |product| {
        defer em.freeModel(product);
        try em.remove(product);

        try em.flush();

        res.setStatus(.no_content);
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Product not found" }, .{});
}
