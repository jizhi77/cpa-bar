# CPAQuotaBar

CPAQuotaBar 是一个原生 macOS 菜单栏应用，用来快速查看和管理 CPA 中的 Codex 与 xAI 账号额度。

它适合已经在使用 CPA 管理多个认证文件的用户：打开菜单栏即可看到每个账号还剩多少额度、什么时候重置，也可以直接在同一个面板里调整账号启用状态和优先级。

## 主要功能

- 在 macOS 菜单栏常驻显示，打开面板时自动刷新额度。
- 菜单栏图标会显示当前可用账号数量。
- 支持 Codex 和 xAI 认证文件，并可按 All、Codex、xAI 快速筛选。
- 展示账号名称、提供商、启用状态、priority 和最近刷新状态。
- 账号会按 priority 优先展示，未设置 priority 的账号按名称排列。
- 提供精简与完整两种展示模式，并记住你的偏好。
- 支持全部刷新，也支持只刷新单个账号。
- 可打开对应的 CPA 额度管理页面，方便在浏览器中继续查看。
- 管理模式下可批量启用或停用账号、调整 priority，并一次性保存。
- 支持删除单个认证文件，删除前会在面板内二次确认。

## 额度信息

Codex 账号可展示：

- 套餐类型，例如 Free、Plus、Pro 5x、Pro 20x、Team。
- 订阅续期时间。
- 主动重置次数。
- 5 小时额度、周额度或月额度。
- 代码审查额度，以及其他由账号返回的附加额度窗口。

xAI 账号可展示：

- SuperGrok 或 SuperGrok Heavy 套餐。
- 周额度。
- 不同产品的使用量。
- 月度积分余额。
- 按量付费额度。

实际能看到哪些额度，取决于你的账号类型以及 CPA 当前能从服务端获取到的数据。

## 系统要求

- macOS 14 Sonoma 或更高版本。
- 一个可访问的 CPA 服务。
- CPA 的 Management Key。
- CPA 中已经存在通过认证文件方式接入的 Codex 或 xAI 账号。

## 安装

推荐使用 Homebrew 安装：

```bash
brew tap jizhi77/cpa-bar https://github.com/jizhi77/cpa-bar
brew install --cask jizhi77/cpa-bar/cpa-bar
```

之后可以通过 Homebrew 升级：

```bash
brew upgrade --cask jizhi77/cpa-bar/cpa-bar
```

也可以前往 [Releases](https://github.com/jizhi77/cpa-bar/releases) 下载 `CPAQuotaBar.zip`，解压后将 `CPAQuotaBar.app` 放入“应用程序”文件夹。

## 首次使用

1. 启动 CPAQuotaBar。
2. 点击菜单栏中的仪表盘图标。
3. 填写 CPA 地址和 Management Key。
4. 点击“保存并刷新”。

CPA 地址可以填写根地址，也可以直接粘贴 CPA 的额度管理页链接。应用会自动整理为可用的连接地址。

默认地址为：

```text
http://127.0.0.1:8317
```

如果你的 CPA 部署在其他设备或端口，请改成自己的地址。

## 使用方式

打开菜单栏面板后，CPAQuotaBar 会自动刷新所有可展示账号。你也可以点击右上角的刷新按钮手动刷新全部账号，或在某个账号卡片中单独刷新。

这是一个菜单栏应用，启动后默认不会出现在 Dock 中。如果没有看到窗口，请在屏幕右上角的菜单栏里寻找仪表盘图标。

顶部的筛选按钮可以在全部账号、Codex 账号和 xAI 账号之间切换。旁边的“精简/完整”按钮用于切换展示密度：精简模式适合快速扫一眼剩余额度，完整模式会显示更多账号和套餐信息。

进入“管理”模式后，可以修改账号启用状态和 priority。修改会先暂存在面板中，点击“保存”后才会写回 CPA；点击“退出”会放弃未保存的修改。

## 数据与安全

- Management Key 会保存到 macOS Keychain。
- CPA 地址会保存在本机偏好设置中。
- CPAQuotaBar 只连接你配置的 CPA 服务，并通过 CPA 获取额度数据。
- 删除认证文件是不可恢复操作，请在确认账号无用后再执行。

## 卸载

如果使用 Homebrew 安装：

```bash
brew uninstall --cask jizhi77/cpa-bar/cpa-bar
```

如果是手动安装，删除“应用程序”中的 `CPAQuotaBar.app` 即可。

如需清除本机保存的 CPA 地址，可在系统设置或偏好设置清理工具中删除 `com.cpa-bar.CPAQuotaBar` 的偏好设置。Management Key 保存在 macOS Keychain 中，可在“钥匙串访问”中删除对应条目。
