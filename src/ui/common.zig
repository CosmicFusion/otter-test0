const std = @import("std");
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");
const ow = @import("otter_wayland");

const root_mod = @import("root.zig");

pub const ButtonInfo = struct {
    id: ui.SurfaceId,
    rect: ?geo.Rect,
    on_pressed: *const fn (self: *root_mod.Root, info: ButtonInfo, damage: *ow.DamageTracker) void,
};
