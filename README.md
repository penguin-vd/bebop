# Bebop

*A Symfony-inspired web framework and ORM for Zig 0.15.1.*

Bebop is a high-performance, type-safe web framework and Object-Relational Mapper (ORM) for the Zig programming language. It is designed to be fast, modern, and developer-friendly, drawing inspiration from the robust architecture of the Symfony framework.

## Features

- **Modern ORM:** A powerful ORM with an expressive query builder.
- **Database Migrations:** A simple and effective migration system for PostgreSQL.
- **Declarative Routing:** A flexible routing system to map requests to controllers with route recording.
- **Comptime Powered:** Leverages Zig's `comptime` for reflection and code generation, eliminating runtime overhead.
- **CLI Tools:** Command-line interface for common tasks like database migrations.
- **Testing Utilities:** Built-in helpers for testing controllers and database operations.

## Requirements

- Zig 0.15.1
- PostgreSQL 16+
- Docker and Docker Compose (optional, for development)

## Installation

Fetch the package:

```sh
zig fetch --save git+https://github.com/penguin-vd/bebop
```

Then add the module in your `build.zig`:

```zig
const bebop_module = b.dependency("bebop", .{
    .target = target,
    .optimize = optimize,
}).module("bebop");
```

## Quick Start

### Using Docker

1. Copy the environment file and adjust as needed:
   ```sh
   cp .env.example .env
   ```

2. Start the development environment:
   ```sh
   docker compose up --build
   ```

3. Create a migration:
   ```sh
   docker compose exec server zig build run -- migrations:create add_users_table
   ```

4. Apply migrations:
   ```sh
   docker compose exec server zig build run -- migrations:apply
   ```

### Running Locally

1. Ensure PostgreSQL is running and accessible.

2. Set environment variables:
   ```sh
   export POSTGRES_HOST=localhost
   export POSTGRES_USER=postgres
   export POSTGRES_PASSWORD=postgres
   export POSTGRES_DATABASE=bebop
   export POSTGRES_PORT=5432
   export POSTGRES_SSLMODE=disable
   ```

3. Run the server:
   ```sh
   zig build run
   ```

## Project Structure

```
bebop/
├── src/                    # Library source code
│   ├── app.zig           # Application context
│   ├── http.zig          # HTTP routing utilities
│   ├── server.zig        # Server setup
│   ├── testing.zig       # Testing utilities
│   ├── orm/              # ORM components
│   └── commands/         # CLI commands
├── example/              # Example application
│   ├── main.zig         # Entry point
│   ├── routes.zig       # Route definitions
│   ├── controllers/     # Request handlers
│   └── models/          # Data models
├── migrations/          # Database migrations
└── docker-compose.yml   # Development environment
```

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

## Built-in Types

Bebop ships with three ORM-aware types for common use cases. Import them from `bebop.orm`.

| Type | SQL type | Description |
|------|----------|-------------|
| `orm.Uuid` | `UUID` | RFC 4122 v4 UUID |
| `orm.DateTime` | `TIMESTAMPTZ` | Microsecond-precision timestamp with timezone |
| `orm.Date` | `DATE` | Calendar date (year, month, day) |

```zig
id: i32 = 0,
external_id: orm.Uuid = .{ .bytes = [_]u8{0} ** 16 },
created_at: orm.DateTime = .{ .micros = 0 },
expires_on: orm.Date = .{ .days = 0 },

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .external_id = orm.FieldMeta(orm.Uuid){},
    .created_at = orm.FieldMeta(orm.DateTime){},
    .expires_on = orm.FieldMeta(orm.Date){},
};
```

**Useful constructors:**

```zig
const id = orm.Uuid.new();                   // random UUID v4
const now = orm.DateTime.now();              // current time
const ts  = orm.DateTime.fromUnix(1_700_000_000); // from Unix seconds
const d   = orm.Date.fromYmd(2030, 12, 31); // from year/month/day
```

## Encrypted Fields

Fields can be transparently encrypted at rest using AES-256-GCM. The value is encrypted before being written to the database and decrypted when read back.

Only `[]const u8` and `?[]const u8` fields can be encrypted.

### 1. Generate an application key

```sh
zig build run -- key:generate
# APP_KEY=base64:...
```

