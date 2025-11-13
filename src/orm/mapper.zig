const std = @import("std");
const pg = @import("pg");
const utils = @import("utils.zig");
const Driver = @import("drivers/base.zig").Driver;

pub fn Map(comptime Model: type, driver: Driver) type {
    return struct {
        const Self = @This();
        pub const Filter = utils.QueryFilter(Model);
        pub const QueryOptions = struct {
            with: ?[]const []const u8 = null,
        };

        pub fn list(_: *const Self, allocator: std.mem.Allocator, conn: *pg.Conn, filter: ?Filter, options: ?QueryOptions) ![]Model {
            var sql: []const u8 = undefined;
            defer allocator.free(sql);

            var query_result: *pg.Result = undefined;
            
            if (filter) |f| {
                sql = try driver.build_list_query_with_filter(allocator, Model, f);
                std.log.info("SQL: {s}\n", .{sql});
                query_result = try conn.query(sql, .{});
            } else {
                const base_sql = try driver.build_list_query(allocator, Model);
                defer allocator.free(base_sql);
                sql = try std.fmt.allocPrint(allocator, "{s};", .{base_sql});
                std.log.info("SQL: {s}\n", .{sql});
                query_result = try conn.query(sql, .{});
            }
            defer query_result.deinit();


            var models: std.ArrayList(Model) = .{};
            errdefer models.deinit(allocator);

            while (try query_result.next()) |row| {
                const model = try Self.row_to_model(allocator, row);
                try models.append(allocator, model);
            }

            const owned_models = try models.toOwnedSlice(allocator);

            if (options) |opts| {
                if (opts.with) |relations_to_load| {
                    const struct_info = @typeInfo(Model).@"struct";
                    inline for (struct_info.fields) |field| {
                        if (comptime utils.is_relation(field.type)) {
                            for (relations_to_load) |requested_relation| {
                                if (std.mem.eql(u8, field.name, requested_relation)) {
                                    try load_relation(allocator, conn, owned_models, field.name);
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            return owned_models;
        }

        pub fn create(_: *const Self, allocator: std.mem.Allocator, conn: *pg.Conn, model: Model) !Model {
            const insert_sql = try driver.build_insert_query(allocator, Model);
            defer allocator.free(insert_sql);

            var result = try execute_insert_query(conn, model, insert_sql);
            defer result.deinit();

            if (try result.next()) |row| {
                return try Self.row_to_model(allocator, row);
            }

            return error.InsertFailed;
        }

        fn execute_insert_query(conn: *pg.Conn, model: Model, sql: []const u8) !*pg.Result {
            const struct_info = @typeInfo(Model).@"struct";

            comptime var field_count: usize = 0;
            inline for (struct_info.fields) |field| {
                if (!comptime should_skip_field(field.name)) {
                    field_count += 1;
                }
            }

            comptime var tuple_fields: [field_count]std.builtin.Type.StructField = undefined;
            comptime var idx: usize = 0;

            inline for (struct_info.fields) |field| {
                if (comptime should_skip_field(field.name)) continue;

                tuple_fields[idx] = .{
                    .name = std.fmt.comptimePrint("{d}", .{idx}),
                    .type = field.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field.type),
                };
                idx += 1;
            }

            const TupleType = @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = &tuple_fields,
                .decls = &.{},
                .is_tuple = true,
            } });

            var tuple: TupleType = undefined;
            idx = 0;
            inline for (struct_info.fields) |field| {
                if (comptime should_skip_field(field.name)) continue;

                @field(tuple, tuple_fields[idx].name) = @field(model, field.name);
                idx += 1;
            }

            return try conn.query(sql, tuple);
        }

        pub fn row_to_model(allocator: std.mem.Allocator, row: anytype) !Model {
            var model: Model = undefined;
            const struct_info = @typeInfo(Model).@"struct";

            inline for (struct_info.fields, 0..) |field, i| {
                if (comptime utils.is_relation(field.type)) {
                    @field(model, field.name) = null;
                    continue;
                }
                std.debug.print("Getting {s}\n", .{field.name});
                @field(model, field.name) = try get_field_value(allocator, field.type, row, i);
            }

            return model;
        }

        fn get_field_value(allocator: std.mem.Allocator, comptime T: type, row: anytype, index: usize) !T {
            return switch (@typeInfo(T)) {
                .int, .float, .bool => row.get(T, index),
                .pointer => |ptr_info| blk: {
                    if (ptr_info.size == .slice and ptr_info.child == u8) {
                        const str = row.get([]const u8, index);
                        break :blk try allocator.dupe(u8, str);
                    }
                    @compileError("Unsupported pointer type: " ++ @typeName(T));
                },
                .optional => |opt_info| blk: {
                    if (row.get(T, index)) |_| {
                        break :blk try get_field_value(allocator, opt_info.child, row, index);
                    }
                    break :blk null;
                },
                else => @compileError("Unsupported field type: " ++ @typeName(T)),
            };
        }

        fn should_skip_field(comptime field_name: []const u8) bool {
            const field_enum = comptime std.meta.stringToEnum(std.meta.FieldEnum(Model), field_name);

            if (field_enum) |enum_val| {
                const field_info = comptime std.meta.fieldInfo(Model, enum_val);
                if (comptime utils.is_relation(field_info.type)) {
                    return true;
                }
            }

            return utils.should_skip_field(Model, field_name);
        }

        fn get_column_name(comptime field_name: []const u8) []const u8 {
            return utils.get_column_name(Model, field_name);
        }

        fn load_relation(allocator: std.mem.Allocator, conn: *pg.Conn, models: []Model, comptime relation_name: []const u8) !void {
            const field_enum = comptime std.meta.stringToEnum(std.meta.FieldEnum(Model), relation_name) orelse @compileError("invalid relation name");
            const field = comptime std.meta.fieldInfo(Model, field_enum);
            const RelatedType = field.type;

            const RelatedModel = switch (@typeInfo(RelatedType)) {
                .pointer => |p| p.child,
                .optional => |o| switch (@typeInfo(o.child)) {
                    .pointer => |p| p.child,
                    else => {
                        // hasOne/belongsTo on optional field. Not yet supported.
                        return;
                    }
                },
                else => {
                    // hasOne/belongsTo on non-optional field. Not yet supported.
                    return;
                }
            };

            const RelatedMapper = Map(RelatedModel, driver);
            const related_mapper = RelatedMapper{};

            var parent_model_name_lower = std.ArrayList(u8){};
            defer parent_model_name_lower.deinit(allocator);
            try parent_model_name_lower.appendSlice(allocator, @typeName(Model));
            std.ascii.lowerInPlace(parent_model_name_lower.items);

            const fk_name = try std.fmt.allocPrint(allocator, "{s}_id", .{parent_model_name_lower.items});
            defer allocator.free(fk_name);

            comptime {
                if (!std.meta.hasField(RelatedModel, fk_name)) {
                    @compileError("Relation error: " ++ @typeName(RelatedModel) ++ " is missing foreign key " ++ fk_name);
                }
            }

            if (models.len == 0) return;

            const PkType = @TypeOf(models[0].id);
            var parent_ids = std.ArrayList(PkType){};
            defer parent_ids.deinit(allocator);
            for (models) |*model| {
                try parent_ids.append(allocator, model.id);
            }

            const related_table_name = utils.get_table_name(RelatedModel);
            var sql_builder = std.ArrayList(u8){};
            defer sql_builder.deinit(allocator);
            const writer = sql_builder.writer();

            try writer.print("SELECT * FROM {s} WHERE {s} IN (", .{ related_table_name, fk_name });
            for (parent_ids.items, 0..) |id, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{}", .{id});
            }
            try writer.print(")", .{});

            const sql = try sql_builder.toOwnedSlice(allocator);
            defer allocator.free(sql);

            var result = try conn.query(sql, .{});
            defer result.deinit();

            var all_related_models = std.ArrayList(RelatedModel){};
            defer all_related_models.deinit(allocator);

            while (try result.next()) |row| {
                const related_model = try related_mapper.row_to_model(allocator, row);
                try all_related_models.append(allocator, related_model);
            }

            var grouped_related = std.HashMap(PkType, std.ArrayList(RelatedModel), std.hash_map.AutoContext(PkType), std.hash_map.default_max_load_percentage){};
            defer {
                var it = grouped_related.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                grouped_related.deinit(allocator);
            }
            try grouped_related.init(allocator);

            for (all_related_models.items) |*related_model| {
                const parent_id = @field(related_model, fk_name);
                var gop = try grouped_related.getOrPut(allocator, parent_id);
                if (!gop.found_existing) {
                    gop.value_ptr.* = .{};
                }
                try gop.value_ptr.append(allocator, related_model.*);
            }

            for (models) |*model| {
                if (grouped_related.get(model.id)) |*related_list| {
                    @field(model, relation_name) = try related_list.toOwnedSlice(allocator);
                } else {
                    @field(model, relation_name) = try allocator.alloc(RelatedModel, 0);
                }
            }
        }
    };
}
