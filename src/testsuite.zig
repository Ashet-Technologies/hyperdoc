const std = @import("std");
const hdoc = @import("./hyperdoc.zig");

// TODO: Write unit test for trailing comma in attribute lists
// TODO: Write unit test for invalid escape sequence detection when more than 6 (hex) chars are used
// TODO: Write unit test for invalid version detection (must be 2.0)
// TODO: Write unit test for duplicate header recognition
// TODO: Write unit test for clean_utf8_input() passthrough
// TODO: Write unit test for clean_utf8_input() BOM detection
// TODO: Write unit test for clean_utf8_input() invalid UTF-8 detection
// TODO: Write unit test for clean_utf8_input() illegal codepoint detection (bare CR -> error)
// TODO: Write unit test for clean_utf8_input() illegal codepoint detection (TAB -> warning)
// TODO: Write unit test for clean_utf8_input() illegal codepoint detection (any other control character -> error)

test "validate examples directory" {
    try parseDirectoryTree("examples");
}

test "validate tests directory" {
    try parseDirectoryTree("test/accept");
}

fn parseDirectoryTree(path: []const u8) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(std.testing.allocator);
    defer walker.deinit();

    var path_buffer: std.array_list.Managed(u8) = .init(std.testing.allocator);
    defer path_buffer.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file)
            continue;
        if (!std.mem.endsWith(u8, entry.path, ".hdoc"))
            continue;

        errdefer std.log.err("failed to process \"{f}/{f}\"", .{ std.zig.fmtString(path), std.zig.fmtString(entry.path) });

        const source = try entry.dir.readFileAlloc(std.testing.allocator, entry.basename, 10 * 1024 * 1024);
        defer std.testing.allocator.free(source);

        path_buffer.clearRetainingCapacity();
        try path_buffer.appendSlice(path);
        try path_buffer.append('/');
        try path_buffer.appendSlice(entry.path);

        try expectParseOk(.{ .file_path = path_buffer.items }, source);
    }
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
        .code = "*abc",
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

test "span merger preserves whitespace after inline mono" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const source =
        \\hdoc(version="2.0",lang="en");
        \\p{ \mono{monospace} text. }
    ;

    var doc = try hdoc.parse(std.testing.allocator, source, &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    try std.testing.expectEqual(@as(usize, 1), doc.contents.len);

    switch (doc.contents[0]) {
        .paragraph => |para| {
            try std.testing.expectEqual(@as(usize, 2), para.content.len);
            try std.testing.expect(para.content[0].attribs.mono);
            try std.testing.expect(!para.content[1].attribs.mono);

            switch (para.content[0].content) {
                .text => |text| try std.testing.expectEqualStrings("monospace", text),
                else => return error.TestExpectedEqual,
            }

            switch (para.content[1].content) {
                .text => |text| try std.testing.expectEqualStrings(" text.", text),
                else => return error.TestExpectedEqual,
            }
        },
        else => return error.TestExpectedEqual,
    }
}

