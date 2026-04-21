const std = @import("std");
const builtin = @import("builtin");
const hdoc = @import("hyperdoc");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main(init: std.process.Init) !u8 {
    defer if (builtin.mode == .Debug) {
        std.debug.assert(debug_allocator.deinit() == .ok);
    };
    const allocator = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const options = try parse_options(&stderr.interface, args);

    var diagnostics: hdoc.Diagnostics = .init(allocator);
    defer diagnostics.deinit();

    const parse_result = parse_and_process(
        init.io,
        allocator,
        &diagnostics,
        &stdout.interface,
        options,
    );

    if (options.json_diagnostics) {
        const json_options: std.json.Stringify.Options = .{ .whitespace = .indent_2 };
        try std.json.Stringify.value(diagnostics.items.items, json_options, &stderr.interface);
        try stderr.interface.writeByte('\n');
    } else {
        for (diagnostics.items.items) |diag| {
            try stderr.interface.print("{s}:{f}: {f}\n", .{
                options.file_path,
                diag.location,
                diag.code,
            });
        }
    }
    try stderr.interface.flush();

    parse_result catch |err| {
        if (!options.json_diagnostics) {
            std.log.err("failed to parse \"{s}\": {t}", .{ options.file_path, err });
        }
        return 1;
    };

    try stdout.interface.flush();

    return 0;
}

fn parse_and_process(
    io: std.Io,
    allocator: std.mem.Allocator,
    diagnostics: *hdoc.Diagnostics,
    output_stream: *std.Io.Writer,
    options: CliOptions,
) !void {
    const document = try std.Io.Dir.cwd().readFileAlloc(
        io,
        options.file_path,
        allocator,
        .limited(1024 * 1024 * 10),
    );
    defer allocator.free(document);

    var parsed = try hdoc.parse(allocator, document, diagnostics);
    defer parsed.deinit();

    if (diagnostics.has_error()) {
        return error.InvalidFile;
    }

    switch (options.format) {
        .yaml => try hdoc.render.yaml(parsed, output_stream),
        .html => try hdoc.render.html5(parsed, output_stream, .{}),
    }
}

const CliOptions = struct {
    format: RenderFormat = .html,
    file_path: []const u8,
    json_diagnostics: bool = false,
};

const RenderFormat = enum {
    yaml,
    html,
};

fn parse_options(stderr: *std.Io.Writer, argv: []const []const u8) !CliOptions {
    var options: CliOptions = .{
        .file_path = "",
    };

    const app_name = argv[0];

    {
        var i: usize = 1;
        while (i < argv.len) {
            const value = argv[i];
            if (std.mem.startsWith(u8, value, "--")) {
                if (std.mem.eql(u8, value, "--format")) {
                    i += 1;
                    options.format = std.meta.stringToEnum(RenderFormat, argv[i]) orelse return error.InvalidCli;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, value, "--json-diagnostics")) {
                    options.json_diagnostics = true;
                    i += 1;
                    continue;
                }
                return error.InvalidCli;
            }

            if (options.file_path.len > 0) {
                return error.InvalidCli;
            }
            options.file_path = value;

            i += 1;
        }
    }

    if (options.file_path.len == 0) {
        try stderr.print("usage: {s} <file>\n", .{app_name});
        try stderr.flush();
        return error.InvalidCli;
    }

    return options;
}
