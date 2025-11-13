const utils = @import("../orm/utils.zig");
const Role = @import("role.zig");

id: i32,
name: []const u8,
role: ?Role = null,

pub const field_meta = .{
    .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    .role = utils.FieldMeta(Role){ },
};
