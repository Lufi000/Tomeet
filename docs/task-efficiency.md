# 模拟器上验证动画的手法

**日期**：2026-10-08
**缘起**：落地封面 flip + zoom 转场时摸出来的。纯逻辑测试证明不了"动画对不对"，
而这次改动有四处 bug **全都是眼睛看出来的**，没有一处是单测抓到的。

> **这份是原始叙述版。** 同一套手法后来做成了 skill `verifying-simulator-animations`
> （带现成脚本 `simframes.swift` / `simrecord.sh`），**以 skill 为准**。
> 下面第 3 节的三条已按后来的实测结果订正过，订正原因一并留在那里。

---

## 1. 为什么需要这套东西

三个约束叠在一起，把"看动画"变成了非做不可的事：

1. **单测测不了**。`CoverFlight` 的纯函数全绿，但"封面是不是真从它自己那一格起飞"
   "面板有没有挡住阅读器"这类事，断言写不出来。
2. **模拟器没有可编程的点击接口**。`simctl` 没有 tap/touch 子命令，
   本机也没装 `cliclick` / `idb`。想让它"点一下"只能另想办法。
3. **`osascript` 点窗口能跑，但会抢用户的前台焦点**。用户可能正在别的窗口干活，
   不能这么干。

结论：**让 App 自己点自己，然后录屏，再逐帧看。**

---

## 2. 四步流程

### 第 1 步：让 App 自己触发

照 `HomeView` 已有的 `--ui-snapshot-reader` 先例，加 `#if DEBUG` 的 launch argument：

```swift
#if DEBUG
/// 仅供截图验证：`xcrun simctl launch <udid> com.ivy.Tomeet --ui-snapshot-flight`
private func openForSnapshotIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-flight") else { return }
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.5))   // 等布局和 frame 上报就绪
        onOpen(book, coverAnchor)                    // 走真回调，不是假的
    }
}
#endif
```

**关键**：走的是**真回调、真 frame**，和手指点完全同一条路径。
要是绕开真实路径直接改状态，录出来的就不是真实交互了。

踩过的坑：`onAppear` 在 Lazy 容器里**每格都会触发**。不加以区分的话，
可见的四格会各点一次，连续重飞四趟 —— 录出来完全不是真实手感。
加一个 `static var didSnapshotFire` 只放行第一个。

### 第 2 步：录屏

```bash
SIM=<UDID>
xcrun simctl io $SIM recordVideo --codec h264 --force /tmp/x.mov &
RECPID=$!
sleep 2                                     # 先起录，再启动 —— 否则开头会缺
xcrun simctl launch $SIM com.ivy.Tomeet --ui-snapshot-flight > /dev/null 2>&1
sleep 12
kill -INT $RECPID
```

**别信容器报的帧率**。同一个 `.mov`，`track.nominalFrameRate` 报出来的和实际落盘的不
是一回事 —— 实测有报 60 而实际只有 ~30 出头的（去掉重复画面再数），本机另一段报 15.7。
300ms 的动画实际只落几帧，**别按帧数反推时长**，只能看"有没有动"。

### 第 3 步：先定位，再细看

直接抽几百帧拼图是浪费。先用**逐帧差分**找出变化窗口：

```swift
// 缩到 64x138 算相邻帧的平均绝对差，超过阈值就打印时间
let mean = Double(sum) / Double(w * h * 3)
if mean > 0.6 { out.append(String(format: "%.2f(%.0f)", t, mean)) }
```

判读规律：

| 观察 | 含义 |
|---|---|
| 持续多帧都在变 | 动画真的在跑 ✅ |
| **单帧突变、之后纹丝不动** | 动画根本没跑（被并进首帧了），或压根没触发 |
| 完全没有变化 | 触发条件没进（参数写错 / `guard` 挡掉了） |

### 第 4 步：抽帧 + 拼图看

`AVAssetImageGenerator` 抽出来拼成 contact sheet。**一次看 20 帧，比一张张 Read 省得多。**

注意 `requestedTimeToleranceBefore/After = .zero` **并不保证**拿到你要的那一帧
（实测偏 ~65ms）。所以"某个时刻那一帧精确长什么样"这种精度别指望，看趋势足够。

---

