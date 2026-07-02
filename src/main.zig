//! CLI entry. Picks layer overlay or XDG window, then runs the shell app.

const std = @import("std");
const utils = @import("otter_utils");
const ui = @import("otter_ui");
const layer_app = @import("shell/layer_app.zig");
const xdg_app = @import("shell/xdg_app.zig");

const Mode = enum {
    layer,
    window,

    fn parse(text: []const u8) ?Mode {
        if (std.ascii.eqlIgnoreCase(text, "layer")) return .layer;
        if (std.ascii.eqlIgnoreCase(text, "window") or std.mem.eql(u8, text, "xdg")) return .window;
        return null;
    }
};

pub fn main(init: std.process.Init) !void {
    // Zig 0.16: register process I/O before any Otter file or network call.
    utils.io.install(init.io);

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = if (args.len > 1) Mode.parse(args[1]) orelse {
        usage();
        return error.UnknownMode;
    } else blk: {
        usage();
        break :blk .window;
    };

    switch (mode) {
        .layer => try layer_app.run(init.gpa),
        .window => {
            var xdg_opts: xdg_app.Options = .{};
            for (args[2..]) |arg| {
                if (ui.debugOverlayModeFromArg(arg)) |overlay_mode| {
                    xdg_opts.debug_overlay_mode = overlay_mode;
                }
            }
            try xdg_app.run(init.gpa, xdg_opts);
        },
    }
}

fn usage() void {
    std.debug.print(
        \\otter-examples - Otter Shell Surface Description demos
        \\
        \\usage:
        \\  otter-examples layer    # zwlr_layer_shell_v1 overlay
        \\  otter-examples window   # xdg toplevel window
        \\
        \\window mode debug overlays (also Ctrl+Shift+I to cycle):
        \\  --inspect / --inspector   SD element inspector
        \\  --metrics                 FPS and frame timing overlay
        \\
    , .{});
}

test "mode parsing" {
    try std.testing.expectEqual(Mode.layer, Mode.parse("layer").?);
    try std.testing.expectEqual(Mode.window, Mode.parse("window").?);
    try std.testing.expectEqual(Mode.window, Mode.parse("xdg").?);
}
