// compressor_dsp.rs - コンプレッサーDSPモジュール例
//
// エンベロープフォロワー、ゲインリダクション計算、
// スムージングを含む完全なコンプレッサーDSPの実装例。

use std::f32::consts::PI;

/// 検出モード
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DetectionMode {
    Peak,       // 瞬時ピーク値
    Rms,        // 二乗平均平方根
    SmoothAvg,  // スムーズな平均
}

/// エンベロープフォロワー
pub struct EnvelopeFollower {
    envelope: f32,
    attack_coeff: f32,
    release_coeff: f32,
    mode: DetectionMode,
    rms_buffer: Vec<f32>,
    rms_index: usize,
    smooth_avg: f32,
    smooth_coeff: f32,
}

impl EnvelopeFollower {
    pub fn new(attack_ms: f32, release_ms: f32, sample_rate: f32) -> Self {
        let rms_window_ms = 10.0;
        let rms_window_samples = (rms_window_ms * 0.001 * sample_rate) as usize;

        Self {
            envelope: 0.0,
            attack_coeff: Self::time_to_coeff(attack_ms, sample_rate),
            release_coeff: Self::time_to_coeff(release_ms, sample_rate),
            mode: DetectionMode::Peak,
            rms_buffer: vec![0.0; rms_window_samples.max(1)],
            rms_index: 0,
            smooth_avg: 0.0,
            smooth_coeff: Self::time_to_coeff(5.0, sample_rate),
        }
    }

    fn time_to_coeff(time_ms: f32, sample_rate: f32) -> f32 {
        if time_ms <= 0.0 {
            0.0
        } else {
            (-1.0 / (time_ms * 0.001 * sample_rate)).exp()
        }
    }

    pub fn set_mode(&mut self, mode: DetectionMode) {
        self.mode = mode;
    }

    pub fn set_times(&mut self, attack_ms: f32, release_ms: f32, sample_rate: f32) {
        self.attack_coeff = Self::time_to_coeff(attack_ms, sample_rate);
        self.release_coeff = Self::time_to_coeff(release_ms, sample_rate);
    }

    pub fn process(&mut self, input: f32) -> f32 {
        let detected = match self.mode {
            DetectionMode::Peak => input.abs(),
            DetectionMode::Rms => {
                let squared = input * input;
                self.rms_buffer[self.rms_index] = squared;
                self.rms_index = (self.rms_index + 1) % self.rms_buffer.len();
                let mean_squared: f32 = self.rms_buffer.iter().sum::<f32>()
                    / self.rms_buffer.len() as f32;
                mean_squared.sqrt()
            }
            DetectionMode::SmoothAvg => {
                let abs_input = input.abs();
                self.smooth_avg = self.smooth_coeff * self.smooth_avg
                    + (1.0 - self.smooth_coeff) * abs_input;
                self.smooth_avg
            }
        };

        // エンベロープフォロワー（アタック/リリース）
        if detected > self.envelope {
            self.envelope = self.attack_coeff * self.envelope
                + (1.0 - self.attack_coeff) * detected;
        } else {
            self.envelope = self.release_coeff * self.envelope
                + (1.0 - self.release_coeff) * detected;
        }

        self.envelope
    }

    pub fn reset(&mut self) {
        self.envelope = 0.0;
        self.smooth_avg = 0.0;
        self.rms_buffer.fill(0.0);
        self.rms_index = 0;
    }
}

/// ゲインリダクション計算機
pub struct GainComputer {
    threshold_db: f32,
    ratio: f32,
    knee_db: f32,
}

impl GainComputer {
    pub fn new(threshold_db: f32, ratio: f32, knee_db: f32) -> Self {
        Self {
            threshold_db,
            ratio,
            knee_db,
        }
    }

    pub fn set_threshold(&mut self, threshold_db: f32) {
        self.threshold_db = threshold_db;
    }

    pub fn set_ratio(&mut self, ratio: f32) {
        self.ratio = ratio.max(1.0);
    }

    pub fn set_knee(&mut self, knee_db: f32) {
        self.knee_db = knee_db.max(0.0);
    }

    /// 入力レベル(dB)からゲインリダクション(dB)を計算
    pub fn compute_gain_reduction(&self, input_db: f32) -> f32 {
        if self.knee_db <= 0.0 {
            // ハードニー
            if input_db <= self.threshold_db {
                0.0
            } else {
                let over = input_db - self.threshold_db;
                over * (1.0 - 1.0 / self.ratio)
            }
        } else {
            // ソフトニー
            let half_knee = self.knee_db / 2.0;
            let knee_start = self.threshold_db - half_knee;
            let knee_end = self.threshold_db + half_knee;

            if input_db <= knee_start {
                0.0
            } else if input_db >= knee_end {
                let over = input_db - self.threshold_db;
                over * (1.0 - 1.0 / self.ratio)
            } else {
                // ニー領域内（二次補間）
                let x = input_db - knee_start;
                let slope = 1.0 - 1.0 / self.ratio;
                (slope * x * x) / (2.0 * self.knee_db)
            }
        }
    }
}

/// ゲインスムーザー
pub struct GainSmoother {
    current_gain: f32,
    target_gain: f32,
    coeff: f32,
}

impl GainSmoother {
    pub fn new(smoothing_ms: f32, sample_rate: f32) -> Self {
        Self {
            current_gain: 1.0,
            target_gain: 1.0,
            coeff: (-2.0 * PI / (smoothing_ms * 0.001 * sample_rate)).exp(),
        }
    }

    pub fn set_target(&mut self, target: f32) {
        self.target_gain = target;
    }

    pub fn next(&mut self) -> f32 {
        self.current_gain = self.coeff * self.current_gain
            + (1.0 - self.coeff) * self.target_gain;
        self.current_gain
    }

    pub fn reset(&mut self, value: f32) {
        self.current_gain = value;
        self.target_gain = value;
    }
}

/// dB⇔リニア変換ユーティリティ
pub mod gain_utils {
    pub fn db_to_gain(db: f32) -> f32 {
        10.0_f32.powf(db / 20.0)
    }

    pub fn gain_to_db(gain: f32) -> f32 {
        20.0 * gain.max(1e-10).log10()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_envelope_follower() {
        let mut env = EnvelopeFollower::new(10.0, 100.0, 44100.0);

        // ゼロ入力でゼロ出力
        assert_eq!(env.process(0.0), 0.0);

        // 入力があればエンベロープが上昇
        let result = env.process(1.0);
        assert!(result > 0.0);
    }

    #[test]
    fn test_gain_computer_hard_knee() {
        let gc = GainComputer::new(-20.0, 4.0, 0.0);

        // スレッショルド以下はゲインリダクションなし
        assert_eq!(gc.compute_gain_reduction(-30.0), 0.0);

        // スレッショルド以上でゲインリダクション
        let gr = gc.compute_gain_reduction(-10.0);
        assert!(gr > 0.0);
    }

    #[test]
    fn test_db_conversion() {
        use gain_utils::*;

        assert!((db_to_gain(0.0) - 1.0).abs() < 0.001);
        assert!((db_to_gain(-6.0) - 0.5).abs() < 0.1);
        assert!((gain_to_db(1.0) - 0.0).abs() < 0.001);
    }
}
