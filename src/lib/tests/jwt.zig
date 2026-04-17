const std = @import("std");
const jwt = @import("../jwt.zig");

test "generate and verify round-trip" {
    const allocator = std.testing.allocator;
    const secret = "supersecret";
    const claims = jwt.Claims{ .sub = 42, .exp = std.time.timestamp() + 3600 };

    const token = try jwt.generate(jwt.Claims, allocator, claims, secret);
    defer allocator.free(token);

    const verified = try jwt.verify(jwt.Claims, allocator, token, secret);
    defer verified.deinit();
    try std.testing.expectEqual(claims.sub, verified.value.sub);
    try std.testing.expectEqual(claims.exp, verified.value.exp);
}

test "verify rejects expired token" {
    const allocator = std.testing.allocator;
    const secret = "supersecret";
    const claims = jwt.Claims{ .sub = 1, .exp = std.time.timestamp() - 1 };

    const token = try jwt.generate(jwt.Claims, allocator, claims, secret);
    defer allocator.free(token);

    try std.testing.expectError(error.TokenExpired, jwt.verify(jwt.Claims, allocator, token, secret));
}

test "verify rejects wrong secret" {
    const allocator = std.testing.allocator;
    const claims = jwt.Claims{ .sub = 1, .exp = std.time.timestamp() + 3600 };

    const token = try jwt.generate(jwt.Claims, allocator, claims, "correct-secret");
    defer allocator.free(token);

    try std.testing.expectError(error.InvalidSignature, jwt.verify(jwt.Claims, allocator, token, "wrong-secret"));
}

test "verify rejects tampered payload" {
    const allocator = std.testing.allocator;
    const secret = "supersecret";
    const claims = jwt.Claims{ .sub = 1, .exp = std.time.timestamp() + 3600 };

    const token = try jwt.generate(jwt.Claims, allocator, claims, secret);
    defer allocator.free(token);

    var parts = std.mem.splitScalar(u8, token, '.');
    const header = parts.next().?;
    _ = parts.next();
    const signature = parts.next().?;

    const encoder = std.base64.url_safe_no_pad.Encoder;
    const raw = "{\"sub\":999,\"exp\":9999999999}";
    const fake_payload = try allocator.alloc(u8, encoder.calcSize(raw.len));
    defer allocator.free(fake_payload);
    _ = encoder.encode(fake_payload, raw);

    const tampered = try std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ header, fake_payload, signature });
    defer allocator.free(tampered);

    try std.testing.expectError(error.InvalidSignature, jwt.verify(jwt.Claims, allocator, tampered, secret));
}

test "verify rejects malformed token" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidToken, jwt.verify(jwt.Claims, allocator, "notavalidtoken", "secret"));
    try std.testing.expectError(error.InvalidToken, jwt.verify(jwt.Claims, allocator, "only.twoparts", "secret"));
}
