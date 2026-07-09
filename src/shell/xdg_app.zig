//! XDG toplevel window. Normal desktop window, optional debug overlays.

const std = @import("std");
const posix = std.posix;
const ow = @import("otter_wayland");
const wl = ow.wayland.client.wl;
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const utils = @import("otter_utils");
const geo = @import("otter_geo");

const root_mod = @import("../ui/root.zig");
const draw_mod = @import("../ui/draw.zig");
const csd_mod = @import("../ui/csd.zig");
const xdg_csd_mod = @import("xdg_csd.zig");
const frame_mod = @import("frame.zig");

pub const Options = struct {
    debug_overlay_mode: ui.DebugOverlayMode = .off,
};

pub const PressResult = union(enum) {
    none,
    input,
    damage: ui.SurfaceId,
    sidebar,
    csd: xdg_csd_mod.CsdAction,
};

pub fn run(allocator: std.mem.Allocator, options: Options) !void {
    var app = App{
        .allocator = allocator,
        .debug_overlay_mode = options.debug_overlay_mode,
    };
    try app.init();
    defer app.deinit();
    try app.loop();
}

pub const App = struct {
    allocator: std.mem.Allocator,
    conn: ow.Connection = undefined,
    keyboard: ow.Keyboard = undefined,
    seat_state: ow.SeatState = .{},
    toplevel: ow.XdgToplevel = .{},
    renderer: ?*ow.Renderer = null,
    font: ?*render.Font = null,
    text_system: ?render.text.TextSystem = null,
    text_scratch: render.text.ShapeScratch = .{},
    ui_state: root_mod.UiState = .{},
    damage: ow.DamageTracker = .{},
    root: root_mod.Root = .{},
    csd: xdg_csd_mod.Chrome = .{},
    redraw: frame_mod.Driver = .{},
    theme: theme_mod.Theme = .{},
    theme_path_buf: [std.fs.max_path_bytes]u8 = undefined,
    theme_path_len: usize = 0,
    theme_mtime_ns: ?i128 = null,
    pointer: geo.Point = .{ .x = 0, .y = 0 },
    surface_width: u16 = root_mod.Ids.panel_width + 48,
    surface_height: u16 = root_mod.Ids.panel_height + 48,
    prefered_decoration_type: theme_mod.Theme.DecorationTypes = undefined,
    scale: u31 = 1,
    running: bool = true,
    configured: bool = false,
    debug_overlay_mode: ui.DebugOverlayMode = .off,

    fn init(self: *App) !void {
        self.keyboard = try ow.Keyboard.init();
        self.keyboard.setCallbacks(.{ .on_key = onKey, .context = self });
        self.seat_state.keyboard = &self.keyboard;

        self.seat_state.setCallbacks(.{
            .on_enter = onPointerEnter,
            .on_motion = onPointerMotion,
            .on_leave = onPointerLeave,
            .on_button = onPointerButton,
            .context = self,
        });

        self.conn = .{
            .display = undefined,
            .registry = undefined,
            .callbacks = .{
                .on_seat_added = onSeatAdded,
                .context = self,
            },
        };
        try self.conn.init();
        self.seat_state.cursor_shape_manager = self.conn.cursor_shape_manager;
        try self.conn.roundtrip();

        self.theme = theme_mod.loadTheme(self.allocator);
        self.initThemeReload();
        self.font = try render.Font.init(self.allocator, .{ .font_family = self.theme.fonts.font_family });
        try self.root.init(self.allocator);
        self.prefered_decoration_type = self.theme.decorations.prefered_decoration_type;
        const request_server_side_decorations = switch (self.prefered_decoration_type) {
            .server => true,
            else => false,
        };
        self.toplevel = try ow.XdgToplevel.createWithOptions(
            &self.conn,
            root_mod.Ids.app_name,
            root_mod.Ids.app_id,
            .{ .on_configure = onConfigure, .on_close = onClose, .context = self },
            .{ .request_server_side_decorations = request_server_side_decorations },
        );
        self.toplevel.bindListeners();
        self.toplevel.setMinSize(root_mod.Ids.panel_width + 32, root_mod.Ids.panel_height + 32 + if (self.prefered_decoration_type == .client or (self.prefered_decoration_type == .client_floating and !self.toplevel.current_state.maximized)) self.theme.csd.titlebar_height else 0);
        if (self.toplevel.wl_surface) |surface| {
            self.redraw.bind(surface, drawCallback, self);
        }
        self.ui_state.setDebugOverlayMode(self.debug_overlay_mode);
        try self.conn.roundtrip();
    }

    fn deinit(self: *App) void {
        if (self.redraw.frame_callback) |cb| cb.destroy();
        self.root.deinit();
        if (self.renderer) |r| r.deinit();
        if (self.text_system) |*ts| ts.deinit();
        if (self.font) |f| f.deinit();
        self.toplevel.destroy();
        self.conn.deinit();
    }

    fn loop(self: *App) !void {
        var pollfds = [_]posix.pollfd{.{ .fd = self.conn.display.getFd(), .events = posix.POLL.IN, .revents = 0 }};

        while (self.running) {
            _ = self.conn.display.flush();
            const nfds = try posix.poll(&pollfds, 500);
            self.reloadThemeIfChanged();
            if (nfds == 0) continue;
            if (pollfds[0].revents & posix.POLL.IN != 0) {
                if (self.conn.dispatch() == error.WaylandDispatchFailed) break;
            }
            if (pollfds[0].revents & (posix.POLL.HUP | posix.POLL.ERR) != 0) break;
        }
    }

    fn createRenderer(self: *App) !void {
        const shm = self.conn.shm orelse return error.NoShm;
        if (self.renderer) |r| r.deinit();
        self.renderer = try ow.createRenderer(
            self.allocator,
            shm,
            self.surface_width,
            self.surface_height,
            self.toplevel.scale,
        );
    }

    fn initThemeReload(self: *App) void {
        const path = theme_mod.getThemeConfigPath(&self.theme_path_buf) orelse return;
        self.theme_path_len = path.len;
        self.theme_mtime_ns = themeStamp(path);
    }

    fn reloadThemeIfChanged(self: *App) void {
        if (self.theme_path_len == 0) return;
        const path = self.theme_path_buf[0..self.theme_path_len];
        const mtime_ns = themeStamp(path) orelse return;
        if (self.theme_mtime_ns != null and self.theme_mtime_ns.? == mtime_ns) return;

        const new_theme = theme_mod.loadTheme(self.allocator);
        const new_font = render.Font.init(self.allocator, .{ .font_family = new_theme.fonts.font_family }) catch return;

        if (self.text_system) |*ts| {
            ts.deinit();
            self.text_system = null;
        }
        if (self.font) |f| f.deinit();
        self.font = new_font;
        self.theme = new_theme;
        self.theme_mtime_ns = mtime_ns;
        requestFullRedraw(self);
    }

    fn draw(self: *App) void {
        const renderer = self.renderer orelse return;
        const font = self.font orelse return;
        const surface = self.toplevel.wl_surface orelse return;

        if (self.debug_overlay_mode != .off) {
            self.damage.markFullDamage();
        }

        self.ui_state.setDebugOverlayMode(self.debug_overlay_mode);
        draw_mod.draw(.{
            .root = &self.root,
            .ui_state = &self.ui_state,
            .damage = &self.damage,
            .font = font,
            .renderer = renderer,
            .surface = surface,
            .shell_label = "XDG toplevel root",
            .card_placement = .fill,
            .background = .{ .color = self.theme.colors.background_opaque },
            .theme = self.theme,
            .text_provider = self.textSystemProvider(),
            .maximized = self.toplevel.current_state.maximized,
            .active = self.toplevel.current_state.activated,
        });

        if (self.ui_state.debugOverlayMode() == .metrics) {
            self.redraw.request();
        }
    }

    fn pointerOpts(self: *const App) root_mod.PointerOpts {
        return .{ .debug_overlay = self.debug_overlay_mode != .off };
    }

    fn viewport(self: *const App) geo.Rect {
        return .{
            .x = 0,
            .y = 0,
            .width = self.surface_width,
            .height = self.surface_height,
        };
    }

    fn textSystemProvider(self: *App) ui.TextSystemProvider {
        return .{ .context = self, .ensure_fn = ensureTextSystemForUi };
    }

    fn ensureTextSystem(self: *App) ?ui.TextSystemAccess {
        if (self.text_system) |*ts| return .{ .text_system = ts, .scratch = &self.text_scratch };
        const font = self.font orelse return null;
        self.text_system = render.text.TextSystem.init(self.allocator, font) catch return null;
        return .{ .text_system = &self.text_system.?, .scratch = &self.text_scratch };
    }
};

