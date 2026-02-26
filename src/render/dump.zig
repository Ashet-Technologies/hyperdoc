const std = @import("std");
const hdoc = @import("../hyperdoc.zig");

const Writer = std.Io.Writer;
const indent_step: usize = 2;

fn writeIndent(writer: *Writer, indent: usize) Writer.Error!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeByte(' ');
    }
}

fn writeStringValue(writer: *Writer, value: []const u8) Writer.Error!void {
    try writer.print("\"{f}\"", .{std.zig.fmtString(value)});
}

fn writeOptionalStringValue(writer: *Writer, value: ?[]const u8) Writer.Error!void {
    if (value) |text| {
        try writeStringValue(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn writeOptionalIntValue(writer: *Writer, value: anytype) Writer.Error!void {
    if (value) |number| {
        try writer.print("{}", .{number});
    } else {
        try writer.writeAll("null");
    }
}

fn dumpOptionalStringField(writer: *Writer, indent: usize, key: []const u8, value: ?[]const u8) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("{s}: ", .{key});
    try writeOptionalStringValue(writer, value);
    try writer.writeByte('\n');
}

fn dumpOptionalStringFieldInline(writer: *Writer, key: []const u8, value: ?[]const u8) Writer.Error!void {
    try writer.print("{s}: ", .{key});
    try writeOptionalStringValue(writer, value);
    try writer.writeByte('\n');
}

fn dumpOptionalStringFieldWithIndent(writer: *Writer, indent: usize, key: []const u8, value: ?[]const u8) Writer.Error!void {
    try writeIndent(writer, indent);
    try dumpOptionalStringFieldInline(writer, key, value);
}

fn dumpOptionalNumberField(writer: *Writer, indent: usize, key: []const u8, value: anytype) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("{s}: ", .{key});
    try writeOptionalIntValue(writer, value);
    try writer.writeByte('\n');
}

fn dumpBoolField(writer: *Writer, indent: usize, key: []const u8, value: bool) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("{s}: {}\n", .{ key, value });
}

fn dumpEnumField(writer: *Writer, indent: usize, key: []const u8, value: anytype) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("{s}: {s}\n", .{ key, @tagName(value) });
}

fn dumpVersion(writer: *Writer, indent: usize, version: hdoc.Version) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.writeAll("version:\n");
    try writeIndent(writer, indent + indent_step);
    try writer.print("major: {}\n", .{version.major});
    try writeIndent(writer, indent + indent_step);
    try writer.print("minor: {}\n", .{version.minor});
}

fn dumpDate(writer: *Writer, indent: usize, date: hdoc.Date) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("year: {}\n", .{date.year});
    try writeIndent(writer, indent);
    try writer.print("month: {}\n", .{date.month});
    try writeIndent(writer, indent);
    try writer.print("day: {}\n", .{date.day});
}

fn dumpTime(writer: *Writer, indent: usize, time: hdoc.Time) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("hour: {}\n", .{time.hour});
    try writeIndent(writer, indent);
    try writer.print("minute: {}\n", .{time.minute});
    try writeIndent(writer, indent);
    try writer.print("second: {}\n", .{time.second});
    try writeIndent(writer, indent);
    try writer.print("microsecond: {}\n", .{time.microsecond});
}

fn dumpDateTime(writer: *Writer, indent: usize, datetime: hdoc.DateTime) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.writeAll("date:\n");
    try dumpDate(writer, indent + indent_step, datetime.date);
    try writeIndent(writer, indent);
    try writer.writeAll("time:\n");
    try dumpTime(writer, indent + indent_step, datetime.time);
}

fn writeAttrSeparator(writer: *Writer, first: *bool) Writer.Error!void {
    if (first.*) {
        first.* = false;
    } else {
        try writer.writeByte(' ');
    }
}

