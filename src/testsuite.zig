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
    try std.testing.expectEqual(@as(usize, 0), ident.location.offset);
    try std.testing.expectEqual(@as(usize, 2), ident.location.length);

    const word = try parser.accept_word();
    try std.testing.expectEqualStrings("word", word.text);
    try std.testing.expectEqual(@as(usize, 3), word.location.offset);
    try std.testing.expectEqual(@as(usize, 4), word.location.length);
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

test "semantic analyzer unescapes string literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "\"line\\\\break\\nquote \\\" unicode \\u{1F600}\"";

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var sema: hdoc.SemanticAnalyzer = .{
        .arena = arena.allocator(),
        .diagnostics = &diagnostics,
        .code = source,
    };

    const token: hdoc.Parser.Token = .{ .text = source, .location = .{ .offset = 0, .length = source.len } };

    const text = try sema.unescape_string(token);
    try std.testing.expectEqualStrings("line\\break\nquote \" unicode 😀", text);
    try std.testing.expect(!diagnostics.has_error());
}

test "semantic analyzer reports invalid string escapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "\"oops\\q\"";

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var sema: hdoc.SemanticAnalyzer = .{
        .arena = arena.allocator(),
        .diagnostics = &diagnostics,
        .code = source,
    };

    const token: hdoc.Parser.Token = .{ .text = source, .location = .{ .offset = 0, .length = source.len } };

    const text = try sema.unescape_string(token);
    try std.testing.expectEqualStrings("oops\\q", text);
    try std.testing.expectEqual(@as(usize, 1), diagnostics.items.items.len);
    try std.testing.expect(diagnosticCodesEqual(diagnostics.items.items[0].code, .{ .invalid_string_escape = .{ .codepoint = 'q' } }));
}

test "semantic analyzer flags forbidden control characters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "\"tab\\u{9}\"";

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var sema: hdoc.SemanticAnalyzer = .{
        .arena = arena.allocator(),
        .diagnostics = &diagnostics,
        .code = source,
    };

    const token: hdoc.Parser.Token = .{ .text = source, .location = .{ .offset = 0, .length = source.len } };

    const text = try sema.unescape_string(token);
    try std.testing.expectEqualStrings("tab\t", text);
    try std.testing.expectEqual(@as(usize, 1), diagnostics.items.items.len);
    try std.testing.expect(diagnosticCodesEqual(diagnostics.items.items[0].code, .{ .illegal_character = .{ .codepoint = 0x9 } }));
}

test "semantic analyzer forbids raw control characters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "\"bad\tvalue\"";

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var sema: hdoc.SemanticAnalyzer = .{
        .arena = arena.allocator(),
        .diagnostics = &diagnostics,
        .code = source,
    };

    const token: hdoc.Parser.Token = .{ .text = source, .location = .{ .offset = 0, .length = source.len } };
    _ = try sema.unescape_string(token);

    try std.testing.expectEqual(@as(usize, 1), diagnostics.items.items.len);
    try std.testing.expect(diagnosticCodesEqual(diagnostics.items.items[0].code, .{ .illegal_character = .{ .codepoint = 0x9 } }));
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
    try std.testing.expectEqual(@as(usize, 2), node.attributes.items.len);

    const attribs = node.attributes.items;

    const title = attribs[0];
    try std.testing.expectEqualStrings("title", title.name.text);
    try std.testing.expectEqualStrings("\"Hello\"", title.value.text);

    const author = attribs[1];
    try std.testing.expectEqualStrings("author", author.name.text);
    try std.testing.expectEqualStrings("\"World\"", author.value.text);

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

