# Codex Quota Activator for Windows

简体中文 | [English](README.md)

这是一个 Windows 计划任务项目，每隔六小时通过 Codex CLI 发送一条简短请求。每次运行使用 `codex exec --ephemeral`，指定 `gpt-6-luna` 和 `low` 思考强度；CLI 不会为该请求保存会话记录文件。

计划任务会使用已登录的 Codex CLI 发起真实请求。**定时发送请求不保证开启、重置或延长额度窗口。**额度规则由 OpenAI 决定。

## 运行要求

- Windows PowerShell 5.1 或更高版本。
- 已完成登录、且支持 `codex exec --ephemeral` 的 [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)。
- 一个可写且安装后路径保持不变的文件夹。

如果使用 npm，可这样安装 CLI：

```powershell
npm install -g @openai/codex@latest
codex
```

首次运行 `codex` 时完成登录。如果系统已安装 npm，安装器也可以提示安装 Codex CLI。

## 安装

1. 从[最新版本](https://github.com/LoveElysia1314/CodexQuotaActivator/releases/latest)下载源代码 ZIP，解压到一个可写且准备长期使用的文件夹。
2. 在该文件夹中双击 `install.cmd`。
3. 安装后保持文件夹路径不变；计划任务会从这里运行脚本。

安装器检查 CLI，在项目文件夹中生成 `config.json`、`run-hidden.vbs` 和 `logs/`，然后以当前 Windows 用户身份注册名为 `Codex Quota Activator` 的计划任务。

也可以在 PowerShell 中打开安装与卸载菜单：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

直接选择安装操作：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Mode Install
```

## 执行时间与行为

默认从本地时间 05:30 开始，每六小时执行一次，即 **05:30、11:30、17:30、23:30**。Windows 中只注册一个任务。

每次运行时，脚本发送以下消息：

```text
Ping. Reply PONG.
```

计划任务在后台运行，不显示终端窗口，并使用电脑现有的网络配置。如果请求失败或超过 60 秒，脚本等待 15 秒后再尝试一次。运行结果和简短的 CLI 输出写入 `logs/activator.log`。

Codex CLI 的 [`--ephemeral` 选项](https://learn.chatgpt.com/docs/developer-commands?surface=cli)使本次运行不保存会话记录文件。
模型与思考强度仅对此命令生效，不修改全局 Codex 设置。缩短消息不会移除 CLI 请求自身的固定上下文，因此不能保证额度消耗按消息字数等比例下降。

如需手动发送一次请求进行检查，而不运行计划任务，可执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-activation.ps1
```

该脚本会发送一次真实请求，不会重试。

## 查看任务状态

手动运行一次并查看任务信息：

```powershell
schtasks /Run /TN "Codex Quota Activator"
schtasks /Query /TN "Codex Quota Activator" /V /FO LIST
```

运行后查看项目文件夹中的 `logs/activator.log`。失败会写入日志，下一次计划运行照常进行。日志可能包含 CLI 输出和本机路径，请将其作为本地诊断文件保管。

## 修改开始时间

修改 `setup.ps1` 中 `Install-CodexActivator` 函数的 `/ST 05:30`，然后再次运行 `install.cmd` 更新任务。`/SC HOURLY /MO 6` 设置决定六小时间隔。

## 卸载

双击 `uninstall.cmd`，或运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Mode Uninstall
```

卸载会删除计划任务以及生成的 `config.json`、`run-hidden.vbs` 和 `logs/`；项目脚本保留在原文件夹。

## 项目文件

| 文件 | 用途 |
| --- | --- |
| `activate.ps1` | 执行定时请求并写入日志。 |
| `test-activation.ps1` | 手动发送一次请求进行检查。 |
| `setup.ps1` | 安装或删除计划任务。 |
| `install.cmd`、`uninstall.cmd` | Windows 安装和卸载入口。 |
| `CHANGELOG.md` | 中英双语版本记录。 |