fn writeSpanAttributes(writer: *Writer, span: hdoc.Span) Writer.Error!void {
    try writer.writeByte('[');
    var first = true;
    if (span.attribs.em) {
        try writeAttrSeparator(writer, &first);
        try writer.writeAll("em");
    }
    if (span.attribs.mono) {
        try writeAttrSeparator(writer, &first);
        try writer.writeAll("mono");
    }
    if (span.attribs.strike) {
        try writeAttrSeparator(writer, &first);
        try writer.writeAll("strike");
    }
    if (span.attribs.position != .baseline) {
        try writeAttrSeparator(writer, &first);
        try writer.print("position=\"{s}\"", .{@tagName(span.attribs.position)});
    }
    switch (span.attribs.link) {
        .none => {},
        .ref => |value| {
            try writeAttrSeparator(writer, &first);
            if (value.block_index) |idx| {
                try writer.print("link=\"ref:{f}#{d}\"", .{ std.zig.fmtString(value.ref.text), idx });
            } else {
                try writer.print("link=\"ref:{f}\"", .{std.zig.fmtString(value.ref.text)});
            }
        },
        .uri => |value| {
            try writeAttrSeparator(writer, &first);
            try writer.print("link=\"uri:{f}\"", .{std.zig.fmtString(value.text)});
        },
    }
    if (span.attribs.lang.text.len != 0) {
        try writeAttrSeparator(writer, &first);
        try writer.print("lang=\"{f}\"", .{std.zig.fmtString(span.attribs.lang.text)});
    }
    if (span.attribs.syntax.len != 0) {
        try writeAttrSeparator(writer, &first);
        try writer.print("syntax=\"{f}\"", .{std.zig.fmtString(span.attribs.syntax)});
    }
    try writer.writeByte(']');
}

fn writeDateValue(writer: *Writer, date: hdoc.Date) Writer.Error!void {
    try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ date.year, date.month, date.day });
}

fn writeTimeValue(writer: *Writer, time: hdoc.Time) Writer.Error!void {
    try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ time.hour, time.minute, time.second });
    if (time.microsecond != 0) {
        try writer.print(".{d:0>6}", .{time.microsecond});
    }
}

fn writeDateTimeValue(writer: *Writer, datetime: hdoc.DateTime) Writer.Error!void {
    try writeDateValue(writer, datetime.date);
    try writer.writeByte('T');
    try writeTimeValue(writer, datetime.time);
}

fn writeFormattedDateInline(writer: *Writer, formatted: hdoc.FormattedDateTime(hdoc.Date)) Writer.Error!void {
    try writer.writeAll("date:");
    try writeDateValue(writer, formatted.value);
    if (formatted.format != hdoc.Date.Format.default) {
        try writer.writeByte('@');
        try writer.writeAll(@tagName(formatted.format));
    }
}

fn writeFormattedTimeInline(writer: *Writer, formatted: hdoc.FormattedDateTime(hdoc.Time)) Writer.Error!void {
    try writer.writeAll("time:");
    try writeTimeValue(writer, formatted.value);
    if (formatted.format != hdoc.Time.Format.default) {
        try writer.writeByte('@');
        try writer.writeAll(@tagName(formatted.format));
    }
}

fn writeFormattedDateTimeInline(writer: *Writer, formatted: hdoc.FormattedDateTime(hdoc.DateTime)) Writer.Error!void {
    try writer.writeAll("datetime:");
    try writeDateTimeValue(writer, formatted.value);
    if (formatted.format != hdoc.DateTime.Format.default) {
        try writer.writeByte('@');
        try writer.writeAll(@tagName(formatted.format));
    }
}

