const std = @import("std");
const parser_toolkit = @import("parser-toolkit");

/// A HyperDoc document. Contains both memory and
/// tree structure of the document.
pub const Document = struct {
    arena: std.heap.ArenaAllocator,

    version: Version,

    // document contents:
    contents: []Block,
    ids: []?Reference,

    // header information
    lang: ?[]const u8,
    title: ?[]const u8,
    author: ?[]const u8,
    date: ?DateTime,
    timezone: ?[]const u8,

    pub fn deinit(doc: *Document) void {
        doc.arena.deinit();
        doc.* = undefined;
    }
};

/// A top level layouting element of a document.
/// Each block is a rectangular element on the screen with
/// variable height, but a fixed width.
/// Depending on the level of nesting, the width might decrease
/// from the full document size.
pub const Block = union(enum) {
    heading: Heading,
    paragraph: Paragraph,
    list: List,
    image: Image,
    preformatted: Preformatted,
    toc: TableOfContents,
    table: Table,

    pub const Heading = struct {
        level: HeadingLevel,
        lang: ?[]const u8,
        content: []Span,
    };

    pub const HeadingLevel = enum { h1, h2, h3 };

    pub const Paragraph = struct {
        kind: ParagraphKind,
        lang: ?[]const u8,
        content: []Span,
    };

    pub const ParagraphKind = enum { p, note, warning, danger, tip, quote, spoiler };

    pub const List = struct {
        lang: ?[]const u8,
        first: ?u32,
        items: []ListItem,
    };

    pub const ListItem = struct {
        lang: ?[]const u8,
        content: []Span,
    };

    pub const Image = struct {
        lang: ?[]const u8,
        alt: ?[]const u8,
        path: ?[]const u8,
        content: []Span,
    };

    pub const Preformatted = struct {
        lang: ?[]const u8,
        syntax: ?[]const u8,
        content: []Span,
    };

    pub const TableOfContents = struct {
        lang: ?[]const u8,
        depth: ?u8,
    };

    pub const Table = struct {
        lang: ?[]const u8,
        rows: []TableRow,
    };

    pub const TableRow = union(enum) {
        columns: TableColumns,
        row: TableDataRow,
        group: TableGroup,
    };

    pub const TableColumns = struct {
        lang: ?[]const u8,
        cells: []TableCell,
    };

    pub const TableDataRow = struct {
        lang: ?[]const u8,
        title: ?[]const u8,
        cells: []TableCell,
    };

    pub const TableGroup = struct {
        lang: ?[]const u8,
        content: []Span,
    };

    pub const TableCell = struct {
        lang: ?[]const u8,
        colspan: ?u32,
        content: []Span,
    };
};

pub fn FormattedDateTime(comptime DT: type) type {
    return struct {
        value: DT,
        format: DT.Format = .default,
    };
}

pub const Span = struct {
    pub const Content = union(enum) {
        text: []const u8,
        date: FormattedDateTime(Date),
        time: FormattedDateTime(Time),
        datetime: FormattedDateTime(DateTime),
    };

    pub const Attributes = struct {
        lang: []const u8 = "", // empty is absence
        position: ScriptPosition = .baseline,
        em: bool = false,
        mono: bool = false,
        strike: bool = false,
        link: Link = .none,
        syntax: []const u8 = "", // empty is absence
    };

    content: Content,
    attribs: Attributes,
};

pub const ScriptPosition = enum {
    baseline,
    superscript,
    subscript,
};

pub const Link = union(enum) {
    none,
    ref: Reference,
    uri: Uri,
};

/// HyperDoc Version Number
pub const Version = struct {
    major: u16,
    minor: u16,

    pub fn parse(text: []const u8) !Version {
        const split_index = std.mem.indexOfScalar(u8, text, '.') orelse return error.InvalidValue;

        const head = text[0..split_index];
        const tail = text[split_index + 1 ..];

        return .{
            .major = std.fmt.parseInt(u16, head, 10) catch return error.InvalidValue,
            .minor = std.fmt.parseInt(u16, tail, 10) catch return error.InvalidValue,
        };
    }
};

pub const DateTime = struct {
    pub const Format = enum {
        pub const default: Format = .short;

        short,
        long,
        relative,
        iso,
    };

    date: Date,
    time: Time,

    pub fn parse(text: []const u8, default_timezone: ?[]const u8) !DateTime {
        const split_index = std.mem.indexOfScalar(u8, text, 'T') orelse return error.InvalidValue;

        const head = text[0..split_index];
        const tail = text[split_index + 1 ..];

        return .{
            .date = try Date.parse(head),
            .time = try Time.parse(tail, default_timezone),
        };
    }
};

pub const Date = struct {
    pub const Format = enum {
        pub const default: Format = .short;
        year,
        month,
        day,
        weekday,
        short,
        long,
        relative,
        iso,
    };

    year: i32, // e.g., 2024
    month: u4, // 1-12
    day: u5, // 1-31

    pub fn parse(text: []const u8) !Date {
        if (text.len < 7) // "Y-MM-DD"
            return error.InvalidValue;
        const first_dash = std.mem.indexOfScalar(u8, text, '-') orelse return error.InvalidValue;
        const tail = text[first_dash + 1 ..];
        const second_dash_rel = std.mem.indexOfScalar(u8, tail, '-') orelse return error.InvalidValue;
        const second_dash = first_dash + 1 + second_dash_rel;

        const year_text = text[0..first_dash];
        const month_text = text[first_dash + 1 .. second_dash];
        const day_text = text[second_dash + 1 ..];

        if (year_text.len == 0 or month_text.len != 2 or day_text.len != 2) return error.InvalidValue;

        const year_value = std.fmt.parseInt(u32, year_text, 10) catch return error.InvalidValue;
        if (year_value > std.math.maxInt(i32)) return error.InvalidValue;

        const month_value = std.fmt.parseInt(u8, month_text, 10) catch return error.InvalidValue;
        const day_value = std.fmt.parseInt(u8, day_text, 10) catch return error.InvalidValue;

        if (month_value < 1 or month_value > 12) return error.InvalidValue;
        if (day_value < 1 or day_value > 31) return error.InvalidValue;

        return .{
            .year = @intCast(year_value),
            .month = @intCast(month_value),
            .day = @intCast(day_value),
        };
    }
};

pub const Time = struct {
    pub const Format = enum {
        pub const default: Format = .short;

        long,
        short,
        rough,
        relative,
        iso,
    };

    hour: u5, // 0-23
    minute: u6, // 0-59
    second: u6, // 0-59
    microsecond: u20, // 0-999999
    zone_offset: i32, // in minutes

    pub fn parse(text: []const u8, default_timezone: ?[]const u8) !Time {
        if (text.len < 8) // "HH:MM:SS"
            return error.InvalidValue;

        const hour = std.fmt.parseInt(u8, text[0..2], 10) catch return error.InvalidValue;
        if (text[2] != ':') return error.InvalidValue;
        const minute = std.fmt.parseInt(u8, text[3..5], 10) catch return error.InvalidValue;
        if (text[5] != ':') return error.InvalidValue;
        const second = std.fmt.parseInt(u8, text[6..8], 10) catch return error.InvalidValue;

        if (hour > 23 or minute > 59 or second > 59) return error.InvalidValue;

        var index: usize = 8;
        var microsecond: u20 = 0;

        if (index < text.len) {
            if (text[index] == '.') {
                const start = index + 1;
                var end = start;
                while (end < text.len and std.ascii.isDigit(text[end])) : (end += 1) {}
                if (end == start) return error.InvalidValue;

                const fraction_value = std.fmt.parseInt(u64, text[start..end], 10) catch return error.InvalidValue;
                microsecond = fractionToMicrosecond(end - start, fraction_value) orelse return error.InvalidValue;
                index = end;
            }
        }

        const timezone = if (index == text.len)
            default_timezone orelse return error.MissingTimezone
        else
            text[index..];

        if (timezone.len != 1 and timezone.len != 6) // "Z" or "±HH:MM"
            return error.InvalidValue;

        if (timezone.len == 1) {
            if (timezone[0] != 'Z')
                return error.InvalidValue;
            return .{
                .hour = @intCast(hour),
                .minute = @intCast(minute),
                .second = @intCast(second),
                .microsecond = microsecond,
                .zone_offset = 0,
            };
        }
        std.debug.assert(timezone.len == 6);

        const sign_char = timezone[0];
        const sign: i32 = switch (sign_char) {
            '+' => 1,
            '-' => -1,
            else => return error.InvalidValue,
        };
        if (timezone[3] != ':')
            return error.InvalidValue;

        const zone_hour = std.fmt.parseInt(u8, timezone[1..3], 10) catch return error.InvalidValue;
        const zone_minute = std.fmt.parseInt(u8, timezone[4..6], 10) catch return error.InvalidValue;

        if (zone_hour > 23 or zone_minute > 59) return error.InvalidValue;

        const zone_total: u16 = @as(u16, zone_hour) * 60 + zone_minute;
        const offset_minutes: i32 = sign * @as(i32, zone_total);

        return .{
            .hour = @intCast(hour),
            .minute = @intCast(minute),
            .second = @intCast(second),
            .microsecond = microsecond,
            .zone_offset = offset_minutes,
        };
    }

    fn fractionToMicrosecond(len: usize, value: u64) ?u20 {
        const micro: u64 = switch (len) {
            1 => value * 100_000,
            2 => value * 10_000,
            3 => value * 1_000,
            6 => value,
            9 => value / 1_000,
            else => return null,
        };
        if (micro > 999_999) return null;
        return @intCast(micro);
    }
};

