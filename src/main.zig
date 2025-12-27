const std = @import("std");
const builtin = @import("builtin");
const hdoc = @import("hyperdoc");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

const indent_step: usize = 2;

fn writeIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeByte(' ');
    }
}

fn writeStringValue(writer: anytype, value: []const u8) !void {
    try writer.print("\"{f}\"", .{std.zig.fmtString(value)});
}

fn writeOptionalStringValue(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeStringValue(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn writeOptionalIntValue(writer: anytype, value: anytype) !void {
    if (value) |number| {
        try writer.print("{}", .{number});
    } else {
        try writer.writeAll("null");
    }
}

fn dumpOptionalStringField(writer: anytype, indent: usize, key: []const u8, value: ?[]const u8) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: ", .{key});
    try writeOptionalStringValue(writer, value);
    try writer.writeByte('\n');
}

fn dumpOptionalNumberField(writer: anytype, indent: usize, key: []const u8, value: anytype) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: ", .{key});
    try writeOptionalIntValue(writer, value);
    try writer.writeByte('\n');
}

fn dumpBoolField(writer: anytype, indent: usize, key: []const u8, value: bool) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: {}\n", .{ key, value });
}

fn dumpEnumField(writer: anytype, indent: usize, key: []const u8, value: anytype) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: {s}\n", .{ key, @tagName(value) });
}

fn dumpVersion(writer: anytype, indent: usize, version: hdoc.Version) !void {
    try writeIndent(writer, indent);
    try writer.writeAll("version:\n");
    try writeIndent(writer, indent + indent_step);
    try writer.print("major: {}\n", .{version.major});
    try writeIndent(writer, indent + indent_step);
    try writer.print("minor: {}\n", .{version.minor});
}

fn dumpDate(writer: anytype, indent: usize, date: hdoc.Date) !void {
    try writeIndent(writer, indent);
    try writer.print("year: {}\n", .{date.year});
    try writeIndent(writer, indent);
    try writer.print("month: {}\n", .{date.month});
    try writeIndent(writer, indent);
    try writer.print("day: {}\n", .{date.day});
}

fn dumpTime(writer: anytype, indent: usize, time: hdoc.Time) !void {
    try writeIndent(writer, indent);
    try writer.print("hour: {}\n", .{time.hour});
    try writeIndent(writer, indent);
    try writer.print("minute: {}\n", .{time.minute});
    try writeIndent(writer, indent);
    try writer.print("second: {}\n", .{time.second});
    try writeIndent(writer, indent);
    try writer.print("microsecond: {}\n", .{time.microsecond});
}

fn dumpDateTime(writer: anytype, indent: usize, datetime: hdoc.DateTime) !void {
    try writeIndent(writer, indent);
    try writer.writeAll("date:\n");
    try dumpDate(writer, indent + indent_step, datetime.date);
    try writeIndent(writer, indent);
    try writer.writeAll("time:\n");
    try dumpTime(writer, indent + indent_step, datetime.time);
}

fn writeAttrSeparator(writer: anytype, first: *bool) !void {
    if (first.*) {
        first.* = false;
    } else {
        try writer.writeByte(' ');
    }
}

fn writeSpanAttributes(writer: anytype, span: hdoc.Span) !void {
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
            try writer.print("link=\"ref:{f}\"", .{std.zig.fmtString(value.text)});
        },
        .uri => |value| {
            try writeAttrSeparator(writer, &first);
            try writer.print("link=\"uri:{f}\"", .{std.zig.fmtString(value.text)});
        },
    }
    if (span.attribs.lang.len != 0) {
        try writeAttrSeparator(writer, &first);
        try writer.print("lang=\"{f}\"", .{std.zig.fmtString(span.attribs.lang)});
    }
    if (span.attribs.syntax.len != 0) {
        try writeAttrSeparator(writer, &first);
        try writer.print("syntax=\"{f}\"", .{std.zig.fmtString(span.attribs.syntax)});
    }
    try writer.writeByte(']');
}

fn writeDateValue(writer: anytype, date: hdoc.Date) !void {
    try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ date.year, date.month, date.day });
}

fn writeTimeValue(writer: anytype, time: hdoc.Time) !void {
    try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ time.hour, time.minute, time.second });
    if (time.microsecond != 0) {
        try writer.print(".{d:0>6}", .{time.microsecond});
    }
}

fn writeDateTimeValue(writer: anytype, datetime: hdoc.DateTime) !void {
    try writeDateValue(writer, datetime.date);
    try writer.writeByte('T');
    try writeTimeValue(writer, datetime.time);
}

fn writeFormattedDateInline(writer: anytype, formatted: hdoc.FormattedDateTime(hdoc.Date)) !void {
    try writer.writeAll("date:");
    try writeDateValue(writer, formatted.value);
    if (formatted.format != hdoc.Date.Format.default) {
        try writer.writeByte('@');
        try writer.writeAll(@tagName(formatted.format));
    }
}

