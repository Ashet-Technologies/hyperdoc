//!
//! compare <ground truth> <new input>
//!
const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.arena.allocator();

    const argv = try init.minimal.args.toSlice(allocator);
    defer allocator.free(argv);

    if (argv.len != 3) {
        std.debug.print("usage: {s} <ground truth> <new input>\n", .{argv[0]});
        return 2;
    }

    const ground_truth_path = argv[1];
    const new_input_path = argv[2];

    var files_ok = true;
    const ground_truth = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        ground_truth_path,
        allocator,
        .limited(10 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => blk: {
            files_ok = false;
            break :blk "<file not found>";
        },
        else => |e| return e,
    };
    defer allocator.free(ground_truth);

    const new_input = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        new_input_path,
        allocator,
        .limited(10 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => blk: {
            files_ok = false;
            break :blk "<file not found>";
        },
        else => |e| return e,
    };
    defer allocator.free(new_input);

    // Compare full file contents for now. This keeps the snapshot tests simple and
    // uses std.testing's string mismatch reporting.
    std.testing.expectEqualStrings(ground_truth, new_input) catch |err| switch (err) {
        error.TestExpectedEqual => return 1,
    };

    if (!files_ok)
        return 1;

    return 0;
}
