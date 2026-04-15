const orm = @import("bebop").orm;

const Self = @This();

var post_load_count: u32 = 0;
var post_remove_count: u32 = 0;

pub fn resetHookCounters() void {
    post_load_count = 0;
    post_remove_count = 0;
}

pub fn postLoadCount() u32 {
    return post_load_count;
}

pub fn postRemoveCount() u32 {
    return post_remove_count;
}

id: i32 = 0,
external_id: orm.Uuid = .{ .bytes = [_]u8{0} ** 16 },
created_at: orm.DateTime = .{ .micros = 0 },
updated_at: orm.DateTime = .{ .micros = 0 },
expires_on: orm.Date = .{ .days = 0 },
token: []const u8,

pub const table_name = "secrets";

pub const field_meta = .{
    .id = orm.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .external_id = orm.FieldMeta(orm.Uuid){},
    .created_at = orm.FieldMeta(orm.DateTime){},
    .updated_at = orm.FieldMeta(orm.DateTime){},
    .expires_on = orm.FieldMeta(orm.Date){},
    .token = orm.FieldMeta([]const u8){ .is_encrypted = true, .max_length = 4096 },
};

pub fn pre_persist(self: *Self) !void {
    self.external_id = orm.Uuid.new();
    const now = orm.DateTime.now();
    self.created_at = now;
    self.updated_at = now;
    if (self.expires_on.days == 0) {
        self.expires_on = orm.Date.fromYmd(2030, 12, 31);
    }
}

pub fn pre_update(self: *Self) !void {
    self.updated_at = orm.DateTime{ .micros = self.updated_at.micros + 1 };
}

pub fn post_load(self: *Self) !void {
    _ = self;
    post_load_count += 1;
}

pub fn post_remove(self: *Self) !void {
    _ = self;
    post_remove_count += 1;
}
