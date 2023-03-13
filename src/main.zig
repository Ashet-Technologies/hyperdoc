const std = @import("std");
const hdoc = @import("hyperdoc");
const args_parser = @import("args");

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var cli = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try printUsage(cli.executable_name.?, stdout);
        return 0;
    }

    if (cli.positionals.len != 1) {
        try printUsage(cli.executable_name.?, stderr);
        return 1;
    }

    var document: hdoc.Document = blk: {
        const source_text = try std.fs.cwd().readFileAlloc(allocator, cli.positionals[0], 512 << 20); // 512MB
        defer allocator.free(source_text);

        break :blk try hdoc.parse(allocator, source_text);
    };
    defer document.deinit();

    var output_stream = if (cli.options.output != null and !std.mem.eql(u8, cli.options.output.?, "-"))
        try std.fs.cwd().createFile(cli.options.output.?, .{})
    else
        std.io.getStdOut();
    defer output_stream.close();

    const renderDocument = switch (cli.options.format) {
        .hdoc => &@import("renderer/HyperDoc.zig").render,
        .html => &@import("renderer/Html.zig").render,
        .markdown => &@import("renderer/Markdown.zig").render,
    };

    try renderDocument(output_stream, document);

    return 0;
}


const TargetFormat = enum {
    hdoc,
    html,
    markdown,
};

const CliOptions = struct {
    help: bool = false,
    format: TargetFormat = .hdoc,
    output: ?[]const u8 = null,

    pub const shorthands = .{
        .h = "help",
        .f = "format",
    };
};

fn printUsage(exe_name: []const u8, stream: anytype) !void {
    try stream.print("{s} [-h] [-f <format>] <file>\n", .{
        std.fs.path.basename(exe_name),
    });
    try stream.writeAll(
        \\
        \\Options:
        \\  -h, --help              Prints this text
        \\  -f, --format <format>   Converts the given <file> into <format>. Legal values are:
        \\                          - hdoc     - Formats the input file into canonical format.
        \\                          - html     - Renders the HyperDocument as HTML.
        \\                          - markdown - Renders the HyperDocument as CommonMark.
        \\  -o, --output <result>   Instead of printing to stdout, will put the output into <result>.
        \\
    );
}