test "pre verbatim preserves trailing whitespace" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const source =
        "hdoc(version=\"2.0\",lang=\"en\");\n" ++ "pre:\n" ++ "| line with trailing spaces   \n" ++ "|   indented line  \n";

    var doc = try hdoc.parse(std.testing.allocator, source, &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    try std.testing.expectEqual(@as(usize, 1), doc.contents.len);

    const preformatted = doc.contents[0].preformatted;
    try std.testing.expectEqual(@as(usize, 1), preformatted.content.len);

    const expected = "line with trailing spaces   \n  indented line  ";
    switch (preformatted.content[0].content) {
        .text => |text| try std.testing.expectEqualStrings(expected, text),
        else => return error.TestExpectedEqual,
    }
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
            try std.testing.expectEqual(@as(usize, 5), children.len);

            try std.testing.expectEqual(.text, children[0].type);
            try std.testing.expectEqual(.text, children[1].type);
            try std.testing.expectEqual(.text, children[2].type);
            try std.testing.expectEqual(.@"\\em", children[3].type);
            try std.testing.expectEqual(.text, children[4].type);

            try std.testing.expectEqual(" ".len, children[0].location.length);
            try std.testing.expectEqual("Hello".len, children[1].location.length);
            try std.testing.expectEqual(" ".len, children[2].location.length);
            try std.testing.expectEqual("\\em{world}".len, children[3].location.length);
            try std.testing.expectEqual(" ".len, children[4].location.length);

            switch (children[3].body) {
                .list => |inline_children| {
                    try std.testing.expectEqual(1, inline_children.len);
                    try std.testing.expectEqual(.text, inline_children[0].type);
                    try std.testing.expectEqual("world".len, inline_children[0].location.length);
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

test "table of contents inserts automatic headings when skipping levels" {
    const source =
        \\hdoc(version="2.0");
        \\h3{Third}
        \\h2{Second}
        \\h1{First}
    ;

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, source, &diagnostics);
    defer doc.deinit();

    try std.testing.expectEqual(@as(usize, 3), diagnostics.items.items.len);
    try std.testing.expect(diagnosticCodesEqual(diagnostics.items.items[0].code, .missing_document_language));
    try std.testing.expect(diagnosticCodesEqual(diagnostics.items.items[1].code, .{ .automatic_heading_insertion = .{ .level = .h1 } }));
    try std.testing.expect(diagnosticCodesEqual(diagnostics.items.items[2].code, .{ .automatic_heading_insertion = .{ .level = .h2 } }));

    const toc = doc.toc;
    try std.testing.expectEqual(.h1, toc.level);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, toc.headings);
    try std.testing.expectEqual(@as(usize, 2), toc.children.len);

    const auto_h1 = toc.children[0];
    try std.testing.expectEqual(.h2, auto_h1.level);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, auto_h1.headings);
    try std.testing.expectEqual(@as(usize, 2), auto_h1.children.len);

    const auto_h2 = auto_h1.children[0];
    try std.testing.expectEqual(.h3, auto_h2.level);
    try std.testing.expectEqualSlices(usize, &.{0}, auto_h2.headings);

    const h2_child = auto_h1.children[1];
    try std.testing.expectEqual(.h3, h2_child.level);
    try std.testing.expectEqual(@as(usize, 0), h2_child.headings.len);
    try std.testing.expectEqual(@as(usize, 0), h2_child.children.len);

    const trailing_h1_child = toc.children[1];
    try std.testing.expectEqual(.h2, trailing_h1_child.level);
    try std.testing.expectEqual(@as(usize, 0), trailing_h1_child.headings.len);
    try std.testing.expectEqual(@as(usize, 0), trailing_h1_child.children.len);
}

fn diagnosticCodesEqual(lhs: hdoc.Diagnostic.Code, rhs: hdoc.Diagnostic.Code) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs))
        return false;

    switch (lhs) {
        inline else => |_, tag_value| {
            const tag = @tagName(tag_value);
            const a_struct = @field(lhs, tag);
            const b_struct = @field(rhs, tag);

            const TagField = @FieldType(hdoc.Diagnostic.Code, tag);
            const info = @typeInfo(TagField);

            switch (info) {
                .void => return true,

                .@"struct" => |struct_info| {
                    inline for (struct_info.fields) |fld| {
                        const a = @field(a_struct, fld.name);
                        const b = @field(b_struct, fld.name);
                        const eql = switch (fld.type) {
                            []const u8 => std.mem.eql(u8, a, b),
                            else => (a == b),
                        };
                        if (!eql)
                            return false;
                    }
                    return true;
                },

                else => @compileError("Unsupported type: " ++ @typeName(TagField)),
            }
        },
    }
}

const LogDiagOptions = struct {
    file_path: []const u8 = "",
};

fn logDiagnostics(diag: *const hdoc.Diagnostics, opts: LogDiagOptions) void {
    for (diag.items.items) |item| {
        var buf: [256]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        item.code.format(stream.writer()) catch {};
        std.log.err("Diagnostic {s}:{d}:{d}: {s}", .{ opts.file_path, item.location.line, item.location.column, stream.getWritten() });
    }
}

fn validateDiagnostics(opts: LogDiagOptions, code: []const u8, expected: []const hdoc.Diagnostic.Code) !void {
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
        logDiagnostics(&diagnostics, opts);
    }
    try std.testing.expectEqual(expected.len, diagnostics.items.items.len);
    for (expected, 0..) |exp, idx| {
        const actual = diagnostics.items.items[idx].code;
        if (!diagnosticCodesEqual(actual, exp)) {
            logDiagnostics(&diagnostics, opts);
            return error.MissingDiagnosticCode;
        }
    }
}

