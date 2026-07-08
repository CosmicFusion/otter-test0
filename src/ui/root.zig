//! Root card: state, IDs, SD tree, pointer handling.
//!
//! **Add a button:** define a node in `buildCard()` and handle its id in `onPointerPress()`.

const std = @import("std");
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");
const ow = @import("otter_wayland");

const welcome_mod = @import("welcome.zig");
const sidebar_mod = @import("sidebar.zig");
const top_controls_mod = @import("top_controls.zig");
const csd_mod = @import("csd.zig");
const xdg_app_mod = @import("../shell/xdg_app.zig");

/// Surface IDs and layout numbers for this root. Bump `UiState` bucket sizes when the tree grows.
pub const Ids = struct {
    pub const app_name = "Otter Examples";
    pub const app_id = "otter-examples";

    pub const panel_width: u16 = 400;
    pub const panel_height: u16 = 500;

    pub const card = ui.SurfaceId.namedComptime("root.card");
    pub const panel = ui.SurfaceId.namedComptime("root.panel");
    pub const layout_root = ui.SurfaceId.namedComptime("root.layout_root");
    pub const window_root = ui.SurfaceId.namedComptime("root.window_root");
    pub const main_wrapper = ui.SurfaceId.namedComptime("root.main_wrapper");
};

pub const UiState = ui.UiState(.{
    .elements = 48,
    .hit_regions = 16,
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
    content: [5]ui.SurfaceNode = undefined,
    // Sidebar structs
    sidebar_breakpoint: u16 = 1000,
    sidebar_width: u16 = 200,
    sidebar_layers: [2]ui.SurfaceNode = undefined,
    sidebar_overlay: ui.SurfaceNode = undefined,
    sidebar_visible: bool = false,
    // Top controls structs
    toggle_button_shown: bool = false,
    top_controls: [2]ui.SurfaceNode = undefined,
    // CSD structs
    window_children_count: usize = 0,
    titlebar_layers: [2]ui.SurfaceNode = undefined,
    titlebar_children: [4]ui.SurfaceNode = undefined,
    //
    window_children: [2]ui.SurfaceNode = undefined,
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
    pub fn buildCard(self: *Root, viewport: geo.Rect, title_text: []const u8, theme: theme_mod.Theme, maximized: bool) ui.SurfaceNode {
        self.main_count = 0;
        self.window_children_count = 0;
        const wide_mode = viewport.width > self.sidebar_breakpoint;
        self.toggle_button_shown = !wide_mode;

        self.card_layers[0] = ui.SurfaceNode.panel(Ids.panel, .{ .width = .fill, .height = .fill }, .{
            .background = theme.panelColor(theme.surfaces.surface),
            .border = theme.surfaces.border_subtle,
            .shadow = theme.surfaces.shadow,
            .highlight_edge = theme.surfaces.highlight_edge,
            .radius = theme.popup.border_radius,
            .border_width = 1,
        });

        if (theme.decorations.prefered_decoration_type == .client or (theme.decorations.prefered_decoration_type == .client_floating) and !maximized) {
            csd_mod.buildTitlebar(self, Ids.app_name, theme, maximized);
        }
        top_controls_mod.buildTopControls(self);
        welcome_mod.buildWelcomeCard(self, theme, viewport, title_text);

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

        if (wide_mode) {
            // Sidebar shares space with main content, side by side.
            self.layout_children[0] = sidebar_mod.buildSidebar(self, theme);
            self.layout_children[1] = main_wrapper_node;

            self.window_children[self.window_children_count] = .{
                .id = Ids.layout_root,
                .kind = .row,
                .layout = .{ .width = .fill, .height = .fill },
                .children = self.layout_children[0..2],
            };
        } else {
            // Narrow mode: main content always fills the viewport. Floating
            // surfaces are queued through UiFrame overlays after layout.
            self.layout_children[0] = main_wrapper_node;

            self.window_children[self.window_children_count] = .{
                .id = Ids.layout_root,
                .kind = .stack,
                .layout = .{ .width = .fill, .height = .fill },
                .children = self.layout_children[0..1],
            };
        }

        return .{
            .id = Ids.window_root,
            .kind = .column,
            .layout = .{ .width = .fill, .height = .fill },
            .children = self.window_children[0 .. self.window_children_count + 1],
        };
    }

    pub fn queueOverlays(self: *Root, frame: anytype, viewport: geo.Rect, theme: theme_mod.Theme) void {
        if (viewport.width > self.sidebar_breakpoint or !self.sidebar_visible) return;

        self.sidebar_overlay = sidebar_mod.buildSidebar(self, theme);
        frame.queueOverlay(.{
            .id = sidebar_mod.Ids.root,
            .anchor = .{ .rect = .{
                .x = 0,
                .y = 0,
                .width = 0,
                .height = viewport.height,
            } },
            .placement = .end,
            .size = .{
                .x = @intCast(self.sidebar_width),
                .y = @intCast(viewport.height),
            },
            .node = &self.sidebar_overlay,
        }) catch {};
    }

    pub fn onPointerMotion(
        self: *Root,
        ui_state: *UiState,
        point: geo.Point,
        opts: PointerOpts,
    ) bool {
        _ = self;
        const old_hover = ui_state.input.hovered;
        _ = ui_state.dispatch(.{ .pointer_motion = point });
        if (opts.debug_overlay) return true;
        return !old_hover.eql(ui_state.input.hovered);
    }

    pub fn onPointerPress(
        self: *Root,
        ui_state: *UiState,
        point: geo.Point,
    ) xdg_app_mod.PressResult {
        const press = ui_state.dispatch(.{ .button_press = .{ .point = point, .button = 1 } });

        var result: xdg_app_mod.PressResult = if (press.id.eql(ui.SurfaceId.none)) .none else .input;
        result = mergePressResult(result, top_controls_mod.checkPress(self, press.id));
        result = mergePressResult(result, welcome_mod.checkPress(self, press.id));
        result = mergePressResult(result, sidebar_mod.checkPress(self, press.id));
        result = mergePressResult(result, csd_mod.checkPress(self, press.id));
        return result;
    }

    fn mergePressResult(current: xdg_app_mod.PressResult, local: xdg_app_mod.PressResult) xdg_app_mod.PressResult {
        return switch (local) {
            .sidebar => .sidebar,
            .damage => |id| .{ .damage = id },
            .csd => |action| .{ .csd = action },
            .input => if (std.meta.activeTag(current) == .none) .input else current,
            .none => current,
        };
    }

    pub fn onPointerRelease(self: *Root, ui_state: *UiState, point: geo.Point) bool {
        _ = self;
        const active = ui_state.input.active;
        _ = ui_state.dispatch(.{ .button_release = .{ .point = point, .button = 1 } });
        return !active.eql(ui.SurfaceId.none);
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
};
