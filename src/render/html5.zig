//!
//! This file implements a HTML content renderer for HyperDoc.
//!
const std = @import("std");
const hdoc = @import("../hyperdoc.zig");

const Writer = std.Io.Writer;
const RenderError = Writer.Error || error{NoSpaceLeft};
const indent_step: usize = 2;

pub fn render(doc: hdoc.Document, writer: *Writer) RenderError!void {
    var ctx: RenderContext = .{ .doc = &doc, .writer = writer };

    try ctx.renderDocumentHeader();

    for (doc.contents, 0..) |block, index| {
        try ctx.renderBlock(block, index, 0);
    }
}

const RenderContext = struct {
    doc: *const hdoc.Document,
    writer: *Writer,

    fn renderBlock(ctx: *RenderContext, block: hdoc.Block, block_index: ?usize, indent: usize) RenderError!void {
        switch (block) {
            .heading => |heading| try ctx.renderHeading(heading, block_index, indent),
            .paragraph => |paragraph| try ctx.renderParagraph(paragraph, block_index, indent),
            .admonition => |admonition| try ctx.renderAdmonition(admonition, block_index, indent),
            .list => |list| try ctx.renderList(list, block_index, indent),
            .image => |image| try ctx.renderImage(image, block_index, indent),
            .preformatted => |preformatted| try ctx.renderPreformatted(preformatted, block_index, indent),
            .toc => |toc| try ctx.renderTableOfContents(toc, block_index, indent),
            .table => |table| try ctx.renderTable(table, block_index, indent),
            .footnotes => |footnotes| try ctx.renderFootnotes(footnotes, block_index, indent),
        }
    }

    fn renderDocumentHeader(ctx: *RenderContext) RenderError!void {
        const has_title = ctx.doc.title != null;
        const has_author = ctx.doc.author != null;
        const has_date = ctx.doc.date != null;

        if (!has_title and !has_author and !has_date) return;

        try writeStartTag(ctx.writer, "header", .regular, .{ .lang = langAttribute(ctx.doc.lang) });
        try ctx.writer.writeByte('\n');

        if (has_title) {
            const title = ctx.doc.title.?;
            try writeIndent(ctx.writer, indent_step);
            try writeStartTag(ctx.writer, "h1", .regular, .{ .lang = langAttribute(title.full.lang) });
            try ctx.renderSpans(title.full.content);
            try writeEndTag(ctx.writer, "h1");
            try ctx.writer.writeByte('\n');
        }

        if (has_author or has_date) {
            try writeIndent(ctx.writer, indent_step);
            try writeStartTag(ctx.writer, "p", .regular, .{ .class = "hdoc-doc-meta" });

            var wrote_any = false;
            if (has_author) {
                try ctx.writer.writeAll("By ");
                try writeEscapedHtml(ctx.writer, ctx.doc.author.?);
                wrote_any = true;
            }
            if (has_date) {
                if (wrote_any) {
                    try ctx.writer.writeAll(" - ");
                }

                var date_buffer: [128]u8 = undefined;
                const date_text = try formatIsoDateTime(ctx.doc.date.?, &date_buffer);
                try writeEscapedHtml(ctx.writer, date_text);
            }

            try writeEndTag(ctx.writer, "p");
            try ctx.writer.writeByte('\n');
        }

        try writeEndTag(ctx.writer, "header");
        try ctx.writer.writeByte('\n');
    }

    fn renderBlocks(ctx: *RenderContext, blocks: []const hdoc.Block, indent: usize) RenderError!void {
        for (blocks) |block| {
            try ctx.renderBlock(block, null, indent);
        }
    }

    fn renderHeading(ctx: *RenderContext, heading: hdoc.Block.Heading, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(heading.lang);

        var id_buffer: [32]u8 = undefined;
        const id_attr = if (block_index) |idx|
            ctx.resolveHeadingId(idx, &id_buffer)
        else
            null;

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, headingTag(heading.index), .regular, .{
            .id = id_attr,
            .lang = lang_attr,
        });

        // TODO: Make stylable:
        if (true) {
            var buffer: [32]u8 = undefined;
            try ctx.renderSpan(.{
                .content = .{
                    .text = switch (heading.index) {
                        .h1 => |level| std.fmt.bufPrint(&buffer, "§{} ", .{level[0]}) catch unreachable,
                        .h2 => |level| std.fmt.bufPrint(&buffer, "§{}.{} ", .{ level[0], level[1] }) catch unreachable,
                        .h3 => |level| std.fmt.bufPrint(&buffer, "§{}.{}.{} ", .{ level[0], level[1], level[2] }) catch unreachable,
                    },
                },
                .attribs = .{},
                .location = undefined,
            });
        }

        try ctx.renderSpans(heading.content);
        try writeEndTag(ctx.writer, headingTag(heading.index));
        try ctx.writer.writeByte('\n');
    }

    fn renderParagraph(ctx: *RenderContext, paragraph: hdoc.Block.Paragraph, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(paragraph.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "p", .regular, .{
            .id = id_attr,
            .lang = lang_attr,
        });
        try ctx.renderSpans(paragraph.content);
        try writeEndTag(ctx.writer, "p");
        try ctx.writer.writeByte('\n');
    }

    fn renderAdmonition(ctx: *RenderContext, admonition: hdoc.Block.Admonition, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(admonition.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        var class_buffer: [32]u8 = undefined;
        const class_attr = std.fmt.bufPrint(&class_buffer, "hdoc-{s}", .{@tagName(admonition.kind)}) catch unreachable;

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "div", .regular, .{
            .id = id_attr,
            .lang = lang_attr,
            .class = class_attr,
        });
        if (admonition.content.len > 0) {
            try ctx.writer.writeByte('\n');
            try ctx.renderBlocks(admonition.content, indent + indent_step);
            try writeIndent(ctx.writer, indent);
        }
        try writeEndTag(ctx.writer, "div");
        try ctx.writer.writeByte('\n');
    }

    fn renderList(ctx: *RenderContext, list: hdoc.Block.List, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(list.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        const tag = if (list.first != null)
            "ol"
        else
            "ul";

        try writeIndent(ctx.writer, indent);
        if (std.mem.eql(u8, tag, "ol")) {
            try writeStartTag(ctx.writer, tag, .regular, .{
                .id = id_attr,
                .lang = lang_attr,
                .start = list.first,
            });
        } else {
            try writeStartTag(ctx.writer, tag, .regular, .{
                .id = id_attr,
                .lang = lang_attr,
            });
        }
        try ctx.writer.writeByte('\n');

        for (list.items) |item| {
            try writeIndent(ctx.writer, indent + indent_step);
            try writeStartTag(ctx.writer, "li", .regular, .{ .lang = langAttribute(item.lang) });
            if (item.content.len > 0) {
                try ctx.writer.writeByte('\n');
                try ctx.renderBlocks(item.content, indent + 2 * indent_step);
                try writeIndent(ctx.writer, indent + indent_step);
            }
            try writeEndTag(ctx.writer, "li");
            try ctx.writer.writeByte('\n');
        }

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, tag);
        try ctx.writer.writeByte('\n');
    }

    fn renderImage(ctx: *RenderContext, image: hdoc.Block.Image, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(image.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "figure", .regular, .{ .id = id_attr, .lang = lang_attr });
        try ctx.writer.writeByte('\n');

        try writeIndent(ctx.writer, indent + indent_step);
        try writeStartTag(ctx.writer, "img", .auto_close, .{
            .src = image.path,
            .alt = image.alt,
        });
        try ctx.writer.writeByte('\n');

        if (image.content.len > 0) {
            try writeIndent(ctx.writer, indent + indent_step);
            try writeStartTag(ctx.writer, "figcaption", .regular, .{});
            try ctx.renderSpans(image.content);
            try writeEndTag(ctx.writer, "figcaption");
            try ctx.writer.writeByte('\n');
        }

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "figure");
        try ctx.writer.writeByte('\n');
    }

    fn renderPreformatted(ctx: *RenderContext, preformatted: hdoc.Block.Preformatted, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(preformatted.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "pre", .regular, .{ .id = id_attr, .lang = lang_attr });
        const class_attr = "hdoc-code";
        if (preformatted.syntax) |syntax| {
            try writeStartTag(ctx.writer, "code", .regular, .{ .class = class_attr, .data_syntax = syntax });
        } else {
            try writeStartTag(ctx.writer, "code", .regular, .{ .class = class_attr });
        }
        try ctx.renderSpans(preformatted.content);
        try writeEndTag(ctx.writer, "code");
        try writeEndTag(ctx.writer, "pre");
        try ctx.writer.writeByte('\n');
    }

    fn renderTableOfContents(ctx: *RenderContext, toc_block: hdoc.Block.TableOfContents, block_index: ?usize, indent: usize) RenderError!void {
        const depth = toc_block.depth;
        const lang_attr = langAttribute(toc_block.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        if (!tocHasEntries(ctx.doc.toc)) {
            return;
        }

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "nav", .regular, .{
            .id = id_attr,
            .lang = lang_attr,
            .aria_label = "Table of contents",
        });
        try ctx.writer.writeByte('\n');

        try ctx.renderTocList(ctx.doc.toc, indent + indent_step, depth, 1);

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "nav");
        try ctx.writer.writeByte('\n');
    }

    fn renderTocList(ctx: *RenderContext, node: hdoc.Document.TableOfContents, indent: usize, max_depth: u8, current_depth: u8) RenderError!void {
        if (node.headings.len == 0) {
            return;
        }

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "ol", .regular, .{});
        try ctx.writer.writeByte('\n');

        for (node.headings, 0..) |heading_index, child_index| {
            try writeIndent(ctx.writer, indent + indent_step);
            try writeStartTag(ctx.writer, "li", .regular, .{});

            const heading_block = ctx.doc.contents[heading_index].heading;
            var id_buffer: [32]u8 = undefined;
            const target_id = ctx.resolveHeadingId(heading_index, &id_buffer);

            var href_buffer: [64]u8 = undefined;
            const href = std.fmt.bufPrint(&href_buffer, "#{s}", .{target_id}) catch unreachable;

            try writeStartTag(ctx.writer, "a", .regular, .{ .href = href });
            try ctx.renderSpans(heading_block.content);
            try writeEndTag(ctx.writer, "a");

            const child_allowed = current_depth < max_depth and
                child_index < node.children.len and
                tocHasEntries(node.children[child_index]);
            if (child_allowed) {
                try ctx.writer.writeByte('\n');
                try ctx.renderTocList(node.children[child_index], indent + 2 * indent_step, max_depth, current_depth + 1);
                try writeIndent(ctx.writer, indent + indent_step);
            }

            try writeEndTag(ctx.writer, "li");
            try ctx.writer.writeByte('\n');
        }

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "ol");
        try ctx.writer.writeByte('\n');
    }

    fn renderTable(ctx: *RenderContext, table: hdoc.Block.Table, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(table.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        const column_count = table.column_count;
        const has_title_column = table.has_row_titles;

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "table", .regular, .{ .id = id_attr, .lang = lang_attr });
        try ctx.writer.writeByte('\n');

        const header_index = findHeaderIndex(table.rows);
        if (header_index) |index| {
            try writeIndent(ctx.writer, indent + indent_step);
            try writeStartTag(ctx.writer, "thead", .regular, .{});
            try ctx.writer.writeByte('\n');
            try ctx.renderHeaderRow(table.rows[index].columns, indent + 2 * indent_step, has_title_column);
            try writeIndent(ctx.writer, indent + indent_step);
            try writeEndTag(ctx.writer, "thead");
            try ctx.writer.writeByte('\n');
        }

        try writeIndent(ctx.writer, indent + indent_step);
        try writeStartTag(ctx.writer, "tbody", .regular, .{});
        try ctx.writer.writeByte('\n');

        for (table.rows, 0..) |row, index| {
            if (header_index) |head_idx| {
                if (index == head_idx) continue;
            }
            switch (row) {
                .columns => |columns| try ctx.renderHeaderRow(columns, indent + 2 * indent_step, has_title_column),
                .row => |data_row| try ctx.renderDataRow(data_row, indent + 2 * indent_step, has_title_column),
                .group => |group| try ctx.renderGroupRow(group, indent + 2 * indent_step, column_count, has_title_column),
            }
        }

        try writeIndent(ctx.writer, indent + indent_step);
        try writeEndTag(ctx.writer, "tbody");
        try ctx.writer.writeByte('\n');

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "table");
        try ctx.writer.writeByte('\n');
    }

    fn renderFootnotes(ctx: *RenderContext, footnotes: hdoc.Block.Footnotes, block_index: ?usize, indent: usize) RenderError!void {
        const lang_attr = langAttribute(footnotes.lang);
        const id_attr = ctx.resolveBlockId(block_index);

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "div", .regular, .{
            .id = id_attr,
            .lang = lang_attr,
            .class = "hdoc-footnotes",
        });
        try ctx.writer.writeByte('\n');

        const kinds = [_]hdoc.FootnoteKind{ .footnote, .citation };
        for (kinds) |kind| {
            var first_index: ?usize = null;
            var count: usize = 0;

            for (footnotes.entries) |entry| {
                if (entry.kind != kind)
                    continue;
                if (first_index == null)
                    first_index = entry.index;
                count += 1;
            }

            if (count == 0)
                continue;

            try writeIndent(ctx.writer, indent + indent_step);
            var class_buffer: [64]u8 = undefined;
            const list_class = std.fmt.bufPrint(&class_buffer, "hdoc-footnote-list hdoc-{s}", .{footnoteSlug(kind)}) catch unreachable;
            try writeStartTag(ctx.writer, "ol", .regular, .{
                .class = list_class,
                .start = first_index,
            });
            try ctx.writer.writeByte('\n');

            for (footnotes.entries) |entry| {
                if (entry.kind != kind)
                    continue;

                var id_buffer: [64]u8 = undefined;
                const entry_id = ctx.footnoteId(entry.kind, entry.index, &id_buffer);

                try writeIndent(ctx.writer, indent + 2 * indent_step);
                try writeStartTag(ctx.writer, "li", .regular, .{
                    .id = entry_id,
                    .lang = langAttribute(entry.lang),
                });
                if (entry.content.len > 0) {
                    try ctx.writer.writeByte('\n');
                    try writeIndent(ctx.writer, indent + 3 * indent_step);
                    try writeStartTag(ctx.writer, "p", .regular, .{ .lang = langAttribute(entry.lang) });
                    try ctx.renderSpans(entry.content);
                    try writeEndTag(ctx.writer, "p");
                    try ctx.writer.writeByte('\n');
                    try writeIndent(ctx.writer, indent + 2 * indent_step);
                }
                try writeEndTag(ctx.writer, "li");
                try ctx.writer.writeByte('\n');
            }

            try writeIndent(ctx.writer, indent + indent_step);
            try writeEndTag(ctx.writer, "ol");
            try ctx.writer.writeByte('\n');
        }

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "div");
        try ctx.writer.writeByte('\n');
    }

    fn renderHeaderRow(ctx: *RenderContext, columns: hdoc.Block.TableColumns, indent: usize, has_title_column: bool) RenderError!void {
        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "tr", .regular, .{ .lang = langAttribute(columns.lang) });
        try ctx.writer.writeByte('\n');

        if (has_title_column) {
            try writeIndent(ctx.writer, indent + indent_step);
            try writeStartTag(ctx.writer, "th", .regular, .{ .scope = "col" });
            try writeEndTag(ctx.writer, "th");
            try ctx.writer.writeByte('\n');
        }

        for (columns.cells) |cell| {
            try ctx.renderTableCellWithScope(cell, indent + indent_step, true, "col");
        }

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "tr");
        try ctx.writer.writeByte('\n');
    }

    fn renderDataRow(ctx: *RenderContext, row: hdoc.Block.TableDataRow, indent: usize, has_title_column: bool) RenderError!void {
        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "tr", .regular, .{ .lang = langAttribute(row.lang) });
        try ctx.writer.writeByte('\n');

        if (has_title_column) {
            try writeIndent(ctx.writer, indent + indent_step);
            try writeStartTag(ctx.writer, "th", .regular, .{ .scope = "row" });
            if (row.title) |title| {
                try writeEscapedHtml(ctx.writer, title);
            }
            try writeEndTag(ctx.writer, "th");
            try ctx.writer.writeByte('\n');
        }

        for (row.cells) |cell| {
            try ctx.renderTableCell(cell, indent + indent_step, false);
        }

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "tr");
        try ctx.writer.writeByte('\n');
    }

    fn renderGroupRow(ctx: *RenderContext, group: hdoc.Block.TableGroup, indent: usize, column_count: usize, has_title_column: bool) RenderError!void {
        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, "tr", .regular, .{ .lang = langAttribute(group.lang) });
        try ctx.writer.writeByte('\n');

        if (has_title_column) {
            try writeIndent(ctx.writer, indent + indent_step);
            try writeStartTag(ctx.writer, "td", .regular, .{});
            try writeEndTag(ctx.writer, "td");
            try ctx.writer.writeByte('\n');
        }

        try writeIndent(ctx.writer, indent + indent_step);
        try writeStartTag(ctx.writer, "th", .regular, .{
            .scope = "rowgroup",
            .colspan = @as(u32, @intCast(@max(@as(usize, 1), column_count))),
        });
        try ctx.renderSpans(group.content);
        try writeEndTag(ctx.writer, "th");
        try ctx.writer.writeByte('\n');

        try writeIndent(ctx.writer, indent);
        try writeEndTag(ctx.writer, "tr");
        try ctx.writer.writeByte('\n');
    }

    fn renderTableCell(ctx: *RenderContext, cell: hdoc.Block.TableCell, indent: usize, is_header: bool) RenderError!void {
        try ctx.renderTableCellWithScope(cell, indent, is_header, null);
    }

    fn renderTableCellWithScope(ctx: *RenderContext, cell: hdoc.Block.TableCell, indent: usize, is_header: bool, scope: ?[]const u8) RenderError!void {
        const tag = if (is_header) "th" else "td";
        const lang_attr = langAttribute(cell.lang);
        const colspan_attr: ?u32 = if (cell.colspan > 1) cell.colspan else null;

        try writeIndent(ctx.writer, indent);
        try writeStartTag(ctx.writer, tag, .regular, .{ .lang = lang_attr, .colspan = colspan_attr, .scope = scope });
        if (cell.content.len > 0) {
            try ctx.writer.writeByte('\n');
            try ctx.renderBlocks(cell.content, indent + indent_step);
            try writeIndent(ctx.writer, indent);
        }
        try writeEndTag(ctx.writer, tag);
        try ctx.writer.writeByte('\n');
    }

    fn resolveHeadingId(ctx: *RenderContext, index: usize, buffer: *[32]u8) []const u8 {
        if (index < ctx.doc.content_ids.len) {
            if (ctx.doc.content_ids[index]) |value| {
                return value.text;
            }
        }

        return std.fmt.bufPrint(buffer, "hdoc-auto-{d}", .{index}) catch unreachable;
    }

    fn resolveBlockId(ctx: *RenderContext, block_index: ?usize) ?[]const u8 {
        if (block_index) |idx| {
            if (idx < ctx.doc.content_ids.len) {
                if (ctx.doc.content_ids[idx]) |value| {
                    return value.text;
                }
            }
        }
        return null;
    }

    fn footnoteSlug(kind: hdoc.FootnoteKind) []const u8 {
        return switch (kind) {
            .footnote => "footnote",
            .citation => "citation",
        };
    }

    fn footnoteId(ctx: *RenderContext, kind: hdoc.FootnoteKind, index: usize, buffer: []u8) []const u8 {
        _ = ctx;
        return std.fmt.bufPrint(buffer, "hdoc-{s}-{d}", .{ footnoteSlug(kind), index }) catch unreachable;
    }

    fn renderSpans(ctx: *RenderContext, spans: []const hdoc.Span) RenderError!void {
        for (spans) |span| {
            try ctx.renderSpan(span);
        }
    }

    fn renderSpan(ctx: *RenderContext, span: hdoc.Span) RenderError!void {
        var pending_lang = langAttribute(span.attribs.lang);

        var opened: [6][]const u8 = undefined;
        var opened_len: usize = 0;

        const link_tag = span.attribs.link != .none;
        if (link_tag) {
            const href_value = switch (span.attribs.link) {
                .none => unreachable,
                .ref => |reference| blk: {
                    if (ctx.resolveBlockId(reference.block_index)) |resolved| {
                        var href_buffer: [128]u8 = undefined;
                        break :blk std.fmt.bufPrint(&href_buffer, "#{s}", .{resolved}) catch unreachable;
                    }

                    var href_buffer: [128]u8 = undefined;
                    break :blk std.fmt.bufPrint(&href_buffer, "#{s}", .{reference.ref.text}) catch unreachable;
                },
                .uri => |uri| uri.text,
            };

            try writeStartTag(ctx.writer, "a", .regular, .{ .href = href_value, .lang = takeLang(&pending_lang) });
            opened[opened_len] = "a";
            opened_len += 1;
        }

        switch (span.attribs.position) {
            .baseline => {},
            .subscript => {
                try writeStartTag(ctx.writer, "sub", .regular, .{ .lang = takeLang(&pending_lang) });
                opened[opened_len] = "sub";
                opened_len += 1;
            },
            .superscript => {
                try writeStartTag(ctx.writer, "sup", .regular, .{ .lang = takeLang(&pending_lang) });
                opened[opened_len] = "sup";
                opened_len += 1;
            },
        }

        if (span.attribs.strike) {
            try writeStartTag(ctx.writer, "s", .regular, .{ .lang = takeLang(&pending_lang) });
            opened[opened_len] = "s";
            opened_len += 1;
        }

        if (span.attribs.em) {
            try writeStartTag(ctx.writer, "em", .regular, .{ .lang = takeLang(&pending_lang) });
            opened[opened_len] = "em";
            opened_len += 1;
        }

        if (span.attribs.mono) {
            const syntax_attr = if (span.attribs.syntax.len > 0) span.attribs.syntax else null;
            try writeStartTag(ctx.writer, "code", .regular, .{ .lang = takeLang(&pending_lang), .class = "hdoc-code", .data_syntax = syntax_attr });
            opened[opened_len] = "code";
            opened_len += 1;
        }

        const content_lang = takeLang(&pending_lang);
        switch (span.content) {
            .text => |text| {
                if (content_lang) |lang| {
                    try writeStartTag(ctx.writer, "bdi", .regular, .{ .lang = lang });
                    try writeEscapedHtml(ctx.writer, text);
                    try writeEndTag(ctx.writer, "bdi");
                } else {
                    try writeEscapedHtml(ctx.writer, text);
                }
            },
            .date => |date| try ctx.renderDateTimeValue(.date, date, content_lang),
            .time => |time| try ctx.renderDateTimeValue(.time, time, content_lang),
            .datetime => |datetime| try ctx.renderDateTimeValue(.datetime, datetime, content_lang),
            .reference => |reference| {
                try ctx.renderReference(reference, content_lang);
            },
            .footnote => |footnote| {
                var id_buffer: [64]u8 = undefined;
                const target_id = ctx.footnoteId(footnote.kind, footnote.index, &id_buffer);
                var href_buffer: [64]u8 = undefined;
                const href = std.fmt.bufPrint(&href_buffer, "#{s}", .{target_id}) catch unreachable;

                var class_buffer: [64]u8 = undefined;
                const class_attr = std.fmt.bufPrint(&class_buffer, "hdoc-footnote-ref hdoc-{s}", .{footnoteSlug(footnote.kind)}) catch unreachable;

                try writeStartTag(ctx.writer, "sup", .regular, .{ .class = class_attr, .lang = content_lang });
                try writeStartTag(ctx.writer, "a", .regular, .{ .href = href });
                try ctx.writer.print("{d}", .{footnote.index});
                try writeEndTag(ctx.writer, "a");
                try writeEndTag(ctx.writer, "sup");
            },
        }

        while (opened_len > 0) {
            opened_len -= 1;
            try writeEndTag(ctx.writer, opened[opened_len]);
        }
    }

    fn renderReference(ctx: *RenderContext, reference: hdoc.Span.InlineReference, content_lang: ?[]const u8) RenderError!void {
        if (reference.target_block) |target_idx| {
            if (target_idx < ctx.doc.contents.len) {
                switch (ctx.doc.contents[target_idx]) {
                    .heading => |heading| return ctx.renderHeadingReference(reference, heading, content_lang),
                    else => {},
                }
            }
        }

        try ctx.renderReferenceText(reference.ref.text, content_lang);
    }

    fn renderHeadingReference(ctx: *RenderContext, reference: hdoc.Span.InlineReference, heading: hdoc.Block.Heading, content_lang: ?[]const u8) RenderError!void {
        var has_bdi = false;
        if (content_lang) |lang| {
            try writeStartTag(ctx.writer, "bdi", .regular, .{ .lang = lang });
            has_bdi = true;
        }

        const print_index = reference.fmt != .name;
        if (print_index) {
            var index_buffer: [32]u8 = undefined;
            const index_label = try formatHeadingIndexLabel(heading.index, &index_buffer);
            try writeEscapedHtml(ctx.writer, index_label);
        }

        if (reference.fmt == .full and heading.content.len > 0) {
            try ctx.writer.writeByte(' ');
        }

        switch (reference.fmt) {
            .full, .name => try ctx.renderReferenceTargetSpans(heading.content),
            .index => {},
        }

        if (has_bdi) {
            try writeEndTag(ctx.writer, "bdi");
        }
    }

    fn renderReferenceText(ctx: *RenderContext, text: []const u8, content_lang: ?[]const u8) RenderError!void {
        if (content_lang) |lang| {
            try writeStartTag(ctx.writer, "bdi", .regular, .{ .lang = lang });
            try writeEscapedHtml(ctx.writer, text);
            try writeEndTag(ctx.writer, "bdi");
            return;
        }

        try writeEscapedHtml(ctx.writer, text);
    }

    fn renderReferenceTargetSpans(ctx: *RenderContext, spans: []const hdoc.Span) RenderError!void {
        for (spans) |span| {
            var adjusted = span;
            adjusted.attribs.link = .none;
            try ctx.renderSpan(adjusted);
        }
    }

    fn renderDateTimeValue(ctx: *RenderContext, comptime kind: enum { date, time, datetime }, value: anytype, lang_attr: ?[]const u8) RenderError!void {
        var datetime_buffer: [128]u8 = undefined;
        const datetime_value = switch (kind) {
            .date => try formatIsoDate(value.value, &datetime_buffer),
            .time => try formatIsoTime(value.value, &datetime_buffer),
            .datetime => try formatIsoDateTime(value.value, &datetime_buffer),
        };

        var display_buffer: [128]u8 = undefined;
        const display_text = switch (kind) {
            .date => try formatDateValue(value, &display_buffer),
            .time => try formatTimeValue(value, &display_buffer),
            .datetime => try formatDateTimeValue(value, &display_buffer),
        };

        try writeStartTag(ctx.writer, "time", .regular, .{ .datetime = datetime_value, .lang = lang_attr });
        try ctx.writer.writeAll(display_text);
        try writeEndTag(ctx.writer, "time");
    }
};

