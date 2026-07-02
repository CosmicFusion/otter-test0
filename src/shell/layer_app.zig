//! Layer-shell overlay (`zwlr_layer_shell_v1`).
//!
//! Top-right popup; click outside the card dismisses. UI lives in `ui/demo.zig`.

const std = @import("std");
const posix = std.posix;
const ow = @import("otter_wayland");
const wl = ow.wayland.client.wl;
const zwlr = ow.wayland.client.zwlr;
const render = @import("otter_render");
const ui = @import("otter_ui");
const theme_mod = @import("otter_theme");
const geo = @import("otter_geo");

const demo_mod = @import("../ui/demo.zig");
const draw_mod = @import("../ui/draw.zig");
const frame_mod = @import("frame.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    var app = App{ .allocator = allocator };
    try app.init();
    defer app.deinit();
    try app.loop();
}

const App = struct {
    allocator: std.mem.Allocator,
    conn: ow.Connection = undefined,
    seat_state: ow.SeatState = .{},
    surface: ?*wl.Surface = null,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,
    renderer: ?*ow.Renderer = null,
    font: ?*render.Font = null,
    text_system: ?render.text.TextSystem = null,
    text_scratch: render.text.ShapeScratch = .{},
    ui_state: demo_mod.UiState = .{},
    damage: ow.DamageTracker = .{},
    demo: demo_mod.Demo = .{},
    redraw: frame_mod.Driver = .{},
    pointer: geo.Point = .{ .x = 0, .y = 0 },
    width: u16 = demo_mod.Ids.panel_width,
    height: u16 = demo_mod.Ids.panel_height,
    scale: u31 = 1,
    running: bool = true,

    fn init(self: *App) !void {
        self.seat_state.setCallbacks(.{
            .on_enter = onPointerEnter,
            .on_motion = onPointerMotion,
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

        const theme = theme_mod.Theme{};
        self.font = try render.Font.init(self.allocator, .{ .font_family = theme.fonts.font_family });
        try self.demo.init(self.allocator);
        try self.createLayerSurface();
    }

    fn deinit(self: *App) void {
        if (self.redraw.frame_callback) |cb| cb.destroy();
        self.demo.deinit();
        if (self.renderer) |r| r.deinit();
        if (self.text_system) |*ts| ts.deinit();
        if (self.font) |f| f.deinit();
        if (self.layer_surface) |ls| ls.destroy();
        if (self.surface) |s| s.destroy();
        self.conn.deinit();
    }

    fn loop(self: *App) !void {
        var pollfds = [_]posix.pollfd{.{ .fd = self.conn.display.getFd(), .events = posix.POLL.IN, .revents = 0 }};

        while (self.running) {
            _ = self.conn.display.flush();
            const nfds = try posix.poll(&pollfds, -1);
            if (nfds == 0) continue;
            if (pollfds[0].revents & posix.POLL.IN != 0) {
                if (self.conn.dispatch() == error.WaylandDispatchFailed) break;
            }
            if (pollfds[0].revents & (posix.POLL.HUP | posix.POLL.ERR) != 0) break;
        }
    }

    fn createLayerSurface(self: *App) !void {
        const compositor = self.conn.compositor orelse return error.NoCompositor;
        const layer_shell = self.conn.layer_shell orelse return error.NoLayerShell;

        const surface = try compositor.createSurface();
        surface.setListener(*App, surfaceListener, self);
        try ow.setSurfaceTransparent(compositor, surface);

        const layer = try layer_shell.getLayerSurface(surface, null, .top, "otter-examples-layer");
        layer.setSize(self.width, self.height);
        layer.setAnchor(.{ .top = true, .right = true });
        layer.setMargin(48, 32, 0, 0);
        layer.setKeyboardInteractivity(.none);
        layer.setExclusiveZone(-1);
        layer.setListener(*App, layerListener, self);

        self.surface = surface;
        self.layer_surface = layer;
        self.redraw.bind(surface, drawCallback, self);
        surface.commit();
        try self.conn.roundtrip();
    }

    fn configure(self: *App, serial: u32, width: u32, height: u32) void {
        if (self.layer_surface) |ls| ls.ackConfigure(serial);
        self.width = @intCast(if (width == 0) self.width else width);
        self.height = @intCast(if (height == 0) self.height else height);
        if (self.surface) |s| s.setBufferScale(@intCast(self.scale));
        if (self.renderer) |r| {
            r.resize(self.width, self.height, self.scale) catch return;
        } else if (self.conn.shm) |shm| {
            self.renderer = ow.createRenderer(self.allocator, shm, self.width, self.height, self.scale) catch return;
        }
        self.damage.markFullDamage();
        self.redraw.drawNow();
        if (self.surface) |s| s.commit();
    }

    fn draw(self: *App) void {
        const renderer = self.renderer orelse return;
        const font = self.font orelse return;
        const surface = self.surface orelse return;

        draw_mod.draw(.{
            .demo = &self.demo,
            .ui_state = &self.ui_state,
            .damage = &self.damage,
            .font = font,
            .renderer = renderer,
            .surface = surface,
            .shell_label = "Layer shell demo",
            .card_placement = .fill,
            .background = .transparent,
            .text_provider = self.textSystemProvider(),
        });
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

fn onSeatAdded(seat: *wl.Seat, _: u32, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    app.seat_state.seat = seat;
    seat.setListener(*ow.SeatState, ow.seatListener, &app.seat_state);
}

fn onPointerEnter(_: *wl.Surface, point: geo.Point, _: u32, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    app.pointer = point;
    if (app.demo.onPointerMotion(&app.ui_state, point, &app.damage, .{})) {
        app.redraw.request();
    }
    demo_mod.Demo.applyPointerCursor(&app.seat_state, &app.ui_state);
}

fn onPointerMotion(point: geo.Point, ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    app.pointer = point;
    if (app.demo.onPointerMotion(&app.ui_state, point, &app.damage, .{})) {
        app.redraw.request();
    }
    demo_mod.Demo.applyPointerCursor(&app.seat_state, &app.ui_state);
}

fn onPointerButton(button: ow.MouseButton, state: ow.ButtonState, ctx: ?*anyopaque) void {
    if (!button.isLeft()) return;
    const app: *App = @ptrCast(@alignCast(ctx orelse return));
    if (state == .pressed) {
        if (app.demo.onPointerPress(&app.ui_state, app.pointer, &app.damage) == .handled) {
            app.redraw.request();
            return;
        }
        app.running = false;
        return;
    }
    if (app.demo.onPointerRelease(&app.ui_state, app.pointer, &app.damage)) {
        app.redraw.request();
    }
}

fn layerListener(_: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, app: *App) void {
    switch (event) {
        .configure => |cfg| app.configure(cfg.serial, cfg.width, cfg.height),
        .closed => app.running = false,
    }
}

fn surfaceListener(_: *wl.Surface, event: wl.Surface.Event, app: *App) void {
    switch (event) {
        .preferred_buffer_scale => |scale| {
            const new_scale: u31 = @intCast(@max(1, scale.factor));
            if (app.scale == new_scale) return;
            app.scale = new_scale;
            if (app.surface) |s| {
                s.setBufferScale(new_scale);
                if (app.renderer) |r| r.resize(app.width, app.height, new_scale) catch return;
                app.damage.markFullDamage();
                app.redraw.request();
            }
        },
        .enter, .leave, .preferred_buffer_transform => {},
    }
}

fn ensureTextSystemForUi(ctx: ?*anyopaque) ?ui.TextSystemAccess {
    const app: *App = @ptrCast(@alignCast(ctx orelse return null));
    return app.ensureTextSystem();
}
