//! Top controls: utility buttons above the main card.

const std = @import("std");
const ui = @import("otter_ui");

const types = @import("ui_types.zig");

pub const Ids = struct {
    pub const content = ui.SurfaceId.namedComptime("top_controls.content");
    pub const hello = ui.SurfaceId.namedComptime("top_controls.hello");
    pub const toggle_sidebar = ui.SurfaceId.namedComptime("top_controls.toggle_sidebar");
};

pub fn buildTopControls(root: anytype) void {
    root.top_controls[0] = buildHelloButton(root);
    root.top_controls[1] = buildSidebarToggle(root);

    const child_count: usize = if (root.toggle_button_shown) 2 else 1;

    root.main_children[root.main_count] = .{ .id = Ids.content, .kind = .stack, .layout = .{ .width = .fill, .height = .fit }, .children = root.top_controls[0..child_count] };
    root.main_count += 1;
}

fn buildHelloButton(root: anytype) ui.SurfaceNode {
    const id = Ids.hello;
    _ = root;

    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .fit, .height = .fit, .align_x = .start },
        .content = .{ .button = .{ .text = "Hello" } },
        .hit = .button,
    };
}

fn buildSidebarToggle(root: anytype) ui.SurfaceNode {
    const id = Ids.toggle_sidebar;
    const text = if (root.sidebar_visible) "Hide Sidebar" else "Show Sidebar";

    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .fit, .height = .fit, .align_x = .end },
        .content = .{ .button = .{ .text = text } },
        .hit = .button,
    };
}

fn helloPressed(root: anytype) types.PressResult {
    _ = root;
    std.debug.print("hello\n", .{});
    return .input;
}

fn toggleSidebarPressed(root: anytype) types.PressResult {
    root.sidebar_visible = !root.sidebar_visible;
    return .sidebar;
}

pub fn checkPress(root: anytype, pressed_id: ui.SurfaceId) types.PressResult {
    if (pressed_id.eql(Ids.hello)) return helloPressed(root);
    if (pressed_id.eql(Ids.toggle_sidebar)) return toggleSidebarPressed(root);
    return .none;
}
