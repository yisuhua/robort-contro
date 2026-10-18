# Automated test dispatcher. No implicit installation or code overwrite.
# Run after clone or via bootstrap-desktop.ps1 on Windows PowerShell 5.1+.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [switch]$SkipMatlab,
    [switch]$SkipWSL
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (!(Test-Path -LiteralPath (Join-Path $RepoRoot 'integration/tests/test_reference_fk.py')) -or
    !(Test-Path -LiteralPath (Join-Path $RepoRoot 'matlab/robot_model/build_robot.m'))) {
    throw 'RepoRoot is not the expected industrial robot repository.'
}
$folder = Join-Path $RepoRoot ('integration/test-results/' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$script:rows = New-Object 'System.Collections.Generic.List[object]'
$script:failure = $false
$script:blocked = $false
function Record([string]$name,[string]$status,[int]$code,[string]$details) {
    $script:rows.Add([pscustomobject]@{name=$name;status=$status;exit_code=$code;details=$details})
    if ($status -eq 'FAILED') { $script:failure = $true }
    if ($status -eq 'BLOCKED') { $script:blocked = $true }
    Write-Host "[$status] $name - $details"
}
function RunCommand([string]$name,[string]$exe,[string[]]$arguments) {
    $log = Join-Path $folder ($name + '.log')
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exe @arguments *> $log
        $code = $LASTEXITCODE
    } catch {
        $_ | Out-File -LiteralPath $log -Append -Encoding UTF8
        $code = 1
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($null -eq $code) { $code = 1 }
    if ($code -eq 0) {
        Record $name 'PASS' 0 $log
    } else {
        Record $name 'FAILED' ([int]$code) $log
    }
}
$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $git) {
    RunCommand 'git-status' $git.Source @('-C',$RepoRoot,'status','--short')
    RunCommand 'git-head' $git.Source @('-C',$RepoRoot,'rev-parse','HEAD')
} else {
    Record 'git' 'BLOCKED' 2 'Git executable missing'
}
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$pyLauncher = Get-Command py -ErrorAction SilentlyContinue
$pythonExe = $null
$pythonPrefix = @()
if ($pythonCmd) {
    $pythonExe = $pythonCmd.Source
} elseif ($pyLauncher) {
    $pythonExe = $pyLauncher.Source
    $pythonPrefix = @('-3')
}
if ($pythonExe) {
    RunCommand 'python-offline-tests' $pythonExe ($pythonPrefix + @('-m','unittest','discover','-s',(Join-Path $RepoRoot 'integration/tests'),'-p','test_*.py','-v'))
    $src = Join-Path $RepoRoot 'integration/ros2_ws/src/industrial_robot_integration'
    RunCommand 'python-syntax' $pythonExe ($pythonPrefix + @('-m','py_compile',(Join-Path $src 'setup.py'),(Join-Path $src 'launch/demo.launch.py'),(Join-Path $src 'industrial_robot_integration/feedback_probe.py'),(Join-Path $src 'industrial_robot_integration/command_probe.py')))
} else {
    Record 'python-offline-tests' 'BLOCKED' 2 'Python 3 not detected on Windows; WSL tests may still run'
}
if ($SkipMatlab) {
    Record 'matlab-stage1-3' 'SKIPPED' 0 'Explicit -SkipMatlab'
} else {
    $matlab = Get-Command matlab -ErrorAction SilentlyContinue
    $matlabExe = $null
    if ($matlab) { $matlabExe = $matlab.Source }
    $knownMatlab = 'C:\Program Files\MATLAB\R2024b\bin\matlab.exe'
    if (!$matlabExe -and (Test-Path -LiteralPath $knownMatlab)) { $matlabExe = $knownMatlab }
    if (!$matlabExe) {
        Record 'matlab-stage1-3' 'BLOCKED' 2 'MATLAB executable not found on PATH or in default R2024b folder'
    } else {
        $robotFolder = (Join-Path $RepoRoot 'matlab/robot_model').Replace("'","''")
        # Separate MATLAB sessions preserve per-stage evidence even if inverse kinematics fails.
        # Each test starts by re-running unmodified build_robot.m.
        RunCommand 'matlab-stage1-fk' $matlabExe @('-batch',("cd('" + $robotFolder + "'); build_robot;"))
        RunCommand 'matlab-stage2-joint-motion' $matlabExe @('-batch',("cd('" + $robotFolder + "'); build_robot; stage02_joint_motion;"))
        RunCommand 'matlab-stage3-ik' $matlabExe @('-batch',("cd('" + $robotFolder + "'); build_robot; stage03_inverse_kinematics;"))
        # Network demo is excluded here: run only after ROS/Gazebo target and DDS are verified.
        Record 'matlab-ros2-roundtrip' 'BLOCKED' 2 'Real MATLAB↔ROS2 DDS reachability not pre-verified; no automatic command'
    }
}
if ($SkipWSL) {
    Record 'wsl-ros2-gazebo' 'SKIPPED' 0 'Explicit -SkipWSL'
} else {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (!$wsl) {
        Record 'wsl-ros2-gazebo' 'BLOCKED' 2 'WSL command unavailable'
    } else {
        $wslPath = & wsl.exe --exec wslpath -a $RepoRoot 2>&1
        $wslCode = $LASTEXITCODE
        if ($wslCode -ne 0 -or @($wslPath).Count -ne 1 -or ([string]$wslPath).Trim() -notlike '/*') {
            Record 'wsl-ros2-gazebo' 'BLOCKED' 2 'WSL distro not available or Windows path mapping failed'
        } else {
            $linuxRepo = ([string]$wslPath).Trim()
            $linuxReport = $linuxRepo + '/integration/test-results/' + (Split-Path $folder -Leaf) + '/wsl'
            $linuxScript = $linuxRepo + '/integration/scripts/run-wsl-tests.sh'
            RunCommand 'wsl-ros2-gazebo' $wsl.Source @('--exec','bash',$linuxScript,$linuxRepo,$linuxReport)
        }
    }
}
$head = if ($git) { ((& git -C $RepoRoot rev-parse HEAD) | Out-String).Trim() } else { 'UNKNOWN' }
$summary = [pscustomobject]@{
    repository=$RepoRoot
    timestamp_utc=(Get-Date).ToUniversalTime().ToString('o')
    git_sha=$head
    overall=$(if ($script:failure) {'FAILED'} elseif ($script:blocked) {'PARTIAL_BLOCKED'} else {'PASS_AVAILABLE_CHECKS'})
    tests=$script:rows.ToArray()
    note='PASS_AVAILABLE_CHECKS does not imply MATLAB/ROS2/Gazebo/CAD end-to-end VALID. See each stage.'
}
$summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $folder 'summary.json') -Encoding UTF8
Write-Host "Full test evidence: $folder"
Write-Host "Overall: $($summary.overall)"
if ($script:failure) { exit 1 }
if ($script:blocked) { exit 2 }
exit 0
