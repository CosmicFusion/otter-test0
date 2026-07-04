//! Demo card: state, IDs, SD tree, pointer handling, damage helpers.
//!
//! **Add a button:** define a node in `buildCard()` and handle its id in `onPointerPress()`.

const std = @import("std");
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");
const ow = @import("otter_wayland");

const Color = render.Color;

/// Surface IDs and layout numbers for this demo. Bump `UiState` bucket sizes when the tree grows.
pub const Ids = struct {
    pub const panel_width: u16 = 320;
    pub const panel_height: u16 = 220;
    pub const icon_size: u16 = 48;
    pub const body_font_size: u16 = 15;
    pub const title_font_size: u16 = 18;
    pub const damage_pad: i32 = 6;

    pub const card = ui.SurfaceId.namedComptime("demo.card");
    pub const panel = ui.SurfaceId.namedComptime("demo.panel");
    pub const content = ui.SurfaceId.namedComptime("demo.content");
    pub const title = ui.SurfaceId.namedComptime("demo.title");
    pub const icon = ui.SurfaceId.namedComptime("demo.icon");
    pub const counter = ui.SurfaceId.namedComptime("demo.counter");
    pub const increment = ui.SurfaceId.namedComptime("demo.increment");
    pub const reset = ui.SurfaceId.namedComptime("demo.reset");
};

pub const UiState = ui.UiState(.{
    .elements = 48,
    .hit_regions = 9,
    .overlays = 1,
    .focus_scopes = 1,
    .scroll_states = 0,
    .text_states = 1,
});

pub const CardPlacement = enum {
    /// Layer shell: surface matches the card size.
    fill,
    /// XDG window: center the card in a larger viewport.
    center,
};

pub const PressResult = enum { none, handled };

pub const PointerOpts = struct {
    debug_overlay: bool = false,
};

const otter_icon_png = @embedFile("../assets/otter-shell-icon.png");

pub const ButtonInfo = struct {
    id: ui.SurfaceId,
    rect: ?geo.Rect,
    on_pressed: *const fn (self: *Demo, info: ButtonInfo, damage: *ow.DamageTracker) void,
};

