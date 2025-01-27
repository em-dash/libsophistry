pub const ParseArgsOptions = struct {};

fn ParseArgsReturnType(args_decl: anytype) type {
    var names: []const [:0]const u8 = &.{};

    for (@typeInfo(@TypeOf(args_decl)).@"struct".fields) |f| {
        names = names ++ .{f.name};
    }
    var fields: []const std.builtin.Type.StructField = &.{};
    for (names) |n| {
        const input = @field(args_decl, n);
        const field_type = if (@hasField(@TypeOf(input), "type")) input.type else u32;
        const struct_field: std.builtin.Type.StructField = .{
            .name = n,
            .type = field_type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(field_type),
        };
        // TODO check the input here cause it will suck later if we didn't
        fields = fields ++ .{struct_field};
    }

    const result: std.builtin.Type = .{ .@"struct" = .{
        .layout = .auto,
        .fields = fields,
        .decls = &[0]std.builtin.Type.Declaration{},
        .is_tuple = false,
    } };
    return @Type(result);
}

pub fn parseArgs(
    args_decl: anytype,
    args: [][:0]const u8,
    options: ParseArgsOptions,
) !ParseArgsReturnType(args_decl) {
    comptime {
        var seen_short_flags: []const u8 = &.{};
        for (std.meta.fieldNames(@TypeOf(args_decl))) |f| {
            const arg = @field(args_decl, f);
            if (@hasField(@TypeOf(arg), "short"))
                seen_short_flags = seen_short_flags ++ .{arg.short};
        }
    }
    _ = options;
    _ = args;
    const ReturnType = ParseArgsReturnType(args_decl);
    _ = ReturnType;
    // var result: ReturnType = undefined;
    // for (@typeInfo(args_decl).@"struct".fields) |f| {}

}

const test_args_decl = .{
    .epic_mode = .{
        .long = "epic-mode",
        .short_true = 'e',
        .short_false = 'E',
        .type = bool,
    },
    .blep = .{
        .short = 'b',
    },
    .mlem = .{
        .short = 'm',
    },
};

test {
    return error.SkipZigTest;
    // _ = try parseArgs(test_args_decl, &.{}, .{});
}

const std = @import("std");
