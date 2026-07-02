//! Paint path: SD emit, repair dirty rects, rasterize, commit damage.

const ow = @import("otter_wayland");
const render = @import("otter_render");
const ui = @import("otter_ui");
const geo = @import("otter_geo");

const demo_mod = @import("demo.zig");

const Color = render.Color;

pub const Background = union(enum) {
    transparent,
    color: Color,
};

pub const Frame = struct {
    demo: *demo_mod.Demo,
    ui_state: *demo_mod.UiState,
    damage: *ow.DamageTracker,
    font: *render.Font,
    renderer: *ow.Renderer,
    surface: *ow.wayland.client.wl.Surface,
    shell_label: []const u8,
    card_placement: demo_mod.CardPlacement,
    background: Background,
    text_provider: ui.TextSystemProvider,
};

pub fn draw(frame: Frame) void {
    if (!frame.damage.hasDamage() and !frame.damage.isFullDamage()) return;

    var acquired = frame.renderer.acquire() orelse return;
    defer acquired.release();

    const viewport = geo.Rect{
        .x = 0,
        .y = 0,
        .width = acquired.surface.logicalWidth(),
        .height = acquired.surface.logicalHeight(),
    };

    const effective = frame.damage.getEffectiveDamage();
    const damage_rects = if (effective.full) null else effective.rects.constSlice();

    var ui_frame = frame.ui_state.begin(.{
        .viewport = viewport,
        .scale = acquired.surface.scale,
        .font = frame.font,
        .text_provider = frame.text_provider,
    });

    if (effective.full) {
        switch (frame.background) {
            .transparent => ui_frame.clear(Color.init(0, 0, 0, 0)),
            .color => |bg| ui_frame.clear(bg),
        }
    }

    const card_rect = demo_mod.Demo.cardRect(viewport, frame.card_placement);
    const root = frame.demo.buildCard(frame.ui_state, frame.shell_label);
    _ = ui_frame.render(&root, card_rect) catch {};
    ui_frame.finish() catch {};

    if (!effective.full) {
        const fill = switch (frame.background) {
            .transparent => Color.init(0, 0, 0, 0),
            .color => |bg| bg,
        };
        for (damage_rects.?) |rect| acquired.surface.fillRectLogical(rect, fill);
    }

    frame.ui_state.rasterize(&acquired.surface, damage_rects, effective.full);
    frame.renderer.submit(frame.surface, frame.damage);
    frame.damage.commitFrame();
    frame.demo.captureRects(frame.ui_state);
}