fn writeIndent(writer: *Writer, indent: usize) RenderError!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeByte(' ');
    }
}

fn writeAttributeName(writer: *Writer, name: []const u8) RenderError!void {
    for (name) |char| {
        if (char == '_')
            try writer.writeByte('-')
        else
            try writer.writeByte(char);
    }
}

fn writeEscapedHtml(writer: *Writer, text: []const u8) RenderError!void {
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

            else => try writer.writeAll(slice),
        }
    }
}

fn writeStartTag(writer: *Writer, tag: []const u8, style: enum { regular, auto_close }, attribs: anytype) RenderError!void {
    try writer.print("<{s}", .{tag});

    const Attribs = @TypeOf(attribs);
    inline for (@typeInfo(Attribs).@"struct".fields) |fld| {
        const value = @field(attribs, fld.name);
        try writeAttribute(writer, fld.name, value);
    }

    switch (style) {
        .auto_close => try writer.writeAll("/>"),
        .regular => try writer.writeAll(">"),
    }
}

fn writeAttribute(writer: *Writer, name: []const u8, value: anytype) RenderError!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .bool => {
            if (value) {
                try writer.writeByte(' ');
                try writeAttributeName(writer, name);
            }
        },
        .optional => {
            if (value) |inner| {
                try writeAttribute(writer, name, inner);
            }
        },
        .int, .comptime_int => try writeNumericAttribute(writer, name, value),
        .float, .comptime_float => try writeFloatAttribute(writer, name, value),
        .@"enum" => try writeStringAttribute(writer, name, @tagName(value)),
        .pointer => |info| switch (info.size) {
            .slice => {
                if (info.child != u8) @compileError("unsupported pointer type " ++ @typeName(T));
                try writeStringAttribute(writer, name, value);
            },
            .one => {
                const child = @typeInfo(info.child);
                if (child != .array) @compileError("unsupported pointer type " ++ @typeName(T));
                if (child.array.child != u8) @compileError("unsupported pointer type " ++ @typeName(T));
                const slice: []const u8 = value[0..child.array.len];
                try writeStringAttribute(writer, name, slice);
            },
            else => @compileError("unsupported pointer type " ++ @typeName(T)),
        },
        .array => |info| {
            if (info.child != u8) @compileError("unsupported array type " ++ @typeName(T));
            const slice: []const u8 = value[0..];
            try writeStringAttribute(writer, name, slice);
        },
        else => switch (T) {
            []u8, []const u8 => try writeStringAttribute(writer, name, value),
            else => @compileError("unsupported tag type " ++ @typeName(T) ++ ", implement support above."),
        },
    }
}