fn writeSpanContentInline(writer: *Writer, content: hdoc.Span.Content) Writer.Error!void {
    switch (content) {
        .text => |text| {
            try writeStringValue(writer, text);
        },
        .date => |date| {
            try writer.writeByte('"');
            try writeFormattedDateInline(writer, date);
            try writer.writeByte('"');
        },
        .time => |time| {
            try writer.writeByte('"');
            try writeFormattedTimeInline(writer, time);
            try writer.writeByte('"');
        },
        .datetime => |datetime| {
            try writer.writeByte('"');
            try writeFormattedDateTimeInline(writer, datetime);
            try writer.writeByte('"');
        },
        .footnote => |footnote| {
            try writer.print("\"footnote:{s}:{d}\"", .{ @tagName(footnote.kind), footnote.index });
        },
        .reference => |reference| {
            try writer.writeByte('"');
            try writer.writeAll("ref:");
            try writer.writeAll(reference.ref.text);
            try writer.writeByte('@');
            try writer.writeAll(@tagName(reference.fmt));
            if (reference.target_block) |idx| {
                try writer.print("#{d}", .{idx});
            }
            try writer.writeByte('"');
        },
    }
}

fn dumpSpanInline(writer: *Writer, span: hdoc.Span) Writer.Error!void {
    try writeSpanAttributes(writer, span);
    try writer.writeByte(' ');
    try writeSpanContentInline(writer, span.content);
}

fn writeTypeTag(writer: *Writer, tag: []const u8) Writer.Error!void {
    try writer.print("{s}:\n", .{tag});
}

fn dumpSpanListField(writer: *Writer, indent: usize, key: []const u8, spans: []const hdoc.Span) Writer.Error!void {
    try writeIndent(writer, indent);
    if (spans.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (spans) |span| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("- ");
        try dumpSpanInline(writer, span);
        try writer.writeByte('\n');
    }
}

fn dumpBlockListField(writer: *Writer, indent: usize, key: []const u8, blocks: []const hdoc.Block) Writer.Error!void {
    try writeIndent(writer, indent);
    if (blocks.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (blocks) |block| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("- ");
        try dumpBlockInline(writer, indent + indent_step, block);
    }
}

fn dumpNumberListField(writer: *Writer, indent: usize, key: []const u8, values: []const usize) Writer.Error!void {
    try writeIndent(writer, indent);
    if (values.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (values) |value| {
        try writeIndent(writer, indent + indent_step);
        try writer.print("- {}\n", .{value});
    }
}

fn dumpOptionalStringListField(writer: *Writer, indent: usize, key: []const u8, values: []?hdoc.Reference) Writer.Error!void {
    try writeIndent(writer, indent);
    if (values.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (values) |value| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("- ");
        try writeOptionalStringValue(writer, if (value) |val| val.text else null);
        try writer.writeByte('\n');
    }
}

fn dumpListItem(writer: *Writer, indent: usize, item: hdoc.Block.ListItem) Writer.Error!void {
    try dumpOptionalStringFieldInline(writer, "lang", item.lang.text);
    try dumpBlockListField(writer, indent + indent_step, "content", item.content);
}

fn dumpListItemsField(writer: *Writer, indent: usize, key: []const u8, items: []const hdoc.Block.ListItem) Writer.Error!void {
    try writeIndent(writer, indent);
    if (items.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (items) |item| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("- ");
        try dumpListItem(writer, indent + indent_step, item);
    }
}

fn dumpFootnoteEntry(writer: *Writer, indent: usize, entry: hdoc.Block.FootnoteEntry) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("index: {}\n", .{entry.index});
    try dumpEnumField(writer, indent, "kind", entry.kind);
    try dumpOptionalStringField(writer, indent, "lang", entry.lang.text);
    try dumpSpanListField(writer, indent, "content", entry.content);
}

fn dumpFootnoteEntries(writer: *Writer, indent: usize, entries: []const hdoc.Block.FootnoteEntry) Writer.Error!void {
    try writeIndent(writer, indent);
    if (entries.len == 0) {
        try writer.writeAll("entries: []\n");
        return;
    }
    try writer.writeAll("entries:\n");
    for (entries) |entry| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("- ");
        try dumpFootnoteEntry(writer, indent + indent_step, entry);
    }
}

