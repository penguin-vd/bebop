const std = @import("std");

const utils = @import("../utils.zig");
const QueryBuilder = @import("../query_builder.zig").QueryBuilder;

const Tag = struct {
    id: i32,
    name: []const u8,

    pub const table_name = "tags";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    };
};

const Article = struct {
    id: i32,
    title: []const u8,
    tags: []Tag,

    pub const table_name = "articles";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .title = utils.FieldMeta([]const u8){ .max_length = 255 },
        .tags = utils.FieldMeta([]Tag){ .many_to_many = true },
    };
};

test "many to many default select generates pivot joins" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Article).init(allocator);
    defer qb.deinit();

    qb.select();
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer allocator.free(result.params);

    try std.testing.expectEqualStrings(
        "SELECT articles.id, articles.title, tags.id, tags.name " ++
            "FROM articles " ++
            "LEFT JOIN articles_tags ON articles.id = articles_tags.articles_id " ++
            "LEFT JOIN tags ON articles_tags.tags_id = tags.id",
        result.sql,
    );

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "many to many select specific fields" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Article).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "id", "tags.name" };
    try qb.selectFields(&fields);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer allocator.free(result.params);

    try std.testing.expectEqualStrings(
        "SELECT articles.id, tags.name " ++
            "FROM articles " ++
            "LEFT JOIN articles_tags ON articles.id = articles_tags.articles_id " ++
            "LEFT JOIN tags ON articles_tags.tags_id = tags.id",
        result.sql,
    );

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "many to many select only owner fields skips pivot joins" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Article).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "id", "title" };
    try qb.selectFields(&fields);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer allocator.free(result.params);

    try std.testing.expectEqualStrings(
        "SELECT articles.id, articles.title FROM articles",
        result.sql,
    );

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "many to many where on related field" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Article).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("tags.id", "=", 3);
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| allocator.free(param);
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings(
        "SELECT articles.id, articles.title, tags.id, tags.name " ++
            "FROM articles " ++
            "LEFT JOIN articles_tags ON articles.id = articles_tags.articles_id " ++
            "LEFT JOIN tags ON articles_tags.tags_id = tags.id " ++
            "WHERE tags.id = $1",
        result.sql,
    );

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("3", result.params[0]);
}

test "many to many filter only selecting owner fields includes pivot joins" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Article).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{"id"};
    try qb.selectFields(&fields);
    try qb.where("tags.name", "=", "zig");

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| allocator.free(param);
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings(
        "SELECT articles.id " ++
            "FROM articles " ++
            "LEFT JOIN articles_tags ON articles.id = articles_tags.articles_id " ++
            "LEFT JOIN tags ON articles_tags.tags_id = tags.id " ++
            "WHERE tags.name = $1",
        result.sql,
    );

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("zig", result.params[0]);
}