fn drawCallback(ctx: *anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.draw();
}

fn onConfigure(width: u31, height: u31, _: ow.XdgToplevelState, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));

    const w: u16 = if (width > 0) @intCast(width) else app.surface_width;
    const h: u16 = if (height > 0) @intCast(height) else app.surface_height;
    const size_changed = w != app.surface_width or h != app.surface_height;
    const scale_changed = app.toplevel.scale != app.scale;

    app.surface_width = w;
    app.surface_height = h;
    app.scale = app.toplevel.scale;
    app.configured = true;

    if (size_changed or scale_changed or app.renderer == null) {
        app.createRenderer() catch {
            app.running = false;
            return;
        };
        if (app.toplevel.wl_surface) |surface| {
            surface.setBufferScale(@intCast(app.toplevel.scale));
        }
    }

    app.damage.markFullDamage();
    app.redraw.drawNow();
    if (app.toplevel.wl_surface) |surface| surface.commit();
}

fn onClose(ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    app.running = false;
}

fn onSeatAdded(seat: *wl.Seat, _: u32, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    seat.setListener(*ow.SeatState, ow.seatListener, &app.seat_state);
}

fn onPointerEnter(_: *wl.Surface, point: geo.Point, _: u32, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    app.pointer = point;
    const old_hover = app.ui_state.input.hovered;
    const old_active = app.ui_state.input.active;
    if (app.root.onPointerMotion(&app.ui_state, point, app.pointerOpts())) {
        requestInputRedraw(app, old_hover, old_active);
    }
    applyPointerCursor(app);
}

