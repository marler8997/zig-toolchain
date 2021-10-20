const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-toolchain", "zig-toolchain.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const install_msvc = std.build.RunStep.create(b, "run zig-toolchain msvc");
    install_msvc.addArtifactArg(exe);
    install_msvc.addArg("msvc");
    install_msvc.step.dependOn(b.getInstallStep());
    b.step("verify", "Verify the toolchains install").dependOn(&install_msvc.step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var exe_tests = b.addTest("zig-toolchain.zig");
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
