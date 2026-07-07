//! Minimal client-side decoration chrome for XDG windows.

const geo = @import("otter_geo");
const theme_mod = @import("otter_theme");
const ui = @import("otter_ui");
const ow = @import("otter_wayland");

const csd_mod = @import("../ui/csd.zig");
const ui_types = @import("../ui/ui_types.zig");

pub const Edge = ui_types.Edge;

pub const Hit = union(enum) {
    content,
    titlebar,
    button: ui.SurfaceId,
    resize: Edge,
};

pub const PressResult = union(enum) {
    content,
    close,
    minimize,
    maximize,
    move,
    resize: Edge,
};

pub const Chrome = struct {
    pub fn contentRect(viewport: geo.Rect) geo.Rect {
        return .{
            .x = viewport.x,
            .y = viewport.y + csd_mod.Ids.titlebar_height,
            .width = viewport.width,
            .height = viewport.height -| csd_mod.Ids.titlebar_height,
        };
    }

    pub fn titlebarRect(viewport: geo.Rect) geo.Rect {
        return .{
            .x = viewport.x,
            .y = viewport.y,
            .width = viewport.width,
            .height = csd_mod.Ids.titlebar_height,
        };
    }

    pub fn hit(self: *const Chrome, point: geo.Point, viewport: geo.Rect) Hit {
        _ = self;
        if (resizeEdge(point, viewport)) |edge| return .{ .resize = edge };
        if (point.y >= viewport.y + csd_mod.Ids.titlebar_height) return .content;
        return .titlebar;
    }

    pub fn resizeCursor(self: *const Chrome, point: geo.Point, viewport: geo.Rect) ?Edge {
        return switch (self.hit(point, viewport)) {
            .resize => |edge| edge,
            else => null,
        };
    }
};

fn resizeEdge(point: geo.Point, viewport: geo.Rect) ?Edge {
    const left = point.x < viewport.x + csd_mod.Ids.resize_margin;
    const right = point.x >= viewport.x + @as(i32, @intCast(viewport.width -| csd_mod.Ids.resize_margin));
    const top = point.y < viewport.y + csd_mod.Ids.resize_margin;
    const bottom = point.y >= viewport.y + @as(i32, @intCast(viewport.height -| csd_mod.Ids.resize_margin));

    if (top and left) return .top_left;
    if (top and right) return .top_right;
    if (bottom and left) return .bottom_left;
    if (bottom and right) return .bottom_right;
    if (top) return .top;
    if (bottom) return .bottom;
    if (left) return .left;
    if (right) return .right;
    return null;
}

pub fn xdgResizeEdge(edge: Edge) ow.wayland.client.xdg.Toplevel.ResizeEdge {
    return switch (edge) {
        .top => .top,
        .bottom => .bottom,
        .left => .left,
        .right => .right,
        .top_left => .top_left,
        .top_right => .top_right,
        .bottom_left => .bottom_left,
        .bottom_right => .bottom_right,
    };
}

pub fn resizeCursorShape(edge: Edge) ow.wayland.client.wp.CursorShapeDeviceV1.Shape {
    return switch (edge) {
        .top => .n_resize,
        .bottom => .s_resize,
        .left => .w_resize,
        .right => .e_resize,
        .top_left => .nw_resize,
        .top_right => .ne_resize,
        .bottom_left => .sw_resize,
        .bottom_right => .se_resize,
    };
}
