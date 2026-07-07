//! Minimal client-side decoration chrome for XDG windows.

const geo = @import("otter_geo");
const theme_mod = @import("otter_theme");
const ui = @import("otter_ui");

pub const titlebar_height: u16 = 36;
pub const resize_margin: u16 = 6;

pub const Edge = enum {
    top,
    bottom,
    left,
    right,
    top_left,
    top_right,
    bottom_left,
    bottom_right,
};

pub const Ids = struct {
    pub const titlebar = ui.SurfaceId.namedComptime("csd.titlebar");
    pub const background = ui.SurfaceId.namedComptime("csd.background");
    pub const title = ui.SurfaceId.namedComptime("csd.title");
    pub const minimize = ui.SurfaceId.namedComptime("csd.minimize");
    pub const maximize = ui.SurfaceId.namedComptime("csd.maximize");
    pub const close = ui.SurfaceId.namedComptime("csd.close");
};

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
    layers: [2]ui.SurfaceNode = undefined,
    titlebar_children: [4]ui.SurfaceNode = undefined,

    pub fn contentRect(viewport: geo.Rect) geo.Rect {
        return .{
            .x = viewport.x,
            .y = viewport.y + titlebar_height,
            .width = viewport.width,
            .height = viewport.height -| titlebar_height,
        };
    }

    pub fn titlebarRect(viewport: geo.Rect) geo.Rect {
        return .{
            .x = viewport.x,
            .y = viewport.y,
            .width = viewport.width,
            .height = titlebar_height,
        };
    }

    pub fn buildTitlebar(self: *Chrome, title: []const u8, theme: theme_mod.Theme, maximized: bool) ui.SurfaceNode {
        self.layers[0] = ui.SurfaceNode.panel(Ids.background, .{ .width = .fill, .height = .fill }, .{
            .background = theme.panelColor(theme.surfaces.surface),
            .border = theme.surfaces.border_subtle,
            .highlight_edge = theme.surfaces.highlight_edge,
            .radius = 0,
            .border_width = 1,
        });

        self.titlebar_children[0] = ui.SurfaceNode.label(Ids.title, title, 13, theme.colors.foreground);
        self.titlebar_children[0].layout = .{
            .width = .fill,
            .height = .fill,
            .align_y = .center,
        };

        self.titlebar_children[1] = titlebarButton(Ids.minimize, "_");
        self.titlebar_children[2] = titlebarButton(Ids.maximize, if (maximized) "[]" else "[ ]");
        self.titlebar_children[3] = titlebarButton(Ids.close, "x");

        self.layers[1] = .{
            .id = Ids.titlebar,
            .kind = .row,
            .layout = .{
                .width = .fill,
                .height = .fill,
                .padding = .{ .west = 12, .east = 6, .north = 4, .south = 4 },
                .gap = 4,
                .align_y = .center,
            },
            .hit = .generic,
            .children = self.titlebar_children[0..4],
        };

        return .{
            .id = Ids.titlebar,
            .kind = .stack,
            .layout = .{ .width = .fill, .height = .fill },
            .children = self.layers[0..2],
        };
    }

    pub fn hit(self: *const Chrome, point: geo.Point, viewport: geo.Rect) Hit {
        _ = self;
        if (resizeEdge(point, viewport)) |edge| return .{ .resize = edge };
        if (point.y >= viewport.y + titlebar_height) return .content;
        return .titlebar;
    }

    pub fn resizeCursor(self: *const Chrome, point: geo.Point, viewport: geo.Rect) ?Edge {
        return switch (self.hit(point, viewport)) {
            .resize => |edge| edge,
            else => null,
        };
    }
};

pub fn ownsId(id: ui.SurfaceId) bool {
    return id.eql(Ids.titlebar) or
        id.eql(Ids.background) or
        id.eql(Ids.title) or
        id.eql(Ids.minimize) or
        id.eql(Ids.maximize) or
        id.eql(Ids.close);
}

fn titlebarButton(id: ui.SurfaceId, text: []const u8) ui.SurfaceNode {
    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .{ .fixed = 34 }, .height = .{ .fixed = 26 } },
        .content = .{ .button = .{ .text = text, .font_size = 12 } },
        .hit = .button,
    };
}

fn resizeEdge(point: geo.Point, viewport: geo.Rect) ?Edge {
    const left = point.x < viewport.x + resize_margin;
    const right = point.x >= viewport.x + @as(i32, @intCast(viewport.width -| resize_margin));
    const top = point.y < viewport.y + resize_margin;
    const bottom = point.y >= viewport.y + @as(i32, @intCast(viewport.height -| resize_margin));

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
