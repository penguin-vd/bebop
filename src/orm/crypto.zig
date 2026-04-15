const std = @import("std");

const Aes256Gcm = std.crypto.aead.aes_gcm.Aes256Gcm;
const nonce_len = Aes256Gcm.nonce_length;
const tag_len = Aes256Gcm.tag_length;
const key_len = Aes256Gcm.key_length;

var cached_key: ?[key_len]u8 = null;

pub fn loadKey(allocator: std.mem.Allocator) ![key_len]u8 {
    if (cached_key) |k| return k;

    const raw = std.process.getEnvVarOwned(allocator, "APP_KEY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.MissingAppKey,
        else => return err,
    };
    defer allocator.free(raw);

    var key: [key_len]u8 = undefined;
    const prefix = "base64:";
    if (std.mem.startsWith(u8, raw, prefix)) {
        const encoded = raw[prefix.len..];
        const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
        if (decoded_len != key_len) return error.InvalidAppKeyLength;
        try std.base64.standard.Decoder.decode(&key, encoded);
    } else {
        if (raw.len != key_len) return error.InvalidAppKeyLength;
        @memcpy(&key, raw);
    }

    cached_key = key;
    return key;
}

pub fn encryptWithKey(allocator: std.mem.Allocator, key: [key_len]u8, plaintext: []const u8) ![]u8 {
    var nonce: [nonce_len]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    const ciphertext = try allocator.alloc(u8, plaintext.len);
    defer allocator.free(ciphertext);

    var tag: [tag_len]u8 = undefined;
    Aes256Gcm.encrypt(ciphertext, &tag, plaintext, "", nonce, key);

    const combined_len = nonce_len + ciphertext.len + tag_len;
    const combined = try allocator.alloc(u8, combined_len);
    defer allocator.free(combined);
    @memcpy(combined[0..nonce_len], &nonce);
    @memcpy(combined[nonce_len..][0..ciphertext.len], ciphertext);
    @memcpy(combined[nonce_len + ciphertext.len ..][0..tag_len], &tag);

    const encoder = std.base64.standard.Encoder;
    const out = try allocator.alloc(u8, encoder.calcSize(combined.len));
    _ = encoder.encode(out, combined);
    return out;
}

pub fn decryptWithKey(allocator: std.mem.Allocator, key: [key_len]u8, b64_input: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const decoded_size = try decoder.calcSizeForSlice(b64_input);
    if (decoded_size < nonce_len + tag_len) return error.InvalidCiphertext;

    const combined = try allocator.alloc(u8, decoded_size);
    defer allocator.free(combined);
    try decoder.decode(combined, b64_input);

    var nonce: [nonce_len]u8 = undefined;
    var tag: [tag_len]u8 = undefined;
    @memcpy(&nonce, combined[0..nonce_len]);
    const ct_len = combined.len - nonce_len - tag_len;
    @memcpy(&tag, combined[nonce_len + ct_len ..][0..tag_len]);

    const plaintext = try allocator.alloc(u8, ct_len);
    errdefer allocator.free(plaintext);

    try Aes256Gcm.decrypt(plaintext, combined[nonce_len..][0..ct_len], tag, "", nonce, key);
    return plaintext;
}

pub fn encrypt(allocator: std.mem.Allocator, plaintext: []const u8) ![]u8 {
    const key = try loadKey(allocator);
    return encryptWithKey(allocator, key, plaintext);
}

pub fn decrypt(allocator: std.mem.Allocator, b64_input: []const u8) ![]u8 {
    const key = try loadKey(allocator);
    return decryptWithKey(allocator, key, b64_input);
}

pub fn resetKeyCache() void {
    cached_key = null;
}
