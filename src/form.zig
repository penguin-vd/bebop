const std = @import("std");
const httpz = @import("httpz");

/// Returns the URL-decoded value for `key` from an application/x-www-form-urlencoded
/// request body, or null if the key is not present or the body is empty.
/// Allocates into req.arena.
pub fn formParam(req: *httpz.Request, key: []const u8) !?[]const u8 {
    const body = req.body() orelse return null;
    var it = std.mem.splitScalar(u8, body, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOf(u8, pair, "=") orelse continue;
        if (std.mem.eql(u8, pair[0..eq], key)) {
            return try urlDecode(req.arena, pair[eq + 1 ..]);
        }
    }
    return null;
}

fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, input.len);
    var i: usize = 0;
    var j: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch null;
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch null;
            if (hi != null and lo != null) {
                out[j] = (hi.? << 4) | lo.?;
                i += 3;
                j += 1;
                continue;
            }
        } else if (input[i] == '+') {
            out[j] = ' ';
            i += 1;
            j += 1;
            continue;
        }
        out[j] = input[i];
        i += 1;
        j += 1;
    }
    return out[0..j];
}
