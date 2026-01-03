const std = @import("std");

const test_files: []const []const u8 = &.{
    "test/html5/admonition_blocks.hdoc",
    "test/html5/document_header.hdoc",
    "test/html5/media_and_toc.hdoc",
    "test/html5/nesting_and_inlines.hdoc",
    "test/html5/paragraph_styles.hdoc",
    "test/html5/tables.hdoc",
};

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

    // Snapshot tests:
    for (test_files) |path| {
        std.debug.assert(std.mem.endsWith(u8, path, ".hdoc"));
        const html_file = b.fmt("{s}.html", .{path[0 .. path.len - 5]});
        const yaml_file = b.fmt("{s}.yaml", .{path[0 .. path.len - 5]});

        for (&[2][]const u8{ html_file, yaml_file }) |file| {
            const test_run = b.addRunArtifact(exe);
            test_run.addArgs(&.{ "--format", file[file.len - 4 ..] });
            test_run.addFileArg(b.path(path));
            test_run.expectStdOutEqual(
                b.build_root.handle.readFileAlloc(b.allocator, file, 10 * 1024 * 1024) catch @panic("oom"),
            );
            test_step.dependOn(&test_run.step);
        }
    }

    // Unit tests:
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
                rawFileMod(b, "test/accept/stress.hdoc"),
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
