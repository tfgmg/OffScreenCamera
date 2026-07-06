# 黑屏录像（OffScreenCamera）

iPhone 自用：**黑屏界面 + 摄像头录像**，支持前置/后置切换、麦克风开关。  
不上 App Store，适合 **Windows + 免费 Apple ID + Sideloadly** 安装。

## 功能

- 前置 / 后置摄像头录像
- 麦克风可开可关（静音录像）
- 录制时全黑界面，防自动锁屏
- 本地文件列表、预览、删除、导出相册
- 双击黑屏停止录像

## 系统限制（必读）

- 这是 **伪息屏**：App 内黑屏，不是锁屏后继续录
- 按电源键真锁屏后，录像会停止
- iOS 会显示 **相机绿点**（无法隐藏）
- 免费 Apple ID 安装的 App **约 7 天过期**，需用 Sideloadly 重装

## 环境要求

| 项目 | 要求 |
|---|---|
| iPhone | iOS 17+ |
| Windows | 用于 sideload |
| GitHub | 用于云端编译（免费） |
| Apple ID | 免费即可 |

## 一、用 GitHub Actions 编译 IPA

1. 把本项目推到 GitHub 仓库
2. 打开仓库 **Actions** → **Build iOS IPA** → **Run workflow**
3. 等任务完成后，在 **Artifacts** 下载 `OffScreenCamera-unsigned-ipa`
4. 解压得到 `OffScreenCamera-unsigned.ipa`

> 每次改代码后 push 到 `main`，或手动 Run workflow，都会生成新的 ipa。

## 二、Windows 上用 Sideloadly 安装（免费 Apple ID）

1. 安装 [Sideloadly](https://sideloadly.io/)
2. iPhone 用数据线连接电脑，解锁并信任
3. iPhone 打开：**设置 → 隐私与安全性 → 开发者模式**（iOS 16+）
4. 打开 Sideloadly：
   - 选你的 iPhone
   - 拖入 `OffScreenCamera-unsigned.ipa`
   - 登录 **专用 Apple ID**（建议不要用主 iCloud 账号）
   - 点击 **Start**
5. 手机上：**设置 → 通用 → VPN 与设备管理** → 信任开发者
6. 打开「黑屏录像」，允许 **相机**；若开声音，再允许 **麦克风**

### 7 天过期后

- 没改代码：Sideloadly 再装 **同一个 ipa** 即可
- 改了代码：重新跑 GitHub Actions，下载新 ipa 再装

## 三、使用说明

1. 打开 App → **录制** 页
2. 选择 **前置 / 后置**
3. 开关 **录制声音**
4. 点 **开始黑屏录像**
5. 进入全黑界面，可手动把系统亮度调到最低
6. **双击屏幕** 停止录像
7. 到 **文件** 页预览、保存相册或删除

## 四、项目结构

```
OffScreenCamera/
├── project.yml                 # XcodeGen 工程定义
├── OffScreenCamera/
│   ├── OffScreenCameraApp.swift
│   ├── ContentView.swift
│   ├── Features/
│   │   ├── Home/HomeView.swift
│   │   ├── Recording/RecordingView.swift
│   │   └── Library/VideoLibraryView.swift
│   ├── Services/
│   │   ├── CameraService.swift
│   │   ├── VideoStorage.swift
│   │   └── PowerGuard.swift
│   └── Models/RecordingModels.swift
└── .github/workflows/ios-build.yml
```

## 五、可选：修改 Bundle ID

若 Sideloadly 提示 App ID 冲突，可改 `project.yml` 里的：

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.offscreen.camera
```

改成唯一值，例如 `com.你的昵称.offscreencamera`，然后重新编译。

## 六、有 Mac 时本地调试

```bash
brew install xcodegen
xcodegen generate
open OffScreenCamera.xcodeproj
```

用 Xcode 连接 iPhone，选 Personal Team 直接 Run。

---

**自用工具，请勿用于未经他人同意的偷拍或监控。**
