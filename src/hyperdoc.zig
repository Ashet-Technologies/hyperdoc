const std = @import("std");
const parser_toolkit = @import("parser-toolkit");

/// A HyperDoc document. Contains both memory and
/// tree structure of the document.
pub const Document = struct {
    arena: std.heap.ArenaAllocator,

    version: Version,

    // document contents:
    contents: []Block,
    ids: []?[]const u8,

    // header information
    lang: ?[]const u8,
    title: ?[]const u8,
    author: ?[]const u8,
    date: ?DateTime,

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

pub const SpanContent = union(enum) {
    text: []const u8,
    date: FormattedDateTime(Date),
    time: FormattedDateTime(Time),
    datetime: FormattedDateTime(DateTime),
};

pub fn FormattedDateTime(comptime DT: type) type {
    return struct {
        value: DT,
        format: DT.Format = .default,
    };
}

pub const Span = struct {
    content: SpanContent,
    lang: ?[]const u8 = null,
    em: bool = false,
    mono: bool = false,
    strike: bool = false,
    sub: bool = false,
    sup: bool = false,
    link: Link = .none,
    syntax: ?[]const u8 = null,
};

pub const Link = union(enum) {
    none,
    ref: []const u8,
    uri: []const u8,
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

    pub fn parse(text: []const u8) !DateTime {
        const split_index = std.mem.indexOfScalar(u8, text, 'T') orelse return error.InvalidValue;

        const head = text[0..split_index];
        const tail = text[split_index + 1 ..];

        return .{
            .date = try Date.parse(head),
            .time = try Time.parse(tail),
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
        _ = text;
        @panic("TODO: Implement this");
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

    pub fn parse(text: []const u8) !Time {
        _ = text;
        @panic("TODO: Implement this");
    }
};

/// Parses a HyperDoc document.
pub fn parse(
    allocator: std.mem.Allocator,
    /// The source code to be parsed
    plain_text: []const u8,
    /// An optional diagnostics element that receives diagnostic messages like errors and warnings.
    /// If present, will be filled out by the parser.
    diagnostics: ?*Diagnostics,
) error{ OutOfMemory, SyntaxError, MalformedDocument }!Document {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var parser: Parser = .{
        .code = plain_text,
        .arena = arena.allocator(),
        .diagnostics = diagnostics,
    };

    var sema: SemanticAnalyzer = .{
        .arena = arena.allocator(),
        .diagnostics = diagnostics,
        .code = plain_text,
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
    };
}

pub const SemanticAnalyzer = struct {
    const Header = struct {
        version: Version,
        lang: ?[]const u8,
        title: ?[]const u8,
        author: ?[]const u8,
        date: ?DateTime,
    };

    arena: std.mem.Allocator,
    diagnostics: ?*Diagnostics,
    code: []const u8,

    header: ?Header = null,
    blocks: std.ArrayList(Block) = .empty,
    ids: std.ArrayList(?[]const u8) = .empty,

    fn append_node(sema: *SemanticAnalyzer, node: Parser.Node) error{OutOfMemory}!void {
        switch (node.type) {
            .hdoc => {
                if (sema.header != null) {
                    try sema.emit_diagnostic(.duplicate_hdoc_header, node.location.offset);
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
                        try sema.emit_diagnostic(.missing_hdoc_header, node.location.offset);
                    }
                }

                const block, const id = sema.translate_block_node(node) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.InvalidNodeType, error.BadAttributes => {
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
        });

        return .{
            .version = attrs.version,
            .lang = attrs.lang,
            .title = attrs.title,
            .author = attrs.author,
            .date = attrs.date,
        };
    }

    fn translate_block_node(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, InvalidNodeType, BadAttributes }!struct { Block, ?[]const u8 } {
        std.debug.assert(node.type != .hdoc);

        _ = sema;

        return error.InvalidNodeType;
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
        for (node.attributes.keys(), node.attributes.values()) |key, attrib| {
            const fld = std.meta.stringToEnum(Fields, key) orelse {
                try sema.emit_diagnostic(.{ .unknown_attribute = .{ .type = node.type, .name = key } }, node.location.offset);
                continue;
            };
            if (found.contains(fld)) {
                try sema.emit_diagnostic(.{ .duplicate_attribute = .{ .name = key } }, node.location.offset);
            }
            found.insert(fld);

            switch (fld) {
                inline else => |tag| @field(attrs, @tagName(tag)) = sema.cast_value(attrib, @FieldType(Attrs, @tagName(tag))) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,

                    else => {
                        any_invalid = true;

                        try sema.emit_diagnostic(.{ .invalid_attribute = .{ .type = node.type, .name = key } }, node.location.offset);

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
                    try sema.emit_diagnostic(.{ .missing_attribute = .{ .type = node.type, .name = @tagName(req_field) } }, node.location.offset);
                    any_missing = true;
                }
            }
        }
        if (any_missing or any_invalid)
            return error.BadAttributes;

        return attrs;
    }

    fn cast_value(sema: *SemanticAnalyzer, attrib: Parser.Attribute, comptime T: type) error{ OutOfMemory, InvalidValue }!T {
        if (@typeInfo(T) == .optional) {
            return try sema.cast_value(attrib, @typeInfo(T).optional.child);
        }

        return switch (T) {
            []const u8 =>  attrib.value,

            Version => Version.parse(attrib.value) catch return error.InvalidValue,
            DateTime => DateTime.parse(attrib.value) catch return error.InvalidValue,
            Date => Date.parse(attrib.value) catch return error.InvalidValue,
            Time => Time.parse(attrib.value) catch return error.InvalidValue,

            else => @compileError("Unsupported attribute type: " ++ @typeName(T)),
        };
    }

    fn emit_diagnostic(sema: *SemanticAnalyzer, code: Diagnostic.Code, offset: usize) !void {
        if (sema.diagnostics) |diag| {
            try diag.add(code, sema.make_location(offset));
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

        var attributes: std.StringArrayHashMapUnmanaged(Attribute) = .empty;
        errdefer attributes.deinit(parser.arena);

        if (parser.try_accept_char('(')) {
            if (!parser.try_accept_char(')')) {
                // We 're not at the end of the attribute list,
                // so we know that the next token must be the attribute name.

                while (true) {
                    const start = parser.offset;
                    const attr_name = try parser.accept_identifier();
                    _ = try parser.accept_char('=');
                    const attr_value = try parser.accept_string();
                    const attr_location = parser.location(start, parser.offset);

                    const gop_entry = try attributes.getOrPut(parser.arena, attr_name.text);
                    if (gop_entry.found_existing) {
                        emitDiagnostic(parser, .{ .duplicate_attribute = .{ .name = attr_name.text } }, parser.make_diagnostic_location(attr_location.offset));
                    }
                    gop_entry.value_ptr.* = .{
                        .location = attr_location,
                        .value = try parser.unescape_string(attr_value),
                    };

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
                .location = parser.location(type_ident.position.offset, null),
                .type = node_type,
                .attributes = attributes,
                .body = .empty,
            };
        }

        if (parser.try_accept_char(':')) {
            // block has verbatim content

            var lines: std.ArrayList(Token) = .empty;

            while (try parser.try_accept_verbatim_line()) |line| {
                try lines.append(parser.arena, line);
            }

            if (lines.items.len == 0) {
                emitDiagnostic(parser, .empty_verbatim_block, parser.make_diagnostic_location(type_ident.position.offset));
            }

            return .{
                .location = parser.location(type_ident.position.offset, null),
                .type = node_type,
                .attributes = attributes,
                .body = .{ .verbatim = try lines.toOwnedSlice(parser.arena) },
            };
        }

        if (try parser.try_accept_string()) |string_body| {
            // block has string content

            return .{
                .location = parser.location(type_ident.position.offset, null),
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
            .location = parser.location(type_ident.position.offset, null),
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
                },

                '}' => {
                    parser.offset += 1;

                    if (nesting == 0)
                        break;

                    nesting -= 1;
                },

                '\\' => backslash: {
                    if (parser.offset < parser.code.len - 1) {
                        const next_char = parser.code[parser.offset + 1];
                        switch (next_char) {
                            '{', '}', '\\' => {
                                // Escaped brace
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
                        .location = word.position,
                        .type = .text,
                        .attributes = .empty,
                        .body = .empty,
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

    /// Accepts a string literal, including the surrounding quotes.
    pub fn unescape_string(parser: *Parser, token: Token) error{OutOfMemory}![]const u8 {
        std.debug.assert(token.text.len >= 2);
        std.debug.assert(token.text[0] == '"' and token.text[token.text.len - 1] == '"');

        _ = parser;
        // TODO: Implement unescaping logic here.

        // For now, we just return the raw text.
        return token.text[1 .. token.text.len - 1];
    }

    pub fn location(parser: *Parser, start: usize, end: ?usize) Location {
        return .{ .offset = start, .length = (end orelse parser.offset) - start };
    }

    pub fn slice(parser: *Parser, start: usize, end: usize) Token {
        return .{
            .text = parser.code[start..end],
            .position = .{ .offset = start, .length = end - start },
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
        position: Location,
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
                .unknown_block,
                => false,
            };
        }
    };

    pub const Node = struct {
        location: Location,
        type: NodeType,
        attributes: std.StringArrayHashMapUnmanaged(Attribute),

        body: Body,

        pub const Body = union(enum) {
            empty,
            string: Token,
            verbatim: []Token,
            list: []Node,
        };
    };

    pub const Attribute = struct {
        location: Location,
        value: []const u8,
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

        // warnings:
        unknown_attribute: NodeAttributeError,
        duplicate_attribute: DuplicateAttribute,
        empty_verbatim_block,
        verbatim_missing_trailing_newline,
        verbatim_missing_space,
        trailing_whitespace,

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
                => .@"error",

                .unknown_attribute,
                .duplicate_attribute,
                .empty_verbatim_block,
                .verbatim_missing_trailing_newline,
                .verbatim_missing_space,
                .trailing_whitespace,
                => .warning,
            };
        }

        pub fn format(code: Code, w: anytype) !void {
            switch (code) {
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
            @embedFile("test/parser/stress.hdoc"),
        },
    });
}
