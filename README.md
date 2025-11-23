# Bebop

*A Symfony-inspired web framework and ORM for Zig 0.15.1.*

Bebop is a high-performance, type-safe web framework and Object-Relational Mapper (ORM) for the Zig programming language. It is designed to be fast, modern, and developer-friendly, drawing inspiration from the robust architecture of the Symfony framework.

## Features

*   **Modern ORM:** A powerful ORM with an expressive query builder.
*   **Database Migrations:** A simple and effective migration system for PostgreSQL.
*   **Declarative Routing:** A flexible routing system to map requests to controllers.
*   **Comptime Powered:** Leverages Zig's `comptime` for reflection and code generation, eliminating runtime overhead.
*   **CLI Tools:** Command-line interface for common tasks like database migrations.

## Getting Started

### Installation

For now this is only possible in this repository, later this will supported using it like an library.

## Usage

### Defining an Entity

Entities are regular Zig structs. You define your data schema and relationships in one place. A `field_meta` constant provides the ORM with metadata about the fields.

*src/models/product.zig*
```zig
const orm = @import("../lib/bebop.zig").orm;
const Category = @import("category.zig").Category;

id: i32 = 0,
name: []const u8,
category: Category,

pub const table_name = "products";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .name = orm.FieldMeta([]const u8){ .max_length = 255 },
    .category = orm.FieldMeta(Category){},
};
```

### Using the Entity Manager

The `EntityManager` is your primary tool for interacting with the database. Use it in your controllers to handle all CRUD (Create, Read, Update, Delete) operations.

*src/controllers/product_controller.zig*
```zig
const Product = @import("../models/product.zig");
const bebop = @import("../lib/bebop.zig");

// ...

fn get(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
    defer em.deinit();

    // The 'get' function finds an entity by its primary key
    const found = try em.get(req.param("id"));
    defer em.freeModel(found);

    if (found) |product| {
        try res.json(product, .{});
        return;
    }

    res.setStatus(.not_found);
    try res.json(.{ .message = "Product not found" }, .{});
}
```

### Querying for Objects

Bebop includes a powerful query builder that allows you to construct complex queries with ease, including pagination and filtering.

```zig
var em = bebop.orm.EntityManager(Product).init(res.arena, conn);
defer em.deinit();

var qb = em.query();
defer qb.deinit();

// Add conditions to the query
try qb.where("name", "ILIKE", "%gadget%");
qb.limit = 10;
qb.page = 1; // For pagination (LIMIT 10 OFFSET 10)

// Find all products matching the query
const products = try em.find(&qb);
defer res.arena.free(products);

// Use the results
try res.json(products, .{});
```

## Migrations

Bebop provides CLI commands to manage your database schema migrations, making it easy to version your database alongside your code.

### 1. Create a Migration

Generate a new, timestamped SQL migration file.

```sh
zig build run -- migrations:create
```

This command will create a file like `migrations/1763156804_your_model.sql`.

### 2. Apply Migrations

To apply all pending migrations to the database, run the following command:

```sh
zig build run -- migrations:apply
```