fn writeStringAttribute(writer: *Writer, name: []const u8, value: []const u8) RenderError!void {
    try writer.writeByte(' ');
    try writeAttributeName(writer, name);
    try writer.writeByte('=');
    try writer.writeByte('"');
    try writeEscapedHtml(writer, value);
    try writer.writeByte('"');
}

fn writeNumericAttribute(writer: *Writer, name: []const u8, value: anytype) RenderError!void {
    try writer.writeByte(' ');
    try writeAttributeName(writer, name);
    try writer.print("=\"{}\"", .{value});
}

fn writeFloatAttribute(writer: *Writer, name: []const u8, value: anytype) RenderError!void {
    try writer.writeByte(' ');
    try writeAttributeName(writer, name);
    try writer.print("=\"{d}\"", .{value});
}

fn writeEndTag(writer: *Writer, tag: []const u8) RenderError!void {
    try writer.print("</{s}>", .{tag});
}

fn langAttribute(lang: hdoc.LanguageTag) ?[]const u8 {
    if (lang.text.len == 0)
        return null;
    return lang.text;
}

fn takeLang(lang: *?[]const u8) ?[]const u8 {
    if (lang.*) |value| {
        lang.* = null;
        return value;
    }
    return null;
}

fn headingTag(level: hdoc.Block.Heading.Level) []const u8 {
    return switch (level) {
        .h1 => "h2",
        .h2 => "h3",
        .h3 => "h4",
    };
}

