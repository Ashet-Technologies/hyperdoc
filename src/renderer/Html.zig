const std = @import("std");
const hdoc = @import("hyperdoc");

pub const WriteError = std.Io.Writer.Error;

pub fn render(writer: *std.Io.Writer, document: hdoc.Document) WriteError!void {
    try writer.writeAll(
        \\<!doctype html>
        \\<head>
        \\<meta charset="UTF-8">
        \\<style>
    );
    try writer.writeAll(@embedFile("../data/default.css"));
    try writer.writeAll(
        \\</style>
        \\</head>
        \\<body>
    );

    try renderBlocks(writer, document, document.contents);

    try writer.writeAll(
        \\</body>
        \\
    );
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
            try writer.writeAll("<p>");
            try renderSpans(writer, content.contents);
            try writer.writeAll("</p>\n");
        },

        .ordered_list => |content| {
            try writer.writeAll("<ol>\n");
            for (content) |item| {
                try writer.writeAll("<li>");
                try renderBlocks(writer, document, item.contents);
                try writer.writeAll("</li>\n");
            }
            try writer.writeAll("</ol>\n");
        },

        .unordered_list => |content| {
            try writer.writeAll("<ul>\n");
            for (content) |item| {
                try writer.writeAll("<li>");
                try renderBlocks(writer, document, item.contents);
                try writer.writeAll("</li>\n");
            }
            try writer.writeAll("</ul>\n");
        },

        .quote => |content| {
            try writer.writeAll("<blockquote>");
            try renderSpans(writer, content.contents);
            try writer.writeAll("</blockquote>\n");
        },

        .preformatted => |content| {
            if (!std.mem.eql(u8, content.language, "")) {
                try writer.print("<pre class=\"lang-{s}\">", .{content.language});
            } else {
                try writer.writeAll("<pre>");
            }
            try renderSpans(writer, content.contents);
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

            try writer.print("{f}", .{escapeHtml(content.title)});

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
            try writer.print("{f}", .{escapeHtml(val)});
        },
        .emphasis => |val| {
            try writer.writeAll("<em>");
            try writer.print("{f}", .{escapeHtml(val)});
            try writer.writeAll("</em>");
        },
        .monospace => |val| {
            try writer.writeAll("<code>");
            try writer.print("{f}", .{escapeHtml(val)});
            try writer.writeAll("</code>");
        },
        .link => |val| {
            try writer.print("<a href=\"{s}\">{f}</a>", .{
                val.href,
                escapeHtml(val.text),
            });
        },
    }
}

fn escapeHtml(string: []const u8) HtmlEscaper {
    return .{ .string = string };
}

const HtmlEscaper = struct {
    string: []const u8,

    pub fn format(html: HtmlEscaper, writer: *std.Io.Writer) !void {
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
