// this is code copied from the zig repo, src/introspect.zig
const std = @import("std");
const mem = std.mem;
const fs = std.fs;

const Directory = @import("Directory.zig");

/// Returns the sub_path that worked, or `null` if none did.
/// The path of the returned Directory is relative to `base`.
/// The handle of the returned Directory is open.
fn testZigToolchainInstallPrefix(base_dir: fs.Dir) ?Directory {
    const test_index_file = "cl.zig";

    var test_zig_dir = base_dir.openDir("lib", .{}) catch return null;
    const file = test_zig_dir.openFile(test_index_file, .{}) catch {
        test_zig_dir.close();
        return null;
    };
    file.close();
    return Directory{ .handle = test_zig_dir, .path = "lib" };
}

/// Both the directory handle and the path are newly allocated resources which the caller now owns.
pub fn findZigLibDirFromSelfExe(
    allocator: *mem.Allocator,
    self_exe_path: []const u8,
) error{ OutOfMemory, FileNotFound }!Directory {
    const cwd = fs.cwd();
    var cur_path: []const u8 = self_exe_path;
    while (fs.path.dirname(cur_path)) |dirname| : (cur_path = dirname) {
        var base_dir = cwd.openDir(dirname, .{}) catch continue;
        defer base_dir.close();

        const sub_directory = testZigToolchainInstallPrefix(base_dir) orelse continue;
        return Directory{
            .handle = sub_directory.handle,
            .path = try fs.path.join(allocator, &[_][]const u8{ dirname, sub_directory.path }),
        };
    }
    return error.FileNotFound;
}
