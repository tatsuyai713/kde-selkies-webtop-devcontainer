# kde-selkies-webtop-devcontainer

**[English Version (README.md)](README.md)**

ブラウザからアクセスできるコンテナ化された Kubuntu (KDE Plasma) デスクトップ環境。Selkies WebRTC ストリーミングにより、VNC や RDP なしでフル機能の Linux デスクトップを提供します。

**Ubuntu/Linux**、**macOS (Docker Desktop)**、**WSL2** に対応。すべてのプラットフォームで `build-user-image.sh`、`start-container.sh`、`create-devcontainer-config.sh` を共通の入口として利用できます。

## なぜこのプロジェクト？

[linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) をベースに、開発者の使いやすさとマルチプラットフォーム対応を重視したフォークです。

| | オリジナル | このプロジェクト |
|---|---|---|
| **イメージ提供** | Pull 可能なイメージ | 2段階ローカルビルド（ユーザーイメージは1-2分） |
| **コンテナユーザー** | Root | あなたの UID/GID（非root） |
| **UID/GID 設定** | 手動 | 自動マッチング |
| **パスワード** | コマンドに平文 | 環境変数で安全に |
| **シェル** | 汎用 bash | Ubuntu Desktop bash（カラープロンプト、Git ブランチ、エイリアス） |
| **GPU 選択** | 自動検出 | 明示的な `--encoder` / `--gpu` フラグ |
| **依存バージョン** | 変動 | 固定（VirtualGL 3.1.4、Pixelflux 1.6.0、Selkies は最新 main / `SELKIES_COMMIT` で固定可能） |
| **Docker-in-Docker** | — | `--docker-mode dind\|dood` |
| **配信チューニング** | — | `-S` ストリームスケール、`-f` フレームレート制御 |
| **Dev Container** | — | `create-devcontainer-config.sh`（CLI と同じ設定項目） |
| **言語サポート** | 英語のみ | 多言語（EN/JA） |

## 主な特徴

- **2段階ビルド** — 重いベースイメージ（5-10 GB、一度だけ）＋軽量ユーザーイメージ（~100 MB、1-2分）。30-60分の待ち時間なし。
- **デフォルト非root** — コンテナはあなたのユーザー権限で実行。適切な権限分離、必要時は sudo 利用可能。
- **自動 UID/GID マッチング** — マウントしたホストディレクトリがそのまま動作。共有フォルダでの「permission denied」なし。
- **統一された設定** — `start-container.sh`（日常利用）と `create-devcontainer-config.sh`（VS Code Dev Container）が同じ対話設定を共有。
- **エンコーダー/GPU の明示的制御** — `--encoder nvidia|intel|amd|software|nvidia-wsl|intel-wsl|amd-wsl` でエンコーダーを選択。`--all`/`--num` で Docker GPU 割り当てを独立制御。
- **ストリームスケーリング** — `-S 0.5` でエンコード解像度を半分に。帯域とエンコーダー負荷の両方を削減。
- **Docker モード切替** — `--docker-mode dood`（ホスト socket）または `dind`（コンテナ内 dockerd）。
- **ブラウザのみでアクセス** — 起動後 `https://localhost:<30000+UID>` にアクセス。SSH/RDP の配布不要。
- **安全なパスワード** — 環境変数で設定。コマンドやログに表示されない。
- **多言語対応** — ビルド時に `-l jp` で日本語入力、タイムゾーン、ロケールを設定。
- **バージョン固定** — VirtualGL 3.1.4、Pixelflux 1.6.0、Selkies（デフォルトで最新 `main`、`SELKIES_COMMIT` ビルド引数で固定可能）により再現可能なビルドを保証。

## 対応環境

| 環境 | GPU レンダリング | WebGL / Vulkan | ハードウェアエンコード | 備考 |
|---|---|---|---|---|
| **Ubuntu + NVIDIA GPU** | ✅ | ✅ | ✅ NVENC | 最高パフォーマンス |
| **Ubuntu + Intel GPU** | ✅ | ✅ | ✅ VA-API (QSV) | 統合GPU可 |
| **Ubuntu + AMD GPU** | ✅ | ✅ | ✅ VA-API | RDNA / GCN |
| **WSL2 + NVIDIA GPU** | ✅ Mesa D3D12 | ✅ WebGL / ⚠️ Vulkan | ✅ NVENC | `/dev/dxg` 経由のOpenGL＋NVENC |
| **WSL2 + Intel GPU** | ✅ Mesa D3D12 | ✅ WebGL / ⚠️ Vulkan | ⚠️ VA-API (Mesa D3D12) | `--encoder intel-wsl`。エンコードは Windows ドライバの D3D12 Video Encode 対応が必要、非対応なら x264 にフォールバック |
| **WSL2 + AMD GPU** | ✅ Mesa D3D12 | ✅ WebGL / ⚠️ Vulkan | ⚠️ VA-API (Mesa D3D12) | `--encoder amd-wsl`。エンコードは Windows ドライバの D3D12 Video Encode 対応が必要、非対応なら x264 にフォールバック |
| **macOS (Docker Desktop)** | ❌ | ❌ ソフトウェア | ❌ | VM 制限あり。ワークフローは同一 |

---

## クイックスタート

```bash
# 1. ユーザーイメージをビルド（1-2分、ベースイメージは GHCR から自動取得）
./build-user-image.sh                    # 英語（デフォルト）
./build-user-image.sh -l jp              # 日本語環境
./build-user-image.sh -u 22.04           # Ubuntu 22.04
./build-user-image.sh -u 26.04           # Ubuntu 26.04（X11/Xvfb）

# 2. コンテナを起動
./start-container.sh                     # 対話設定
./start-container.sh --encoder software  # ソフトウェアエンコード
./start-container.sh --encoder nvidia --all          # NVIDIA NVENC（全GPU）
./start-container.sh --encoder nvidia --num 0        # NVIDIA NVENC（GPU 0のみ）
./start-container.sh --encoder intel                 # Intel VA-API
./start-container.sh --encoder amd -r 1920x1080 -S 0.5  # AMD + 配信解像度半分
./start-container.sh --encoder nvidia-wsl --all      # WSL2 + NVIDIA NVENC
./start-container.sh --encoder intel-wsl             # WSL2 + Intel（Mesa D3D12 OpenGL + VA-API）
./start-container.sh --encoder amd-wsl               # WSL2 + AMD（Mesa D3D12 OpenGL + VA-API）

# 3. ブラウザでアクセス
#    https://localhost:<30000+UID>（例: UID 1000 → https://localhost:31000）
#    http://localhost:<40000+UID> （例: UID 1000 → http://localhost:41000）

# 4. 変更を保存（重要！コンテナ削除前に必ず実行）
./commit-container.sh

# 5. 停止
./stop-container.sh            # 停止（コンテナ保持、再起動可能）
./stop-container.sh --rm       # 停止して削除（commit 後のみ推奨）
```

### プラットフォーム別の例

**Ubuntu / Linux**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder intel
```

**macOS (Docker Desktop)**
```bash
./build-user-image.sh -u 22.04 -a amd64
./start-container.sh --encoder software -a amd64 --docker-mode dood
```

**WSL2 + NVIDIA**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder nvidia-wsl --all
```

