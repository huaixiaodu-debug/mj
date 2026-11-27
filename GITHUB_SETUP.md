# 把 DoorOpener 部署到 GitHub

## 已完成部署 ✓

- 仓库：https://github.com/huaixiaodu-debug/mj （私有）
- 分支：main，本地与远端同步
- GitHub Actions 工作流已推送：编译 App 并产出**未签名 IPA**，推到 `artifacts` 分支 + 作为 Actions artifact

## 生成 IPA（需在 GitHub 网页启用 Actions）

当前环境（Windows）无法编译 IPA——苹果工具链必须在 macOS + Xcode 上跑。已配置好 Actions 自动构建，但**私有仓库首次需要在网页手动启用 Actions**：

1. 打开 https://github.com/huaixiaodu-debug/mj/actions
2. 若提示 "Enable Actions"，点击启用
3. 启用后点左侧 **Build DoorOpener** → 右上 **Run workflow** → 手动触发一次
4. 等待运行完成（首次约 5-10 分钟）
5. 取 IPA 二选一：
   - **Actions artifact**：进入该次运行，页面底部 Artifacts → 下载 `DoorOpener-unsigned-IPA`
   - **artifacts 分支**：`git checkout artifacts` 后有 `DoorOpener-unsigned.ipa`

注意：这是**未签名 IPA**，无法直接安装，需用侧载工具（爱思助手/Sideloadly/AltStore）用自己的 Apple ID 重签名后安装到 iPhone（免费证书 7 天有效）。要正式签名分发需 Apple 开发者账号 + 证书。


以下内容为原始准备说明，供参考。

## 一、已为你准备好的内容

### 1. SSH 密钥对
- 私钥：`C:/Users/Administrator/WorkBuddy/2026-11-27-14-01-55/.ssh/id_ed25519`（**不要公开、不要提交**）
- 公钥（下面要填到 GitHub）：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB8rQpiOYr715UD/SsaX11szKBCw9SuOPu2Zo7hAHWXf dooropener-ios-app
```

- 指纹：`SHA256:CBCk9pzvo/Ckv7Dt9r5DhJCl3rIuOziHLFkmv+FBHjI`

### 2. Git 仓库
已 `git init` 并完成首次提交（分支 `main`，10 个文件），并已配置使用该密钥连接 GitHub。

### 3. GitHub Actions 自动编译
`.github/workflows/build.yml`：每次 push 到 main 会自动在 macOS 上编译验证工程（无需签名）。

## 二、你需要在 GitHub 网页操作

### 步骤 1：把公钥添加到 GitHub
1. 登录 https://github.com
2. 右上角头像 → **Settings**
3. 左侧 **SSH and GPG keys** → **New SSH key**
4. Title 填 `DoorOpener`，Key type 选 `Authentication Key`
5. 把上面那段 `ssh-ed25519 AAAA...` 公钥完整粘贴进 Key 框
6. 点 **Add SSH key**

### 步骤 2：新建一个仓库
1. GitHub 首页右上 **+** → **New repository**
2. Repository name 填 `DoorOpener`（或你喜欢的名字）
3. 选 **Private**（推荐，含内网地址和账号信息）或 Public
4. **不要**勾选 "Add a README file"（保持空仓库）
5. 点 **Create repository**

## 三、推送代码（添加完公钥和仓库后告诉我，我来推送；或你自己执行）

把下面命令里的 `你的用户名` 换成你的 GitHub 用户名，在本目录执行：

```bash
cd C:/Users/Administrator/WorkBuddy/2026-11-27-14-01-55/DoorOpener
git remote add origin git@github.com:你的用户名/DoorOpener.git
git push -u origin main
```

## 四、验证

- 刷新 GitHub 仓库页面，应能看到全部代码
- 打开 **Actions** 标签，可看到 `Build DoorOpener` 工作流在跑（绿色对勾=编译通过）

## 五、后续在 GitHub 上编辑/协作

- 网页上直接改代码：仓库里点文件 → 铅笔图标 → 编辑 → Commit
- 本地改完推送：`git add -A && git commit -m "说明" && git push`
- 每次推送都会触发自动编译检查

---

## 重要提醒

1. **这是内网门禁系统**：App 里的服务器地址 `10.85.160.4` 是内网 IP，GitHub Actions 的 macOS 机器只做"编译验证"，**不会也不能访问你的门禁服务器**。真正开门要在能连上内网的设备（你的 iPhone）上进行。
2. **建议用 Private 仓库**：代码里含账号 gzb1、服务器地址、门牌清单，建议私有。
3. **私钥不要泄露**：`id_ed25519` 是私钥，任何拿到它的人都能以你的身份操作 GitHub 仓库。不要上传到仓库或发给别人。
4. **iOS App 无法在 GitHub 上"运行/托管"**：GitHub 只托管代码和自动编译；要装到 iPhone 仍需你在 Mac 上用 Xcode 签名编译（或用 GitHub Actions + 证书做自动构建 IPA，这是进阶配置，需要你的 Apple 开发者证书）。
