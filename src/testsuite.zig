const std = @import("std");
const hdoc = @import("hyperdoc");

fn testAcceptDocument(document: []const u8) !void {
    var doc = try hdoc.parse(std.testing.allocator, document);
    defer doc.deinit();
}

test "empty document" {
    try testAcceptDocument(
        \\hdoc "1.0"
    );
}

test "invalid document" {
    try std.testing.expectError(error.InvalidFormat, testAcceptDocument(
        \\
    ));
    try std.testing.expectError(error.InvalidFormat, testAcceptDocument(
        \\hdoc
    ));
    try std.testing.expectError(error.InvalidFormat, testAcceptDocument(
        \\hdoc {
    ));
    try std.testing.expectError(error.InvalidFormat, testAcceptDocument(
        \\span
    ));
    try std.testing.expectError(error.InvalidFormat, testAcceptDocument(
        \\blob
    ));
}

test "invalid version" {
    try std.testing.expectError(error.InvalidFormat, testAcceptDocument(
        \\hdoc 1.0
    ));
    try std.testing.expectError(error.InvalidVersion, testAcceptDocument(
        \\hdoc ""
    ));
    try std.testing.expectError(error.InvalidVersion, testAcceptDocument(
        \\hdoc "1.2"
    ));
}

test "accept toc" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\toc {}
    );
}

test "accept multiple blocks" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\toc {}
        \\toc {}
        \\toc {}
        \\toc {}
    );
}

test "accept image" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\image "dog.png"
    );
}

test "accept headers" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\h1 "" "Empty anchor"
        \\h2 "chapter" "Chapter anchor"
        \\h3 "section" "Section anchor"
    );
}

test "invalid top level items" {
    try std.testing.expectError(error.InvalidTopLevelItem, testAcceptDocument(
        \\hdoc "1.0"
        \\span
    ));
    try std.testing.expectError(error.InvalidTopLevelItem, testAcceptDocument(
        \\hdoc "1.0"
        \\link
    ));
    try std.testing.expectError(error.InvalidTopLevelItem, testAcceptDocument(
        \\hdoc "1.0"
        \\emph
    ));
    try std.testing.expectError(error.InvalidTopLevelItem, testAcceptDocument(
        \\hdoc "1.0"
        \\mono
    ));
}

test "empty ordered lists" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\enumerate {}
    );
}

test "ordered lists" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\enumerate {
        \\  toc {}
        \\  toc {}
        \\  toc {}
        \\}
    );
}

test "unordered lists" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\itemize {
        \\  toc {}
        \\  toc {}
        \\  toc {}
        \\}
    );
}

test "nested lists" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\enumerate {
        \\  itemize { }
        \\  enumerate { }
        \\  toc { }
        \\  itemize { toc { } }
        \\  enumerate { toc { } }
        \\}
    );
}

test "empty paragraph" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\p{}
        \\p{}
        \\p{}
    );
}

test "empty quote" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\quote{}
        \\quote{}
        \\quote{}
    );
}

test "spans" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\p{ span "hello" }
        \\p{ span "\n" }
        \\p{ span "" }
    );
}

test "mono" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\p{ mono "hello" }
        \\p{ mono "\n" }
        \\p{ mono "" }
    );
}

test "emph" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\p{ emph "hello" }
        \\p{ emph "\n" }
        \\p{ emph "" }
    );
}

test "links" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\p{ link "" "hello" }
        \\p{ link "" "\n" }
        \\p{ link "" "" }
        \\p{ link "https://www.example.com/deep/path.txt" "hello" }
        \\p{ link "https://www.example.com/deep/path.txt" "\n" }
        \\p{ link "https://www.example.com/deep/path.txt" "" }
        \\p{ link "#anchor" "hello" }
        \\p{ link "#anchor" "\n" }
        \\p{ link "#anchor" "" }
    );
}

test "code block" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\pre "" { }
        \\pre "c++" { }
        \\pre "zig" { }
        \\pre "c++" { span "#include <cstdio>" }
        \\pre "zig" { span "const std = @import(\"std\");" }
    );
}

test "example document" {
    try testAcceptDocument(
        \\hdoc "1.0"
        \\h1 "intro" "Introduction"
        \\toc { }
        \\p {
        \\  span "Hello, World!\n"
        \\  link "http://google.com" "Visit Google!"
        \\  span "\n"
        \\  emph "This is fat!"
        \\  span "\n"
        \\  mono "int main()"
        \\  span "\n"
        \\}
        \\enumerate {
        \\  p { span "first" }
        \\  p { span "second" }
        \\  p { span "third" }
        \\}
        \\itemize {
        \\  p { span "first" }
        \\  p { span "second" }
        \\  p { span "third" }
        \\}
        \\quote {
        \\  span "Life is what happens when you're busy making other plans.\n - John Lennon"
        \\}
        \\pre "zig" {
        \\  span "const std = @import(\"std\");\n"
        \\  span "\n"
        \\  span "pub fn main() !void {\n"
        \\  span "    std.debug.print(\"Hello, World!\\n\", .{});\n"
        \\  span "}\n"
        \\}
        \\image "dog.png"
    );
}
