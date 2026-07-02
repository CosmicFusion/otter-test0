//! Batches redraw requests into wl_surface.frame (one paint per compositor tick).
//!
//! Input handlers call request(); the frame listener actually paints.

const ow = @import("otter_wayland");
const wl = ow.wayland.client.wl;

pub const Driver = struct {
    needs_redraw: bool = false,
    frame_callback: ?*wl.Callback = null,
    surface: ?*wl.Surface = null,
    draw_ctx: ?*anyopaque = null,
    draw_fn: ?*const fn (*anyopaque) void = null,

    pub fn bind(self: *Driver, surface: *wl.Surface, draw_fn: *const fn (*anyopaque) void, draw_ctx: *anyopaque) void {
        self.surface = surface;
        self.draw_fn = draw_fn;
        self.draw_ctx = draw_ctx;
    }

    /// Mark dirty; schedule frame callback if we do not already have one pending.
    pub fn request(self: *Driver) void {
        self.needs_redraw = true;
        const surface = self.surface orelse return;
        if (self.frame_callback != null) return;

        self.frame_callback = surface.frame() catch return;
        self.frame_callback.?.setListener(*Driver, frameListener, self);
        surface.commit();
    }

    /// Paint immediately. Used on first configure before the event loop runs.
    pub fn drawNow(self: *Driver) void {
        const ctx = self.draw_ctx orelse return;
        if (self.draw_fn) |draw| draw(ctx);
        self.needs_redraw = false;
    }
};

fn frameListener(cb: *wl.Callback, event: wl.Callback.Event, driver: *Driver) void {
    switch (event) {
        .done => {
            cb.destroy();
            driver.frame_callback = null;
            if (driver.needs_redraw) {
                const ctx = driver.draw_ctx orelse return;
                if (driver.draw_fn) |draw| draw(ctx);
                driver.needs_redraw = false;
                if (driver.surface) |surface| surface.commit();
            }
        },
    }
}
