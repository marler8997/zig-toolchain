const std = @import("std");
const Directory = @This();

path: []const u8,
handle: std.fs.Dir,