const std = @import("std");
const bebop = @import("bebop");
const httpz = bebop.httpz;

const Order = @import("../models/order.zig");
const OrderLine = @import("../models/order_line.zig");
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

    var em = bebop.orm.EntityManager(Order).init(res.arena, conn);
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

    const orders = try em.find(&qb);
    defer em.freeModels(orders);

    try res.json(orders, .{});
}

fn create(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Order).init(res.arena, conn);
    defer em.deinit();

    var product_em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer product_em.deinit();

    const body = req.json(struct {
        reference: []const u8,
        order_lines: []const struct {
            quantity: i32,
            product_id: i32,
        },
    }) catch null;

    if (body) |dto| {
        var lines = try res.arena.alloc(OrderLine, dto.order_lines.len);

        for (dto.order_lines, 0..) |line_dto, i| {
            const found_product = try product_em.get(line_dto.product_id);

            if (found_product) |product| {
                lines[i] = .{
                    .quantity = line_dto.quantity,
                    .order = std.mem.zeroes(Order),
                    .product = product.*,
                };
            } else {
                res.setStatus(.not_found);
                try res.json(.{ .message = "Product not found" }, .{});
                return;
            }
        }

        const order = try em.create(.{
            .reference = dto.reference,
            .order_lines = lines,
        });
        try em.flush();

        try res.json(order, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn get(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Order).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |order| {
        defer em.freeModel(order);
        try res.json(order, .{});
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Order not found" }, .{});
}

fn update(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Order).init(res.arena, conn);
    defer em.deinit();

    var product_em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer product_em.deinit();

    const body = req.json(struct {
        reference: ?[]const u8 = null,
        order_lines: ?[]const struct {
            id: i32 = 0,
            quantity: i32,
            product_id: i32,
        } = null,
    }) catch null;

    if (body) |dto| {
        const found = try em.get(req.param("id"));
        if (found) |order| {
            defer em.freeModel(order);

            if (dto.reference) |reference| {
                order.reference = reference;
            }

            if (dto.order_lines) |line_dtos| {
                var lines = try res.arena.alloc(OrderLine, line_dtos.len);

                for (line_dtos, 0..) |line_dto, i| {
                    const found_product = try product_em.get(line_dto.product_id);

                    if (found_product) |product| {
                        lines[i] = .{
                            .id = line_dto.id,
                            .quantity = line_dto.quantity,
                            .order = order.*,
                            .product = product.*,
                        };
                    } else {
                        res.setStatus(.not_found);
                        try res.json(.{ .message = "Product not found" }, .{});
                        return;
                    }
                }

                order.order_lines = lines;
            }

            try em.flush();

            try res.json(order, .{});
            return;
        }

        res.setStatus(.not_found);
        try res.json(.{ .message = "Order not found" }, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

fn delete(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Order).init(res.arena, conn);
    defer em.deinit();

    const found = try em.get(req.param("id"));

    if (found) |order| {
        defer em.freeModel(order);

        var line_em = bebop.orm.EntityManager(OrderLine).init(res.arena, conn);
        defer line_em.deinit();

        var line_qb = line_em.query();
        defer line_qb.deinit();
        try line_qb.where("order", "=", order.id);

        const order_lines = try line_em.find(&line_qb);
        defer line_em.freeModels(order_lines);

        for (order_lines) |line| {
            try line_em.remove(line);
        }
        try line_em.flush();

        try em.remove(order);
        try em.flush();

        res.setStatus(.no_content);
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Order not found" }, .{});
}
