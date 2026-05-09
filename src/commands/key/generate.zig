const std = @import("std");

pub const command = "key:generate";

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;
    var key: [32]u8 = undefined;
    _ = std.os.linux.getrandom(&key, key.len, 0);

    const encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, encoder.calcSize(key.len));
    defer allocator.free(encoded);
    _ = encoder.encode(encoded, &key);

    var buf: [512]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "APP_KEY=base64:{s}\n", .{encoded});
    _ = std.os.linux.write(std.os.linux.STDOUT_FILENO, msg.ptr, msg.len);
}
