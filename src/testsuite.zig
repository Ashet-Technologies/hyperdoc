const std = @import("std");
const hdoc = @import("./hyperdoc.zig");

fn testAcceptDocument(document: []const u8) !void {
    var doc = try hdoc.parse(std.testing.allocator, document, null);
    defer doc.deinit();
}

fn parseFile(path: []const u8) !void {
    const source = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 10 * 1024 * 1024);
    defer std.testing.allocator.free(source);
    try testAcceptDocument(source);
}

fn parseDirectoryTree(path: []const u8) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(std.testing.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file)
            continue;
        if (!std.mem.endsWith(u8, entry.path, ".hdoc"))
            continue;

        const full_path = try std.fs.path.join(std.testing.allocator, &.{ path, entry.path });
        defer std.testing.allocator.free(full_path);

        try parseFile(full_path);
    }
}

test "parser accepts examples and test documents" {
    try parseDirectoryTree("examples");
    try parseDirectoryTree("test");
}

test "parser accept identifier and word tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "h1 word\\em{test}",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const ident = try parser.accept_identifier();
    try std.testing.expectEqualStrings("h1", ident.text);
    try std.testing.expectEqual(@as(usize, 0), ident.position.offset);
    try std.testing.expectEqual(@as(usize, 2), ident.position.length);

    const word = try parser.accept_word();
    try std.testing.expectEqualStrings("word", word.text);
    try std.testing.expectEqual(@as(usize, 3), word.position.offset);
    try std.testing.expectEqual(@as(usize, 4), word.position.length);
    try std.testing.expectEqual(@as(usize, 7), parser.offset);
}

test "parser rejects identifiers with invalid start characters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "-abc",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    try std.testing.expectError(error.InvalidCharacter, parser.accept_identifier());
}

test "parser accept string literals and unescape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "\"hello\\\\n\"",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const token = try parser.accept_string();
    try std.testing.expectEqualStrings("\"hello\\\\n\"", token.text);
}

test "parser reports unterminated string literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "\"unterminated\n",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    try std.testing.expectError(error.UnterminatedStringLiteral, parser.accept_string());
}

test "parser handles attributes and empty bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "h1(title=\"Hello\",author=\"World\");",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const node = try parser.accept_node(.top_level);
    try std.testing.expectEqual(hdoc.Parser.NodeType.h1, node.type);
    try std.testing.expectEqual(@as(usize, 2), node.attributes.count());

    const title = node.attributes.get("title") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Hello", title.value);

    const author = node.attributes.get("author") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("World", author.value);

    try std.testing.expect(node.body == .empty);
}

test "parser handles string bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "p \"Hello world\"",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const node = try parser.accept_node(.top_level);
    try std.testing.expectEqual(hdoc.Parser.NodeType.p, node.type);
    switch (node.body) {
        .string => |token| try std.testing.expectEqualStrings("\"Hello world\"", token.text),
        else => return error.TestExpectedEqual,
    }
}

test "parser handles verbatim blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "pre:\n|line one\n|line two\n",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const node = try parser.accept_node(.top_level);
    try std.testing.expectEqual(hdoc.Parser.NodeType.pre, node.type);
    switch (node.body) {
        .verbatim => |lines| {
            try std.testing.expectEqual(@as(usize, 2), lines.len);
            try std.testing.expectEqualStrings("|line one", lines[0].text);
            try std.testing.expectEqualStrings("|line two", lines[1].text);
        },
        else => return error.TestExpectedEqual,
    }
}

test "parser handles block node lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "hdoc{h1 \"Title\" p \"Body\"}",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const node = try parser.accept_node(.top_level);
    try std.testing.expectEqual(hdoc.Parser.NodeType.hdoc, node.type);
    switch (node.body) {
        .list => |children| {
            try std.testing.expectEqual(@as(usize, 2), children.len);
            try std.testing.expectEqual(hdoc.Parser.NodeType.h1, children[0].type);
            try std.testing.expectEqual(hdoc.Parser.NodeType.p, children[1].type);
        },
        else => return error.TestExpectedEqual,
    }
}

test "parser handles inline node lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "p { Hello \\em{world} }",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const node = try parser.accept_node(.top_level);
    try std.testing.expectEqual(hdoc.Parser.NodeType.p, node.type);
    switch (node.body) {
        .list => |children| {
            try std.testing.expectEqual(@as(usize, 2), children.len);
            try std.testing.expectEqual(hdoc.Parser.NodeType.text, children[0].type);
            try std.testing.expectEqual(@as(usize, 5), children[0].location.length);

            try std.testing.expectEqual(hdoc.Parser.NodeType.@"\\em", children[1].type);
            switch (children[1].body) {
                .list => |inline_children| {
                    try std.testing.expectEqual(@as(usize, 1), inline_children.len);
                    try std.testing.expectEqual(hdoc.Parser.NodeType.text, inline_children[0].type);
                    try std.testing.expectEqual(@as(usize, 5), inline_children[0].location.length);
                },
                else => return error.TestExpectedEqual,
            }
        },
        else => return error.TestExpectedEqual,
    }
}

