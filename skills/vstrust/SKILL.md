---
name: vstrust
description: "nih-plugとeguiを使用したRust VST3/CLAPプラグイン開発の包括的ガイド。DSP実装、GUI設計、パラメータ定義、ビルド/デプロイの完全なワークフローを提供。"
---

# VSTrust - Rust VST3/CLAP Plugin Development Guide

nih-plugフレームワークを使用したRustによるVST3/CLAPオーディオプラグイン開発の包括的リファレンス。

## When to Use This Skill

- 新規VST3/CLAPプラグイン作成時
- コンプレッサー/エフェクター開発時
- egui GUIデザイン時
- DSPアルゴリズム実装時
- Ableton Live等DAW用プラグイン開発時

## Quick Start

### プロジェクト構造

```
my-plugin/
├── Cargo.toml
├── src/
│   ├── lib.rs                 # Plugin本体 (Plugin trait実装)
│   ├── editor.rs              # egui GUI
│   └── dsp/
│       ├── mod.rs             # DSPモジュールエクスポート
│       ├── envelope.rs        # エンベロープフォロワー
│       ├── dynamics.rs        # ダイナミクス処理
│       └── gain.rs            # ゲインユーティリティ
└── xtask/
    ├── Cargo.toml
    └── src/main.rs            # バンドルタスク
```

### 最小限のCargo.toml

```toml
[package]
name = "my-plugin"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
nih_plug = { git = "https://github.com/robbert-vdh/nih-plug.git", features = ["assert_process_allocs"] }
nih_plug_egui = { git = "https://github.com/robbert-vdh/nih-plug.git" }
atomic_float = "1"

[profile.release]
lto = "thin"
strip = "symbols"
```

## Core Concepts

### 1. Plugin Trait実装

nih-plugの中核となるPlugin traitを実装します。

```rust
use nih_plug::prelude::*;
use std::sync::Arc;

pub struct MyPlugin {
    params: Arc<MyPluginParams>,
    sample_rate: f32,
}

impl Default for MyPlugin {
    fn default() -> Self {
        Self {
            params: Arc::new(MyPluginParams::default()),
            sample_rate: 44100.0,
        }
    }
}

impl Plugin for MyPlugin {
    const NAME: &'static str = "My Plugin";
    const VENDOR: &'static str = "Your Name";
    const URL: &'static str = "https://example.com";
    const EMAIL: &'static str = "your@email.com";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    const AUDIO_IO_LAYOUTS: &'static [AudioIOLayout] = &[
        AudioIOLayout {
            main_input_channels: NonZeroU32::new(2),
            main_output_channels: NonZeroU32::new(2),
            ..AudioIOLayout::const_default()
        },
    ];

    const MIDI_INPUT: MidiConfig = MidiConfig::None;
    const SAMPLE_ACCURATE_AUTOMATION: bool = true;

    type SysExMessage = ();
    type BackgroundTask = ();

    fn params(&self) -> Arc<dyn Params> {
        self.params.clone()
    }

    fn initialize(
        &mut self,
        _audio_io_layout: &AudioIOLayout,
        buffer_config: &BufferConfig,
        _context: &mut impl InitContext<Self>,
    ) -> bool {
        self.sample_rate = buffer_config.sample_rate;
        true
    }

    fn process(
        &mut self,
        buffer: &mut Buffer,
        _aux: &mut AuxiliaryBuffers,
        _context: &mut impl ProcessContext<Self>,
    ) -> ProcessStatus {
        for mut samples in buffer.iter_samples() {
            // DSP処理をここに実装
            let gain = self.params.gain.smoothed.next();
            for sample in samples.iter_mut() {
                *sample *= gain;
            }
        }
        ProcessStatus::Normal
    }
}

impl ClapPlugin for MyPlugin {
    const CLAP_ID: &'static str = "com.example.my-plugin";
    const CLAP_DESCRIPTION: Option<&'static str> = Some("My audio plugin");
    const CLAP_MANUAL_URL: Option<&'static str> = None;
    const CLAP_SUPPORT_URL: Option<&'static str> = None;
    const CLAP_FEATURES: &'static [ClapFeature] = &[
        ClapFeature::AudioEffect,
        ClapFeature::Stereo,
    ];
}

impl Vst3Plugin for MyPlugin {
    const VST3_CLASS_ID: [u8; 16] = *b"MyPluginXXXXXXXX";
    const VST3_SUBCATEGORIES: &'static [Vst3SubCategory] = &[
        Vst3SubCategory::Fx,
        Vst3SubCategory::Dynamics,
    ];
}

nih_export_clap!(MyPlugin);
nih_export_vst3!(MyPlugin);
```

### 2. パラメータ定義

