//! Sidebar module: fixed-width panel, fills available height.

const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");

const root_mod = @import("root.zig");

pub const Ids = struct {
    // Sidebar
    pub const root = ui.SurfaceId.namedComptime("sidebar.root");
    pub const panel = ui.SurfaceId.namedComptime("sidebar.panel");
    pub const content = ui.SurfaceId.namedComptime("sidebar.content");
};

/// Builds the sidebar's own [panel, content] pair into root.sidebar_layers,
/// and returns the sidebar's root node (fixed width, fills height).
pub fn buildSidebar(root: *root_mod.Root, theme: theme_mod.Theme) ui.SurfaceNode {
    //_ = is_overlay;
    root.sidebar_layers[0] = ui.SurfaceNode.panel(Ids.panel, .{ .width = .fill, .height = .fill }, .{
        .background = theme.panelColor(theme.surfaces.surface),
        .border = theme.surfaces.border_subtle,
        .border_width = 1,
    });

    // Placeholder — add nav items / labels here later, same way sidebar.zig
    // fills root.content[]. For now, an empty fill column.
    root.sidebar_layers[1] = .{
        .id = Ids.content,
        .kind = .column,
        .layout = .{
            .width = .fill,
            .height = .fill,
            .padding = ui.Padding.uniform(16),
            .gap = 8,
        },
        .children = &.{},
    };

    return .{
        .id = Ids.root,
        .kind = .stack,
        .layout = .{
            .width = .{ .fixed = root.sidebar_width },
            .height = .fill,
            .align_x = .start,
        },
        .children = root.sidebar_layers[0..2],
    };
}

pub fn checkPress(root: *root_mod.Root, pressed_id: ui.SurfaceId) root_mod.PressResult {
    _ = root;
    _ = pressed_id;
    return .none;
}
