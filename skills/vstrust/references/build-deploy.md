# ビルド・デプロイ手順

## xtaskセットアップ

### xtask/Cargo.toml

```toml
[package]
name = "xtask"
version = "0.1.0"
edition = "2021"

[dependencies]
nih_plug_xtask = { git = "https://github.com/robbert-vdh/nih-plug.git" }
```

### xtask/src/main.rs

```rust
fn main() -> nih_plug_xtask::Result<()> {
    nih_plug_xtask::main()
}
```

## ビルドコマンド

### 基本ビルド

```bash
# デバッグビルド
cargo build

# リリースビルド
cargo build --release

# バンドル作成（VST3/CLAP）
cargo xtask bundle <plugin_name> --release
```

### プロファイリング用ビルド

```toml
# Cargo.toml に追加
[profile.profiling]
inherits = "release"
debug = true
strip = false
```

```bash
cargo build --profile profiling
```

## macOSインストール手順

### 1. プラグインのコピー

```bash
# VST3
cp -r target/bundled/<plugin_name>.vst3 ~/Library/Audio/Plug-Ins/VST3/

# CLAP
cp -r target/bundled/<plugin_name>.clap ~/Library/Audio/Plug-Ins/CLAP/
```

### 2. 拡張属性のクリア

```bash
xattr -cr ~/Library/Audio/Plug-Ins/VST3/<plugin_name>.vst3
xattr -cr ~/Library/Audio/Plug-Ins/CLAP/<plugin_name>.clap
```

### 3. コード署名

```bash
# アドホック署名（開発用）
codesign --force --deep -s - ~/Library/Audio/Plug-Ins/VST3/<plugin_name>.vst3

# 署名の検証
codesign --verify --deep --strict ~/Library/Audio/Plug-Ins/VST3/<plugin_name>.vst3
```

### 4. ワンライナースクリプト

```bash
# 完全なインストールスクリプト
cargo xtask bundle my_plugin --release && \
cp -r target/bundled/my_plugin.vst3 ~/Library/Audio/Plug-Ins/VST3/ && \
xattr -cr ~/Library/Audio/Plug-Ins/VST3/my_plugin.vst3 && \
codesign --force --deep -s - ~/Library/Audio/Plug-Ins/VST3/my_plugin.vst3 && \
echo "Installation complete!"
```

## Windows/Linux対応

### Windows

```bash
# VST3
copy /Y target\bundled\<plugin_name>.vst3 "%COMMONPROGRAMFILES%\VST3\"

# CLAP
copy /Y target\bundled\<plugin_name>.clap "%COMMONPROGRAMFILES%\CLAP\"
```

### Linux

```bash
# VST3
cp -r target/bundled/<plugin_name>.vst3 ~/.vst3/

# CLAP
cp -r target/bundled/<plugin_name>.clap ~/.clap/
```

## トラブルシューティング

### DAWで認識されない場合

1. **キャッシュクリア**
```bash
# Ableton Live
rm -rf ~/Library/Caches/Ableton/

# Logic Pro
rm -rf ~/Library/Caches/AudioUnitCache/
```

2. **完全リビルド**
```bash
cargo clean
cargo xtask bundle <plugin_name> --release
```

3. **署名の再実行**
```bash
xattr -cr ~/Library/Audio/Plug-Ins/VST3/<plugin_name>.vst3
codesign --force --deep -s - ~/Library/Audio/Plug-Ins/VST3/<plugin_name>.vst3
```

### プラグインがクラッシュする場合

1. **デバッグビルドで確認**
```bash
cargo build
# DAWをターミナルから起動してログを確認
/Applications/Ableton\ Live\ 11\ Suite.app/Contents/MacOS/Live
```

2. **assert_process_allocsの確認**
```toml
# Cargo.toml - リリース時にはオフにする
nih_plug = { git = "...", features = ["assert_process_allocs"] }
```

### VST3 IDの変更

プラグインIDを変更すると、DAWは新しいプラグインとして認識します。

```rust
impl Vst3Plugin for MyPlugin {
    // 16バイトの一意なID（変更すると別プラグインとして認識される）
    const VST3_CLASS_ID: [u8; 16] = *b"MyPluginUniqueID";
}
```

## バージョン管理

### Cargo.tomlでのバージョン指定

```toml
[package]
name = "my-plugin"
version = "0.2.0"  # セマンティックバージョニング
```

### プラグインでの参照

```rust
impl Plugin for MyPlugin {
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
}
```

## リリースチェックリスト

1. [ ] バージョン番号を更新（Cargo.toml）
2. [ ] `cargo test` で全テスト通過
3. [ ] `cargo clippy` で警告なし
4. [ ] `cargo fmt --check` でフォーマット確認
5. [ ] リリースビルド作成
6. [ ] 署名実行
7. [ ] DAWでの動作確認
8. [ ] Git タグ作成
