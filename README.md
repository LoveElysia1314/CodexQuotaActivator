# Codex Quota Activator for Windows

[简体中文](README.zh-CN.md) | English

A Windows scheduled task that sends a short Codex CLI request every six hours. Each run uses `codex exec --ephemeral` with `gpt-6-luna` at `low` reasoning effort, so the CLI does not persist a session rollout file for that request.

The task sends real requests through your signed-in Codex CLI. **A scheduled request does not guarantee that a usage limit window will start, reset, or extend.** OpenAI controls how usage limits work.

## Requirements

- Windows with Windows PowerShell 5.1 or later.
- A signed-in [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) installation that supports `codex exec --ephemeral`.
- A writable folder that can stay at the same path after installation.

If you use npm, install the CLI with:

```powershell
npm install -g @openai/codex@latest
codex
```

Run `codex` once to complete sign-in. The installer can also offer to install the CLI when npm is available.

## Install

1. Download the [latest release](https://github.com/LoveElysia1314/CodexQuotaActivator/releases/latest) and extract its source ZIP to a writable, permanent folder.
2. Double-click `install.cmd` in that folder.
3. Keep the folder at the same path while the task is installed. The scheduled task runs the scripts from there.

The installer checks the CLI, creates `config.json`, `run-hidden.vbs`, and `logs/` in the project folder, then registers a task named `Codex Quota Activator` under the current Windows user.

You can also open the setup menu in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

To select installation directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Mode Install
```

## Schedule and behavior

The default schedule starts at 05:30 local time and repeats every six hours: **05:30, 11:30, 17:30, and 23:30**. It is registered as one Windows task.

At each run, the script sends this prompt:

```text
Ping. Reply PONG.
```

The task launches without a visible terminal window and uses the machine's existing network configuration. If a request fails or exceeds 60 seconds, the script waits 15 seconds and tries once more. Results and brief CLI output are written to `logs/activator.log`.

The [`--ephemeral` option](https://learn.chatgpt.com/docs/developer-commands?surface=cli) prevents Codex CLI from persisting session rollout files for these runs.
The model and reasoning effort are set on this command only; they do not change your global Codex settings. A shorter prompt does not remove the CLI's fixed request context, so it does not guarantee a proportional reduction in usage.

To send one request manually without running the scheduled task, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-activation.ps1
```

This sends one real request and does not retry.

## Check the task

To run it once manually and inspect its status:

```powershell
schtasks /Run /TN "Codex Quota Activator"
schtasks /Query /TN "Codex Quota Activator" /V /FO LIST
```

After the run, read `logs/activator.log` in the project folder. A failed run is logged and the next scheduled run proceeds normally. The log can contain CLI output and local paths, so treat it as a local diagnostic file.

## Change the start time

Edit `/ST 05:30` in `Install-CodexActivator` in `setup.ps1`, then run `install.cmd` again to update the task. The `/SC HOURLY /MO 6` settings keep the six-hour interval.

## Uninstall

Double-click `uninstall.cmd`, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Mode Uninstall
```

Uninstallation removes the scheduled task and the generated `config.json`, `run-hidden.vbs`, and `logs/` files. The project scripts remain in the folder.

## Project files

| File | Purpose |
| --- | --- |
| `activate.ps1` | Runs the scheduled Codex request and writes the log. |
| `test-activation.ps1` | Sends one manual request for a quick check. |
| `setup.ps1` | Installs or removes the scheduled task. |
| `install.cmd`, `uninstall.cmd` | Windows entry points for setup. |
| `CHANGELOG.md` | Release history in English and Chinese. |
