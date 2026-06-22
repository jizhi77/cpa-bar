# CPAQuotaBar

一个原生 macOS 菜单栏工具，用来直接查看并刷新 CPA 里的 Codex 认证文件额度，不再需要频繁打开浏览器管理页。

## 功能

- 从 CPA 的 `/v0/management/auth-files` 拉取认证文件
- 过滤 `provider/type == codex` 的文件型认证
- 每次点击打开菜单栏时自动刷新一次
- 支持全部刷新和单账号刷新
- 支持精简 / 完整模式切换，默认记住上次选择
- 展示套餐、续期时间、主动重置次数和各额度窗口
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

## 打包成 `.app`

```bash
./scripts/build-app.sh
```

打包完成后会生成：

`dist/CPAQuotaBar.app`

`dist/CPAQuotaBar.zip`

这是一个菜单栏模式应用，默认不会显示 Dock 图标。