/// Type-safe wrapper around a URI attribute.
pub const Uri = struct {
    pub const empty: Uri = .{ .text = "" };

    text: []const u8,

    pub fn init(text: []const u8) Uri {
        // TODO: Add correctness validation here
        return .{ .text = text };
    }
};

/// Type-safe wrapper around a reference value (id/ref) attribute.
pub const Reference = struct {
    pub const empty: Reference = .{ .text = "" };

    text: []const u8,

    pub fn init(text: []const u8) Reference {
        // TODO: Add correctness validation here
        return .{ .text = text };
    }
};

/// Parses a HyperDoc document.
pub fn parse(
    allocator: std.mem.Allocator,
    /// The source code to be parsed
    raw_plain_text: []const u8,
    /// An optional diagnostics element that receives diagnostic messages like errors and warnings.
    /// If present, will be filled out by the parser.
    diagnostics: ?*Diagnostics,
) error{ OutOfMemory, SyntaxError, MalformedDocument, InvalidUtf8 }!Document {
    const source_text = try remove_byte_order_mark(diagnostics, raw_plain_text);

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var parser: Parser = .{
        .code = source_text,
        .arena = arena.allocator(),
        .diagnostics = diagnostics,
    };

    var sema: SemanticAnalyzer = .{
        .arena = arena.allocator(),
        .diagnostics = diagnostics,
        .code = source_text,
    };

    while (true) {
        errdefer |err| {
            std.log.debug("error at examples/demo.hdoc:{f}: {t}", .{
                parser.make_diagnostic_location(parser.offset),
                err,
            });
        }

        const node = parser.accept_node(.top_level) catch |err| switch (err) {
            error.OutOfMemory => |e| return @as(error{OutOfMemory}!Document, e), // TODO: What the fuck? Bug report!

            error.EndOfFile => break,

            error.UnexpectedEndOfFile,
            error.InvalidCharacter,
            error.UnexpectedCharacter,
            error.UnterminatedStringLiteral,
            error.UnterminatedList,
            => return error.SyntaxError,
        };

        try sema.append_node(node);
    }

    const header = sema.header orelse return error.MalformedDocument;

    return .{
        .arena = arena,
        .contents = try sema.blocks.toOwnedSlice(arena.allocator()),
        .ids = try sema.ids.toOwnedSlice(arena.allocator()),

        .lang = header.lang,
        .title = header.title,
        .version = header.version,
        .author = header.author,
        .date = header.date,
        .timezone = header.timezone,
    };
}

pub fn remove_byte_order_mark(diagnostics: ?*Diagnostics, plain_text: []const u8) error{ OutOfMemory, InvalidUtf8 }![]const u8 {
    // First check if all of our code is valid UTF-8
    // and if it potentially starts with a BOM.
    var view = std.unicode.Utf8View.init(plain_text) catch {
        return error.InvalidUtf8;
    };

    var iter = view.iterator();

    if (iter.nextCodepointSlice()) |slice| {
        const codepoint = std.unicode.utf8Decode(slice) catch unreachable;
        if (codepoint == 0xFEFF) {
            if (diagnostics) |diag| {
                try diag.add(.document_starts_with_bom, .{ .column = 1, .line = 1 });
            }
            return plain_text[slice.len..];
        }
    }
    return plain_text;
}

