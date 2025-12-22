const std = @import("std");
const hdoc = @import("hyperdoc");

fn testAcceptDocument(document: []const u8) !void {
    var doc = try hdoc.parse(std.testing.allocator, document, null);
    defer doc.deinit();
}

test "empty document" {
    try testAcceptDocument(
        \\hdoc "2.0"
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
}

test "invalid version" {
    try std.testing.expectError(error.InvalidFormat, testAcceptDocument(
        \\hdoc 2.0
    ));
    try std.testing.expectError(error.InvalidVersion, testAcceptDocument(
        \\hdoc ""
    ));
    try std.testing.expectError(error.InvalidVersion, testAcceptDocument(
        \\hdoc "1.2"
    ));
    try std.testing.expectError(error.InvalidVersion, testAcceptDocument(
        \\hdoc "1.0"
    ));
}
