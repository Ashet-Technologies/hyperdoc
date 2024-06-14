const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parser_toolkit = b.dependency("parser_toolkit", .{});
    const args = b.dependency("args", .{});

    const hyperdoc = b.addModule(
        "hyperdoc",
        .{
            .root_source_file = b.path("src/hyperdoc.zig"),
        },
    );
    hyperdoc.addImport("parser-toolkit", parser_toolkit.module("parser-toolkit"));

    const exe = b.addExecutable(.{
        .name = "hyperdoc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("hyperdoc", hyperdoc);
    exe.root_module.addImport("args", args.module("args"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |arg| {
        run_cmd.addArgs(arg);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/testsuite.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_tests.root_module.addImport("hyperdoc", hyperdoc);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
