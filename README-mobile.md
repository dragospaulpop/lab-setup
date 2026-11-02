# Mobile Apps: setup-mobile

`setup-mobile.ps1` (Windows) and `setup-mobile.sh` (macOS, Linux, WSL). Usage: see the
[index](README.md). Table ids for `-Only` / `--only`: `git gh node bun code jdk android image flutter supabase firebase`.

## The tools

| id | Tool | Needed | Windows route (your user, no admin) | macOS / Linux route |
| --- | --- | --- | --- | --- |
| `git` | Git | 2.30+ | `winget install Git.Git --scope user` | `brew install git`; `xcode-select --install`; `apt-get install git` |
| `gh` | GitHub CLI | 2.40+ | `winget install GitHub.cli --scope user` (the portable zip; the MSI is machine-wide) | `brew install gh`; Linux: GitHub's apt repository (Ubuntu's own `gh` is older than 2.40) |
| `node` | Node.js LTS | 22+ | the official zip from nodejs.org into `%LOCALAPPDATA%\node`, SHA-256 from `SHASUMS256.txt` (winget's package is machine-wide and **needs admin**) | `brew install node@<LTS major>` (plain `node` is the Current release); else the official tarball into `~/.local/node` with the same checksum check |
| `bun` | Bun | 1.1+ | `winget install Oven-sh.Bun` (portable zip) | `brew install oven-sh/bun/bun`; else bun.sh's install script |
| `code` | VS Code | 1.90+ | `winget install Microsoft.VisualStudioCode --scope user` (the user installer) | macOS: `brew install --cask visual-studio-code`; Linux: not scripted (use the Windows VS Code from WSL) |
| `jdk` | JDK | 17+ (21 installed) | **Android Studio's own JDK** if the PC has Android Studio and neither `JAVA_HOME` nor `PATH` reaches a JDK yet (nothing to download; the script sets `JAVA_HOME` to it); else the Microsoft Build of OpenJDK 21 zip into `%LOCALAPPDATA%\Programs\jdk-21`, checksum from Microsoft's `.sha256sum.txt` (winget's package is machine-wide and **needs admin**) | `brew install openjdk@21`; else Microsoft's OpenJDK 21 tarball into `~/.local/jdk-21` |
| `android` | Android SDK (**slow**) | API 36, platform-tools, build-tools 36.0.0, emulator | Google's command-line tools zip (SHA-256 pinned in the script, from the download page) into `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest`, then `sdkmanager` | the same, into `~/Android/Sdk` |
| `image` | Emulator image (**slow**) | `system-images;android-36;google_apis;x86_64` and the AVD `Pixel_7_API_36` | `sdkmanager --install ...`, then `avdmanager create avd` | the same (`arm64-v8a` on Apple Silicon and ARM Linux) |
| `flutter` | Flutter | 3.47+ stable | the stable zip from Flutter's release list (`releases_windows.json`, SHA-256 from it), unpacked with `tar.exe` into `%USERPROFILE%\develop\flutter`; an existing one gets `flutter upgrade` | the stable archive from `releases_linux.json` / `releases_macos.json` into `~/develop/flutter` (needs `python3` to read the list) |
| `supabase` | Supabase CLI | 2.0+ | Scoop (installed first if missing, no admin): `scoop bucket add supabase ...`, `scoop install supabase/supabase` | `brew install supabase/tap/supabase`; Linux without brew: the `.deb` from GitHub Releases, checked against the release's `checksums.txt` (`dpkg`, sudo) |
| `firebase` | Firebase CLI | 15+ | `npm.cmd install -g firebase-tools` (`.cmd`, because the default execution policy blocks npm's `.ps1` shims; sets npm's prefix to `%APPDATA%\npm` first if the default is under Program Files) | the same (prefix `~/.local` if the default is not writable) |

**Download size.** The Android SDK plus the emulator image are about 2.6 GB (command-line tools
160 MB, emulator about 350 MB, platform and build-tools about 130 MB, system image about
1.9 GB). The script warns before it starts. Everything else is small. Flutter is 1.9 GB on disk.

**Licences.** Running `-Install` for the Android SDK accepts the Android SDK licences
(`sdkmanager --licenses`); read them at <https://developer.android.com/studio/terms>.

**Java.** The check accepts any JDK 17 or newer (Android Gradle Plugin 8.x needs 17); the install
puts JDK 21, because the Firebase emulators in the week-4 tutorial want Java 21 (their docs say
11 or newer). On a PC with Android Studio the script uses Studio's own JDK instead of downloading one.

**Why zips and not winget for Node and the JDK.** Their winget manifests are machine-scope MSIs,
which need administrator rights on a lab PC. If a PC does allow it, `winget install OpenJS.NodeJS.LTS`
works too.

**Why a zip and not `git clone` for Flutter on Windows.** The repository's longest paths break
Windows' 260-character limit (measured in week 4).

**npm, bun, firebase and "running scripts is disabled".** The default PowerShell policy blocks `.ps1`
files, which is what `npm` and `firebase` can resolve to. The script calls `npm.cmd` and `firebase.cmd`.
For `firebase` itself to work in your window, type `firebase.cmd`, or (your account only, no administrator;
on a shared lab PC ask first) `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

**Linux without Homebrew.** The script runs `sudo apt-get update` once, installs `curl`, `unzip`, `xz-utils`
and `python3` when they are missing (stock WSL Ubuntu has no `unzip`), and adds GitHub's apt repository for `gh`.

**Needs admin?** None of the routes above, on Windows or Linux with Homebrew. Linux without
Homebrew: `apt-get install` for Git and the GitHub CLI and `dpkg -i` for the Supabase CLI ask for
`sudo`. If an older Node or Git in `Program Files` sits ahead of the one in your profile on
`PATH`, the table keeps saying "too old": ask for the older one to be removed.

**Emulator.** The x86_64 image needs hardware acceleration (Windows Hypervisor Platform or
Hyper-V on Windows, KVM on Linux). The script cannot turn that on.

## Sources

- Supabase CLI: <https://supabase.com/docs/guides/local-development/cli/getting-started> (Scoop and brew; npm is a per-project install, not global); <https://scoop.sh>
- Flutter: <https://docs.flutter.dev/install/manual>, <https://docs.flutter.dev/platform-integration/android/setup>, release lists <https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json> (`_linux`, `_macos`)
- Android command-line tools and checksums: <https://developer.android.com/studio#command-line-tools-only>; `sdkmanager`: <https://developer.android.com/tools/sdkmanager> (Android marks it deprecated in favour of the Android CLI; it still works and is what we use)
- JDK: <https://developer.android.com/build/jdks>, <https://learn.microsoft.com/en-us/java/openjdk/download>, Firebase emulators <https://firebase.google.com/docs/emulator-suite/install_and_configure>
- Firebase CLI: <https://firebase.google.com/docs/cli>
- Bun: <https://bun.sh/docs/installation>
- Node: <https://nodejs.org/dist/index.json> and `SHASUMS256.txt` beside each release
- winget manifests (the scope of each package): <https://github.com/microsoft/winget-pkgs> (`Git.Git`, `GitHub.cli`, `OpenJS.NodeJS.LTS`, `Oven-sh.Bun`, `Microsoft.VisualStudioCode`, `Microsoft.OpenJDK.21`)