pub const SemanticAnalyzer = struct {
    const whitespace_chars = " \t";

    const Header = struct {
        version: Version,
        lang: ?[]const u8,
        title: ?[]const u8,
        author: ?[]const u8,
        timezone: ?[]const u8,
        date: ?DateTime,
    };

    arena: std.mem.Allocator,
    diagnostics: ?*Diagnostics,
    code: []const u8,

    header: ?Header = null,
    blocks: std.ArrayList(Block) = .empty,
    ids: std.ArrayList(?Reference) = .empty,

    fn append_node(sema: *SemanticAnalyzer, node: Parser.Node) error{OutOfMemory}!void {
        switch (node.type) {
            .hdoc => {
                if (sema.header != null) {
                    try sema.emit_diagnostic(.duplicate_hdoc_header, node.location);
                }
                sema.header = sema.translate_header_node(node) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.BadAttributes => null,
                };
            },

            else => {
                if (sema.header == null) {
                    if (sema.blocks.items.len == 0) {
                        // Emit error for the first encountered block.
                        // This can only happen exactly once, as we either:
                        // - have already set a header block when the first non-header nodes arrives.
                        // - we have processed another block already, so the previous block would've emitted the warning already.
                        try sema.emit_diagnostic(.missing_hdoc_header, node.location);
                    }
                }

                const block, const id = sema.translate_block_node(node) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.InvalidNodeType, error.BadAttributes => {
                        return;
                    },
                    error.Unimplemented => {
                        std.log.warn("implementd translation of {} node", .{node.type});
                        return;
                    },
                };

                try sema.blocks.append(sema.arena, block);
                try sema.ids.append(sema.arena, id);
            },
        }
    }

    fn translate_header_node(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, BadAttributes }!Header {
        std.debug.assert(node.type == .hdoc);

        const attrs = try sema.get_attributes(node, struct {
            version: Version,
            title: ?[]const u8 = null,
            author: ?[]const u8 = null,
            date: ?DateTime = null,
            lang: ?[]const u8 = null,
            tz: ?[]const u8 = null,
        });

        return .{
            .version = attrs.version,
            .lang = attrs.lang,
            .title = attrs.title,
            .author = attrs.author,
            .date = attrs.date,
            .timezone = attrs.tz,
        };
    }

    fn translate_block_node(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, InvalidNodeType, BadAttributes, Unimplemented }!struct { Block, ?Reference } {
        std.debug.assert(node.type != .hdoc);

        switch (node.type) {
            .hdoc => unreachable,

            .h1, .h2, .h3 => {
                const heading, const id = try sema.translate_heading_node(node);
                return .{ .{ .heading = heading }, id };
            },
            .p, .note, .warning, .danger, .tip, .quote, .spoiler => {
                const paragraph, const id = try sema.translate_paragraph_node(node);
                return .{ .{ .paragraph = paragraph }, id };
            },
            .ul, .ol => {
                const list, const id = try sema.translate_list_node(node);
                return .{ .{ .list = list }, id };
            },
            .img => {
                const image, const id = try sema.translate_image_node(node);
                return .{ .{ .image = image }, id };
            },
            .pre => {
                const preformatted, const id = try sema.translate_preformatted_node(node);
                return .{ .{ .preformatted = preformatted }, id };
            },
            .toc => {
                const toc, const id = try sema.translate_toc_node(node);
                return .{ .{ .toc = toc }, id };
            },
            .table => {
                const table, const id = try sema.translate_table_node(node);
                return .{ .{ .table = table }, id };
            },

            .unknown_block, .unknown_inline => {
                try sema.emit_diagnostic(.{ .unknown_block_type = .{ .name = sema.code[node.location.offset .. node.location.offset + node.location.length] } }, node.location);
                return error.InvalidNodeType;
            },

            .@"\\em",
            .@"\\mono",
            .@"\\strike",
            .@"\\sub",
            .@"\\sup",
            .@"\\link",
            .@"\\time",
            .@"\\date",
            .@"\\datetime",
            .text,
            .columns,
            .group,
            .row,
            .td,
            .li,
            => {
                try sema.emit_diagnostic(.{ .invalid_block_type = .{ .name = sema.code[node.location.offset .. node.location.offset + node.location.length] } }, node.location);
                return error.InvalidNodeType;
            },
        }

        return error.InvalidNodeType;
    }

    fn translate_heading_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Heading, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: ?[]const u8 = null,
            id: ?Reference = null,
        });

        const heading: Block.Heading = .{
            .level = switch (node.type) {
                .h1 => .h1,
                .h2 => .h2,
                .h3 => .h3,
                else => unreachable,
            },
            .lang = attrs.lang,
            .content = try sema.translate_inline(node),
        };

        return .{ heading, attrs.id };
    }

    fn translate_paragraph_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Paragraph, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: ?[]const u8 = null,
            id: ?Reference = null,
        });

        const heading: Block.Paragraph = .{
            .kind = switch (node.type) {
                .p => .p,
                .note => .note,
                .warning => .warning,
                .danger => .danger,
                .tip => .tip,
                .quote => .quote,
                .spoiler => .spoiler,
                else => unreachable,
            },
            .lang = attrs.lang,
            .content = try sema.translate_inline(node),
        };

        return .{ heading, attrs.id };
    }

    fn translate_list_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.List, ?Reference } {
        _ = sema;
        _ = node;
        return error.Unimplemented; // TODO: Implement this node type
    }

    fn translate_image_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Image, ?Reference } {
        _ = sema;
        _ = node;
        return error.Unimplemented; // TODO: Implement this node type
    }

    fn translate_preformatted_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Preformatted, ?Reference } {
        _ = sema;
        _ = node;
        return error.Unimplemented; // TODO: Implement this node type
    }

    fn translate_toc_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.TableOfContents, ?Reference } {
        _ = sema;
        _ = node;
        return error.Unimplemented; // TODO: Implement this node type
    }

    fn translate_table_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Table, ?Reference } {
        _ = sema;
        _ = node;
        return error.Unimplemented; // TODO: Implement this node type
    }

    fn translate_inline(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, BadAttributes }![]Span {
        var spans: std.ArrayList(Span) = .empty;
        errdefer spans.deinit(sema.arena);

        // TODO: Implement automatic space insertion.
        //       This must be done when two consecutive nodes are separated by a space

        try sema.translate_inline_body(&spans, node.body, .{});

        // TODO: Compact spans by joining spans with equal properties

        return try spans.toOwnedSlice(sema.arena);
    }

    pub const AttribOverrides = struct {
        lang: ?[]const u8 = null,
        em: ?bool = null,
        mono: ?bool = null,
        strike: ?bool = null,
        position: ?ScriptPosition = null,
        link: ?Link = null,
        syntax: []const u8 = "",
    };

    fn derive_attribute(sema: *SemanticAnalyzer, location: Parser.Location, old: Span.Attributes, overlay: AttribOverrides) !Span.Attributes {
        comptime std.debug.assert(@typeInfo(Span.Attributes).@"struct".fields.len == @typeInfo(AttribOverrides).@"struct".fields.len);

        var new = old;
        if (overlay.lang) |lang| {
            new.lang = lang;
        }

        if (overlay.em) |v| {
            if (old.em) {
                try sema.emit_diagnostic(.{ .redundant_inline = .{ .attribute = .em } }, location);
            }
            new.em = v;
        }

        if (overlay.mono) |mono| {
            if (old.mono) {
                if (std.mem.eql(u8, old.syntax, new.syntax)) {
                    try sema.emit_diagnostic(.{ .redundant_inline = .{ .attribute = .mono } }, location);
                }
            }
            new.mono = mono;
            new.syntax = overlay.syntax;
        } else {
            // can't override syntax without also enabling mono!
            std.debug.assert(overlay.syntax.len == 0);
        }

        if (overlay.strike) |strike| {
            if (old.strike) {
                try sema.emit_diagnostic(.{ .redundant_inline = .{ .attribute = .strike } }, location);
            }
            new.strike = strike;
        }

        if (overlay.position) |new_pos| {
            std.debug.assert(new_pos != .baseline); // we can never return to baseline script.
            if (old.position == new_pos) {
                try sema.emit_diagnostic(.{ .redundant_inline = .{ .attribute = .sub } }, location);
            } else if (old.position != .baseline) {
                try sema.emit_diagnostic(.{ .invalid_inline_combination = .{
                    .first = switch (old.position) {
                        .superscript => .sup,
                        .subscript => .sub,
                        .baseline => unreachable,
                    },
                    .second = switch (new_pos) {
                        .superscript => .sup,
                        .subscript => .sub,
                        .baseline => unreachable,
                    },
                } }, location);
            }
            new.position = new_pos;
        }

        if (overlay.link) |link| {
            if (old.link != .none) {
                try sema.emit_diagnostic(.link_not_nestable, location);
            }
            new.link = link;
        }

        return new;
    }

    fn translate_inline_node(sema: *SemanticAnalyzer, spans: *std.ArrayList(Span), node: Parser.Node, attribs: Span.Attributes) !void {
        switch (node.type) {
            .unknown_inline,
            .text,
            => try sema.translate_inline_body(spans, node.body, attribs),

            .@"\\em" => {
                const props = try sema.get_attributes(node, struct {
                    lang: ?[]const u8 = null,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .em = true,
                }));
            },

            .@"\\strike" => {
                const props = try sema.get_attributes(node, struct {
                    lang: ?[]const u8 = null,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .strike = true,
                }));
            },

            .@"\\sub" => {
                const props = try sema.get_attributes(node, struct {
                    lang: ?[]const u8 = null,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .position = .superscript,
                }));
            },

            .@"\\sup" => {
                const props = try sema.get_attributes(node, struct {
                    lang: ?[]const u8 = null,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .position = .subscript,
                }));
            },

            .@"\\link" => {
                const props = try sema.get_attributes(node, struct {
                    lang: ?[]const u8 = null,
                    uri: ?Uri = null,
                    ref: ?Reference = null,
                });

                if (props.uri != null and props.ref != null) {
                    try sema.emit_diagnostic(.invalid_link, node.location);
                }

                const link: Link = if (props.uri) |uri| blk: {
                    break :blk .{ .uri = uri };
                } else if (props.ref) |ref| blk: {
                    break :blk .{ .ref = ref };
                } else blk: {
                    try sema.emit_diagnostic(.invalid_link, node.location);
                    break :blk .none;
                };

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .link = link,
                }));
            },

            .@"\\mono" => {
                const props = try sema.get_attributes(node, struct {
                    lang: ?[]const u8 = null,
                    syntax: []const u8 = "",
                });
                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .mono = true,
                    .lang = props.lang,
                    .syntax = props.syntax,
                }));
            },

            .@"\\date",
            .@"\\time",
            .@"\\datetime",
            => {
                const props = try sema.get_attributes(node, struct {
                    lang: ?[]const u8 = null,
                    fmt: []const u8 = "",
                });

                var content_spans: std.ArrayList(Span) = .empty;
                defer content_spans.deinit(sema.arena);

                // TODO: Implement automatic space insertion.
                //       This must be done when two consecutive nodes are separated by a space

                try sema.translate_inline_body(&content_spans, node.body, .{});

                //  Convert the content_spans into a "rendered string".
                const content_text = try sema.join_spans(content_spans.items, .no_space);

                const content: Span.Content = switch (node.type) {
                    .@"\\date" => try sema.parse_date_body(node, .date, Date, content_text, props.fmt),
                    .@"\\time" => try sema.parse_date_body(node, .time, Time, content_text, props.fmt),
                    .@"\\datetime" => try sema.parse_date_body(node, .datetime, DateTime, content_text, props.fmt),
                    else => unreachable,
                };

                try spans.append(sema.arena, .{
                    .content = content,
                    .attribs = try sema.derive_attribute(node.location, attribs, .{
                        .lang = attribs.lang,
                    }),
                });
            },

            .hdoc,
            .h1,
            .h2,
            .h3,
            .p,
            .note,
            .warning,
            .danger,
            .tip,
            .quote,
            .spoiler,
            .ul,
            .ol,
            .img,
            .pre,
            .toc,
            .table,
            .columns,
            .group,
            .row,
            .td,
            .li,
            .unknown_block,
            => @panic("PARSER ERROR: The parser emitted a block node inside an inline context"),
        }
    }

    fn parse_date_body(
        sema: *SemanticAnalyzer,
        node: Parser.Node,
        comptime body: enum { date, time, datetime },
        comptime DTValue: type,
        value_str: []const u8,
        format_str: []const u8,
    ) !Span.Content {
        const Format: type = DTValue.Format;

        const timezone_hint: ?[]const u8 = if (sema.header) |header| header.timezone else null;

        const value_or_err: error{ InvalidValue, MissingTimezone }!DTValue = switch (DTValue) {
            Date => Date.parse(value_str),
            Time => Time.parse(value_str, timezone_hint),
            DateTime => DateTime.parse(value_str, timezone_hint),
            else => unreachable,
        };

        const value: DTValue = if (value_or_err) |value|
            value
        else |err| blk: {
            switch (err) {
                error.InvalidValue => {
                    try sema.emit_diagnostic(.invalid_date_time, node.location);
                },
                error.MissingTimezone => {
                    // TODO: Use (timezone_hint != null) to emit diagnostic for hint with
                    //       adding `tz` attribute when all date/time values share a common base.
                    try sema.emit_diagnostic(.invalid_date_time, node.location);
                },
            }
            break :blk std.mem.zeroes(DTValue);
        };

        const format: Format = if (format_str.len == 0)
            .default
        else if (std.meta.stringToEnum(Format, format_str)) |format|
            format
        else blk: {
            // TODO: Report error about invalid format
            try sema.emit_diagnostic(.invalid_date_time_fmt, get_attribute_location(node, "fmt", .value) orelse node.location);
            break :blk .default;
        };

        return @unionInit(Span.Content, @tagName(body), .{
            .format = format,
            .value = value,
        });
    }

    const JoinStyle = enum { no_space, one_space };
    fn join_spans(sema: *SemanticAnalyzer, source_spans: []const Span, style: JoinStyle) ![]const u8 {
        var len: usize = switch (style) {
            .no_space => 0,
            .one_space => (source_spans.len -| 1),
        };
        for (source_spans) |span| {
            len += switch (span.content) {
                .text => |str| str.len,
                .date, .time, .datetime => @panic("TODO: Implement date-to-text conversion!"),
            };
        }

        var output_str: std.ArrayList(u8) = .empty;
        defer output_str.deinit(sema.arena);

        try output_str.ensureTotalCapacityPrecise(sema.arena, len);

        for (source_spans, 0..) |span, index| {
            switch (style) {
                .no_space => {},
                .one_space => if (index > 0)
                    output_str.appendAssumeCapacity(' '),
            }

            switch (span.content) {
                .text => |str| output_str.appendSliceAssumeCapacity(str),
                .date, .time, .datetime => @panic("TODO: Implement date-to-text conversion!"),
            }
        }

        return try output_str.toOwnedSlice(sema.arena);
    }

    fn translate_inline_body(sema: *SemanticAnalyzer, spans: *std.ArrayList(Span), body: Parser.Node.Body, attribs: Span.Attributes) error{ OutOfMemory, BadAttributes }!void {
        switch (body) {
            .empty => |location| {
                try sema.emit_diagnostic(.empty_inline_body, location);
            },

            .string => |string_body| {
                const text = try sema.unescape_string(string_body);

                try spans.append(sema.arena, .{
                    .content = .{ .text = text },
                    .attribs = attribs,
                });
            },

            .verbatim => |verbatim_lines| {
                var text_buffer: std.ArrayList(u8) = .empty;
                defer text_buffer.deinit(sema.arena);

                var size: usize = verbatim_lines.len -| 1;
                for (verbatim_lines) |line| {
                    size += line.text.len;
                }
                try text_buffer.ensureTotalCapacityPrecise(sema.arena, size);

                for (verbatim_lines, 0..) |line, index| {
                    if (index != 0) {
                        try text_buffer.append(sema.arena, '\n');
                    }
                    std.debug.assert(std.mem.startsWith(u8, line.text, "|"));

                    const is_padded = std.mem.startsWith(u8, line.text, "| ");
                    const text = if (is_padded)
                        line.text[2..]
                    else
                        line.text[1..];

                    const stripped = std.mem.trimRight(u8, text, whitespace_chars);

                    text_buffer.appendSliceAssumeCapacity(stripped);
                }

                try spans.append(sema.arena, .{
                    .content = .{ .text = try text_buffer.toOwnedSlice(sema.arena) },
                    .attribs = attribs,
                });
            },

            .list => |list| {
                for (list) |child_node| {
                    try sema.translate_inline_node(spans, child_node, attribs);
                }
            },

            .text_span => |text_span| {
                try spans.append(sema.arena, .{
                    .content = .{ .text = text_span.text },
                    .attribs = attribs,
                });
            },
        }
    }

    fn get_attribute_location(node: Parser.Node, attrib_name: []const u8, comptime key: enum { name, value }) ?Parser.Location {
        var i = node.attributes.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, node.attributes.items[i].name.text, attrib_name))
                return @field(node.attributes.items[i], @tagName(key)).location;
        }
        return null;
    }

    fn get_attributes(sema: *SemanticAnalyzer, node: Parser.Node, comptime Attrs: type) error{ OutOfMemory, BadAttributes }!Attrs {
        const Fields = std.meta.FieldEnum(Attrs);
        const fields = @typeInfo(Attrs).@"struct".fields;

        var required: std.EnumSet(Fields) = .initEmpty();

        var attrs: Attrs = undefined;
        inline for (fields) |fld| {
            if (fld.default_value_ptr) |default_value_ptr| {
                @field(attrs, fld.name) = @as(*const fld.type, @ptrCast(@alignCast(default_value_ptr))).*;
            } else {
                @field(attrs, fld.name) = undefined;
                required.insert(@field(Fields, fld.name));
            }
        }

        var any_invalid = false;
        var found: std.EnumSet(Fields) = .initEmpty();
        for (node.attributes.items) |attrib| {
            const key = attrib.name.text;

            const fld = std.meta.stringToEnum(Fields, key) orelse {
                try sema.emit_diagnostic(.{ .unknown_attribute = .{ .type = node.type, .name = key } }, attrib.name.location);
                continue;
            };
            if (found.contains(fld)) {
                try sema.emit_diagnostic(.{ .duplicate_attribute = .{ .name = key } }, attrib.name.location);
            }
            found.insert(fld);

            switch (fld) {
                inline else => |tag| @field(attrs, @tagName(tag)) = sema.cast_value(attrib.value, @FieldType(Attrs, @tagName(tag))) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,

                    else => {
                        any_invalid = true;

                        try sema.emit_diagnostic(.{ .invalid_attribute = .{ .type = node.type, .name = key } }, attrib.value.location);

                        continue;
                    },
                },
            }
        }

        // Check if we have any required attributes missing:
        var any_missing = false;
        {
            var iter = required.iterator();
            while (iter.next()) |req_field| {
                if (!found.contains(req_field)) {
                    try sema.emit_diagnostic(.{ .missing_attribute = .{ .type = node.type, .name = @tagName(req_field) } }, node.location);
                    any_missing = true;
                }
            }
        }
        if (any_missing or any_invalid)
            return error.BadAttributes;

        return attrs;
    }

    fn cast_value(sema: *SemanticAnalyzer, attrib: Parser.Token, comptime T: type) error{ OutOfMemory, InvalidValue }!T {
        if (@typeInfo(T) == .optional) {
            return try sema.cast_value(attrib, @typeInfo(T).optional.child);
        }

        const value = try sema.unescape_string(attrib);

        const timezone_hint = if (sema.header) |header|
            header.timezone
        else
            null;

        return switch (T) {
            []const u8 => value,

            Reference => {
                const stripped = std.mem.trim(u8, value, whitespace_chars);
                if (stripped.len != value.len) {
                    try sema.emit_diagnostic(.attribute_leading_trailing_whitespace, attrib.location);
                }
                return .init(stripped);
            },

            Uri => {
                const stripped = std.mem.trim(u8, value, whitespace_chars);
                if (stripped.len != value.len) {
                    try sema.emit_diagnostic(.attribute_leading_trailing_whitespace, attrib.location);
                }
                return .init(stripped);
            },

            Version => Version.parse(value) catch return error.InvalidValue,
            Date => Date.parse(value) catch return error.InvalidValue,
            Time => Time.parse(value, timezone_hint) catch return error.InvalidValue,
            DateTime => DateTime.parse(value, timezone_hint) catch return error.InvalidValue,

            else => @compileError("Unsupported attribute type: " ++ @typeName(T)),
        };
    }

    fn emit_diagnostic(sema: *SemanticAnalyzer, code: Diagnostic.Code, location: Parser.Location) !void {
        if (sema.diagnostics) |diag| {
            try diag.add(code, sema.make_location(location.offset));
        }
    }

    fn make_location(sema: *SemanticAnalyzer, offset: usize) Diagnostic.Location {
        var line: u32 = 1;
        var column: u32 = 1;

        var i: usize = 0;
        while (i < offset and i < sema.code.len) : (i += 1) {
            if (sema.code[i] == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }

        return .{ .line = line, .column = column };
    }

    /// Accepts a string literal, including the surrounding quotes.
    pub fn unescape_string(sema: *SemanticAnalyzer, token: Parser.Token) error{OutOfMemory}![]const u8 {
        std.debug.assert(token.text.len >= 2);
        std.debug.assert(token.text[0] == '"' and token.text[token.text.len - 1] == '"');

        const base_offset = token.location.offset + 1; // skip leading quote
        const content = token.text[1 .. token.text.len - 1];

        const Source = struct {
            char: u8,
            location: Parser.Location,
        };

        var output_buffer: std.MultiArrayList(Source) = .empty;
        defer output_buffer.deinit(sema.arena);

        try output_buffer.ensureTotalCapacity(sema.arena, content.len);

        {
            var out_chars_buffer: [4]u8 = undefined;

            var i: usize = 0;
            while (i < content.len) {
                const start = i;

                // We process bytes, even thought the input is UTF-8.
                // This is fine as we only process ASCII-range escape sequences
                const in_char = content[i];

                // We process our in_char into 1..4 bytes, depending
                // on the escape sequence. Worst input is \u{10FFFF}, which is
                // encoded as {F4 8F BF BF}, so 4 bytes.
                const out_chars: []const u8 = blk: {
                    i += 1;
                    if (in_char != '\\') {
                        // Just return the actual character
                        break :blk content[start..i];
                    }

                    // This would mean an uinterminated escape sequence, and
                    // must be processed by the parser already:
                    std.debug.assert(i < content.len);

                    const esc_char = content[i];

                    switch (esc_char) {
                        '"' => {
                            i += 1;
                            break :blk "\"";
                        },
                        '\\' => {
                            i += 1;
                            break :blk "\\";
                        },
                        'n' => {
                            i += 1;
                            break :blk "\n";
                        },
                        'r' => {
                            i += 1;
                            break :blk "\r";
                        },

                        'u' => {
                            while (content[i] != '}') {
                                i += 1;
                                if (i >= content.len) {
                                    try sema.emit_diagnostic(.invalid_unicode_string_escape, .{ .offset = start, .length = i - start });
                                    break :blk content[start..i];
                                }
                            }
                            i += 1;
                            const escape_part = content[start..i];
                            std.debug.assert(escape_part.len >= 3);
                            std.debug.assert(escape_part[0] == '\\');
                            std.debug.assert(escape_part[1] == 'u');
                            std.debug.assert(escape_part[escape_part.len - 1] == '}');

                            const location: Parser.Location = .{ .offset = start, .length = escape_part.len };

                            if (escape_part[2] != '{') {
                                try sema.emit_diagnostic(.invalid_unicode_string_escape, location);
                                break :blk "???";
                            }

                            if (escape_part.len == 4) {
                                // Empty escape: \u{}
                                std.debug.assert(std.mem.eql(u8, escape_part, "\\u{}"));
                                try sema.emit_diagnostic(.invalid_unicode_string_escape, location);
                                break :blk "???";
                            }

                            const codepoint = std.fmt.parseInt(u21, escape_part[3 .. escape_part.len - 1], 16) catch {
                                try sema.emit_diagnostic(.invalid_unicode_string_escape, location);
                                break :blk "???";
                            };

                            const out_len = std.unicode.utf8Encode(codepoint, &out_chars_buffer) catch |err| switch (err) {
                                error.Utf8CannotEncodeSurrogateHalf => {
                                    try sema.emit_diagnostic(.{ .illegal_character = .{ .codepoint = codepoint } }, location);
                                    break :blk "???";
                                },
                                error.CodepointTooLarge => {
                                    try sema.emit_diagnostic(.invalid_unicode_string_escape, location);
                                    break :blk "???";
                                },
                            };
                            break :blk out_chars_buffer[0..out_len];
                        },

                        else => {
                            // Unknown escape sequence, emit escaped char verbatim:
                            // TODO: How to handle something like "\😭", which is
                            //       definitly valid and in-scope.

                            const len = std.unicode.utf8ByteSequenceLength(esc_char) catch unreachable;

                            const esc_codepoint = std.unicode.utf8Decode(content[i .. i + len]) catch unreachable;

                            i += len;

                            try sema.emit_diagnostic(.{
                                .invalid_string_escape = .{ .codepoint = esc_codepoint },
                            }, .{ .offset = start, .length = i - start + 1 });

                            break :blk content[start..i];
                        },
                    }
                    @compileError("The switch above must be exhaustive and break to :blk for each code path.");
                };

                const loc: Parser.Location = .{
                    .offset = base_offset + start,
                    .length = i - start + 1,
                };
                for (out_chars) |out_char| {
                    output_buffer.appendAssumeCapacity(.{
                        .char = out_char,
                        .location = loc,
                    });
                }
            }
        }

        var output = output_buffer.toOwnedSlice();
        errdefer output.deinit(sema.arena);

        const view = std.unicode.Utf8View.init(output.items(.char)) catch {
            std.log.err("invalid utf-8 input: \"{f}\"", .{std.zig.fmtString(output.items(.char))});
            @panic("String unescape produced invalid UTF-8 sequence. This should not be possible.");
        };

        var iter = view.iterator();
        while (iter.nextCodepointSlice()) |slice| {
            const start = iter.i - slice.len;
            const codepoint = std.unicode.utf8Decode(slice) catch unreachable;

            if (is_illegal_character(codepoint)) {
                try sema.emit_diagnostic(
                    .{ .illegal_character = .{ .codepoint = codepoint } },
                    output.get(start).location,
                );
            }
        }

        return view.bytes;
    }

    // TODO: Also validate the whole document against this rules.
    fn is_illegal_character(codepoint: u21) bool {
        // Surrogate codepoints are illegal, we're only ever using UTF-8 which doesn't need them.
        if (std.unicode.isSurrogateCodepoint(codepoint))
            return true;

        // CR and LF are the only allowed control characters:
        if (codepoint == std.ascii.control_code.cr)
            return false;
        if (codepoint == std.ascii.control_code.lf)
            return false;

        // Disallow characters from the "Control" category:
        // <https://www.compart.com/en/unicode/category/Cc>
        if (codepoint <= 0x1F) // C0 control characters
            return true;
        if (codepoint == 0x7F) // DEL
            return true;
        if (codepoint >= 0x80 and codepoint <= 0x9F) // C1 control characters
            return true;

        // All other characters are fine
        return false;
    }
};

