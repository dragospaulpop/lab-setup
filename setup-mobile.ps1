# setup-mobile.ps1 - check (and, with -Install, set up) the tools of the Mobile Apps course.
# Windows PowerShell 5.1 or PowerShell 7. Plain ASCII on purpose.
#
#   .\setup-mobile.ps1                    check only: prints a table, changes nothing
#   .\setup-mobile.ps1 -Install           install or upgrade what is missing or too old, then check again
#   .\setup-mobile.ps1 -Install -DryRun   print every command it would run, run none
#   .\setup-mobile.ps1 -Only flutter,jdk  limit the check (and the install) to these tools
#   .\setup-mobile.ps1 -Install -Force    redo the install even for tools that are fine (with -Only, to repair one)
#
# Everything goes into your own user profile; no administrator needed unless the table says so.
# PATH, JAVA_HOME and ANDROID_HOME are changed in YOUR user environment only (and in this window).
# No telemetry. Every download comes from the tool's official site; where the site publishes a
# checksum, the script checks it. README.md says where each route comes from.

param(
  [switch]$Install,
  [switch]$DryRun,
  [switch]$Force,
  [string[]]$Only
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is much faster without its progress bar

# ---- settings you may want to read --------------------------------------------------------------
$AndroidApi   = '36'                                   # Flutter's docs ask for API level 36
$SdkRoot      = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$SysImage     = "system-images;android-$AndroidApi;google_apis;x86_64"
$AvdName      = "Pixel_7_API_$AndroidApi"
$CmdlineZip   = 'commandlinetools-win-15859902_latest.zip'   # from developer.android.com/studio, "Command line tools only"
$CmdlineSha   = '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'   # published next to that download
$FlutterDir   = Join-Path $env:USERPROFILE 'develop\flutter'
$NodeDir      = Join-Path $env:LOCALAPPDATA 'node'
$JdkDir       = Join-Path $env:LOCALAPPDATA 'Programs\jdk-21'
$StudioJbr    = 'C:\Program Files\Android\Android Studio\jbr'

# ---- helpers ------------------------------------------------------------------------------------
function Say($text) { Write-Host $text }

function Get-Ver($text) {            # first "1.2.3" in a text, or $null
  if ($text -match '(\d+(\.\d+)+)') { return $Matches[1] }
  return $null
}

function Run($label, [scriptblock]$cmd) {   # print, then run unless -DryRun
  Say "    > $label"
  if (-not $DryRun) { & $cmd }
}

function Refresh-Path {              # pick up PATH changes made by installers
  $reg = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  foreach ($p in ($reg -split ';')) { if ($p -and (($env:Path -split ';') -notcontains $p)) { $env:Path += ";$p" } }
}

function Add-UserPath($dir) {        # user PATH (registry) + this window
  Say "    > add to your user PATH: $dir"
  if ($DryRun) { return }
  # read and write the raw value: entries like %USERPROFILE%\bin stay as they are (REG_EXPAND_SZ)
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  $u = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
  if (($u -split ';') -notcontains $dir) {
    $key.SetValue('Path', $(if ($u) { "$dir;$u" } else { $dir }), 'ExpandString')
    # setting and clearing a user variable makes Windows tell running programs that the environment changed
    [Environment]::SetEnvironmentVariable('LAB_SETUP_NOTIFY', '1', 'User'); [Environment]::SetEnvironmentVariable('LAB_SETUP_NOTIFY', $null, 'User')
  }
  $key.Close()
  if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}

function Set-UserEnv($name, $value) {
  Say "    > set your user variable $name = $value"
  if ($DryRun) { return }
  [Environment]::SetEnvironmentVariable($name, $value, 'User')
  Set-Item -Path "Env:$name" -Value $value
}

function Get-Text($url) {            # a web page as text (aka.ms serves checksum files as raw bytes)
  $r = Invoke-WebRequest -Uri $url -UseBasicParsing
  if ($r.Content -is [byte[]]) { return [Text.Encoding]::ASCII.GetString($r.Content) }
  return $r.Content
}

function Download($url, $file) {
  Run "download $url" { Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing }
}

function Check-Sha256($file, $expected) {
  if ($DryRun) { Say "    > check SHA-256 of the file against $expected"; return }
  $got = (Get-FileHash -Algorithm SHA256 -Path $file).Hash
  if ($got -ne $expected.ToUpper()) { throw "checksum mismatch for $file (got $got, wanted $expected)" }
  Say "    SHA-256 matches."
}

function Winget($id) {               # user scope; a package with no per-user installer says NEEDS ADMIN
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget not found (install "App Installer" from the Microsoft Store)' }
  $common = @('--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
  Run "winget install $id --scope user" { winget install @common --scope user }
  if (-not $DryRun) {
    $code = $LASTEXITCODE
    if ($code -eq -1978335216) {   # no applicable installer: the package has no per-user installer
      Say "    NEEDS ADMIN: $id has no per-user installer. Windows will ask for an administrator's password; on a lab PC without one, ask the lab."
      winget install @common
      $code = $LASTEXITCODE
    }
    if ($code -ne 0 -and $code -ne -1978335189) { throw "winget exited with code $code for $id" }   # -1978335189 = already up to date
  }
  Refresh-Path
}

function Unpack-Zip($url, $sha, $dest) {   # download, verify, unpack the zip's one top folder as $dest (replacing it)
  if (-not $sha) { throw "no checksum found for ${url}: not installing a download that cannot be checked" }
  $tmp = Join-Path $env:TEMP ('lab-setup-' + [guid]::NewGuid().ToString('N'))
  $stage = Join-Path (Split-Path $dest) '.lab-setup-stage'   # unpacked next to its target: short paths (260-character limit)
  Run "mkdir $tmp" { New-Item -ItemType Directory -Force $tmp | Out-Null }
  Download $url "$tmp\pkg.zip"
  Check-Sha256 "$tmp\pkg.zip" $sha
  Run "unpack into $dest (tar -xf, much faster than Expand-Archive)" {
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Force $stage | Out-Null
    tar.exe -xf "$tmp\pkg.zip" -C $stage
    if ($LASTEXITCODE -ne 0) { throw 'tar.exe could not unpack the zip' }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Move-Item (Get-ChildItem $stage)[0].FullName $dest
    Remove-Item -Recurse -Force $stage, $tmp
  }
}

function Native($file, $argList) {   # run a program, return stdout+stderr as text, never throw
  try { return ((& $file @argList 2>&1) | Out-String) } catch { return '' }
}

function Find-Java {
  $cands = @()
  if ($env:JAVA_HOME) { $cands += "$env:JAVA_HOME\bin\java.exe" }
  $onPath = Get-Command java -ErrorAction SilentlyContinue
  if ($onPath) { $cands += $onPath.Source }
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  return $null
}

function Sdk-Tool($name) { Join-Path $SdkRoot "cmdline-tools\latest\bin\$name.bat" }

function Accept-AndroidLicences {
  Say "    > accept the Android SDK licences (you accepted them by running -Install; read them: https://developer.android.com/studio/terms)"
  if (-not $DryRun) { 1..40 | ForEach-Object { 'y' } | & (Sdk-Tool 'sdkmanager') --licenses "--sdk_root=$SdkRoot" | Out-Null }
}

# ---- the table of tools -------------------------------------------------------------------------
# Id | Name | Needed (text) | Min version | Get = prints the found version (or nothing) | Setup = installs or upgrades
$Tools = @(
  @{ Id = 'git'; Name = 'Git'; Needed = '2.30+'; Min = '2.30'
     Get = { Get-Ver (Native git @('--version')) }
     Setup = { Winget 'Git.Git' } },

  @{ Id = 'gh'; Name = 'GitHub CLI'; Needed = '2.40+'; Min = '2.40'
     Get = { Get-Ver (Native gh @('--version')) }
     Setup = { Winget 'GitHub.cli' } },

  @{ Id = 'node'; Name = 'Node.js LTS'; Needed = '22+'; Min = '22.0'
     Get = { Get-Ver (Native node @('--version')) }
     Setup = {   # winget's Node package is machine-wide (admin); the official zip is not
       $idx = @(Invoke-RestMethod https://nodejs.org/dist/index.json | ForEach-Object { $_ } | Where-Object { $_.lts })[0]   # ForEach: Windows PowerShell 5.1 hands the JSON array over as one object
       $v = $idx.version
       $sums = Get-Text "https://nodejs.org/dist/$v/SHASUMS256.txt"
       $sha = ($sums -split "`n" | Where-Object { $_ -match "node-$v-win-x64.zip" } | Select-Object -First 1) -split '\s+' | Select-Object -First 1
       Unpack-Zip "https://nodejs.org/dist/$v/node-$v-win-x64.zip" $sha $NodeDir
       Add-UserPath $NodeDir
       Add-UserPath (Join-Path $env:APPDATA 'npm')
     } },

  @{ Id = 'bun'; Name = 'Bun'; Needed = '1.1+'; Min = '1.1'
     Get = { Get-Ver (Native bun @('--version')) }
     Setup = { Winget 'Oven-sh.Bun' } },

  @{ Id = 'code'; Name = 'VS Code'; Needed = '1.90+'; Min = '1.90'
     Get = { Get-Ver ((Native code @('--version')) -split "`n" | Select-Object -First 1) }
     Setup = { Winget 'Microsoft.VisualStudioCode' } },

  @{ Id = 'jdk'; Name = 'JDK'; Needed = '17+'; Min = '17.0'
     Get = { $j = Find-Java; if ($j) { Get-Ver ((Native $j @('-version')) -split "`n" | Select-Object -First 1) } }
     Setup = {   # Android Studio's own JDK if the PC has it (nothing to download), else Microsoft's OpenJDK 21 zip
       if (Test-Path "$StudioJbr\bin\java.exe") {
         Say "    Android Studio is installed: using its JDK, $StudioJbr"
         Set-UserEnv 'JAVA_HOME' $StudioJbr
         Add-UserPath "$StudioJbr\bin"
       } else {
         $url = 'https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.zip'
         $sha = $null
         $sha = ((Get-Text "$url.sha256sum.txt") -split "\s+")[0]
         Unpack-Zip $url $sha $JdkDir
         Set-UserEnv 'JAVA_HOME' $JdkDir
         Add-UserPath "$JdkDir\bin"
       }
     } },

  @{ Id = 'android'; Name = 'Android SDK'; Needed = "API $AndroidApi + tools"; Min = $null
     Get = {
       $need = @("cmdline-tools\latest\bin\sdkmanager.bat", "platform-tools\adb.exe", "platforms\android-$AndroidApi", "build-tools\$AndroidApi.0.0")
       $missing = $need | Where-Object { -not (Test-Path (Join-Path $SdkRoot $_)) }
       if (-not $missing) { "API $AndroidApi" }
     }
     Setup = {
       $sm = Sdk-Tool 'sdkmanager'
       if (-not (Test-Path $sm)) {
         $tmp = Join-Path $env:TEMP ('lab-setup-' + [guid]::NewGuid().ToString('N'))
         Run "mkdir $tmp" { New-Item -ItemType Directory -Force $tmp | Out-Null }
         Download "https://dl.google.com/android/repository/$CmdlineZip" "$tmp\cmdline.zip"
         Check-Sha256 "$tmp\cmdline.zip" $CmdlineSha
         Run "unpack into $SdkRoot\cmdline-tools\latest" {
           Expand-Archive -Path "$tmp\cmdline.zip" -DestinationPath "$tmp\out" -Force
           New-Item -ItemType Directory -Force "$SdkRoot\cmdline-tools" | Out-Null
           if (Test-Path "$SdkRoot\cmdline-tools\latest") { Remove-Item -Recurse -Force "$SdkRoot\cmdline-tools\latest" }
           Move-Item "$tmp\out\cmdline-tools" "$SdkRoot\cmdline-tools\latest"
           Remove-Item -Recurse -Force $tmp
         }
       }
       Accept-AndroidLicences
       Run "sdkmanager --install platform-tools emulator platforms;android-$AndroidApi build-tools;$AndroidApi.0.0" {
         & $sm "--sdk_root=$SdkRoot" --install 'platform-tools' 'emulator' "platforms;android-$AndroidApi" "build-tools;$AndroidApi.0.0"
       }
       Set-UserEnv 'ANDROID_HOME' $SdkRoot
       Add-UserPath "$SdkRoot\platform-tools"
       Add-UserPath "$SdkRoot\emulator"
       Add-UserPath "$SdkRoot\cmdline-tools\latest\bin"
     } },

  @{ Id = 'image'; Name = 'Emulator image'; Needed = "$AvdName"; Min = $null
     Get = {
       $img = Test-Path (Join-Path $SdkRoot "system-images\android-$AndroidApi\google_apis\x86_64")
       $avd = Test-Path (Join-Path $env:USERPROFILE ".android\avd\$AvdName.ini")
       if ($img -and $avd) { "API $AndroidApi, AVD ok" }
     }
     Setup = {
       $sm = Sdk-Tool 'sdkmanager'
       Accept-AndroidLicences
       Run "sdkmanager --install $SysImage" { & $sm "--sdk_root=$SdkRoot" --install $SysImage }
       Run "avdmanager create avd --name $AvdName --package $SysImage --device pixel_7 --force" {
         'no' | & (Sdk-Tool 'avdmanager') create avd --name $AvdName --package $SysImage --device pixel_7 --force
       }
     } },

  @{ Id = 'flutter'; Name = 'Flutter'; Needed = '3.47+ (stable)'; Min = '3.47'
     Get = { $f = Get-Command flutter -ErrorAction SilentlyContinue; if ($f) { Get-Ver ((Native $f.Source @('--version')) -split "`n" | Select-Object -First 1) } }
     Setup = {   # the zip, not git clone: the repository's longest paths break Windows' 260-character limit
       if (Test-Path "$FlutterDir\bin\flutter.bat") { Run 'flutter upgrade' { & "$FlutterDir\bin\flutter.bat" upgrade } }
       else {
         $rel = Invoke-RestMethod https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json
         $r = $rel.releases | Where-Object { $_.hash -eq $rel.current_release.stable } | Select-Object -First 1
         Unpack-Zip "https://storage.googleapis.com/flutter_infra_release/releases/$($r.archive)" $r.sha256 $FlutterDir
       }
       Add-UserPath "$FlutterDir\bin"
       Run 'flutter config --android-sdk' { & flutter config --android-sdk $SdkRoot }
     } },

  @{ Id = 'supabase'; Name = 'Supabase CLI'; Needed = '2.0+'; Min = '2.0'
     Get = { Get-Ver (Native supabase @('--version')) }
     Setup = {   # not on winget: Scoop is the route supabase.com/docs documents for Windows
       # Scoop's own scripts need RemoteSigned: for this PowerShell window only (Process scope; with irm | iex it lasts until you close it)
       Run 'Set-ExecutionPolicy RemoteSigned -Scope Process' { try { Set-ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction Stop } catch { } }
       if (-not $DryRun -and (Get-ExecutionPolicy) -in 'Restricted', 'AllSigned') {
         throw "this computer's policy ($(Get-ExecutionPolicy)) blocks Scoop's scripts and this window cannot change it: install the Supabase CLI another way (README-mobile.md)"
       }
       if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
         Say '    Scoop (a user-level installer, no admin) is not installed: installing it from https://get.scoop.sh'
         Run 'irm https://get.scoop.sh | iex' { Invoke-RestMethod https://get.scoop.sh | Invoke-Expression }
         Refresh-Path
       }
       $haveBucket = (-not $DryRun) -and ((scoop bucket list | Out-String) -match 'supabase')
       if (-not $haveBucket) { Run 'scoop bucket add supabase' { scoop bucket add supabase https://github.com/supabase/scoop-bucket.git } }
       Run 'scoop install supabase/supabase' { scoop install supabase/supabase }
       Run 'scoop update supabase' { scoop update supabase }
       Refresh-Path
     } },

  @{ Id = 'firebase'; Name = 'Firebase CLI'; Needed = '15+'; Min = '15.0'
     Get = { Get-Ver (Native firebase.cmd @('--version')) }   # .cmd: the .ps1 shims are blocked by the default execution policy
     Setup = {   # firebase.google.com/docs/cli: npm install -g firebase-tools
       $prefix = ((Native npm.cmd @('config', 'get', 'prefix')) -split "`n" | Select-Object -First 1).Trim()
       if ($prefix -like "$env:ProgramFiles*") {
         Run "npm config set prefix $env:APPDATA\npm  (the default one is admin-only)" { npm.cmd config set prefix (Join-Path $env:APPDATA 'npm') }
         Add-UserPath (Join-Path $env:APPDATA 'npm')
       }
       Run 'npm install -g firebase-tools' { npm.cmd install -g firebase-tools; if ($LASTEXITCODE -ne 0) { throw 'npm install failed' } }
     } }
)

# ---- check, table, install ----------------------------------------------------------------------
function Test-Tool($t) {
  $found = $null
  try { $found = & $t.Get } catch { $found = $null }
  if (-not $found) { return @{ Found = '-'; Status = 'missing' } }
  if ($t.Min -and ([version](Get-Ver $found)) -lt [version]$t.Min) { return @{ Found = "$found"; Status = 'too old' } }
  return @{ Found = "$found"; Status = 'ok' }
}

$selected = $Tools
if ($Only) {
  $want = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
  $bad = $want | Where-Object { $Tools.Id -notcontains $_ }
  if ($bad) { Say "Unknown tool(s): $($bad -join ', '). Choose from: $($Tools.Id -join ', ')"; return }
  $selected = @($Tools | Where-Object { $want -contains $_.Id })
}

function Show-Table {
  $rows = foreach ($t in $selected) { $r = Test-Tool $t; $t.Status = $r.Status; [pscustomobject]@{ T = $t.Name; N = $t.Needed; F = $r.Found; S = $r.Status } }
  Say ''
  Say ('{0,-16}{1,-24}{2,-22}{3}' -f 'Tool', 'Needed', 'Found', 'Status')
  Say ('{0,-16}{1,-24}{2,-22}{3}' -f '----', '------', '-----', '------')
  foreach ($r in $rows) { Say ('{0,-16}{1,-24}{2,-22}{3}' -f $r.T, $r.N, $r.F, $r.S) }
  Say ''
}

Say "setup-mobile.ps1 - $env:COMPUTERNAME, user $env:USERNAME, PowerShell $($PSVersionTable.PSVersion)"
Show-Table
$todo = @($selected | Where-Object { $Force -or $_.Status -ne 'ok' })

if (-not $Install) {
  if ($todo.Count -eq 0) { Say 'Everything is in place. Nothing to do.' }
  else { Say "$($todo.Count) tool(s) need work. Nothing was changed. To install or upgrade them, run again with -Install (add -DryRun to see the commands first)." }
  return
}

if ($todo.Count -eq 0) { Say 'Everything is in place. Nothing to do.'; return }

if ($todo | Where-Object { $_.Id -in 'android', 'image' }) {
  Say '!! SLOW DOWNLOAD AHEAD: the Android SDK and the emulator image are about 2.6 GB together'
  Say '!! (command-line tools 160 MB, emulator ~350 MB, platform + build-tools ~130 MB, system image ~1.9 GB).'
  Say '!! On the lab network expect 10 to 30 minutes. Keep this window open.'
  Say ''
}

foreach ($t in $todo) {
  Say "== $($t.Name): $($t.Status)"
  try { & $t.Setup } catch { Say "   FAILED: $($_.Exception.Message)" }
  Refresh-Path
}

Say ''
if ($DryRun) { Say 'Dry run: nothing was changed.'; Show-Table; return }
Say 'Checking again:'
Show-Table
$bad = @($selected | Where-Object { -not $_.CheckOnly -and $_.Status -ne 'ok' })
if ($bad.Count -gt 0) {
  Say ('FAILED: still not ok after the install: ' + (($bad | ForEach-Object { $_.Name }) -join ', '))
  if ($PSCommandPath) { exit 1 }      # run as a file: the exit code says so
  $global:LASTEXITCODE = 1; return    # run with irm | iex: exit would close the student's window
}
Say 'Open a NEW PowerShell window to be sure every tool is on its PATH.'
