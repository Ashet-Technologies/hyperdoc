const std = @import("std");
const hyperdoc = @import("hyperdoc");

const LogLevel = enum(u8) { err, warn, info, debug };

extern fn reset_log() void;
extern fn append_log(ptr: [*]const u8, len: usize) void;
extern fn flush_log(level: LogLevel) void;

const LogWriter = struct {
    fn appendWrite(chunk: []const u8) usize {
        append_log(chunk.ptr, chunk.len);
        return chunk.len;
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        var count: usize = 0;
        if (w.end > 0) {
            count += appendWrite(w.buffered());
            w.end = 0;
        }
        if (data.len > 1) {
            for (data[0 .. data.len - 1]) |item| {
                count += appendWrite(item);
            }
        }
        for (0..splat) |_| {
            count += appendWrite(data[data.len - 1]);
        }
        return count;
    }

    fn writer(buffer: []u8) std.Io.Writer {
        return .{
            .buffer = buffer,
            .vtable = &.{
                .drain = LogWriter.drain,
            },
        };
    }
};

fn log_to_host(
    comptime level: std.log.Level,
    comptime _scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = _scope;

    reset_log();

    var buffer: [256]u8 = undefined;
    var writer = LogWriter.writer(&buffer);
    writer.print(format, args) catch {};

    const mapped: LogLevel = switch (level) {
        .err => .err,
        .warn => .warn,
        .info => .info,
        .debug => .debug,
    };

    flush_log(mapped);
}

fn fixedPageSize() usize {
    return 4096;
}

fn zeroRandom(buffer: []u8) void {
    @memset(buffer, 0);
}

pub const std_options: std.Options = .{
    .enable_segfault_handler = false,
    .logFn = log_to_host,
    .queryPageSize = fixedPageSize,
    // .cryptoRandomSeed = zeroRandom,
};

const allocator = std.heap.wasm_allocator;

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = message;
    _ = stack_trace;
    _ = ret_addr;
    @breakpoint();
    unreachable;
}

pub fn main() !void {}

const DiagnosticView = struct {
    line: u32,
    column: u32,
    message: []u8,
    is_fatal: bool,
};

var document_buffer: std.array_list.Managed(u8) = .init(allocator);
var html_buffer: std.Io.Writer.Allocating = .init(allocator);
var diagnostic_views: std.array_list.Managed(DiagnosticView) = .init(allocator);
var diagnostic_text: std.Io.Writer.Allocating = .init(allocator);

fn capture_diagnostics(source: *hyperdoc.Diagnostics) !void {
    diagnostic_views.clearRetainingCapacity();
    diagnostic_text.clearRetainingCapacity();

    if (source.items.items.len == 0) return;

    var total: usize = 0;
    for (source.items.items) |diag| {
        var cw: std.Io.Writer.Discarding = .init(&.{});
        _ = diag.code.format(&cw.writer) catch {};
        total += @intCast(cw.fullCount());
    }

    diagnostic_text.ensureTotalCapacityPrecise(total) catch return;

    const diag_writer = &diagnostic_text.writer;

    for (source.items.items) |diag| {
        const start = diagnostic_text.writer.end;
        try diag.code.format(diag_writer);

        const rendered = diagnostic_text.writer.buffered()[start..];
        try diagnostic_views.append(.{
            .line = diag.location.line,
            .column = diag.location.column,
            .message = rendered,
            .is_fatal = switch (diag.code.severity()) {
                .warning => false,
                .@"error" => true,
            },
        });
    }
}

export fn hdoc_set_document_len(len: usize) bool {
    document_buffer.clearRetainingCapacity();
    document_buffer.items.len = 0;

    if (len == 0) return true;

    document_buffer.ensureTotalCapacityPrecise(len) catch return false;
    document_buffer.items.len = len;
    return true;
}

export fn hdoc_document_ptr() [*]u8 {
    return document_buffer.items.ptr;
}

export fn hdoc_process() bool {
    html_buffer.clearRetainingCapacity();
    diagnostic_views.clearRetainingCapacity();
    diagnostic_text.clearRetainingCapacity();

    const source: []const u8 = document_buffer.items;

    var diagnostics = hyperdoc.Diagnostics.init(allocator);
    defer diagnostics.deinit();

    var parsed = hyperdoc.parse(allocator, source, &diagnostics) catch {
        capture_diagnostics(&diagnostics) catch {};
        return false;
    };
    defer parsed.deinit();

    if (diagnostics.has_error()) {
        capture_diagnostics(&diagnostics) catch {};
        return false;
    }

    const html_writer = &html_buffer.writer;

    hyperdoc.render.html5(parsed, html_writer, .{}) catch {
        capture_diagnostics(&diagnostics) catch {};
        return false;
    };

    capture_diagnostics(&diagnostics) catch {};
    return true;
}

export fn hdoc_html_ptr() ?[*]const u8 {
    if (html_buffer.writer.end == 0) return null;
    return html_buffer.writer.buffer.ptr;
}

export fn hdoc_html_len() usize {
    return html_buffer.writer.end;
}

export fn hdoc_diagnostic_count() usize {
    return diagnostic_views.items.len;
}

export fn hdoc_diagnostic_line(index: usize) u32 {
    if (index >= diagnostic_views.items.len) return 0;

    return diagnostic_views.items[index].line;
}

export fn hdoc_diagnostic_column(index: usize) u32 {
    if (index >= diagnostic_views.items.len) return 0;

    return diagnostic_views.items[index].column;
}

export fn hdoc_diagnostic_fatal(index: usize) bool {
    if (index >= diagnostic_views.items.len) return false;

    return diagnostic_views.items[index].is_fatal;
}

export fn hdoc_diagnostic_message_ptr(index: usize) ?[*]const u8 {
    if (index >= diagnostic_views.items.len) return null;

    if (diagnostic_views.items[index].message.len == 0) return null;

    return diagnostic_views.items[index].message.ptr;
}

export fn hdoc_diagnostic_message_len(index: usize) usize {
    if (index >= diagnostic_views.items.len) return 0;

    return diagnostic_views.items[index].message.len;
}
