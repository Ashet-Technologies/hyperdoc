const std = @import("std");

pub const render = struct {
    pub const yaml = @import("render/dump.zig").render;
    pub const html5 = @import("render/html5.zig").render;
};

/// A HyperDoc document. Contains both memory and
/// tree structure of the document.
pub const Document = struct {
    arena: std.heap.ArenaAllocator,

    version: Version,

    // document contents:
    contents: []Block,
    content_ids: []?Reference,
    id_map: std.StringArrayHashMapUnmanaged(usize), // id -> index
    toc: TableOfContents,

    // header information
    lang: LanguageTag = .inherit, // inherit here means "unset"
    title: ?Title = null,
    author: ?[]const u8,
    date: ?DateTime,
    timezone: ?TimeZoneOffset,

    pub const Title = struct {
        full: Block.Title,
        simple: []const u8,
    };

    pub const TableOfContents = struct {
        level: Block.Heading.Level, // TODO: Refactor to use `index` here as well.
        headings: []usize,
        children: []TableOfContents,
    };

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
        index: Index,
        lang: LanguageTag,
        content: []Span,

        pub const Level = enum(u2) {
            pub const count: comptime_int = @typeInfo(@This()).@"enum".fields.len;

            h1 = 0,
            h2 = 1,
            h3 = 2,
        };

        /// Stores both heading level and the index number of that heading.
        /// h1 is §[0]
        /// h2 is §[0].[1]
        /// h3 is §[0].[1].[2]
        pub const Index = union(Level) {
            h1: [1]u16,
            h2: [2]u16,
            h3: [3]u16,
        };
    };

    pub const Paragraph = struct {
        kind: ParagraphKind,
        lang: LanguageTag,
        content: []Span,
    };

    pub const ParagraphKind = enum { p, note, warning, danger, tip, quote, spoiler };

    pub const List = struct {
        lang: LanguageTag,
        first: ?u32,
        items: []ListItem,
    };

    pub const ListItem = struct {
        lang: LanguageTag,
        content: []Block,
    };

    pub const Image = struct {
        lang: LanguageTag,
        alt: []const u8, // empty means none
        path: []const u8,
        content: []Span,
    };

    pub const Preformatted = struct {
        lang: LanguageTag,
        syntax: ?[]const u8,
        content: []Span,
    };

    pub const TableOfContents = struct {
        lang: LanguageTag,
        depth: u8,
    };

    pub const Table = struct {
        // TODO: column_count: usize,
        // TODO: has_row_titles: bool, // not counted inside `Table.column_count`!
        lang: LanguageTag,
        rows: []TableRow,
    };

    pub const TableRow = union(enum) {
        columns: TableColumns,
        row: TableDataRow,
        group: TableGroup,
    };

    pub const TableColumns = struct {
        lang: LanguageTag,
        cells: []TableCell,
    };

    pub const TableDataRow = struct {
        lang: LanguageTag,
        title: ?[]const u8,
        cells: []TableCell,
    };

    pub const TableGroup = struct {
        lang: LanguageTag,
        content: []Span,
    };

    pub const TableCell = struct {
        lang: LanguageTag,
        colspan: u32,
        content: []Block,
    };

    pub const Title = struct {
        lang: LanguageTag,
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
        lang: LanguageTag = .inherit,
        position: ScriptPosition = .baseline,
        em: bool = false,
        mono: bool = false,
        strike: bool = false,
        link: Link = .none,
        syntax: []const u8 = "", // empty is absence

        pub fn eql(lhs: Attributes, rhs: Attributes) bool {
            // Trivial comparisons:
            if (lhs.position != rhs.position)
                return false;
            if (lhs.em != rhs.em)
                return false;
            if (lhs.mono != rhs.mono)
                return false;
            if (lhs.strike != rhs.strike)
                return false;

            // string comparison:
            if (!std.mem.eql(u8, lhs.syntax, rhs.syntax))
                return false;

            // complex comparison
            if (!lhs.lang.eql(rhs.lang))
                return false;
            if (!lhs.link.eql(rhs.link))
                return false;

            return true;
        }
    };

    content: Content,
    attribs: Attributes,
    location: Parser.Location,
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

    pub fn eql(lhs: Link, rhs: Link) bool {
        return switch (lhs) {
            .none => (rhs == .none),
            .ref => (rhs == .ref) and std.mem.eql(u8, lhs.ref.text, rhs.ref.text),
            .uri => (rhs == .uri) and std.mem.eql(u8, lhs.uri.text, rhs.uri.text),
        };
    }
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

    pub fn parse(text: []const u8, timezone_hint: ?TimeZoneOffset) !DateTime {
        const split_index = std.mem.indexOfScalar(u8, text, 'T') orelse return error.InvalidValue;

        const head = text[0..split_index];
        const tail = text[split_index + 1 ..];

        return .{
            .date = try Date.parse(head),
            .time = try Time.parse(tail, timezone_hint),
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
        if (text.len != "YYYY-MM-DD".len)
            return error.InvalidValue;
        const first_dash = std.mem.indexOfScalar(u8, text, '-') orelse return error.InvalidValue;
        const tail = text[first_dash + 1 ..];
        const second_dash_rel = std.mem.indexOfScalar(u8, tail, '-') orelse return error.InvalidValue;
        const second_dash = first_dash + 1 + second_dash_rel;

        const year_text = text[0..first_dash];
        const month_text = text[first_dash + 1 .. second_dash];
        const day_text = text[second_dash + 1 ..];

        if (year_text.len != 4 or month_text.len != 2 or day_text.len != 2) return error.InvalidValue;

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
    timezone: TimeZoneOffset,

    pub fn parse(text: []const u8, timezone_hint: ?TimeZoneOffset) !Time {
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
            timezone_hint orelse return error.MissingTimezone
        else
            try TimeZoneOffset.parse(text[index..]);

        return .{
            .hour = @intCast(hour),
            .minute = @intCast(minute),
            .second = @intCast(second),
            .microsecond = microsecond,
            .timezone = timezone,
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

/// A time offset to timezones in minutes.
pub const TimeZoneOffset = enum(i32) {
    utc = 0,

    _,

    pub fn from_hhmm(hour: i8, minute: u8) error{InvalidValue}!TimeZoneOffset {
        const hour_pos = @abs(hour);
        const sign = std.math.sign(hour);

        if (hour < -23 and hour > 23)
            return error.InvalidValue;
        if (minute >= 60)
            return error.InvalidValue;

        return @enumFromInt(@as(i32, sign) * (hour_pos * @as(i32, 60) + minute));
    }

    pub fn parse(timezone: []const u8) error{InvalidValue}!TimeZoneOffset {
        if (timezone.len != 1 and timezone.len != 6) // "Z" or "±HH:MM"
            return error.InvalidValue;

        if (timezone.len == 1) {
            if (timezone[0] != 'Z')
                return error.InvalidValue;
            return .utc;
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

        return @enumFromInt(offset_minutes);
    }
};

/// Type-safe wrapper around a URI attribute.
pub const Uri = struct {
    pub const empty: Uri = .{ .text = "" };

    text: []const u8,

    pub fn init(text: []const u8) Uri {
        // TODO: Add correctness validation here (IRI syntax, non-empty).
        return .{ .text = text };
    }
};

/// Type-safe wrapper around a reference value (id/ref) attribute.
pub const Reference = struct {
    pub const empty: Reference = .{ .text = "" };

    text: []const u8,

    pub fn parse(text: []const u8) !Reference {
        if (text.len == 0)
            return error.InvalidValue;

        var view: std.unicode.Utf8View = try .init(text);
        var iter = view.iterator();
        while (iter.nextCodepoint()) |codepoint| {
            if (SemanticAnalyzer.is_illegal_character(codepoint))
                return error.InvalidValue;
            switch (codepoint) {
                '\t', '\r', '\n', ' ' => return error.InvalidValue,
                else => {},
            }
        }

        return .{ .text = text };
    }

    pub fn eql(lhs: Reference, rhs: Reference) bool {
        return std.mem.eql(u8, lhs.text, rhs.text);
    }
};

/// A BCP 47 language tag.
pub const LanguageTag = struct {
    //! https://datatracker.ietf.org/doc/html/rfc5646

    /// The empty language tag means that the language is inherited from the parent.
    pub const inherit: LanguageTag = .{ .text = "" };

    text: []const u8,

    pub fn parse(tag_str: []const u8) !LanguageTag {
        // TODO: Implement proper BCP 47 tag verification
        return .{ .text = tag_str };
    }

    pub fn eql(lhs: LanguageTag, rhs: LanguageTag) bool {
        return std.mem.eql(u8, lhs.text, rhs.text);
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
) error{ OutOfMemory, SyntaxError, MalformedDocument, UnsupportedVersion, InvalidUtf8 }!Document {
    const source_text = try clean_utf8_input(diagnostics, raw_plain_text);

    // We now know that the source code is 'fine' and

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

    const content_ids = try sema.ids.toOwnedSlice(arena.allocator());
    const id_locations = sema.id_locations.items;
    std.debug.assert(id_locations.len == content_ids.len);

    var id_map: std.StringArrayHashMapUnmanaged(usize) = .empty;
    errdefer id_map.deinit(arena.allocator());

    try id_map.ensureTotalCapacity(arena.allocator(), content_ids.len);

    for (content_ids, 0..) |id_or_null, index| {
        const id = id_or_null orelse continue;
        const id_location = id_locations[index] orelse Parser.Location{ .offset = 0, .length = 0 };

        const gop = id_map.getOrPutAssumeCapacity(id.text);
        if (gop.found_existing) {
            try sema.emit_diagnostic(
                .{ .duplicate_id = .{ .ref = id.text } },
                id_location,
            );
            continue;
        }
        gop.value_ptr.* = index;
    }

    try sema.validate_references(&id_map);

    const doc_lang = header.lang orelse LanguageTag.inherit;
    const title = try sema.finalize_title(header, doc_lang);
    const contents = try sema.blocks.toOwnedSlice(arena.allocator());
    const block_locations = try sema.block_locations.toOwnedSlice(arena.allocator());
    const toc = try sema.build_toc(contents, block_locations);

    return .{
        .arena = arena,
        .contents = contents,
        .content_ids = content_ids,
        .id_map = id_map,
        .toc = toc,

        .lang = doc_lang,
        .title = title,
        .version = header.version,
        .author = header.author,
        .date = header.date,
        .timezone = header.timezone,
    };
}

pub fn clean_utf8_input(diagnostics: ?*Diagnostics, raw_plain_text: []const u8) error{ OutOfMemory, InvalidUtf8 }![]const u8 {

    // First check if all of our code is valid UTF-8
    // and if it potentially starts with a BOM.
    var view = std.unicode.Utf8View.init(raw_plain_text) catch {
        return error.InvalidUtf8;
    };

    var iter = view.iterator();
    if (iter.nextCodepointSlice()) |slice| {
        const codepoint = std.unicode.utf8Decode(slice) catch unreachable;
        if (codepoint == 0xFEFF) {
            if (diagnostics) |diag| {
                try diag.add(.document_starts_with_bom, .{ .column = 1, .line = 1 });
            }
            std.debug.assert(iter.i == slice.len);
        } else {
            iter.i = 0; // Reset iterator to start position
        }
    }
    const source_head = iter.i;

    var line: u32 = 1;
    var column: u32 = 1;
    var saw_invalid = false;

    var prev_was_cr = false;
    var prev_cr_location: Diagnostic.Location = undefined;

    while (iter.nextCodepointSlice()) |slice| {
        const codepoint = std.unicode.utf8Decode(slice) catch unreachable;

        const location: Diagnostic.Location = .{ .line = line, .column = column };

        if (prev_was_cr) {
            if (codepoint != '\n') {
                if (diagnostics) |diag| {
                    try diag.add(.bare_carriage_return, prev_cr_location);
                }
                saw_invalid = true;
            }
            prev_was_cr = false;
            if (codepoint == '\n') {
                continue;
            }
        }

        if (codepoint == '\r') {
            prev_was_cr = true;
            prev_cr_location = location;
            line += 1;
            column = 1;
            continue;
        }

        if (codepoint == '\n') {
            line += 1;
            column = 1;
            continue;
        }

        if (codepoint == '\t') {
            if (diagnostics) |diag| {
                try diag.add(.tab_character, location);
            }
        } else if (SemanticAnalyzer.is_illegal_character(codepoint)) {
            if (diagnostics) |diag| {
                try diag.add(.{ .illegal_character = .{ .codepoint = codepoint } }, location);
            }
            saw_invalid = true;
        }

        column += 1;
    }

    if (prev_was_cr) {
        if (diagnostics) |diag| {
            try diag.add(.bare_carriage_return, prev_cr_location);
        }
        saw_invalid = true;
    }

    if (saw_invalid)
        return error.InvalidUtf8;

    return raw_plain_text[source_head..];
}

pub const SemanticAnalyzer = struct {
    const whitespace_chars = " \t\r\n";

    const Header = struct {
        version: Version,
        lang: ?LanguageTag,
        title: ?[]const u8,
        author: ?[]const u8,
        timezone: ?TimeZoneOffset,
        date: ?DateTime,
    };

    const RefUse = struct {
        ref: Reference,
        location: Parser.Location,
    };

    const TocBuilder = struct {
        level: Block.Heading.Level,
        headings: std.ArrayList(usize),
        children: std.ArrayList(*TocBuilder),

        fn init(level: Block.Heading.Level) @This() {
            return .{
                .level = level,
                .headings = .empty,
                .children = .empty,
            };
        }
    };

    arena: std.mem.Allocator,
    diagnostics: ?*Diagnostics,
    code: []const u8,

    header: ?Header = null,
    title_block: ?Block.Title = null,
    title_location: ?Parser.Location = null,
    top_level_index: usize = 0,
    blocks: std.ArrayList(Block) = .empty,
    block_locations: std.ArrayList(Parser.Location) = .empty,
    ids: std.ArrayList(?Reference) = .empty,
    id_locations: std.ArrayList(?Parser.Location) = .empty,
    pending_refs: std.ArrayList(RefUse) = .empty,

    current_heading_level: usize = 0,
    heading_counters: [Block.Heading.Level.count]u16 = @splat(0),

    fn append_node(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, UnsupportedVersion }!void {
        const node_index = sema.top_level_index;
        sema.top_level_index += 1;

        switch (node.type) {
            .hdoc => {
                if (node_index != 0) {
                    try sema.emit_diagnostic(.misplaced_hdoc_header, node.location);
                }
                if (node.body != .empty) {
                    try sema.emit_diagnostic(.non_empty_hdoc_body, node.location);
                }

                const header = sema.translate_header_node(node) catch |err| switch (err) {
                    error.OutOfMemory, error.UnsupportedVersion => |e| return e,
                    error.BadAttributes => null,
                };
                if (sema.header != null) {
                    try sema.emit_diagnostic(.duplicate_hdoc_header, node.location);
                } else {
                    sema.header = header orelse .{
                        .version = .{ .major = 2, .minor = 0 },
                        .lang = null,
                        .title = null,
                        .author = null,
                        .timezone = null,
                        .date = null,
                    };
                }
                std.debug.assert(sema.header != null);
            },

            .title => {
                if (sema.header == null and node_index == 0) {
                    try sema.emit_diagnostic(.missing_hdoc_header, node.location);
                }
                if (node_index != 1) {
                    try sema.emit_diagnostic(.misplaced_title_block, node.location);
                }
                if (sema.title_block != null) {
                    try sema.emit_diagnostic(.duplicate_title_block, node.location);
                    return;
                }

                const title_block = sema.translate_title_node(node) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.BadAttributes => {
                        return;
                    },
                };

                sema.title_block = title_block;
                sema.title_location = node.location;
            },

            else => {
                if (sema.header == null and node_index == 0) {
                    try sema.emit_diagnostic(.missing_hdoc_header, node.location);
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

                const id_location = if (id != null)
                    get_attribute_location(node, "id", .value) orelse get_attribute_location(node, "id", .name) orelse node.location
                else
                    null;

                try sema.blocks.append(sema.arena, block);
                try sema.block_locations.append(sema.arena, node.location);
                try sema.ids.append(sema.arena, id);
                try sema.id_locations.append(sema.arena, id_location);
            },
        }
    }

    fn translate_header_node(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, BadAttributes, UnsupportedVersion }!Header {
        std.debug.assert(node.type == .hdoc);

        const attrs = try sema.get_attributes(node, struct {
            version: Version,
            title: ?[]const u8 = null,
            author: ?[]const u8 = null,
            date: ?[]const u8 = null,
            lang: LanguageTag = .inherit,
            tz: ?TimeZoneOffset = null,
        });

        const lang_location = get_attribute_location(node, "lang", .name);
        if (lang_location == null) {
            try sema.emit_diagnostic(.missing_document_language, node.location);
        }

        if (attrs.version.major != 2)
            return error.UnsupportedVersion;
        if (attrs.version.minor != 0)
            return error.UnsupportedVersion;

        const date = if (attrs.date) |date_str|
            DateTime.parse(date_str, attrs.tz) catch blk: {
                try sema.emit_diagnostic(.{ .invalid_attribute = .{ .type = node.type, .name = "date" } }, get_attribute_location(node, "date", .value).?);
                break :blk null;
            }
        else
            null;

        return .{
            .version = attrs.version,
            .lang = if (lang_location != null) attrs.lang else null,
            .title = attrs.title,
            .author = attrs.author,
            .date = date,
            .timezone = attrs.tz,
        };
    }

    /// Translates a top-level block node.
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
            .title => {
                try sema.emit_diagnostic(.{ .invalid_block_type = .{ .name = sema.code[node.location.offset .. node.location.offset + node.location.length] } }, node.location);
                return error.InvalidNodeType;
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
            lang: LanguageTag = .inherit,
            id: ?Reference = null,
        });

        const heading: Block.Heading = .{
            .index = try sema.compute_next_heading(node, switch (node.type) {
                .h1 => .h1,
                .h2 => .h2,
                .h3 => .h3,
                else => unreachable,
            }),
            .lang = attrs.lang,
            .content = try sema.translate_inline(node, .emit_diagnostic, .one_space),
        };

        return .{ heading, attrs.id };
    }

    fn translate_title_node(sema: *SemanticAnalyzer, node: Parser.Node) !Block.Title {
        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
        });

        return .{
            .lang = attrs.lang,
            .content = try sema.translate_inline(node, .emit_diagnostic, .one_space),
        };
    }

    fn translate_paragraph_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Paragraph, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
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
            .content = try sema.translate_inline(node, .emit_diagnostic, .one_space),
        };

        return .{ heading, attrs.id };
    }

    fn translate_list_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.List, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
            id: ?Reference = null,
            first: ?u32 = null,
        });

        if (attrs.first != null and node.type != .ol) {
            try sema.emit_diagnostic(.{ .invalid_attribute = .{ .type = node.type, .name = "first" } }, get_attribute_location(node, "first", .name).?);
        }

        var children: std.ArrayList(Block.ListItem) = .empty;
        defer children.deinit(sema.arena);

        var saw_list_body = false;
        switch (node.body) {
            .list => |child_nodes| {
                saw_list_body = true;
                try children.ensureTotalCapacityPrecise(sema.arena, child_nodes.len);
                for (child_nodes) |child_node| {
                    const list_item = sema.translate_list_item_node(child_node) catch |err| switch (err) {
                        error.InvalidNodeType => {
                            try sema.emit_diagnostic(.illegal_child_item, node.location);
                            continue;
                        },
                        else => |e| return e,
                    };
                    children.appendAssumeCapacity(list_item);
                }
            },

            .empty, .string, .text_span, .verbatim => {
                try sema.emit_diagnostic(.list_body_required, node.location);
            },
        }

        if (saw_list_body and children.items.len == 0) {
            try sema.emit_diagnostic(.list_body_required, node.location);
        }

        const list: Block.List = .{
            .first = attrs.first orelse if (node.type == .ol) 1 else null,
            .lang = attrs.lang,
            .items = try children.toOwnedSlice(sema.arena),
        };

        return .{ list, attrs.id };
    }

    fn translate_image_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Image, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
            id: ?Reference = null,
            alt: ?[]const u8 = null,
            path: []const u8,
        });

        const alt = if (attrs.alt) |alt|
            std.mem.trim(u8, alt, whitespace_chars)
        else
            "";

        const path = std.mem.trim(u8, attrs.path, whitespace_chars);
        if (path.len == 0) {
            // The path must be non-empty.

            try sema.emit_diagnostic(.{ .empty_attribute = .{ .type = .img, .name = "path" } }, get_attribute_location(node, "path", .value).?);
        }

        if (attrs.alt != null and alt.len == 0) {
            // If alt is present, it must be non-empty, and not fully whitespace.

            try sema.emit_diagnostic(.{ .empty_attribute = .{ .type = .img, .name = "alt" } }, get_attribute_location(node, "alt", .value).?);
        }

        const image: Block.Image = .{
            .lang = attrs.lang,
            .alt = alt,
            .path = path,
            .content = try sema.translate_inline(node, .allow_empty, .one_space),
        };

        return .{ image, attrs.id };
    }

    fn translate_preformatted_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Preformatted, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
            id: ?Reference = null,
            syntax: ?[]const u8 = null,
        });

        const preformatted: Block.Preformatted = .{
            .lang = attrs.lang,
            .syntax = attrs.syntax,
            .content = try sema.translate_inline(node, .emit_diagnostic, .keep_space),
        };

        return .{ preformatted, attrs.id };
    }

    fn translate_toc_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.TableOfContents, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
            id: ?Reference = null,
            depth: ?u8 = null,
        });

        const max_depth = Block.Heading.Level.count;

        var depth = attrs.depth orelse max_depth;
        if (depth < 1 or depth > max_depth) {
            try sema.emit_diagnostic(.{ .invalid_attribute = .{ .type = node.type, .name = "depth" } }, get_attribute_location(node, "depth", .value) orelse node.location);
            depth = @max(1, @min(max_depth, depth));
        }

        switch (node.body) {
            .empty => {},
            .list => |child_nodes| {
                for (child_nodes) |child_node| {
                    try sema.emit_diagnostic(.illegal_child_item, child_node.location);
                }
            },
            .string, .verbatim, .text_span => {
                try sema.emit_diagnostic(.illegal_child_item, node.location);
            },
        }

        const toc: Block.TableOfContents = .{
            .lang = attrs.lang,
            .depth = depth,
        };

        return .{ toc, attrs.id };
    }

    fn translate_table_node(sema: *SemanticAnalyzer, node: Parser.Node) !struct { Block.Table, ?Reference } {
        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
            id: ?Reference = null,
        });

        var rows: std.ArrayList(Block.TableRow) = .empty;
        defer rows.deinit(sema.arena);

        var column_count: ?usize = null;

        switch (node.body) {
            .list => |child_nodes| {
                try rows.ensureTotalCapacityPrecise(sema.arena, child_nodes.len);
                for (child_nodes) |child_node| {
                    switch (child_node.type) {
                        .columns => {
                            const row_attrs = try sema.get_attributes(child_node, struct {
                                lang: LanguageTag = .inherit,
                            });

                            const cells = try sema.translate_table_cells(child_node);
                            rows.appendAssumeCapacity(.{
                                .columns = .{
                                    .lang = row_attrs.lang,
                                    .cells = cells,
                                },
                            });

                            var width: usize = 0;
                            for (cells) |cell| {
                                std.debug.assert(cell.colspan > 0);
                                width += cell.colspan;
                            }

                            column_count = column_count orelse width;
                            if (width != column_count) {
                                try sema.emit_diagnostic(.{ .column_count_mismatch = .{
                                    .expected = column_count.?,
                                    .actual = width,
                                } }, child_node.location);
                            }
                        },
                        .row => {
                            const row_attrs = try sema.get_attributes(child_node, struct {
                                lang: LanguageTag = .inherit,
                                title: ?[]const u8 = null,
                            });

                            const cells = try sema.translate_table_cells(child_node);

                            rows.appendAssumeCapacity(.{
                                .row = .{
                                    .lang = row_attrs.lang,
                                    .title = row_attrs.title,
                                    .cells = cells,
                                },
                            });

                            var width: usize = 0;
                            for (cells) |cell| {
                                std.debug.assert(cell.colspan > 0);
                                width += cell.colspan;
                            }

                            column_count = column_count orelse width;
                            if (width != column_count) {
                                try sema.emit_diagnostic(.{ .column_count_mismatch = .{
                                    .expected = column_count.?,
                                    .actual = width,
                                } }, child_node.location);
                            }
                        },
                        .group => {
                            const row_attrs = try sema.get_attributes(child_node, struct {
                                lang: LanguageTag = .inherit,
                            });

                            rows.appendAssumeCapacity(.{
                                .group = .{
                                    .lang = row_attrs.lang,
                                    .content = try sema.translate_inline(child_node, .emit_diagnostic, .one_space),
                                },
                            });
                        },
                        else => {
                            try sema.emit_diagnostic(.illegal_child_item, child_node.location);
                        },
                    }
                }
            },
            .empty, .string, .verbatim, .text_span => {
                try sema.emit_diagnostic(.list_body_required, node.location);
            },
        }

        const table: Block.Table = .{
            .lang = attrs.lang,
            .rows = try rows.toOwnedSlice(sema.arena),
        };

        return .{ table, attrs.id };
    }

    fn translate_table_cells(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, BadAttributes, InvalidNodeType, Unimplemented }![]Block.TableCell {
        var cells: std.ArrayList(Block.TableCell) = .empty;
        defer cells.deinit(sema.arena);

        var saw_list_body = false;
        switch (node.body) {
            .list => |child_nodes| {
                saw_list_body = true;
                try cells.ensureTotalCapacityPrecise(sema.arena, child_nodes.len);
                for (child_nodes) |child_node| {
                    const cell = sema.translate_table_cell_node(child_node) catch |err| switch (err) {
                        error.InvalidNodeType => {
                            try sema.emit_diagnostic(.illegal_child_item, child_node.location);
                            continue;
                        },
                        else => |e| return e,
                    };
                    cells.appendAssumeCapacity(cell);
                }
            },
            .empty, .string, .verbatim, .text_span => {
                try sema.emit_diagnostic(.list_body_required, node.location);
            },
        }

        if (saw_list_body and cells.items.len == 0) {
            try sema.emit_diagnostic(.list_body_required, node.location);
        }

        return try cells.toOwnedSlice(sema.arena);
    }

    fn translate_table_cell_node(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, BadAttributes, InvalidNodeType, Unimplemented }!Block.TableCell {
        switch (node.type) {
            .td => {},
            else => return error.InvalidNodeType,
        }

        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
            colspan: ?u32 = null,
        });

        var colspan = attrs.colspan orelse 1;
        if (colspan < 1) {
            try sema.emit_diagnostic(.{ .invalid_attribute = .{ .type = node.type, .name = "colspan" } }, get_attribute_location(node, "colspan", .value) orelse node.location);
            colspan = 1;
        }

        return .{
            .lang = attrs.lang,
            .colspan = colspan,
            .content = try sema.translate_block_list(node, .text_to_p),
        };
    }

    fn translate_list_item_node(sema: *SemanticAnalyzer, node: Parser.Node) !Block.ListItem {
        switch (node.type) {
            .li => {},
            else => return error.InvalidNodeType,
        }

        const attrs = try sema.get_attributes(node, struct {
            lang: LanguageTag = .inherit,
        });

        return .{
            .lang = attrs.lang,
            .content = try sema.translate_block_list(node, .text_to_p),
        };
    }

    const BlockTextUpgrade = enum { no_upgrade, text_to_p };

    fn translate_block_list(sema: *SemanticAnalyzer, node: Parser.Node, upgrade: BlockTextUpgrade) error{ Unimplemented, InvalidNodeType, OutOfMemory, BadAttributes }![]Block {
        switch (node.body) {
            .list => |child_nodes| {
                var blocks: std.ArrayList(Block) = .empty;
                defer blocks.deinit(sema.arena);

                try blocks.ensureTotalCapacityPrecise(sema.arena, child_nodes.len);

                for (child_nodes) |child_node| {
                    if (child_node.type == .toc) {
                        try sema.emit_diagnostic(.illegal_child_item, child_node.location);
                        continue;
                    }

                    const block, const id = try sema.translate_block_node(child_node);
                    if (id != null) {
                        try sema.emit_diagnostic(.illegal_id_attribute, get_attribute_location(child_node, "id", .name).?);
                    }
                    blocks.appendAssumeCapacity(block);
                }

                return try blocks.toOwnedSlice(sema.arena);
            },

            .empty, .string, .verbatim, .text_span => switch (upgrade) {
                .no_upgrade => {
                    try sema.emit_diagnostic(.{ .block_list_required = .{ .type = node.type } }, node.location);
                    return &.{};
                },
                .text_to_p => {
                    const spans = try sema.translate_inline(node, .emit_diagnostic, .one_space);

                    const blocks = try sema.arena.alloc(Block, 1);
                    blocks[0] = .{
                        .paragraph = .{
                            .kind = .p,
                            .lang = .inherit,
                            .content = spans,
                        },
                    };

                    return blocks;
                },
            },
        }
    }

    /// Translates a node into a sequence of inline spans.
    fn translate_inline(sema: *SemanticAnalyzer, node: Parser.Node, empty_handling: EmptyHandling, whitespace_handling: Whitespace) error{ OutOfMemory, BadAttributes }![]Span {
        var spans: std.ArrayList(Span) = .empty;
        defer spans.deinit(sema.arena);

        try sema.translate_inline_body(&spans, node.body, .{}, empty_handling);

        return try sema.compact_spans(spans.items, whitespace_handling);
    }

    const Whitespace = enum {
        one_space,
        keep_space,
    };

    /// Compacts and merges spans of equal attributes by `whitespace` ruling.
    fn compact_spans(sema: *SemanticAnalyzer, input: []const Span, whitespace: Whitespace) ![]Span {
        var merger: SpanMerger = .{
            .arena = sema.arena,
            .whitespace = whitespace,
        };

        for (input) |span| {
            try merger.push(span);
        }

        try merger.flush();

        return try merger.output.toOwnedSlice(sema.arena);
    }

    /// Checks if only
    fn is_only_whitespace(str: []const u8) bool {
        return std.mem.indexOfNone(u8, str, whitespace_chars) == null;
    }

    const SpanMerger = struct {
        arena: std.mem.Allocator,
        whitespace: Whitespace,

        output: std.ArrayList(Span) = .empty,

        span_start: usize = 0,
        current_span: std.ArrayList(u8) = .empty,
        attribs: Span.Attributes = .{},
        last_end: usize = std.math.maxInt(usize),

        fn push(merger: *SpanMerger, span: Span) !void {
            if (merger.last_end == std.math.maxInt(usize)) {
                merger.last_end = span.location.offset;
            }

            if (!span.attribs.eql(merger.attribs)) {
                try merger.flush_internal(.keep);
                std.debug.assert(merger.current_span.items.len == 0);
                merger.attribs = span.attribs;
                std.debug.assert(span.attribs.eql(merger.attribs));
            }
            switch (span.content) {
                .date, .time, .datetime => {
                    // All date/time/datetime require to be passed verbatim into the output
                    try merger.flush_internal(.keep);
                    std.debug.assert(merger.current_span.items.len == 0);

                    try merger.output.append(merger.arena, span);
                },
                .text => |text_content| {
                    std.debug.assert(span.attribs.eql(merger.attribs));

                    const append_text, const skip_head = if (is_only_whitespace(text_content))
                        switch (merger.whitespace) {
                            .one_space => .{ " ", true },
                            .keep_space => .{ text_content, false },
                        }
                    else
                        .{ text_content, false };

                    // check if we already have any text collected, and if not, if we should keep the whitespace
                    if (merger.output.items.len > 0 or merger.current_span.items.len > 0 or !skip_head) {
                        try merger.current_span.appendSlice(merger.arena, append_text);
                    }
                },
            }
            merger.last_end = span.location.offset_one_after();
        }

        pub fn flush(merger: *SpanMerger) !void {
            return merger.flush_internal(.strip);
        }

        fn flush_internal(merger: *SpanMerger, mode: enum { strip, keep }) !void {
            if (merger.current_span.items.len == 0)
                return;

            const raw_string = try merger.current_span.toOwnedSlice(merger.arena);

            const string = switch (mode) {
                .strip => switch (merger.whitespace) {
                    .one_space => std.mem.trimRight(u8, raw_string, whitespace_chars),
                    .keep_space => raw_string,
                },
                .keep => raw_string,
            };

            try merger.output.append(merger.arena, .{
                .attribs = merger.attribs,
                .content = .{ .text = string },
                .location = .{
                    .offset = merger.span_start,
                    .length = merger.last_end - merger.span_start,
                },
            });
            merger.span_start = merger.last_end;
        }
    };

    pub const AttribOverrides = struct {
        lang: ?LanguageTag = null,
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
            => try sema.translate_inline_body(spans, node.body, attribs, .emit_diagnostic),

            .@"\\em" => {
                const props = try sema.get_attributes(node, struct {
                    lang: LanguageTag = .inherit,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .em = true,
                }), .emit_diagnostic);
            },

            .@"\\strike" => {
                const props = try sema.get_attributes(node, struct {
                    lang: LanguageTag = .inherit,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .strike = true,
                }), .emit_diagnostic);
            },

            .@"\\sub" => {
                const props = try sema.get_attributes(node, struct {
                    lang: LanguageTag = .inherit,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .position = .subscript,
                }), .emit_diagnostic);
            },

            .@"\\sup" => {
                const props = try sema.get_attributes(node, struct {
                    lang: LanguageTag = .inherit,
                });

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .position = .superscript,
                }), .emit_diagnostic);
            },

            .@"\\link" => {
                const props = try sema.get_attributes(node, struct {
                    lang: LanguageTag = .inherit,
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

                if (props.ref) |ref| {
                    if (props.uri == null) {
                        const ref_location = get_attribute_location(node, "ref", .value) orelse node.location;
                        try sema.pending_refs.append(sema.arena, .{ .ref = ref, .location = ref_location });
                    }
                }

                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .lang = props.lang,
                    .link = link,
                }), .emit_diagnostic);
            },

            .@"\\mono" => {
                const props = try sema.get_attributes(node, struct {
                    lang: LanguageTag = .inherit,
                    syntax: []const u8 = "",
                });
                try sema.translate_inline_body(spans, node.body, try sema.derive_attribute(node.location, attribs, .{
                    .mono = true,
                    .lang = props.lang,
                    .syntax = props.syntax,
                }), .emit_diagnostic);
            },

            .@"\\date",
            .@"\\time",
            .@"\\datetime",
            => blk: {
                const props = try sema.get_attributes(node, struct {
                    lang: LanguageTag = .inherit,
                    fmt: []const u8 = "",
                });

                // Enforce the body is only plain text.
                const ok = switch (node.body) {
                    .empty => false,
                    .string, .verbatim, .text_span => true, // always ok
                    .list => |list| for (list) |item| {
                        if (item.type != .text) {
                            break false;
                        }
                    } else true,
                };
                if (!ok) {
                    try sema.emit_diagnostic(.invalid_date_time_body, node.location);
                    break :blk;
                }

                const content_spans = try sema.translate_inline(node, .emit_diagnostic, .one_space);

                //  Convert the content_spans into a "rendered string".
                const content_text = (sema.render_spans_to_plaintext(content_spans, .reject_date_time) catch |err| switch (err) {
                    error.DateTimeRenderingUnsupported => unreachable,
                    else => |e| return e,
                }).text;

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
                    .location = node.location,
                });
            },

            .hdoc,
            .h1,
            .h2,
            .h3,
            .title,
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
            => {
                std.log.err("type: {t} location: {}", .{ node.type, node.location });
                @panic("PARSER ERROR: The parser emitted a block node inside an inline context");
            },
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

        const timezone_hint: ?TimeZoneOffset = if (sema.header) |header| header.timezone else null;

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
                    try sema.emit_diagnostic(.missing_timezone, node.location);
                },
            }
            break :blk std.mem.zeroes(DTValue);
        };

        const format: Format = if (format_str.len == 0)
            .default
        else if (std.meta.stringToEnum(Format, format_str)) |format|
            format
        else blk: {
            try sema.emit_diagnostic(.{ .invalid_date_time_fmt = .{ .fmt = format_str } }, get_attribute_location(node, "fmt", .value) orelse node.location);
            break :blk .default;
        };

        return @unionInit(Span.Content, @tagName(body), .{
            .format = format,
            .value = value,
        });
    }

    const TitlePlainText = struct {
        text: []const u8,
        contains_date_time: bool,
    };

    const PlaintextMode = enum {
        reject_date_time,
        iso_date_time,
    };

    fn render_spans_to_plaintext(
        sema: *SemanticAnalyzer,
        source_spans: []const Span,
        mode: PlaintextMode,
    ) error{ OutOfMemory, DateTimeRenderingUnsupported }!TitlePlainText {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(sema.arena);

        var contains_date_time = false;

        for (source_spans) |span| {
            switch (span.content) {
                .text => |str| try output.appendSlice(sema.arena, str),
                .date => |value| switch (mode) {
                    .reject_date_time => return error.DateTimeRenderingUnsupported,
                    .iso_date_time => {
                        contains_date_time = true;
                        var buffer: [64]u8 = undefined;
                        const text = format_iso_date(value.value, &buffer);
                        try output.appendSlice(sema.arena, text);
                    },
                },
                .time => |value| switch (mode) {
                    .reject_date_time => return error.DateTimeRenderingUnsupported,
                    .iso_date_time => {
                        contains_date_time = true;
                        var buffer: [64]u8 = undefined;
                        const text = format_iso_time(value.value, &buffer);
                        try output.appendSlice(sema.arena, text);
                    },
                },
                .datetime => |value| switch (mode) {
                    .reject_date_time => return error.DateTimeRenderingUnsupported,
                    .iso_date_time => {
                        contains_date_time = true;
                        var buffer: [96]u8 = undefined;
                        const text = format_iso_datetime(value.value, &buffer);
                        try output.appendSlice(sema.arena, text);
                    },
                },
            }
        }

        return .{
            .text = try output.toOwnedSlice(sema.arena),
            .contains_date_time = contains_date_time,
        };
    }

    fn format_iso_date(value: Date, buffer: []u8) []const u8 {
        const formatted = std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            @as(u32, @intCast(value.year)),
            value.month,
            value.day,
        }) catch unreachable;

        return if (formatted.len > 0 and formatted[0] == '+')
            formatted[1..]
        else
            formatted;
    }

    fn format_iso_time(value: Time, buffer: []u8) []const u8 {
        var stream = std.io.fixedBufferStream(buffer);
        const writer = stream.writer();

        writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ value.hour, value.minute, value.second }) catch unreachable;
        if (value.microsecond > 0) {
            writer.print(".{d:0>6}", .{value.microsecond}) catch unreachable;
        }
        const minutes = @intFromEnum(value.timezone);
        if (minutes == 0) {
            writer.writeByte('Z') catch unreachable;
        } else {
            const sign: u8 = if (minutes < 0) '-' else '+';
            const abs_minutes: u32 = @intCast(@abs(minutes));
            const hour: u32 = abs_minutes / 60;
            const minute: u32 = abs_minutes % 60;
            writer.print("{c}{d:0>2}:{d:0>2}", .{ sign, hour, minute }) catch unreachable;
        }

        return stream.getWritten();
    }

    fn format_iso_datetime(value: DateTime, buffer: []u8) []const u8 {
        const date_text = format_iso_date(value.date, buffer);
        const sep_index = date_text.len;
        buffer[sep_index] = 'T';

        const time_text = format_iso_time(value.time, buffer[sep_index + 1 ..]);

        return buffer[0 .. sep_index + 1 + time_text.len];
    }

    fn synthesize_title_from_plaintext(sema: *SemanticAnalyzer, text: []const u8, doc_lang: LanguageTag) !Block.Title {
        const spans = try sema.arena.alloc(Span, 1);
        spans[0] = .{
            .content = .{ .text = text },
            .attribs = .{ .lang = .inherit },
            .location = .{ .offset = 0, .length = text.len },
        };

        return .{
            .lang = doc_lang,
            .content = spans,
        };
    }

    fn finalize_title(sema: *SemanticAnalyzer, header: Header, doc_lang: LanguageTag) !?Document.Title {
        const header_title = header.title;
        const block_title = sema.title_block;

        if (header_title == null and block_title == null)
            return null;

        if (block_title) |title_block| {
            const rendered = sema.render_spans_to_plaintext(title_block.content, .iso_date_time) catch |err| switch (err) {
                error.DateTimeRenderingUnsupported => unreachable,
                else => |e| return e,
            };

            if (header_title == null and rendered.contains_date_time) {
                if (sema.title_location) |location| {
                    try sema.emit_diagnostic(.title_inline_date_time_without_header, location);
                }
            }

            return .{
                .full = title_block,
                .simple = rendered.text,
            };
        }

        const simple_text = header_title.?;
        const synthesized_full = try sema.synthesize_title_from_plaintext(simple_text, doc_lang);

        return .{
            .full = synthesized_full,
            .simple = simple_text,
        };
    }

    const EmptyHandling = enum {
        allow_empty,
        emit_diagnostic,
    };
    fn translate_inline_body(sema: *SemanticAnalyzer, spans: *std.ArrayList(Span), body: Parser.Node.Body, attribs: Span.Attributes, empty_handling: EmptyHandling) error{ OutOfMemory, BadAttributes }!void {
        switch (body) {
            .empty => |location| switch (empty_handling) {
                .allow_empty => {},
                .emit_diagnostic => try sema.emit_diagnostic(.empty_inline_body, location),
            },

            .string => |string_body| {
                const text = try sema.unescape_string(string_body);

                try spans.append(sema.arena, .{
                    .content = .{ .text = text },
                    .attribs = attribs,
                    .location = string_body.location,
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

                    text_buffer.appendSliceAssumeCapacity(text);
                }

                const location: Parser.Location = if (verbatim_lines.len > 0) blk: {
                    const head = verbatim_lines[0].location.offset;
                    const tail = verbatim_lines[verbatim_lines.len - 1].location.offset_one_after();
                    break :blk .{
                        .offset = head,
                        .length = tail - head,
                    };
                } else .{ .offset = 0, .length = 0 };

                try spans.append(sema.arena, .{
                    .content = .{ .text = try text_buffer.toOwnedSlice(sema.arena) },
                    .attribs = attribs,
                    .location = location,
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
                    .location = text_span.location,
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

        const unstripped_value = try sema.unescape_string(attrib);

        const value = std.mem.trim(u8, unstripped_value, whitespace_chars);
        if (value.len != unstripped_value.len) {
            try sema.emit_diagnostic(.attribute_leading_trailing_whitespace, attrib.location);
        }

        const timezone_hint = if (sema.header) |header|
            header.timezone
        else
            null;

        return switch (T) {
            []const u8 => value,

            u8 => std.fmt.parseInt(u8, value, 10) catch return error.InvalidValue,
            u32 => std.fmt.parseInt(u32, value, 10) catch return error.InvalidValue,

            Reference => Reference.parse(value) catch return error.InvalidValue,

            Uri => Uri.init(value),

            Version => Version.parse(value) catch return error.InvalidValue,
            Date => Date.parse(value) catch return error.InvalidValue,
            Time => Time.parse(value, timezone_hint) catch return error.InvalidValue,
            DateTime => DateTime.parse(value, timezone_hint) catch return error.InvalidValue,
            LanguageTag => LanguageTag.parse(value) catch return error.InvalidValue,
            TimeZoneOffset => TimeZoneOffset.parse(value) catch return error.InvalidValue,

            else => @compileError("Unsupported attribute type: " ++ @typeName(T)),
        };
    }

    fn validate_references(sema: *SemanticAnalyzer, id_map: *const std.StringArrayHashMapUnmanaged(usize)) !void {
        for (sema.pending_refs.items) |ref_use| {
            if (!id_map.contains(ref_use.ref.text)) {
                try sema.emit_diagnostic(.{ .unknown_id = .{ .ref = ref_use.ref.text } }, ref_use.location);
            }
        }
    }

    fn build_toc(sema: *SemanticAnalyzer, contents: []const Block, block_locations: []const Parser.Location) !Document.TableOfContents {
        std.debug.assert(contents.len == block_locations.len);

        var root_builder = TocBuilder.init(.h1);
        defer root_builder.headings.deinit(sema.arena);
        defer root_builder.children.deinit(sema.arena);

        var stack: std.ArrayList(*TocBuilder) = .empty;
        defer stack.deinit(sema.arena);

        try stack.append(sema.arena, &root_builder);

        for (contents, 0..) |block, block_index| {
            const heading = switch (block) {
                .heading => |value| value,
                else => continue,
            };

            const target_depth = heading_level_index(heading.index);

            while (stack.items.len > target_depth) {
                _ = stack.pop();
            }

            while (stack.items.len < target_depth) {
                const parent = stack.items[stack.items.len - 1];
                try sema.append_toc_entry(&stack, parent, block_index, block_locations, .automatic);
            }

            const parent = stack.items[stack.items.len - 1];
            try sema.append_toc_entry(&stack, parent, block_index, block_locations, .real);
        }

        return sema.materialize_toc(&root_builder);
    }

    fn append_toc_entry(
        sema: *SemanticAnalyzer,
        stack: *std.ArrayList(*TocBuilder),
        parent: *TocBuilder,
        heading_index: usize,
        block_locations: []const Parser.Location,
        kind: enum { automatic, real },
    ) !void {
        if (kind == .automatic) {
            const heading_location = block_locations[heading_index];
            try sema.emit_diagnostic(
                .{ .automatic_heading_insertion = .{ .level = parent.level } },
                heading_location,
            );
        }

        try parent.headings.append(sema.arena, heading_index);

        const child_level = next_heading_level(parent.level);
        if (child_level == parent.level) {
            return;
        }

        const child = try sema.arena.create(TocBuilder);
        child.* = TocBuilder.init(child_level);

        try parent.children.append(sema.arena, child);
        try stack.append(sema.arena, child);
    }

    fn materialize_toc(sema: *SemanticAnalyzer, builder: *TocBuilder) !Document.TableOfContents {
        var node: Document.TableOfContents = .{
            .level = builder.level,
            .headings = try builder.headings.toOwnedSlice(sema.arena),
            .children = try sema.arena.alloc(Document.TableOfContents, builder.children.items.len),
        };

        for (builder.children.items, 0..) |child_builder, index| {
            node.children[index] = try sema.materialize_toc(child_builder);
        }

        return node;
    }

    fn heading_level_index(level: Block.Heading.Level) usize {
        return switch (level) {
            .h1 => 1,
            .h2 => 2,
            .h3 => 3,
        };
    }

    fn next_heading_level(level: Block.Heading.Level) Block.Heading.Level {
        return switch (level) {
            .h1 => .h2,
            .h2 => .h3,
            .h3 => .h3,
        };
    }

    /// Computes the next index number for a heading of the given level:
    fn compute_next_heading(sema: *SemanticAnalyzer, node: Parser.Node, level: Block.Heading.Level) !Block.Heading.Index {
        const index = @intFromEnum(level);

        sema.heading_counters[index] += 1;

        if (index > sema.current_heading_level + 1) {
            // TODO: Emit fatal diagnostic for invalid heading sequencing: "h3 after h1 is not legal"
        }
        sema.current_heading_level = index;

        // Reset all higher levels to 1:
        for (sema.heading_counters[index + 1 ..]) |*val| {
            val.* = 0;
        }
        _ = node;

        return switch (level) {
            .h1 => .{ .h1 = sema.heading_counters[0..1].* },
            .h2 => .{ .h2 = sema.heading_counters[0..2].* },
            .h3 => .{ .h3 = sema.heading_counters[0..3].* },
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

                            const min_len = "\\u{}".len;
                            const max_len = "\\u{123456}".len;

                            if (escape_part.len == min_len) {
                                // Empty escape: \u{}
                                std.debug.assert(std.mem.eql(u8, escape_part, "\\u{}"));
                                try sema.emit_diagnostic(.invalid_unicode_string_escape, location);
                                break :blk "???";
                            }

                            if (escape_part.len > max_len) {
                                // Escape sequence is more than 6 chars long
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
                            // Unknown escape sequence, emit escaped char verbatim. Use the full UTF-8 codepoint
                            // inside the error message, so we can tell that "\😢" is not a valid escape sequence
                            // instead of saying that "\{F0}" is not a valid escape sequence

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
                    if (parser.try_accept_char(')'))
                        break;
                    const attr_name = try parser.accept_identifier();
                    _ = try parser.accept_char('=');
                    const attr_value = try parser.accept_string();

                    try attributes.append(parser.arena, .{
                        .name = attr_name,
                        .value = attr_value,
                    });

                    if (!parser.try_accept_char(',')) {
                        try parser.accept_char(')');
                        break;
                    }
                }
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
            // If necessary, emit a whitespace span:
            {
                const before = parser.offset;
                parser.skip_whitespace();
                const after = parser.offset;
                std.debug.assert(after >= before);
                if (after > before) {
                    // We've skipped over whitespace, so we emit a "whitespace" node here:
                    const whitespace = parser.slice(before, after);
                    try children.append(parser.arena, .{
                        .location = whitespace.location,
                        .type = .text,
                        .body = .{
                            .text_span = whitespace,
                        },
                    });
                }
            }

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
                '\n' => return error.UnterminatedStringLiteral,

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
            'a'...'z',
            'A'...'Z',
            '0'...'9',
            '_',
            '-',
            '\\',
            => true,
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

        pub fn offset_one_after(loc: Location) usize {
            return loc.offset + loc.length;
        }
    };

    pub const NodeType = enum {
        hdoc,
        h1,
        h2,
        h3,
        title,
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
                .title,
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

                .title,
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
    pub const NodeBodyError = struct { type: Parser.NodeType };
    pub const MissingHdocHeader = struct {};
    pub const DuplicateHdocHeader = struct {};
    pub const InvalidBlockError = struct { name: []const u8 };
    pub const InlineUsageError = struct { attribute: InlineAttribute };
    pub const InlineCombinationError = struct { first: InlineAttribute, second: InlineAttribute };
    pub const DateTimeFormatError = struct { fmt: []const u8 };
    pub const InvalidStringEscape = struct { codepoint: u21 };
    pub const ForbiddenControlCharacter = struct { codepoint: u21 };
    pub const TableShapeError = struct { actual: usize, expected: usize };
    pub const ReferenceError = struct { ref: []const u8 };
    pub const AutomaticHeading = struct { level: Block.Heading.Level };

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
        misplaced_hdoc_header,
        non_empty_hdoc_body,
        missing_attribute: NodeAttributeError,
        invalid_attribute: NodeAttributeError,
        empty_attribute: NodeAttributeError,
        unknown_block_type: InvalidBlockError,
        invalid_block_type: InvalidBlockError,
        block_list_required: NodeBodyError,
        invalid_inline_combination: InlineCombinationError,
        link_not_nestable,
        invalid_link,
        invalid_date_time,
        invalid_date_time_body,
        invalid_date_time_fmt: DateTimeFormatError,
        missing_timezone,
        invalid_unicode_string_escape,
        invalid_string_escape: InvalidStringEscape,
        illegal_character: ForbiddenControlCharacter,
        bare_carriage_return,
        illegal_child_item,
        list_body_required,
        illegal_id_attribute,
        misplaced_title_block,
        duplicate_title_block,
        column_count_mismatch: TableShapeError,
        duplicate_id: ReferenceError,
        unknown_id: ReferenceError,

        // warnings:
        document_starts_with_bom,
        missing_document_language,
        unknown_attribute: NodeAttributeError,
        duplicate_attribute: DuplicateAttribute,
        empty_verbatim_block,
        verbatim_missing_trailing_newline,
        verbatim_missing_space,
        trailing_whitespace,
        empty_inline_body,
        redundant_inline: InlineUsageError,
        attribute_leading_trailing_whitespace,
        tab_character,
        automatic_heading_insertion: AutomaticHeading,
        title_inline_date_time_without_header,

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
                .misplaced_hdoc_header,
                .non_empty_hdoc_body,
                .invalid_attribute,
                .missing_attribute,
                .empty_attribute,
                .unknown_block_type,
                .invalid_block_type,
                .block_list_required,
                .invalid_inline_combination,
                .link_not_nestable,
                .invalid_link,
                .invalid_date_time,
                .invalid_date_time_fmt,
                .missing_timezone,
                .invalid_string_escape,
                .illegal_character,
                .bare_carriage_return,
                .invalid_unicode_string_escape,
                .illegal_child_item,
                .list_body_required,
                .illegal_id_attribute,
                .invalid_date_time_body,
                .misplaced_title_block,
                .duplicate_title_block,
                .column_count_mismatch,
                .duplicate_id,
                .unknown_id,
                => .@"error",

                .missing_document_language,
                .unknown_attribute,
                .duplicate_attribute,
                .empty_verbatim_block,
                .verbatim_missing_trailing_newline,
                .verbatim_missing_space,
                .trailing_whitespace,
                .empty_inline_body,
                .redundant_inline,
                .attribute_leading_trailing_whitespace,
                .tab_character,
                .document_starts_with_bom,
                .automatic_heading_insertion,
                .title_inline_date_time_without_header,
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
                .misplaced_hdoc_header => try w.writeAll("The 'hdoc' header must be the first node in the document."),
                .non_empty_hdoc_body => try w.writeAll("The 'hdoc' header must have an empty body (';')."),
                .duplicate_attribute => |ctx| try w.print("Duplicate attribute '{s}' will overwrite the earlier value.", .{ctx.name}),
                .empty_verbatim_block => try w.writeAll("Verbatim block has no lines."),
                .verbatim_missing_trailing_newline => try w.writeAll("Verbatim line should end with a newline."),
                .verbatim_missing_space => try w.writeAll("Expected a space after '|' in verbatim line."),
                .trailing_whitespace => try w.writeAll("Trailing whitespace at end of line."),

                .missing_attribute => |ctx| try w.print("Missing required attribute '{s}' for node type '{t}'.", .{ ctx.name, ctx.type }),
                .invalid_attribute => |ctx| try w.print("Invalid value for attribute '{s}' for node type '{t}'.", .{ ctx.name, ctx.type }),
                .empty_attribute => |ctx| try w.print("Attribute '{s}' for node type '{t}' must be non-empty.", .{ ctx.name, ctx.type }),
                .unknown_attribute => |ctx| try w.print("Unknown attribute '{s}' for node type '{t}'.", .{ ctx.name, ctx.type }),
                .unknown_block_type => |ctx| try w.print("Unknown block type '{s}'.", .{ctx.name}),
                .invalid_block_type => |ctx| try w.print("Invalid block type '{s}' in this context.", .{ctx.name}),
                .block_list_required => |ctx| try w.print("Node type '{t}' requires a block list body.", .{ctx.type}),

                .empty_inline_body => try w.writeAll("Inline body is empty."),

                .redundant_inline => |ctx| try w.print("The inline \\{t} has no effect.", .{ctx.attribute}),
                .invalid_inline_combination => |ctx| try w.print("Cannot combine \\{t} with \\{t}.", .{ ctx.first, ctx.second }),
                .link_not_nestable => try w.writeAll("Links are not nestable"),
                .invalid_link => try w.writeAll("\\link requires either ref=\"…\" or uri=\"…\" attribute."),

                .attribute_leading_trailing_whitespace => try w.writeAll("Attribute value has invalid leading or trailing whitespace."),

                .invalid_date_time => try w.writeAll("Invalid date/time value."),

                .missing_timezone => try w.writeAll("Missing timezone offset; add a 'tz' header attribute or include a timezone in the value."),

                .invalid_date_time_fmt => |ctx| try w.print("Invalid 'fmt' value '{s}' for date/time.", .{ctx.fmt}),

                .invalid_string_escape => |ctx| if (ctx.codepoint > 0x20 and ctx.codepoint <= 0x7F)
                    try w.print("\\{u} is not a valid escape sequence.", .{ctx.codepoint})
                else
                    try w.print("U+{X:0>2} is not a valid escape sequence.", .{ctx.codepoint}),

                .invalid_unicode_string_escape => try w.writeAll("Invalid unicode escape sequence"),

                .illegal_character => |ctx| try w.print("Forbidden control character U+{X:0>4}.", .{ctx.codepoint}),
                .bare_carriage_return => try w.writeAll("Bare carriage return (CR) is not allowed; use LF or CRLF."),

                .list_body_required => try w.writeAll("Node requires list body."),
                .illegal_child_item => try w.writeAll("Node not allowed here."),

                .illegal_id_attribute => try w.writeAll("Attribute 'id' not allowed here."),
                .misplaced_title_block => try w.writeAll("Document title must be the second node (directly after 'hdoc')."),
                .duplicate_title_block => try w.writeAll("Only one 'title' block is allowed."),

                .invalid_date_time_body => try w.writeAll("\\date, \\time and \\datetime do not allow any inlines inside their body."),

                .column_count_mismatch => |ctx| try w.print("Expected {} columns, but found {}", .{ ctx.expected, ctx.actual }),

                .duplicate_id => |ctx| try w.print("The id \"{s}\" is already taken by another node.", .{ctx.ref}),
                .unknown_id => |ctx| try w.print("The referenced id \"{s}\" does not exist.", .{ctx.ref}),

                .missing_document_language => try w.writeAll("Document language is missing; set lang on the hdoc header."),
                .tab_character => try w.writeAll("Tab character is not allowed; use spaces instead."),

                .automatic_heading_insertion => |ctx| try w.print("Inserted automatic {t} to fill heading level gap.", .{ctx.level}),
                .title_inline_date_time_without_header => try w.writeAll("Title block contains \\date/\\time/\\datetime but hdoc(title=\"...\") is missing; metadata title cannot be derived reliably."),
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
