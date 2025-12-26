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
        .{ .code = .{ .duplicate_attribute = .{ .name = "title" } }, .samples = &.{"hdoc(version=\"2.0\"); h1(lang=\"a\",lang=\"b\");"} },
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

            if (!diagnosticsContain(&diagnostics, case.code)) {
                std.log.err("Diagnostics did not contain expected code: '{t}'", .{case.code});
                for (diagnostics.items.items) |item| {
                    std.log.err("  Emitted diagnostic: {f}", .{item.code});
                }
                return error.MissingDiagnosticCode;
            }

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
