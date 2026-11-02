# Advanced Web Development: setup-web

`setup-web.ps1` (Windows) and `setup-web.sh` (macOS, Linux, WSL). Usage: see the
[index](README.md). Table ids for `-Only` / `--only`: `git gh node bun code` (and `wsl` on Windows).

| id | Tool | Needed | Windows route (your user, no admin) | macOS / Linux route |
| --- | --- | --- | --- | --- |
| `git` | Git | 2.30+ | `winget install Git.Git --scope user` | `brew install git`; `xcode-select --install`; `apt-get install git` |
| `gh` | GitHub CLI | 2.40+ | `winget install GitHub.cli --scope user` (the portable zip) | `brew install gh`; Linux: GitHub's apt repository |
| `node` | Node.js LTS | 22+ | the official zip from nodejs.org into `%LOCALAPPDATA%\node`, SHA-256 from `SHASUMS256.txt` (winget's package is machine-wide and **needs admin**) | `brew install node@<LTS major>`; else the official tarball into `~/.local/node` |
| `bun` | Bun | 1.1+ | `winget install Oven-sh.Bun` (portable zip) | `brew install oven-sh/bun/bun`; else bun.sh's install script |
| `code` | VS Code | 1.90+ | `winget install Microsoft.VisualStudioCode --scope user` | macOS: `brew install --cask visual-studio-code`; Linux: not scripted |
| `wsl` | WSL 2 (Windows only) | optional | **check only**: reported, never installed (it needs administrator rights and a restart) | - |

The WSL row is information, not a fault: in some labs Hyper-V (and so WSL 2) is switched off
for the first weeks of the course; use PowerShell and Git Bash there.

The details of each route, "needs admin", Scoop and the options are the same as in
[README-mobile.md](README-mobile.md).

## Sources

- Bun: <https://bun.sh/docs/installation>
- Node: <https://nodejs.org/dist/index.json> and `SHASUMS256.txt` beside each release
- winget manifests (the scope of each package): <https://github.com/microsoft/winget-pkgs> (`Git.Git`, `GitHub.cli`, `OpenJS.NodeJS.LTS`, `Oven-sh.Bun`, `Microsoft.VisualStudioCode`)
- GitHub CLI: <https://cli.github.com>; Git for Windows: <https://git-scm.com/downloads/win>
