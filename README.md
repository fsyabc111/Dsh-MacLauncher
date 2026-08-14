# DSH Launcher

DSH Launcher 是一个 macOS 菜单栏应用，用于安装和管理本地
[`@deepseek-ai/dsh`](https://github.com/deepseek-ai/deepseek-harness) Web 服务。

## 功能

- 首次下载经过 SHA-256 校验的 Node + dsh 固定版本运行时
- 启动、停止、重启并打开本地 DSH Web 页面
- 最近工作区、自动端口回退、登录启动和自动启动服务
- 未选择工作区时直接使用当前用户主目录
- 实时滚动日志、状态诊断与脱敏诊断包导出
- 手动确认运行时升级，失败时回滚上一版本
- 复用 `~/.dsh`，服务仅绑定 `127.0.0.1`
- 为 DSH Web 子进程组合通用 PATH（运行时 node、`~/.npm-global/bin`、pnpm、
  Homebrew 等常见工具目录），插件市场等功能的 pnpm/npm 调用不受 GUI 最小
  PATH 影响；可在设置中追加额外目录

## 开发

要求 Apple 芯片 Mac、macOS 13+ 和完整 Xcode。仓库同时提供 Swift Package，
因此不依赖 Xcode 的核心检查可以直接运行：

```bash
swift test
swift run DshLauncherSmokeChecks
```

Xcode 工程由 `project.yml` 生成并提交。修改工程定义后运行：

```bash
brew install xcodegen
xcodegen generate
open DshMacLauncher.xcodeproj
```

开发环境可通过 `DSH_RUNTIME_MANIFEST_URL` 指向本地或测试清单。生产默认使用本仓库
GitHub Releases 中的 `runtime-manifest.json`。

## 运行时包

运行时发布包由官方 Node arm64 归档和固定版本 dsh 构建：

```bash
RELEASE_TAG=v1.0.0 Scripts/build-runtime.sh dist
```

脚本会校验 Node 官方 SHA-256，生成 `dsh-runtime-arm64.zip` 和运行时清单。

## 发布

推送 `v*` tag 会触发签名、公证和 GitHub Release 工作流。仓库需要配置：

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`

发布前应在干净的 Apple 芯片 Mac 上完成首次下载、启动、退出、登录启动和
Gatekeeper 验证。

## 安全边界

启动器不会读取 `~/.dsh/.credentials.yaml` 或会话内容。诊断包只包含应用状态和
脱敏后的启动器日志。进程停止操作会核对本应用记录的 Node 与 dsh 路径，不会终止
从终端单独启动的 dsh。
