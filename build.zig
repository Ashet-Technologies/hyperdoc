const std = @import("std");

pub fn build(b: *std.Build) void {
    // Options:
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    // Targets:
    const run_step = b.step("run", "Run the app");
    const test_step = b.step("test", "Run unit tests");

    // Build:
    const hyperdoc = b.addModule("hyperdoc", .{
        .root_source_file = b.path("src/hyperdoc.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "hyperdoc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hyperdoc", .module = hyperdoc },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |arg| {
        run_cmd.addArgs(arg);
    }

    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/testsuite.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hyperdoc", .module = hyperdoc },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
