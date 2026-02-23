// gui_with_editor.rs - egui GUIを持つプラグインの例
//
// このファイルはnih_plug_eguiを使用してGUIを持つ
// プラグインの完全な実装例を示します。

use atomic_float::AtomicF32;
use nih_plug::prelude::*;
use nih_plug_egui::egui::{self, Color32, FontId, Pos2, RichText, Sense, Stroke, Vec2};
use nih_plug_egui::{create_egui_editor, EguiState};
use std::sync::atomic::Ordering;
use std::sync::Arc;

const WIDTH: u32 = 400;
const HEIGHT: u32 = 300;

// =============================================================================
// プラグイン本体
// =============================================================================

struct GainWithGui {
    params: Arc<GainParams>,
    // GUI通信用（オーディオスレッド→GUIスレッド）
    current_gain_db: Arc<AtomicF32>,
    editor_state: Arc<EguiState>,
}

#[derive(Params)]
struct GainParams {
    #[id = "gain"]
    pub gain: FloatParam,

    #[id = "bypass"]
    pub bypass: BoolParam,
}

impl Default for GainWithGui {
    fn default() -> Self {
        Self {
            params: Arc::new(GainParams::default()),
            current_gain_db: Arc::new(AtomicF32::new(0.0)),
            editor_state: EguiState::from_size(WIDTH, HEIGHT),
        }
    }
}

impl Default for GainParams {
    fn default() -> Self {
        Self {
            gain: FloatParam::new(
                "Gain",
                util::db_to_gain(0.0),
                FloatRange::Skewed {
                    min: util::db_to_gain(-30.0),
                    max: util::db_to_gain(30.0),
                    factor: FloatRange::gain_skew_factor(-30.0, 30.0),
                },
            )
            .with_smoother(SmoothingStyle::Logarithmic(50.0))
            .with_unit(" dB")
            .with_value_to_string(formatters::v2s_f32_gain_to_db(2))
            .with_string_to_value(formatters::s2v_f32_gain_to_db()),

            bypass: BoolParam::new("Bypass", false),
        }
    }
}

impl Plugin for GainWithGui {
    const NAME: &'static str = "Gain With GUI";
    const VENDOR: &'static str = "Your Name";
    const URL: &'static str = "https://example.com";
    const EMAIL: &'static str = "your@email.com";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    const AUDIO_IO_LAYOUTS: &'static [AudioIOLayout] = &[AudioIOLayout {
        main_input_channels: NonZeroU32::new(2),
        main_output_channels: NonZeroU32::new(2),
        ..AudioIOLayout::const_default()
    }];

    const MIDI_INPUT: MidiConfig = MidiConfig::None;
    const SAMPLE_ACCURATE_AUTOMATION: bool = true;

    type SysExMessage = ();
    type BackgroundTask = ();

    fn params(&self) -> Arc<dyn Params> {
        self.params.clone()
    }

    fn editor(&mut self, _async_executor: AsyncExecutor<Self>) -> Option<Box<dyn Editor>> {
        create_editor(
            self.params.clone(),
            self.current_gain_db.clone(),
            self.editor_state.clone(),
        )
    }

    fn process(
        &mut self,
        buffer: &mut Buffer,
        _aux: &mut AuxiliaryBuffers,
        _context: &mut impl ProcessContext<Self>,
    ) -> ProcessStatus {
        if self.params.bypass.value() {
            return ProcessStatus::Normal;
        }

        for mut samples in buffer.iter_samples() {
            let gain = self.params.gain.smoothed.next();

            // GUI用にゲイン値を更新
            let gain_db = util::gain_to_db(gain);
            self.current_gain_db.store(gain_db, Ordering::Relaxed);

            for sample in samples.iter_mut() {
                *sample *= gain;
            }
        }
        ProcessStatus::Normal
    }
}

impl ClapPlugin for GainWithGui {
    const CLAP_ID: &'static str = "com.example.gain-with-gui";
    const CLAP_DESCRIPTION: Option<&'static str> = Some("A gain plugin with GUI");
    const CLAP_MANUAL_URL: Option<&'static str> = None;
    const CLAP_SUPPORT_URL: Option<&'static str> = None;
    const CLAP_FEATURES: &'static [ClapFeature] = &[
        ClapFeature::AudioEffect,
        ClapFeature::Stereo,
    ];
}

impl Vst3Plugin for GainWithGui {
    const VST3_CLASS_ID: [u8; 16] = *b"GainWithGuiXXXXX";
    const VST3_SUBCATEGORIES: &'static [Vst3SubCategory] = &[
        Vst3SubCategory::Fx,
        Vst3SubCategory::Tools,
    ];
}

nih_export_clap!(GainWithGui);
nih_export_vst3!(GainWithGui);

// =============================================================================
// エディター（GUI）
// =============================================================================

