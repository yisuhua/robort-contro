# Clones/updates the EXISTING GitHub integration branch on the actual Windows Desktop,
# then invokes the full available test runner. No software installation, no real robot.
[CmdletBinding()]
param(
    [switch]$SkipMatlab,
    [switch]$SkipWSL
)
$ErrorActionPreference = 'Stop'
$branch = 'feature/matlab-ros2-gazebo-integration'
$remote = 'https://github.com/yisuhua/robort-contro.git'
$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop) -or !(Test-Path -LiteralPath $desktop)) {
    throw 'Windows Desktop path is not accessible. No clone attempted.'
}
$target = Join-Path $desktop 'robort-contro'
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is missing: install Git for Windows first. No files were modified.'
}
if (Test-Path -LiteralPath $target) {
    if (!(Test-Path -LiteralPath (Join-Path $target '.git'))) {
        throw "Target folder already exists but is not a Git repository: $target. Refusing to overwrite."
    }
    $origin = (& git -C $target remote get-url origin 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $origin -notmatch '(?i)(github.com[:/])yisuhua/robort-contro(?:\.git)?$') {
        throw "Existing repository has a different origin: $origin. Refusing to overwrite."
    }
    $dirty = & git -C $target status --porcelain
    if ($LASTEXITCODE -ne 0 -or ($null -ne $dirty -and @($dirty).Count -gt 0)) {
        throw 'Existing desktop working tree is not clean. Commit/stash your changes before updating.'
    }
    & git -C $target fetch origin $branch
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed; tests not started.' }
    & git -C $target checkout $branch
    if ($LASTEXITCODE -ne 0) { throw 'git checkout failed; tests not started.' }
    & git -C $target merge --ff-only "origin/$branch"
    if ($LASTEXITCODE -ne 0) { throw 'git fast-forward rejected; tests not started.' }
} else {
    & git clone --branch $branch --single-branch $remote $target
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed; tests not started.' }
}
Write-Host "Desktop project: $target"
$runner = Join-Path $target 'integration/scripts/run-desktop-tests.ps1'
if (!(Test-Path -LiteralPath $runner)) { throw "Missing test runner: $runner" }
& $runner -RepoRoot $target -SkipMatlab:$SkipMatlab -SkipWSL:$SkipWSL
exit $LASTEXITCODE
