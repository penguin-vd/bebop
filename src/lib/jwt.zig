const std = @import("std");
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

pub const Claims = struct {
    sub: i32,
    exp: i64,
};

pub fn generate(comptime T: type, allocator: std.mem.Allocator, claims: T, secret: []const u8) ![]u8 {
    const header = "eyJhbGciOiJIUzI1NiJ9";

    const fmt = std.json.fmt(claims, .{});

    var writer = std.Io.Writer.Allocating.init(allocator);
    try fmt.format(&writer.writer);
    const json_string = try writer.toOwnedSlice();
    defer allocator.free(json_string);

    const payload = try base64Encode(allocator, json_string);
    defer allocator.free(payload);

    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ header, payload });
    defer allocator.free(signing_input);

    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input, secret);

    const signature = try base64Encode(allocator, &mac);
    defer allocator.free(signature);

    return std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ header, payload, signature });
}

pub fn verify(comptime T: type, allocator: std.mem.Allocator, token: []const u8, secret: []const u8) !T {
    var parts = std.mem.splitScalar(u8, token, '.');
    const header = parts.next() orelse return error.InvalidToken;
    const payload = parts.next() orelse return error.InvalidToken;
    const signature = parts.next() orelse return error.InvalidToken;

    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ header, payload });
    defer allocator.free(signing_input);

    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input, secret);

    const expected_sig = try base64Encode(allocator, &mac);
    defer allocator.free(expected_sig);

    if (!std.mem.eql(u8, signature, expected_sig)) return error.InvalidSignature;

    const payload_json = try base64Decode(allocator, payload);
    defer allocator.free(payload_json);

    const parsed = try std.json.parseFromSlice(T, allocator, payload_json, .{});
    defer parsed.deinit();

    if (@hasField(T, "exp")) {
        const now = std.time.timestamp();
        if (parsed.value.exp < now) return error.TokenExpired;
    }

    return parsed.value;
}

fn base64Encode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const encoder = std.base64.url_safe_no_pad.Encoder;
    const out = try allocator.alloc(u8, encoder.calcSize(data.len));
    return encoder.encode(out, data);
}

fn base64Decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const decoder = std.base64.url_safe_no_pad.Decoder;
    const out = try allocator.alloc(u8, try decoder.calcSizeForSlice(data));
    try decoder.decode(out, data);
    return out;
}
