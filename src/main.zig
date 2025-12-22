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

    // TODO: Parse arguments and load file.
    const document =
        \\hdoc "2.0"
        \\
    ;

    var doc = try hdoc.parse(allocator, document, null);
    defer doc.deinit();

    // TODO: Dump AST

    return 0;
}
