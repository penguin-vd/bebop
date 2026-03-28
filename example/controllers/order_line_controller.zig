const std = @import("std");
const bebop = @import("bebop");
const httpz = bebop.httpz;

const OrderLine = @import("../models/order_line.zig");
const Order = @import("../models/order.zig");
const Product = @import("../models/product.zig");

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

    var em = bebop.orm.EntityManager(OrderLine).init(res.arena, conn);
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

    const order_lines = try em.find(&qb);
    defer em.freeModels(order_lines);

    try res.json(order_lines, .{});
}

fn create(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(OrderLine).init(res.arena, conn);
    defer em.deinit();

    var order_em = bebop.orm.EntityManager(Order).init(res.arena, conn);
    defer order_em.deinit();

    var product_em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer product_em.deinit();

    const body = req.json(struct {
        quantity: i32,
        order_id: i32,
        product_id: i32,
    }) catch null;

    if (body) |dto| {
        const found_order = try order_em.get(dto.order_id);
        if (found_order == null) {
            res.setStatus(.not_found);
            try res.json(.{ .message = "Order not found" }, .{});
            return;
        }

        const found_product = try product_em.get(dto.product_id);
        if (found_product == null) {
            res.setStatus(.not_found);
            try res.json(.{ .message = "Product not found" }, .{});
            return;
        }

        const order_line = try em.create(.{
            .quantity = dto.quantity,
            .order = found_order.?.*,
            .product = found_product.?.*,
        });
        try em.flush();

        try res.json(order_line, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn get(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(OrderLine).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |order_line| {
        defer em.freeModel(order_line);
        try res.json(order_line, .{});
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Order line not found" }, .{});
}

fn update(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(OrderLine).init(res.arena, conn);
    defer em.deinit();

    var product_em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer product_em.deinit();

    const body = req.json(struct {
        quantity: ?i32 = null,
        product_id: ?i32 = null,
    }) catch null;

    if (body) |dto| {
        const found = try em.get(req.param("id"));
        if (found) |order_line| {
            defer em.freeModel(order_line);

            if (dto.quantity) |quantity| {
                order_line.quantity = quantity;
            }

            if (dto.product_id) |product_id| {
                const found_product = try product_em.get(product_id);

                if (found_product) |product| {
                    order_line.product = product.*;
                } else {
                    res.setStatus(.not_found);
                    try res.json(.{ .message = "Product not found" }, .{});
                    return;
                }
            }

            try em.flush();

            try res.json(order_line, .{});
            return;
        }

        res.setStatus(.not_found);
        try res.json(.{ .message = "Order line not found" }, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn delete(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(OrderLine).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |order_line| {
        defer em.freeModel(order_line);
        try em.remove(order_line);
        try em.flush();

        res.setStatus(.no_content);
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Order line not found" }, .{});
}
