# Dusk — CLAUDE.md

## 项目简介
Dusk 是一个 macOS 菜单栏 App，帮助用户在下班时自动执行断网、关闭显示器、定时关机等操作，主要面向有网络安全需求的职场用户。

## 技术栈
- Swift + SwiftUI
- macOS 13 Ventura+
- MenuBarExtra（原生菜单栏 API）
- SMAppService（Login Item 开机自启）
- Privileged Helper Tool（XPC，处理需要 root 的操作）
- launchd（定时任务）
- 分发方式：Non-sandboxed，直接分发 .dmg

## 项目结构
- `Dusk/` — 主 App target
- `DuskHelper/` — Privileged Helper Tool target（XPC service，处理 networksetup / shutdown）
- `docs/` — 设计文档、架构决策记录

## 核心功能
1. 定时断网（Wi-Fi，networksetup -setairportpower）
2. 定时恢复网络
3. 定时关闭显示器（pmset displaysleepnow）
4. 定时关机（shutdown -h）
5. 开机自启（SMAppService）
6. 菜单栏常驻，点击展开控制面板

## 开发规范
- 语言：Swift，注释用英文
- SwiftUI 优先，避免 AppKit 混用（除非必须）
- 每个功能模块独立 Service 类，不堆在 AppDelegate
- UserDefaults 存储用户配置，key 统一在 StorageKeys.swift 管理
- 不使用第三方依赖，保持零依赖

## 权限说明
- Privileged Helper 通过 SMAppService 注册
- Helper Bundle ID：com.murphy.dusk.helper
- Helper 负责执行所有需要 root 的系统命令

## 已知陷阱与经验教训（每次踩坑必须追加，避免重复犯错）

> 元规则：任何修改第一次没生效，**立刻停下**，先理解机制/框架行为再改，禁止「调数值反复试」。
> 第二次还没解决 → 用可观测手段（运行 app、打日志、命令行复现）直接观察。
> 意识到犯错后，把具体根因和正确解法追加到本节，用机制而非记忆避免重复。

### SwiftUI `.frame` 的作用层级（按钮等宽踩过坑）
- `.frame(width:)` 加在 **Button 外层** 只分配布局格子，`.bordered`/`.borderedProminent` 的胶囊背景仍只包裹文字、在格子里居中 → 两个按钮永远不等宽。
- 正确解法：把 `.frame(maxWidth: .infinity)` 加在 **Button 的 label（Text）上**，让文字撑满格子，胶囊才跟着撑大。外层再配 `.frame(width: N)` 固定总宽。
- 教训：`minWidth` 反复调没用时，是「frame 作用对象错了」，不是数值问题。

### 不是 bug 的现象不要乱改
- 带 `NSToolbar` 的窗口顶部那条半透明遮罩是系统的 **scroll edge material**，内容可滚动时上滑内容从它下面穿过是标准行为，**不是 bug**。
- 用户只问「这是什么/是不是 bug」时，先回答，不要擅自动手改。
- 改一个**共享资源**（如 General/About 共用的设置窗口尺寸）前，必须考虑对其它使用方的影响。

### macOS 版本兼容（项目 target = macOS 13）
- 双参数 `onChange(of:) { _, new in }` 是 **macOS 14+**；13 必须用单参数 `onChange(of:) { new in }`。
- 新建/检查项目时，Xcode 默认把 `MACOSX_DEPLOYMENT_TARGET` 设成**开发机系统版本**，必须手动改回 13.0，否则低版本 Mac 报「无法在这一版 macOS 上使用」。

### MenuBarExtra(.window) 的框架行为
- 面板是 `NSPanel`，**失去 key 状态就自动关闭**。
- 不要在面板内用系统 `confirmationDialog`/`alert`/`.sheet`/`Picker` 弹窗——它们会创建新 key 窗口、导致面板自动 dismiss。用**面板内的内联视图/覆盖层**代替。
- `MenuBarExtra(isInserted:)` 不要绑 `@Published`：面板会在 view update 期间回写该绑定，触发「Publishing changes from within view updates」无限循环。用不可变 `let` + `.constant(...)`。

### 其它
- accessory（隐藏 Dock）模式下，普通窗口要靠 `NSApp.activate` + `orderFrontRegardless()` 才能稳定到最前；从 MenuBarExtra 菜单触发时还要 `DispatchQueue.main.async` 延后一帧，等 panel 先关闭。
- 改 UI/动画/生命周期前先问：框架在这个 API 调用后会自动做什么？能不能「不对抗框架」地解决。

## 当前进度
- [ ] 项目初始化
- [ ] MenuBarExtra 基础框架
- [ ] ScheduleRule 数据模型
- [ ] Privileged Helper 搭建
- [ ] networksetup 断网/恢复
- [ ] pmset 显示器休眠
- [ ] shutdown 定时关机
- [ ] launchd 定时触发
- [ ] UI 设计实现
- [ ] 开机自启
