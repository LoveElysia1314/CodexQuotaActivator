# Changelog / 更新日志

## v0.1.0 — 2026-09-23

### English

- Initial release of the Windows scheduled task installer and uninstaller.
- Runs `codex exec --ephemeral` every six hours, starting at 05:30 local time.
- Runs in the background, with a 60-second timeout, one retry, and local logging.
- Sends an English prompt to check Codex CLI connectivity and the scheduled execution path.

Scheduled requests do not guarantee a reset or extension of Codex usage limits.

### 简体中文

- 首次发布 Windows 计划任务安装器与卸载器。
- 默认从本地时间 05:30 起每六小时运行一次 `codex exec --ephemeral`。
- 后台运行；单次请求 60 秒超时，失败后重试一次，并在本地记录日志。
- 使用英文消息检查 Codex CLI 网络连接和定时脚本执行路径。

定时请求不保证重置或延长 Codex 使用额度。
