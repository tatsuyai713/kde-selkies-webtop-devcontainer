# kde-selkies-webtop-devcontainer

**[English Version (README_en.md)](README_en.md)**

ブラウザからアクセス可能なコンテナ化されたKubuntu (KDE Plasma) デスクトップ環境。Selkies WebRTCストリーミングを使用し、VNC/RDPなしでフル機能のLinuxデスクトップを提供します。VS Code Dev Containerにも対応。

### 機能対応表（プラットフォーム）

| 環境 | GPUレンダリング | WebGL/Vulkan | ハードウェアエンコード | 備考 |
|------|----------------|--------------|----------------------|------|
| **Ubuntu + NVIDIA GPU** | ✅ 対応 | ✅ 対応 | ✅ NVENC | 高パフォーマンス |
| **Ubuntu + Intel GPU** | ✅ 対応 | ✅ 対応 | ✅ VA-API (QSV) | 統合GPU可 |
| **Ubuntu + AMD GPU** | ✅ 対応 | ✅ 対応 | ✅ VA-API | RDNA/GCN対応 |
| **WSL2 + NVIDIA GPU** | ❌ ソフトウェア | ❌ ソフトウェアのみ | ✅ NVENC | WSL2で動作確認済み |
| **macOS (Docker)** | ❌ 非対応 | ❌ ソフトウェアのみ | ❌ 非対応 | VM制限 |

---

## クイックスタート

```bash
# 1. ユーザーイメージをビルド（1-2分）
# ベースイメージはGHCRから自動取得されます
./build-user-image.sh                                         # 英語環境
./build-user-image.sh -l ja                                   # 日本語環境
./build-user-image.sh -u 22.04                                # Ubuntu 22.04

# 2. コンテナを起動
./start-container.sh                                          # 対話設定で起動
./start-container.sh --encoder software                       # ソフトウェアエンコード
./start-container.sh --encoder nvidia --all                   # NVIDIA NVENC（全GPU）
./start-container.sh --encoder nvidia --num 0                 # NVIDIA NVENC（GPU 0のみ）
./start-container.sh --encoder intel                          # Intel VA-API
./start-container.sh --encoder amd -r 1920x1080 -S 0.5        # AMD VA-API + 実解像度半分
./start-container.sh --encoder nvidia-wsl --all               # WSL2 + NVIDIA NVENC

# 3. ブラウザでアクセス
# → https://localhost:<30000+UID> (例: UID=1000 → https://localhost:31000)
# → http://localhost:<40000+UID>  (例: UID=1000 → http://localhost:41000)

# 4. 変更を保存（重要！コンテナ削除前に必ず実行）
./commit-container.sh

# 5. 停止
./stop-container.sh                    # 停止（コンテナ保持、再起動可能）
./stop-container.sh --rm               # 停止して削除（commitした後のみ推奨）
```

`./start-container.sh` を引数なしで実行すると、`create-devcontainer-config.sh` と同じ項目を対話形式で設定できます。

### VS Code Dev Container を使用する場合

```bash
# 1. Dev Container設定を生成
./create-devcontainer-config.sh

# start-container.sh と同じ対話項目を使用:
# container name / Ubuntu / arch / docker mode / encoder / GPU / resolution / DPI
# stream scale / framerate / timezone / SSL / Mac settings

# 2. VS Codeで開く
# VS Codeで「F1」→「Dev Containers: Reopen in Container」を選択

# 3. コンテナ内でワークスペースが自動的に開きます
# ブラウザから https://localhost:<表示されたポート> でデスクトップにアクセス
```

---

## 🚀 このプロジェクトの特徴

### アーキテクチャの改善

- **🏗️ 2段階ビルドシステム**: ベースイメージ（5-10 GB）とユーザーイメージ（~100 MB、1-2分でビルド）を分離
  - ベースイメージはシステムパッケージとデスクトップ環境を含む
  - ユーザーイメージはあなたのUID/GIDに合わせたユーザーを追加
  - 毎回30-60分待つ必要なし！

