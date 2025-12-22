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
    placeholder: void,
};

/// A token emitted by the HyperDoc tokenizer.
pub const Token = struct {
    pub const Tag = enum {
        eof,
        word,
        string_literal,
        unterminated_string_literal,
        literal_line,
        newline,
        @"{",
        @"}",
        @"(",
        @")",
        @",",
        @"=",
        @":",
        @"\\",
        invalid_character,
    };

    tag: Tag,
    offset: usize,
    len: usize,

    /// Returns the slice of the original input covered by this token.
    pub fn slice(token: Token, input: []const u8) []const u8 {
        return input[token.offset .. token.offset + token.len];
    }
};

/// Tokenizes HyperDoc source text incrementally.
pub const Tokenizer = struct {
    input: []const u8,
    index: usize = 0,
    line_start: bool = true,
    finished: bool = false,

    /// Creates a tokenizer for the provided input.
    pub fn init(input: []const u8) Tokenizer {
        return .{ .input = input };
    }

    /// Returns the next token, or null after emitting EOF once.
    pub fn next(tok: *Tokenizer) ?Token {
        if (tok.finished) {
            return null;
        }

        while (tok.index < tok.input.len) {
            const start = tok.index;
            const ch = tok.input[tok.index];

            if (tok.line_start) {
                const literal = tok.scanLiteralLine();
                if (literal) |token| {
                    return token;
                }
            }

            if (tok.isNewline(ch)) {
                const consumed = tok.consumeNewline();
                tok.line_start = true;
                return .{ .tag = .newline, .offset = start, .len = consumed };
            }

            if (tok.isHorizontalWhitespace(ch)) {
                tok.index += 1;
                tok.line_start = false;
                continue;
            }

            tok.line_start = false;

            switch (ch) {
                '{' => return tok.simpleToken(.@"{"),
                '}' => return tok.simpleToken(.@"}"),
                '(' => return tok.simpleToken(.@"("),
                ')' => return tok.simpleToken(.@")"),
                ',' => return tok.simpleToken(.@","),
                '=' => return tok.simpleToken(.@"="),
                ':' => return tok.simpleToken(.@":"),
                '\\' => return tok.simpleToken(.@"\\"),
                '"' => return tok.scanStringLiteral(),
                else => {},
            }

            if (tok.isWordChar(ch)) {
                return tok.scanWord();
            }

            // Non-obvious fallback: we still emit a token for unknown bytes
            // so callers can recover and keep walking the stream.
            tok.index += 1;
            return .{ .tag = .invalid_character, .offset = start, .len = 1 };
        }

        tok.finished = true;
        return .{ .tag = .eof, .offset = tok.input.len, .len = 0 };
    }

    /// Emits a single-character token at the current offset.
    fn simpleToken(tok: *Tokenizer, tag: Token.Tag) Token {
        const start = tok.index;
        tok.index += 1;
        return .{ .tag = tag, .offset = start, .len = 1 };
    }

    /// Scans a quoted string or an unterminated string literal.
    fn scanStringLiteral(tok: *Tokenizer) Token {
        const start = tok.index;
        tok.index += 1;
        while (tok.index < tok.input.len) {
            const ch = tok.input[tok.index];
            if (ch == '"') {
                tok.index += 1;
                return .{ .tag = .string_literal, .offset = start, .len = tok.index - start };
            }
            if (tok.isNewline(ch)) {
                // We stop before the newline so the next call can emit it.
                return .{ .tag = .unterminated_string_literal, .offset = start, .len = tok.index - start };
            }
            if (ch == '\\') {
                // Escape sequences consume the next byte, even if it is a quote.
                if (tok.index + 1 >= tok.input.len) {
                    tok.index = tok.input.len;
                    break;
                }
                tok.index += 2;
                continue;
            }
            tok.index += 1;
        }

        return .{ .tag = .unterminated_string_literal, .offset = start, .len = tok.index - start };
    }

    /// Scans a WORD token as defined by the grammar.
    fn scanWord(tok: *Tokenizer) Token {
        const start = tok.index;
        tok.index += 1;
        while (tok.index < tok.input.len and tok.isWordChar(tok.input[tok.index])) {
            tok.index += 1;
        }
        return .{ .tag = .word, .offset = start, .len = tok.index - start };
    }

    /// Scans a literal line token if the current position is at a line start.
    fn scanLiteralLine(tok: *Tokenizer) ?Token {
        const start = tok.index;
        var cursor = tok.index;
        while (cursor < tok.input.len and tok.isHorizontalWhitespace(tok.input[cursor])) {
            cursor += 1;
        }
        if (cursor >= tok.input.len or tok.input[cursor] != '|') {
            return null;
        }
        cursor += 1;
        while (cursor < tok.input.len and !tok.isNewline(tok.input[cursor])) {
            cursor += 1;
        }
        tok.index = cursor;
        tok.line_start = false;
        return .{ .tag = .literal_line, .offset = start, .len = cursor - start };
    }

    /// Consumes a newline, including CRLF sequences.
    fn consumeNewline(tok: *Tokenizer) usize {
        if (tok.input[tok.index] == '\r') {
            if (tok.index + 1 < tok.input.len and tok.input[tok.index + 1] == '\n') {
                tok.index += 2;
                return 2;
            }
            tok.index += 1;
            return 1;
        }
        tok.index += 1;
        return 1;
    }
    fn isWordChar(_: *Tokenizer, ch: u8) bool {
        return !std.ascii.isControl(ch) and !std.ascii.isWhitespace(ch) and ch != '{' and ch != '}' and ch != '\\' and ch != '"' and ch != '(' and ch != ')' and ch != ',' and ch != '=' and ch != ':';
    }

    fn isHorizontalWhitespace(_: *Tokenizer, ch: u8) bool {
        return ch == ' ' or ch == '\t';
    }

    fn isNewline(_: *Tokenizer, ch: u8) bool {
        return ch == '\n' or ch == '\r';
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
) !Document {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    _ = plain_text;
    _ = diagnostics;

    return .{
        .arena = arena,
        .contents = &[_]Block{},
    };
}

/// A diagnostic message.
pub const Diagnostic = struct {
    pub const Severity = enum { warning, @"error" };

    pub const Location = struct {
        line: u32,
        column: u32,
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
