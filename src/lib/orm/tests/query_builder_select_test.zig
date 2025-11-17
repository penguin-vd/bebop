const std = @import("std");

const utils = @import("../utils.zig");
const QueryBuilder = @import("../query_builder.zig").QueryBuilder;

const User = struct {
    id: i32,
    name: []const u8,
    age: i32,

    pub const table_name = "users";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
        .age = utils.FieldMeta(i32){},
    };
};

const Product = struct {
    id: i32,
    price: f64,
    in_stock: bool,

    pub const table_name = "products";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .price = utils.FieldMeta(f64){},
        .in_stock = utils.FieldMeta(bool){},
    };
};

const Category = struct {
    id: i32,
    name: []const u8,

    pub const table_name = "categories";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    };
};

const Supplier = struct {
    id: i32,
    company_name: []const u8,

    pub const table_name = "suppliers";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .company_name = utils.FieldMeta([]const u8){ .max_length = 255 },
    };
};

const ProductWithRelations = struct {
    id: i32,
    category: ?Category,
    supplier: ?Supplier,

    pub const table_name = "products";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .category = utils.FieldMeta(Category){},
        .supplier = utils.FieldMeta(Supplier){},
    };
};

const ParentCategory = struct {
    id: i32,
    name: []const u8,

    pub const table_name = "categories";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    };
};

const NestedCategory = struct {
    id: i32,
    name: []const u8,
    parent: ?ParentCategory,

    pub const table_name = "categories";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
        .parent = utils.FieldMeta(ParentCategory){},
    };
};

const ProductWithNestedRelation = struct {
    id: i32,
    category: ?NestedCategory,

    pub const table_name = "products";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .category = utils.FieldMeta(NestedCategory){},
    };
};

test "where with multiple conditions and different types" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("age", ">", 18);
    try qb.where("name", "=", "Bob");
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.age > $1 AND users.name = $2", result.sql);

    try std.testing.expectEqual(@as(usize, 2), result.params.len);
    try std.testing.expectEqualStrings("18", result.params[0]);
    try std.testing.expectEqualStrings("Bob", result.params[1]);
}

test "where with float and boolean values" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Product).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("price", ">=", 10.99);
    try qb.where("in_stock", "=", true);
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id, products.price, products.in_stock " ++
        "FROM products " ++
        "WHERE products.price >= $1 AND products.in_stock = $2", result.sql);

    try std.testing.expectEqual(@as(usize, 2), result.params.len);
    try std.testing.expectEqualStrings("10.99", result.params[0]);
    try std.testing.expectEqualStrings("true", result.params[1]);
}

test "selectFields with where clause" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "name", "age" };
    try qb.selectFields(&fields);
    try qb.where("id", "=", 1);
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT users.name, users.age " ++
        "FROM users " ++
        "WHERE users.id = $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("1", result.params[0]);
}

test "select specific field on relation" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithRelations).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "id", "category.name" };
    try qb.selectFields(&fields);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id, categories.name " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id", result.sql);

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "nested relations" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithNestedRelation).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "id", "category.parent.name" };
    try qb.selectFields(&fields);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id, categories_parent.name " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id " ++
        "LEFT JOIN categories AS categories_parent ON categories.parent_id = categories_parent.id", result.sql);

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "only join relations that are selected" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithRelations).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "id", "category.name" };
    try qb.selectFields(&fields);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id, categories.name " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id", result.sql);

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "select from nested relation without intermediate fields" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithNestedRelation).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "id", "category.parent.name" };
    try qb.selectFields(&fields);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id, categories_parent.name " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id " ++
        "LEFT JOIN categories AS categories_parent ON categories.parent_id = categories_parent.id", result.sql);

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "filter by relation field" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithRelations).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("category.id", "=", 5);
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id, categories.id, categories.name, suppliers.id, suppliers.company_name " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id " ++
        "LEFT JOIN suppliers ON products.supplier_id = suppliers.id " ++
        "WHERE categories.id = $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("5", result.params[0]);
}

test "filter by nested relation field" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithNestedRelation).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("category.parent.id", "=", 5);
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id, categories_parent.id, categories_parent.name, categories.id, categories.name " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id " ++
        "LEFT JOIN categories AS categories_parent ON categories.parent_id = categories_parent.id " ++
        "WHERE categories_parent.id = $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("5", result.params[0]);
}

test "filter by relation only selecting field on single" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithRelations).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{"id"};
    try qb.selectFields(&fields);

    try qb.where("category.id", "=", 1);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id " ++
        "WHERE categories.id = $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
}

test "filter by nested relation only selecting field on single" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(ProductWithNestedRelation).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{"id"};
    try qb.selectFields(&fields);

    try qb.where("category.parent.id", "=", 5);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| {
            allocator.free(param);
        }
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings("SELECT products.id " ++
        "FROM products " ++
        "LEFT JOIN categories ON products.category_id = categories.id " ++
        "LEFT JOIN categories AS categories_parent ON categories.parent_id = categories_parent.id " ++
        "WHERE categories_parent.id = $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
}