fn tocHasEntries(node: hdoc.Document.TableOfContents) bool {
    if (node.headings.len > 0) return true;
    for (node.children) |child| {
        if (tocHasEntries(child)) return true;
    }
    return false;
}

fn findHeaderIndex(rows: []const hdoc.Block.TableRow) ?usize {
    if (rows.len > 0 and rows[0] == .columns) return 0;
    return null;
}

fn formatIsoDate(value: hdoc.Date, buffer: []u8) RenderError![]const u8 {
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ value.year, value.month, value.day }) catch unreachable;
}

fn writeTimeZone(writer: anytype, timezone: hdoc.TimeZoneOffset) RenderError!void {
    const minutes = @intFromEnum(timezone);
    if (minutes == 0) {
        try writer.writeByte('Z');
        return;
    }

    const sign: u8 = if (minutes < 0) '-' else '+';
    const abs_minutes: u32 = @intCast(@abs(minutes));
    const hour: u32 = abs_minutes / 60;
    const minute: u32 = abs_minutes % 60;

    try writer.print("{c}{d:0>2}:{d:0>2}", .{ sign, hour, minute });
}

fn formatIsoTime(value: hdoc.Time, buffer: []u8) RenderError![]const u8 {
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();

    try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ value.hour, value.minute, value.second });
    if (value.microsecond > 0) {
        try writer.print(".{d:0>6}", .{value.microsecond});
    }
    try writeTimeZone(writer, value.timezone);

    return stream.getWritten();
}

