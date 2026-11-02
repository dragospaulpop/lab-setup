# lab-setup

Scripts that **check** (and, when you ask, **set up**) the tools for our lab courses.
The lab computers run Deep Freeze: everything you install is gone after a restart, so
every week starts the same way: run the script, read the table, install what is missing.

| Course | Windows (PowerShell) | macOS / Linux / WSL (bash) | Details |
| --- | --- | --- | --- |
| Mobile Apps | `setup-mobile.ps1` | `setup-mobile.sh` | [README-mobile.md](README-mobile.md) |
| Advanced Web Development | `setup-web.ps1` | `setup-web.sh` | [README-web.md](README-web.md) |

By default a script **changes nothing**: it prints a table (tool, needed version, found
version, status). Only with `-Install` / `--install` does it install or upgrade what is
missing or too old, and then it prints the table again. Run it as often as you like: a
tool that is fine is left alone.

## Run it: the one line

Windows, in PowerShell (swap `mobile` for `web` for the web course). First the safe
check, which changes nothing:

```powershell
irm https://raw.githubusercontent.com/dragospaulpop/lab-setup/main/setup-mobile.ps1 | iex
```

Then, to install or upgrade what the table says is missing:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/dragospaulpop/lab-setup/main/setup-mobile.ps1))) -Install
```

macOS, Linux and WSL, in bash:

```bash
curl -fsSL https://raw.githubusercontent.com/dragospaulpop/lab-setup/main/setup-mobile.sh | bash
curl -fsSL https://raw.githubusercontent.com/dragospaulpop/lab-setup/main/setup-mobile.sh | bash -s -- --install
```

What the line does: `irm` / `curl` downloads the text of the script from this repository
(`raw.githubusercontent.com` serves the files of the `main` branch), and the second half
(`iex`, `[scriptblock]::Create(...)`, `bash`) **runs it**. That is the point: you are running
a stranger's program on your computer, with your rights. Read it first.

## Safer: download, read, run

```powershell
irm https://raw.githubusercontent.com/dragospaulpop/lab-setup/main/setup-mobile.ps1 -OutFile setup-mobile.ps1
notepad setup-mobile.ps1            # read it: it is one table of tools and one loop
powershell -ExecutionPolicy Bypass -File .\setup-mobile.ps1            # check
powershell -ExecutionPolicy Bypass -File .\setup-mobile.ps1 -Install   # install
```

```bash
curl -fsSL -o setup-mobile.sh https://raw.githubusercontent.com/dragospaulpop/lab-setup/main/setup-mobile.sh
less setup-mobile.sh                # read it
bash setup-mobile.sh                # check
bash setup-mobile.sh --install      # install
```

(`-ExecutionPolicy Bypass` applies to that one PowerShell process only; the setting of the
computer is not touched.)

## Options

| PowerShell | bash | Does |
| --- | --- | --- |
| *(none)* | *(none)* | print the table, change nothing |
| `-Install` | `--install` | install or upgrade what is missing or too old, then print the table again |
| `-DryRun` | `--dry-run` | with install: print every command, run none |
| `-Only a,b` | `--only a,b` | limit the check (and the install) to these tools (the ids are listed in the error if you misspell one) |
| `-Force` | `--force` | with install: redo the install even for tools that are fine (to repair one) |

## What the scripts promise

- Nothing is installed unless you pass `-Install` / `--install`. `-DryRun` shows the commands first.
- Installs go into **your own user profile** (`%LOCALAPPDATA%`, `~`). No administrator, no
  `sudo`, unless a tool's only route needs it; then the script says so before it asks. The
  only `sudo` are `apt-get` / `dpkg` lines on Linux without Homebrew, shown first, with the
  password asked in front of you.
- `PATH`, `JAVA_HOME` and `ANDROID_HOME` are set in **your user environment** (the Windows
  user registry; `~/.bashrc` or `~/.zprofile`) and in the window that runs the script, so the
  re-check sees them. Open a new terminal afterwards.
- Nothing machine-wide: no `Set-ExecutionPolicy` at machine scope (Scoop's own scripts need
  `RemoteSigned`, set for that one PowerShell process only).
- No telemetry. Every download comes from the tool's official site (the URL is in the script);
  where the site publishes a checksum, the script checks it and stops on a mismatch. Some
  routes run the vendor's own installer (`irm https://get.scoop.sh | iex`,
  `curl -fsSL https://bun.com/install | bash`): the script says so first, and that line is the
  vendor's documented install line, not ours.
- Plain ASCII, Windows PowerShell 5.1 and PowerShell 7, bash 3.2 and newer.

## Test notes

Written and tried on Windows 11 (Windows PowerShell 5.1 and PowerShell 7) and Ubuntu 24.04 in
WSL, not on a lab computer under Deep Freeze and not on macOS. The Linux-without-Homebrew and
macOS routes were read against the official docs but only rehearsed with `--dry-run`.
