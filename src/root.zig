pub const ParseArgsOptions = struct {
    bool_true_prefix: []const u8 = "",
    bool_false_prefix: []const u8 = "no-",
};

const Argument = union(enum) {
    bool: struct {
        name: [:0]const u8,
        default: ?bool,
        short_true: ?u8 = null,
        short_false: ?u8 = null,
        long: ?union(enum) {
            auto: []const u8,
            manual: struct { true: ?[]const u8 = null, false: ?[]const u8 = null },
        } = null,
    },
};

fn Result(comptime args_decl: []const Argument) type {
    comptime var fields: []const std.builtin.Type.StructField = &.{};
    comptime for (args_decl) |argument| {
        switch (argument) {
            .bool => |b| fields = fields ++ &[_]std.builtin.Type.StructField{.{
                .name = b.name,
                .type = bool,
                .default_value_ptr = &b.default.?,
                .is_comptime = false,
                .alignment = @alignOf(bool),
            }},
        }
    };

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn parseArgs(
    comptime _args_decl: []const Argument,
    inputs: []const [:0]const u8,
    comptime options: ParseArgsOptions,
) std.meta.Tuple(&.{ Result(_args_decl), std.StaticBitSet(_args_decl.len) }) {
    var result: Result(_args_decl) = .{};
    var unused = std.StaticBitSet(_args_decl.len).initFull();
    const args = comptime block: {
        var seen_short_args: []const u8 = &.{};
        var seen_long_args: []const []const u8 = &.{};
        var args_decl: []const Argument = &.{};
        for (_args_decl) |argument| switch (argument) {
            .bool => |b| {
                var new: Argument = .{ .bool = .{
                    .name = b.name,
                    .default = b.default,
                    .short_true = b.short_true,
                    .short_false = b.short_false,
                } };

                if (b.long) |long| switch (long) {
                    .auto => |auto| {
                        new.bool.long = .{ .manual = .{
                            .true = options.bool_true_prefix ++ auto,
                            .false = options.bool_false_prefix ++ auto,
                        } };
                    },
                    .manual => {},
                };

                if (new.bool.short_true) |t| {
                    if (std.mem.containsAtLeastScalar(u8, seen_short_args, 1, t))
                        @compileError("Found duplicate short option " ++ &[_]u8{t});
                    seen_short_args = seen_short_args ++ &[_]u8{t};
                }
                if (new.bool.short_false) |f| {
                    if (std.mem.containsAtLeastScalar(u8, seen_short_args, 1, f))
                        @compileError("Found duplicate short option " ++ &[_]u8{f});
                    seen_short_args = seen_short_args ++ &[_]u8{f};
                }
                if (new.bool.long) |long| if (long.manual.true) |t|
                    for (seen_long_args) |seen| {
                        if (std.mem.eql(u8, seen, t))
                            @compileError("Found duplicate long option " ++ t);
                        seen_long_args = seen_long_args ++ t;
                    };
                if (new.bool.long) |long| if (long.manual.false) |f|
                    for (seen_long_args) |seen| {
                        if (std.mem.eql(u8, seen, f))
                            @compileError("Found duplicate long option " ++ f);
                        seen_long_args = seen_long_args ++ f;
                    };

                args_decl = args_decl ++ &[_]Argument{new};
            },
        };

        break :block args_decl;
    };

    for (inputs, 0..) |input, index| inline for (args) |argument| switch (argument) {
        .bool => |b| {
            if (input.len > 2 and std.mem.eql(u8, "--", input[0..2])) {
                if (b.long) |long| {
                    if (std.mem.eql(u8, long.manual.true.?, input[2..])) {
                        @field(result, b.name) = true;
                        unused.unset(index);
                    }
                    if (std.mem.eql(u8, long.manual.false.?, input[2..])) {
                        @field(result, b.name) = false;
                        unused.unset(index);
                    }
                }
            }

            if (input.len >= 2 and input[0] == '-') {
                if (b.short_true) |t| {
                    if (std.mem.containsAtLeastScalar(u8, input[1..], 1, t)) {
                        @field(result, b.name) = true;
                        unused.unset(index);
                    }
                }
                if (b.short_false) |f| {
                    if (std.mem.containsAtLeastScalar(u8, input[1..], 1, f)) {
                        @field(result, b.name) = false;
                        unused.unset(index);
                    }
                }
            }
        },
    };

    return .{ result, unused };
}

test {
    {
        const actual, const unused = parseArgs(
            &[_]Argument{
                .{ .bool = .{
                    .name = "blep",
                    .default = true,
                    .short_true = 'b',
                    .short_false = 'B',
                    .long = .{ .auto = "lol" },
                } },
                .{ .bool = .{
                    .name = "mlem",
                    .default = false,
                    .long = .{ .auto = "lol" },
                    .short_true = 'm',
                } },
            },
            &[_][:0]const u8{"-B -m"},
            .{},
        );
        _ = unused;
        try std.testing.expectEqual(@TypeOf(actual){ .blep = false, .mlem = true }, actual);
    }
}

const std = @import("std");
