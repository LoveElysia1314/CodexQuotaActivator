# Changelog / 更新日志

## v0.1.0 — 2026-09-24

- Use `gpt-6-luna` with `low` reasoning effort for scheduled requests.
- Replace the timestamped connectivity prompt with `Ping. Reply PONG.`
- Add `test-activation.ps1` for one manual request without retries.
- 定时请求指定 `gpt-6-luna` 和 `low` 思考强度，并改用极简呼叫消息。
- 增加 `test-activation.ps1`，用于手动发送一次请求，不执行重试。

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
