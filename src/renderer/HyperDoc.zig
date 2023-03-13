const std = @import("std");
const hdoc = @import("hyperdoc");

pub fn render(file: std.fs.File, document: hdoc.Document) !void {
    const writer = file.writer();

    try writer.writeAll("hdoc \"1.0\"\n");
    try renderBlocks(file, document, document.contents, 0);
}

fn renderBlocks(file: std.fs.File, document: hdoc.Document, blocks: []const hdoc.Block, indent: usize) !void {
    for (blocks) |block| {
        try renderBlock(file, document, block, indent);
    }
}

fn renderBlock(file: std.fs.File, document: hdoc.Document, block: hdoc.Block, indent: usize) !void {
    const writer = file.writer();
    try writer.writeByteNTimes(' ', 2 * indent);
    switch (block) {
        .paragraph => |content| {
            try writer.writeAll("p {\n");
            try renderSpans(file, content.contents, indent + 1);
            try writer.writeByteNTimes(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .ordered_list => |content| {
            try writer.writeAll("enumerate {\n");
            for (content) |item| {
                try renderBlock(file, document, item, indent + 1);
            }
            try writer.writeByteNTimes(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .unordered_list => |content| {
            try writer.writeAll("itemize {\n");
            for (content) |item| {
                try renderBlock(file, document, item, indent + 1);
            }
            try writer.writeByteNTimes(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .quote => |content| {
            try writer.writeAll("quote {\n");
            try renderSpans(file, content.contents, indent + 1);
            try writer.writeByteNTimes(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .preformatted => |content| {
            try writer.print("pre \"{}\" {{\n", .{
                escape(content.language),
            });
            try renderSpans(file, content.contents, indent + 1);
            try writer.writeByteNTimes(' ', 2 * indent);
            try writer.writeAll("}\n");
        },
        .image => |content| {
            try writer.print("image \"{}\"\n", .{
                escape(content.path),
            });
        },
        .heading => |content| {
            try writer.writeAll(switch (content.level) {
                .document => "h1",
                .chapter => "h2",
                .section => "h3",
            });
            try writer.print(" \"{}\" \"{}\"\n", .{
                escape(content.anchor),
                escape(content.title),
            });
        },
        .table_of_contents => {
            try writer.writeAll("toc {}\n");
        },
    }
}

fn renderSpans(file: std.fs.File, spans: []const hdoc.Span, indent: usize) !void {
    for (spans) |span| {
        try renderSpan(file, span, indent);
    }
}

fn renderSpan(file: std.fs.File, span: hdoc.Span, indent: usize) !void {
    const writer = file.writer();
    try writer.writeByteNTimes(' ', 2 * indent);
    switch (span) {
        .text => |val| {
            try writer.print("span \"{}\"\n", .{escape(val)});
        },
        .emphasis => |val| {
            try writer.print("emph \"{}\"\n", .{escape(val)});
        },
        .monospace => |val| {
            try writer.print("mono \"{}\"\n", .{escape(val)});
        },
        .link => |val| {
            try writer.print("link \"{}\" \"{}\"\n", .{
                escape(val.href),
                escape(val.text),
            });
        },
    }
}

fn escape(string: []const u8) HtmlEscaper {
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