## 3. 四个坑

1. **`CGImage.cropping(to:)` 的原点在左上。**

   > 本文档初版这条写成"左下"，**是错的**。当时的"验证"用的是
   > `x:955 y:160 w:560 h:1025` 这种上下都盖住大半个图的矩形 ——
   > 两种解释下裁出来的内容都差不多，等于没验。
   > 要验就得用一个**只可能落在单侧**的矩形。记在这里：证伪自己时，
   > 先问"这个实验有没有可能两种解释都通过"。

   搞反了会裁出一张纯白，然后你会开始怀疑代码，而其实只是坐标。
   症状：裁剪区域全白，但同一张图换个矩形就有内容。

2. **文件名里可能是 U+202F（窄不换行空格）而不是普通空格。**
   `ls` 列得出来，硬编码路径却 `No such file or directory`。
   用 glob 取：`ls ScreenRecording_*.mov`。

3. **`kill -INT` 才收得干净。** `simctl io recordVideo` 要 SIGINT 才会把
   moov box 写完；直接 `kill -9` 得到的是打不开的文件。

4. **模拟器录像的时间轴 ≠ App 的时间轴。**
   录像从 `recordVideo` 起算，App 从 `launch` 起算，中间隔着启动耗时。
   先用差分定位窗口，再拿窗口内的帧去对，别一上来就算绝对时间。

---

## 4. 判定实验必须带对照（A/B/A/B）

验"某 API 到底生不生效"这类问题时，**单次实验的结论不可信**。
验 `withTransaction(Transaction(disablesAnimations: true))` 对 `fullScreenCover`
生不生效时，第一版实验只跑了一轮，看到"第一次呈现没动画" —— 但
**"首次呈现天然不带动画"本身就是一种可能**，结论是废的。

改成 A/B/A/B（正常、抑制、正常、抑制），拿"红像素占比"当观测量：

| # | 模式 | 观测量 |
|---|---|---|
| 1 | 正常 | 0.35s 渐入 |
| 2 | 抑制 | **一帧到位** |
| 3 | 正常 | 0.35s 渐入 |
| 4 | 抑制 | **一帧到位** |

这样才敢下结论。**做法**：写一个几十行的独立 SwiftUI app，
`xcrun swiftc -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -target x86_64-apple-ios18.0-simulator`
编译成 `.app` 装进模拟器，用定时器自动播放 A/B/A/B —— 同样不需要点击。

---

## 5. 这套手法实测抓到了什么

全部是**单测抓不到、只有眼睛能看见**的：

| 现象 | 根因 |
|---|---|
| 封面飞出去的头两帧是**占位图标** | 飞行层当场 new 了一个 `BookCoverView`，走的还是异步加载 |
| 面板**永远不出现**（全透明） | 连点两次时目标页布局没变，`onGeometryChange` 不会再报落点，飞行干等 |
| 转场是**硬切**，没有动画 | `onAppear` 里的 `withAnimation` 被并进首帧，动画没机会跑 |
| 封面飞完**把阅读器整个盖住** | 飞行层画在了内容上层，且落定后没撤 |

第二个尤其值：它同时暴露了**测试脚手架的 bug**（四格一起点）和
**产品代码的 bug**（重飞就会卡死）。只做单测的话两个都发现不了。

---

## 6. 什么时候不需要这套

- 纯数据/逻辑改动 —— 单测就够，别录屏
- 静态布局 —— `simctl io screenshot` 一张就够，不用录像
- 只有当结论是**"它动起来对不对"**时才值得走完整流程

成本大约是每轮 3–5 分钟（编译 + 录制 + 抽帧）。
这次总共跑了 8 轮，抓到 4 个 bug —— 划算。

---

## 7. 现成脚本

验证期间写的三个一次性脚本，留在 `/tmp` 下会被清掉，这里留个备份思路：

- **抽帧**：`AVAssetImageGenerator` + `crop(cgImage)` + 拼 contact sheet
- **差分定位**：缩图 → 相邻帧平均绝对差 → 打印超阈值的时刻
- **占比观测**：数某种颜色（红屏 / 白屏）的像素占比，用于 A/B 判定

需要时照上面几段核心代码重建即可，每段都不到 60 行。
