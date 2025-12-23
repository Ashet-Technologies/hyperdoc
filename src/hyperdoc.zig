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