fn create_editor(
    params: Arc<GainParams>,
    current_gain_db: Arc<AtomicF32>,
    egui_state: Arc<EguiState>,
) -> Option<Box<dyn Editor>> {
    create_egui_editor(
        egui_state,
        (),
        |_, _| {},
        move |egui_ctx, setter, _state| {
            // 現在のゲイン値を読み取り
            let gain_db = current_gain_db.load(Ordering::Relaxed);

            egui::CentralPanel::default()
                .frame(egui::Frame::new().fill(Color32::from_rgb(30, 32, 40)))
                .show(egui_ctx, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.add_space(20.0);

                        // タイトル
                        ui.label(
                            RichText::new("Gain Plugin")
                                .size(24.0)
                                .color(Color32::WHITE)
                        );

                        ui.add_space(30.0);

                        // ノブ
                        draw_knob(ui, "GAIN", &params.gain, setter, Color32::from_rgb(100, 200, 255));

                        ui.add_space(20.0);

                        // 現在のゲイン表示
                        ui.label(
                            RichText::new(format!("Current: {:.1} dB", gain_db))
                                .size(14.0)
                                .color(Color32::from_rgb(150, 150, 160))
                        );

                        ui.add_space(20.0);

                        // バイパスボタン
                        draw_toggle(ui, &params.bypass, setter, "BYPASS");
                    });
                });
        },
    )
}

// =============================================================================
// カスタムウィジェット
// =============================================================================

fn draw_knob<P: Param>(
    ui: &mut egui::Ui,
    label: &str,
    param: &P,
    setter: &ParamSetter,
    color: Color32,
) {
    let knob_size = 80.0;

    ui.vertical(|ui| {
        ui.set_width(knob_size + 10.0);

        let (rect, response) = ui.allocate_exact_size(
            Vec2::splat(knob_size),
            Sense::click_and_drag()
        );
        let painter = ui.painter();
        let normalized = param.modulated_normalized_value();

        // ドラッグ処理
        if response.dragged() {
            let delta = response.drag_delta();
            let new_value = (normalized - delta.y * 0.005).clamp(0.0, 1.0);
            setter.set_parameter_normalized(param, new_value);
        }

        // ダブルクリックでリセット
        if response.double_clicked() {
            setter.set_parameter_normalized(param, param.default_normalized_value());
        }

        let center = rect.center();
        let radius = knob_size / 2.0 - 4.0;

        // 背景円
        painter.circle_stroke(center, radius, Stroke::new(4.0, Color32::from_rgb(50, 55, 65)));

        // アーク
        let start_angle = std::f32::consts::PI * 0.75;
        let end_angle = std::f32::consts::PI * 2.25;
        let current_angle = start_angle + (end_angle - start_angle) * normalized;

        let arc_points: Vec<Pos2> = (0..=30)
            .map(|i| {
                let angle = start_angle + (current_angle - start_angle) * (i as f32 / 30.0);
                Pos2::new(
                    center.x + radius * angle.cos(),
                    center.y + radius * angle.sin()
                )
            })
            .collect();

        if arc_points.len() >= 2 {
            painter.add(egui::Shape::line(arc_points, Stroke::new(4.0, color)));
        }

        // インジケータードット
        let indicator_pos = Pos2::new(
            center.x + (radius - 8.0) * current_angle.cos(),
            center.y + (radius - 8.0) * current_angle.sin()
        );
        painter.circle_filled(indicator_pos, 4.0, color);

        // 値表示
        painter.text(
            center,
            egui::Align2::CENTER_CENTER,
            param.to_string(),
            FontId::proportional(12.0),
            Color32::WHITE
        );

        ui.add_space(4.0);
        ui.vertical_centered(|ui| {
            ui.label(RichText::new(label).size(11.0).color(Color32::from_rgb(140, 145, 160)));
        });
    });
}

fn draw_toggle(
    ui: &mut egui::Ui,
    param: &BoolParam,
    setter: &ParamSetter,
    label: &str,
) {
    let button_width = 80.0;
    let button_height = 30.0;
    let is_on = param.value();

    let (rect, response) = ui.allocate_exact_size(
        Vec2::new(button_width, button_height),
        Sense::click()
    );
    let painter = ui.painter();

    if response.clicked() {
        setter.set_parameter(param, !is_on);
    }

    let bg_color = if is_on {
        Color32::from_rgb(255, 100, 100)
    } else {
        Color32::from_rgb(50, 55, 65)
    };

    painter.rect_filled(rect, 6.0, bg_color);

    painter.text(
        rect.center(),
        egui::Align2::CENTER_CENTER,
        label,
        FontId::proportional(12.0),
        if is_on { Color32::WHITE } else { Color32::from_rgb(140, 145, 160) }
    );
}
