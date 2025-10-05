const std = @import("std");
const hdoc = @import("hyperdoc");

const WriteError = std.Io.Writer.Error;

pub fn render(writer: *std.Io.Writer, document: hdoc.Document) WriteError!void {
    try renderBlocks(writer, document, document.contents);
}

fn renderBlocks(
    writer: *std.Io.Writer,
    document: hdoc.Document,
    blocks: []const hdoc.Block,
) WriteError!void {
    for (blocks) |block| {
        try renderBlock(writer, document, block);
    }
}

fn renderBlock(
    writer: *std.Io.Writer,
    document: hdoc.Document,
    block: hdoc.Block,
) WriteError!void {
    switch (block) {
        .paragraph => |content| {
            try renderSpans(writer, content.contents);
            try writer.writeAll("\n\n");
        },

        .ordered_list => |content| {
            for (content) |item| {
                try writer.writeAll("- ");
                try renderBlocks(writer, document, item.contents);
            }
        },

        .unordered_list => |content| {
            for (content, 1..) |item, index| {
                try writer.print("{}. ", .{index});
                try renderBlocks(writer, document, item.contents);
            }
        },

        .quote => |content| {
            try writer.writeAll("> ");
            try renderSpans(writer, content.contents);
            try writer.writeAll("\n\n");
        },

        .preformatted => |content| {
            try writer.print("```{s}\n", .{content.language});
            try renderSpans(writer, content.contents);
            try writer.writeAll("```\n\n");
        },
        .image => |content| {
            try writer.print("![]({s})\n\n", .{content.path});
        },
        .heading => |content| {
            try writer.writeAll(switch (content.level) {
                .document => "# ",
                .chapter => "## ",
                .section => "### ",
            });
            if (content.anchor.len > 0) {
                std.log.warn("anchor not supported in markdown!", .{});
            }

            try writer.print("{f}\n\n", .{escapeMd(content.title)});
        },
        .table_of_contents => |content| {
            // TODO: Render TOC
            _ = content;
        },
    }
}

fn renderSpans(
    writer: *std.Io.Writer,
    spans: []const hdoc.Span,
) WriteError!void {
    for (spans) |span| {
        try renderSpan(writer, span);
    }
}

fn renderSpan(writer: *std.Io.Writer, span: hdoc.Span) WriteError!void {
    switch (span) {
        .text => |val| {
            try writer.print("{f}", .{escapeMd(val)});
        },
        .emphasis => |val| {
            try writer.writeAll("**");
            try writer.print("{f}", .{escapeMd(val)});
            try writer.writeAll("**");
        },
        .monospace => |val| {
            try writer.writeAll("`");
            try writer.print("{f}", .{escapeMd(val)});
            try writer.writeAll("`");
        },
        .link => |val| {
            try writer.print("[{f}]({s})", .{
                escapeMd(val.text),
                val.href,
            });
        },
    }
}

fn escapeMd(string: []const u8) MarkdownEscaper {
    return .{ .string = string };
}

const MarkdownEscaper = struct {
    string: []const u8,

    pub fn format(html: MarkdownEscaper, writer: *std.Io.Writer) !void {
        for (html.string) |char| {
            switch (char) {
                '&' => try writer.writeAll("&amp;"),
                '<' => try writer.writeAll("&lt;"),
                '>' => try writer.writeAll("&gt;"),
                '\"' => try writer.writeAll("&quot;"),
                '\'' => try writer.writeAll("&#39;"),
                '\n' => try writer.writeAll("  \n"),
                else => try writer.writeByte(char),
            }
        }
    }
};
