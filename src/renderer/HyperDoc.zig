const std = @import("std");
const hdoc = @import("hyperdoc");

pub const WriteError = std.Io.Writer.Error;

pub fn render(writer: *std.Io.Writer, document: hdoc.Document) WriteError!void {
    try writer.writeAll("hdoc \"1.0\"\n");
    try renderBlocks(writer, document, document.contents, 0);
}

fn renderBlocks(
    writer: *std.Io.Writer,
    document: hdoc.Document,
    blocks: []const hdoc.Block,
    indent: usize,
) WriteError!void {
    for (blocks) |block| {
        try renderBlock(writer, document, block, indent);
    }
}

fn renderBlock(
    writer: *std.Io.Writer,
    document: hdoc.Document,
    block: hdoc.Block,
    indent: usize,
) WriteError!void {
    try writer.splatByteAll(' ', 2 * indent);
    switch (block) {
        .paragraph => |content| {
            try writer.writeAll("p {\n");
            try renderSpans(writer, content.contents, indent + 1);
            try writer.splatByteAll(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .ordered_list => |content| {
            try writer.writeAll("enumerate {\n");
            for (content) |item| {
                try writer.splatByteAll(' ', 2 * indent + 2);
                try writer.writeAll("item {\n");

                try renderBlocks(writer, document, item.contents, indent + 2);

                try writer.splatByteAll(' ', 2 * indent + 2);
                try writer.writeAll("}\n");
            }
            try writer.splatByteAll(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .unordered_list => |content| {
            try writer.writeAll("itemize {\n");
            for (content) |item| {
                try writer.splatByteAll(' ', 2 * indent + 2);
                try writer.writeAll("item {\n");

                try renderBlocks(writer, document, item.contents, indent + 2);

                try writer.splatByteAll(' ', 2 * indent + 2);
                try writer.writeAll("}\n");
            }
            try writer.splatByteAll(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .quote => |content| {
            try writer.writeAll("quote {\n");
            try renderSpans(writer, content.contents, indent + 1);
            try writer.splatByteAll(' ', 2 * indent);
            try writer.writeAll("}\n");
        },

        .preformatted => |content| {
            try writer.print("pre \"{f}\" {{\n", .{
                escape(content.language),
            });
            try renderSpans(writer, content.contents, indent + 1);
            try writer.splatByteAll(' ', 2 * indent);
            try writer.writeAll("}\n");
        },
        .image => |content| {
            try writer.print("image \"{f}\"\n", .{
                escape(content.path),
            });
        },
        .heading => |content| {
            try writer.writeAll(switch (content.level) {
                .document => "h1",
                .chapter => "h2",
                .section => "h3",
            });
            try writer.print(" \"{f}\" \"{f}\"\n", .{
                escape(content.anchor),
                escape(content.title),
            });
        },
        .table_of_contents => {
            try writer.writeAll("toc {}\n");
        },
    }
}

fn renderSpans(
    writer: *std.Io.Writer,
    spans: []const hdoc.Span,
    indent: usize,
) WriteError!void {
    for (spans) |span| {
        try renderSpan(writer, span, indent);
    }
}

fn renderSpan(
    writer: *std.Io.Writer,
    span: hdoc.Span,
    indent: usize,
) WriteError!void {
    try writer.splatByteAll(' ', 2 * indent);
    switch (span) {
        .text => |val| {
            try writer.print("span \"{f}\"\n", .{escape(val)});
        },
        .emphasis => |val| {
            try writer.print("emph \"{f}\"\n", .{escape(val)});
        },
        .monospace => |val| {
            try writer.print("mono \"{f}\"\n", .{escape(val)});
        },
        .link => |val| {
            try writer.print("link \"{f}\" \"{f}\"\n", .{
                escape(val.href),
                escape(val.text),
            });
        },
    }
}

fn escape(string: []const u8) HDocEscaper {
    return .{ .string = string };
}

const HDocEscaper = struct {
    string: []const u8,

    pub fn format(html: HDocEscaper, writer: *std.Io.Writer) !void {
        for (html.string) |char| {
            switch (char) {
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\x1B' => try writer.writeAll("\\e"),
                '\'' => try writer.writeAll("\\\'"),
                '\"' => try writer.writeAll("\\\""),
                else => try writer.writeByte(char),
            }
        }
    }
};