fn onPointerMotion(point: geo.Point, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    app.pointer = point;
    const old_hover = app.ui_state.input.hovered;
    const old_active = app.ui_state.input.active;
    if (app.root.onPointerMotion(&app.ui_state, point, app.pointerOpts())) {
        requestInputRedraw(app, old_hover, old_active);
    }
    applyPointerCursor(app);
}

fn onPointerLeave(_: *wl.Surface, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    const old_hover = app.ui_state.input.hovered;
    const old_active = app.ui_state.input.active;
    _ = app.ui_state.dispatch(.pointer_leave);
    if (!old_hover.eql(ui.SurfaceId.none) or !old_active.eql(ui.SurfaceId.none)) {
        requestInputRedraw(app, old_hover, old_active);
    } else if (app.debug_overlay_mode != .off) {
        app.redraw.request();
    }
}

fn onPointerButton(button: ow.MouseButton, state: ow.ButtonState, ctx: ?*anyopaque) void {
    if (!button.isLeft()) return;
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    if (state == .pressed) {
        const old_hover = app.ui_state.input.hovered;
        const old_active = app.ui_state.input.active;
        if (app.prefered_decoration_type == .client or (app.prefered_decoration_type == .client_floating and !app.toplevel.current_state.maximized)) {
            switch (app.csd.hit(app.theme, app.pointer, app.viewport())) {
                .resize => |edge| {
                    performCsdAction(app, .{ .resize = edge });
                    return;
                },
                else => {},
            }
        }
        switch (app.root.onPointerPress(&app.ui_state, app.pointer)) {
            .sidebar => {
                damageInputChange(app, old_hover, old_active);
                damageSidebar(app);
                app.redraw.request();
            },
            .damage => |id| {
                damageInputChange(app, old_hover, old_active);
                damageSurface(app, id);
                app.redraw.request();
            },
            .csd => |action| {
                performCsdAction(app, action);
                damageInputChange(app, old_hover, old_active);
                app.redraw.request();
            },
            .input => requestInputRedraw(app, old_hover, old_active),
            .none => if (app.debug_overlay_mode != .off) app.redraw.request(),
        }
        return;
    }
    const old_hover = app.ui_state.input.hovered;
    const old_active = app.ui_state.input.active;
    if (app.root.onPointerRelease(&app.ui_state, app.pointer)) {
        requestInputRedraw(app, old_hover, old_active);
    } else if (app.debug_overlay_mode != .off) {
        app.redraw.request();
    }
}