fn diagnosticCodesEqual(a: hdoc.Diagnostic.Code, b: hdoc.Diagnostic.Code) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;

    return switch (a) {
        .document_starts_with_bom,
        .unterminated_inline_list,
        .unterminated_string,
        .unterminated_block_list,
        .missing_hdoc_header,
        .duplicate_hdoc_header,
        .link_not_nestable,
        .invalid_link,
        .invalid_date_time,
        .invalid_date_time_fmt,
        .empty_verbatim_block,
        .verbatim_missing_trailing_newline,
        .verbatim_missing_space,
        .trailing_whitespace,
        .empty_inline_body,
        .attribute_leading_trailing_whitespace,
        .invalid_unicode_string_escape,
        => true,

        .unexpected_eof => |ctx| blk: {
            const other = b.unexpected_eof;
            break :blk ctx.expected_char == other.expected_char and std.mem.eql(u8, ctx.context, other.context);
        },

        .unexpected_character => |ctx| blk: {
            const other = b.unexpected_character;
            break :blk ctx.expected == other.expected and ctx.found == other.found;
        },

        .invalid_identifier_start => |ctx| blk: {
            const other = b.invalid_identifier_start;
            break :blk ctx.char == other.char;
        },

        .missing_attribute => |ctx| blk: {
            const other = b.missing_attribute;
            break :blk ctx.type == other.type and std.mem.eql(u8, ctx.name, other.name);
        },

        .invalid_attribute => |ctx| blk: {
            const other = b.invalid_attribute;
            break :blk ctx.type == other.type and std.mem.eql(u8, ctx.name, other.name);
        },

        .unknown_block_type => |ctx| blk: {
            const other = b.unknown_block_type;
            break :blk std.mem.eql(u8, ctx.name, other.name);
        },

        .invalid_block_type => |ctx| blk: {
            const other = b.invalid_block_type;
            break :blk std.mem.eql(u8, ctx.name, other.name);
        },

        .invalid_inline_combination => |ctx| blk: {
            const other = b.invalid_inline_combination;
            break :blk ctx.first == other.first and ctx.second == other.second;
        },

        .duplicate_attribute => |ctx| blk: {
            const other = b.duplicate_attribute;
            break :blk std.mem.eql(u8, ctx.name, other.name);
        },

        .unknown_attribute => |ctx| blk: {
            const other = b.unknown_attribute;
            break :blk ctx.type == other.type and std.mem.eql(u8, ctx.name, other.name);
        },

        .redundant_inline => |ctx| blk: {
            const other = b.redundant_inline;
            break :blk ctx.attribute == other.attribute;
        },

        .invalid_string_escape => |ctx| blk: {
            break :blk b.invalid_string_escape.codepoint == ctx.codepoint;
        },

        .illegal_character => |ctx| blk: {
            const other = b.illegal_character;
            break :blk ctx.codepoint == other.codepoint;
        },
    };
}

fn logDiagnostics(diag: *const hdoc.Diagnostics) void {
    for (diag.items.items) |item| {
        var buf: [256]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        item.code.format(stream.writer()) catch {};
        std.log.err("Diagnostic {d}:{d}: {s}", .{ item.location.line, item.location.column, stream.getWritten() });
    }
}

fn validateDiagnostics(code: []const u8, expected: []const hdoc.Diagnostic.Code) !void {
    try std.testing.expect(expected.len > 0);

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const maybe_doc = hdoc.parse(std.testing.allocator, code, &diagnostics) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => null,
    };
    if (maybe_doc) |doc| {
        var owned = doc;
        defer owned.deinit();
    }

    if (diagnostics.items.items.len != expected.len) {
        logDiagnostics(&diagnostics);
    }
    try std.testing.expectEqual(expected.len, diagnostics.items.items.len);
    for (expected, 0..) |exp, idx| {
        const actual = diagnostics.items.items[idx].code;
        if (!diagnosticCodesEqual(actual, exp)) {
            logDiagnostics(&diagnostics);
            return error.MissingDiagnosticCode;
        }
    }
}

fn expectParseOk(code: []const u8) !void {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, code, &diagnostics);
    defer doc.deinit();

    if (diagnostics.has_error() or diagnostics.has_warning()) {
        logDiagnostics(&diagnostics);
        return error.TestExpectedEqual;
    }
}

fn expectParseNoFail(code: []const u8) !void {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = hdoc.parse(std.testing.allocator, code, &diagnostics) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => {
            logDiagnostics(&diagnostics);
            return error.TestExpectedEqual;
        },
    };
    defer doc.deinit();

    if (diagnostics.has_error()) {
        logDiagnostics(&diagnostics);
        return error.TestExpectedEqual;
    }
}

test "parsing valid document yields empty diagnostics" {
    try expectParseOk("hdoc(version=\"2.0\");");
}

