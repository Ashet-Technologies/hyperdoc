//!
//! compare <ground truth> <new input>
//!
const std = @import("std");

var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

const allocator = arena.allocator();

pub fn main() !u8 {
    defer arena.deinit();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len != 3) {
        std.debug.print("usage: {s} <ground truth> <new input>\n", .{argv[0]});
        return 2;
    }

    const ground_truth_path = argv[1];
    const new_input_path = argv[2];

    var files_ok = true;
    const ground_truth = readFileAlloc(allocator, ground_truth_path, 10 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => blk: {
            files_ok = false;
            break :blk "<file not found>";
        },
        else => |e| return e,
    };
    defer allocator.free(ground_truth);

    const new_input = readFileAlloc(allocator, new_input_path, 10 * 1024 * 1024) catch |err| switch (err) {
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
        else => return err,
    };

    if (!files_ok)
        return 1;

    return 0;
}

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const file = try openFile(path);
    defer file.close();
    return file.readToEndAlloc(alloc, max_bytes);
}

fn openFile(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, .{});
    }
    return std.fs.cwd().openFile(path, .{});
}
