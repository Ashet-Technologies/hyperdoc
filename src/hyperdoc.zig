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
    paragraph: Paragraph,
    ordered_list: []Item,
    unordered_list: []Item,
    quote: Paragraph,
    preformatted: CodeBlock,
    image: Image,
    heading: Heading,
    table_of_contents,
};

/// A paragraph is a sequence of spans.
pub const Paragraph = struct {
    contents: []Span,
};

/// A list item is a sequence of blocks
pub const Item = struct {
    contents: []Block,
};

/// A code block is a paragraph with a programming language attachment
pub const CodeBlock = struct {
    contents: []Span,
    language: []const u8, // empty=none
};

/// An image is a block that will display non-text content.
pub const Image = struct {
    path: []const u8,
};

/// A heading is a block that will be rendered in a bigger/different font
/// and introduces a new section of the document.
/// It has an anchor that can be referenced.
pub const Heading = struct {
    level: Level,
    title: []const u8,
    anchor: []const u8,

    pub const Level = enum(u2) {
        document = 0,
        chapter = 1,
        section = 2,
    };
};

/// Spans are the building blocks of paragraphs. Each span is
/// defining a sequence of text with a certain formatting.
pub const Span = union(enum) {
    text: []const u8,
    emphasis: []const u8,
    monospace: []const u8,
    link: Link,
};

/// Links are spans that can refer to other documents or elements.
pub const Link = struct {
    href: []const u8,
    text: []const u8,
};

pub const ErrorLocation = parser_toolkit.Location;

/// Parses a HyperDoc document.
pub fn parse(allocator: std.mem.Allocator, plain_text: []const u8, error_location: ?*ErrorLocation) !Document {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var tokenizer = Tokenizer.init(plain_text, null);

    var parser = Parser{
        .allocator = arena.allocator(),
        .core = ParserCore.init(&tokenizer),
    };

    defer if (error_location) |err| {
        err.* = tokenizer.current_location;
    };

    const root_id = parser.acceptIdentifier() catch return error.InvalidFormat;
    if (root_id != .hdoc)
        return error.InvalidFormat;
    const version_number = parser.accept(.text) catch return error.InvalidFormat;
    if (!std.mem.eql(u8, version_number.text, "\"1.0\""))
        return error.InvalidVersion;

    const root_elements = try parser.acceptBlockSequence(.eof);

    return Document{
        .arena = arena,
        .contents = root_elements,
    };
}

