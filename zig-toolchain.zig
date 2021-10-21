const std = @import("std");

const Directory = @import("Directory.zig");
const introspect = @import("introspect.zig");

var global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = &global_arena.allocator;

pub fn main() !u8 {
    var args = try std.process.argsAlloc(allocator);
    // no need to free args
    if (args.len <= 1) {
        std.debug.print(
            \\Usage: zig-toolchain <toolchain>
            \\
            \\Toolchains:
            \\    msvc     The Micrsofot Visual C/C++ Toolchain.
            \\
            , .{}
        );
        //return 1; // compiler doesn't let me do this
        std.os.exit(0xff);
    }
    const toolchain = args[1];
    args = args[2..];
    if (std.mem.eql(u8, toolchain, "msvc"))
        return msvc(args);
    std.log.err("unknown toolchain '{s}'", .{toolchain});
    //return 1; // compiler doesn't let me do this
    std.os.exit(0xff);
}

// NOTE: this code was copied from the zig compiler in main.zig cmdBuild
//       maybe it should be in std?
fn findBuildDir(cwd: []const u8) ?Directory {
    // Search up parent directories until we find build.zig.
    var dirname = cwd;
    while (true) {
        const joined_path = std.fs.path.join(allocator, &[_][]const u8{ dirname, "build.zig" }) catch @panic("memory");
        defer allocator.free(joined_path);
        if (std.fs.cwd().access(joined_path, .{})) |_| {
            const dir = std.fs.cwd().openDir(dirname, .{}) catch |err|
                fatal("unable to open directory while searching for build.zig file, '{s}': {s}", .{ dirname, @errorName(err) });

            return Directory{ .path = dirname, .handle = dir };
        } else |err| switch (err) {
            error.FileNotFound => {
                dirname = std.fs.path.dirname(dirname) orelse return null;
                continue;
            },
            else => |e| fatal("failed to access '{s}': {s}", .{joined_path, @errorName(e)}),
        }
    }
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.os.exit(0xff);
}

fn findLibDir(override_lib_dir: ?[]const u8) !Directory {
    const self_exe_path = try std.fs.selfExePathAlloc(allocator);
    return if (override_lib_dir) |lib_dir| .{
        .path = lib_dir,
        .handle = std.fs.cwd().openDir(lib_dir, .{}) catch |err| {
            fatal("unable to open zig-toolchain lib directory from 'zig-lib-dir' argument or env, '{s}': {s}", .{ lib_dir, @errorName(err) });
        },
    } else introspect.findZigLibDirFromSelfExe(allocator, self_exe_path) catch |err| {
        fatal("unable to find zig-toolchain lib directory from exe path '{s}': {s}\n", .{self_exe_path, @errorName(err)});
    };
}

fn printRun(optional_cwd: ?[]const u8, argv: []const []const u8) void {
    var msg = std.ArrayList(u8).init(allocator);
    defer msg.deinit();
    const writer = msg.writer();
    var prefix: []const u8 = "";
    for (argv) |arg| {
        writer.print("{s}\"{s}\"", .{prefix, arg}) catch @panic("memory");
        prefix = " ";
    }
    if (optional_cwd) |cwd| {
        std.log.info("[RUN] cd \"{s}\" && {s}", .{cwd, msg.items});
    } else {
        std.log.info("[RUN] {s}", .{msg.items});
    }
}
fn runNoCapture(error_context: []const u8, cwd: ?[]const u8, argv: []const []const u8) void {
    const child = std.ChildProcess.init(argv, allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("memory"),
    };
    defer child.deinit();

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.cwd = cwd;

    child.spawn() catch |err|
        fatal("{s} failed with {s}", .{error_context, @errorName(err)});
    const result = child.wait() catch |err|
        fatal("failed to wait for {s}: {s}", .{error_context, @errorName(err)});

    switch (result) {
        .Exited => |code| if (code != 0)
            fatal("{s} failed with exit code {}", .{error_context, code}),
        else => fatal("{s} crashed with: {}", .{error_context, result}),
    }
}
fn run(cwd: ?[]const u8, argv: []const []const u8) []u8 {
    const child = std.ChildProcess.init(argv, allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("memory"),
    };
    defer child.deinit();

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.cwd = cwd;

    child.spawn() catch |err|
        fatal("{s} failed with {s}", .{argv[0], @errorName(err)});

    const stdout = child.stdout.?.reader().readAllAlloc(allocator, 1024 * 1024) catch |err|
        fatal("failed to read stdout from {s}: {s}", .{argv[0], @errorName(err)});

    errdefer allocator.free(stdout);

    const result = child.wait() catch |err|
        fatal("failed to wait for {s}: {s}", .{argv[0], @errorName(err)});

    switch (result) {
        .Exited => |code| if (code != 0)
            fatal("{s} failed with exit code {}", .{argv[0], code}),
        else => fatal("{s} failed with: {}", .{argv[0], result}),
    }
    return stdout;
}

fn buildToolchain(toolchain_name: []const u8) !void {
    var lib_dir = try findLibDir(null);
    defer lib_dir.handle.close();

    const cwd = try std.process.getCwdAlloc(allocator);
    var build_dir = findBuildDir(cwd) orelse Directory{ .path = cwd, .handle = std.fs.cwd() };
    defer build_dir.handle.close();
    std.log.info("installing {s} toolchain to '{s}'", .{toolchain_name, build_dir.path});

    const cache_root = try std.fs.path.join(allocator, &[_][]const u8 {build_dir.path, "zig-cache" });
    defer allocator.free(cache_root);

    const toolchain_path = try std.fs.path.join(allocator, &[_][]const u8 { cache_root, "toolchain", toolchain_name});
    defer allocator.free(toolchain_path);
    try std.fs.cwd().makePath(toolchain_path);

    {
        const build_file = try std.fs.path.join(allocator, &[_][]const u8 {lib_dir.path, "build.zig"});
        defer allocator.free(build_file);

        var zig_args = std.ArrayList([]const u8).init(allocator);
        defer zig_args.deinit();
        try zig_args.append("zig");
        try zig_args.append("build");
        try zig_args.append("--prefix");
        try zig_args.append(toolchain_path);
        try zig_args.append("--build-file");
        try zig_args.append(build_file);
        try zig_args.append(toolchain_name);
        try zig_args.append("--cache-dir");
        try zig_args.append(cache_root);

        printRun(null, zig_args.items);
        runNoCapture("zig build toolchain", null, zig_args.items);
    }

    const zig_env_bat = try std.fs.path.join(allocator, &[_][]const u8 { toolchain_path, "bin", "zig-env.bat" });
    defer allocator.free(zig_env_bat);

    const stdout = std.io.getStdOut().writer();
    // TODO: check if this path is already in the PATH
    try stdout.print("\n", .{});
    try stdout.print("Run the following to setup the environment in a BATCH shell:\n", .{});
    try stdout.print("{s}\n", .{zig_env_bat});
}


fn msvc(args: [][:0]const u8) !u8 {
    if (args.len != 0) {
        std.log.err("msvc toolchain does not take any arguments", .{});
        return 1;
    }

    try buildToolchain("msvc");
    return 0;
}
