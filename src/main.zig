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

    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&stderr_buffer);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try stderr.interface.print("usage: {s} <file>\n", .{args[0]});
        try stderr.interface.flush();
        return 1;
    }

    const path = args[1];

    var diagnostics: hdoc.Diagnostics = .init(allocator);
    defer diagnostics.deinit();

    const parse_result = parse_and_process(
        allocator,
        &diagnostics,
        &stdout.interface,
        path,
    );

    for (diagnostics.items.items) |diag| {
        try stderr.interface.print("{s}:{f}: {f}\n", .{
            path,
            diag.location,
            diag.code,
        });
    }
    try stderr.interface.flush();

    parse_result catch |err| {
        std.log.err("failed to parse \"{s}\": {t}", .{ path, err });
        return 1;
    };

    try stdout.interface.flush();

    return 0;
}

fn parse_and_process(allocator: std.mem.Allocator, diagnostics: *hdoc.Diagnostics, output_stream: *std.Io.Writer, path: []const u8) !void {
    const document = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 10);
    defer allocator.free(document);

    var parsed = try hdoc.parse(allocator, document, diagnostics);
    defer parsed.deinit();

    if (diagnostics.has_error()) {
        return error.InvalidFile;
    }

    try hdoc.render.yaml(parsed, output_stream);
}
