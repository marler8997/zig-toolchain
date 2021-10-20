const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // we only want to install this directory if we are deploying
    // zig-toolchain, otherwise we want zig-toolchain to use the
    // lib directory in the source path so the errors are pointing
    // to the source file rather than the installed file which will
    // be overwritten.
    // So for now I'm just commenting this out, by the time it matters
    // its possible this code will be upstreamed into zig proper.
    //b.installDirectory(.{
    //    .source_dir = "lib",
    //    .install_dir = .prefix,
    //    .install_subdir = "lib",
    //});

    const exe = b.addExecutable("zig-toolchain", "zig-toolchain.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.override_dest_dir = .prefix;
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
