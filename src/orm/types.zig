const std = @import("std");

pub const Uuid = struct {
    bytes: [16]u8,

    pub const sql_type = "UUID";

    pub fn new() Uuid {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        bytes[6] = (bytes[6] & 0x0F) | 0x40;
        bytes[8] = (bytes[8] & 0x3F) | 0x80;
        return .{ .bytes = bytes };
    }

    pub fn parse(s: []const u8) !Uuid {
        if (s.len != 36) return error.InvalidUuid;
        if (s[8] != '-' or s[13] != '-' or s[18] != '-' or s[23] != '-') return error.InvalidUuid;

        var bytes: [16]u8 = undefined;
        const positions = [_]usize{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };
        for (positions, 0..) |pos, i| {
            bytes[i] = try std.fmt.parseInt(u8, s[pos .. pos + 2], 16);
        }
        return .{ .bytes = bytes };
    }

    pub fn toString(self: Uuid, out: *[36]u8) void {
        const hex = "0123456789abcdef";
        const layout = [_]usize{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };
        for (self.bytes, 0..) |b, i| {
            const pos = layout[i];
            out[pos] = hex[b >> 4];
            out[pos + 1] = hex[b & 0x0F];
        }
        out[8] = '-';
        out[13] = '-';
        out[18] = '-';
        out[23] = '-';
    }

    pub fn to_sql_param(self: Uuid, allocator: std.mem.Allocator) ![]u8 {
        const out = try allocator.alloc(u8, 36);
        self.toString(out[0..36]);
        return out;
    }

    pub fn from_sql_param(allocator: std.mem.Allocator, s: []const u8) !Uuid {
        _ = allocator;
        if (s.len == 16) {
            var bytes: [16]u8 = undefined;
            @memcpy(&bytes, s);
            return .{ .bytes = bytes };
        }
        return try parse(s);
    }
};

pub const DateTime = struct {
    micros: i64,

    pub const sql_type = "TIMESTAMPTZ";

    pub fn now() DateTime {
        return .{ .micros = std.time.microTimestamp() };
    }

    pub fn fromUnix(seconds: i64) DateTime {
        return .{ .micros = seconds * std.time.us_per_s };
    }

    pub fn to_sql_param(self: DateTime, allocator: std.mem.Allocator) ![]u8 {
        const secs_total = @divFloor(self.micros, std.time.us_per_s);
        const frac: u32 = @intCast(@mod(self.micros, std.time.us_per_s));

        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(secs_total) };
        const epoch_day = epoch_secs.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_secs = epoch_secs.getDaySeconds();

        return try std.fmt.allocPrint(
            allocator,
            "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}+00:00",
            .{
                year_day.year,
                @intFromEnum(month_day.month),
                month_day.day_index + 1,
                day_secs.getHoursIntoDay(),
                day_secs.getMinutesIntoHour(),
                day_secs.getSecondsIntoMinute(),
                frac,
            },
        );
    }

    pub fn from_sql_param(allocator: std.mem.Allocator, s: []const u8) !DateTime {
        _ = allocator;
        if (s.len == 8) {
            const micros_since_2000 = std.mem.readInt(i64, s[0..8], .big);
            return .{ .micros = micros_since_2000 + 946_684_800_000_000 };
        }
        if (s.len < 19) return error.InvalidDateTime;

        const year = try std.fmt.parseInt(i32, s[0..4], 10);
        const month = try std.fmt.parseInt(u8, s[5..7], 10);
        const day = try std.fmt.parseInt(u8, s[8..10], 10);
        const hour = try std.fmt.parseInt(u8, s[11..13], 10);
        const minute = try std.fmt.parseInt(u8, s[14..16], 10);
        const second = try std.fmt.parseInt(u8, s[17..19], 10);

        var micros_frac: i64 = 0;
        var tz_offset_secs: i64 = 0;
        var idx: usize = 19;

        if (idx < s.len and s[idx] == '.') {
            idx += 1;
            const frac_start = idx;
            while (idx < s.len and s[idx] >= '0' and s[idx] <= '9') : (idx += 1) {}
            const frac_str = s[frac_start..idx];
            const frac_val = try std.fmt.parseInt(i64, frac_str, 10);
            micros_frac = frac_val;
            if (frac_str.len <= 6) {
                var k: usize = frac_str.len;
                while (k < 6) : (k += 1) micros_frac *= 10;
            } else {
                var k: usize = 6;
                while (k < frac_str.len) : (k += 1) micros_frac = @divTrunc(micros_frac, 10);
            }
        }

        if (idx < s.len and (s[idx] == '+' or s[idx] == '-')) {
            const sign: i64 = if (s[idx] == '+') 1 else -1;
            idx += 1;
            if (idx + 2 > s.len) return error.InvalidDateTime;
            const tz_hour = try std.fmt.parseInt(u8, s[idx .. idx + 2], 10);
            idx += 2;
            var tz_min: u8 = 0;
            if (idx < s.len and s[idx] == ':') idx += 1;
            if (idx + 2 <= s.len) {
                tz_min = std.fmt.parseInt(u8, s[idx .. idx + 2], 10) catch 0;
            }
            tz_offset_secs = sign * (@as(i64, tz_hour) * 3600 + @as(i64, tz_min) * 60);
        }

        const days_from_civil = civilToDays(year, month, day);
        const secs = days_from_civil * std.time.s_per_day +
            @as(i64, hour) * 3600 +
            @as(i64, minute) * 60 +
            @as(i64, second) -
            tz_offset_secs;

        return .{ .micros = secs * std.time.us_per_s + micros_frac };
    }
};

pub const Date = struct {
    days: i32,

    pub const sql_type = "DATE";

    pub fn fromYmd(year: i32, month: u8, day: u8) Date {
        return .{ .days = @intCast(civilToDays(year, month, day)) };
    }

    pub fn to_sql_param(self: Date, allocator: std.mem.Allocator) ![]u8 {
        const secs: i64 = @as(i64, self.days) * std.time.s_per_day;
        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(secs) };
        const year_day = epoch_secs.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(
            allocator,
            "{d:0>4}-{d:0>2}-{d:0>2}",
            .{ year_day.year, @intFromEnum(month_day.month), month_day.day_index + 1 },
        );
    }

    pub fn from_sql_param(allocator: std.mem.Allocator, s: []const u8) !Date {
        _ = allocator;
        if (s.len == 4) {
            const days_since_2000 = std.mem.readInt(i32, s[0..4], .big);
            return .{ .days = days_since_2000 + 10957 };
        }
        if (s.len < 10) return error.InvalidDate;
        const year = try std.fmt.parseInt(i32, s[0..4], 10);
        const month = try std.fmt.parseInt(u8, s[5..7], 10);
        const day = try std.fmt.parseInt(u8, s[8..10], 10);
        return fromYmd(year, month, day);
    }
};

fn civilToDays(y: i32, m: u8, d: u8) i64 {
    const yy: i64 = if (m <= 2) @as(i64, y) - 1 else y;
    const era: i64 = @divFloor(yy, 400);
    const yoe: i64 = yy - era * 400;
    const mm: i64 = m;
    const doy: i64 = @divFloor(153 * (if (mm > 2) mm - 3 else mm + 9) + 2, 5) + @as(i64, d) - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

pub fn is_custom_type(comptime T: type) bool {
    const ti = @typeInfo(T);
    return ti == .@"struct" and @hasDecl(T, "sql_type") and !@hasDecl(T, "table_name");
}
