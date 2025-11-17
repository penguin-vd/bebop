const std = @import("std");
const utils = @import("utils.zig");

pub const FieldInfo = struct {
    name: []const u8,
    column_name: []const u8,
    table_name: []const u8,
    relation_depth: usize = 0,
};

pub const JoinType = enum {
    inner,
    left,
};

pub const JoinInfo = struct {
    table_name: []const u8,
    join_type: JoinType,
    foreign_key: []const u8,
    foreign_table: []const u8,
    primary_key: []const u8,
    alias: ?[]const u8 = null,
    relation_depth: usize = 0,
};

pub inline fn count_total_fields(Model: type) usize {
    const struct_info = @typeInfo(Model).@"struct";
    var count = 0;
    for (struct_info.fields) |field| {
        if (!utils.is_relation(field.type)) {
            count += 1;
        } else {
            const RelatedModel = rel: {
                const field_type_info = @typeInfo(field.type);
                break :rel if (field_type_info == .optional) field_type_info.optional.child else field.type;
            };

            switch (@typeInfo(RelatedModel)) {
                .@"struct" => {
                    count += count_total_fields(RelatedModel);
                },
                else => unreachable,
            }
        }
    }

    return count;
}

pub inline fn fill_field_info_slice(table_name: []const u8, Model: type, fieldInfo: anytype, start: usize, depth: usize) usize {
    const struct_info = @typeInfo(Model).@"struct";
    var idx: usize = start;
    for (struct_info.fields) |field| {
        if (!utils.is_relation(field.type)) {
            fieldInfo.*[idx] = .{
                .name = field.name,
                .column_name = utils.get_column_name(Model, field.name),
                .table_name = table_name,
                .relation_depth = depth,
            };
            idx += 1;
        } else {
            const RelatedModel = rel: {
                const field_type_info = @typeInfo(field.type);
                break :rel if (field_type_info == .optional) field_type_info.optional.child else field.type;
            };

            switch (@typeInfo(RelatedModel)) {
                .@"struct" => {
                    const related_table_name = if (@hasDecl(RelatedModel, "table_name"))
                        RelatedModel.table_name
                    else
                        unreachable;
                    idx = fill_field_info_slice(related_table_name, RelatedModel, fieldInfo, idx, depth + 1);
                },
                else => unreachable,
            }
        }
    }

    return idx;
}

pub inline fn count_relations(Model: type) usize {
    const struct_info = @typeInfo(Model).@"struct";
    var count = 0;
    for (struct_info.fields) |field| {
        if (utils.is_relation(field.type)) {
            count += 1;

            const RelatedModel = rel: {
                const field_type_info = @typeInfo(field.type);
                break :rel if (field_type_info == .optional)
                    field_type_info.optional.child
                else
                    field.type;
            };

            switch (@typeInfo(RelatedModel)) {
                .@"struct" => {
                    count += count_relations(RelatedModel);
                },
                else => {},
            }
        }
    }
    return count;
}

pub inline fn fill_join_info(parent_table: []const u8, Model: type, joins: anytype, start: usize, depth: usize) usize {
    const struct_info = @typeInfo(Model).@"struct";
    var idx: usize = start;

    for (struct_info.fields) |field| {
        if (utils.is_relation(field.type)) {
            const field_type_info = @typeInfo(field.type);
            const is_optional = field_type_info == .optional;

            const RelatedModel = if (is_optional)
                field_type_info.optional.child
            else
                field.type;

            const related_table_name = if (@hasDecl(RelatedModel, "table_name"))
                RelatedModel.table_name
            else
                unreachable;

            const join_type: JoinType = if (is_optional) .left else .inner;
            const foreign_key = field.name ++ "_id";

            const alias = if (depth > 0) related_table_name ++ "_" ++ field.name else null;

            joins.*[idx] = .{
                .table_name = related_table_name,
                .join_type = join_type,
                .foreign_key = foreign_key,
                .foreign_table = parent_table,
                .primary_key = "id",
                .alias = alias,
                .relation_depth = depth,
            };
            idx += 1;

            switch (@typeInfo(RelatedModel)) {
                .@"struct" => {
                    idx = fill_join_info(related_table_name, RelatedModel, joins, idx, depth + 1);
                },
                else => {},
            }
        }
    }

    return idx;
}
