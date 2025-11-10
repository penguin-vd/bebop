const std = @import("std");
const pg = @import("pg");
const utils = @import("utils.zig");
const Driver = @import("drivers/base.zig").Driver;

pub fn Map(comptime Model: type, driver: Driver) type {
    return struct {
        const Self = @This();
        pub const Filter = utils.QueryFilter(Model);

        pub fn list(_: *const Self, allocator: std.mem.Allocator, conn: *pg.Conn, filter: ?Filter) ![]Model {
            var sql: []const u8 = undefined;
            defer allocator.free(sql);

            var result: *pg.Result = undefined;
            defer result.deinit();

            if (filter) |f| {
                sql = try driver.build_list_query_with_filter(allocator, Model, f);

                result = try conn.query(sql, .{});
            } else {
                const base_sql = try driver.build_list_query(allocator, Model);
                defer allocator.free(base_sql);
                sql = try std.fmt.allocPrint(allocator, "{s};", .{base_sql});
                result = try conn.query(sql, .{});
            }
            
            std.log.info("SQL: {s}\n", .{sql});

            var models: std.ArrayList(Model) = .{};
            errdefer models.deinit(allocator);

            while (try result.next()) |row| {
                const model = try row_to_model(allocator, row);
                try models.append(allocator, model);
            }

            return models.toOwnedSlice(allocator);
        }

        pub fn create(_: *const Self, allocator: std.mem.Allocator, conn: *pg.Conn, model: Model) !Model {
            const insert_sql = try driver.build_insert_query(allocator, Model);
            defer allocator.free(insert_sql);

            var result = try execute_insert_query(conn, model, insert_sql);
            defer result.deinit();

            if (try result.next()) |row| {
                return try row_to_model(allocator, row);
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

                tuple[idx] = @field(model, field.name);
                idx += 1;
            }

            return try conn.query(sql, tuple);
        }

        fn row_to_model(allocator: std.mem.Allocator, row: anytype) !Model {
            var model: Model = undefined;
            const struct_info = @typeInfo(Model).@"struct";

            inline for (struct_info.fields, 0..) |field, i| {
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
                    if (row.isNull(index)) {
                        break :blk null;
                    }
                    break :blk try get_field_value(allocator, opt_info.child, row, index);
                },
                else => @compileError("Unsupported field type: " ++ @typeName(T)),
            };
        }

        fn should_skip_field(comptime field_name: []const u8) bool {
            return utils.should_skip_field(Model, field_name);
        }

        fn get_column_name(comptime field_name: []const u8) []const u8 {
            return utils.get_column_name(Model, field_name);
        }
    };
}
