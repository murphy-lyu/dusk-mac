# Decision Log

## 2026-06 Non-sandboxed 直接分发
App Store 沙箱无法使用 networksetup 和 SMJobBless，
申请特殊 entitlement 流程长且不确定。
决定先做直接分发 .dmg，后续评估 App Store。

## 2026-06 使用 Privileged Helper 而非每次 sudo 弹窗
用户体验：后台定时任务不能弹 sudo 密码框。
用 SMAppService + XPC Helper 一次授权，后续静默执行。