test "parser handles unknown node types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "\\madeup{} mystery{}",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const inline_node = try parser.accept_node(.top_level);
    try std.testing.expectEqual(hdoc.Parser.NodeType.unknown_inline, inline_node.type);
    switch (inline_node.body) {
        .list => |children| try std.testing.expectEqual(@as(usize, 0), children.len),
        else => return error.TestExpectedEqual,
    }

    const block_node = try parser.accept_node(.top_level);
    try std.testing.expectEqual(hdoc.Parser.NodeType.unknown_block, block_node.type);
    switch (block_node.body) {
        .list => |children| try std.testing.expectEqual(@as(usize, 0), children.len),
        else => return error.TestExpectedEqual,
    }
}

fn diagnosticsContain(diag: *const hdoc.Diagnostics, expected: hdoc.Diagnostic.Code) bool {
    for (diag.items.items) |item| {
        if (std.meta.activeTag(item.code) == std.meta.activeTag(expected)) {
            return true;
        }
    }
    return false;
}

test "parsing valid document yields empty diagnostics" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, "hdoc(version=\"2.0\");", &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    try std.testing.expect(!diagnostics.has_warning());
    try std.testing.expectEqual(@as(usize, 0), diagnostics.items.items.len);
}

test "diagnostic codes are emitted for expected samples" {
    const Case = struct {
        code: hdoc.Diagnostic.Code,
        samples: []const []const u8,
    };

    const cases = [_]Case{
        .{ .code = .{ .unexpected_eof = .{ .context = "identifier", .expected_char = null } }, .samples = &.{"hdoc(version=\"2.0\"); h1("} },
        .{ .code = .{ .unexpected_character = .{ .expected = '{', .found = '1' } }, .samples = &.{"hdoc(version=\"2.0\"); h1 123"} },
        .{ .code = .unterminated_string, .samples = &.{"hdoc(version=\"2.0\"); h1 \"unterminated"} },
        .{ .code = .{ .invalid_identifier_start = .{ .char = '-' } }, .samples = &.{"hdoc(version=\"2.0\"); -abc"} },
        .{ .code = .unterminated_block_list, .samples = &.{"hdoc{h1 \"x\""} },
        .{ .code = .unterminated_inline_list, .samples = &.{"hdoc(version=\"2.0\"); p {hello"} },
        .{ .code = .{ .duplicate_attribute = .{ .name = "title" } }, .samples = &.{"hdoc(version=\"2.0\"); h1(title=\"a\",title=\"b\");"} },
        .{ .code = .empty_verbatim_block, .samples = &.{"hdoc(version=\"2.0\"); pre:\n"} },
        .{ .code = .verbatim_missing_trailing_newline, .samples = &.{"hdoc(version=\"2.0\"); pre:\n|line"} },
        .{ .code = .verbatim_missing_space, .samples = &.{"hdoc(version=\"2.0\"); pre:\n|nospace\n"} },
        .{ .code = .trailing_whitespace, .samples = &.{"hdoc(version=\"2.0\"); pre:\n| trailing \n"} },
        .{ .code = .missing_hdoc_header, .samples = &.{"h1 \"Title\""} },
        .{ .code = .duplicate_hdoc_header, .samples = &.{"hdoc(version=\"2.0\"); hdoc(version=\"2.0\");"} },
    };

    inline for (cases) |case| {
        for (case.samples) |sample| {
            var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
            defer diagnostics.deinit();

            const maybe_doc = hdoc.parse(std.testing.allocator, sample, &diagnostics) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => null,
            };

            if (maybe_doc) |doc| {
                var owned_doc = doc;
                defer owned_doc.deinit();
            }

            try std.testing.expect(diagnosticsContain(&diagnostics, case.code));

            const expected_severity = case.code.severity();
            if (expected_severity == .@"error") {
                try std.testing.expect(diagnostics.has_error());
            } else {
                try std.testing.expect(!diagnostics.has_error());
                try std.testing.expect(diagnostics.has_warning());
            }
        }
    }
}

test "parser reports unterminated inline lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "p { word",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    try std.testing.expectError(error.UnterminatedList, parser.accept_node(.top_level));
}

test "parser maps diagnostic locations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser: hdoc.Parser = .{
        .code = "a\nb\nc",
        .arena = arena.allocator(),
        .diagnostics = null,
    };

    const loc = parser.make_diagnostic_location(4);
    try std.testing.expectEqual(@as(u32, 3), loc.line);
    try std.testing.expectEqual(@as(u32, 1), loc.column);
}
