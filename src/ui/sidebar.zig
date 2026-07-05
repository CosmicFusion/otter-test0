//! Sidebar module: fixed-width panel, fills available height.

const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");
const ow = @import("otter_wayland");

const root_mod = @import("root.zig");
const common_mod = @import("common.zig");

pub const Ids = struct {
    // Sidebar
    pub const panel = ui.SurfaceId.namedComptime("sidebar.panel");
    pub const content = ui.SurfaceId.namedComptime("sidebar.content");
    // Sidebar toggle
    pub const toggle_sidebar = ui.SurfaceId.namedComptime("root.toggle_sidebar");
};

/// Builds the sidebar's own [panel, content] pair into root.sidebar_layers,
/// and returns the sidebar's root node (fixed width, fills height).
pub fn buildSidebar(root: *root_mod.Root, theme: theme_mod.Theme) ui.SurfaceNode {
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
        .id = ui.SurfaceId.namedComptime("sidebar.root"),
        .kind = .stack,
        .layout = .{ .width = .{ .fixed = root.sidebar_width }, .height = .fill },
        .children = root.sidebar_layers[0..2],
    };
}

pub fn BuildSidebarToggle(root: *root_mod.Root, ui_state: *const root_mod.UiState, theme: theme_mod.Theme) void {
    const id = Ids.toggle_sidebar;
    const text = if (root.sidebar_collapsed) "Hide Sidebar" else "Show Sidebar";

    root.main_children[root.main_count] = .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .fit, .height = .fit, .align_x = .center },
        .content = .{ .button = .{
            .text = text,
            .hovered = ui_state.input.hovered.eql(id),
            .hover_background = theme.surfaces.hover,
            .pressed_background = theme.surfaces.pressed,
            .border = theme.surfaces.border_subtle,
            .radius = theme.spacing.button_border_radius,
        } },
        .hit = .button,
    };

    root.sidebar_button_infos[0] = .{
        .id = id,
        .rect = null,
        .on_pressed = toggleSidebarPressed,
    };

    root.main_count += 1;
}

fn toggleSidebarPressed(root: *root_mod.Root, info: common_mod.ButtonInfo, damage: *ow.DamageTracker) void {
    root_mod.Root.damageRect(damage, info.rect);
    root.sidebar_collapsed = !root.sidebar_collapsed;
    // The whole row reflows (main card's width, everything's position)
    // — cheaper and safer to redraw everything than to hand-compute
    // every rect that shifted.
    damage.markFullDamage();
}

pub fn checkHover(
    root: *root_mod.Root,
    old_hover: ui.SurfaceId,
    current: ui.SurfaceId,
    damage: *ow.DamageTracker,
) bool {
    var dirty = false;
    for (root.sidebar_button_infos) |info| {
        if (root_mod.Root.hoverChanged(old_hover, current, info.id)) {
            root_mod.Root.damageRect(damage, info.rect);
            dirty = true;
        }
    }
    return dirty;
}

pub fn onPointerPress(
    root: *root_mod.Root,
    ui_state: *root_mod.UiState,
    point: geo.Point,
    damage: *ow.DamageTracker,
) bool {
    const press = ui_state.dispatch(.{ .button_press = .{ .point = point, .button = 1 } });

    for (root.sidebar_button_infos) |info| {
        if (press.id.eql(info.id)) {
            info.on_pressed(root, info, damage);
            return true;
        }
    }
    return false;
}

pub fn onPointerRelease(root: *root_mod.Root, ui_state: *root_mod.UiState, point: geo.Point, damage: *ow.DamageTracker) bool {
    _ = ui_state.dispatch(.{ .button_release = .{ .point = point, .button = 1 } });
    var dirty = false;
    for (root.sidebar_button_infos) |info| {
        root_mod.Root.damageRect(damage, info.rect);
        dirty = true;
    }
    return dirty;
}

pub fn captureRects(root: *root_mod.Root, ui_state: *const root_mod.UiState) void {
    for (&root.sidebar_button_infos) |*info| {
        if (ui_state.findElement(info.id)) |element| info.rect = element.rect;
    }
}
