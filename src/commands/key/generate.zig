const std = @import("std");

pub const command = "key:generate";

pub fn run(allocator: std.mem.Allocator) !void {
    var key: [32]u8 = undefined;
    std.crypto.random.bytes(&key);

    const encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, encoder.calcSize(key.len));
    defer allocator.free(encoded);
    _ = encoder.encode(encoded, &key);

    const stdout_file = std.fs.File.stdout();
    var buf: [256]u8 = undefined;
    var writer = stdout_file.writer(&buf);
    try writer.interface.print("APP_KEY=base64:{s}\n", .{encoded});
    try writer.interface.flush();
}
