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

fn printRun(cwd: []const u8, argv: []const []const u8) void {
    var msg = std.ArrayList(u8).init(allocator);
    defer msg.deinit();
    const writer = msg.writer();
    var prefix: []const u8 = "";
    for (argv) |arg| {
        writer.print("{s}\"{s}\"", .{prefix, arg}) catch @panic("memory");
        prefix = " ";
    }
    std.log.info("[RUN] cd \"{s}\" && {s}", .{cwd, msg.items});
}
fn run(cwd: []const u8, argv: []const []const u8) []u8 {
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

fn msvc(args: [][:0]const u8) !u8 {
    if (args.len != 0) {
        std.log.err("msvc toolchain does not take any arguments", .{});
        return 1;
    }

    var lib_dir = try findLibDir(null);
    defer lib_dir.handle.close();

    const cwd = try std.process.getCwdAlloc(allocator);
    var build_dir = findBuildDir(cwd) orelse Directory{ .path = cwd, .handle = std.fs.cwd() };
    defer build_dir.handle.close();
    std.log.info("installing msvc toolchain to '{s}'", .{build_dir.path});

    try build_dir.handle.makePath("zig-cache");

    const msvc_path = try std.fs.path.join(allocator, &[_][]const u8 {build_dir.path, "zig-cache", "msvc-toolchain"});
    defer allocator.free(msvc_path);
    try std.fs.cwd().makePath(msvc_path);

    const msvc_bin_path = try std.fs.path.join(allocator, &[_][]const u8 {msvc_path, "bin"});
    defer allocator.free(msvc_bin_path);
    try std.fs.cwd().makePath(msvc_bin_path);

    const msvc_src_path = try std.fs.path.join(allocator, &[_][]const u8 {msvc_path, "src"});
    defer allocator.free(msvc_src_path);
    try std.fs.cwd().makePath(msvc_src_path);
    {
        const cl_zig_path = try std.fs.path.join(allocator, &[_][]const u8 {lib_dir.path, "cl.zig"});
        defer allocator.free(cl_zig_path);

        var zig_args = std.ArrayList([]const u8).init(allocator);
        defer zig_args.deinit();
        try zig_args.append("zig");
        try zig_args.append("build-exe");
        try zig_args.append("--name");
        try zig_args.append("cl");
        try zig_args.append("--single-threaded");
        try zig_args.append("--enable-cache");

        const cache_path = try std.fs.path.join(allocator, &[_][]const u8 {msvc_src_path, "zig-cache"});
        defer allocator.free(cache_path);
        try std.fs.cwd().makePath(cache_path);
        try zig_args.append("--cache-dir");
        try zig_args.append(cache_path);

        try zig_args.append(cl_zig_path);

        printRun(msvc_src_path, zig_args.items);
        const exe_cache_path_nl = run(msvc_src_path, zig_args.items);
        defer allocator.free(exe_cache_path_nl);
        const exe_cache_path = std.mem.trimRight(u8, exe_cache_path_nl, "\r\n");

        var dest_dir = try std.fs.cwd().openDir(msvc_bin_path, .{});
        defer dest_dir.close();

        var exe_cache_dir = try std.fs.cwd().openDir(exe_cache_path, .{ .iterate = true });
        defer exe_cache_dir.close();
        var exe_cache_dir_it = exe_cache_dir.iterate();
        while (try exe_cache_dir_it.next()) |entry| {

            // The compiler can put these files into the same directory, but we don't
            // want to copy them over.
            if (   !std.mem.startsWith(u8, entry.name, "cl.")
                or std.mem.endsWith(u8, entry.name, ".id")
                or std.mem.endsWith(u8, entry.name, ".zig")
                or std.mem.endsWith(u8, entry.name, ".txt")
                or std.mem.endsWith(u8, entry.name, ".o")
                or std.mem.endsWith(u8, entry.name, ".obj")
            ) continue;
            std.log.info("installing '{s}'", .{entry.name});
            _ = try exe_cache_dir.updateFile(entry.name, dest_dir, entry.name, .{});
        }
    }


    const zig_toolchain_env_path = try std.fs.path.join(allocator, &[_][]const u8 {msvc_bin_path, "zig-env.bat"});
    defer allocator.free(zig_toolchain_env_path);
    {
        var zig_env_bat = try std.fs.cwd().createFile(zig_toolchain_env_path, .{});
        defer zig_env_bat.close();
        const writer = zig_env_bat.writer();
        try writer.print("set PATH=%~dp0;%PATH%\n", .{});
        try writer.print("set Platform=x64\n", .{});
    }

    const stdout = std.io.getStdOut().writer();
    // TODO: check if this path is already in the PATH
    try stdout.print("\n", .{});
    try stdout.print("Run the following to setup the environment in a BATCH shell:\n", .{});
    try stdout.print("{s}\n", .{zig_toolchain_env_path});

    return 0;
}