- **🔒 非rootコンテナ実行**: デフォルトでユーザー権限で実行
  - `fakeroot`ハックや権限エスカレーション回避策を削除
  - システムとユーザー操作の適切な権限分離
  - 必要時はsudoアクセス可能

- **📁 自動UID/GID一致**: ファイル権限がシームレスに動作
  - ユーザーイメージが自動的にホストのUID/GIDに一致
  - マウントしたホストディレクトリの所有権が正しく設定
  - 共有フォルダでの「permission denied」エラーなし

### ユーザー体験の向上

- **🔐 セキュアパスワード管理**: 環境変数でパスワード入力
  - コマンドにパスワードを平文で表示しない
  - イメージ内に安全に保存

- **💻 Ubuntu Desktop標準環境**: 完全な`.bashrc`設定
  - Git branch検出付きカラープロンプト
  - ヒストリー最適化（重複無視、追記モード、タイムスタンプ）
  - 便利なエイリアス（ll, la, grep色付けなど）

- **🎮 柔軟な起動設定**: 対話/CLI の両方で同じ設定項目を利用可能
  - `--encoder nvidia` - NVIDIA NVENC
  - `--encoder intel` - Intel VA-API
  - `--encoder amd` - AMD VA-API
  - `--encoder software` - ソフトウェアエンコード
  - `--all` / `--num 0,1` - Docker GPU割り当て（`docker --gpus`、encoder と独立）
  - `-S 0.5` - 実際の配信解像度を 50% に縮小
  - `--docker-mode dind|dood` - コンテナ内 Docker かホスト Docker socket を選択

### 開発者体験

- **📦 バージョン固定**: 再現可能なビルドを保証
  - VirtualGL 3.1.4、Selkies 1.6.2
  - 「昨日は動いた」問題なし

- **🛠️ 完全な管理スクリプト**: 全操作用シェルスクリプト
  - `build-user-image.sh` - パスワード付きビルド
  - `start-container.sh` - 対話/CLI で起動、既存コンテナは自動再利用
  - `create-devcontainer-config.sh` - 同じ設定項目で Dev Container 設定を生成
  - `stop/shell-container.sh` - ライフサイクル管理
  - `commit-container.sh` - 変更を保存

- **🌐 多言語サポート**: 日本語環境対応
  - ビルド時に`-l ja`で日本語入力（Mozc）
  - タイムゾーン（Asia/Tokyo）とロケール（ja_JP.UTF-8）自動設定
  - fcitx入力メソッドフレームワーク含む
  - 英語がデフォルト

### なぜこのフォーク？

| 元プロジェクト | このフォーク |
|---------------|-------------|
| Pull可能イメージ | ローカルビルド（1-2分） |
| rootコンテナ | ユーザー権限コンテナ |
| 手動UID/GID設定 | 自動マッチング |
| コマンドにパスワード | 環境変数で安全に |
| 汎用bash | Ubuntu Desktop bash |
| GPU自動検出 | エンコーダー/GPU明示的選択 |
| バージョンドリフト | バージョン固定 |
| 英語のみ | 多言語（EN/JP） |

---

## 目次

