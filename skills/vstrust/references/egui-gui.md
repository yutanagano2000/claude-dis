# egui GUI実装リファレンス

## エディター構造

### 基本セットアップ

```rust
use atomic_float::AtomicF32;
use nih_plug::prelude::{Editor, Param};
use nih_plug::context::gui::ParamSetter;
use nih_plug_egui::egui::{self, Color32, FontId, Pos2, Rect, RichText, Sense, Stroke, Vec2};
use nih_plug_egui::{create_egui_editor, EguiState};
use std::sync::atomic::Ordering;
use std::sync::Arc;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

pub fn default_state() -> Arc<EguiState> {
    EguiState::from_size(WIDTH, HEIGHT)
}

pub fn create(
    params: Arc<MyPluginParams>,
    gain_reduction: Arc<AtomicF32>,
    egui_state: Arc<EguiState>,
) -> Option<Box<dyn Editor>> {
    create_egui_editor(
        egui_state,
        (),  // カスタム状態（必要に応じて構造体を定義）
        |_, _| {},  // セットアップコールバック
        move |egui_ctx, setter, _state| {
            // GUI描画コード
            egui::CentralPanel::default()
                .frame(egui::Frame::new().fill(Color32::from_rgb(20, 22, 28)))
                .show(egui_ctx, |ui| {
                    // UIウィジェット
                });
        },
    )
}
```

### Plugin本体でのエディター登録

```rust
impl Plugin for MyPlugin {
    fn editor(&mut self, _async_executor: AsyncExecutor<Self>) -> Option<Box<dyn Editor>> {
        editor::create(
            self.params.clone(),
            self.gain_reduction.clone(),
            self.editor_state.clone(),
        )
    }
}
```

## カスタムウィジェット

### ノブ（Knob）

```rust
fn draw_knob<P: Param>(
    ui: &mut egui::Ui,
    label: &str,
    param: &P,
    setter: &ParamSetter,
    color: Color32,
) {
    let knob_size = 50.0;

    ui.vertical(|ui| {
        ui.set_width(knob_size + 5.0);

        let (rect, response) = ui.allocate_exact_size(
            Vec2::splat(knob_size),
            Sense::click_and_drag()
        );
        let painter = ui.painter();
        let normalized = param.modulated_normalized_value();

        // ドラッグ処理
        if response.dragged() {
            let delta = response.drag_delta();
            let new_value = (normalized - delta.y * 0.006).clamp(0.0, 1.0);
            setter.set_parameter_normalized(param, new_value);
        }

        // ダブルクリックでデフォルト値に戻す
        if response.double_clicked() {
            setter.set_parameter_normalized(param, param.default_normalized_value());
        }

        let center = rect.center();
        let radius = knob_size / 2.0 - 2.0;

        // 背景円
        painter.circle_stroke(center, radius, Stroke::new(3.0, Color32::from_rgb(40, 45, 55)));

        // 値に応じた円弧
        let start_angle = std::f32::consts::PI * 0.75;
        let end_angle = std::f32::consts::PI * 2.25;
        let current_angle = start_angle + (end_angle - start_angle) * normalized;

        let arc_points: Vec<Pos2> = (0..=20)
            .filter_map(|i| {
                let angle = start_angle + (current_angle - start_angle) * (i as f32 / 20.0);
                if angle <= current_angle {
                    Some(Pos2::new(
                        center.x + radius * angle.cos(),
                        center.y + radius * angle.sin()
                    ))
                } else {
                    None
                }
            })
            .collect();

        if arc_points.len() >= 2 {
            painter.add(egui::Shape::line(arc_points, Stroke::new(3.0, color)));
        }

        // インジケーター
        let indicator_pos = Pos2::new(
            center.x + (radius - 6.0) * current_angle.cos(),
            center.y + (radius - 6.0) * current_angle.sin()
        );
        painter.circle_filled(indicator_pos, 3.0, color);

        // 値表示
        painter.text(
            center,
            egui::Align2::CENTER_CENTER,
            param.to_string(),
            FontId::proportional(9.0),
            Color32::WHITE
        );

        ui.add_space(1.0);
        ui.vertical_centered(|ui| {
            ui.label(RichText::new(label).size(9.0).color(Color32::from_rgb(130, 135, 150)));
        });
    });
}
```

### ゲインリダクションメーター

```rust
fn draw_gr_meter(ui: &mut egui::Ui, gr_db: f32) {
    let width = 300.0;
    let height = 24.0;

    let (rect, _) = ui.allocate_exact_size(Vec2::new(width, height), Sense::hover());
    let painter = ui.painter();

    // 背景
    painter.rect_filled(rect, 3.0, Color32::from_rgb(15, 17, 22));

    // バー
    let fill_ratio = (gr_db / 24.0).clamp(0.0, 1.0);
    if fill_ratio > 0.0 {
        let fill_rect = Rect::from_min_size(
            rect.min,
            Vec2::new(width * fill_ratio, height)
        );
        let color = if fill_ratio > 0.5 {
            Color32::from_rgb(255, 80, 80)
        } else {
            Color32::from_rgb(80, 200, 120)
        };
        painter.rect_filled(fill_rect, 3.0, color);
    }

    // 数値表示
    painter.text(
        Pos2::new(rect.right() - 8.0, rect.center().y),
        egui::Align2::RIGHT_CENTER,
        format!("-{:.1}dB", gr_db),
        FontId::proportional(12.0),
        Color32::WHITE
    );
}
```