```rust
#[derive(Params)]
pub struct MyPluginParams {
    #[id = "gain"]
    pub gain: FloatParam,

    #[id = "threshold"]
    pub threshold: FloatParam,

    #[id = "ratio"]
    pub ratio: FloatParam,

    #[id = "bypass"]
    pub bypass: BoolParam,

    #[id = "mode"]
    pub mode: IntParam,
}

impl Default for MyPluginParams {
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

            threshold: FloatParam::new(
                "Threshold",
                -20.0,
                FloatRange::Skewed {
                    min: -60.0,
                    max: 0.0,
                    factor: FloatRange::gain_skew_factor(-60.0, 0.0),
                },
            )
            .with_unit(" dB"),

            ratio: FloatParam::new(
                "Ratio",
                4.0,
                FloatRange::Skewed {
                    min: 1.0,
                    max: 20.0,
                    factor: -1.0,
                },
            )
            .with_unit(":1"),

            bypass: BoolParam::new("Bypass", false),

            mode: IntParam::new("Mode", 0, IntRange::Linear { min: 0, max: 2 }),
        }
    }
}
```

### 3. AtomicF32によるスレッド間通信

オーディオスレッド(process)からGUIスレッドへのデータ転送：

```rust
use atomic_float::AtomicF32;
use std::sync::atomic::Ordering;

pub struct MyPlugin {
    params: Arc<MyPluginParams>,
    // GUI通信用
    gain_reduction: Arc<AtomicF32>,
    input_level: Arc<AtomicF32>,
}

impl MyPlugin {
    fn process(&mut self, buffer: &mut Buffer, ...) -> ProcessStatus {
        // オーディオスレッドで値を更新
        self.gain_reduction.store(gr_db, Ordering::Relaxed);
        self.input_level.store(input_db, Ordering::Relaxed);
        // ...
    }
}

// GUIスレッドで読み取り
fn draw_meter(gain_reduction: &Arc<AtomicF32>) {
    let gr_db = gain_reduction.load(Ordering::Relaxed);
    // 描画処理
}
```

### 4. DSPモジュール設計

#### エンベロープフォロワー

```rust
pub struct EnvelopeFollower {
    envelope: f32,
    attack_coeff: f32,
    release_coeff: f32,
}

impl EnvelopeFollower {
    pub fn new(attack_ms: f32, release_ms: f32, sample_rate: f32) -> Self {
        Self {
            envelope: 0.0,
            attack_coeff: (-1.0 / (attack_ms * 0.001 * sample_rate)).exp(),
            release_coeff: (-1.0 / (release_ms * 0.001 * sample_rate)).exp(),
        }
    }

    pub fn process(&mut self, input: f32) -> f32 {
        let abs_input = input.abs();
        if abs_input > self.envelope {
            self.envelope = self.attack_coeff * self.envelope
                + (1.0 - self.attack_coeff) * abs_input;
        } else {
            self.envelope = self.release_coeff * self.envelope
                + (1.0 - self.release_coeff) * abs_input;
        }
        self.envelope
    }
}
```

#### dB/ゲイン変換

```rust
pub fn db_to_gain(db: f32) -> f32 {
    10.0_f32.powf(db / 20.0)
}

pub fn gain_to_db(gain: f32) -> f32 {
    20.0 * gain.max(1e-10).log10()
}
```

## egui GUI実装

詳細は [references/egui-gui.md](references/egui-gui.md) を参照。

## ビルドとデプロイ

詳細は [references/build-deploy.md](references/build-deploy.md) を参照。

## Best Practices

1. **リアルタイム安全性**: process()内でメモリ確保、ブロッキング操作、panicを避ける
2. **デノーマル防止**: 小さな値に対して `DenormalPrevention` を使用
3. **Atomic通信**: GUI通信には `AtomicF32` + `Ordering::Relaxed` を使用
4. **パラメータビルダー**: 一貫したパラメータ定義のためビルダーパターンを使用
5. **モジュール分離**: DSP/GUI/パラメータを明確に分離
6. **codesign署名**: macOSでのDAW認識のため必須

## Common Pitfalls

1. **process()内でのメモリ確保**: `Vec::new()`, `Box::new()` 等は禁止
2. **ブロッキング操作**: `mutex.lock()`, ファイルI/O等は禁止
3. **panic**: `unwrap()` より `unwrap_or_default()` を使用
4. **DAW認識問題**: `xattr -cr` と `codesign --force --deep -s -` が必要
5. **パラメータID重複**: 各パラメータには一意のID文字列が必要

## Additional Resources

- [examples/](examples/) - 完全なコード例
- [references/egui-gui.md](references/egui-gui.md) - egui GUI詳細
- [references/build-deploy.md](references/build-deploy.md) - ビルド/デプロイ手順
- [nih-plug GitHub](https://github.com/robbert-vdh/nih-plug)
- [egui Documentation](https://docs.rs/egui/latest/egui/)