Add the output to your `.env` file (or export it as an environment variable). The key is loaded from `APP_KEY` at runtime.

### 2. Mark the field as encrypted

```zig
token: []const u8,

pub const field_meta = .{
    .token = orm.FieldMeta([]const u8){ .is_encrypted = true, .max_length = 4096 },
};
```

Everything else — binding, fetching, decrypting — is handled automatically by the `EntityManager`.

## Lifecycle Hooks

Entities can declare hook methods that the `EntityManager` calls automatically at specific points in the entity's lifecycle. All hooks are optional; declare only the ones you need.

| Hook | Called |
|------|--------|
| `pre_persist` | Before `INSERT` |
| `post_persist` | After `INSERT` |
| `pre_update` | Before `UPDATE` |
| `post_update` | After `UPDATE` |
| `pre_remove` | Before `DELETE` |
| `post_remove` | After `DELETE` |
| `post_load` | After loading from the database |

All hooks have the signature `pub fn hook_name(self: *Self) !void`.

```zig
const Self = @This();

id: i32 = 0,
external_id: orm.Uuid = .{ .bytes = [_]u8{0} ** 16 },
created_at: orm.DateTime = .{ .micros = 0 },
updated_at: orm.DateTime = .{ .micros = 0 },

pub fn pre_persist(self: *Self) !void {
    self.external_id = orm.Uuid.new();
    self.created_at = orm.DateTime.now();
    self.updated_at = orm.DateTime.now();
}

pub fn pre_update(self: *Self) !void {
    self.updated_at = orm.DateTime.now();
}
```

## Custom Types

Any struct can be used as an ORM field type by implementing three declarations:

| Declaration | Description |
|-------------|-------------|
| `pub const sql_type: []const u8` | PostgreSQL column type (e.g. `"TEXT"`) |
| `pub fn to_sql_param(self: T, allocator: Allocator) ![]u8` | Serialize to a SQL string parameter |
| `pub fn from_sql_param(allocator: Allocator, s: []const u8) !T` | Deserialize from the raw bytes returned by the driver |

The ORM detects a custom type at `comptime` by checking for `sql_type` on the struct (and the absence of `table_name`, which would mark it as an entity).

**Example — a `Money` type stored as `NUMERIC`:**

```zig
const std = @import("std");

pub const Money = struct {
    cents: i64,

    pub const sql_type = "NUMERIC(12,2)";

    pub fn to_sql_param(self: Money, allocator: std.mem.Allocator) ![]u8 {
        const euros = @divTrunc(self.cents, 100);
        const frac  = @abs(@rem(self.cents, 100));
        return std.fmt.allocPrint(allocator, "{d}.{d:0>2}", .{ euros, frac });
    }

    pub fn from_sql_param(_: std.mem.Allocator, s: []const u8) !Money {
        // parse "123.45" → 12345 cents
        var it = std.mem.splitScalar(u8, s, '.');
        const euros = try std.fmt.parseInt(i64, it.next() orelse return error.Invalid, 10);
        const frac  = try std.fmt.parseInt(i64, it.next() orelse "0", 10);
        return .{ .cents = euros * 100 + frac };
    }
};
```

Then use it in any entity just like any other field:

```zig
price: Money,

pub const field_meta = .{
    .price = orm.FieldMeta(Money){},
};
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

## Testing

Run all tests:

```sh
zig build test
```

### Using Testing Utilities

Bebop provides helpers for testing controllers:

```zig
const bebop = @import("bebop");

test "products endpoint" {
    const app = try bebop.testing.App.init(allocator, .{});
    defer app.deinit();

    try app.migrate();

    const response = try app.get("/api/products");
    defer response.deinit();

    try std.testing.expectEqual(200, response.status);
}
```

## Development

### Route Inspection

Bebop can record and print all registered routes during development:

```zig
pub fn register(router: *Router) !void {
    var recording_router = Router.recording(allocator);
    defer recording_router.deinit();

    // Register routes...
    recording_router.get("api/healthz", health_check);
    recording_router.get("api/test", testing);

    // Print all routes
    recording_router.printRoutes();
}
```

## Credits

- [pg.zig](https://github.com/karlseguin/pg.zig) — PostgreSQL client by karlseguin
- [http.zig](https://github.com/karlseguin/http.zig) — HTTP server by karlseguin