fn dumpTableCell(writer: *Writer, indent: usize, cell: hdoc.Block.TableCell) Writer.Error!void {
    try dumpOptionalStringFieldInline(writer, "lang", cell.lang.text);
    try dumpOptionalNumberField(writer, indent + indent_step, "colspan", @as(?u32, cell.colspan));
    try dumpBlockListField(writer, indent + indent_step, "content", cell.content);
}

fn dumpTableCellsField(writer: *Writer, indent: usize, key: []const u8, cells: []const hdoc.Block.TableCell) Writer.Error!void {
    try writeIndent(writer, indent);
    if (cells.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (cells) |cell| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("- ");
        try dumpTableCell(writer, indent + indent_step, cell);
    }
}

fn dumpTableColumns(writer: *Writer, indent: usize, columns: hdoc.Block.TableColumns) Writer.Error!void {
    try dumpOptionalStringField(writer, indent, "lang", columns.lang.text);
    try dumpTableCellsField(writer, indent, "cells", columns.cells);
}

fn dumpTableDataRow(writer: *Writer, indent: usize, row: hdoc.Block.TableDataRow) Writer.Error!void {
    try dumpOptionalStringFieldWithIndent(writer, indent, "lang", row.lang.text);
    try dumpOptionalStringField(writer, indent, "title", row.title);
    try dumpTableCellsField(writer, indent, "cells", row.cells);
}

fn dumpTableGroup(writer: *Writer, indent: usize, group: hdoc.Block.TableGroup) Writer.Error!void {
    try dumpOptionalStringFieldWithIndent(writer, indent, "lang", group.lang.text);
    try dumpSpanListField(writer, indent, "content", group.content);
}

fn dumpTableRow(writer: *Writer, indent: usize, row: hdoc.Block.TableRow) Writer.Error!void {
    switch (row) {
        .columns => |columns| {
            try writeTypeTag(writer, "columns");
            try dumpTableColumns(writer, indent + indent_step, columns);
        },
        .row => |data_row| {
            try writeTypeTag(writer, "row");
            try dumpTableDataRow(writer, indent + indent_step, data_row);
        },
        .group => |group| {
            try writeTypeTag(writer, "group");
            try dumpTableGroup(writer, indent + indent_step, group);
        },
    }
}

fn dumpTableRowsField(writer: *Writer, indent: usize, key: []const u8, rows: []const hdoc.Block.TableRow) Writer.Error!void {
    try writeIndent(writer, indent);
    if (rows.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (rows) |row| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("- ");
        try dumpTableRow(writer, indent + indent_step, row);
    }
}

fn dumpTableOfContentsChildren(writer: *Writer, indent: usize, children: []const hdoc.Document.TableOfContents) Writer.Error!void {
    try writeIndent(writer, indent);
    if (children.len == 0) {
        try writer.writeAll("children: []\n");
        return;
    }
    try writer.writeAll("children:\n");
    for (children) |child| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("-\n");
        try dumpTableOfContentsNode(writer, indent + 2 * indent_step, child);
    }
}

fn dumpTableOfContentsNode(writer: *Writer, indent: usize, toc: hdoc.Document.TableOfContents) Writer.Error!void {
    try dumpEnumField(writer, indent, "level", toc.level);
    try dumpNumberListField(writer, indent, "headings", toc.headings);
    try dumpTableOfContentsChildren(writer, indent, toc.children);
}

fn dumpTableOfContents(writer: *Writer, indent: usize, toc: hdoc.Document.TableOfContents) Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.writeAll("toc:\n");
    try dumpTableOfContentsNode(writer, indent + indent_step, toc);
}