const Parser = struct {
    allocator: std.mem.Allocator,
    core: ParserCore,

    fn save(parser: *Parser) Tokenizer.State {
        return parser.core.saveState();
    }

    fn restore(parser: *Parser, state: Tokenizer.State) void {
        return parser.core.restoreState(state);
    }

    fn accept(parser: *Parser, token_type: TokenType) !Token {
        var state = parser.save();
        errdefer parser.restore(state);

        var token = (try parser.core.nextToken()) orelse return error.EndOfFile;
        if (token.type != token_type)
            return error.UnexpectedToken;
        return token;
    }

    fn consume(parser: *Parser, token_type: TokenType) !void {
        _ = try parser.accept(token_type);
    }

    const Identifier = enum {
        // management
        hdoc,

        // blocks
        h1,
        h2,
        h3,
        toc,
        p,
        enumerate,
        itemize,
        quote,
        pre,
        image,

        // spans
        span,
        link,
        emph,
        mono,

        // list of blocks
        item,
    };
    fn acceptIdentifier(parser: *Parser) !Identifier {
        var tok = try parser.accept(.identifier);
        return std.meta.stringToEnum(Identifier, tok.text) orelse return error.InvalidIdentifier;
    }

    fn acceptText(parser: *Parser) ![]const u8 {
        const text_tok = try parser.accept(.text);

        const text = text_tok.text;

        std.debug.assert(text.len >= 2);
        std.debug.assert(text[0] == text[text.len - 1]);

        const string_body = text[1 .. text.len - 1];

        var temp_string = std.ArrayList(u8).init(parser.allocator);
        defer temp_string.deinit();

        try temp_string.ensureTotalCapacity(string_body.len);

        {
            var i: usize = 0;
            while (i < string_body.len) {
                const c = string_body[i];
                if (c != '\\') {
                    try temp_string.append(c);
                    i += 1;
                    continue;
                }
                i += 1;
                if (i >= string_body.len)
                    return error.InvalidEscapeSequence;
                const selector = string_body[i];
                i += 1;
                switch (selector) {
                    'n' => try temp_string.append('\n'),
                    'r' => try temp_string.append('\r'),
                    'e' => try temp_string.append('\x1B'),

                    // TODO: Implement the following cases:
                    // '\xFF'
                    // '\u{ABCD}'

                    else => {
                        try temp_string.append(selector);
                    },
                }
            }
        }

        return try temp_string.toOwnedSlice();
    }

    const BlockSequenceTerminator = enum { @"}", eof };

    fn acceptBlockSequence(parser: *Parser, terminator: BlockSequenceTerminator) ![]Block {
        var seq = std.ArrayList(Block).init(parser.allocator);
        defer seq.deinit();

        accept_loop: while (true) {
            const id = switch (terminator) {
                .@"}" => if (parser.acceptIdentifier()) |id|
                    id
                else |_| if (parser.accept(.@"}")) |_|
                    break :accept_loop
                else |_|
                    return error.UnexpectedToken,
                .eof => if (parser.acceptIdentifier()) |id|
                    id
                else |err| switch (err) {
                    error.EndOfFile => break :accept_loop,
                    else => |e| return e,
                },
            };

            switch (id) {
                .toc => {
                    try parser.consume(.@"{");
                    try parser.consume(.@"}");
                    try seq.append(.table_of_contents);
                },

                .h1, .h2, .h3 => {
                    const anchor = try parser.acceptText();
                    const title = try parser.acceptText();

                    try seq.append(Block{
                        .heading = .{
                            .level = switch (id) {
                                .h1 => .document,
                                .h2 => .chapter,
                                .h3 => .section,
                                else => unreachable,
                            },
                            .title = title,
                            .anchor = anchor,
                        },
                    });
                },

                .p, .quote => {
                    try parser.consume(.@"{");
                    const items = try parser.acceptSpanSequence();

                    try seq.append(if (id == .p)
                        Block{ .paragraph = .{ .contents = items } }
                    else
                        Block{ .quote = .{ .contents = items } });
                },

                .pre => {
                    const language = try parser.acceptText();
                    try parser.consume(.@"{");
                    const items = try parser.acceptSpanSequence();

                    try seq.append(Block{
                        .preformatted = CodeBlock{
                            .language = language,
                            .contents = items,
                        },
                    });
                },

                .enumerate, .itemize => {
                    try parser.consume(.@"{");

                    var list = std.ArrayList(Item).init(parser.allocator);
                    defer list.deinit();

                    while (true) {
                        if (parser.consume(.@"}")) |_| {
                            break;
                        } else |_| {}

                        const ident = try parser.acceptIdentifier();
                        if (ident != .item) {
                            return error.UnexpectedToken;
                        }

                        try parser.consume(.@"{");

                        const sequence = try parser.acceptBlockSequence(.@"}");

                        try list.append(Item{
                            .contents = sequence,
                        });
                    }

                    try seq.append(if (id == .enumerate)
                        Block{ .ordered_list = try list.toOwnedSlice() }
                    else
                        Block{ .unordered_list = try list.toOwnedSlice() });
                },

                .image => {
                    const file_path = try parser.acceptText();
                    try seq.append(Block{ .image = .{
                        .path = file_path,
                    } });
                },

                .item, .hdoc, .link, .emph, .mono, .span => return error.InvalidTopLevelItem,
            }
        }

        return try seq.toOwnedSlice();
    }

    fn acceptSpanSequence(parser: *Parser) ![]Span {
        var seq = std.ArrayList(Span).init(parser.allocator);
        defer seq.deinit();

        accept_loop: while (true) {
            const id = if (parser.acceptIdentifier()) |id|
                id
            else |_| if (parser.accept(.@"}")) |_|
                break :accept_loop
            else |_|
                return error.UnexpectedToken;

            switch (id) {
                .item, .toc, .h1, .h2, .h3, .p, .quote, .pre, .enumerate, .itemize, .image, .hdoc => return error.InvalidSpan,

                .span => {
                    const text = try parser.acceptText();
                    try seq.append(Span{ .text = text });
                },
                .emph => {
                    const text = try parser.acceptText();
                    try seq.append(Span{ .emphasis = text });
                },
                .mono => {
                    const text = try parser.acceptText();
                    try seq.append(Span{ .monospace = text });
                },

                .link => {
                    const href = try parser.acceptText();
                    const text = try parser.acceptText();
                    try seq.append(Span{ .link = .{
                        .href = href,
                        .text = text,
                    } });
                },
            }
        }

        return try seq.toOwnedSlice();
    }
};

const ParserCore = parser_toolkit.ParserCore(Tokenizer, .{ .whitespace, .comment });

const Pattern = parser_toolkit.Pattern(TokenType);

const Token = Tokenizer.Token;

const Tokenizer = parser_toolkit.Tokenizer(TokenType, &[_]Pattern{
    Pattern.create(.comment, parser_toolkit.matchers.withPrefix("#", parser_toolkit.matchers.takeNoneOf("\n"))),

    Pattern.create(.@"{", parser_toolkit.matchers.literal("{")),
    Pattern.create(.@"}", parser_toolkit.matchers.literal("}")),
    Pattern.create(.text, matchStringLiteral('\"')),

    Pattern.create(.identifier, parser_toolkit.matchers.identifier),

    Pattern.create(.whitespace, parser_toolkit.matchers.whitespace),
});

fn matchStringLiteral(comptime boundary: u8) parser_toolkit.Matcher {
    const T = struct {
        fn match(str: []const u8) ?usize {
            if (str.len < 2)
                return null;

            if (str[0] != boundary)
                return null;

            var i: usize = 1;
            while (i < str.len) {
                if (str[i] == boundary)
                    return i + 1;

                if (str[i] == '\\') {
                    i += 2; // skip over the escape and the escaped char
                } else {
                    i += 1; // just go to the next char
                }
            }

            return null;
        }
    };

    return T.match;
}

const TokenType = enum {
    comment,
    whitespace,
    identifier,
    text,
    @"{",
    @"}",
};
