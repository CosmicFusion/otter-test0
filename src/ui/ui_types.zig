const ui = @import("otter_ui");

pub const Decoration = enum {
    none,
    server,
    client,
};

pub const Edge = enum {
    top,
    bottom,
    left,
    right,
    top_left,
    top_right,
    bottom_left,
    bottom_right,
};

pub const CsdAction = union(enum) {
    minimize,
    maximize,
    close,
    move,
    resize: Edge,
};

pub const PressResult = union(enum) {
    none,
    input,
    damage: ui.SurfaceId,
    sidebar,
    csd: CsdAction,
};

pub const PointerOpts = struct {
    debug_overlay: bool = false,
};