fn dumpBlockInline(writer: *Writer, indent: usize, block: hdoc.Block) Writer.Error!void {
    switch (block) {
        .heading => |heading| {
            try writeTypeTag(writer, "heading");
            try dumpEnumField(writer, indent + indent_step, "level", heading.index); // TODO: Also print the indices here
            try dumpOptionalStringField(writer, indent + indent_step, "lang", heading.lang.text);
            try dumpSpanListField(writer, indent + indent_step, "content", heading.content);
        },
        .paragraph => |paragraph| {
            try writeTypeTag(writer, "paragraph");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", paragraph.lang.text);
            try dumpSpanListField(writer, indent + indent_step, "content", paragraph.content);
        },
        .admonition => |admonition| {
            try writeTypeTag(writer, "admonition");
            try dumpEnumField(writer, indent + indent_step, "kind", admonition.kind);
            try dumpOptionalStringField(writer, indent + indent_step, "lang", admonition.lang.text);
            try dumpBlockListField(writer, indent + indent_step, "content", admonition.content);
        },
        .list => |list| {
            try writeTypeTag(writer, "list");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", list.lang.text);
            try dumpOptionalNumberField(writer, indent + indent_step, "first", list.first);
            try dumpListItemsField(writer, indent + indent_step, "items", list.items);
        },
        .image => |image| {
            try writeTypeTag(writer, "image");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", image.lang.text);
            try dumpOptionalStringField(writer, indent + indent_step, "alt", image.alt);
            try dumpOptionalStringField(writer, indent + indent_step, "path", image.path);
            try dumpSpanListField(writer, indent + indent_step, "content", image.content);
        },
        .preformatted => |preformatted| {
            try writeTypeTag(writer, "preformatted");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", preformatted.lang.text);
            try dumpOptionalStringField(writer, indent + indent_step, "syntax", preformatted.syntax);
            try dumpSpanListField(writer, indent + indent_step, "content", preformatted.content);
        },
        .toc => |toc| {
            try writeTypeTag(writer, "toc");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", toc.lang.text);
            try dumpOptionalNumberField(writer, indent + indent_step, "depth", @as(?u8, toc.depth));
        },
        .footnotes => |footnotes| {
            try writeTypeTag(writer, "footnotes");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", footnotes.lang.text);
            try dumpFootnoteEntries(writer, indent + indent_step, footnotes.entries);
        },
        .table => |table| {
            try writeTypeTag(writer, "table");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", table.lang.text);
            try dumpOptionalNumberField(writer, indent + indent_step, "column_count", @as(?usize, table.column_count));
            try dumpBoolField(writer, indent + indent_step, "has_row_titles", table.has_row_titles);
            try dumpTableRowsField(writer, indent + indent_step, "rows", table.rows);
        },
    }
}

fn dumpOptionalDateTimeField(writer: *Writer, indent: usize, key: []const u8, value: ?hdoc.DateTime) Writer.Error!void {
    try writeIndent(writer, indent);
    if (value) |datetime| {
        try writer.print("{s}:\n", .{key});
        try dumpDateTime(writer, indent + indent_step, datetime);
    } else {
        try writer.print("{s}: null\n", .{key});
    }
}

fn dumpOptionalTitleField(writer: *Writer, indent: usize, key: []const u8, value: ?hdoc.Document.Title) Writer.Error!void {
    try writeIndent(writer, indent);
    if (value) |title| {
        try writer.print("{s}:\n", .{key});
        try dumpOptionalStringField(writer, indent + indent_step, "simple", title.simple);
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("full:\n");
        try dumpOptionalStringField(writer, indent + 2 * indent_step, "lang", title.full.lang.text);
        try dumpSpanListField(writer, indent + 2 * indent_step, "content", title.full.content);
    } else {
        try writer.print("{s}: null\n", .{key});
    }
}

fn dumpDocument(writer: *Writer, doc: *const hdoc.Document) Writer.Error!void {
    try writer.writeAll("document:\n");
    try dumpVersion(writer, indent_step, doc.version);
    try dumpOptionalStringField(writer, indent_step, "lang", doc.lang.text);
    try dumpOptionalTitleField(writer, indent_step, "title", doc.title);
    try dumpOptionalStringField(writer, indent_step, "author", doc.author);
    try dumpOptionalDateTimeField(writer, indent_step, "date", doc.date);
    try dumpTableOfContents(writer, indent_step, doc.toc);
    try dumpBlockListField(writer, indent_step, "contents", doc.contents);
    try dumpOptionalStringListField(writer, indent_step, "ids", doc.content_ids);
    // TODO: Dump ID map
}

