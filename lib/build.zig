const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    try addMsvc(b, mode);
}

fn addMsvc(b: *Builder, mode: std.builtin.Mode) !void {

    const msvc = b.step("msvc", "build the msvc toolchain");

    {
        const cl = b.addExecutable("cl", "cl.zig");
        cl.setBuildMode(mode);
        cl.install();
        msvc.dependOn(&cl.install_step.?.step);
    }
    {
        const zig_env_step = GenerateEnvBatStep.create(b);
        msvc.dependOn(&zig_env_step.step);
    }
}

const GenerateEnvBatStep = struct {
    step: std.build.Step,
    dest_path: []const u8,
    pub fn create(b: *Builder) *GenerateEnvBatStep {
        var result = b.allocator.create(GenerateEnvBatStep) catch unreachable;
        result.* = .{
            .step = std.build.Step.init(.custom, "generate zig-env.bat", b.allocator, make),
            .dest_path = b.getInstallPath(.bin, "zig-env.bat"),
        };
        return result;
    }
    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(GenerateEnvBatStep, "step", step);
        const file = try std.fs.cwd().createFile(self.dest_path, .{});
        defer file.close();
        const writer = file.writer();
        try writer.print("set PATH=%~dp0;%PATH%\n", .{});
        try writer.print("set Platform=x64\n", .{});
    }
};
