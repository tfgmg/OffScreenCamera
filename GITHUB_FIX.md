# GitHub 编译修复（浏览器操作，不用 git push）

Actions 三次失败，主要是 Swift 代码编译错误。请用网页 **编辑 3 个文件**。

---

## 第 1 步：改 VideoLibraryView.swift

1. 打开：https://github.com/tfgmg/OffScreenCamera/edit/main/OffScreenCamera/Features/Library/VideoLibraryView.swift
2. 在第 2 行 `import AVKit` 下面 **加一行**：

```swift
import UIKit
```

3. 点 **Commit changes**

---

## 第 2 步：替换 VideoMergeService.swift

1. 打开：https://github.com/tfgmg/OffScreenCamera/edit/main/OffScreenCamera/Services/VideoMergeService.swift
2. **全选删除**，粘贴本地文件 `OffScreenCamera/Services/VideoMergeService.swift` 的全部内容
3. **Commit changes**

---

## 第 3 步：替换 VolumeButtonMonitor.swift

1. 打开：https://github.com/tfgmg/OffScreenCamera/edit/main/OffScreenCamera/Services/VolumeButtonMonitor.swift
2. **全选删除**，粘贴本地 `OffScreenCamera/Services/VolumeButtonMonitor.swift` 的全部内容
3. **Commit changes**

---

## 第 4 步：重新编译

1. https://github.com/tfgmg/OffScreenCamera/actions
2. **Build iOS IPA** → **Run workflow** → **Run workflow**
3. 等绿色 ✅ → 下载 **Artifacts** 里的 ipa

---

## 若还是红色

1. 点最新失败运行 → **build**
2. 点 **Build unsigned app for device** 展开
3. 截图红色报错发给我