pub const Demo = struct {
    counter: u32 = 0,
    counter_text: [48]u8 = undefined,
    counter_text_len: usize = 0,
    icon: ?render.Image = null,
    counter_rect: ?geo.Rect = null,
    card_layers: [2]ui.SurfaceNode = undefined,
    content: [5]ui.SurfaceNode = undefined,
    button_infos: [2]ButtonInfo = undefined,

    pub fn init(self: *Demo, allocator: std.mem.Allocator) !void {
        self.icon = render.Image.loadFromMemory(allocator, otter_icon_png) catch null;
        self.refreshCounterText();
    }

    pub fn deinit(self: *Demo) void {
        if (self.icon) |*img| img.deinit();
    }

    pub fn cardRect(viewport: geo.Rect, placement: CardPlacement) geo.Rect {
        return switch (placement) {
            .fill => viewport,
            .center => .{
                .x = @intCast(@max(0, (viewport.width - Ids.panel_width) / 2)),
                .y = @intCast(@max(0, (viewport.height - Ids.panel_height) / 2)),
                .width = Ids.panel_width,
                .height = Ids.panel_height,
            },
        };
    }

    /// Build the demo card (fixed size). Hover state comes from `ui_state.input`.
    pub fn buildCard(self: *Demo, ui_state: *const UiState, title_text: []const u8) ui.SurfaceNode {
        const theme = theme_mod.Theme{};

        self.content[0] = ui.SurfaceNode.label(Ids.title, title_text, Ids.title_font_size, theme.colors.foreground);
        self.content[0].layout = .{ .width = .fill, .height = .{ .fixed = 24 }, .align_x = .center };

        self.content[1] = ui.SurfaceNode.image(Ids.icon, .{
            .image = if (self.icon) |*img| @as(?*const render.Image, img) else null,
            .fit = .contain,
        });
        self.content[1].layout = .{ .width = .{ .fixed = Ids.icon_size }, .height = .{ .fixed = Ids.icon_size }, .align_x = .center };

        self.content[2] = ui.SurfaceNode.label(Ids.counter, self.counterSlice(), Ids.body_font_size, theme.colors.muted);
        self.content[2].layout = .{ .width = .fill, .height = .{ .fixed = 22 }, .align_x = .center };

        // Setup Increment Button

        {
            const id = Ids.increment;
            const text = "Increment";

            self.content[3] = .{
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

            self.button_infos[0] = .{
                .id = id,
                .rect = null,
                .on_pressed = incrementPressed,
            };
        }

        // Setup Reset Button

        {
            const id = Ids.reset;
            const text = "Reset";

            self.content[4] = .{
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

            self.button_infos[1] = .{
                .id = id,
                .rect = null,
                .on_pressed = ResetPressed,
            };
        }
        self.card_layers[1] = .{
            .id = Ids.content,
            .kind = .column,
            .layout = .{
                .width = .fill,
                .height = .fill,
                .padding = ui.Padding.uniform(20),
                .gap = 12,
                .align_x = .center,
            },
            .children = self.content[0..5],
        };

        self.card_layers[0] = ui.SurfaceNode.panel(Ids.panel, .{ .width = .fill, .height = .fill }, .{
            .background = theme.panelColor(theme.surfaces.surface),
            .border = theme.surfaces.border_subtle,
            .shadow = Color.init(0, 0, 0, 72),
            .highlight_edge = Color.init(255, 255, 255, 12),
            .radius = theme.popup.border_radius,
            .border_width = 1,
        });

        return .{
            .id = Ids.card,
            .kind = .stack,
            .layout = .{ .width = .{ .fixed = Ids.panel_width }, .height = .{ .fixed = Ids.panel_height } },
            .children = self.card_layers[0..2],
        };
    }

    pub fn captureRects(self: *Demo, ui_state: *const UiState) void {
        if (ui_state.findElement(Ids.counter)) |element| self.counter_rect = element.rect;
        for (&self.button_infos) |*info| {
            if (ui_state.findElement(info.id)) |element| info.rect = element.rect;
        }
    }

    pub fn applyPointerCursor(seat_state: *ow.SeatState, ui_state: *const UiState) void {
        const point = ui_state.input.pointer orelse {
            seat_state.setCursorShape(.default);
            return;
        };
        const hit = ui_state.hitTest(point) orelse {
            seat_state.setCursorShape(.default);
            return;
        };
        seat_state.setCursorShape(switch (hit.kind) {
            .button, .icon_button => .pointer,
            else => .default,
        });
    }

    fn hoverChanged(old: ui.SurfaceId, current: ui.SurfaceId, id: ui.SurfaceId) bool {
        return old.eql(id) != current.eql(id);
    }

    fn damageRect(tracker: *ow.DamageTracker, rect: ?geo.Rect) void {
        if (rect) |r| tracker.addRect(padded(r));
    }

    pub fn onPointerMotion(
        self: *Demo,
        ui_state: *UiState,
        point: geo.Point,
        damage: *ow.DamageTracker,
        opts: PointerOpts,
    ) bool {
        const old_hover = ui_state.input.hovered;
        _ = ui_state.dispatch(.{ .pointer_motion = point });

        if (opts.debug_overlay) return true;

        const current = ui_state.input.hovered;
        var dirty = false;

        // Check every button that paints hover state. Do not return early inside the loop.
        for (self.button_infos) |info| {
            if (hoverChanged(old_hover, current, info.id)) {
                damageRect(damage, info.rect);
                dirty = true;
            }
        }

        return dirty;
    }

    fn incrementPressed(self: *Demo, info: ButtonInfo, damage: *ow.DamageTracker) void {
        damageRect(damage, info.rect);
        self.counter +%= 1;
        self.refreshCounterText();
        self.damageCounter(damage);
    }

    fn ResetPressed(self: *Demo, info: ButtonInfo, damage: *ow.DamageTracker) void {
        damageRect(damage, info.rect);
        self.counter = 0;
        self.refreshCounterText();
        self.damageCounter(damage);
    }

    pub fn onPointerPress(
        self: *Demo,
        ui_state: *UiState,
        point: geo.Point,
        damage: *ow.DamageTracker,
    ) PressResult {
        const press = ui_state.dispatch(.{ .button_press = .{ .point = point, .button = 1 } });

        var handled = false;

        for (self.button_infos) |info| {
            if (press.id.eql(info.id)) {
                info.on_pressed(self, info, damage);
                handled = true;
            }
        }
        if (handled) {
            return .handled;
        } else {
            return .none;
        }
    }

    pub fn onPointerRelease(self: *Demo, ui_state: *UiState, point: geo.Point, damage: *ow.DamageTracker) bool {
        var dirty = false;
        for (self.button_infos) |info| {
            _ = ui_state.dispatch(.{ .button_release = .{ .point = point, .button = 1 } });
            damageRect(damage, info.rect);
            dirty = true;
        }
        return dirty;
    }

    fn counterSlice(self: *const Demo) []const u8 {
        return self.counter_text[0..self.counter_text_len];
    }

    fn refreshCounterText(self: *Demo) void {
        const written = std.fmt.bufPrint(self.counter_text[0..], "Clicked {d} time{s}", .{
            self.counter,
            if (self.counter == 1) "" else "s",
        }) catch return;
        self.counter_text_len = written.len;
    }

    fn damageCounter(self: *const Demo, tracker: *ow.DamageTracker) void {
        if (self.counter_rect) |rect| {
            tracker.addRect(.{
                .x = rect.x - Ids.damage_pad,
                .y = rect.y - Ids.damage_pad,
                .width = @intCast(@max(0, Ids.panel_width - 40)),
                .height = rect.height + @as(geo.Size, @intCast(Ids.damage_pad * 2)),
            });
        }
    }

    fn padded(rect: geo.Rect) geo.Rect {
        return .{
            .x = rect.x - Ids.damage_pad,
            .y = rect.y - Ids.damage_pad,
            .width = rect.width + @as(geo.Size, @intCast(Ids.damage_pad * 2)),
            .height = rect.height + @as(geo.Size, @intCast(Ids.damage_pad * 2)),
        };
    }
};

test "counter text updates" {
    var demo: Demo = .{};
    demo.counter +%= 1;
    demo.refreshCounterText();
    try std.testing.expectEqualStrings("Clicked 1 time", demo.counterSlice());
    demo.counter +%= 1;
    demo.refreshCounterText();
    try std.testing.expectEqualStrings("Clicked 2 times", demo.counterSlice());
}

test "card centers in a larger viewport" {
    const rect = Demo.cardRect(.{ .x = 0, .y = 0, .width = 400, .height = 300 }, .center);
    try std.testing.expectEqual(@as(geo.SizeSigned, 40), rect.x);
    try std.testing.expectEqual(@as(geo.SizeSigned, 40), rect.y);
    try std.testing.expectEqual(Ids.panel_width, rect.width);
}
