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
                rawFileMod(b, "examples/tables.hdoc"),
                rawFileMod(b, "examples/featurematrix.hdoc"),
                rawFileMod(b, "examples/demo.hdoc"),
                rawFileMod(b, "examples/guide.hdoc"),
                rawFileMod(b, "test/parser/stress.hdoc"),
            },
        }),
        .use_llvm = true,
    });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hyperdoc", .module = hyperdoc },
            },
        }),
        .use_llvm = true,
    });
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
}

fn rawFileMod(b: *std.Build, path: []const u8) std.Build.Module.Import {
    return .{
        .name = path,
        .module = b.createModule(.{
            .root_source_file = b.path(path),
        }),
    };
}
