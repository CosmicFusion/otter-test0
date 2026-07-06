const std = @import("std");
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");
const ow = @import("otter_wayland");

const Color = render.Color;

const root_mod = @import("root.zig");
const common_mod = @import("common.zig");

pub const Ids = struct {
    pub const icon_size: u16 = 48;
    pub const body_font_size: u16 = 15;
    pub const title_font_size: u16 = 18;

    pub const content = ui.SurfaceId.namedComptime("root.content");
    pub const title = ui.SurfaceId.namedComptime("root.title");
    pub const icon = ui.SurfaceId.namedComptime("root.icon");
    pub const counter = ui.SurfaceId.namedComptime("root.counter");
    pub const increment = ui.SurfaceId.namedComptime("root.increment");
    pub const reset = ui.SurfaceId.namedComptime("root.reset");
};

pub fn init(root: *root_mod.Root) !void {
    refreshCounterText(root);
}

pub fn buildWelcomeCard(root: *root_mod.Root, ui_state: *const root_mod.UiState, theme: theme_mod.Theme, viewport: geo.Rect, title_text: []const u8) void {
    _ = viewport;

    root.content[0] = ui.SurfaceNode.label(Ids.title, title_text, Ids.title_font_size, theme.colors.foreground);
    root.content[0].layout = .{ .width = .fill, .height = .{ .fixed = 24 }, .align_x = .center };

    root.content[1] = ui.SurfaceNode.image(Ids.icon, .{
        .image = if (root.icon) |*img| @as(?*const render.Image, img) else null,
        .fit = .contain,
    });
    root.content[1].layout = .{ .width = .{ .fixed = Ids.icon_size }, .height = .{ .fixed = Ids.icon_size }, .align_x = .center };

    root.content[2] = ui.SurfaceNode.label(Ids.counter, counterSlice(root), Ids.body_font_size, theme.colors.muted);
    root.content[2].layout = .{ .width = .fill, .height = .{ .fixed = 22 }, .align_x = .center };

    // Setup Increment Button

    {
        const id = Ids.increment;
        const text = "Increment";

        root.content[3] = .{
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

        root.welcome_button_infos[0] = .{
            .id = id,
            .rect = null,
            .on_pressed = incrementPressed,
        };
    }

    // Setup Reset Button

    {
        const id = Ids.reset;
        const text = "Reset";

        root.content[4] = .{
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

        root.welcome_button_infos[1] = .{
            .id = id,
            .rect = null,
            .on_pressed = resetPressed,
        };
    }

    root.card_layers[1] = .{
        .id = Ids.content,
        .kind = .column,
        .layout = .{
            .width = .fill,
            .height = .fill,
            .padding = ui.Padding.uniform(20),
            .gap = 12,
            .align_x = .center,
        },
        .children = root.content[0..5],
    };
}

fn incrementPressed(root: *root_mod.Root, info: common_mod.ButtonInfo, damage: *ow.DamageTracker) void {
    root_mod.Root.damageRect(damage, info.rect);
    root.counter +%= 1;
    refreshCounterText(root);
    damageCounter(root, damage);
}

fn resetPressed(root: *root_mod.Root, info: common_mod.ButtonInfo, damage: *ow.DamageTracker) void {
    root_mod.Root.damageRect(damage, info.rect);
    root.counter = 0;
    refreshCounterText(root);
    damageCounter(root, damage);
}

fn counterSlice(root: *const root_mod.Root) []const u8 {
    return root.counter_text[0..root.counter_text_len];
}

fn refreshCounterText(root: *root_mod.Root) void {
    const written = std.fmt.bufPrint(root.counter_text[0..], "Clicked {d} time{s}", .{
        root.counter,
        if (root.counter == 1) "" else "s",
    }) catch return;
    root.counter_text_len = written.len;
}

fn damageCounter(root: *const root_mod.Root, tracker: *ow.DamageTracker) void {
    if (root.counter_rect) |rect| {
        tracker.addRect(root_mod.Root.padded(rect));
    }
}

pub fn checkHover(
    root: *root_mod.Root,
    old_hover: ui.SurfaceId,
    current: ui.SurfaceId,
    damage: *ow.DamageTracker,
) bool {
    var dirty = false;
    for (root.welcome_button_infos) |info| {
        if (root_mod.Root.hoverChanged(old_hover, current, info.id)) {
            root_mod.Root.damageRect(damage, info.rect);
            dirty = true;
        }
    }
    return dirty;
}

pub fn checkPress(root: *root_mod.Root, pressed_id: ui.SurfaceId, damage: *ow.DamageTracker) bool {
    for (root.welcome_button_infos) |info| {
        if (pressed_id.eql(info.id)) {
            info.on_pressed(root, info, damage);
            return true;
        }
    }
    return false;
}

pub fn checkRelease(root: *root_mod.Root, damage: *ow.DamageTracker) bool {
    var dirty = false;
    for (root.welcome_button_infos) |info| {
        root_mod.Root.damageRect(damage, info.rect);
        dirty = true;
    }
    return dirty;
}

pub fn captureRects(root: *root_mod.Root, ui_state: *const root_mod.UiState) void {
    if (ui_state.findElement(Ids.counter)) |element| root.counter_rect = element.rect;
    for (&root.welcome_button_infos) |*info| {
        if (ui_state.findElement(info.id)) |element| info.rect = element.rect;
    }
}
