const std = @import("std");

pub export fn _start() void {}

pub export fn hyperdoc_lsp_ping() void {
    // Placeholder entrypoint for a wasm-based language server.
    // Real initialization will be wired once the wasm server is implemented.
    std.mem.doNotOptimizeAway(@as(u32, 0));
}
