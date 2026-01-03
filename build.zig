const std = @import("std");

const snapshot_files: []const []const u8 = &.{
    "test/snapshot/admonition_blocks.hdoc",
    "test/snapshot/document_header.hdoc",
    "test/snapshot/media_and_toc.hdoc",
    "test/snapshot/nesting_and_inlines.hdoc",
    "test/snapshot/paragraph_styles.hdoc",
    "test/snapshot/tables.hdoc",
    "test/snapshot/footnotes.hdoc",
};

const conformance_accept_files: []const []const u8 = &.{
    "test/conformance/accept/inline_escape.hdoc",
    "test/conformance/accept/title_header_redundant.hdoc",
};

const conformance_reject_files: []const []const u8 = &.{
    "test/conformance/reject/string_cr_escape.hdoc",
    "test/conformance/reject/inline_identifier_dash.hdoc",
    "test/conformance/reject/heading_sequence.hdoc",
    "test/conformance/reject/nested_top_level.hdoc",
    "test/conformance/reject/container_children.hdoc",
    "test/conformance/reject/time_relative_fmt.hdoc",
    "test/conformance/reject/ref_in_heading.hdoc",
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

    const snapshot_diff = b.addExecutable(.{
        .name = "diff",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compare.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    // Snapshot tests:
    for (snapshot_files) |path| {
        std.debug.assert(std.mem.endsWith(u8, path, ".hdoc"));
        const html_file = b.fmt("{s}.html", .{path[0 .. path.len - 5]});
        const yaml_file = b.fmt("{s}.yaml", .{path[0 .. path.len - 5]});

        for (&[2][]const u8{ html_file, yaml_file }) |snapshot_file| {
            const test_run = b.addRunArtifact(exe);
            test_run.addArgs(&.{ "--format", snapshot_file[snapshot_file.len - 4 ..] });
            test_run.addFileArg(b.path(path));
            const generated_file = test_run.captureStdOut();

            const compare_run = b.addRunArtifact(snapshot_diff);
            compare_run.addFileArg(b.path(snapshot_file));
            compare_run.addFileArg(generated_file);

            test_step.dependOn(&compare_run.step);
        }
    }

    // Conformance snapshots: accept cases (YAML only):
    for (conformance_accept_files) |path| {
        std.debug.assert(std.mem.endsWith(u8, path, ".hdoc"));
        const yaml_file = b.fmt("{s}.yaml", .{path[0 .. path.len - 5]});

        const test_run = b.addRunArtifact(exe);
        test_run.addArgs(&.{ "--format", "yaml" });
        test_run.addFileArg(b.path(path));
        const generated_file = test_run.captureStdOut();

        const compare_run = b.addRunArtifact(snapshot_diff);
        compare_run.addFileArg(b.path(yaml_file));
        compare_run.addFileArg(generated_file);

        test_step.dependOn(&compare_run.step);
    }

    // Conformance snapshots: reject cases (diagnostics on stderr, expect exit code 1):
    for (conformance_reject_files) |path| {
        std.debug.assert(std.mem.endsWith(u8, path, ".hdoc"));
        const diag_file = b.fmt("{s}.diag", .{path[0 .. path.len - 5]});

        const test_run = b.addRunArtifact(exe);
        test_run.addFileArg(b.path(path));
        test_run.expectExitCode(1);
        const generated_diag = test_run.captureStdErr();

        const compare_run = b.addRunArtifact(snapshot_diff);
        compare_run.addFileArg(b.path(diag_file));
        compare_run.addFileArg(generated_diag);

        test_step.dependOn(&compare_run.step);
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