- [システム要件](#システム要件)
- [2段階ビルドシステム](#2段階ビルドシステム)
- [Intel/AMD GPUホストセットアップ](#intelamd-gpuホストセットアップ)
- [セットアップ（通常使用）](#セットアップ通常使用)
- [使い方](#使い方)
- [付録: ベースイメージのビルド](#付録-ベースイメージのビルド)
- [付録: スクリプトリファレンス](#付録-スクリプトリファレンス)
- [付録: 設定](#付録-設定)
- [付録: HTTPS/SSL](#付録-httpsssl)
- [トラブルシューティング](#トラブルシューティング)
- [既知の制限](#既知の制限)
- [付録: 高度なトピック](#付録-高度なトピック)

---

## システム要件

### 必須
- **Docker** 20.10以降（Docker Desktop 4.0+）
- **8GB以上のRAM**（16GB推奨）
- **20GB以上のディスク空き容量**

### GPU（オプション、ハードウェアアクセラレーション用）
- **NVIDIA GPU** ✅ テスト済み
  - ドライバーバージョン 470以降
  - Maxwell世代以降
  - NVIDIA Container Toolkit インストール済み
- **Intel GPU** ✅ テスト済み
  - Intel統合グラフィックス（HD Graphics, Iris, Arc）
  - Quick Sync Videoサポート
  - VA-APIドライバはコンテナに含む
  - **ホストセットアップ必要**（下記参照）
- **AMD GPU** ⚠️ 部分的にテスト済み
  - VCE/VCNエンコーダー搭載Radeonグラフィックス
  - VA-APIドライバはコンテナに含む
  - **ホストセットアップ必要**（下記参照）

## 2段階ビルドシステム

このプロジェクトは高速セットアップと適切なファイル権限のために2段階ビルドアプローチを使用：

```
┌─────────────────────────┐
│   ベースイメージ (5-10 GB)  │  ← 初回のみビルド（30-60分）
│  • 全システムパッケージ    │
│  • デスクトップ環境       │
│  • プリインストールアプリ  │
└────────────┬────────────┘
             │
             ↓ これを基にビルド
┌────────────┴────────────┐
│ ユーザーイメージ (~100 MB) │  ← あなたがビルド（1-2分）
│  • あなたのユーザー名      │
│  • あなたのUID/GID        │
│  • あなたのパスワード      │
└─────────────────────────┘
```

**メリット:**

- ✅ **高速セットアップ:** 30-60分のビルド待ち不要
- ✅ **適切な権限:** ファイルがホストのUID/GIDに一致
- ✅ **簡単な更新:** 新しいベースイメージをビルド、ユーザーイメージを再ビルド

**なぜUID/GID一致が重要？**

- ホストディレクトリ（`$HOME`など）をマウントする際、ファイルに一致する所有権が必要
- UID/GID不一致だと権限エラーが発生
- ユーザーイメージが自動的にホストの認証情報に一致

---

## Intel/AMD GPUホストセットアップ

Intel/AMD GPUでハードウェアエンコード（VA-API）を使用する場合、ホスト側のセットアップが必要：

### 1. ユーザーをvideo/renderグループに追加

コンテナがGPUデバイス（`/dev/dri/*`）にアクセスするには、ホストユーザーが`video`と`render`グループのメンバーである必要があります：

```bash
# video/renderグループに追加
sudo usermod -aG video,render $USER

# ログアウト＆再ログインまたは再起動してグループ変更を適用
# 確認:
groups
# 出力に "video" と "render" が含まれていることを確認
```

### 2. VA-APIドライバーのインストール（Intel）

IntelGPUハードウェアエンコード用：

```bash
# VA-APIツールとIntelドライバーをインストール
sudo apt update
sudo apt install vainfo intel-media-va-driver-non-free

# インストール確認（H.264エンコードサポートを確認）:
vainfo
# 出力に "VAProfileH264Main : VAEntrypointEncSlice" などが含まれていることを確認
```

### 3. VA-APIドライバーのインストール（AMD）

AMD GPUハードウェアエンコード用：

```bash
# VA-APIツールとAMDドライバーをインストール
sudo apt update
sudo apt install vainfo mesa-va-drivers

# インストール確認:
vainfo
# 出力に "VAProfileH264Main : VAEntrypointEncSlice" などが含まれていることを確認
```

**注意:**
- NVIDIA GPUはこのセットアップ不要
- ホストでVA-APIが正しく動作すれば、コンテナでも自動的に動作
- グループ変更後は必ずログアウト/再ログインまたは再起動

---

## セットアップ（通常使用）

ベースイメージはGHCRから自動取得されるため、通常利用ではビルド不要です。

### ユーザーイメージのビルド

UID/GIDが一致するパーソナルイメージを作成（1-2分）：

```bash
# 英語（デフォルト）
./build-user-image.sh

# 日本語
./build-user-image.sh -l ja
```

※ `USER_PASSWORD=...` を先に付けると対話プロンプトを省略できます。

**オプション: カスタマイズ**

```bash
# Ubuntu 22.04を使用
./build-user-image.sh -u 22.04

# 別バージョン
./build-user-image.sh -v 2.0.0

# 別のベースイメージを使用
./build-user-image.sh -b my-custom-base:1.1.0
```

---

## 使い方

### コンテナの起動

`start-container.sh` は 2 通りの使い方があります。

```bash
# 対話モード
./start-container.sh

# CLI モード
./start-container.sh --encoder software
./start-container.sh --encoder nvidia --all
./start-container.sh --encoder nvidia --num 0
./start-container.sh --encoder intel --dri-node /dev/dri/renderD129
./start-container.sh --encoder amd -r 2560x1440 -d 144 -S 0.5
./start-container.sh --encoder nvidia-wsl --all --docker-mode dood
./start-container.sh --encoder software -a amd64              # docker run --platform linux/amd64 を自動付与
```

**対話モードで設定できる項目（Dev Container 作成時と同一）:**

- container name
- Ubuntu version
- target architecture
- docker mode (`dind` / `dood`)
- encoder type
- Docker GPU selection (`--all` / `--num`)
- DRI node
- resolution / DPI / stream scale / framerate
- timezone / language
- SSL directory
- Mac / Docker Desktop settings

**既存コンテナがある場合の挙動:**

- 同名コンテナが停止中なら、以前の設定のまま再開
- 同名コンテナが起動中なら、そのまま終了
- その場合は対話項目は表示されません

**UIDベースのポート割り当て（マルチユーザー対応）:**

ポートは自動的にユーザーIDに基づいて割り当てられ、同一ホストで複数ユーザーが使用可能：

- **HTTPSポート**: `30000 + UID`（例: UID 1000 → ポート 31000）
- **HTTPポート**: `40000 + UID`（例: UID 1000 → ポート 41000）

アクセス: `https://localhost:${HTTPS_PORT}`（例: UID 1000で `https://localhost:31000`）

**リモートアクセス（LAN/WAN）:**

WebRTCによるリモートアクセスが可能：

- LAN IPアドレスを自動検出
- リモートPCからアクセス: `https://<host-ip>:<https-port>`

**コンテナの特徴:**

- **コンテナ永続化:** 停止しても削除されない（再起動またはcommit可能）
- **ホスト名:** `Docker-$(hostname)`に設定
- **ホストホームマウント:** `~/host_home`で利用可能
- **コンテナ名:** `linuxserver-kde-{username}`
- **docker mode:** `dind` はコンテナ内 `dockerd`、`dood` はホスト `/var/run/docker.sock` を利用
- **STREAM_SCALE:** 表示だけでなく、エンコード前の実解像度も縮小

### 変更の保存（重要！）

ソフトウェアをインストールしたり設定を変更した場合：

```bash
# コンテナ状態をイメージに保存
./commit-container.sh
```

**重要な注意:**

- ⚠️ **`./stop-container.sh --rm`の前に必ずcommit** - commitしないと変更が失われます
- ✅ イメージ名形式は `webtop-kde-{username}-{arch}:{version}`
- ✅ commitしたイメージはコンテナ削除後も残る
- ✅ 次回起動時は自動的にcommitしたイメージを使用

**ワークフロー例:**

```bash
# 1. コンテナ内で作業、ソフトウェアインストール、設定変更
./shell-container.sh
# ... パッケージインストール、環境設定 ...
exit

# 2. 変更をイメージに保存
./commit-container.sh

# 3. コンテナを安全に停止・削除（変更はイメージに保存済み）
./stop-container.sh --rm

# 4. 次回起動時、commitしたイメージで全変更が反映
./start-container.sh --encoder intel
```

### コンテナの停止

```bash
# 停止（再起動またはcommit用に保持）
./stop-container.sh

# 停止して削除
./stop-container.sh --rm
# または
./stop-container.sh -r
```

---

## 付録: ベースイメージのビルド

ベースイメージは初回のみビルドが必要（30-60分）：

```bash
# デフォルトのリポジトリ: ghcr.io/tatsuyai713/webtop-kde
# ホストアーキテクチャに合わせて自動検出
./files/build-base-image.sh                         # Ubuntu 24.04 (デフォルト)
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04

# または明示的に指定
./files/build-base-image.sh -a amd64                # Intel/AMD 64-bit
./files/build-base-image.sh -a arm64                # Apple Silicon / ARM
./files/build-base-image.sh -a amd64 -u 22.04       # AMD64 + Ubuntu 22.04

# キャッシュなしでビルド（問題がある場合）
./files/build-base-image.sh --no-cache

# GHCRに保存する場合（デフォルトのリポジトリ名を使用）
./files/push-base-image.sh

# リポジトリ名を変える場合
IMAGE_NAME=ghcr.io/tatsuyai713/your-base ./files/build-base-image.sh
IMAGE_NAME=ghcr.io/tatsuyai713/your-base ./files/push-base-image.sh
```

---

## 付録: スクリプトリファレンス

### コアスクリプト

| スクリプト | 説明 | 使い方 |
|--------|-------------|-------|
| `files/build-base-image.sh` | ベースイメージをビルド | `./files/build-base-image.sh [-a arch]` |
| `build-user-image.sh` | ユーザー固有イメージをビルド | `./build-user-image.sh [-l ja]` |
| `start-container.sh` | デスクトップコンテナを起動/再開 | `./start-container.sh` または `./start-container.sh --encoder <type>` |
| `create-devcontainer-config.sh` | Dev Container設定を生成 | `./create-devcontainer-config.sh` |
| `stop-container.sh` | コンテナを停止 | `./stop-container.sh [--rm]` |

### 管理スクリプト

| スクリプト | 説明 | 使い方 |
|--------|-------------|-------|
| `shell-container.sh` | コンテナシェルにアクセス | `./shell-container.sh` |
| `commit-container.sh` | コンテナ変更をイメージに保存 | `./commit-container.sh` |
| `files/push-base-image.sh` | ベースイメージをGHCRへPush | `./files/push-base-image.sh` |

### 起動オプション詳細

```bash
./start-container.sh [オプション]

主なオプション:
  -e, --encoder <type>        software|nvidia|nvidia-wsl|intel|amd
  -g, --gpu <value>           Docker --gpus 値: all または device=0,1
  --all                       --gpu all のショートカット
  --num <list>                --gpu device=<list> のショートカット
  --dri-node <path>           Intel/AMD 用の render node を明示
  -r <WxH>                    解像度（例: 1920x1080）
  -d <dpi>                    DPI（例: 96, 144, 192）
  -S <factor>                 実配信解像度の倍率（0.25-1.0）
  -f <fps|min-max>            フレームレート（例: 30, 30-60）
  --timezone <tz>             タイムゾーン（例: Asia/Tokyo）
  --docker-mode <mode>        dind または dood
  -a <arch>                   amd64 / arm64
  -p <platform>               docker run --platform を明示指定
  -s <ssl_dir>                SSL証明書ディレクトリ
```

---

## 付録: 設定

### 表示設定

```bash
# 解像度とDPI
./start-container.sh -r 1920x1080 -d 96              # 標準
./start-container.sh -r 2560x1440 -d 144             # WQHD HiDPI
./start-container.sh -r 3840x2160 -d 192             # 4K HiDPI

# STREAM_SCALE（実際の配信解像度を縮小）
./start-container.sh --encoder software -r 1920x1080 -S 0.5
# 1920x1080 のウィンドウを 960x540 でエンコードして配信
```

### ビデオエンコード

**ハードウェアエンコード (Pixelflux):**

| GPU | エンコーダー | 品質 | CPU負荷 |
|-----|-------------|------|---------|
| NVIDIA | NVENC | 高 | 低 |
| Intel | VA-API (Quick Sync) | 高 | 低 |
| AMD | VA-API | 高 | 低 |
| なし | Software (libx264) | 中 | 高 |

エンコーダーは `--encoder` に基づいて選択されます。`-S/--stream-scale` を指定すると、表示だけでなくエンコード前の実解像度自体を縮小するため、帯域だけでなく encoder 負荷の削減にも効きます。

### オーディオ設定

**オーディオサポート:**

| 機能 | サポート | 技術 |
|------|---------|------|
| スピーカー出力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |
| マイク入力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |

Selkiesは双方向オーディオをブラウザにWebRTC経由でストリーミングします。

---

## 付録: HTTPS/SSL

### SSL証明書の設定

```bash
# 1. ssl/ディレクトリを作成
mkdir -p ssl

# 2. 証明書を配置
cp /path/to/your/cert.pem ssl/
cp /path/to/your/key.pem ssl/cert.key

# 3. コンテナ起動（ssl/フォルダを自動検出）
./start-container.sh --encoder nvidia --all
```

### 自己署名証明書の生成

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/cert.key -out ssl/cert.pem \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dev/CN=localhost"
```

### 証明書の優先順位

`start-container.sh`スクリプトは以下の順序で証明書を自動検出：

1. `ssl/cert.pem`と`ssl/cert.key`
2. 環境変数`SSL_DIR`
3. 証明書が見つからない場合はイメージのデフォルト証明書を使用

---

## トラブルシューティング

### コンテナが起動しない

```bash
# ログを確認
docker logs linuxserver-kde-$(whoami)

# イメージが存在するか確認
docker images | grep webtop-kde

# ユーザーイメージを再ビルド
./build-user-image.sh

# ポートが使用中か確認
sudo netstat -tulpn | grep -E "31000|41000"
```

### GPUが検出されない

```bash
# NVIDIA
./shell-container.sh
nvidia-smi

# Intel/AMD
./shell-container.sh
ls -la /dev/dri/
vainfo

# Docker GPUアクセス確認
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### 権限の問題

```bash
# UID一致確認
id  # ホスト上
./shell-container.sh
id  # コンテナ内

# UID/GID不一致の場合、ユーザーイメージを再ビルド
./build-user-image.sh
```

### 黒画面 / デスクトップが表示されない

```bash
# ログ確認
docker logs linuxserver-kde-$(whoami)

# plasmashellの状態確認
docker exec linuxserver-kde-$(whoami) pgrep -af plasmashell

# ランタイムディレクトリ確認
docker exec linuxserver-kde-$(whoami) ls -la /run/user/$(id -u)
```

**原因と対処:**
- `/run/user/<uid>`が存在しない/権限が不正 → コンテナ再起動
- plasmashellがクラッシュ → コンテナ再起動

### WebGL/Vulkanが動かない

```bash
# OpenGL情報
docker exec linuxserver-kde-$(whoami) glxinfo | head -30

# Vulkan情報
docker exec linuxserver-kde-$(whoami) vulkaninfo | head -50
```

**macOSの場合:** Docker VMの制限により、GPUアクセラレーションは不可。ソフトウェアレンダリングで動作。

### 音声が出ない

```bash
# PulseAudioサーバー確認
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl info'

# シンク一覧
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl list sinks short'
```

**対処:**
- ブラウザのオーディオ権限を確認
- HTTPS接続を使用（一部ブラウザはHTTPでオーディオをブロック）

---

## 既知の制限

### Vulkanの制限

- XvfbはDRI3をサポートしていないため、Vulkanアプリケーションはフレームをプレゼントできず動作しません
- VirtualGLを使用したOpenGLアプリケーションは正常に動作します
- 環境によってはXvfb上でもvkcubeが動作しNVIDIA GPUを認識します（ただし表示/presentの挙動は構成依存です）

### macOSの制限

- Docker Desktop for MacはLinux VM内でコンテナを実行するため、Apple GPU（Metal）へのアクセス不可
- WebGL/Vulkanはソフトウェアレンダリング（llvmpipe）で動作
- ハードウェアアクセラレーションが必要な場合はLinux実機またはWSL2を使用

### WSL2 GPUメモ

- WSL2はNVIDIAのみ対応
- WSL2ではレンダリングはソフトウェア（llvmpipe）になり、WebGL/Vulkanもソフトウェア動作

---

## 付録: 高度なトピック

### 環境変数リファレンス

<details>
<summary>クリックで環境変数一覧を展開</summary>

#### コンテナ設定

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `CONTAINER_NAME` | コンテナ名 | `linuxserver-kde-$(whoami)` |
| `IMAGE_BASE` | イメージベース名 | `webtop-kde` |
| `IMAGE_VERSION` | イメージバージョン | `1.1.0` |

#### 表示

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `RESOLUTION` | 解像度 | `1920x1080` |
| `DPI` | DPI設定 | `96` |
| `STREAM_SCALE` | 実配信解像度の倍率 | `1.0` |
| `FRAMERATE` | Selkies フレームレート | `30-60` |
| `TIMEZONE` | タイムゾーン | `UTC` |

#### GPU

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `ENCODER` | エンコーダー種別 | 未設定 |
| `GPU_VENDOR` | GPUベンダー | `software` |
| `DOCKER_MODE` | Docker モード | `dind` |

#### ネットワーク

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `PORT_SSL_OVERRIDE` | HTTPSポート上書き | `UID+30000` |
| `PORT_HTTP_OVERRIDE` | HTTPポート上書き | `UID+40000` |

</details>

### プロジェクト構造

```
devcontainer-ubuntu-kde-selkies-for-mac/
├── build-user-image.sh           # ユーザーイメージビルド
├── start-container.sh            # コンテナ起動
├── create-devcontainer-config.sh # Dev Container設定生成
├── compose-env.sh                # compose/devcontainer 用 env 生成
├── interactive-common.sh         # 対話設定の共通処理
├── stop-container.sh             # コンテナ停止
├── shell-container.sh            # シェルアクセス
├── commit-container.sh           # 変更保存
├── ssl/                          # SSL証明書（自動検出）
│   ├── cert.pem
│   └── cert.key
└── files/                        # システムファイル
    ├── build-base-image.sh       # ベースイメージビルド
    ├── push-base-image.sh        # ベースイメージをPush
    ├── linuxserver-kde.base.dockerfile   # ベースイメージ定義
    ├── linuxserver-kde.user.dockerfile   # ユーザーイメージ定義
    ├── alpine-root/              # s6-overlay設定
    ├── kde-root/                 # KDE設定
    └── ubuntu-root/              # Ubuntu設定
```

### バージョン固定

再現可能なビルドのため、外部依存関係は特定バージョンに固定：

- **VirtualGL:** 3.1.4
- **Selkies + Pixelflux:** Selkies WebRTCストリーミングとPixelfluxエンコーダー

**ハードウェアエンコード:**
- **NVIDIA GPU:** Pixelflux経由でNVENC自動検出
- **Intel GPU:** Pixelflux経由でVA-API (Quick Sync Video)
- **AMD GPU:** Pixelflux経由でVA-API

これらは [files/linuxserver-kde.base.dockerfile](files/linuxserver-kde.base.dockerfile) でビルド引数として定義。

---

## ライセンス

**メインプロジェクト:**

このプロジェクトは複数のオープンソースプロジェクトを基にしています：
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) - GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) - LGPL

詳細は各プロジェクトのライセンスを参照してください。

---

## 関連プロジェクト

- [tatsuyai713/devcontainer-egl-desktop](https://github.com/tatsuyai713/devcontainer-egl-desktop) - EGLベース版（3つの表示モード対応）
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) - 元プロジェクト
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - WebRTCストリーミング

---

## クレジット

### 元プロジェクト

- **Selkies Project:** [github.com/selkies-project](https://github.com/selkies-project)
- **LinuxServer.io:** [github.com/linuxserver](https://github.com/linuxserver)

### このフォーク

- **強化:** 2段階ビルドシステム、非root実行、UID/GID一致、セキュアパスワード管理、管理スクリプト、バージョン固定、マルチGPU対応
- **メンテナー:** [@tatsuyai713](https://github.com/tatsuyai713)
