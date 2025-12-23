const std = @import("std");
const parser_toolkit = @import("parser-toolkit");

/// A HyperDoc document. Contains both memory and
/// tree structure of the document.
pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    contents: []Block,

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
    header: Header,

    pub const Header = struct {
        title: ?[]const u8,
        author: ?[]const u8,
        date: ?[]const u8,
    };
};

/// Parses a HyperDoc document.
pub fn parse(
    allocator: std.mem.Allocator,
    /// The source code to be parsed
    plain_text: []const u8,
    /// An optional diagnostics element that receives diagnostic messages like errors and warnings.
    /// If present, will be filled out by the parser.
    diagnostics: ?*Diagnostics,
) error{ OutOfMemory, SyntaxError }!Document {
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
    };

    var blocks: std.ArrayList(Block) = .empty;

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

        const block = sema.translate_toplevel_node(node) catch |err| switch (err) {
            error.OutOfMemory => |e| return @as(error{OutOfMemory}!Document, e),

            error.InvalidNodeType => continue,
        };

        try blocks.append(arena.allocator(), block);
    }

    return .{
        .arena = arena,
        .contents = try blocks.toOwnedSlice(arena.allocator()),
    };
}

pub const SemanticAnalyzer = struct {
    arena: std.mem.Allocator,
    diagnostics: ?*Diagnostics,

    fn translate_toplevel_node(sema: *SemanticAnalyzer, node: Parser.Node) error{ OutOfMemory, InvalidNodeType }!Block {
        _ = sema;
        switch (node.type) {
            else => {
                return error.InvalidNodeType;
            },
        }
    }
};

pub const Parser = struct {
    code: []const u8,
    offset: usize = 0,

    arena: std.mem.Allocator,
    diagnostics: ?*Diagnostics,

    pub const ScopeType = enum { top_level, nested };

    pub fn accept_node(parser: *Parser, comptime scope_type: ScopeType) !Node {
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
                        // TODO: Emit diagnostic
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
                // TODO: Emit diagnostic about verbatim block with no lines
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
                // TODO: Emit diagnostic
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

        while (!parser.at_end()) {
            const c = parser.code[parser.offset];
            if (c == '\n') {
                break;
            }

            // we don't consume the LF character, as each verbatim line should be prefixed with exactly a single LF character
            parser.offset += 1;
        }
        if (parser.at_end()) {
            // TODO: Emit diagnostic about verbatim lines should have an empty line feed at the end of the file.
        }

        const token = parser.slice(head, parser.offset);
        std.debug.assert(std.mem.startsWith(u8, token.text, "|"));
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

        if (parser.at_end())
            return error.UnexpectedEndOfFile;

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

        if (parser.at_end())
            return null;

        if (parser.code[parser.offset] != '"')
            return null;

        return try parser.accept_string();
    }

    pub fn accept_string(parser: *Parser) error{ OutOfMemory, UnexpectedEndOfFile, UnexpectedCharacter, UnterminatedStringLiteral }!Token {
        parser.skip_whitespace();

        if (parser.at_end())
            return error.UnexpectedEndOfFile;

        const start = parser.offset;
        if (parser.code[start] != '"')
            return error.UnexpectedCharacter;

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

        return error.UnterminatedStringLiteral;
    }

    pub fn accept_identifier(parser: *Parser) error{ UnexpectedEndOfFile, InvalidCharacter }!Token {
        parser.skip_whitespace();

        if (parser.at_end())
            return error.UnexpectedEndOfFile;

        const start = parser.offset;
        const first = parser.code[start];
        if (!is_ident_char(first))
            return error.InvalidCharacter;

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

        if (parser.at_end())
            return error.UnexpectedEndOfFile;

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

    /// An diagnostic code encoded as a 16 bit integer.
    /// The upper 4 bit encode the severity of the code, the lower 12 bit the number.
    pub const Code = enum(u16) {
        // bitmasks:
        const ERROR = 0x1000;
        const WARNING = 0x2000;

        // TODO: Add other diagnostic codes

        // errors:
        invalid_character = ERROR | 1,

        // warnings:
        missing_space_in_literal = WARNING | 1,

        pub fn get_severity(code: Code) Severity {
            const num = @intFromEnum(code);
            return switch (num & 0xF000) {
                ERROR => .@"error",
                WARNING => .warning,
                else => @panic("invalid error code!"),
            };
        }
    };

    code: Code,
    location: Location,
    message: []const u8,
};

/// A collection of diagnostic messages.
pub const Diagnostics = struct {
    arena: std.heap.ArenaAllocator,
    items: std.ArrayList(Diagnostic) = .empty,

    pub fn init(allocator: std.mem.Allocator) Diagnostic {
        return .{ .arena = .init(allocator) };
    }

    pub fn deinit(diag: *Diagnostics) void {
        diag.arena.deinit();
        diag.* = undefined;
    }

    pub fn add(diag: *Diagnostics, code: Diagnostic.Code, location: Diagnostic.Location, comptime fmt: []const u8, args: anytype) !void {
        const allocator = diag.arena.allocator();

        const msg = try std.fmt.allocPrint(allocator, fmt, args);
        errdefer allocator.free(msg);

        try diag.items.append(allocator, .{
            .location = location,
            .code = code,
            .message = msg,
        });
    }
};
