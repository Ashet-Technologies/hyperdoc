//!
//! This file implements a HTML content renderer for HyperDoc.
//!
const std = @import("std");
const hdoc = @import("../hyperdoc.zig");

const Writer = std.Io.Writer;
const indent_step: usize = 2;

// TODO: Implementation hints:
// - Use writeStartTag, writeEndTag to construct the document
// - Use and expand writeEscapedHtml to suite the needs of HyperDoc.
// - Implement a custom formatter for string attribute values so they have proper escaping applied.
// - Use semantic HTML. Never use `div` or `span`. If necessary, ask back when you encounter the need for a "custom tag".
// - For the different paragraph types, use a class="hdoc-${kind}", so for example class="hdoc-warning" to distinguish the special paragraphs from regular <p> ones.
// - The TOC element must be unrolled manually and should auto-link to the h1,h2,h3 elements.

/// This function emits the body-only part of a HyperDoc document as
/// valid HTML5.
pub fn render(doc: hdoc.Document, writer: *Writer) Writer.Error!void {
    _ = doc;

    // TODO: Implement this proper

    try writeStartTag(writer, "p", .regular, .{
        .style = "font-weight: bold",
    });
    try writeEscapedHtml(writer, "Hello, World!");
    try writeEndTag(writer, "p");
    try writer.writeAll("\n");
}

fn writeEscapedHtml(writer: *Writer, text: []const u8) !void {
    var view = std.unicode.Utf8View.init(text) catch @panic("invalid utf-8 passed");
    var iter = view.iterator();
    while (iter.nextCodepointSlice()) |slice| {
        const codepoint = std.unicode.utf8Decode(slice) catch unreachable;
        switch (codepoint) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),

            0xA0 => try writer.writeAll("&nbsp;"),

            // TODO: Fill out other required codes.

            else => try writer.writeAll(slice),
        }
    }
}

fn writeStartTag(writer: *Writer, tag: []const u8, style: enum { regular, auto_close }, attribs: anytype) !void {
    try writer.print("<{s}", .{tag});

    const Attribs = @TypeOf(attribs);
    inline for (@typeInfo(Attribs).@"struct".fields) |fld| {
        const value = @field(attribs, fld.name);

        if (fld.type == bool) {
            if (value) {
                try writer.print(" {s}", .{fld.name});
            }
        } else {
            try writer.print(" {s}=", .{fld.name});

            switch (@typeInfo(fld.type)) {
                .int, .comptime_int => try writer.print("\"{}\"", .{value}),
                .float, .comptime_float => try writer.print("\"{d}\"", .{value}),

                .pointer => |info| if (info.size == .one) {
                    const child = @typeInfo(info.child);

                    if (child != .array)
                        @compileError("unsupported pointer type " ++ @typeName(fld.type));
                    if (child.array.child != u8)
                        @compileError("unsupported pointer type " ++ @typeName(fld.type));

                    try writer.print("\"{s}\"", .{value}); // TODO: Implement proper HTML escaping!
                },

                else => switch (fld.type) {
                    bool => unreachable,

                    []u8, []const u8 => try writer.print("\"{s}\"", .{value}), // TODO: Implement proper HTML escaping!

                    else => @compileError("unsupported tag type " ++ @typeName(fld.type) ++ ", implement support above."),
                },
            }
        }
    }
    switch (style) {
        .auto_close => try writer.writeAll("/>"),
        .regular => try writer.writeAll(">"),
    }
}

fn writeEndTag(writer: *Writer, tag: []const u8) !void {
    try writer.print("</{s}>", .{tag});
}
