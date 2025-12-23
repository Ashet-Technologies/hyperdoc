const std = @import("std");
const builtin = @import("builtin");
const hdoc = @import("hyperdoc");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !u8 {
    defer if (builtin.mode == .Debug) {
        std.debug.assert(debug_allocator.deinit() == .ok);
    };
    const allocator = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("usage: {s} <file>\n", .{args[0]});
        return 1;
    }

    const path = args[1];
    const document = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 10);
    defer allocator.free(document);

    // TODO: Parse document

    return 0;
}
