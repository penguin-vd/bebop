const std = @import("std");
const utils = @import("utils.zig");

pub const FieldInfo = struct {
    name: []const u8,
    column_name: []const u8,
    table_name: []const u8,
    table_alias: ?[]const u8 = null,
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

pub inline fn count_total_fields(Model: type, Parent: ?type) usize {
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
                    if (Parent) |p| {
                        if (RelatedModel == p) {
                            continue;
                        }
                    }
                    count += count_total_fields(RelatedModel, Model);
                },
                .pointer => |ptr_info| {
                    if (@typeInfo(ptr_info.child) == .@"struct") {
                        if (Parent) |p| {
                            if (ptr_info.child == p) {
                                continue;
                            }
                        }
                        count += count_total_fields(ptr_info.child, Model);
                    }
                },
                else => unreachable,
            }
        }
    }

    return count;
}

pub inline fn fill_field_info_slice(table_name: []const u8, table_alias: ?[]const u8, Model: type, Parent: ?type, fieldInfo: anytype, start: usize, depth: usize) usize {
    const struct_info = @typeInfo(Model).@"struct";
    var idx: usize = start;
    for (struct_info.fields) |field| {
        if (!utils.is_relation(field.type)) {
            fieldInfo.*[idx] = .{
                .name = field.name,
                .column_name = utils.get_column_name(Model, field.name),
                .table_name = table_name,
                .table_alias = table_alias,
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
                    if (Parent) |p| {
                        if (RelatedModel == p) {
                            continue;
                        }
                    }
                    const related_table_name = if (@hasDecl(RelatedModel, "table_name"))
                        RelatedModel.table_name
                    else
                        unreachable;
                    const alias = if (depth > 0) related_table_name ++ "_" ++ field.name else null;
                    idx = fill_field_info_slice(related_table_name, alias, RelatedModel, Model, fieldInfo, idx, depth + 1);
                },
                .pointer => |ptr_info| {
                    if (@typeInfo(ptr_info.child) == .@"struct") {
                        if (Parent) |p| {
                            if (ptr_info.child == p) {
                                continue;
                            }
                        }
                        const related_table_name = if (@hasDecl(ptr_info.child, "table_name"))
                            ptr_info.child.table_name
                        else
                            unreachable;
                        const alias = if (depth > 0) related_table_name ++ "_" ++ field.name else null;
                        idx = fill_field_info_slice(related_table_name, alias, ptr_info.child, Model, fieldInfo, idx, depth + 1);
                    }
                },
                else => unreachable,
            }
        }
    }

    return idx;
}

pub inline fn count_relations(Model: type, Parent: ?type) usize {
    const struct_info = @typeInfo(Model).@"struct";
    var count = 0;
    for (struct_info.fields) |field| {
        if (utils.is_relation(field.type)) {
            const RelatedModel = rel: {
                const field_type_info = @typeInfo(field.type);
                break :rel if (field_type_info == .optional)
                    field_type_info.optional.child
                else
                    field.type;
            };

            switch (@typeInfo(RelatedModel)) {
                .@"struct" => {
                    if (Parent) |p| {
                        if (RelatedModel == p) {
                            continue;
                        }
                    }
                    count += 1;
                    count += count_relations(RelatedModel, Model);
                },
                .pointer => |ptr_info| {
                    if (@typeInfo(ptr_info.child) == .@"struct") {
                        if (Parent) |p| {
                            if (ptr_info.child == p) {
                                continue;
                            }
                        }
                        count += 1;
                        count += count_relations(ptr_info.child, Model);
                    }
                },
                else => {},
            }
        }
    }
    return count;
}

pub inline fn fill_join_info(parent_table: []const u8, Model: type, Parent: ?type, joins: anytype, start: usize, depth: usize) usize {
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

            switch (@typeInfo(RelatedModel)) {
                .@"struct" => {
                    if (Parent) |p| {
                        if (RelatedModel == p) {
                            continue;
                        }
                    }
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

                    const next_parent = if (depth > 0) related_table_name ++ "_" ++ field.name else related_table_name;
                    idx = fill_join_info(next_parent, RelatedModel, Model, joins, idx, depth + 1);
                },
                .pointer => |ptr_info| {
                    if (@typeInfo(ptr_info.child) == .@"struct") {
                        if (Parent) |p| {
                            if (ptr_info.child == p) {
                                continue;
                            }
                        }
                        const related_table_name = if (@hasDecl(ptr_info.child, "table_name"))
                            ptr_info.child.table_name
                        else
                            unreachable;

                        const foreign_key = "id";

                        const alias = if (depth > 0) related_table_name ++ "_" ++ field.name else null;

                        const primary_key = comptime blk: {
                            const child_struct_info = @typeInfo(ptr_info.child).@"struct";
                            for (child_struct_info.fields) |child_field| {
                                if (utils.is_relation(child_field.type)) {
                                    const ChildRelatedType = if (@typeInfo(child_field.type) == .optional)
                                        @typeInfo(child_field.type).optional.child
                                    else
                                        child_field.type;

                                    if (ChildRelatedType == Model) {
                                        break :blk child_field.name ++ "_id";
                                    }
                                }
                            }
                            break :blk parent_table ++ "_id";
                        };

                        joins.*[idx] = .{
                            .table_name = related_table_name,
                            .join_type = .left,
                            .foreign_key = foreign_key,
                            .foreign_table = parent_table,
                            .primary_key = primary_key,
                            .alias = alias,
                            .relation_depth = depth,
                        };
                        idx += 1;

                        const next_parent = if (depth > 0) related_table_name ++ "_" ++ field.name else related_table_name;
                        idx = fill_join_info(next_parent, ptr_info.child, Model, joins, idx, depth + 1);
                    }
                },
                else => {},
            }
        }
    }

    return idx;
}