pub const Parser = struct {
    code: []const u8,
    offset: usize = 0,

    arena: std.mem.Allocator,
    diagnostics: ?*Diagnostics,

    pub const ScopeType = enum { top_level, nested };

    fn emitDiagnostic(
        parser: *Parser,
        code: Diagnostic.Code,
        diag_location: Diagnostic.Location,
    ) void {
        if (parser.diagnostics) |diag| {
            diag.add(code, diag_location) catch {};
        }
    }

    pub fn accept_node(parser: *Parser, comptime scope_type: ScopeType) !Node {
        parser.skip_whitespace();
        if (scope_type == .top_level and parser.at_end()) {
            return error.EndOfFile;
        }

        const type_ident = parser.accept_identifier() catch |err| switch (err) {
            error.UnexpectedEndOfFile => |e| switch (scope_type) {
                .nested => return e,
                .top_level => return error.EndOfFile,
            },
            else => |e| return e,
        };
        const node_type: NodeType = if (std.meta.stringToEnum(NodeType, type_ident.text)) |node_type|
            node_type
        else if (std.mem.startsWith(u8, type_ident.text, "\\"))
            .unknown_inline
        else
            .unknown_block;

        var attributes: std.ArrayList(Attribute) = .empty;
        errdefer attributes.deinit(parser.arena);

        if (parser.try_accept_char('(')) {
            if (!parser.try_accept_char(')')) {
                // We 're not at the end of the attribute list,
                // so we know that the next token must be the attribute name.

                while (true) {
                    const attr_name = try parser.accept_identifier();
                    _ = try parser.accept_char('=');
                    const attr_value = try parser.accept_string();

                    try attributes.append(parser.arena, .{
                        .name = attr_name,
                        .value = attr_value,
                    });

                    if (!parser.try_accept_char(',')) {
                        break;
                    }
                }
                try parser.accept_char(')');
            }
        }

        if (parser.try_accept_char(';')) {
            // block has empty content
            return .{
                .location = parser.location(type_ident.location.offset, null),
                .type = node_type,
                .attributes = attributes,
                .body = .{ .empty = parser.location(parser.offset - 1, null) },
            };
        }

        if (parser.try_accept_char(':')) {
            // block has verbatim content

            var lines: std.ArrayList(Token) = .empty;

            while (try parser.try_accept_verbatim_line()) |line| {
                try lines.append(parser.arena, line);
            }

            if (lines.items.len == 0) {
                emitDiagnostic(parser, .empty_verbatim_block, parser.make_diagnostic_location(type_ident.location.offset));
            }

            return .{
                .location = parser.location(type_ident.location.offset, null),
                .type = node_type,
                .attributes = attributes,
                .body = .{ .verbatim = try lines.toOwnedSlice(parser.arena) },
            };
        }

        if (try parser.try_accept_string()) |string_body| {
            // block has string content

            return .{
                .location = parser.location(type_ident.location.offset, null),
                .type = node_type,
                .attributes = attributes,
                .body = .{ .string = string_body },
            };
        }

        var children = if (node_type.has_inline_body())
            try parser.accept_inline_node_list()
        else
            try parser.accept_block_node_list();

        return .{
            .location = parser.location(type_ident.location.offset, null),
            .type = node_type,
            .attributes = attributes,
            .body = .{ .list = try children.toOwnedSlice(parser.arena) },
        };
    }

    pub fn accept_block_node_list(parser: *Parser) error{
        OutOfMemory,
        InvalidCharacter,
        UnterminatedStringLiteral,
        UnexpectedEndOfFile,
        UnterminatedList,
        UnexpectedCharacter,
    }!std.ArrayList(Node) {
        var children: std.ArrayList(Node) = .empty;
        errdefer children.deinit(parser.arena);

        try parser.accept_char('{');

        while (true) {
            parser.skip_whitespace();

            if (parser.at_end()) {
                emitDiagnostic(parser, .unterminated_block_list, parser.make_diagnostic_location(parser.offset));
                return error.UnterminatedList;
            }

            if (parser.try_accept_char('}'))
                break;

            const child = try parser.accept_node(.nested);
            try children.append(parser.arena, child);
        }

        return children;
    }

    pub fn accept_inline_node_list(parser: *Parser) error{
        OutOfMemory,
        InvalidCharacter,
        UnterminatedStringLiteral,
        UnexpectedEndOfFile,
        UnterminatedList,
        UnexpectedCharacter,
    }!std.ArrayList(Node) {
        var children: std.ArrayList(Node) = .empty;
        errdefer children.deinit(parser.arena);

        try parser.accept_char('{');

        var nesting: usize = 0;

        while (true) {
            parser.skip_whitespace();

            const head = parser.peek_char() orelse {
                emitDiagnostic(parser, .unterminated_inline_list, parser.make_diagnostic_location(parser.offset));
                return error.UnterminatedList;
            };

            switch (head) {
                '{' => {
                    nesting += 1;
                    parser.offset += 1;

                    const token = parser.slice(parser.offset - 1, parser.offset);
                    try children.append(parser.arena, .{
                        .location = token.location,
                        .type = .text,
                        .body = .{
                            .text_span = token,
                        },
                    });
                },

                '}' => {
                    parser.offset += 1;

                    if (nesting == 0)
                        break;

                    nesting -= 1;

                    const token = parser.slice(parser.offset - 1, parser.offset);
                    try children.append(parser.arena, .{
                        .location = token.location,
                        .type = .text,
                        .body = .{
                            .text_span = token,
                        },
                    });
                },

                '\\' => backslash: {
                    if (parser.offset < parser.code.len - 1) {
                        const next_char = parser.code[parser.offset + 1];
                        switch (next_char) {
                            '{', '}', '\\' => {
                                // Escaped brace

                                const token = parser.slice(parser.offset, parser.offset + 2);
                                try children.append(parser.arena, .{
                                    .location = token.location,
                                    .type = .text,
                                    .body = .{
                                        .text_span = token,
                                    },
                                });

                                parser.offset += 2;

                                break :backslash;
                            },
                            else => {},
                        }
                    }

                    const child = try parser.accept_node(.nested);

                    // This will only be a non-inline node if we have a bug.
                    std.debug.assert(child.type.is_inline());

                    try children.append(parser.arena, child);
                },

                else => {
                    const word = try parser.accept_word();
                    try children.append(parser.arena, .{
                        .location = word.location,
                        .type = .text,
                        .body = .{ .text_span = word },
                    });
                },
            }
        }

        return children;
    }

    pub fn try_accept_verbatim_line(parser: *Parser) !?Token {
        parser.skip_whitespace();

        const head = parser.offset;
        if (!parser.try_accept_char('|')) {
            return null;
        }

        const after_pipe = if (!parser.at_end()) parser.code[parser.offset] else null;
        if (after_pipe) |c| {
            if (c != ' ' and c != '\n') {
                emitDiagnostic(parser, .verbatim_missing_space, parser.make_diagnostic_location(head));
            }
        }

        while (!parser.at_end()) {
            const c = parser.code[parser.offset];
            if (c == '\n') {
                break;
            }

            // we don't consume the LF character, as each verbatim line should be prefixed with exactly a single LF character
            parser.offset += 1;
        }
        if (parser.at_end()) {
            emitDiagnostic(parser, .verbatim_missing_trailing_newline, parser.make_diagnostic_location(parser.offset));
        }

        const token = parser.slice(head, parser.offset);
        std.debug.assert(std.mem.startsWith(u8, token.text, "|"));
        if (token.text.len > 0) {
            const last = token.text[token.text.len - 1];
            if (last == ' ' or last == '\t') {
                emitDiagnostic(parser, .trailing_whitespace, parser.make_diagnostic_location(parser.offset - 1));
            }
        }
        return token;
    }

    pub fn peek_char(parser: *Parser) ?u8 {
        if (parser.at_end())
            return null;
        return parser.code[parser.offset];
    }

    pub fn accept_char(parser: *Parser, expected: u8) error{ UnexpectedEndOfFile, UnexpectedCharacter }!void {
        if (parser.try_accept_char(expected))
            return;

        if (parser.at_end()) {
            emitDiagnostic(parser, .{ .unexpected_eof = .{ .context = "character", .expected_char = expected } }, parser.make_diagnostic_location(parser.offset));
            return error.UnexpectedEndOfFile;
        }

        emitDiagnostic(parser, .{ .unexpected_character = .{ .expected = expected, .found = parser.code[parser.offset] } }, parser.make_diagnostic_location(parser.offset));
        return error.UnexpectedCharacter;
    }

    pub fn try_accept_char(parser: *Parser, expected: u8) bool {
        std.debug.assert(!is_space(expected));
        parser.skip_whitespace();

        if (parser.at_end())
            return false;

        if (parser.code[parser.offset] != expected)
            return false;

        parser.offset += 1;
        return true;
    }

    pub fn try_accept_string(parser: *Parser) !?Token {
        parser.skip_whitespace();

        if (parser.at_end()) {
            emitDiagnostic(parser, .{ .unexpected_eof = .{ .context = "string literal" } }, parser.make_diagnostic_location(parser.offset));
            return null;
        }

        if (parser.code[parser.offset] != '"')
            return null;

        return try parser.accept_string();
    }

    pub fn accept_string(parser: *Parser) error{ OutOfMemory, UnexpectedEndOfFile, UnexpectedCharacter, UnterminatedStringLiteral }!Token {
        parser.skip_whitespace();

        if (parser.at_end()) {
            emitDiagnostic(parser, .{ .unexpected_eof = .{ .context = "string literal" } }, parser.make_diagnostic_location(parser.offset));
            return error.UnexpectedEndOfFile;
        }

        const start = parser.offset;
        if (parser.code[start] != '"') {
            emitDiagnostic(parser, .{ .unexpected_character = .{ .expected = '"', .found = parser.code[start] } }, parser.make_diagnostic_location(parser.offset));
            return error.UnexpectedCharacter;
        }

        parser.offset += 1;

        while (parser.offset < parser.code.len) {
            const c = parser.code[parser.offset];
            parser.offset += 1;

            switch (c) {
                '"' => return parser.slice(start, parser.offset),

                '\\' => {
                    // Escape sequence
                    if (parser.at_end())
                        return error.UnterminatedStringLiteral;

                    const escaped = parser.code[parser.offset];
                    parser.offset += 1;

                    switch (escaped) {
                        '\n', '\r' => return error.UnterminatedStringLiteral,
                        else => {},
                    }
                },

                else => {},
            }
        }

        emitDiagnostic(parser, .unterminated_string, parser.make_diagnostic_location(start));
        return error.UnterminatedStringLiteral;
    }

    pub fn accept_identifier(parser: *Parser) error{ UnexpectedEndOfFile, InvalidCharacter }!Token {
        parser.skip_whitespace();

        if (parser.at_end()) {
            emitDiagnostic(parser, .{ .unexpected_eof = .{ .context = "identifier" } }, parser.make_diagnostic_location(parser.offset));
            return error.UnexpectedEndOfFile;
        }

        const start = parser.offset;
        const first = parser.code[start];
        if (!is_ident_char(first)) {
            emitDiagnostic(parser, .{ .invalid_identifier_start = .{ .char = first } }, parser.make_diagnostic_location(start));
            return error.InvalidCharacter;
        }

        while (parser.offset < parser.code.len) {
            const c = parser.code[parser.offset];
            if (!is_ident_char(c))
                break;
            parser.offset += 1;
        }

        return parser.slice(start, parser.offset);
    }

    /// Accepts a word token (a sequence of non-whitespace characters).
    pub fn accept_word(parser: *Parser) error{UnexpectedEndOfFile}!Token {
        parser.skip_whitespace();

        if (parser.at_end()) {
            emitDiagnostic(parser, .{ .unexpected_eof = .{ .context = "word" } }, parser.make_diagnostic_location(parser.offset));
            return error.UnexpectedEndOfFile;
        }

        const start = parser.offset;

        while (parser.offset < parser.code.len) {
            const c = parser.code[parser.offset];
            if (is_space(c))
                break;
            switch (c) {
                // These are word-terminating characters:
                '{', '}', '\\' => break,
                else => {},
            }
            parser.offset += 1;
        }

        return parser.slice(start, parser.offset);
    }

    /// Skips forward until the first non-whitespace character.
    pub fn skip_whitespace(parser: *Parser) void {
        while (!parser.at_end()) {
            const c = parser.code[parser.offset];
            if (!is_space(c)) {
                break;
            }
            parser.offset += 1;
        }
    }

    pub fn at_end(parser: *Parser) bool {
        return parser.offset >= parser.code.len;
    }

    pub fn location(parser: *Parser, start: usize, end: ?usize) Location {
        return .{ .offset = start, .length = (end orelse parser.offset) - start };
    }

    pub fn slice(parser: *Parser, start: usize, end: usize) Token {
        return .{
            .text = parser.code[start..end],
            .location = .{ .offset = start, .length = end - start },
        };
    }

    pub fn make_diagnostic_location(parser: Parser, offset: usize) Diagnostic.Location {
        var line: u32 = 1;
        var column: u32 = 1;

        var i: usize = 0;
        while (i < offset and i < parser.code.len) : (i += 1) {
            if (parser.code[i] == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }

        return .{ .line = line, .column = column };
    }

    pub fn is_space(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }

    pub fn is_ident_char(c: u8) bool {
        return switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '\\' => true,
            else => false,
        };
    }

    pub const Token = struct {
        text: []const u8,
        location: Location,
    };

    pub const Location = struct {
        offset: usize,
        length: usize,
    };

    pub const NodeType = enum {
        hdoc,
        h1,
        h2,
        h3,
        p,
        note,
        warning,
        danger,
        tip,
        quote,
        spoiler,
        ul,
        ol,
        img,
        pre,
        toc,
        table,
        columns,
        group,
        row,
        td,
        li,

        text,
        @"\\em",
        @"\\mono",
        @"\\strike",
        @"\\sub",
        @"\\sup",
        @"\\link",
        @"\\date",
        @"\\time",
        @"\\datetime",

        unknown_block,
        unknown_inline,

        pub fn is_inline(node_type: NodeType) bool {
            return switch (node_type) {
                .@"\\em",
                .@"\\mono",
                .@"\\strike",
                .@"\\sub",
                .@"\\sup",
                .@"\\link",
                .@"\\date",
                .@"\\time",
                .@"\\datetime",
                .unknown_inline,
                .text,
                => true,

                .hdoc,
                .h1,
                .h2,
                .h3,
                .p,
                .note,
                .warning,
                .danger,
                .tip,
                .quote,
                .spoiler,
                .ul,
                .ol,
                .img,
                .pre,
                .toc,
                .table,
                .columns,
                .group,
                .row,
                .td,
                .li,
                .unknown_block,
                => false,
            };
        }

        pub fn has_inline_body(node_type: NodeType) bool {
            return switch (node_type) {
                .h1,
                .h2,
                .h3,

                .p,
                .note,
                .warning,
                .danger,
                .tip,
                .quote,
                .spoiler,

                .img,
                .pre,
                .toc,
                .group,

                .@"\\em",
                .@"\\mono",
                .@"\\strike",
                .@"\\sub",
                .@"\\sup",
                .@"\\link",
                .@"\\date",
                .@"\\time",
                .@"\\datetime",

                .unknown_inline,
                .unknown_block, // Unknown blocks must also have inline bodies to optimally retain body contents
                => true,

                .hdoc,
                .ul,
                .ol,
                .table,
                .columns,
                .row,
                .td,
                .li,

                .text,
                => false,
            };
        }
    };

    pub const Node = struct {
        location: Location,
        type: NodeType,
        attributes: std.ArrayList(Attribute) = .empty,

        body: Body,

        pub const Body = union(enum) {
            empty: Location,
            string: Token,
            verbatim: []Token,
            list: []Node,
            text_span: Token,
        };
    };

    pub const Attribute = struct {
        name: Token,
        value: Token,
    };
};