fn formatIsoDateTime(value: hdoc.DateTime, buffer: []u8) RenderError![]const u8 {
    var date_buffer: [32]u8 = undefined;
    var time_buffer: [64]u8 = undefined;

    const date_text = try formatIsoDate(value.date, &date_buffer);
    const time_text = try formatIsoTime(value.time, &time_buffer);

    return std.fmt.bufPrint(buffer, "{s}T{s}", .{ date_text, time_text }) catch unreachable;
}

fn formatHeadingIndexLabel(index: hdoc.Block.Heading.Index, buffer: []u8) RenderError![]const u8 {
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();

    const parts = switch (index) {
        .h1 => index.h1[0..1],
        .h2 => index.h2[0..2],
        .h3 => index.h3[0..3],
    };

    for (parts, 0..) |value, idx| {
        if (idx != 0) try writer.writeByte('.');
        try writer.print("{d}", .{value});
    }
    try writer.writeByte('.');

    return stream.getWritten();
}

fn formatDateValue(value: hdoc.FormattedDateTime(hdoc.Date), buffer: []u8) RenderError![]const u8 {
    return switch (value.format) {
        .year => std.fmt.bufPrint(buffer, "{d}", .{value.value.year}) catch unreachable,
        .month => std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}", .{ value.value.year, value.value.month }) catch unreachable,
        .day => std.fmt.bufPrint(buffer, "{d:0>2}", .{value.value.day}) catch unreachable,
        .weekday => std.fmt.bufPrint(buffer, "{s}", .{weekdayName(value.value)}) catch unreachable,
        .short, .long, .relative, .iso => formatIsoDate(value.value, buffer),
    };
}

