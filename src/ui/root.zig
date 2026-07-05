//! Root card: state, IDs, SD tree, pointer handling, damage helpers.
//!
//! **Add a button:** define a node in `buildCard()` and handle its id in `onPointerPress()`.

const std = @import("std");
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");
const ow = @import("otter_wayland");

const common_mod = @import("common.zig");
const welcome_mod = @import("welcome.zig");
const sidebar_mod = @import("sidebar.zig");

const Color = render.Color;

/// Surface IDs and layout numbers for this root. Bump `UiState` bucket sizes when the tree grows.
pub const Ids = struct {
    pub const panel_width: u16 = 400;
    pub const panel_height: u16 = 500;
    pub const damage_pad: i32 = 6;

    pub const card = ui.SurfaceId.namedComptime("root.card");
    pub const panel = ui.SurfaceId.namedComptime("root.panel");
    pub const layout_root = ui.SurfaceId.namedComptime("root.layout_root");
    pub const main_wrapper = ui.SurfaceId.namedComptime("root.main_wrapper");
};

pub const UiState = ui.UiState(.{
    .elements = 56,
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

pub const otter_icon_png = @embedFile("../assets/otter-shell-icon.png");

pub const Root = struct {
    // Root Structs
    main_count: usize = 0,
    card_layers: [2]ui.SurfaceNode = undefined,
    // Welcome Structs
    counter: u32 = 0,
    counter_text: [48]u8 = undefined,
    counter_text_len: usize = 0,
    icon: ?render.Image = null,
    counter_rect: ?geo.Rect = null,
    content: [5]ui.SurfaceNode = undefined,
    welcome_button_infos: [2]common_mod.ButtonInfo = undefined,
    // Sidebar structs
    sidebar_breakpoint: u16 = 1000,
    sidebar_width: u16 = 200,
    sidebar_layers: [2]ui.SurfaceNode = undefined,
    sidebar_collapsed: bool = false,
    sidebar_button_infos: [1]common_mod.ButtonInfo = undefined,
    // Sidebar toggle structs
    toggle_button_active: bool = false,
    //
    main_children: [2]ui.SurfaceNode = undefined,
    layout_children: [2]ui.SurfaceNode = undefined,

    pub fn init(self: *Root, allocator: std.mem.Allocator) !void {
        // Root init
        self.icon = render.Image.loadFromMemory(allocator, otter_icon_png) catch null;
        // Init Welcome
        welcome_mod.init(self) catch null;
    }

    pub fn deinit(self: *Root) void {
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

    /// Build the root card (fixed size). Hover state comes from `ui_state.input`.
    pub fn buildCard(self: *Root, ui_state: *const UiState, viewport: geo.Rect, title_text: []const u8) ui.SurfaceNode {
        self.main_count = 0;
        const theme = theme_mod.Theme{};
        const wide_mode = viewport.width > self.sidebar_breakpoint;
        const show_sidebar = wide_mode or self.sidebar_collapsed;
        self.toggle_button_active = !wide_mode;

        self.card_layers[0] = ui.SurfaceNode.panel(Ids.panel, .{ .width = .fill, .height = .fill }, .{
            .background = theme.panelColor(theme.surfaces.surface),
            .border = theme.surfaces.border_subtle,
            .shadow = Color.init(0, 0, 0, 72),
            .highlight_edge = Color.init(255, 255, 255, 12),
            .radius = theme.popup.border_radius,
            .border_width = 1,
        });

        welcome_mod.buildWelcomeCard(self, ui_state, theme, viewport, title_text);

        // Toggle button only exists below the breakpoint — above it, the
        // sidebar is forced on and there's nothing to toggle.
        if (self.toggle_button_active) {
            sidebar_mod.BuildSidebarToggle(self, ui_state, theme);
        }

        self.main_children[self.main_count] = .{
            .id = Ids.card,
            .kind = .stack,
            .layout = .{ .width = .fill, .height = .fill },
            .children = self.card_layers[0..2],
        };
        self.main_count += 1;

        const main_wrapper_node: ui.SurfaceNode = .{
            .id = Ids.main_wrapper,
            .kind = .column,
            .layout = .{
                .width = .fill,
                .height = .fill,
                .padding = ui.Padding.uniform(24),
                .gap = 12,
            },
            .children = self.main_children[0..self.main_count],
        };

        var layout_count: usize = 0;
        if (show_sidebar) {
            self.layout_children[0] = sidebar_mod.buildSidebar(self, theme);
            layout_count += 1;
        }
        self.layout_children[layout_count] = main_wrapper_node;
        layout_count += 1;

        return .{
            .id = Ids.layout_root,
            .kind = .row,
            .layout = .{ .width = .fill, .height = .fill },
            .children = self.layout_children[0..layout_count],
        };
    }

    pub fn captureRects(self: *Root, ui_state: *const UiState) void {
        welcome_mod.captureRects(self, ui_state);
        sidebar_mod.captureRects(self, ui_state);
    }

    pub fn onPointerMotion(
        self: *Root,
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
        var motion_handlers: [2]bool = undefined;
        motion_handlers[0] = welcome_mod.checkHover(self, old_hover, current, damage);
        motion_handlers[1] = sidebar_mod.checkHover(self, old_hover, current, damage);
        for (motion_handlers) |local_dirty| {
            if (local_dirty) {
                dirty = true;
                break;
            }
        }
        return dirty;
    }

    pub fn onPointerPress(
        self: *Root,
        ui_state: *UiState,
        point: geo.Point,
        damage: *ow.DamageTracker,
    ) PressResult {
        var handled = false;

        var press_handlers: [2]bool = undefined;
        // Press Events
        press_handlers[0] = welcome_mod.onPointerPress(self, ui_state, point, damage);
        press_handlers[1] = sidebar_mod.onPointerPress(self, ui_state, point, damage);
        // Check all events
        for (press_handlers) |local_handled| {
            if (local_handled) {
                handled = true;
                break;
            }
        }

        if (handled) {
            return .handled;
        } else {
            return .none;
        }
    }

    pub fn onPointerRelease(self: *Root, ui_state: *UiState, point: geo.Point, damage: *ow.DamageTracker) bool {
        var dirty = false;
        var release_handlers: [2]bool = undefined;
        // Release Events
        release_handlers[0] = welcome_mod.onPointerRelease(self, ui_state, point, damage);
        release_handlers[1] = sidebar_mod.onPointerRelease(self, ui_state, point, damage);
        // Check all events
        for (release_handlers) |local_dirty| {
            if (local_dirty) {
                dirty = true;
                break;
            }
        }
        return dirty;
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

    pub fn hoverChanged(old: ui.SurfaceId, current: ui.SurfaceId, id: ui.SurfaceId) bool {
        return old.eql(id) != current.eql(id);
    }

    pub fn damageRect(tracker: *ow.DamageTracker, rect: ?geo.Rect) void {
        if (rect) |r| tracker.addRect(padded(r));
    }

    pub fn padded(rect: geo.Rect) geo.Rect {
        return .{
            .x = rect.x - Ids.damage_pad,
            .y = rect.y - Ids.damage_pad,
            .width = rect.width + @as(geo.Size, @intCast(Ids.damage_pad * 2)),
            .height = rect.height + @as(geo.Size, @intCast(Ids.damage_pad * 2)),
        };
    }
};
