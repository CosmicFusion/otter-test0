const ui = @import("otter_ui");

const root_mod = @import("root.zig");

pub const ButtonInfo = struct {
    id: ui.SurfaceId,
    on_pressed: *const fn (self: *root_mod.Root) root_mod.PressResult,
};