/// A diagnostic message.
pub const Diagnostic = struct {
    pub const Severity = enum { warning, @"error" };

    pub const Location = struct {
        line: u32,
        column: u32,

        pub fn format(loc: Location, w: *std.Io.Writer) !void {
            try w.print("{d}:{d}", .{ loc.line, loc.column });
        }
    };

    pub const UnexpectedEof = struct { context: []const u8, expected_char: ?u8 = null };
    pub const UnexpectedCharacter = struct { expected: u8, found: u8 };
    pub const InvalidIdentifierStart = struct { char: u8 };
    pub const DuplicateAttribute = struct { name: []const u8 };
    pub const NodeAttributeError = struct { type: Parser.NodeType, name: []const u8 };
    pub const MissingHdocHeader = struct {};
    pub const DuplicateHdocHeader = struct {};
    pub const InvalidBlockError = struct { name: []const u8 };
    pub const InlineUsageError = struct { attribute: InlineAttribute };
    pub const InlineCombinationError = struct { first: InlineAttribute, second: InlineAttribute };
    pub const InvalidStringEscape = struct { codepoint: u21 };
    pub const ForbiddenControlCharacter = struct { codepoint: u21 };

    pub const Code = union(enum) {
        // errors:
        unterminated_inline_list,
        unexpected_eof: UnexpectedEof,
        unexpected_character: UnexpectedCharacter,
        unterminated_string,
        invalid_identifier_start: InvalidIdentifierStart,
        unterminated_block_list,
        missing_hdoc_header: MissingHdocHeader,
        duplicate_hdoc_header: DuplicateHdocHeader,
        missing_attribute: NodeAttributeError,
        invalid_attribute: NodeAttributeError,
        unknown_block_type: InvalidBlockError,
        invalid_block_type: InvalidBlockError,
        invalid_inline_combination: InlineCombinationError,
        link_not_nestable,
        invalid_link,
        invalid_date_time,
        invalid_date_time_fmt,
        invalid_unicode_string_escape,
        invalid_string_escape: InvalidStringEscape,
        illegal_character: ForbiddenControlCharacter,

        // warnings:
        document_starts_with_bom,
        unknown_attribute: NodeAttributeError,
        duplicate_attribute: DuplicateAttribute,
        empty_verbatim_block,
        verbatim_missing_trailing_newline,
        verbatim_missing_space,
        trailing_whitespace,
        empty_inline_body,
        redundant_inline: InlineUsageError,
        attribute_leading_trailing_whitespace,

        pub fn severity(code: Code) Severity {
            return switch (code) {
                .unterminated_inline_list,
                .unexpected_eof,
                .unexpected_character,
                .unterminated_string,
                .invalid_identifier_start,
                .unterminated_block_list,
                .missing_hdoc_header,
                .duplicate_hdoc_header,
                .invalid_attribute,
                .missing_attribute,
                .unknown_block_type,
                .invalid_block_type,
                .invalid_inline_combination,
                .link_not_nestable,
                .invalid_link,
                .invalid_date_time,
                .invalid_date_time_fmt,
                .invalid_string_escape,
                .illegal_character,
                .invalid_unicode_string_escape,
                => .@"error",

                .unknown_attribute,
                .duplicate_attribute,
                .empty_verbatim_block,
                .verbatim_missing_trailing_newline,
                .verbatim_missing_space,
                .trailing_whitespace,
                .empty_inline_body,
                .redundant_inline,
                .attribute_leading_trailing_whitespace,
                .document_starts_with_bom,
                => .warning,
            };
        }

        pub fn format(code: Code, w: anytype) !void {
            switch (code) {
                .document_starts_with_bom => try w.writeAll("Document starts with BOM (U+FEFF). HyperDoc recommends not using the BOM with UTF-8."),

                .unterminated_inline_list => try w.writeAll("Inline list body is unterminated (missing '}' before end of file)."),
                .unexpected_eof => |ctx| {
                    if (ctx.expected_char) |ch| {
                        try w.print("Unexpected end of file while expecting '{c}'.", .{ch});
                    } else {
                        try w.print("Unexpected end of file while expecting {s}.", .{ctx.context});
                    }
                },
                .unexpected_character => |ctx| try w.print("Expected '{c}' but found '{c}'.", .{ ctx.expected, ctx.found }),
                .unterminated_string => try w.writeAll("Unterminated string literal (missing closing \")."),
                .invalid_identifier_start => |ctx| try w.print("Invalid identifier start character: '{c}'.", .{ctx.char}),
                .unterminated_block_list => try w.writeAll("Block list body is unterminated (missing '}' before end of file)."),
                .missing_hdoc_header => try w.writeAll("Document must start with an 'hdoc' header."),
                .duplicate_hdoc_header => try w.writeAll("Only one 'hdoc' header is allowed; additional header found."),
                .duplicate_attribute => |ctx| try w.print("Duplicate attribute '{s}' will overwrite the earlier value.", .{ctx.name}),
                .empty_verbatim_block => try w.writeAll("Verbatim block has no lines."),
                .verbatim_missing_trailing_newline => try w.writeAll("Verbatim line should end with a newline."),
                .verbatim_missing_space => try w.writeAll("Expected a space after '|' in verbatim line."),
                .trailing_whitespace => try w.writeAll("Trailing whitespace at end of line."),

                .missing_attribute => |ctx| try w.print("Missing required attribute '{s}' for node type '{t}'.", .{ ctx.name, ctx.type }),
                .invalid_attribute => |ctx| try w.print("Invalid value for attribute '{s}' for node type '{t}'.", .{ ctx.name, ctx.type }),
                .unknown_attribute => |ctx| try w.print("Unknown attribute '{s}' for node type '{t}'.", .{ ctx.name, ctx.type }),
                .unknown_block_type => |ctx| try w.print("Unknown block type '{s}'.", .{ctx.name}),
                .invalid_block_type => |ctx| try w.print("Invalid block type '{s}' in this context.", .{ctx.name}),

                .empty_inline_body => try w.writeAll("Inline body is empty."),

                .redundant_inline => |ctx| try w.print("The inline \\{t} has no effect.", .{ctx.attribute}),
                .invalid_inline_combination => |ctx| try w.print("Cannot combine \\{t} with \\{t}.", .{ ctx.first, ctx.second }),
                .link_not_nestable => try w.writeAll("Links are not nestable"),
                .invalid_link => try w.writeAll("\\link requires either ref=\"…\" or uri=\"…\" attribute."),

                .attribute_leading_trailing_whitespace => try w.writeAll("Attribute value has invalid leading or trailing whitespace."),

                .invalid_date_time => try w.writeAll("Invalid date/time value."),

                .invalid_date_time_fmt => try w.writeAll("Invalid 'fmt' for date/time value."),

                .invalid_string_escape => |ctx| if (ctx.codepoint > 0x20 and ctx.codepoint <= 0x7F)
                    try w.print("\\{u} is not a valid escape sequence.", .{ctx.codepoint})
                else
                    try w.print("U+{X:0>2} is not a valid escape sequence.", .{ctx.codepoint}),

                .invalid_unicode_string_escape => try w.writeAll("Invalid unicode escape sequence"),

                .illegal_character => |ctx| try w.print("Forbidden control character U+{X:0>4}.", .{ctx.codepoint}),
            }
        }
    };

    code: Code,
    location: Location,
};