fn formatTimeValue(value: hdoc.FormattedDateTime(hdoc.Time), buffer: []u8) RenderError![]const u8 {
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();

    switch (value.format) {
        .short, .rough => try writer.print("{d:0>2}:{d:0>2}", .{ value.value.hour, value.value.minute }),
        .long => {
            try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ value.value.hour, value.value.minute, value.value.second });
            if (value.value.microsecond > 0) {
                try writer.print(".{d:0>6}", .{value.value.microsecond});
            }
        },
        .iso => try writer.writeAll(try formatIsoTime(value.value, buffer)),
    }

    if (value.format != .iso) {
        try writer.writeByte(' ');
        try writeTimeZone(writer, value.value.timezone);
    }

    return stream.getWritten();
}

fn formatDateTimeValue(value: hdoc.FormattedDateTime(hdoc.DateTime), buffer: []u8) RenderError![]const u8 {
    var date_buffer: [32]u8 = undefined;
    var time_buffer: [64]u8 = undefined;

    const date_text = try formatIsoDate(value.value.date, &date_buffer);

    return switch (value.format) {
        .short => std.fmt.bufPrint(buffer, "{s} {s}", .{
            date_text,
            try formatTimeValue(.{ .format = .short, .value = value.value.time }, &time_buffer),
        }) catch unreachable,
        .long, .relative => std.fmt.bufPrint(buffer, "{s} {s}", .{
            date_text,
            try formatTimeValue(.{ .format = .long, .value = value.value.time }, &time_buffer),
        }) catch unreachable,
        .iso => formatIsoDateTime(value.value, buffer),
    };
}

fn weekdayName(date: hdoc.Date) []const u8 {
    const y = if (date.month < 3) date.year - 1 else date.year;
    const m = if (date.month < 3) date.month + 12 else date.month;
    const k: i32 = @mod(y, 100);
    const j: i32 = @divTrunc(y, 100);

    const day_component: i32 = @intCast(date.day);
    const z: i32 = day_component + @divTrunc(13 * (m + 1), 5) + k + @divTrunc(k, 4) + @divTrunc(j, 4) + 5 * j;
    const h: i32 = @mod(z, 7);
    return switch (h) {
        0 => "Saturday",
        1 => "Sunday",
        2 => "Monday",
        3 => "Tuesday",
        4 => "Wednesday",
        5 => "Thursday",
        6 => "Friday",
        else => "",
    };
}