fn expectParseOk(opts: LogDiagOptions, code: []const u8) !void {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, code, &diagnostics);
    defer doc.deinit();

    if (diagnostics.has_error()) {
        logDiagnostics(&diagnostics, opts);
        return error.TestExpectedNoDiagnostics;
    }

    for (diagnostics.items.items) |item| {
        if (item.code.severity() != .warning)
            continue;
        switch (item.code) {
            .missing_document_language => {},
            else => {
                logDiagnostics(&diagnostics, opts);
                return error.TestExpectedNoDiagnostics;
            },
        }
    }
}

fn expectParseNoFail(opts: LogDiagOptions, code: []const u8) !void {
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
        logDiagnostics(&diagnostics, opts);
        return error.TestExpectedNoErrors;
    }
}

test "parsing valid document yields empty diagnostics" {
    try expectParseOk(.{}, "hdoc(version=\"2.0\",lang=\"en\");");
}

test "diagnostic codes are emitted for expected samples" {
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); h1(", &.{.{ .unexpected_eof = .{ .context = "identifier", .expected_char = null } }});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); h1 123", &.{.{ .unexpected_character = .{ .expected = '{', .found = '1' } }});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); h1 \"unterminated", &.{.unterminated_string});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); *abc", &.{.{ .invalid_identifier_start = .{ .char = '*' } }});
    try validateDiagnostics(.{}, "hdoc{h1 \"x\"", &.{.unterminated_block_list});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); p {hello", &.{.unterminated_inline_list});
    try validateDiagnostics(
        .{},
        "hdoc(version=\"2.0\",lang=\"en\"); h1(lang=\"a\",lang=\"b\");",
        &.{ .{ .duplicate_attribute = .{ .name = "lang" } }, .empty_inline_body },
    );
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); pre:\n", &.{.empty_verbatim_block});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); pre:\n| line", &.{.verbatim_missing_trailing_newline});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); pre:\n|nospace\n", &.{.verbatim_missing_space});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); pre:\n| trailing \n", &.{.trailing_whitespace});
    try validateDiagnostics(.{}, "h1 \"Title\"", &.{.missing_hdoc_header});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); hdoc(version=\"2.0\",lang=\"en\");", &.{ .misplaced_hdoc_header, .duplicate_hdoc_header });
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); h1 \"bad\\q\"", &.{.{ .invalid_string_escape = .{ .codepoint = 'q' } }});
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); h1 \"bad\\u{9}\"", &.{.{ .illegal_character = .{ .codepoint = 0x9 } }});
}

test "table derives column count from first data row" {
    const code =
        \\hdoc(version="2.0",lang="en");
        \\table {
        \\  row(title="headered") {
        \\    td { p "A" }
        \\    td(colspan="2") { p "B" }
        \\  }
        \\}
    ;

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, code, &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    try std.testing.expectEqual(@as(usize, 1), doc.contents.len);

    switch (doc.contents[0]) {
        .table => |table| {
            try std.testing.expectEqual(@as(usize, 3), table.column_count);
            try std.testing.expect(table.has_row_titles);
        },
        else => return error.TestExpectedEqual,
    }
}

test "table without header or data rows is rejected" {
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); table { group \"Topic\" }", &.{.missing_table_column_count});
}

test "columns row must come first" {
    const code =
        \\hdoc(version="2.0",lang="en");
        \\table {
        \\  row { td "A" }
        \\  columns { td "B" }
        \\}
    ;

    try validateDiagnostics(.{}, code, &.{.misplaced_columns_row});
}

test "table allows only one columns row" {
    const code =
        \\hdoc(version="2.0",lang="en");
        \\table {
        \\  columns { td "A" }
        \\  columns { td "B" }
        \\}
    ;

    try validateDiagnostics(.{}, code, &.{.duplicate_columns_row});
}

test "table tracks presence of row titles" {
    const code =
        \\hdoc(version="2.0",lang="en");
        \\table {
        \\  row { td "A" }
        \\  group { "Topic" }
        \\}
    ;

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, code, &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    try std.testing.expectEqual(@as(usize, 1), doc.contents.len);

    switch (doc.contents[0]) {
        .table => |table| {
            try std.testing.expect(!table.has_row_titles);
        },
        else => return error.TestExpectedEqual,
    }
}