/// A collection of diagnostic messages.
pub const Diagnostics = struct {
    arena: std.heap.ArenaAllocator,
    items: std.ArrayList(Diagnostic) = .empty,

    pub fn init(allocator: std.mem.Allocator) Diagnostics {
        return .{ .arena = .init(allocator) };
    }

    pub fn deinit(diag: *Diagnostics) void {
        diag.arena.deinit();
        diag.* = undefined;
    }

    pub fn add(diag: *Diagnostics, code: Diagnostic.Code, location: Diagnostic.Location) !void {
        try diag.items.append(diag.arena.allocator(), .{
            .location = location,
            .code = code,
        });
    }

    pub fn has_error(diag: Diagnostics) bool {
        for (diag.items.items) |item| {
            if (item.code.severity() == .@"error")
                return true;
        }
        return false;
    }

    pub fn has_warning(diag: Diagnostics) bool {
        for (diag.items.items) |item| {
            if (item.code.severity() == .warning)
                return true;
        }
        return false;
    }
};

pub const InlineAttribute = enum {
    lang,
    em,
    mono,
    strike,
    sub,
    sup,
    link,
    syntax,
};

test "fuzz parser" {
    const Impl = struct {
        fn testOne(impl: @This(), data: []const u8) !void {
            _ = impl;

            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();

            var diagnostics: Diagnostics = .init(std.testing.allocator);
            defer diagnostics.deinit();

            var doc = parse(std.testing.allocator, data, &diagnostics) catch return;
            defer doc.deinit();
        }
    };

    try std.testing.fuzz(Impl{}, Impl.testOne, .{
        .corpus = &.{
            "hdoc(version=\"2.0\");",
            @embedFile("examples/tables.hdoc"),
            @embedFile("examples/featurematrix.hdoc"),
            @embedFile("examples/demo.hdoc"),
            @embedFile("examples/guide.hdoc"),
            @embedFile("test/accept/stress.hdoc"),
        },
    });
}