**WSL2 + Intel / AMD**
```bash
sudo modprobe vgem                        # 仮想 DRM レンダーノード（各スクリプトも対話的に提案）
./start-container.sh --encoder intel-wsl  # Docker GPU は「None」。--all は指定しない
```

### VS Code Dev Container

```bash
# 1. Dev Container 設定を生成（start-container.sh と同じ対話設定）
./create-devcontainer-config.sh

# 2. VS Code で F1 → 「Dev Containers: Reopen in Container」を選択

# 3. ブラウザから https://localhost:<表示されたポート> でデスクトップにアクセス
```

---

## 目次

- [なぜこのプロジェクト？](#なぜこのプロジェクト)
- [主な特徴](#主な特徴)
- [対応環境](#対応環境)
- [クイックスタート](#クイックスタート)
- [システム要件](#システム要件)
- [2段階ビルドシステム](#2段階ビルドシステム)
- [Intel/AMD GPU ホストセットアップ](#intelamd-gpu-ホストセットアップ)
- [セットアップ（ユーザーイメージのビルド）](#セットアップユーザーイメージのビルド)
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

- **Docker** 20.10 以降（Docker Desktop 4.0+）
- **8 GB 以上の RAM**（16 GB 推奨）
- **20 GB 以上のディスク空き容量**

### GPU（オプション — ハードウェアアクセラレーション用）

- **NVIDIA GPU** ✅ テスト済み
  - ドライバー 470 以降、Maxwell 世代以降
  - NVIDIA Container Toolkit インストール済み
- **Intel GPU** ✅ テスト済み
  - 統合グラフィックス（HD Graphics、Iris、Arc）、Quick Sync Video 対応
  - VA-API ドライバーはコンテナに含まれる
  - **ホストセットアップ必要**（下記参照）
- **AMD GPU** ⚠️ 部分的にテスト済み
  - VCE/VCN エンコーダー搭載 Radeon
  - VA-API ドライバーはコンテナに含まれる
  - **ホストセットアップ必要**（下記参照）

---

## 2段階ビルドシステム

```
┌─────────────────────────────┐
│   ベースイメージ (5-10 GB)    │  ← 一度だけビルド（30-60分）または GHCR から取得
│  • システムパッケージ         │
│  • デスクトップ環境           │
│  • プリインストールアプリ     │
└────────────┬────────────────┘
             │
             ↓  この上にビルド
┌────────────┴────────────────┐
│ ユーザーイメージ (~100 MB)    │  ← あなたがビルド（1-2分）
│  • あなたのユーザー名         │
│  • あなたの UID/GID          │
│  • あなたのパスワード         │
└─────────────────────────────┘
```

**メリット:**
- ✅ **高速セットアップ** — 30-60分のビルド待ち不要
- ✅ **適切な権限** — ファイルがホストの UID/GID に一致
- ✅ **簡単な更新** — 新しいベースイメージを取得してユーザーイメージを再ビルド

**なぜ UID/GID マッチングが重要か:**
ホストディレクトリ（例: `$HOME`）をマウントするにはファイルの所有権が一致する必要があります。不一致だと権限エラーが発生します。ユーザーイメージがこれを自動的に処理します。

---

## Intel/AMD GPU ホストセットアップ

通常LinuxとWSL2ではGPUの渡し方が異なります。Dockerの `--gpus` / 本プロジェクトの
`--all`・`--num` はNVIDIA Container Toolkit用です。Intel/AMDだけの環境では指定しないでください。

### WSL2 + Intel の事前確認

1. Windows側で最新のIntelグラフィックスドライバーを導入し、PowerShellで `wsl --update`、
   続いて `wsl --shutdown` を実行してWSLを再起動します。WSL内にLinux用Intelカーネル
   ドライバーを追加する必要はありません。GPUはWindowsのWDDMドライバーを通じて公開されます。
   Windowsが認識しているアダプターとドライバーバージョンは次で確認できます。

```powershell
Get-CimInstance Win32_VideoController |
  Select-Object Name, DriverVersion, Status
```

2. WSL内で次を確認します。

```bash
# WSL2カーネルであること
uname -r | grep -i microsoft

# Windows GPUへの入口とWSLgのD3D12ライブラリ
test -c /dev/dxg && echo "OK: /dev/dxg"
test -f /usr/lib/wsl/lib/libd3d12.so && echo "OK: libd3d12.so"
test -f /usr/lib/wsl/lib/libdxcore.so && echo "OK: libdxcore.so"

# vgemとDRMノード。再起動後も必要なら /etc/modules-load.d/vgem.conf に vgem を記載
sudo modprobe vgem
ls -l /dev/dri/renderD128

# Docker daemonと容量
docker version
docker info
df -h /var/lib/docker
```

`/dev/dri/renderD128` はIntel GPUそのものではなく、`vgem` が作る仮想DRMノードです。
実GPUは `/dev/dxg` + `/usr/lib/wsl` を介してMesa D3D12から利用します。そのため、WSLホストで
`vainfo` を単独実行して失敗しても、それだけではGPU非検出とは判断できません。コンテナ起動後の
確認を優先してください。

```bash
./start-container.sh --encoder intel-wsl   # --all / --gpu は付けない
./check-wsl-gpu.sh linuxserver-kde-$(whoami)
```

Microsoft公式のWSLgコンテナ手順に従い、D3D12 VA-APIのデバイスには `/dev/dri/card0` を使います。
`renderD128` ではなくcard0を使い、かつ `MESA_LOADER_DRIVER_OVERRIDE` を外す必要があります。

```bash
docker exec linuxserver-kde-$(whoami) bash -lc \
  'env -u MESA_LOADER_DRIVER_OVERRIDE LIBVA_DRIVER_NAME=d3d12 GALLIUM_DRIVER=d3d12 \
   vainfo --display drm --device /dev/dri/card0'
```

一括診断には次を使います。Windowsドライバー、WSLのデバイス、コンテナのIntel D3D12
OpenGLレンダラー、VA-API列挙に加え、1秒のH.264を実際にエンコードしてフレーム数まで検証します。
`vainfo` が成功しても実データが0 bytesなら警告になるため、見かけだけの対応を判別できます。

```bash
./check-wsl-gpu.sh linuxserver-kde-$(whoami)
```

`intel-wsl` の既定は `WSL_GPU_MODE=full` です。KWin、Plasma/Qt Quick、アプリケーションと
PixelfluxのWayland描画を、選択したIntel GPU上のMesa D3D12で実行します。H.264 Encodeは
専用FFmpeg子プロセス内でMesa 25.2.8 D3D12 VAドライバーと`wsl-vaapi-serialize`同期シムを使い、
デスクトップOpenGLは現行Mesaのままです。このプロセス分離は必須です。同一Pixelfluxプロセスへ
OpenGLとVA-APIのD3D12スタックをロードすると`vaCreateSurfaces`が失敗し、その後Intelの
`libigd12dxva64.so`内でfaultして親WaylandとPlasmaまで落ちました。frame readbackはデータ転送で、
H.264圧縮はIntel GPU VA-APIのままです。既定はVBR目標4 Mbps・最大8 Mbpsで、CBR互換時も8 Mbpsを
超えません。
[試験結果と制約](files/pixelflux/README.md#intel-wsl-va-api-synchronization)も参照してください。
`applications`と`software`は明示的な診断用に残していますが、自動回避策としては使いません。

Pixelflux 2.0はVA-APIの`gop_size`を`INT_MAX`にしていたため、FFmpegがSPSへ
`log2_max_frame_num_minus4=27`を出力していました。H.264仕様の上限は12なので、Edgeだけでなく
FFmpegもこのStreamを復号できません。さらにSelkies側はフレームレート引数を渡さず、I420
High@4.1の実映像を`High 4:2:2 @ Level 6.2`と誤申告していました。Google MeetでIntel Decodeが
動くのにこの画面だけ失敗したのは、EdgeやIntelドライバーではなく、この2つの配信側不具合が原因です。

Ubuntu 26.04 amd64ではPixelflux 2.0をsystem FFmpeg 8に対してビルドし、合法なGOP、1 slice、
Intel外部Encoderを含む同梱wheelを使います。フロントエンドは実SPSに合う`avc1.640C29`
（High 4:2:0、constraint byte `0x0c`、Level 4.1）と`prefer-hardware`を指定します。`init-nginx`がdashboardを更新した直後にも
hardware-decode patchを再適用するため、コンテナ再起動で`prefer-software`へ戻りません。

動きのあるデスクトップをEdgeで前面表示した実測では、Edge GPUプロセスのIntel
`engtype_VideoDecode`が最大5.4%（平均4.8%）、`3D`が最大5.81%でした。コンテナ側でもIntel
Video Engine最大17%、D3D12 3D最大14.09%を確認しています。したがって現在の確認結果は
**Intel GPU OpenGLデスクトップ + Intel GPU VA-API Encode + Edge Intel GPU Decode**です。
WebCodecsの`hardwareAcceleration`自体は仕様上ヒントなので、別ホストでは`edge://gpu`も確認してください。

KWinのGPUデスクトップ効果は次で確認できます。

```bash
WSL_GPU_MODE=full ./start-container.sh --encoder intel-wsl
docker exec linuxserver-kde-$(whoami) bash -lc \
  's6-setuidgid "$USER_NAME" qdbus6 org.kde.KWin /KWin supportInformation' \
  | grep -E 'Compositing Type|OpenGL renderer string'
```

黒画面になりログに `Failed to allocate GBM buffer`、`Could not find a suitable render format`、
または `D3D12: Removing Device` が出る場合は、まず `wsl_gpu_mode: "applications"` にします。
アプリとキャプチャはIntel GPUのまま、KWinだけQPainterになります。最終復旧手段が`software`です。

Encode回避は複数のWSL成功報告と一致します。Microsoft公式はD3D12 VA-API H.264 Encodeを説明し、
WSL issueではMesa 24.0.9で失敗した同じパイプラインがMesa 23.2.1への変更後に再び成功、
Frigate利用者もWSL Ubuntu 22.04でFFmpegのVP9→H.264 VA-API変換成功を報告しています。
この実機でもMesa 23.2.1は1280x720・30フレーム・1,169,109 bytesを生成し、Mesa 26は0フレームでした。
Jammyのグラフィックス一式を混在させず、イメージ内ではSelkies Encodeだけに旧VAドライバーを隔離します。
`wsl_intel_vaapi: ""` のままにし、`"1"`へ変更しないでください。

公式資料・再現報告:

- [Microsoft: Containerizing GUI applications with WSLg](https://github.com/microsoft/wslg/blob/main/samples/container/Containers.md)
- [Microsoft WSLg: Mesa D3D12でIntel/NVIDIA/AMDを選択する方法](https://github.com/microsoft/wslg/wiki/GPU-selection-in-WSLg)
- [Microsoft: Run Linux GUI apps with WSL（vGPU/OpenGL）](https://learn.microsoft.com/windows/wsl/tutorials/gui-apps)
- [Intel: Iris Xe Graphics Family drivers](https://www.intel.com/content/www/us/en/support/products/211012/graphics/processor-graphics/intel-iris-xe-graphics-family.html)
- [Intel: Configure WSL2 for GPU workflows](https://www.intel.com/content/www/us/en/docs/oneapi/installation-guide-linux/2025-1/configure-wsl-2-for-gpu-workflows.html)
- [Selkies: capture and encoder implementation](https://github.com/selkies-project/selkies/blob/main/docs/component.md)
- [Mesa: D3D12 driver](https://docs.mesa3d.org/drivers/d3d12.html)
- [Mesa 26.2.2 release notes](https://docs.mesa3d.org/relnotes/26.2.2.html)
- [Microsoft: D3D12 video encoding](https://learn.microsoft.com/windows-hardware/drivers/display/video-encoding-d3d12)
- [Microsoft: WSLのD3D12 GPU動画アクセラレーション（Encode成功例）](https://devblogs.microsoft.com/commandline/d3d12-gpu-video-acceleration-in-the-windows-subsystem-for-linux-now-available/)
- [Microsoft WSL issue #11838: Mesa 23.2.1でEncode復旧](https://github.com/microsoft/WSL/issues/11838)
- [Frigate discussion #11133: WSL Ubuntu 22.04でVA-API変換成功](https://github.com/blakeblackshear/frigate/discussions/11133#discussioncomment-9241829)
- [Microsoft WSLg issue #1458: Intel D3D12 VA-API/TDR report](https://github.com/microsoft/wslg/issues/1458)
- [Microsoft WSLg issue #1492: NVIDIA D3D12/Dozenの`vkCreateDevice` crash](https://github.com/microsoft/wslg/issues/1492)
- [NVIDIA: WSL上のFFmpeg GPU acceleration（NVENC/NVDEC）](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.1/ffmpeg-with-nvidia-gpu/index.html)
- [Pixelflux: VA-API/Wayland encoder implementation](https://github.com/linuxserver/pixelflux/blob/master/pixelflux/src/encoders/vaapi.rs)
- [Microsoft: EdgeのH.264 Decode確認方法](https://learn.microsoft.com/en-us/troubleshoot/microsoft-edge/development/video-playback-issues)
- [W3C WebCodecs: HardwareAcceleration preference](https://w3c.github.io/webcodecs/#enumdef-hardwareacceleration)

`failed to discover GPU vendor from CDI: no known GPU vendor found` で起動しない場合は、Intel用設定に
NVIDIA専用の `docker_gpus: "all"` が残っています。`configs/<コンテナ名>.yml` の値を空文字列にし、
作成途中のコンテナを削除してから再実行します。

```bash
docker rm linuxserver-kde-$(whoami)  # Status が Created の作成失敗コンテナだけを対象にする
./start-container.sh
```

### 通常LinuxのIntel/AMD

以下はWSL2ではなく、GPUが `/dev/dri` に直接公開されるLinuxホスト向けです。

### 1. ユーザーを video/render グループに追加

```bash
sudo usermod -aG video,render $USER
# ログアウト・再ログイン後に確認:
groups  # "video" と "render" が含まれていること
```

### 2. VA-API ドライバーのインストール

**Intel:**
```bash
sudo apt update && sudo apt install vainfo intel-media-va-driver-non-free
vainfo  # VAProfileH264Main : VAEntrypointEncSlice が表示されること
```

**AMD:**
```bash
sudo apt update && sudo apt install vainfo mesa-va-drivers
vainfo  # VAProfileH264Main : VAEntrypointEncSlice が表示されること
```

> 通常Linuxでは、ホストでVA-APIが正しく動作し、同じ `/dev/dri` を渡せればコンテナでも利用できます。

---

## セットアップ（ユーザーイメージのビルド）

ベースイメージは GHCR から自動取得されるため、通常利用では手動ビルド不要です。

```bash
# 英語（デフォルト）
./build-user-image.sh

# 日本語
./build-user-image.sh -l jp

# パスワードプロンプトをスキップ
USER_PASSWORD=yourpass ./build-user-image.sh
```

**オプション:**
```bash
./build-user-image.sh -u 22.04           # Ubuntu 22.04
./build-user-image.sh -u 26.04           # Ubuntu 26.04（X11/Xvfb）
./build-user-image.sh -v 2.0.0           # カスタムバージョン
./build-user-image.sh -b my-base:1.1.0   # カスタムベースイメージタグ
./build-user-image.sh -i ghcr.io/you/img  # カスタムベースイメージ名
./build-user-image.sh -a amd64           # アーキテクチャヒント
./build-user-image.sh -p linux/amd64     # 明示的なプラットフォーム指定
./build-user-image.sh -n                 # Docker キャッシュなしでビルド
```

---

## 使い方

### コンテナの起動

初回起動時は対話ウィザードが設定を `configs/<name>.yml` に保存し、次回以降はその設定を自動で読み込みます。
保存済みの設定を再編集するには `--reconfigure` を使用します。

```bash
# 初回起動 — すべての設定を入力して保存
./start-container.sh

# 再設定 — 保存済みの値をデフォルトとして対話式で編集してから起動
./start-container.sh --reconfigure

# CLI の例
./start-container.sh --encoder software
./start-container.sh --encoder nvidia --all
./start-container.sh --encoder nvidia --num 0
./start-container.sh --encoder intel --dri-node /dev/dri/renderD129
./start-container.sh --encoder amd -r 2560x1440 -d 144 -S 0.5
./start-container.sh --encoder nvidia-wsl --all --docker-mode dood
./start-container.sh --encoder software -a amd64   # --platform linux/amd64 を自動付与
```

**対話設定の項目**（`configure-container.sh` で管理）:

コンテナ名、Ubuntu バージョン、アーキテクチャ、Docker モード（`dind`/`dood`）、エンコーダー、Docker GPU 選択（`--all`/`--num`）、DRI ノード、解像度、DPI、ストリームスケール、フレームレート、タイムゾーン、言語、SSL ディレクトリ、Mac/Docker Desktop 設定

**既存コンテナの挙動:**
- 同名の停止中コンテナ → 以前の設定で再開（プロンプトなし）
- 同名の起動中コンテナ → スクリプト終了

**UID ベースのポート割り当て**（マルチユーザー対応）:
- HTTPS: `30000 + UID`（例: UID 1000 → ポート 31000）
- HTTP: `40000 + UID`（例: UID 1000 → ポート 41000）

**リモートアクセス:** WebRTC ベース。LAN IP を自動検出、`https://<ホストIP>:<HTTPSポート>` でアクセス。

**コンテナの特徴:**
- 停止してもコンテナは削除されない（再起動や commit がいつでも可能）
- `start-container.sh` は `--restart unless-stopped` を設定するため、明示停止しない限りDocker/WSL再起動後も自動復帰
- `/config` はDocker volume、ホームと`/mnt`はホストbind mountのため、通常の再起動ではデータを保持
- ホスト名: `Docker-$(hostname)`
- ホストホーム: `~/host_home` でマウント
- ホスト `/mnt`: `~/host_mnt` でマウント（Linux/WSL2 のみ、macOS ではスキップ）
  - WSL2 では Windows ドライブにアクセス可能（例: `~/host_mnt/c/Users/...`）
- コンテナ名: `linuxserver-kde-{username}`
- `dind` はコンテナ内 `dockerd`、`dood` はホスト Docker socket を利用
- `STREAM_SCALE` は表示だけでなくエンコード前の実解像度を縮小

### 変更の保存（重要！）

```bash
./commit-container.sh
```

- ⚠️ **`./stop-container.sh --rm` の前に必ず commit** — さもなければ変更が失われます
- イメージ名形式: `webtop-kde-{username}-{arch}-u{ubuntu_version}:{version}`
- commit したイメージはコンテナ削除後も残る
- 次回起動時は自動的に commit したイメージを使用

デスクトップの **Commit Container** をダブルクリックすると、Yes / No / Cancel ダイアログが表示されます。

- **Yes — Keep History:** 通常の `docker commit` を実行し、過去の履歴の上へ新しいレイヤーを追加
- **No — Merge Previous:** 直前のコンテナコミット1回分と現在の変更だけを1レイヤーへ統合して保存。それ以前のベースイメージ履歴は保持
- **Cancel:** 何も変更せず終了

専用の **Flatten Container** アイコンだけが、積み重なった全イメージ履歴を1レイヤーへ統合します。英語の警告メッセージで OK を押した場合だけ実行します。通常コミットと見分けやすい圧縮アーカイブのアイコンを使用しています。ホスト側からは次のコマンドでも実行できます。

```bash
./flatten-container.sh
```

Flatten後も、ENTRYPOINT、環境変数、公開ポート、ボリューム定義、ラベル、ヘルスチェック、ユーザー、作業ディレクトリなどの実行設定を検証して維持します。通常の `docker commit` と同様、ボリュームやバインドマウントから提供される内容はイメージに含まれません。

実行中コンテナは削除されるまで古いレイヤーを参照します。安全にコンテナを削除した後、`docker image prune` を実行すると、タグの外れた古いレイヤーの容量を回収できます。

**典型的なワークフロー:**
```bash
./shell-container.sh          # コンテナ内で作業
# ... パッケージインストール、環境設定 ...
exit
./commit-container.sh         # イメージに保存
./stop-container.sh --rm      # 安全に削除可能
./start-container.sh --encoder intel   # すべての変更が反映された状態で再開
```

### コンテナの停止

```bash
./stop-container.sh            # 停止（コンテナ保持）
./stop-container.sh --rm       # 停止して削除
```

---

## 付録: ベースイメージのビルド

GHCR から取得する代わりに自分でビルドする場合のみ必要（30-60分）:

```bash
./files/build-base-image.sh                         # Ubuntu 24.04、アーキテクチャ自動検出
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04
./files/build-base-image.sh -u 26.04                # Ubuntu 26.04（X11/Xvfb）
./files/build-base-image.sh -a amd64                # Intel/AMD 64-bit
./files/build-base-image.sh -a arm64                # Apple Silicon / ARM
./files/build-base-image.sh -a amd64 -u 26.04       # オプション組み合わせ
./files/build-base-image.sh --no-cache               # クリーンリビルド

# GHCR へ Push
./files/push-base-image.sh

# カスタムリポジトリ
IMAGE_NAME=ghcr.io/you/your-base ./files/build-base-image.sh
IMAGE_NAME=ghcr.io/you/your-base ./files/push-base-image.sh
```

---

## 付録: スクリプトリファレンス

### コアスクリプト

| スクリプト | 説明 | 使い方 |
|---|---|---|
| `build-user-image.sh` | ユーザー固有イメージをビルド | `./build-user-image.sh [-l jp] [-u 22.04|24.04|26.04]` |
| `start-container.sh` | コンテナを起動/再開 | `./start-container.sh [--encoder <type>]` |
| `configure-container.sh` | 保存済みの起動設定を作成・編集 | `./configure-container.sh [--config <file>]` |
| `create-devcontainer-config.sh` | Dev Container 設定を生成 | `./create-devcontainer-config.sh` |
| `stop-container.sh` | コンテナを停止 | `./stop-container.sh [--rm]` |

### 管理スクリプト

| スクリプト | 説明 | 使い方 |
|---|---|---|
| `shell-container.sh` | コンテナ内シェルを開く | `./shell-container.sh` |
| `commit-container.sh` | コンテナ状態をイメージに保存 | `./commit-container.sh` |
| `flatten-container.sh` | 積み重なったイメージ履歴を1レイヤーへ統合 | `./flatten-container.sh` |
| `logs-container.sh` | コンテナログを表示 | `./logs-container.sh` |
| `restart-container.sh` | コンテナを再起動 | `./restart-container.sh` |
| `delete-image.sh` | ユーザーイメージを削除 | `./delete-image.sh` |
| `files/build-base-image.sh` | ベースイメージをビルド | `./files/build-base-image.sh [-a arch]` |
| `files/push-base-image.sh` | ベースイメージを GHCR へ Push | `./files/push-base-image.sh` |

### 起動オプション

```
./start-container.sh [オプション]

エンコーダー / GPU:
  -e, --encoder <type>       software | nvidia | nvidia-wsl | intel | amd | intel-wsl | amd-wsl
  -g, --gpu <value>          Docker --gpus 値: all または device=0,1
  --all                      --gpu all のショートカット
  --num <list>               --gpu device=<list> のショートカット
  --dri-node <path>          VA-API 用 DRI レンダーノード

表示:
  -r <WxH>                   解像度（例: 1920x1080）
  -d <dpi>                   DPI（例: 96, 144, 192）
  -S, --stream-scale <f>     エンコード解像度の倍率（0.25-1.0）
  -f <fps|min-max>           フレームレート（例: 30, 30-60）

その他:
  --docker-mode <mode>       dind または dood
  --timezone <tz>            タイムゾーン（例: Asia/Tokyo）
  -a <arch>                  amd64 / arm64
  -p <platform>              docker run の --platform を明示指定
  -s <ssl_dir>               SSL 証明書ディレクトリ
  -n <name>                  コンテナ名
  --config <file>            YAML 設定ファイル（デフォルト: configs/<name>.yml）
  --reconfigure              保存済みの設定を起動前に対話式で再編集
```

---

## 付録: 設定

### 表示設定

```bash
./start-container.sh -r 1920x1080 -d 96              # 標準
./start-container.sh -r 2560x1440 -d 144             # WQHD HiDPI
./start-container.sh -r 3840x2160 -d 192             # 4K HiDPI

# ストリームスケール — エンコード解像度を縮小
./start-container.sh --encoder software -r 1920x1080 -S 0.5
# 960x540 でエンコードし、1920x1080 のビューポートで表示
```

### ビデオエンコード

| GPU | エンコーダー | 品質 | CPU 負荷 |
|---|---|---|---|
| NVIDIA | NVENC | 高 | 低 |
| Intel | VA-API (Quick Sync) | 高 | 低 |
| AMD | VA-API | 高 | 低 |
| なし | Software (libx264) | 中 | 高 |

`-S/--stream-scale` はエンコード前に解像度を縮小し、帯域とエンコーダー負荷の両方を削減します。

### オーディオ

| 機能 | 状態 | 技術 |
|---|---|---|
| スピーカー出力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |
| マイク入力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |

Selkies はブラウザへ WebRTC 経由で双方向オーディオをストリーミングします。

---

## 付録: HTTPS/SSL

### 証明書の設定（推奨）

```bash
# 現在のホスト名とIPアドレスをSANへ自動追加
./generate-ssl-cert.sh

# Linuxクライアントの例: CAを信頼済みルートとして登録
sudo cp ./ssl/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt
sudo update-ca-certificates

# Google Chrome/ChromiumはOSとは別のNSS信頼DBを使用するため、こちらも実行
./trust-local-ca-chrome.sh

./start-container.sh --encoder nvidia --all   # ssl/ を自動検出
```

Chromeを完全に終了して再起動した後、`https://localhost:31000` または生成時に表示されたホスト名/IPでアクセスしてください。
別名や固定IPを追加する場合は `--san desktop.local --san 192.168.1.10` のように指定できます。

既存CAを登録済みの場合、`./generate-ssl-cert.sh -f` はCAを維持したままサーバー証明書だけを再発行します。CA自体を交換する場合だけ `--new-ca` を併用し、新しい `ca.crt` を再登録してください。

### 証明書の優先順位

1. `ssl/cert.pem` + `ssl/cert.key`
2. `SSL_DIR` 環境変数
3. イメージのデフォルト証明書（フォールバック）

---

## トラブルシューティング

### コンテナが起動しない

```bash
docker logs linuxserver-kde-$(whoami)
docker images | grep webtop-kde
./build-user-image.sh                           # ユーザーイメージを再ビルド
sudo netstat -tulpn | grep -E "31000|41000"     # ポート競合を確認
```

### GPU が検出されない

```bash
# NVIDIA
./shell-container.sh
nvidia-smi

# Intel / AMD
./shell-container.sh
ls -la /dev/dri/ && vainfo

# Docker GPU アクセスの確認
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### 権限の問題

```bash
id                    # ホスト上
./shell-container.sh
id                    # コンテナ内 — UID が一致していること
# 不一致の場合: ./build-user-image.sh で再ビルド
```

### 黒画面 / デスクトップが表示されない

```bash
docker logs linuxserver-kde-$(whoami)
docker exec linuxserver-kde-$(whoami) pgrep -af plasmashell
docker exec linuxserver-kde-$(whoami) ls -la /run/user/$(id -u)
```

原因: `/run/user/<uid>` が存在しないまたは権限不正、plasmashell のクラッシュ → コンテナを再起動。

**WSL2 では**さらに次の 2 つの原因があり、いずれも本リポジトリで修正済みです：

- `docker compose` は compose ファイル中の `${VAR}` を**呼び出し元シェルの環境変数を最優先**で展開し、`.env` はその後に参照します。WSLg は `WAYLAND_DISPLAY=wayland-0`（と `XDG_RUNTIME_DIR`）を常時エクスポートしているため、`.env` に素の名前で置いた値は乗っ取られ、デスクトップは selkies が作らないソケットを永遠に待ち続けていました。コンテナへ渡す値は `.env` 内で `RUNTIME_*` 接頭辞（`RUNTIME_WAYLAND_DISPLAY` など）を使い、`svc-de` は selkies が実際に作った `wayland-*` ソケットへフォールバックします。**GPU / ディスプレイ関連の変数を追加するときは必ず接頭辞付きにしてください。**
- `/mnt/wslg` はマウントしなくなりました。`/mnt/wslg/.X11-unix` を `/tmp/.X11-unix` に被せると root 所有の tmpfs になり、`startwm_wayland.sh` の `chmod` が `set -e` で失敗してセッションが起動しませんでした。d3d12 GPU ドライバに必要なのは `/usr/lib/wsl` と `/dev/dxg` だけです。

ホストで `vgem` を読み込んだ**後に**黒画面になる場合は、ユーザーイメージが `kwin-d3d12-noscanout` シム導入前のものです（既知の制限の [WSL2](#wsl2) を参照）。ユーザーイメージを再ビルドしてください。

### WebGL/Vulkan が動かない

```bash
docker exec linuxserver-kde-$(whoami) glxinfo | head -30
docker exec linuxserver-kde-$(whoami) vulkaninfo | head -50
```

macOS: Docker VM の制限により GPU アクセラレーションは不可。ソフトウェアレンダリングで動作。

### 音声が出ない

```bash
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl info'
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl list sinks short'
```

ブラウザのオーディオ権限を確認し、HTTPS を使用してください（一部ブラウザは HTTP でオーディオをブロック）。

---

## 既知の制限

### Vulkan
- Xvfb は DRI3 をサポートしていないため、Vulkan アプリケーションはフレームをプレゼントできない
- VirtualGL ベースの OpenGL は正常に動作
- 環境によっては Xvfb 上で vkcube が NVIDIA GPU を検出するが、プレゼンテーションの挙動は構成依存
- Ubuntu 26.04 では xorg-server 21.1.22 にカスタム DRI3 パッチが適用できないため、ディストリビューション標準の Xvfb を使用

### macOS
- Docker Desktop はコンテナを Linux VM 内で実行 — Apple GPU（Metal）へのアクセス不可
- WebGL/Vulkan はソフトウェアレンダリング（llvmpipe）
- ハードウェアアクセラレーションが必要な場合は Linux 実機または WSL2 を使用

### WSL2
- `--encoder nvidia-wsl` / `intel-wsl` / `amd-wsl` はいずれも `/dev/dxg`・vgem レンダーノード・WSLg ライブラリ（`/usr/lib/wsl`）をコンテナへ渡し、Mesa D3D12 で OpenGL を GPU 実行。描画そのものは Windows（WDDM）ドライバが担うためベンダー非依存
- `MESA_D3D12_DEFAULT_ADAPTER_NAME` は D3D12 アダプターを名前の部分文字列で選択。デフォルトはプロファイルに応じて `NVIDIA` / `Intel` / `Radeon`。ハイブリッド GPU では使用したいアダプター名の部分文字列に変更可能
- `nvidia-wsl` のハードウェアエンコード（NVENC）は OpenGL とは独立して Pixelflux から使用
- `intel-wsl` / `amd-wsl` は Mesa の `d3d12` VA ドライバ（`LIBVA_DRIVER_NAME=d3d12`）、つまりWindowsドライバーのD3D12 Video Encode APIを利用可能。Pixelflux 2にはWSLの`/dev/dri/card0`をパスAPIで直接渡す。実動作は`vainfo`だけでなく`check-wsl-gpu.sh`で確認する
- Mesaのd3d12 VAドライバーは`MESA_LOADER_DRIVER_OVERRIDE`と`LIBGL_ALWAYS_SOFTWARE`を外し、`GALLIUM_DRIVER=d3d12`にする。`svc-selkies`が設定する。Intel WSL Encodeは`/opt/wsl-vaapi`のMesa 25.2.8とVA-API同期シムを使用し、OpenGLには現行のsystem Mesaを維持する。
- 3つのWSL GPU profileはいずれも既定が`full`で、KWin、Plasma/Qt Quick、アプリは選択したIntel/NVIDIA/AMD adapter上のMesa D3D12を使う。CPU描画モードは明示的な診断用。Qt Quickは3profile共通でthreaded OpenGL RHIとGPU grayscale distance-field文字materialへ固定し、Vulkan probeと物理subpixel配列への依存を避ける。
- Intel WSLのVA-API Encodeは負荷時にWindows UMDの`libigd12dxva64.so`でSIGSEGVしていた。現在はIntel Encoderを専用FFmpegプロセスへ分離し、PixelfluxのOpenGL compositorとMesa/Intel D3D12状態を共有しない。VBR目標4 Mbps・最大8 Mbps、`async_depth=1`、VA同期シムで動作する。
- Chrome/ChromiumラッパーはPlasma保護用の`GALLIUM_DRIVER=llvmpipe`ポリシーを外し、ブラウザだけprofileのadapter、ANGLE OpenGL、GPU rasterizationを明示する。`--enable-zero-copy`と`mesa_glthread=true`はWSL D3D12で古いsurfaceを表示し続け、アドレスバーの入力文字まで欠けたため強制しない。`chrome://gpu`に加え、GPU processの`/proc/<pid>/maps`へ`libd3d12.so`と選択vendorのUMDがロードされていることでも実使用を確認できる。
- 同一プロセスzero-copy試作版は無効のままです。同梱wheelはIntel D3D12 OpenGLで描画し、NV12をreadback後、別FFmpegプロセスでIntel VA-API upload/Encodeします。1992x1248の実配信試験は18秒で471 frame（約26 fps）、直前の45秒試験は1,095 frameを配信し、CPU codecへのfallbackとSIGSEGVはありませんでした。
- `intel-wsl`、`nvidia-wsl`、`amd-wsl`ではChrome/Chromiumのwindow表示だけをXWaylandへ切り替え、描画は引き続きANGLEからMesa D3D12経由で各profileが選んだGPUを使う。native Ozone/Waylandの仮想GBM/dmabuf同期は、GPU描画が有効でもbrowser surfaceを極端に遅くし、アドレスバーの更新まで遅延させていた。X11 Ozone経路はこの表示bottleneckを回避する。Intel実機の`SystemInfo.getInfo`ではIris Xe、OpenGL 4.1、GPU compositing/rasterization、hardware video encode/decodeが有効で、software rendererが読み込まれていないことを確認した。不要かつ不安定なWSL D3D12 Vulkan経路も3profile共通で無効化する。通常Linuxの`intel`、`amd`、`nvidia`にはこのpolicyを適用しない。
- Adapter選択とD3D12 OpenGLは3つのWSL GPU vendorで共通で、`MESA_D3D12_DEFAULT_ADAPTER_NAME`の既定を`Intel`、`NVIDIA`、`Radeon`に分ける。一方、固定版`/opt/wsl-vaapi-legacy` VA-API driverと直列化した外部FFmpeg Encoderは`intel-wsl`専用のままにする。Selkies配信ではNVIDIAはNVENC、AMDはsystem D3D12 VA-API driverを使うため、Intel旧video stackをNVIDIA/AMDへ流用しない。
- Chrome/Chromiumの起動ラッパーはroot実行を拒否する。診断時も`docker exec --user <デスクトップのユーザー名> <コンテナ名> /usr/local/bin/google-chrome-wrapped ...`を使う。rootでデスクトップユーザーのプロファイルを開くと設定がroot所有・権限600で置き換わり、「プロフィール読み込みエラー」になる。発生時はブラウザを終了して対象プロファイル内の所有者を確認し、誤ってroot所有になった項目だけを本来のユーザーに戻す。プロファイル削除や`chmod 777`は不要。負荷試験では別の`--user-data-dir`を指定し、普段のプロファイルを使わない。
- KWinのD3D12デバイスがリセットされた場合、`kwin_wayland_wrapper`の復帰後に`plasmashell`を再起動する監視をセッション内で行う。これにより下部パネルとデスクトップアイコンも復帰する
- Wayland session終了時は、そのsessionが作成したprivate D-Bus daemonも終了する。compositor復旧のたびに古いportal/session busが残ってCPUを消費する問題を防ぐ
- WSL webtopではBlueZ OBEXのD-Bus自動起動を無効化する。Evolution source-registry実体がない状態で`obexd`が欠落serviceを再要求し続け、Chrome/Plasma操作を遅くしていた別の高負荷ループを止める
- WSL GPU sessionではMesa D3D12 OpenGLを維持したまま、Plasma、KIO、Chrome、ChromiumのVulkan ICD/device-select probeを無効化する。ブラウザでは`--ignore-gpu-blocklist`を使わない。Chromium 152ではこれを指定するとWSLのMicrosoft adapter identityに対してWebGPU-on-Vulkan-via-GL interopまで再有効化され、起動ごとにVulkan初期化へ失敗していた。Intel実機では`kioworker`も`libVkLayer_MESA_device_select.so`内で繰り返しSIGSEGVし、Folder View workerとデスクトップアイコン文字が消えていた。Chrome/ChromiumはWebGPU/GraphiteとLCD/subpixel textを無効化するが、Canvas、compositing、raster、OpenGL/WebGL、video encode/decodeはGPUのまま維持する。X11は`Xft.rgba: none`、fontconfigは`10-sub-pixel-none.conf`、Qtは空の`QT_SUBPIXEL_AA_TYPE`（Qtでは物理subpixel配列なし）を使う。Qt Quickはさらに`QSG_DISTANCEFIELD_ANTIALIASING=gray`を指定し、Mesa D3D12で黄・透明になったA32 subpixel materialではなく、GPU上のA8 gray-alpha distance-field materialを使う。
- KWin/Waylandは`DPI`から計算した出力scaleを既にアプリへ通知するため、起動スクリプトは`--force-device-scale-factor`を自動生成しない。これを併用するとChromiumで1.5倍を二重適用しDPR 2.25になっていた。古い永続コンテナから同引数を継承した場合もwrapper側で無視する。
- Plasma 5のX11 session（Ubuntu 22.04/24.04、Xvfb上）にはcompositor scalingがないため、`startwm.sh`はPlasma 5のX11標準の方式でXのfont DPIを唯一の基準にする。`forceFontDPI`を`DPI`に設定し（startplasma-x11が`Xft.dpi`へ書き込み、kde-gtk-configがxsettingsd経由でGTKへ配布）、Qtアプリには`QT_SCREEN_SCALE_FACTORS=<DPI/96>`を渡す（logical DPIも同じ係数で割られるためフォントは二重に拡大されない）。`GDK_SCALE=1`とし、`QT_SCALE_FACTOR`、`QT_FONT_DPI`、`GDK_DPI_SCALE`は設定しない。従来の`QT_SCALE_FACTOR`+`QT_FONT_DPI=96`+`GDK_SCALE=2`の組み合わせでは、パネルとデスクトップアイコンが等倍のまま（Plasma 5の`plasmashell`はX11でQt scalingを無視しfont DPIに従う）、KWinの装飾も等倍のまま（`kwin_x11`もfont DPIにのみ従う）、Chromium/Chrome/Electron（VS Code）は3.0倍（`GDK_SCALE`とfont DPIを掛け合わせる）になっていた。ブラウザやアプリのwrapperで`--force-device-scale-factor`を付与することはしない。Plasma 6（Ubuntu 26.04）はWaylandで動作するため影響しない。
- 全GPUプロセス停止後も両方のVAドライバーが`vaInitialize ... resource allocation failed`になる場合、WSL VMの`/dev/dxg`がfault状態にある。Docker再起動ではホストデバイスをresetできない。Windows PowerShellで`wsl --shutdown`を実行し、distributionを起動し直してから`./check-wsl-gpu.sh`を実行する。この状態で永続コンテナの再作成やイメージ再buildは不要。
- vgem 未ロード（ホストで `sudo modprobe vgem`）の場合は `/dev/dri` が無いため、KWin はソフトウェア合成となり `intel-wsl` / `amd-wsl` もソフトウェアエンコードにフォールバック
- WSL GPUデスクトップでは、OpenGL/WebGLのD3D12高速化に不要で、検証済みIntel/NVIDIA WSL stackのdevice-select/Dozen経路でfault報告があるためVulkanを無効化する
- Plasma文字消失のA/B試験では、GPU版Qt Quickだけで再現し、Folder Viewの`DropShadow` FBO無効化と`Text.NativeRendering`でも改善しなかった。Qt Quickの文字テクスチャとMesa D3D12間の問題であり、QML単体の修正ではない。Ubuntu標準Mesa 26.0.8はdznを同梱せず、Kisak 26.2.2のdznを隔離試験した場合もIntel UMD内の`vkCreateDevice`でSIGSEGVしたため、Vulkan RHIへの切替も現在は採用しない
- **GPU 合成（デスクトップエフェクト）には DRM レンダーノードが必要。** WSL2 は GPU を `/dev/dxg` としてのみ公開し `/dev/dri` を作らないため、そのままでは pixelflux が linux-dmabuf を公開できず KWin は QPainter（ソフトウェア合成：OpenGL エフェクト無効、WebGL は CPU 描画、ホスト負荷が高い）に落ちる。ホストで `vgem` を読み込む（`sudo modprobe vgem`。永続化は `echo vgem | sudo tee /etc/modules-load.d/vgem.conf`、systemd 無しなら `/etc/wsl.conf` に `[boot] command = modprobe vgem`）。`start-container.sh` / `create-devcontainer-config.sh` は未読み込みを検出すると対話的に提案する。`/dev/dri` は存在する場合のみコンテナへ渡されるので、**コンテナ設定を生成する前に**ノードが必要
- **KWin 6.6 + Mesa d3d12 には `kwin-d3d12-noscanout` シムが必要**（[ソース](files/ubuntu-root/usr/local/src/kwin-d3d12-noscanout.c)）。KWin は gbm バッファを `GBM_BO_USE_SCANOUT` 付きで確保するが d3d12 ドライバはこれを拒否するため、レンダーノードがあると KWin は OpenGL を選んだ後に毎フレーム失敗していた（`Could not find a suitable render format` → 黒画面）。ユーザーイメージでシムをビルドし、`kwin_wayland` の `cap_sys_nice` を外し（glibc が `LD_PRELOAD` を無視するため）、`startwm_wayland.sh` は `/dev/dri/renderD128` とシムが揃えば `KWIN_COMPOSE=O2` + `LD_PRELOAD`、揃わなければ `KWIN_COMPOSE=Q` を使う
- 確認はセッション内で `qdbus6 org.kde.KWin /KWin supportInformation`。`Compositing Type: OpenGL` / `OpenGL renderer string: D3D12 (Intel ...)` なら GPU 合成、`QPainter` なら vgem かシムが欠けている
- 音声はPipeWire-Pulseの`output.monitor`をSelkiesが取り込む。`pactl list short source-outputs`に`output.monitor`向けの`python3`録音ストリームがあればサーバー側の音声Encodeは動作中。Plasmaのprivate `XDG_RUNTIME_DIR`とは別に`PULSE_SERVER`/`PIPEWIRE_REMOTE`を標準の`/run/user/<uid>`へ固定する
- ブラウザズーム/DPRが100%以外の場合、Canvasが親要素を拡大し、その親サイズを再利用するフィードバックで画面下端（Plasmaパネルを含む）が切れることがある。primary Canvasは親要素でなく`window.visualViewport`へ合わせる

---

## 付録: 高度なトピック

### 環境変数

<details>
<summary>クリックで展開</summary>

#### コンテナ

| 変数 | 説明 | デフォルト |
|---|---|---|
| `CONTAINER_NAME` | コンテナ名 | `linuxserver-kde-$(whoami)` |
| `IMAGE_BASE` | イメージベース名 | `webtop-kde` |
| `IMAGE_VERSION` | イメージバージョン | `1.1.0` |

#### 表示

| 変数 | 説明 | デフォルト |
|---|---|---|
| `RESOLUTION` | 解像度 | `1920x1080` |
| `DPI` | DPI | `96` |
| `STREAM_SCALE` | エンコード解像度の倍率 | `1.0` |
| `FRAMERATE` | Selkies フレームレート | `30` |
| `TIMEZONE` | タイムゾーン | `UTC` |

#### GPU

| 変数 | 説明 | デフォルト |
|---|---|---|
| `ENCODER` | エンコーダー種別 | （未設定） |
| `GPU_VENDOR` | GPU ベンダー | `software` |
| `MESA_D3D12_DEFAULT_ADAPTER_NAME` | WSL2で使用するGPU名の部分文字列 | `NVIDIA` / `Intel` / `Radeon`（`*-wsl` エンコーダごと） |
| `DOCKER_MODE` | Docker モード | `dind` |

#### ネットワーク

| 変数 | 説明 | デフォルト |
|---|---|---|
| `PORT_SSL_OVERRIDE` | HTTPS ポート上書き | `UID + 30000` |
| `PORT_HTTP_OVERRIDE` | HTTP ポート上書き | `UID + 40000` |

</details>

### プロジェクト構造

```
kde-selkies-webtop-devcontainer/
├── build-user-image.sh           # ユーザーイメージビルド
├── start-container.sh            # コンテナ起動
├── create-devcontainer-config.sh # Dev Container 設定生成
├── compose-env.sh                # compose/devcontainer 用 env 生成
├── interactive-common.sh         # 対話設定の共通処理
├── stop-container.sh             # コンテナ停止
├── restart-container.sh          # コンテナ再起動
├── shell-container.sh            # シェルアクセス
├── commit-container.sh           # 変更保存
├── flatten-container.sh          # イメージ履歴を1レイヤーへ統合
├── logs-container.sh             # ログ表示
├── delete-image.sh               # ユーザーイメージ削除
├── generate-ssl-cert.sh          # SSL 証明書生成
├── ssl/                          # SSL 証明書（自動検出）
│   ├── cert.pem
│   └── cert.key
└── files/                        # システムファイル
    ├── build-base-image.sh       # ベースイメージビルド
    ├── push-base-image.sh        # ベースイメージを GHCR へ Push
    ├── linuxserver-kde.base.dockerfile
    ├── linuxserver-kde.user.dockerfile
    ├── alpine-root/              # s6-overlay 設定
    ├── kde-root/                 # KDE デフォルト
    └── ubuntu-root/              # Ubuntu デフォルト
```

### バージョン固定

再現可能なビルドのため、外部依存関係を固定:

- **VirtualGL:** 3.1.4（Dockerfile のビルド引数）
- **Pixelflux:** 1.6.0（`files/pixelflux/` 内のローカル `.whl` ファイル）
- **Selkies:** デフォルトで最新 `main` ブランチを追跡。`--build-arg SELKIES_COMMIT=<hash>` で特定コミットに固定可能

ハードウェアエンコード:
- **NVIDIA:** Pixelflux 経由の NVENC
- **Intel:** Pixelflux 経由の VA-API (Quick Sync Video)
- **AMD:** Pixelflux 経由の VA-API

バージョンは [files/linuxserver-kde.base.dockerfile](files/linuxserver-kde.base.dockerfile) で定義。

---

## ライセンス

このプロジェクトは複数のオープンソースプロジェクトを基にしています:
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) — GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) — LGPL

詳細は各プロジェクトのライセンスを参照してください。

## 関連プロジェクト

- [tatsuyai713/devcontainer-egl-desktop](https://github.com/tatsuyai713/devcontainer-egl-desktop) — EGL ベース版（3つの表示モード対応）
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) — 元プロジェクト
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — WebRTC ストリーミング

## クレジット

**元プロジェクト:**
- **Selkies Project:** [github.com/selkies-project](https://github.com/selkies-project)
- **LinuxServer.io:** [github.com/linuxserver](https://github.com/linuxserver)

**このプロジェクト:**
- **改善点:** 2段階ビルド、非root実行、UID/GID マッチング、安全なパスワード管理、管理スクリプト、バージョン固定、マルチGPU/エンコーダー対応、Dev Container 統合
- **メンテナー:** [@tatsuyai713](https://github.com/tatsuyai713)

## ホスト側で NVDEC（ハードウェアデコード）を有効にする

配信映像のデコードは視聴側ブラウザで行われます。Linux の Chrome / Edge は
NVIDIA GPU でのハードウェアデコードがデフォルト無効のため、そのままでは
NVDEC が使われません（CPU デコード）。以下でホスト側を設定してください。

```bash
# nvidia-vaapi-driver のインストール（Ubuntu 標準の 0.0.8 は古いため PPA 推奨）
sudo add-apt-repository ppa:ubuntuhandbook1/nvidia-vaapi
sudo apt update && sudo apt install nvidia-vaapi-driver
```

ブラウザは次のフラグ付きで起動します:

```bash
LIBVA_DRIVER_NAME=nvidia NVD_BACKEND=direct google-chrome \
  --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs \
  --ignore-gpu-blocklist --use-gl=angle --use-angle=gl
# Wayland デスクトップの場合は --ozone-platform=wayland も追加
# Edge の場合は google-chrome を microsoft-edge に置き換え
```

確認方法: `chrome://gpu` の Video Acceleration Information にデコード対応が
表示され、ストリーム視聴中に `nvidia-smi` の `utilization.decoder` が上がれば
有効です。サーバ側の NVENC エンコードとは独立した設定です。

> **Intel / AMD のホストの場合**: nvidia-vaapi-driver は不要です。代わりに
> `intel-media-va-driver`（Intel）または Mesa の VA ドライバ（AMD、通常は導入済み）
> を入れ、ブラウザは `--enable-features=AcceleratedVideoDecodeLinuxGL` のみで
> 起動してください（`LIBVA_DRIVER_NAME` / `NVD_BACKEND` / `VaapiOnNvidiaGPUs` は不要）。
