# setup-web.ps1 - check (and, with -Install, set up) the tools of the Advanced Web Development course.
# Windows PowerShell 5.1 or PowerShell 7. Plain ASCII on purpose.
#
#   .\setup-web.ps1                    check only: prints a table, changes nothing
#   .\setup-web.ps1 -Install           install or upgrade what is missing or too old, then check again
#   .\setup-web.ps1 -Install -DryRun   print every command it would run, run none
#   .\setup-web.ps1 -Only node,bun     limit the check (and the install) to these tools
#   .\setup-web.ps1 -Install -Force    redo the install even for tools that are fine (with -Only, to repair one)
#
# Everything goes into your own user profile; no administrator needed unless the table says so.
# PATH is changed in YOUR user environment only (and in this window).
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
$NodeDir      = Join-Path $env:LOCALAPPDATA 'node'

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
  $u = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($null -eq $u) { $u = '' }
  if (($u -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', "$dir;$u", 'User') }
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

function Winget($id) {               # user scope first; if the package has no user installer, ask for the default
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget not found (install "App Installer" from the Microsoft Store)' }
  $common = @('--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
  Run "winget install $id --scope user" { winget install @common --scope user }
  if (-not $DryRun -and $LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {   # -1978335189 = already up to date
    Say "    no user-scope installer for $id; trying the default (this one may ask for administrator rights)"
    winget install @common
  }
  Refresh-Path
}

function Unpack-Zip($url, $sha, $dest) {   # download, verify, unpack the zip's one top folder as $dest (replacing it)
  $tmp = Join-Path $env:TEMP ('lab-setup-' + [guid]::NewGuid().ToString('N'))
  Run "mkdir $tmp" { New-Item -ItemType Directory -Force $tmp | Out-Null }
  Download $url "$tmp\pkg.zip"
  if ($sha) { Check-Sha256 "$tmp\pkg.zip" $sha }
  Run "unpack into $dest" {
    Expand-Archive -Path "$tmp\pkg.zip" -DestinationPath "$tmp\out" -Force
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Move-Item (Get-ChildItem "$tmp\out")[0].FullName $dest
    Remove-Item -Recurse -Force $tmp
  }
}

function Native($file, $argList) {   # run a program, return stdout+stderr as text, never throw
  try { return ((& $file @argList 2>&1) | Out-String) } catch { return '' }
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

  # WSL is only reported, never installed: it needs administrator rights and a restart.
  # (In some labs Hyper-V is switched off for the first weeks; see the README.)
  @{ Id = 'wsl'; Name = 'WSL 2'; Needed = 'optional'; Min = $null; CheckOnly = $true
     Get = {
       if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
         $v = (Native wsl.exe @('--version')) -replace "`0", ''
         $x = Get-Ver $v
         if ($x) { return $x }
         if ((Native wsl.exe @('--status')) -replace "`0", '' -match 'Default') { return 'installed' }
       }
     } }
)

# ---- check, table, install ----------------------------------------------------------------------
function Test-Tool($t) {
  $found = $null
  try { $found = & $t.Get } catch { $found = $null }
  if (-not $found) { return @{ Found = '-'; Status = $(if ($t.CheckOnly) { 'not installed (optional)' } else { 'missing' }) } }
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

Say "setup-web.ps1 - $env:COMPUTERNAME, user $env:USERNAME, PowerShell $($PSVersionTable.PSVersion)"
Show-Table
$todo = @($selected | Where-Object { -not $_.CheckOnly -and ($Force -or $_.Status -ne 'ok') })

if (-not $Install) {
  if ($todo.Count -eq 0) { Say 'Everything is in place. Nothing to do.' }
  else { Say "$($todo.Count) tool(s) need work. Nothing was changed. To install or upgrade them, run again with -Install (add -DryRun to see the commands first)." }
  return
}

if ($todo.Count -eq 0) { Say 'Everything is in place. Nothing to do.'; return }

foreach ($t in $todo) {
  Say "== $($t.Name): $($t.Status)"
  try { & $t.Setup } catch { Say "   FAILED: $($_.Exception.Message)" }
  Refresh-Path
}

Say ''
if ($DryRun) { Say 'Dry run: nothing was changed.'; Show-Table; return }
Say 'Checking again:'
Show-Table
Say 'Open a NEW PowerShell window to be sure every tool is on its PATH.'
