# Architecture

## 进程架构
MainApp (Dusk.app)
└── XPC → DuskHelper (Privileged Helper)
         ├── networksetup -setairportpower en0 off/on
         ├── pmset displaysleepnow
         └── shutdown -h +N

## 定时机制
用户在 UI 设置规则 → 写入 UserDefaults
App 注册 launchd agent plist → 到时唤醒 App
App 被唤醒 → 通过 XPC 调用 Helper 执行操作

## 数据模型
ScheduleRule
├── id: UUID
├── type: RuleType（.disconnectWifi / .connectWifi / .displaySleep / .shutdown）
├── time: DateComponents（hour + minute）
├── weekdays: Set<Weekday>（支持只在工作日触发）
└── isEnabled: Bool
