const std = @import("std");
const hdoc = @import("hyperdoc");

pub fn render(file: std.fs.File, document: hdoc.Document) !void {
    try renderBlocks(file, document, document.contents);
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
            try renderSpans(file, content.contents);
            try writer.writeAll("\n\n");
        },

        .ordered_list => |content| {
            for (content) |item| {
                try writer.writeAll("- ");
                try renderBlock(file, document, item);
            }
        },

        .unordered_list => |content| {
            for (content, 1..) |item, index| {
                try writer.print("{}. ", .{index});
                try renderBlock(file, document, item);
            }
        },

        .quote => |content| {
            try writer.writeAll("> ");
            try renderSpans(file, content.contents);
            try writer.writeAll("\n\n");
        },

        .preformatted => |content| {
            try writer.print("```{s}\n", .{content.language});
            try renderSpans(file, content.contents);
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

            try writer.print("{}\n\n", .{escapeMd(content.title)});
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
            try writer.print("{}", .{escapeMd(val)});
        },
        .emphasis => |val| {
            try writer.writeAll("**");
            try writer.print("{}", .{escapeMd(val)});
            try writer.writeAll("**");
        },
        .monospace => |val| {
            try writer.writeAll("`");
            try writer.print("{}", .{escapeMd(val)});
            try writer.writeAll("`");
        },
        .link => |val| {
            try writer.print("[{}]({s})", .{
                escapeMd(val.text),
                val.href,
            });
        },
    }
}
fn escapeMd(string: []const u8) MarkdownEscaper {
    return MarkdownEscaper{ .string = string };
}

const MarkdownEscaper = struct {
    string: []const u8,

    pub fn format(html: MarkdownEscaper, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
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
