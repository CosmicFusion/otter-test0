//! Top controls: utility buttons above the main card.

const std = @import("std");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const ow = @import("otter_wayland");

const root_mod = @import("root.zig");
const common_mod = @import("common.zig");

pub const Ids = struct {
    pub const content = ui.SurfaceId.namedComptime("top_controls.content");
    pub const hello = ui.SurfaceId.namedComptime("top_controls.hello");
    pub const toggle_sidebar = ui.SurfaceId.namedComptime("top_controls.toggle_sidebar");
};

pub fn buildTopControls(root: *root_mod.Root, ui_state: *const root_mod.UiState, theme: theme_mod.Theme) void {
    root.top_controls[0] = buildHelloButton(root, ui_state, theme);
    root.top_controls[1] = buildSidebarToggle(root, ui_state, theme);

    const child_count: usize = if (root.toggle_button_shown) 2 else 1;

    root.main_children[root.main_count] = .{ .id = Ids.content, .kind = .stack, .layout = .{ .width = .fill, .height = .fit }, .children = root.top_controls[0..child_count] };
    root.main_count += 1;
}

fn buildHelloButton(root: *root_mod.Root, ui_state: *const root_mod.UiState, theme: theme_mod.Theme) ui.SurfaceNode {
    const id = Ids.hello;

    root.top_button_infos[0] = .{
        .id = id,
        .rect = null,
        .on_pressed = helloPressed,
    };

    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .fit, .height = .fit, .align_x = .start },
        .content = .{ .button = .{
            .text = "Hello",
            .hovered = ui_state.input.hovered.eql(id),
            .hover_background = theme.surfaces.hover,
            .pressed_background = theme.surfaces.pressed,
            .border = theme.surfaces.border_subtle,
            .radius = theme.spacing.button_border_radius,
        } },
        .hit = .button,
    };
}

fn buildSidebarToggle(root: *root_mod.Root, ui_state: *const root_mod.UiState, theme: theme_mod.Theme) ui.SurfaceNode {
    const id = Ids.toggle_sidebar;
    const text = if (root.sidebar_visible) "Hide Sidebar" else "Show Sidebar";

    root.top_button_infos[1] = .{
        .id = id,
        .rect = null,
        .on_pressed = toggleSidebarPressed,
    };

    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .fit, .height = .fit, .align_x = .end },
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
}

fn helloPressed(root: *root_mod.Root, info: common_mod.ButtonInfo, damage: *ow.DamageTracker) void {
    _ = root;
    root_mod.Root.damageRect(damage, info.rect);
    std.debug.print("hello\n", .{});
    damage.markFullDamage();
}

fn toggleSidebarPressed(root: *root_mod.Root, info: common_mod.ButtonInfo, damage: *ow.DamageTracker) void {
    root_mod.Root.damageRect(damage, info.rect);
    root.sidebar_visible = !root.sidebar_visible;
    damage.markFullDamage();
}

pub fn checkHover(
    root: *root_mod.Root,
    old_hover: ui.SurfaceId,
    current: ui.SurfaceId,
    damage: *ow.DamageTracker,
) bool {
    var dirty = false;
    for (root.top_button_infos) |info| {
        if (root_mod.Root.hoverChanged(old_hover, current, info.id)) {
            root_mod.Root.damageRect(damage, info.rect);
            dirty = true;
        }
    }
    return dirty;
}

pub fn checkPress(root: *root_mod.Root, pressed_id: ui.SurfaceId, damage: *ow.DamageTracker) bool {
    for (root.top_button_infos) |info| {
        if (pressed_id.eql(info.id)) {
            info.on_pressed(root, info, damage);
            return true;
        }
    }
    return false;
}

pub fn checkRelease(root: *root_mod.Root, damage: *ow.DamageTracker) bool {
    var dirty = false;
    for (root.top_button_infos) |info| {
        root_mod.Root.damageRect(damage, info.rect);
        dirty = true;
    }
    return dirty;
}

pub fn captureRects(root: *root_mod.Root, ui_state: *const root_mod.UiState) void {
    for (&root.top_button_infos) |*info| {
        if (ui_state.findElement(info.id)) |element| info.rect = element.rect;
    }
}
