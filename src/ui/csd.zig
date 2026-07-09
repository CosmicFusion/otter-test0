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
};

pub fn buildTitlebar(root: anytype, title: []const u8, theme: theme_mod.Theme, maximized: bool, window_active: bool) void {
    var titlebar_children_start_count: u16 = 0;
    var titlebar_children_end_count: u16 = 0;
    const theme_button_layout = theme.csd.button_layout;

    const button_layout = if (theme_button_layout.len < 19) theme_button_layout else ":sbc";

    root.maximize_ids_count = 0;
    root.close_ids_count = 0;
    root.minimize_ids_count = 0;

    root.titlebar_layers[0] = ui.SurfaceNode.panel(Ids.background, .{ .width = .fill, .height = .fill }, .{
        .background = if (window_active) theme.csd.titlebar_bg_active else theme.csd.titlebar_bg_inactive,
        .border = theme.surfaces.border_subtle,
        .highlight_edge = theme.surfaces.highlight_edge,
        .radius = 0,
        .border_width = theme.csd.border_size,
    });
    root.titlebar_layers[0].hit = .generic;

    root.titlebar_layers[1] = ui.SurfaceNode.label(Ids.title, title, theme.csd.titlebar_text_size, theme.colors.foreground);
    root.titlebar_layers[1].layout = .{
        .width = .fit,
        .height = .fit,
        .align_x = .center,
        .align_y = .center,
    };

    var layout_section_end = true;

    var i: usize = button_layout.len;
    while (i > 0) {
        i -= 1;
        const char = button_layout[i];
        const count = if (layout_section_end) titlebar_children_end_count else titlebar_children_start_count;
        if (char == 'c') {
            var buf: [32]u8 = undefined;
            const id_name = std.fmt.bufPrint(&buf, "{s}{d}", .{ "csd.minimize", count }) catch "";
            const id = ui.SurfaceId.named(id_name);
            const button = titlebarButton(
                id,
                theme,
                "_",
                if (window_active) theme.csd.button_minimize_bg else theme.csd.button_icon_color_inactive,
                theme.csd.button_minimize_hover,
            );
            root.minimize_ids[root.minimize_ids_count] = id;
            root.minimize_ids_count += 1;
            if (layout_section_end) {
                root.titlebar_children_end[titlebar_children_end_count] = button;
                titlebar_children_end_count += 1;
            } else {
                root.titlebar_children_start[titlebar_children_start_count] = button;
                titlebar_children_start_count += 1;
            }
            continue;
        }
        if (char == 'b') {
            var buf: [32]u8 = undefined;
            const id_name = std.fmt.bufPrint(&buf, "{s}{d}", .{ "csd.maximize", count }) catch "";
            const id = ui.SurfaceId.named(id_name);
            const button = titlebarButton(
                id,
                theme,
                if (maximized) "[]" else "+",
                if (window_active) theme.csd.button_maximize_bg else theme.csd.button_icon_color_inactive,
                theme.csd.button_maximize_hover,
            );
            root.maximize_ids[root.maximize_ids_count] = id;
            root.maximize_ids_count += 1;
            if (layout_section_end) {
                root.titlebar_children_end[titlebar_children_end_count] = button;
                titlebar_children_end_count += 1;
            } else {
                root.titlebar_children_start[titlebar_children_start_count] = button;
                titlebar_children_start_count += 1;
            }
            continue;
        }
        if (char == 's') {
            var buf: [32]u8 = undefined;
            const id_name = std.fmt.bufPrint(&buf, "{s}{d}", .{ "csd.close", count }) catch "";
            const id = ui.SurfaceId.named(id_name);
            const button = titlebarButton(
                id,
                theme,
                "x",
                if (window_active) theme.csd.button_close_bg else theme.csd.button_icon_color_inactive,
                theme.csd.button_close_hover,
            );
            root.close_ids[root.close_ids_count] = id;
            root.close_ids_count += 1;
            if (layout_section_end) {
                root.titlebar_children_end[titlebar_children_end_count] = button;
                titlebar_children_end_count += 1;
            } else {
                root.titlebar_children_start[titlebar_children_start_count] = button;
                titlebar_children_start_count += 1;
            }
            continue;
        }
        if (char == ':') {
            layout_section_end = false;
            continue;
        }
    }

    root.titlebar_layers[2] = .{
        .id = Ids.titlebar,
        .kind = .row,
        .layout = .{
            .width = .fit,
            .height = .fill,
            .align_x = .start,
            .padding = .{ .west = theme.csd.button_padding, .east = theme.csd.button_padding, .north = theme.csd.button_padding, .south = theme.csd.button_padding },
            .gap = theme.csd.titlebar_padding,
            .align_y = .center,
        },
        .hit = .generic,
        .children = root.titlebar_children_start[0..titlebar_children_start_count],
    };

    root.titlebar_layers[3] = .{
        .id = Ids.titlebar,
        .kind = .row,
        .layout = .{
            .width = .fit,
            .height = .fill,
            .align_x = .end,
            .padding = .{ .west = theme.csd.button_padding, .east = theme.csd.button_padding, .north = theme.csd.button_padding, .south = theme.csd.button_padding },
            .gap = theme.csd.titlebar_padding,
            .align_y = .center,
        },
        .hit = .generic,
        .children = root.titlebar_children_end[0..titlebar_children_end_count],
    };

    root.window_children[root.window_children_count] = .{
        .id = Ids.titlebar,
        .kind = .stack,
        .layout = .{ .width = .fill, .height = .{ .fixed = theme.csd.titlebar_height } },
        .children = root.titlebar_layers[0..4],
    };
    root.window_children_count += 1;
}

pub fn ownsId(id: ui.SurfaceId) bool {
    return id.eql(Ids.titlebar) or
        id.eql(Ids.background) or
        id.eql(Ids.title);
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
    for (root.minimize_ids[0..root.minimize_ids_count]) |id| {
        if (pressed_id.eql(id)) return minimizePressed(root);
    }
    for (root.maximize_ids[0..root.maximize_ids_count]) |id| {
        if (pressed_id.eql(id)) return maximizePressed(root);
    }
    for (root.close_ids[0..root.close_ids_count]) |id| {
        if (pressed_id.eql(id)) return closePressed(root);
    }
    if (pressed_id.eql(Ids.titlebar) or
        pressed_id.eql(Ids.background) or
        pressed_id.eql(Ids.title))
    {
        return movePressed(root);
    }
    return .none;
}
