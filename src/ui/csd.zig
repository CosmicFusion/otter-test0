const std = @import("std");
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");

const xdg_app_mod = @import("../shell/xdg_app.zig");

pub const Ids = struct {
    pub const resize_margin: u16 = 6;

    pub const titlebar = ui.SurfaceId.namedComptime("csd.titlebar");
    pub const background = ui.SurfaceId.namedComptime("csd.background");
    pub const title = ui.SurfaceId.namedComptime("csd.title");
    pub const minimize = ui.SurfaceId.namedComptime("csd.minimize");
    pub const maximize = ui.SurfaceId.namedComptime("csd.maximize");
    pub const close = ui.SurfaceId.namedComptime("csd.close");
};

pub fn buildTitlebar(root: anytype, title: []const u8, theme: theme_mod.Theme, maximized: bool, window_active: bool) void {
    root.titlebar_layers[0] = ui.SurfaceNode.panel(Ids.background, .{ .width = .fill, .height = .fill }, .{
        .background = if (window_active) theme.csd.titlebar_bg_active else theme.csd.titlebar_bg_inactive,
        .border = theme.surfaces.border_subtle,
        .highlight_edge = theme.surfaces.highlight_edge,
        .radius = 0,
        .border_width = theme.csd.border_size,
    });

    root.titlebar_children[0] = ui.SurfaceNode.label(Ids.title, title, theme.csd.titlebar_text_size, theme.colors.foreground);
    root.titlebar_children[0].layout = .{
        .width = .fill,
        .height = .fill,
        .align_y = .center,
    };

    root.titlebar_children[1] = titlebarButton(
        Ids.minimize,
        theme,
        "_",
        if (window_active) theme.csd.button_minimize_bg else theme.csd.button_icon_color_inactive,
        theme.csd.button_minimize_hover,
    );
    root.titlebar_children[2] = titlebarButton(
        Ids.maximize,
        theme,
        if (maximized) "[]" else "+",
        if (window_active) theme.csd.button_maximize_bg else theme.csd.button_icon_color_inactive,
        theme.csd.button_maximize_hover,
    );
    root.titlebar_children[3] = titlebarButton(
        Ids.close,
        theme,
        "x",
        if (window_active) theme.csd.button_close_bg else theme.csd.button_icon_color_inactive,
        theme.csd.button_close_hover,
    );

    root.titlebar_layers[1] = .{
        .id = Ids.titlebar,
        .kind = .row,
        .layout = .{
            .width = .fill,
            .height = .fill,
            .padding = .{ .west = theme.csd.button_padding, .east = theme.csd.button_padding, .north = theme.csd.button_padding, .south = theme.csd.button_padding },
            .gap = theme.csd.titlebar_padding,
            .align_y = .center,
        },
        .hit = .generic,
        .children = root.titlebar_children[0..4],
    };

    root.window_children[root.window_children_count] = .{
        .id = Ids.titlebar,
        .kind = .stack,
        .layout = .{ .width = .fill, .height = .{ .fixed = theme.csd.titlebar_height } },
        .children = root.titlebar_layers[0..2],
    };
    root.window_children_count += 1;
}

pub fn ownsId(id: ui.SurfaceId) bool {
    return id.eql(Ids.titlebar) or
        id.eql(Ids.background) or
        id.eql(Ids.title) or
        id.eql(Ids.minimize) or
        id.eql(Ids.maximize) or
        id.eql(Ids.close);
}

fn titlebarButton(id: ui.SurfaceId, theme: theme_mod.Theme, text: []const u8, background_color: render.Color, hover_background: render.Color) ui.SurfaceNode {
    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .{ .fixed = theme.csd.button_width }, .height = .{ .fixed = theme.csd.button_height } },
        .content = .{
            .button = .{
                .text = text,
                .font_size = @intFromFloat(std.math.round(@as(f32, @floatFromInt(theme.csd.button_height)) * 0.6)),
                .background = background_color,
                .hover_background = hover_background,
                .radius = theme.csd.border_radius,
            },
        },
        .hit = .button,
    };
}

fn minimizePressed(root: anytype) xdg_app_mod.PressResult {
    _ = root;
    return .{ .csd = .minimize };
}

fn maximizePressed(root: anytype) xdg_app_mod.PressResult {
    _ = root;
    return .{ .csd = .maximize };
}

fn closePressed(root: anytype) xdg_app_mod.PressResult {
    _ = root;
    return .{ .csd = .close };
}

fn movePressed(root: anytype) xdg_app_mod.PressResult {
    _ = root;
    return .{ .csd = .move };
}

pub fn checkPress(root: anytype, pressed_id: ui.SurfaceId) xdg_app_mod.PressResult {
    if (pressed_id.eql(Ids.minimize)) return minimizePressed(root);
    if (pressed_id.eql(Ids.maximize)) return maximizePressed(root);
    if (pressed_id.eql(Ids.close)) return closePressed(root);
    if (pressed_id.eql(Ids.titlebar) or
        pressed_id.eql(Ids.background) or
        pressed_id.eql(Ids.title))
    {
        return movePressed(root);
    }
    return .none;
}