fn performCsdAction(app: *App, action: xdg_csd_mod.CsdAction) void {
    switch (action) {
        .close => app.running = false,
        .move => {
            if (app.toplevel.xdg_toplevel) |toplevel| {
                if (app.seat_state.seat) |seat| {
                    toplevel.move(seat, app.seat_state.last_button_serial);
                }
            }
        },
        .resize => |edge| {
            if (app.toplevel.xdg_toplevel) |toplevel| {
                if (app.seat_state.seat) |seat| {
                    toplevel.resize(seat, app.seat_state.last_button_serial, xdg_csd_mod.xdgResizeEdge(edge));
                }
            }
        },
        .minimize => {
            if (app.toplevel.xdg_toplevel) |toplevel| toplevel.setMinimized();
        },
        .maximize => {
            if (app.toplevel.xdg_toplevel) |toplevel| {
                if (app.toplevel.current_state.maximized) {
                    toplevel.unsetMaximized();
                } else {
                    toplevel.setMaximized();
                }
            }
        },
    }
}

fn applyPointerCursor(app: *App) void {
    if (app.prefered_decoration_type == .client or (app.prefered_decoration_type == .client_floating and !app.toplevel.current_state.maximized)) {
        if (app.csd.resizeCursor(app.theme, app.pointer, app.viewport())) |edge| {
            app.seat_state.setCursorShape(xdg_csd_mod.resizeCursorShape(edge));
            return;
        }
    }
    root_mod.Root.applyPointerCursor(&app.seat_state, &app.ui_state);
}

fn requestFullRedraw(app: *App) void {
    app.damage.markFullDamage();
    app.redraw.request();
}

fn requestInputRedraw(app: *App, old_hover: ui.SurfaceId, old_active: ui.SurfaceId) void {
    if (app.debug_overlay_mode != .off) {
        requestFullRedraw(app);
        return;
    }
    damageInputChange(app, old_hover, old_active);
    app.redraw.request();
}

fn damageInputChange(app: *App, old_hover: ui.SurfaceId, old_active: ui.SurfaceId) void {
    damageSurface(app, old_hover);
    damageSurface(app, app.ui_state.input.hovered);
    damageSurface(app, old_active);
    damageSurface(app, app.ui_state.input.active);
}

fn damageSurface(app: *App, id: ui.SurfaceId) void {
    if (id.eql(ui.SurfaceId.none)) return;
    const element = app.ui_state.findElement(id) orelse {
        app.damage.markFullDamage();
        return;
    };
    const viewport = geo.Rect{
        .x = 0,
        .y = 0,
        .width = app.surface_width,
        .height = app.surface_height,
    };
    const padded = element.rect.addPadding(geo.Padding.uniform(4));
    app.damage.addRect(padded.intersection(viewport) orelse element.rect);
}

fn damageSidebar(app: *App) void {
    const width: geo.Size = @min(app.surface_width, app.root.sidebar_width);
    app.damage.addRect(.{
        .x = 0,
        .y = 0,
        .width = width,
        .height = app.surface_height,
    });
}

fn themeStamp(path: []const u8) ?i128 {
    const stat = std.Io.Dir.cwd().statFile(utils.io.get(), path, .{}) catch return null;
    return @as(i128, stat.mtime.nanoseconds);
}

fn onKey(keysym: u32, _: []const u8, state: ow.KeyState, mods: ow.keyboard.Modifiers, ctx: ?*anyopaque) void {
    if (state != .pressed) return;
    const app: *App = @ptrCast(@alignCast(ctx orelse return));

    if (ui.isDebugOverlayShortcut(keysym, mods.ctrl, mods.shift)) {
        app.debug_overlay_mode = app.ui_state.cycleDebugOverlay();
        app.damage.markFullDamage();
        app.redraw.request();
    }
}

fn ensureTextSystemForUi(ctx: ?*anyopaque) ?ui.TextSystemAccess {
    const app: *App = @ptrCast(@alignCast(ctx orelse return null));
    return app.ensureTextSystem();
}
