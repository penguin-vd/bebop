const std = @import("std");
const pg = @import("pg");

pub fn getTableName(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    const input = @typeName(Model);
    const result = try allocator.alloc(u8, input.len);
    for (input, 0..) |char, i| {
        if (char == '.') {
            result[i] = '_';
        } else {
            result[i] = std.ascii.toLower(char);
        }
    }

    return result;
}

pub fn toSqlType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => |int_info| {
            if (int_info.bits <= 32) return "INTEGER";
            return "BIGINT";
        },
        .float => "REAL",
        .bool => "BOOLEAN",
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return "TEXT";
            }
            return "BLOB";
        },
        .optional => |opt_info| toSqlType(opt_info.child),
        else => "TEXT",
    };
}

pub fn ensureMigrationsTable(db: *pg.Pool) !void {
    const sql = "CREATE TABLE IF NOT EXISTS schema_migrations (id SERIAL PRIMARY KEY, migration_name VARCHAR(255) NOT NULL UNIQUE, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())";

    var conn = try db.acquire();
    defer conn.release();

    _ = try conn.exec(sql, .{});
}

pub const TableInformation = struct {
    column: []const u8,
    type: []const u8,
};

pub fn getTableInformation(allocator: std.mem.Allocator, conn: *pg.Conn, table_name: []const u8) !std.ArrayList(TableInformation) {
    const sql =
        \\SELECT column_name, data_type, character_maximum_length
        \\FROM INFORMATION_SCHEMA.COLUMNS
        \\WHERE table_name = $1;
    ;
    var result = try conn.query(sql, .{table_name});
    defer result.deinit();

    var array: std.ArrayList(TableInformation) = .{};

    while (try result.next()) |row| {
        const t = row.get([]const u8, 1);
        const tUpper = try allocator.alloc(u8, t.len);
        for (t, 0..) |char, i| {
            tUpper[i] = std.ascii.toLower(char);
        }

        const c = row.get([]const u8, 0);
        const cClone = try allocator.dupe(u8, c);
        try array.append(allocator, .{
            .type = tUpper,
            .column = cClone,
        });
    }

    return array;
}

pub fn FieldMeta(comptime T: type) type {
    _ = T;
    return struct {
        is_primary_key: bool = false,
        is_unique: bool = false,
        is_auto_increment: bool = false,
        max_length: ?usize = null,
        column_name: ?[]const u8 = null,
        default_value: ?[]const u8 = null,
    };
}

pub fn getFieldMeta(comptime Model: type, comptime field_name: []const u8) ?FieldMeta(void) {
    if (!@hasDecl(Model, "field_meta")) {
        return null;
    }

    const meta_decl = @field(Model, "field_meta");
    const meta_type_info = @typeInfo(@TypeOf(meta_decl));

    if (meta_type_info != .@"struct") {
        return null;
    }

    inline for (meta_type_info.@"struct".fields) |meta_field| {
        if (std.mem.eql(u8, meta_field.name, field_name)) {
            return @field(meta_decl, field_name);
        }
    }

    return null;
}

pub fn typeMatches(model_type: []const u8, db_type: []const u8) bool {
    if (std.mem.eql(u8, model_type, "INTEGER") and
        (std.mem.eql(u8, db_type, "integer") or std.mem.eql(u8, db_type, "int4")))
    {
        return true;
    }
    if (std.mem.eql(u8, model_type, "BIGINT") and
        (std.mem.eql(u8, db_type, "bigint") or std.mem.eql(u8, db_type, "int8")))
    {
        return true;
    }

    if (std.mem.eql(u8, model_type, "TEXT") and
        (std.mem.eql(u8, db_type, "text") or std.mem.eql(u8, db_type, "character varying")))
    {
        return true;
    }

    if (std.mem.eql(u8, model_type, "REAL") and
        (std.mem.eql(u8, db_type, "real") or std.mem.eql(u8, db_type, "float4")))
    {
        return true;
    }

    if (std.mem.eql(u8, model_type, "BOOLEAN") and
        (std.mem.eql(u8, db_type, "boolean") or std.mem.eql(u8, db_type, "bool")))
    {
        return true;
    }

    return std.mem.eql(u8, model_type, db_type);
}

pub fn getDefaultValue(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => "0",
        .float => "0.0",
        .bool => "false",
        .pointer => "''",
        .optional => "NULL",
        else => "''",
    };
}

pub fn getFieldList(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    var fields = std.ArrayList(u8){};
    defer fields.deinit(allocator);
    
    const type_info = @typeInfo(Model);
    const struct_info = type_info.@"struct";
    
    inline for (struct_info.fields, 0..) |field, i| {
        const meta = getFieldMeta(Model, field.name);
        const column_name = if (meta) |m| m.column_name orelse field.name else field.name;
        
        try fields.appendSlice(allocator, column_name);
        
        if (i < struct_info.fields.len - 1) {
            try fields.appendSlice(allocator, ", ");
        }
    }
    
    return fields.toOwnedSlice(allocator);
}