pub fn render(doc: hdoc.Document, writer: *Writer) Writer.Error!void {
    try dumpDocument(writer, &doc);
}

test "render escapes string values" {
    const title = "Doc \"Title\"\n";
    const span_text = "Hello \"world\"\n";
    const link_ref: hdoc.Reference = .{ .text = "section \"A\"" };
    const id_value: hdoc.Reference = .{ .text = "id:1\n" };

    var doc: hdoc.Document = .{
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .version = .{ .major = 1, .minor = 2 },
        .contents = &.{},
        .content_ids = &.{},
        .id_map = .{},
        .toc = undefined,
        .lang = .inherit,
        .title = null,
        .author = null,
        .date = null,
        .timezone = null,
    };
    defer doc.deinit();

    const arena_alloc = doc.arena.allocator();

    const title_spans = try arena_alloc.alloc(hdoc.Span, 1);
    title_spans[0] = .{
        .content = .{ .text = title },
        .attribs = .{},
        .location = .{ .offset = 0, .length = title.len },
    };
    doc.title = .{
        .full = .{
            .lang = .inherit,
            .content = title_spans,
        },
        .simple = title,
    };

    doc.contents = try arena_alloc.alloc(hdoc.Block, 0);
    doc.content_ids = try arena_alloc.alloc(?hdoc.Reference, 0);
    doc.toc = .{
        .level = .h1,
        .headings = try arena_alloc.alloc(usize, 0),
        .children = try arena_alloc.alloc(hdoc.Document.TableOfContents, 0),
    };

    const spans = try arena_alloc.alloc(hdoc.Span, 1);
    spans[0] = .{
        .content = .{ .text = span_text },
        .attribs = .{ .link = .{ .ref = link_ref } },
        .location = .{ .offset = 0, .length = span_text.len },
    };

    const blocks = try arena_alloc.alloc(hdoc.Block, 1);
    blocks[0] = .{
        .heading = .{
            .level = .h1,
            .lang = .inherit,
            .content = spans,
        },
    };
    doc.contents = blocks;

    const ids = try arena_alloc.alloc(?hdoc.Reference, 1);
    ids[0] = id_value;
    doc.content_ids = ids;

    const headings = try arena_alloc.alloc(usize, 1);
    headings[0] = 0;

    const children = try arena_alloc.alloc(hdoc.Document.TableOfContents, 1);
    children[0] = .{ .level = .h2, .headings = &.{}, .children = &.{} };

    doc.toc = .{
        .level = .h1,
        .headings = headings,
        .children = children,
    };

    var buffer = Writer.Allocating.init(std.testing.allocator);
    defer buffer.deinit();

    try render(doc, &buffer.writer);
    try buffer.writer.flush();
    const output = buffer.writer.buffered();

    const expected_title_simple = try std.fmt.allocPrint(std.testing.allocator, "    simple: \"{f}\"\n", .{std.zig.fmtString(title)});
    defer std.testing.allocator.free(expected_title_simple);
    try std.testing.expect(std.mem.indexOf(u8, output, expected_title_simple) != null);

    const expected_span = try std.fmt.allocPrint(
        std.testing.allocator,
        "- [link=\"ref:{f}\"] \"{f}\"\n",
        .{ std.zig.fmtString(link_ref.text), std.zig.fmtString(span_text) },
    );
    defer std.testing.allocator.free(expected_span);
    try std.testing.expect(std.mem.indexOf(u8, output, expected_span) != null);

    const expected_id = try std.fmt.allocPrint(std.testing.allocator, "- \"{f}\"\n", .{std.zig.fmtString(id_value.text)});
    defer std.testing.allocator.free(expected_id);
    try std.testing.expect(std.mem.indexOf(u8, output, expected_id) != null);
}
