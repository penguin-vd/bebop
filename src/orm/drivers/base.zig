const std = @import("std");

pub const TableInformation = struct {
    column: []const u8,
    type: []const u8,
};

pub const Driver = struct {
    build_list_query: *const fn (allocator: std.mem.Allocator, comptime Model: type) anyerror![]const u8,
    build_insert_query: *const fn (allocator: std.mem.Allocator, comptime Model: type) anyerror![]const u8,
    build_create_table_query: *const fn (allocator: std.mem.Allocator, comptime Model: type) anyerror![]const u8,
    build_alter_table_query: *const fn (allocator: std.mem.Allocator, comptime Model: type, table_info: std.ArrayList(TableInformation)) anyerror![]const u8,
    get_table_information: *const fn (allocator: std.mem.Allocator, conn: anytype, table_name: []const u8) anyerror!std.ArrayList(TableInformation),
    to_sql_type: *const fn (comptime T: type) []const u8,
    type_matches: *const fn (model_type: []const u8, db_type: []const u8) bool,
    get_default_value: *const fn (comptime T: type) []const u8,
    ensure_migrations_table: *const fn (db: anytype) anyerror!void,
    build_list_query_with_filter: *const fn (allocator: std.mem.Allocator, comptime Model: type, filter: anytype) anyerror![]const u8,
};
