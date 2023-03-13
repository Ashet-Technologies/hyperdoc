const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parser_toolkit = b.dependency("parser_toolkit", .{});
    const args = b.dependency("args", .{});

    const hyperdoc = b.addModule("hyperdoc", .{
        .source_file = .{ .path = "src/hyperdoc.zig" },
        .dependencies = &.{
            .{ .name = "parser-toolkit", .module = parser_toolkit.module("parser-toolkit") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "hyperdoc",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("hyperdoc", hyperdoc);
    exe.addModule("args", args.module("args"));

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |arg| {
        run_cmd.addArgs(arg);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/testsuite.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe_tests.addModule("hyperdoc", hyperdoc);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