test "diagnostic codes are emitted for expected samples" {
    try validateDiagnostics("hdoc(version=\"2.0\"); h1(", &.{.{ .unexpected_eof = .{ .context = "identifier", .expected_char = null } }});
    try validateDiagnostics("hdoc(version=\"2.0\"); h1 123", &.{.{ .unexpected_character = .{ .expected = '{', .found = '1' } }});
    try validateDiagnostics("hdoc(version=\"2.0\"); h1 \"unterminated", &.{.unterminated_string});
    try validateDiagnostics("hdoc(version=\"2.0\"); -abc", &.{.{ .invalid_identifier_start = .{ .char = '-' } }});
    try validateDiagnostics("hdoc{h1 \"x\"", &.{.unterminated_block_list});
    try validateDiagnostics("hdoc(version=\"2.0\"); p {hello", &.{.unterminated_inline_list});
    try validateDiagnostics(
        "hdoc(version=\"2.0\"); h1(lang=\"a\",lang=\"b\");",
        &.{ .{ .duplicate_attribute = .{ .name = "lang" } }, .empty_inline_body },
    );
    try validateDiagnostics("hdoc(version=\"2.0\"); pre:\n", &.{.empty_verbatim_block});
    try validateDiagnostics("hdoc(version=\"2.0\"); pre:\n| line", &.{.verbatim_missing_trailing_newline});
    try validateDiagnostics("hdoc(version=\"2.0\"); pre:\n|nospace\n", &.{.verbatim_missing_space});
    try validateDiagnostics("hdoc(version=\"2.0\"); pre:\n| trailing \n", &.{.trailing_whitespace});
    try validateDiagnostics("h1 \"Title\"", &.{.missing_hdoc_header});
    try validateDiagnostics("hdoc(version=\"2.0\"); hdoc(version=\"2.0\");", &.{.duplicate_hdoc_header});
    try validateDiagnostics("hdoc(version=\"2.0\"); h1 \"bad\\q\"", &.{.{ .invalid_string_escape = .{ .codepoint = 'q' } }});
    try validateDiagnostics("hdoc(version=\"2.0\"); h1 \"bad\\u{9}\"", &.{.{ .illegal_character = .{ .codepoint = 0x9 } }});
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

test "Version.parse accepts dotted versions" {
    const version = try hdoc.Version.parse("2.0");
    try std.testing.expectEqual(@as(u16, 2), version.major);
    try std.testing.expectEqual(@as(u16, 0), version.minor);

    try std.testing.expectError(error.InvalidValue, hdoc.Version.parse("2"));
    try std.testing.expectError(error.InvalidValue, hdoc.Version.parse("2."));
    try std.testing.expectError(error.InvalidValue, hdoc.Version.parse("2.0.1"));
    try std.testing.expectError(error.InvalidValue, hdoc.Version.parse(".1"));
    try std.testing.expectError(error.InvalidValue, hdoc.Version.parse("2.a"));
}

test "Date.parse accepts ISO dates" {
    const date = try hdoc.Date.parse("2025-12-25");
    try std.testing.expectEqual(@as(i32, 2025), date.year);
    try std.testing.expectEqual(@as(u4, 12), date.month);
    try std.testing.expectEqual(@as(u5, 25), date.day);

    const short_year = try hdoc.Date.parse("1-01-01");
    try std.testing.expectEqual(@as(i32, 1), short_year.year);
    try std.testing.expectEqual(@as(u4, 1), short_year.month);
    try std.testing.expectEqual(@as(u5, 1), short_year.day);

    try std.testing.expectError(error.InvalidValue, hdoc.Date.parse("2025-1-01"));
    try std.testing.expectError(error.InvalidValue, hdoc.Date.parse("2025-13-01"));
    try std.testing.expectError(error.InvalidValue, hdoc.Date.parse("2025-12-32"));
}

test "Time.parse accepts ISO times with zones" {
    const utc = try hdoc.Time.parse("22:30:46Z");
    try std.testing.expectEqual(@as(u5, 22), utc.hour);
    try std.testing.expectEqual(@as(u6, 30), utc.minute);
    try std.testing.expectEqual(@as(u6, 46), utc.second);
    try std.testing.expectEqual(@as(u20, 0), utc.microsecond);
    try std.testing.expectEqual(@as(i32, 0), utc.zone_offset);

    const fractional = try hdoc.Time.parse("22:30:46.136+01:00");
    try std.testing.expectEqual(@as(u20, 136_000), fractional.microsecond);
    try std.testing.expectEqual(@as(i32, 60), fractional.zone_offset);

    const nanos = try hdoc.Time.parse("21:30:46.136797358-05:30");
    try std.testing.expectEqual(@as(u20, 136_797), nanos.microsecond);
    try std.testing.expectEqual(@as(i32, -330), nanos.zone_offset);

    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("21:30:46,1Z"));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("22:30:46"));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("24:00:00Z"));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("23:60:00Z"));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("23:59:60Z"));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("23:59:59.1234Z"));
}

test "DateTime.parse accepts ISO date-time" {
    const datetime = try hdoc.DateTime.parse("2025-12-25T22:31:50.13+01:00");
    try std.testing.expectEqual(@as(i32, 2025), datetime.date.year);
    try std.testing.expectEqual(@as(u4, 12), datetime.date.month);
    try std.testing.expectEqual(@as(u5, 25), datetime.date.day);
    try std.testing.expectEqual(@as(u5, 22), datetime.time.hour);
    try std.testing.expectEqual(@as(u6, 31), datetime.time.minute);
    try std.testing.expectEqual(@as(u6, 50), datetime.time.second);
    try std.testing.expectEqual(@as(u20, 130_000), datetime.time.microsecond);
    try std.testing.expectEqual(@as(i32, 60), datetime.time.zone_offset);

    try std.testing.expectError(error.InvalidValue, hdoc.DateTime.parse("2025-12-25 22:31:50Z"));
}
