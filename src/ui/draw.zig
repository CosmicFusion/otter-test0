//! Paint path: SD emit, repair dirty rects, rasterize, commit damage.

const ow = @import("otter_wayland");
const render = @import("otter_render");
const ui = @import("otter_ui");
const geo = @import("otter_geo");
const theme_mod = @import("otter_theme");

const root_mod = @import("root.zig");

const Color = render.Color;

pub const Background = union(enum) {
    transparent,
    color: Color,
};

pub const Frame = struct {
    root: *root_mod.Root,
    ui_state: *root_mod.UiState,
    damage: *ow.DamageTracker,
    font: *render.Font,
    renderer: *ow.Renderer,
    surface: *ow.wayland.client.wl.Surface,
    shell_label: []const u8,
    card_placement: root_mod.CardPlacement,
    background: Background,
    theme: theme_mod.Theme,
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
    const styles = ui.style.resolve(&frame.theme);

    var ui_frame = frame.ui_state.begin(.{
        .viewport = viewport,
        .scale = acquired.surface.scale,
        .font = frame.font,
        .theme = &frame.theme,
        .styles = &styles,
        .text_provider = frame.text_provider,
    });

    if (effective.full) {
        switch (frame.background) {
            .transparent => ui_frame.clear(Color.init(0, 0, 0, 0)),
            .color => |bg| ui_frame.clear(bg),
        }
    }

    const root_card_rect = root_mod.Root.cardRect(viewport, frame.card_placement);
    const root = frame.root.buildCard(viewport, frame.shell_label, frame.theme);
    _ = ui_frame.render(&root, root_card_rect) catch {};
    frame.root.queueOverlays(&ui_frame, viewport, frame.theme);
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
}
