const std = @import("std");

var global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = &global_arena.allocator;

const TodoIgnore = struct {
    starts_with: []const u8,
    description: []const u8,
};
const todo_ignores = [_]TodoIgnore {
    .{ .starts_with = "-W", .description = "set warning level" },
    .{ .starts_with = "-Z7", .description = "enable old-style debug info" },
    .{ .starts_with = "-GS", .description = "enable security checks" },
    .{ .starts_with = "-Gs", .description = "control stack checking calls" },
};

pub fn main() !u8 {
    //const verbose = true;

    var args = try std.process.argsAlloc(allocator);
    // no need to free args
    if (args.len <= 1) {
        std.debug.print(
            \\Zig emulation of the MSVC C/C++ compiler cl.exe
            \\Usage: cl <args>...
            \\
            , .{}
        );
        //return 1; // compiler doesn't let me do this
        std.os.exit(0xff);
    }
    args = args[1..];

    var zig_args = std.ArrayList([]const u8).init(allocator);

    try zig_args.append("zig");
    try zig_args.append("cc");

    var args_index: usize = 0;
    args_loop: while (args_index < args.len) : (args_index += 1) {
        const arg = args[args_index];
        // just a hack for now
        if (arg[0] == '/') arg[0] = '-';

        if (!std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.endsWith(u8, arg, ".cpp")) {
                zig_args.items[1] = "c++";
                try zig_args.append(arg);
            } else if (std.mem.endsWith(u8, arg, ".c")) {
                try zig_args.append(arg);
            } else {
                std.log.warn("cl(zig-toolchain): unknown non-option argument '{s}'", .{arg});
                try zig_args.append(arg);
            }
        } else if (std.mem.eql(u8, arg, "-nologo")) {
            // ignore
        } else if (std.mem.startsWith(u8, arg, "-D")) {
            try zig_args.append(arg);
        } else if (std.mem.eql(u8, arg, "-Od")) {
            try zig_args.append("-cl-opt-disable");
        } else if (std.mem.startsWith(u8, arg, "-Fe")) {
            try zig_args.append("-o");
            try zig_args.append(arg[2..]);
        } else if (std.mem.eql(u8, arg, "-link")) {
            const result = try parseLinkArgs(args[args_index+1..], &zig_args);
            if (result != 0) return result;
            break;
        } else {
            for (todo_ignores) |todo_ignore| {
                if (std.mem.startsWith(u8, arg, todo_ignore.starts_with)) {
                    std.log.info("todo: not sure how to translate '{s}' ({s})", .{arg, todo_ignore.description});
                    continue :args_loop;
                }
            }

            std.log.warn("cl(zig-toolchain): unknown cl argument '{s}'", .{arg});
            try zig_args.append(arg);
        }
    }

    // Add msvc specific stuff
    // TODO: only add this for the applicable target
    try zig_args.append("-D_M_X64");

    // TODO: use execve on posix platforms
    printRun(zig_args.items);
    const child = try std.ChildProcess.init(zig_args.items, allocator);
    defer child.deinit();

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.spawn() catch |err| {
        std.log.err("zig cc failed with {s}", .{@errorName(err)});
        std.os.exit(0xff);
    };
    const result = child.wait() catch |err| {
        std.log.err("failed to wait for zig cc: {s}", .{@errorName(err)});
        std.os.exit(0xff);
    };
    switch (result) {
        .Exited => |code| std.os.exit(code),
        else => {
            std.log.err("zig cc failed with: {}", .{result});
            std.os.exit(0xff);
        },
    }
}

fn parseLinkArgs(args: []const []u8, zig_args: *std.ArrayList([]const u8)) !u8 {
    var args_index: usize = 0;
    while (args_index < args.len) : (args_index += 1) {
        const arg = args[args_index];
        // just a hack for now
        if (arg[0] == '/') arg[0] = '-';

        if (!std.mem.startsWith(u8, arg, "-")) {
            if (false) {
            } else {
                std.log.warn("cl(zig-toolchain): unknown non-option link argument '{s}'", .{arg});
                try zig_args.append("-Xlinker");
                try zig_args.append(arg);
            }
        } else {
            std.log.warn("cl(zig-toolchain): unknown cl link argument '{s}'", .{arg});
            try zig_args.append("-Xlinker");
            try zig_args.append(arg);
        }
    }
    return 0;
}

// TODO: put this somewhere common
fn printRun(argv: []const []const u8) void {
    var msg = std.ArrayList(u8).init(allocator);
    defer msg.deinit();
    const writer = msg.writer();
    var prefix: []const u8 = "";
    for (argv) |arg| {
        writer.print("{s}\"{s}\"", .{prefix, arg}) catch @panic("memory");
        prefix = " ";
    }
    std.log.info("[RUN] {s}", .{msg.items});
}
