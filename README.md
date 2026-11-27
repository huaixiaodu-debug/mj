# DoorOpener — iPhone 门禁远程开门 App

一个原生 SwiftUI 工程，通过门禁系统 HTTP API 实现手机远程开门。内置 1741 台门禁门牌数据，支持搜索、多选批量开门、结果核实。

## 功能

- **登录**：账号 gzb1 / 密码已内置（MD5），只需输入图形验证码
- **搜索门牌**：输入楼栋名或房间号，如「勇岳107」「智渊楼205」「107」，本地即时匹配（无需联网）
- **开门**：单个或勾选多个门批量开门，自动核实「开门成功」并展示记录
- **状态显示**：联机/脱机标识；脱机门会提示命令可发但无法执行
- **刷新状态**：可从服务器刷新设备的实时联机状态

## 环境要求

- Mac + Xcode 15 或更高版本
- iPhone（**iOS 16.0 以上**，含 iOS 16.6.1）用于真机运行
- 手机需能访问门禁服务器 `http://10.85.160.4`（建议同一内网或 VPN）

## 关于登录 / Cookie / 会话过期（常见问题）

**1. iOS 16.6.1 能用吗？**
能。工程部署目标已设为 iOS 16.0，界面代码全部使用 iOS 16 兼容 API。

**2. 必须每次登录吗？**
不用。App 会把登录会话的 Cookie 持久化保存，下次启动时先用现有 Cookie 自动探测会话是否有效：
- 有效 → 直接进入主界面，无需输入验证码
- 失效 → 才显示登录页

**3. Cookie 是怎么存的？**
登录成功后，App 把门禁服务器的 Cookie（`ASP.NET_SessionId`）序列化存到 `UserDefaults`，App 重启后自动恢复到 `HTTPCookieStorage`。点"退出登录"会清除。

**4. 会话过期时长是多久？**
- 服务端：ASP.NET 默认 **20 分钟滑动过期**（20 分钟内无任何请求才失效）。
- 客户端：Cookie 本身是会话级（无 Expires），但 App 已持久化，不受 App 重启影响。
- App 内置**保活机制**：登录后每 5 分钟自动发一次轻量请求维持会话。只要 App 保持运行，会话就不会因超时失效，可以一直免登录使用。
- 若服务器重启或清理了会话，App 会在下次探测时发现失效并跳回登录页。

## 使用步骤

### 1. 打开工程
双击 `DoorOpener.xcodeproj`，或在 Xcode 中「Open」选择该文件。

### 2. 修改签名配置
选中左侧工程名 `DoorOpener` → TARGETS → DoorOpener → Signing & Capabilities：
- 勾选 **Automatically manage signing**
- Team 选择你的 Apple ID（个人开发者账号即可，免费）
- 把 **Bundle Identifier** 改成你自己的唯一标识（如 `com.你的名字.DoorOpener`）
  - 若改了 Bundle ID，需同步修改 `Info.plist` 无硬性关联，工程内已用变量

### 3. 配置服务器地址（如与默认不同）
打开 `DoorAPI.swift`，顶部配置区修改：
```swift
private let base = "http://10.85.160.4/Access/Standard/Access/"
private let auth = "http://10.85.160.4/Access/Account/"
private let user = "gzb1"
private let passwordMD5 = "21218cca77804d2ba1922c33e0151105" // MD5(888888)
private let systemID = "48"
```

### 4. 编译安装
- 选择目标设备为你的 iPhone（或模拟器）
- 点击 ▶️ Run（⌘R）
- 首次真机安装需在 iPhone「设置 → 通用 → VPN与设备管理」中信任你的开发者证书

## 关于 ATS（HTTP 明文）

门禁服务器是 HTTP（非 HTTPS），iOS 默认会拦截明文请求。`Info.plist` 已配置：
- `NSAllowsArbitraryLoads = true`
- 并对 `10.85.160.4` 设置了例外

若要上架 App Store，需在苹果开发者后台申请 ATS 例外说明（NSExceptionDomains 已就位），或建议服务器升级 HTTPS。个人自用时无需处理。

## 文件结构

```
DoorOpener/
├── DoorOpener.xcodeproj/         # Xcode 工程
│   └── project.pbxproj
└── DoorOpener/
    ├── DoorOpenerApp.swift       # App 入口
    ├── Info.plist                # 配置（含 ATS 例外）
    ├── Models.swift              # 数据模型
    ├── DoorAPI.swift             # 网络层（登录/查询/开门/核实）
    ├── Views.swift               # SwiftUI 界面
    └── doors.json                # 内置 1741 台门牌数据
```

## 注意事项

- 会话有效期有限，过期后 App 会跳回登录页，重新输入验证码即可
- 验证码图片较小，可在 App 里点击图片更换直到看清楚
- 「开首个门」按钮：未勾选任何门时，对搜索结果的第一个门执行开门
- 批量开门时接口不支持一次下发多个，App 已实现逐个下发并逐个核实

## 数据来源

门牌数据与 API 接口于 2026-11-27 从门禁系统抓包/导出获得。设备增减后可更新 `doors.json`。