test "fuzz string unescape" {
    const Impl = struct {
        fn testOne(impl: @This(), string_literal: []const u8) !void {
            // Don't test if the string doesn't follow our rules:
            if (string_literal.len < 2)
                return;
            if (string_literal[0] != '"' or string_literal[string_literal.len - 1] != '"')
                return;
            if (string_literal.len >= 3 and string_literal[string_literal.len - 2] == '\\')
                return;

            // Check for valid UTF-8
            _ = std.unicode.utf8CountCodepoints(string_literal) catch return;

            _ = impl;

            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();

            var diagnostics: Diagnostics = .init(std.testing.allocator);
            defer diagnostics.deinit();

            var sema: SemanticAnalyzer = .{
                .arena = arena.allocator(),
                .code = string_literal,
                .diagnostics = &diagnostics,
            };

            const output = try sema.unescape_string(.{
                .location = .{ .offset = 0, .length = string_literal.len },
                .text = string_literal,
            });

            _ = output;
        }
    };

    try std.testing.fuzz(Impl{}, Impl.testOne, .{
        .corpus = &.{
            \\""
            ,
            \\"hello"
            ,
            \\"simple ASCII 123"
            ,
            \\"quote: \"inside\" ok"
            ,
            \\"backslash: \\ path"
            ,
            \\"mixed: \"a\" and \\b\\"
            ,
            \\"line1\nline2"
            ,
            \\"windows\r\nnew line"
            ,
            \\"unicode snowman: \u{2603} yay"
            ,
            \\"emoji: \u{1F642} smile"
            ,
            \\"CJK: \u{65E5}\u{672C}\u{8A9E}"
            ,
            \\"math: \u{221E} infinity"
            ,
            \\"euro: \u{20AC} symbol"
            ,
            \\"accented: café"
            ,
            \\"escaped braces: \u{7B} \u{7D}"
            ,
            \\"leading zeros: \u{000041} is A"
            ,
            \\"json-ish: {\"k\":\"v\"}"
            ,
            \\"literal sequence: \\\" done"
            ,
            \\"multiple lines:\n- one\n- two"
            ,
            \\"CR only:\rreturn"
            ,
            \\"mix: \u{1F4A1} idea \"quoted\" \\slash"
            ,
            //
            // Adversarial ones:
            //
            \\"tab escape: \t is not allowed"
            ,
            \\"backspace: \b not allowed"
            ,
            \\"null: \0 not allowed"
            ,
            \\"hex escape: \x20 not allowed"
            ,
            \\"octal-ish: \123 not allowed"
            ,
            \\"single quote escape: \' not allowed"
            ,
            \\"unicode short form: \u0041 not allowed"
            ,
            \\"empty unicode: \u{} not allowed"
            ,
            \\"missing closing brace: \u{41 not closed"
            ,
            \\"missing opening brace: \u41} not opened"
            ,
            \\"non-hex digit: \u{12G} invalid"
            ,
            \\"too many digits: \u{1234567} invalid"
            ,
            \\"out of range: \u{110000} invalid"
            ,
            \\"surrogate: \u{D800} invalid"
            ,
            \\"forbidden NUL via unicode: \u{0} invalid"
            ,
            \\"forbidden TAB via unicode: \u{9} invalid"
            ,
            \\"forbidden C1 control: \u{80} invalid"
            ,
            \\"unknown escape: \q invalid"
            ,
            \\"backslash-space escape: \ a invalid"
            ,
            \\"bad hex tail: \u{1F60Z} invalid"
        },
    });
}

