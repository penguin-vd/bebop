const std = @import("std");
const crypto = @import("../crypto.zig");

const test_key: [32]u8 = [_]u8{
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
    0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
};

test "encrypt/decrypt roundtrip" {
    const allocator = std.testing.allocator;

    const plaintext = "hello, world";
    const cipher = try crypto.encryptWithKey(allocator, test_key, plaintext);
    defer allocator.free(cipher);

    const decrypted = try crypto.decryptWithKey(allocator, test_key, cipher);
    defer allocator.free(decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted);
}

test "encrypt produces non-deterministic ciphertext (random nonce)" {
    const allocator = std.testing.allocator;

    const plaintext = "same input";
    const c1 = try crypto.encryptWithKey(allocator, test_key, plaintext);
    defer allocator.free(c1);
    const c2 = try crypto.encryptWithKey(allocator, test_key, plaintext);
    defer allocator.free(c2);

    try std.testing.expect(!std.mem.eql(u8, c1, c2));
}

test "encrypt handles empty plaintext" {
    const allocator = std.testing.allocator;

    const cipher = try crypto.encryptWithKey(allocator, test_key, "");
    defer allocator.free(cipher);

    const decrypted = try crypto.decryptWithKey(allocator, test_key, cipher);
    defer allocator.free(decrypted);

    try std.testing.expectEqual(@as(usize, 0), decrypted.len);
}

test "decrypt with wrong key fails authentication" {
    const allocator = std.testing.allocator;

    const cipher = try crypto.encryptWithKey(allocator, test_key, "secret");
    defer allocator.free(cipher);

    var wrong_key = test_key;
    wrong_key[0] ^= 0xFF;

    try std.testing.expectError(
        error.AuthenticationFailed,
        crypto.decryptWithKey(allocator, wrong_key, cipher),
    );
}

test "decrypt rejects tampered ciphertext" {
    const allocator = std.testing.allocator;

    const cipher = try crypto.encryptWithKey(allocator, test_key, "secret");
    defer allocator.free(cipher);

    // Decode, flip a bit in the ciphertext body, re-encode so we still have valid base64.
    const decoder = std.base64.standard.Decoder;
    const decoded_size = try decoder.calcSizeForSlice(cipher);
    const decoded = try allocator.alloc(u8, decoded_size);
    defer allocator.free(decoded);
    try decoder.decode(decoded, cipher);

    decoded[decoded.len / 2] ^= 0x01;

    const encoder = std.base64.standard.Encoder;
    const tampered = try allocator.alloc(u8, encoder.calcSize(decoded.len));
    defer allocator.free(tampered);
    _ = encoder.encode(tampered, decoded);

    try std.testing.expectError(
        error.AuthenticationFailed,
        crypto.decryptWithKey(allocator, test_key, tampered),
    );
}

test "decrypt rejects ciphertext shorter than nonce + tag" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.InvalidCiphertext,
        crypto.decryptWithKey(allocator, test_key, "dGlueQ=="), // "tiny"
    );
}
