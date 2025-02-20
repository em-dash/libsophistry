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

/// Parse commandline arguments based on provided declaration.
///
/// Can only fail if `allocator != null`.
pub fn parseArgs(
    /// Required to generate an unused argument list.
    allocator: ?std.mem.Allocator,
    comptime _args_decl: []const Argument,
    inputs: []const [:0]const u8,
    comptime options: ParseArgsOptions,
) !std.meta.Tuple(&.{ Result(_args_decl), []const [:0]const u8 }) {
    var result: Result(_args_decl) = .{};
    // `.toOwnedSlice` called at the end of this function
    var unused: std.ArrayListUnmanaged([:0]const u8) = .empty;
    errdefer if (allocator) |a| unused.deinit(a);
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

    for (inputs) |input| {
        var used_argument: bool = false;
        inline for (args) |argument| {
            switch (argument) {
                .bool => |b| {
                    if (input.len > 2 and std.mem.eql(u8, "--", input[0..2])) {
                        if (b.long) |long| {
                            if (std.mem.eql(u8, long.manual.true.?, input[2..])) {
                                @field(result, b.name) = true;
                                used_argument = true;
                            }
                            if (std.mem.eql(u8, long.manual.false.?, input[2..])) {
                                @field(result, b.name) = false;
                                used_argument = true;
                            }
                        }
                    }

                    if (input.len >= 2 and input[0] == '-') {
                        if (b.short_true) |t| {
                            if (std.mem.containsAtLeastScalar(u8, input[1..], 1, t)) {
                                @field(result, b.name) = true;
                                used_argument = true;
                            }
                        }
                        if (b.short_false) |f| {
                            if (std.mem.containsAtLeastScalar(u8, input[1..], 1, f)) {
                                @field(result, b.name) = false;
                                used_argument = true;
                            }
                        }
                    }
                },
            }
        }
        if (!used_argument) if (allocator) |a| try unused.append(a, input);
    }

    return .{ result, if (allocator) |a| try unused.toOwnedSlice(a) else &[_][:0]const u8{} };
}

test {
    {
        const actual, const unused = try parseArgs(
            std.testing.allocator,
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
            &[_][:0]const u8{ "-B", "-m", "chat", "chien" },
            .{},
        );
        defer std.testing.allocator.free(unused);
        try std.testing.expectEqual(@TypeOf(actual){ .blep = false, .mlem = true }, actual);
    }
}

const std = @import("std");
