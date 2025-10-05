const std = @import("std");
const hdoc = @import("hyperdoc");
const args_parser = @import("args");

pub fn main() !u8 {
    var stdout_buf: [1024]u8 = undefined;
    const stdout_file: std.fs.File = .stdout();
    var stdout_writer = stdout_file.writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    var stderr_buf: [1024]u8 = undefined;
    const stderr_file: std.fs.File = .stderr();
    var stderr_writer = stderr_file.writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

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

    var error_location: hdoc.ErrorLocation = undefined;

    var document: hdoc.Document = blk: {
        const source_text = try std.fs.cwd().readFileAlloc(
            allocator,
            cli.positionals[0],
            512 << 20,
        ); // 512MB
        defer allocator.free(source_text);

        break :blk hdoc.parse(allocator, source_text, &error_location) catch |err| {
            error_location.source = cli.positionals[0];
            std.log.err("{f}: Failed to parse document: {s}", .{
                error_location,
                switch (err) {
                    error.UnexpectedToken,
                    error.InvalidIdentifier,
                    error.UnexpectedCharacter,
                    error.InvalidTopLevelItem,
                    error.InvalidSpan,
                    => "syntax error",
                    error.InvalidFormat => "not a HyperDocument file",
                    error.InvalidVersion => "unsupported file version",
                    error.OutOfMemory => "out of memory",
                    error.EndOfFile => "unexpected end of file",
                    error.InvalidEscapeSequence => "illegal escape sequence",
                    // else => |e|   @errorName(e),
                },
            });
            return 1;
        };
    };
    defer document.deinit();

    const output_file: ?std.fs.File = if (cli.options.output != null and !std.mem.eql(u8, cli.options.output.?, "-"))
        try std.fs.cwd().createFile(cli.options.output.?, .{})
    else
        null;
    defer if (output_file) |f| f.close();

    const renderDocument = switch (cli.options.format) {
        .hdoc => &@import("renderer/HyperDoc.zig").render,
        .html => &@import("renderer/Html.zig").render,
        .markdown => &@import("renderer/Markdown.zig").render,
    };

    if (output_file) |f| {
        var out_buf: [1024]u8 = undefined;
        var out_writer = f.writer(&out_buf);
        const output_stream = &out_writer.interface;
        try renderDocument(output_stream, document);
        try output_stream.flush();
    } else {
        try renderDocument(stdout, document);
        try stdout.flush();
    }

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
        .o = "output",
    };
};

fn printUsage(exe_name: []const u8, stream: *std.Io.Writer) !void {
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
    try stream.flush();
}