test "title block populates metadata and warns on inline date" {
    const code = "hdoc(version=\"2.0\",lang=\"en\");\ntitle { Hello \\date{2020-01-02} }\nh1 \"Body\"";

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, code, &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    try std.testing.expectEqual(@as(usize, 1), diagnostics.items.items.len);
    try std.testing.expect(diagnostics.items.items[0].code == .title_inline_date_time_without_header);

    const title = doc.title orelse return error.TestExpectedEqual;
    const full = title.full;
    try std.testing.expectEqualStrings("Hello 2020-01-02", title.simple);
    try std.testing.expectEqual(@as(usize, 3), full.content.len);
}

test "header title synthesizes full title representation" {
    const code = "hdoc(version=\"2.0\",title=\"Metadata\",lang=\"en\");\nh1 \"Body\"";

    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var doc = try hdoc.parse(std.testing.allocator, code, &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    try std.testing.expectEqual(@as(usize, 0), diagnostics.items.items.len);

    const title = doc.title orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Metadata", title.simple);

    const full = title.full;
    try std.testing.expectEqual(@as(usize, 1), full.content.len);
    switch (full.content[0].content) {
        .text => |text| try std.testing.expectEqualStrings("Metadata", text),
        else => return error.TestExpectedEqual,
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

    try std.testing.expectError(error.InvalidValue, hdoc.Date.parse("2025-1-01"));
    try std.testing.expectError(error.InvalidValue, hdoc.Date.parse("2025-13-01"));
    try std.testing.expectError(error.InvalidValue, hdoc.Date.parse("2025-12-32"));
    try std.testing.expectError(error.InvalidValue, hdoc.Date.parse("1-01-01"));
}

test "Time.parse accepts ISO times with zones" {
    const utc = try hdoc.Time.parse("22:30:46Z", null);
    try std.testing.expectEqual(@as(u5, 22), utc.hour);
    try std.testing.expectEqual(@as(u6, 30), utc.minute);
    try std.testing.expectEqual(@as(u6, 46), utc.second);
    try std.testing.expectEqual(@as(u20, 0), utc.microsecond);
    try std.testing.expectEqual(.utc, utc.timezone);

    const utc_hint = try hdoc.Time.parse("22:30:46", .utc);
    try std.testing.expectEqual(@as(u5, 22), utc_hint.hour);
    try std.testing.expectEqual(@as(u6, 30), utc_hint.minute);
    try std.testing.expectEqual(@as(u6, 46), utc_hint.second);
    try std.testing.expectEqual(@as(u20, 0), utc_hint.microsecond);
    try std.testing.expectEqual(.utc, utc_hint.timezone);

    const fractional = try hdoc.Time.parse("22:30:46.136-01:00", null);
    try std.testing.expectEqual(@as(u20, 136_000), fractional.microsecond);
    try std.testing.expectEqual(try hdoc.TimeZoneOffset.from_hhmm(-1, 0), fractional.timezone);

    const fractional_hint = try hdoc.Time.parse("22:30:46.136", try .parse("+01:30"));
    try std.testing.expectEqual(@as(u20, 136_000), fractional_hint.microsecond);
    try std.testing.expectEqual(@as(hdoc.TimeZoneOffset, @enumFromInt(90)), fractional_hint.timezone);

    const nanos = try hdoc.Time.parse("21:30:46.136797358-05:30", null);
    try std.testing.expectEqual(@as(u20, 136_797), nanos.microsecond);
    try std.testing.expectEqual(@as(hdoc.TimeZoneOffset, @enumFromInt(-330)), nanos.timezone);

    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("21:30:46,1Z", null));
    try std.testing.expectError(error.MissingTimezone, hdoc.Time.parse("22:30:46", null));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("24:00:00Z", null));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("23:60:00Z", null));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("23:59:60Z", null));
    try std.testing.expectError(error.InvalidValue, hdoc.Time.parse("23:59:59.1234Z", null));
}

test "DateTime.parse accepts ISO date-time" {
    const datetime = try hdoc.DateTime.parse("2025-12-25T22:31:50.13+01:00", null);
    try std.testing.expectEqual(@as(i32, 2025), datetime.date.year);
    try std.testing.expectEqual(@as(u4, 12), datetime.date.month);
    try std.testing.expectEqual(@as(u5, 25), datetime.date.day);
    try std.testing.expectEqual(@as(u5, 22), datetime.time.hour);
    try std.testing.expectEqual(@as(u6, 31), datetime.time.minute);
    try std.testing.expectEqual(@as(u6, 50), datetime.time.second);
    try std.testing.expectEqual(@as(u20, 130_000), datetime.time.microsecond);
    try std.testing.expectEqual(@as(hdoc.TimeZoneOffset, @enumFromInt(60)), datetime.time.timezone);

    try std.testing.expectError(error.InvalidValue, hdoc.DateTime.parse("2025-12-25 22:31:50Z", null));
}

