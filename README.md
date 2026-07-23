# CPAQuotaBar

一个原生 macOS 菜单栏工具，用来直接查看并刷新 CPA 里的 Codex 和 xAI 认证文件额度，不再需要频繁打开浏览器管理页。

## 功能

- 从 CPA 的 `/v0/management/auth-files` 拉取认证文件
- 支持 `provider/type == codex` 与 `xai`（兼容 `x-ai`、`grok`）的文件型认证
- 支持 All、Codex、xAI 三个列表筛选标签
- 每次点击打开菜单栏时自动刷新一次
- 支持全部刷新和单账号刷新
- 支持精简 / 完整模式切换，默认记住上次选择
- 默认按 `priority` 排序，未设置优先级时按名称兜底
- 支持手动进入管理模式，批量保存启用 / 停用和 `priority` 草稿，或退出时放弃未保存修改
- 支持删除单个认证文件
- 展示 Codex 的套餐、续期时间、主动重置次数和各额度窗口
- 展示 xAI 的周额度、产品用量、月度积分与按量付费额度
- 首次配置服务器地址和管理密钥，管理密钥保存到 macOS Keychain
- `.app` 内置原生 macOS 风格图标

## 默认连接地址

首次启动时会默认填入：

`http://192.168.2.20:8317`

也可以在菜单栏面板里改成你自己的 CPA 地址。支持直接粘贴：

- `192.168.2.20:8317`
- `http://192.168.2.20:8317`
- `http://192.168.2.20:8317/management.html#/quota`
- `http://192.168.2.20:8317/v0/management`

## 本地开发

```bash
swift run CPAQuotaBar
```

## Brew 安装

由于当前仓库名不是 `homebrew-*`，第一次需要显式指定 tap URL：

```bash
brew tap jizhi77/cpa-bar https://github.com/jizhi77/cpa-bar
brew install --cask jizhi77/cpa-bar/cpa-bar
```

升级：

```bash
brew upgrade --cask jizhi77/cpa-bar/cpa-bar
```

## 打包成 `.app`

```bash
./scripts/build-app.sh
```

打包完成后会生成：

`dist/CPAQuotaBar.app`

`dist/CPAQuotaBar.zip`

这是一个菜单栏模式应用，默认不会显示 Dock 图标。
