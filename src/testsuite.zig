const std = @import("std");
const hdoc = @import("hyperdoc");

fn testAcceptDocument(document: []const u8) !void {
    var doc = try hdoc.parse(std.testing.allocator, document, null);
    defer doc.deinit();
}

const TokenExpect = struct {
    tag: hdoc.Token.Tag,
    lexeme: []const u8,
};

fn expectTokens(input: []const u8, expected: []const TokenExpect) !void {
    var tokenizer = hdoc.Tokenizer.init(input);
    var index: usize = 0;
    while (true) {
        const token_opt = tokenizer.next();
        if (token_opt == null) {
            break;
        }
        const token = token_opt.?;
        try std.testing.expect(index < expected.len);
        try std.testing.expectEqual(expected[index].tag, token.tag);
        try std.testing.expectEqualStrings(expected[index].lexeme, token.slice(input));
        index += 1;
        if (token.tag == .eof) {
            break;
        }
    }
    try std.testing.expectEqual(expected.len, index);
    try std.testing.expect(tokenizer.next() == null);
}

test "tokenizes header line" {
    try expectTokens("hdoc \"2.0\"\n", &.{
        .{ .tag = .word, .lexeme = "hdoc" },
        .{ .tag = .string_literal, .lexeme = "\"2.0\"" },
        .{ .tag = .newline, .lexeme = "\n" },
        .{ .tag = .eof, .lexeme = "" },
    });
}

test "tokenizes literal lines" {
    try expectTokens("p:\n| code\n  |more\n", &.{
        .{ .tag = .word, .lexeme = "p" },
        .{ .tag = .@":", .lexeme = ":" },
        .{ .tag = .newline, .lexeme = "\n" },
        .{ .tag = .literal_line, .lexeme = "| code" },
        .{ .tag = .newline, .lexeme = "\n" },
        .{ .tag = .literal_line, .lexeme = "  |more" },
        .{ .tag = .newline, .lexeme = "\n" },
        .{ .tag = .eof, .lexeme = "" },
    });
}

test "tokenizes unterminated string" {
    try expectTokens("\"oops\n", &.{
        .{ .tag = .unterminated_string_literal, .lexeme = "\"oops" },
        .{ .tag = .newline, .lexeme = "\n" },
        .{ .tag = .eof, .lexeme = "" },
    });
}

test "tokenizes word and escapes" {
    try expectTokens("{alpha \\{ -dash}", &.{
        .{ .tag = .@"{", .lexeme = "{" },
        .{ .tag = .word, .lexeme = "alpha" },
        .{ .tag = .@"\\", .lexeme = "\\" },
        .{ .tag = .@"{", .lexeme = "{" },
        .{ .tag = .word, .lexeme = "-dash" },
        .{ .tag = .@"}", .lexeme = "}" },
        .{ .tag = .eof, .lexeme = "" },
    });
}

test "tokenizes mixed sequences" {
    try expectTokens(
        "note(id=\"x\"){\n\\em \"hi\", -dash\n}\n",
        &.{
            .{ .tag = .word, .lexeme = "note" },
            .{ .tag = .@"(", .lexeme = "(" },
            .{ .tag = .word, .lexeme = "id" },
            .{ .tag = .@"=", .lexeme = "=" },
            .{ .tag = .string_literal, .lexeme = "\"x\"" },
            .{ .tag = .@")", .lexeme = ")" },
            .{ .tag = .@"{", .lexeme = "{" },
            .{ .tag = .newline, .lexeme = "\n" },
            .{ .tag = .@"\\", .lexeme = "\\" },
            .{ .tag = .word, .lexeme = "em" },
            .{ .tag = .string_literal, .lexeme = "\"hi\"" },
            .{ .tag = .@",", .lexeme = "," },
            .{ .tag = .word, .lexeme = "-dash" },
            .{ .tag = .newline, .lexeme = "\n" },
            .{ .tag = .@"}", .lexeme = "}" },
            .{ .tag = .newline, .lexeme = "\n" },
            .{ .tag = .eof, .lexeme = "" },
        },
    );
}

test "tokenizes invalid characters" {
    try expectTokens("\x00", &.{
        .{ .tag = .invalid_character, .lexeme = "\x00" },
        .{ .tag = .eof, .lexeme = "" },
    });
}