test "diagnostics for missing language and empty image attributes" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const source =
        \\hdoc(version="2.0");
        \\img(path="", alt="");
    ;

    var doc = try hdoc.parse(std.testing.allocator, source, &diagnostics);
    defer doc.deinit();

    var saw_missing_lang = false;
    var saw_empty_path = false;
    var saw_empty_alt = false;

    for (diagnostics.items.items) |item| {
        switch (item.code) {
            .missing_document_language => saw_missing_lang = true,
            .empty_attribute => |ctx| {
                if (ctx.type == .img and std.mem.eql(u8, ctx.name, "path")) {
                    saw_empty_path = true;
                }
                if (ctx.type == .img and std.mem.eql(u8, ctx.name, "alt")) {
                    saw_empty_alt = true;
                }
            },
            else => {},
        }
    }

    try std.testing.expect(saw_missing_lang);
    try std.testing.expect(saw_empty_path);
    try std.testing.expect(saw_empty_alt);
}

test "diagnostics for missing timezone and unknown id" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const source =
        \\hdoc(version="2.0");
        \\p{ \time"12:00:00" \link(ref="missing"){missing} }
    ;

    var doc = try hdoc.parse(std.testing.allocator, source, &diagnostics);
    defer doc.deinit();

    var saw_missing_timezone = false;
    var saw_unknown_id = false;

    for (diagnostics.items.items) |item| {
        switch (item.code) {
            .missing_timezone => saw_missing_timezone = true,
            .unknown_id => |ctx| {
                if (std.mem.eql(u8, ctx.ref, "missing")) {
                    saw_unknown_id = true;
                }
            },
            else => {},
        }
    }

    try std.testing.expect(saw_missing_timezone);
    try std.testing.expect(saw_unknown_id);
}

test "diagnostics for tab characters" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const source = "hdoc(version=\"2.0\");\n\tp{ ok }";

    var doc = try hdoc.parse(std.testing.allocator, source, &diagnostics);
    defer doc.deinit();

    var saw_tab = false;

    for (diagnostics.items.items) |item| {
        switch (item.code) {
            .tab_character => saw_tab = true,
            else => {},
        }
    }

    try std.testing.expect(saw_tab);
}

test "diagnostics for bare carriage return" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const source = "hdoc(version=\"2.0\");\r";

    try std.testing.expectError(error.InvalidUtf8, hdoc.parse(std.testing.allocator, source, &diagnostics));

    var saw_bare_cr = false;
    for (diagnostics.items.items) |item| {
        switch (item.code) {
            .bare_carriage_return => saw_bare_cr = true,
            else => {},
        }
    }

    try std.testing.expect(saw_bare_cr);
}

test "hdoc header date uses timezone hint for missing zone" {
    var diagnostics: hdoc.Diagnostics = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const source = "hdoc(version=\"2.0\",lang=\"en\",tz=\"-01:30\",date=\"2026-01-01T12:00:00\");";
    var doc = try hdoc.parse(std.testing.allocator, source, &diagnostics);
    defer doc.deinit();

    try std.testing.expect(!diagnostics.has_error());
    const parsed = doc.date orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(i32, 2026), parsed.date.year);
    try std.testing.expectEqual(@as(u4, 1), parsed.date.month);
    try std.testing.expectEqual(@as(u5, 1), parsed.date.day);
    try std.testing.expectEqual(@as(u5, 12), parsed.time.hour);
    try std.testing.expectEqual(@as(u6, 0), parsed.time.minute);
    try std.testing.expectEqual(@as(u6, 0), parsed.time.second);
    try std.testing.expectEqual(@as(u20, 0), parsed.time.microsecond);
    try std.testing.expectEqual(try hdoc.TimeZoneOffset.parse("-01:30"), parsed.time.timezone);
}

test "\\date rejects bad body" {
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); p { \\date; }", &.{
        .invalid_date_time_body,
    });
    try validateDiagnostics(.{}, "hdoc(version=\"2.0\",lang=\"en\"); p { \\date{start \\em{inner}} }", &.{
        .invalid_date_time_body,
    });
}