fn writeFormattedTimeInline(writer: anytype, formatted: hdoc.FormattedDateTime(hdoc.Time)) !void {
    try writer.writeAll("time:");
    try writeTimeValue(writer, formatted.value);
    if (formatted.format != hdoc.Time.Format.default) {
        try writer.writeByte('@');
        try writer.writeAll(@tagName(formatted.format));
    }
}

fn writeFormattedDateTimeInline(writer: anytype, formatted: hdoc.FormattedDateTime(hdoc.DateTime)) !void {
    try writer.writeAll("datetime:");
    try writeDateTimeValue(writer, formatted.value);
    if (formatted.format != hdoc.DateTime.Format.default) {
        try writer.writeByte('@');
        try writer.writeAll(@tagName(formatted.format));
    }
}

fn writeSpanContentInline(writer: anytype, content: hdoc.Span.Content) !void {
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
    }
}

fn dumpSpanInline(writer: anytype, span: hdoc.Span) !void {
    try writeSpanAttributes(writer, span);
    try writer.writeByte(' ');
    try writeSpanContentInline(writer, span.content);
}

fn dumpSpanListField(writer: anytype, indent: usize, key: []const u8, spans: []const hdoc.Span) !void {
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

fn dumpListItem(writer: anytype, indent: usize, item: hdoc.Block.ListItem) !void {
    try dumpOptionalStringField(writer, indent, "lang", item.lang);
    try dumpSpanListField(writer, indent, "content", item.content);
}

fn dumpListItemsField(writer: anytype, indent: usize, key: []const u8, items: []const hdoc.Block.ListItem) !void {
    try writeIndent(writer, indent);
    if (items.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (items) |item| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("-\n");
        try dumpListItem(writer, indent + indent_step * 2, item);
    }
}

fn dumpTableCell(writer: anytype, indent: usize, cell: hdoc.Block.TableCell) !void {
    try dumpOptionalStringField(writer, indent, "lang", cell.lang);
    try dumpOptionalNumberField(writer, indent, "colspan", cell.colspan);
    try dumpSpanListField(writer, indent, "content", cell.content);
}

fn dumpTableCellsField(writer: anytype, indent: usize, key: []const u8, cells: []const hdoc.Block.TableCell) !void {
    try writeIndent(writer, indent);
    if (cells.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (cells) |cell| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("-\n");
        try dumpTableCell(writer, indent + indent_step * 2, cell);
    }
}

fn dumpTableColumns(writer: anytype, indent: usize, columns: hdoc.Block.TableColumns) !void {
    try dumpOptionalStringField(writer, indent, "lang", columns.lang);
    try dumpTableCellsField(writer, indent, "cells", columns.cells);
}

fn dumpTableDataRow(writer: anytype, indent: usize, row: hdoc.Block.TableDataRow) !void {
    try dumpOptionalStringField(writer, indent, "lang", row.lang);
    try dumpOptionalStringField(writer, indent, "title", row.title);
    try dumpTableCellsField(writer, indent, "cells", row.cells);
}

fn dumpTableGroup(writer: anytype, indent: usize, group: hdoc.Block.TableGroup) !void {
    try dumpOptionalStringField(writer, indent, "lang", group.lang);
    try dumpSpanListField(writer, indent, "content", group.content);
}

fn dumpTableRow(writer: anytype, indent: usize, row: hdoc.Block.TableRow) !void {
    switch (row) {
        .columns => |columns| {
            try writeIndent(writer, indent);
            try writer.writeAll("columns:\n");
            try dumpTableColumns(writer, indent + indent_step, columns);
        },
        .row => |data_row| {
            try writeIndent(writer, indent);
            try writer.writeAll("row:\n");
            try dumpTableDataRow(writer, indent + indent_step, data_row);
        },
        .group => |group| {
            try writeIndent(writer, indent);
            try writer.writeAll("group:\n");
            try dumpTableGroup(writer, indent + indent_step, group);
        },
    }
}

fn dumpTableRowsField(writer: anytype, indent: usize, key: []const u8, rows: []const hdoc.Block.TableRow) !void {
    try writeIndent(writer, indent);
    if (rows.len == 0) {
        try writer.print("{s}: []\n", .{key});
        return;
    }
    try writer.print("{s}:\n", .{key});
    for (rows) |row| {
        try writeIndent(writer, indent + indent_step);
        try writer.writeAll("-\n");
        try dumpTableRow(writer, indent + indent_step * 2, row);
    }
}

fn dumpBlockInline(writer: anytype, indent: usize, block: hdoc.Block) !void {
    switch (block) {
        .heading => |heading| {
            try writer.writeAll("heading:\n");
            try dumpEnumField(writer, indent + indent_step, "level", heading.level);
            try dumpOptionalStringField(writer, indent + indent_step, "lang", heading.lang);
            try dumpSpanListField(writer, indent + indent_step, "content", heading.content);
        },
        .paragraph => |paragraph| {
            try writer.writeAll("paragraph:\n");
            try dumpEnumField(writer, indent + indent_step, "kind", paragraph.kind);
            try dumpOptionalStringField(writer, indent + indent_step, "lang", paragraph.lang);
            try dumpSpanListField(writer, indent + indent_step, "content", paragraph.content);
        },
        .list => |list| {
            try writer.writeAll("list:\n");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", list.lang);
            try dumpOptionalNumberField(writer, indent + indent_step, "first", list.first);
            try dumpListItemsField(writer, indent + indent_step, "items", list.items);
        },
        .image => |image| {
            try writer.writeAll("image:\n");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", image.lang);
            try dumpOptionalStringField(writer, indent + indent_step, "alt", image.alt);
            try dumpOptionalStringField(writer, indent + indent_step, "path", image.path);
            try dumpSpanListField(writer, indent + indent_step, "content", image.content);
        },
        .preformatted => |preformatted| {
            try writer.writeAll("preformatted:\n");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", preformatted.lang);
            try dumpOptionalStringField(writer, indent + indent_step, "syntax", preformatted.syntax);
            try dumpSpanListField(writer, indent + indent_step, "content", preformatted.content);
        },
        .toc => |toc| {
            try writer.writeAll("toc:\n");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", toc.lang);
            try dumpOptionalNumberField(writer, indent + indent_step, "depth", toc.depth);
        },
        .table => |table| {
            try writer.writeAll("table:\n");
            try dumpOptionalStringField(writer, indent + indent_step, "lang", table.lang);
            try dumpTableRowsField(writer, indent + indent_step, "rows", table.rows);
        },
    }
}

fn dumpBlockListField(writer: anytype, indent: usize, key: []const u8, blocks: []const hdoc.Block) !void {
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

fn dumpOptionalStringListField(writer: anytype, indent: usize, key: []const u8, values: []?hdoc.Reference) !void {
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

fn dumpOptionalDateTimeField(writer: anytype, indent: usize, key: []const u8, value: ?hdoc.DateTime) !void {
    try writeIndent(writer, indent);
    if (value) |datetime| {
        try writer.print("{s}:\n", .{key});
        try dumpDateTime(writer, indent + indent_step, datetime);
    } else {
        try writer.print("{s}: null\n", .{key});
    }
}

fn dumpDocument(writer: anytype, doc: *const hdoc.Document) !void {
    try writer.writeAll("document:\n");
    try dumpVersion(writer, indent_step, doc.version);
    try dumpOptionalStringField(writer, indent_step, "lang", doc.lang);
    try dumpOptionalStringField(writer, indent_step, "title", doc.title);
    try dumpOptionalStringField(writer, indent_step, "author", doc.author);
    try dumpOptionalDateTimeField(writer, indent_step, "date", doc.date);
    try dumpBlockListField(writer, indent_step, "contents", doc.contents);
    try dumpOptionalStringListField(writer, indent_step, "ids", doc.ids);
}

test "dumpDocument escapes string values" {
    const title = "Doc \"Title\"\n";
    const span_text = "Hello \"world\"\n";
    const link_ref: hdoc.Reference = .init("section \"A\"");
    const id_value: hdoc.Reference = .init("id:1\n");

    var doc: hdoc.Document = .{
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .version = .{ .major = 1, .minor = 2 },
        .contents = &.{},
        .ids = &.{},
        .lang = null,
        .title = title,
        .author = null,
        .date = null,
    };
    defer doc.deinit();

    const arena_alloc = doc.arena.allocator();

    const spans = try arena_alloc.alloc(hdoc.Span, 1);
    spans[0] = .{
        .content = .{ .text = span_text },
        .attribs = .{ .link = .{ .ref = link_ref } },
    };

    const blocks = try arena_alloc.alloc(hdoc.Block, 1);
    blocks[0] = .{
        .heading = .{
            .level = .h1,
            .lang = null,
            .content = spans,
        },
    };
    doc.contents = blocks;

    const ids = try arena_alloc.alloc(?hdoc.Reference, 1);
    ids[0] = id_value;
    doc.ids = ids;

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try dumpDocument(buffer.writer(std.testing.allocator), &doc);
    const output = buffer.items;

    const expected_title = try std.fmt.allocPrint(std.testing.allocator, "title: \"{f}\"\n", .{std.zig.fmtString(title)});
    defer std.testing.allocator.free(expected_title);
    try std.testing.expect(std.mem.indexOf(u8, output, expected_title) != null);

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

pub fn main() !u8 {
    defer if (builtin.mode == .Debug) {
        std.debug.assert(debug_allocator.deinit() == .ok);
    };
    const allocator = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("usage: {s} <file>\n", .{args[0]});
        return 1;
    }

    const path = args[1];
    const document = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 10);
    defer allocator.free(document);

    var diagnostics: hdoc.Diagnostics = .init(allocator);
    defer diagnostics.deinit();

    var parsed = try hdoc.parse(allocator, document, &diagnostics);
    defer parsed.deinit();

    if (diagnostics.has_error())
        return 1;

    const stdout = std.fs.File.stdout().deprecatedWriter();
    try dumpDocument(stdout, &parsed);

    return 0;
}
