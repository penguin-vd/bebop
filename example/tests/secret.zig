const std = @import("std");
const bebop = @import("bebop");

const Secret = @import("../models/secret.zig");

test "secret: pre_persist populates external_id and timestamps" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Secret).init(allocator, conn);
    defer em.deinit();

    const secret = try em.create(.{ .token = "hunter2" });

    // Pre-flush: defaults are zero.
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** 16, &secret.external_id.bytes);
    try std.testing.expectEqual(@as(i64, 0), secret.created_at.micros);

    try em.flush();

    // Post-flush: hook populated fields.
    try std.testing.expect(secret.id != 0);
    try std.testing.expect(!std.mem.eql(u8, &[_]u8{0} ** 16, &secret.external_id.bytes));
    try std.testing.expect(secret.created_at.micros > 0);
    try std.testing.expectEqual(secret.created_at.micros, secret.updated_at.micros);
    try std.testing.expectEqual(bebop.orm.Date.fromYmd(2030, 12, 31).days, secret.expires_on.days);
}

test "secret: pre_update advances updated_at but leaves created_at untouched" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Secret).init(allocator, conn);
    defer em.deinit();

    const secret = try em.create(.{ .token = "first" });
    try em.flush();

    const created_before = secret.created_at.micros;
    const updated_before = secret.updated_at.micros;

    secret.token = "second";
    try em.flush();

    try std.testing.expectEqual(created_before, secret.created_at.micros);
    try std.testing.expect(secret.updated_at.micros > updated_before);
}

test "secret: encrypted token round-trips through DB (raw ciphertext != plaintext)" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    {
        var em = bebop.orm.EntityManager(Secret).init(allocator, conn);
        defer em.deinit();
        _ = try em.create(.{ .token = "plaintext-token" });
        try em.flush();
    }

    // Raw read: column should be base64 ciphertext, not the plaintext.
    var raw = try conn.query("SELECT token FROM secrets LIMIT 1", .{});
    defer raw.deinit();

    const row = (try raw.next()) orelse return error.NoRow;
    const raw_token = row.get([]const u8, 0);
    try std.testing.expect(!std.mem.eql(u8, "plaintext-token", raw_token));
    // AES-GCM output is base64; nonce(12) + ct(15) + tag(16) = 43 bytes → 60 base64 chars.
    try std.testing.expect(raw_token.len >= 60);
    while (try raw.next()) |_| {}

    // Reload via ORM: decryption should yield the original plaintext.
    var em2 = bebop.orm.EntityManager(Secret).init(allocator, conn);
    defer em2.deinit();

    var qb = em2.query();
    defer qb.deinit();

    const results = try em2.find(&qb);
    defer em2.freeModels(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualSlices(u8, "plaintext-token", results[0].token);
}

test "secret: UUID and DateTime round-trip through DB unchanged" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var original_uuid: bebop.orm.Uuid = undefined;
    var original_created: i64 = 0;

    {
        var em = bebop.orm.EntityManager(Secret).init(allocator, conn);
        defer em.deinit();

        const secret = try em.create(.{ .token = "t" });
        try em.flush();

        original_uuid = secret.external_id;
        original_created = secret.created_at.micros;
    }

    var em2 = bebop.orm.EntityManager(Secret).init(allocator, conn);
    defer em2.deinit();

    var qb = em2.query();
    defer qb.deinit();

    const results = try em2.find(&qb);
    defer em2.freeModels(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualSlices(u8, &original_uuid.bytes, &results[0].external_id.bytes);
    try std.testing.expectEqual(original_created, results[0].created_at.micros);
    try std.testing.expectEqual(bebop.orm.Date.fromYmd(2030, 12, 31).days, results[0].expires_on.days);
}

test "secret: post_load fires once per row loaded" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    {
        var em = bebop.orm.EntityManager(Secret).init(allocator, conn);
        defer em.deinit();
        _ = try em.create(.{ .token = "a" });
        _ = try em.create(.{ .token = "b" });
        _ = try em.create(.{ .token = "c" });
        try em.flush();
    }

    Secret.resetHookCounters();

    var em2 = bebop.orm.EntityManager(Secret).init(allocator, conn);
    defer em2.deinit();

    var qb = em2.query();
    defer qb.deinit();

    const results = try em2.find(&qb);
    defer em2.freeModels(results);

    try std.testing.expectEqual(@as(usize, 3), results.len);
    try std.testing.expectEqual(@as(u32, 3), Secret.postLoadCount());
}

test "secret: post_remove fires after delete" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Secret).init(allocator, conn);
    defer em.deinit();

    const secret = try em.create(.{ .token = "doomed" });
    try em.flush();

    Secret.resetHookCounters();

    try em.remove(secret);
    try em.flush();

    try std.testing.expectEqual(@as(u32, 1), Secret.postRemoveCount());
}