test "fuzz Date.parse" {
    const Impl = struct {
        fn testOne(impl: @This(), string_literal: []const u8) !void {
            _ = impl;
            _ = Date.parse(string_literal) catch return;
        }
    };

    const corpus: []const []const u8 = &.{
        "",
        // good input:
        "2025-12-25",
        "1-01-01",
        "0-01-01",
        "1999-11-30",
        "2024-02-29",
        "2025-02-31",
        "9999-12-31",
        "10000-01-01",
        "123456-07-04",
        "42-03-15",
        "2025-01-31",
        "2025-04-30",
        "2025-06-01",
        "2025-10-10",
        "2025-09-09",
        "2025-08-08",
        "2025-07-07",
        "2025-05-05",
        "2025-12-01",
        "2025-11-11",
        // bad input:
        "2025-1-01",
        "2025-01-1",
        "2025/01/01",
        "2025-00-10",
        "2025-13-10",
        "2025-12-00",
        "2025-12-32",
        "2025-12-3a",
        "20a5-12-25",
        "-2025-12-25",
        "+2025-12-25",
        "20251225",
        "2025--12-25",
        "2025-12-25 ",
        " 2025-12-25",
        "٢٠٢٥-١٢-٢٥",
        "2025-12",
        "2025-12-250",
        "2025-12-25T00:00:00Z",
        "2025-12-25\n",
    };

    for (corpus) |item| {
        try Impl.testOne(.{}, item);
    }

    try std.testing.fuzz(Impl{}, Impl.testOne, .{
        .corpus = corpus,
    });
}

test "fuzz Time.parse" {
    const Impl = struct {
        fn testOne(impl: @This(), string_literal: []const u8) !void {
            _ = impl;
            _ = Time.parse(string_literal, null) catch return;
        }
    };

    try std.testing.fuzz(Impl{}, Impl.testOne, .{
        .corpus = &.{
            "",
            // good input:
            "00:00:00Z",
            "23:59:59Z",
            "12:34:56Z",
            "01:02:03+00:00",
            "22:30:46+01:00",
            "22:30:46-05:30",
            "08:15:00+14:00",
            "19:45:30-00:45",
            "05:06:07.1Z",
            "05:06:07.12Z",
            "05:06:07.123Z",
            "05:06:07.123456Z",
            "05:06:07.123456789Z",
            "23:59:59.000+02:00",
            "10:20:30.000000-03:00",
            "10:20:30.000000000+03:00",
            "00:00:00.9-12:34",
            "14:00:00+23:59",
            "09:09:09.6+09:00",
            "16:17:18.136+01:00",
            // bad input:
            "24:00:00Z",
            "23:60:00Z",
            "23:59:60Z",
            "9:00:00Z",
            "09:0:00Z",
            "09:00:0Z",
            "09:00Z",
            "09:00:00",
            "09:00:00z",
            "09:00:00+1:00",
            "09:00:00+01:0",
            "09:00:00+0100",
            "09:00:00+25:00",
            "09:00:00+01:60",
            "09:00:00,+01:00",
            "09:00:00,123Z",
            "09:00:00.1234Z",
            "09:00:00.12345Z",
            "09:00:00.1234567Z",
            "٠٩:٠٠:٠٠Z",
        },
    });
}

test "fuzz DateTime.parse" {
    const Impl = struct {
        fn testOne(impl: @This(), string_literal: []const u8) !void {
            _ = impl;
            _ = DateTime.parse(string_literal, null) catch return;
        }
    };

    try std.testing.fuzz(Impl{}, Impl.testOne, .{
        .corpus = &.{
            "",
            // good input:
            "2025-12-25T22:31:50Z",
            "2025-12-25T22:31:50.1Z",
            "2025-12-25T22:31:50.12+01:00",
            "2025-12-25T22:31:50.123-05:30",
            "1-01-01T00:00:00Z",
            "0-01-01T00:00:00+00:00",
            "1999-11-30T23:59:59-00:45",
            "2024-02-29T12:00:00Z",
            "2025-02-31T08:15:00+14:00",
            "9999-12-31T23:59:59.123456Z",
            "10000-01-01T00:00:00.123456789+03:00",
            "42-03-15T01:02:03+23:59",
            "2025-01-31T10:20:30.000000-03:00",
            "2025-04-30T10:20:30.000+02:00",
            "2025-06-01T16:17:18.136+01:00",
            "2025-10-10T09:09:09.6+09:00",
            "2025-09-09T19:45:30-00:45",
            "2025-08-08T05:06:07.123Z",
            "2025-07-07T05:06:07.123456789Z",
            "123456-07-04T14:00:00Z",
            // bad input:
            "2025-12-25 22:31:50Z",
            "2025-12-25t22:31:50Z",
            "2025-12-25T22:31:50",
            "2025-12-25T22:31Z",
            "2025-12-25T24:00:00Z",
            "2025-12-25T23:60:00Z",
            "2025-12-25T23:59:60Z",
            "2025-12-25T23:59:59.1234Z",
            "2025-12-25T23:59:59,123Z",
            "2025-12-25T23:59:59+0100",
            "2025-12-25T23:59:59+01:60",
            "2025-12-25T23:59:59+25:00",
            "2025-00-25T23:59:59Z",
            "2025-13-25T23:59:59Z",
            "2025-12-00T23:59:59Z",
            "2025-12-32T23:59:59Z",
            "2025-12-25TT23:59:59Z",
            "2025-12-25T23:59:59Z ",
            "٢٠٢٥-١٢-٢٥T٢٢:٣١:٥٠Z",
            "2025-12-25T23:59:59+01",
        },
    });
}