### トグルボタン

```rust
fn draw_toggle(
    ui: &mut egui::Ui,
    param: &nih_plug::prelude::BoolParam,
    setter: &ParamSetter,
    label: &str,
) {
    let button_size = 40.0;
    let is_on = param.value();

    let (rect, response) = ui.allocate_exact_size(Vec2::splat(button_size), Sense::click());
    let painter = ui.painter();

    if response.clicked() {
        setter.set_parameter(param, !is_on);
    }

    let center = rect.center();
    let radius = button_size / 2.0 - 2.0;

    let bg_color = if is_on {
        Color32::from_rgb(100, 200, 120)
    } else {
        Color32::from_rgb(40, 45, 55)
    };
    painter.circle_filled(center, radius, bg_color);

    painter.text(
        center,
        egui::Align2::CENTER_CENTER,
        label,
        FontId::proportional(10.0),
        if is_on { Color32::BLACK } else { Color32::WHITE }
    );
}
```

### モードセレクター（ボタン群）

```rust
fn draw_mode_selector(
    ui: &mut egui::Ui,
    param: &nih_plug::prelude::IntParam,
    setter: &ParamSetter,
) {
    let current_mode = param.value();
    let button_width = 60.0;
    let button_height = 24.0;

    let modes = [
        (0, "MODE A", Color32::from_rgb(255, 100, 100)),
        (1, "MODE B", Color32::from_rgb(100, 200, 255)),
        (2, "MODE C", Color32::from_rgb(100, 255, 150)),
    ];

    ui.horizontal(|ui| {
        for (mode_value, label, active_color) in modes.iter() {
            let is_selected = current_mode == *mode_value;

            let (rect, response) = ui.allocate_exact_size(
                Vec2::new(button_width, button_height),
                Sense::click()
            );
            let painter = ui.painter();

            if response.clicked() {
                setter.set_parameter(param, *mode_value);
            }

            let bg_color = if is_selected {
                *active_color
            } else {
                Color32::from_rgb(40, 45, 55)
            };
            painter.rect_filled(rect, 4.0, bg_color);

            let text_color = if is_selected {
                Color32::from_rgb(20, 20, 25)
            } else {
                Color32::from_rgb(130, 135, 150)
            };
            painter.text(
                rect.center(),
                egui::Align2::CENTER_CENTER,
                *label,
                FontId::proportional(11.0),
                text_color
            );
        }
    });
}
```

## リアルタイムグラフ

### 履歴バッファ付きグラフ

```rust
use std::collections::VecDeque;

const GRAPH_HISTORY_LEN: usize = 200;

struct EditorState {
    gr_history: VecDeque<f32>,
}

impl Default for EditorState {
    fn default() -> Self {
        let mut gr_history = VecDeque::with_capacity(GRAPH_HISTORY_LEN);
        for _ in 0..GRAPH_HISTORY_LEN {
            gr_history.push_back(0.0);
        }
        Self { gr_history }
    }
}

fn draw_timeline_graph(
    ui: &mut egui::Ui,
    history: &VecDeque<f32>,
    color: Color32,
) {
    let width = 400.0;
    let height = 100.0;

    let (rect, _) = ui.allocate_exact_size(Vec2::new(width, height), Sense::hover());
    let painter = ui.painter();

    // 背景
    painter.rect_filled(rect, 5.0, Color32::from_rgb(12, 14, 18));

    // 波形描画
    let points: Vec<Pos2> = history
        .iter()
        .enumerate()
        .map(|(i, &value)| {
            let x = rect.left() + (i as f32 / GRAPH_HISTORY_LEN as f32) * width;
            let y = rect.bottom() - (value / 24.0).clamp(0.0, 1.0) * height;
            Pos2::new(x, y)
        })
        .collect();

    if points.len() >= 2 {
        painter.add(egui::Shape::line(points, Stroke::new(2.0, color)));
    }
}
```

## カラーパレット例

```rust
// 背景色
const BG_DARK: Color32 = Color32::from_rgb(20, 22, 28);
const BG_PANEL: Color32 = Color32::from_rgb(12, 14, 18);
const BG_CONTROL: Color32 = Color32::from_rgb(40, 45, 55);

// アクセントカラー
const ACCENT_RED: Color32 = Color32::from_rgb(255, 100, 100);
const ACCENT_ORANGE: Color32 = Color32::from_rgb(255, 140, 70);
const ACCENT_YELLOW: Color32 = Color32::from_rgb(255, 200, 50);
const ACCENT_GREEN: Color32 = Color32::from_rgb(90, 255, 140);
const ACCENT_BLUE: Color32 = Color32::from_rgb(90, 180, 255);
const ACCENT_PURPLE: Color32 = Color32::from_rgb(180, 90, 255);

// テキスト色
const TEXT_PRIMARY: Color32 = Color32::WHITE;
const TEXT_SECONDARY: Color32 = Color32::from_rgb(130, 135, 150);
const TEXT_LABEL: Color32 = Color32::from_rgb(90, 95, 110);
```
