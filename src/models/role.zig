const utils = @import("../orm/utils.zig");

id: i32,
title: []const u8,

pub const field_meta = .{
    .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .title = utils.FieldMeta([]const u8){ .max_length = 255 },
};
