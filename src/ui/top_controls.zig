//! Top controls: utility buttons above the main card.

const std = @import("std");
const ui = @import("otter_ui");

const root_mod = @import("root.zig");
const common_mod = @import("common.zig");

pub const Ids = struct {
    pub const content = ui.SurfaceId.namedComptime("top_controls.content");
    pub const hello = ui.SurfaceId.namedComptime("top_controls.hello");
    pub const toggle_sidebar = ui.SurfaceId.namedComptime("top_controls.toggle_sidebar");
};

pub fn buildTopControls(root: *root_mod.Root) void {
    root.top_controls[0] = buildHelloButton(root);
    root.top_controls[1] = buildSidebarToggle(root);

    const child_count: usize = if (root.toggle_button_shown) 2 else 1;

    root.main_children[root.main_count] = .{ .id = Ids.content, .kind = .stack, .layout = .{ .width = .fill, .height = .fit }, .children = root.top_controls[0..child_count] };
    root.main_count += 1;
}

fn buildHelloButton(root: *root_mod.Root) ui.SurfaceNode {
    const id = Ids.hello;

    root.top_button_infos[0] = .{
        .id = id,
        .on_pressed = helloPressed,
    };

    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .fit, .height = .fit, .align_x = .start },
        .content = .{ .button = .{ .text = "Hello" } },
        .hit = .button,
    };
}

fn buildSidebarToggle(root: *root_mod.Root) ui.SurfaceNode {
    const id = Ids.toggle_sidebar;
    const text = if (root.sidebar_visible) "Hide Sidebar" else "Show Sidebar";

    root.top_button_infos[1] = .{
        .id = id,
        .on_pressed = toggleSidebarPressed,
    };

    return .{
        .id = id,
        .kind = .leaf,
        .layout = .{ .width = .fit, .height = .fit, .align_x = .end },
        .content = .{ .button = .{ .text = text } },
        .hit = .button,
    };
}

fn helloPressed(root: *root_mod.Root) root_mod.PressResult {
    _ = root;
    std.debug.print("hello\n", .{});
    return .input;
}

fn toggleSidebarPressed(root: *root_mod.Root) root_mod.PressResult {
    root.sidebar_visible = !root.sidebar_visible;
    return .sidebar;
}

pub fn checkPress(root: *root_mod.Root, pressed_id: ui.SurfaceId) root_mod.PressResult {
    for (root.top_button_infos) |info| {
        if (pressed_id.eql(info.id)) {
            return info.on_pressed(root);
        }
    }
    return .none;
}
