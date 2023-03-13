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
        .hdoc => &HyperDocumentRenderer.render,
        .html => &HtmlDocumentRenderer.render,
        .markdown => &MarkdownDocumentRenderer.render,
    };

    try renderDocument(output_stream, document);

    return 0;
}

const HyperDocumentRenderer = struct {
    fn render(file: std.fs.File, document: hdoc.Document) !void {
        _ = file;
        _ = document;
    }
};

const HtmlDocumentRenderer = struct {
    fn render(file: std.fs.File, document: hdoc.Document) !void {
        const writer = file.writer();

        try writer.writeAll(
            \\<!doctype html>
            \\<head>
            \\<meta charset="UTF-8">
            \\<style>
        );
        try writer.writeAll(@embedFile("data/default.css"));
        try writer.writeAll(
            \\</style>
            \\</head>
            \\<body>
        );

        try renderBlocks(file, document, document.contents);

        try writer.writeAll(
            \\</body>
            \\
        );
    }

    fn renderBlocks(file: std.fs.File, document: hdoc.Document, blocks: []const hdoc.Block) !void {
        for (blocks) |block| {
            try renderBlock(file, document, block);
        }
    }

    fn renderBlock(file: std.fs.File, document: hdoc.Document, block: hdoc.Block) !void {
        const writer = file.writer();
        switch (block) {
            .paragraph => |content| {
                try writer.writeAll("<p>");
                try renderSpans(file, content.contents);
                try writer.writeAll("</p>\n");
            },

            .ordered_list => |content| {
                try writer.writeAll("<ol>\n");
                for (content) |item| {
                    try writer.writeAll("<li>");
                    try renderBlock(file, document, item);
                    try writer.writeAll("</li>\n");
                }
                try writer.writeAll("</ol>\n");
            },

            .unordered_list => |content| {
                try writer.writeAll("<ul>\n");
                for (content) |item| {
                    try writer.writeAll("<li>");
                    try renderBlock(file, document, item);
                    try writer.writeAll("</li>\n");
                }
                try writer.writeAll("</ul>\n");
            },

            .quote => |content| {
                try writer.writeAll("<blockquote>");
                try renderSpans(file, content.contents);
                try writer.writeAll("</blockquote>\n");
            },

            .preformatted => |content| {
                if (!std.mem.eql(u8, content.language, "")) {
                    try writer.print("<pre class=\"lang-{s}\">", .{content.language});
                } else {
                    try writer.writeAll("<pre>");
                }
                try renderSpans(file, content.contents);
                try writer.writeAll("</pre>\n");
            },
            .image => |content| {
                try writer.print("<img class=\"block\" href=\"{s}\">\n", .{content.path});
            },
            .heading => |content| {
                try writer.writeAll(switch (content.level) {
                    .document => "<h1",
                    .chapter => "<h2",
                    .section => "<h3",
                });
                if (content.anchor.len > 0) {
                    try writer.print(" id=\"{s}\"", .{content.anchor});
                }
                try writer.writeAll(">");

                try writer.print("{}", .{escapeHtml(content.title)});

                try writer.writeAll(switch (content.level) {
                    .document => "</h1>\n",
                    .chapter => "</h2>\n",
                    .section => "</h3>\n",
                });
            },
            .table_of_contents => |content| {
                // TODO: Render TOC
                _ = content;
            },
        }
    }

    fn renderSpans(file: std.fs.File, spans: []const hdoc.Span) !void {
        for (spans) |span| {
            try renderSpan(file, span);
        }
    }

    fn renderSpan(file: std.fs.File, span: hdoc.Span) !void {
        const writer = file.writer();
        switch (span) {
            .text => |val| {
                try writer.print("{}", .{escapeHtml(val)});
            },
            .emphasis => |val| {
                try writer.writeAll("<em>");
                try writer.print("{}", .{escapeHtml(val)});
                try writer.writeAll("</em>");
            },
            .monospace => |val| {
                try writer.writeAll("<code>");
                try writer.print("{}", .{escapeHtml(val)});
                try writer.writeAll("</code>");
            },
            .link => |val| {
                try writer.print("<a href=\"{s}\">", .{
                    val.href,
                });
                try writer.writeAll(val.text);
                try writer.writeAll("</a>");
            },
        }
    }

    fn escapeHtml(string: []const u8) HtmlEscaper {
        return HtmlEscaper{ .string = string };
    }

    const HtmlEscaper = struct {
        string: []const u8,

        pub fn format(html: HtmlEscaper, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            for (html.string) |char| {
                switch (char) {
                    '&' => try writer.writeAll("&amp;"),
                    '<' => try writer.writeAll("&lt;"),
                    '>' => try writer.writeAll("&gt;"),
                    '\"' => try writer.writeAll("&quot;"),
                    '\'' => try writer.writeAll("&#39;"),
                    '\n' => try writer.writeAll("<br/>"),
                    else => try writer.writeByte(char),
                }
            }
        }
    };
};

const MarkdownDocumentRenderer = struct {
    fn render(file: std.fs.File, document: hdoc.Document) !void {
        _ = file;
        _ = document;
    }
};

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
