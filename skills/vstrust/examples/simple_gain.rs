// simple_gain.rs - 最小限のゲインプラグイン
//
// このファイルは完全なnih-plugプラグインの最小実装例です。
// 新しいプラグインを作成する際のテンプレートとして使用してください。

use nih_plug::prelude::*;
use std::sync::Arc;

/// プラグイン本体
struct SimpleGain {
    params: Arc<SimpleGainParams>,
}

/// パラメータ定義
#[derive(Params)]
struct SimpleGainParams {
    #[id = "gain"]
    pub gain: FloatParam,
}

impl Default for SimpleGain {
    fn default() -> Self {
        Self {
            params: Arc::new(SimpleGainParams::default()),
        }
    }
}

impl Default for SimpleGainParams {
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
        }
    }
}

impl Plugin for SimpleGain {
    const NAME: &'static str = "Simple Gain";
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

    fn process(
        &mut self,
        buffer: &mut Buffer,
        _aux: &mut AuxiliaryBuffers,
        _context: &mut impl ProcessContext<Self>,
    ) -> ProcessStatus {
        for mut samples in buffer.iter_samples() {
            let gain = self.params.gain.smoothed.next();
            for sample in samples.iter_mut() {
                *sample *= gain;
            }
        }
        ProcessStatus::Normal
    }
}

impl ClapPlugin for SimpleGain {
    const CLAP_ID: &'static str = "com.example.simple-gain";
    const CLAP_DESCRIPTION: Option<&'static str> = Some("A simple gain plugin");
    const CLAP_MANUAL_URL: Option<&'static str> = None;
    const CLAP_SUPPORT_URL: Option<&'static str> = None;
    const CLAP_FEATURES: &'static [ClapFeature] = &[
        ClapFeature::AudioEffect,
        ClapFeature::Stereo,
        ClapFeature::Utility,
    ];
}

impl Vst3Plugin for SimpleGain {
    const VST3_CLASS_ID: [u8; 16] = *b"SimpleGainXXXXXX";
    const VST3_SUBCATEGORIES: &'static [Vst3SubCategory] = &[
        Vst3SubCategory::Fx,
        Vst3SubCategory::Tools,
    ];
}

nih_export_clap!(SimpleGain);
nih_export_vst3!(SimpleGain);
