# Generate a stable, privacy-conscious handoff after EACH local test run.
# No network, Git commits, uploads, automatic retries, or additional tests.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$RunDirectory
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$summaryFile = Join-Path $RunDirectory 'summary.json'
if (!(Test-Path -LiteralPath $summaryFile)) { throw "Missing test summary: $summaryFile" }
$summary = Get-Content -LiteralPath $summaryFile -Raw -Encoding UTF8 | ConvertFrom-Json
$runId = Split-Path -Leaf $RunDirectory
if ($runId -notmatch '^[0-9]{8}_[0-9]{6}_[0-9]{3}$') { throw "Invalid run identifier: $runId" }
$handoff = Join-Path $RepoRoot 'handoff'
$history = Join-Path $handoff 'history'
$exports = Join-Path $handoff 'exports'
foreach ($dir in @($handoff,$history,$exports,(Join-Path $handoff 'inbox'))) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
$relativeRun = 'integration/test-results/' + $runId
function Sanitize([string]$value) {
    if ($null -eq $value) { return '' }
    $v = $value
    $v = [regex]::Replace($v,[regex]::Escape($RepoRoot),'<PROJECT>','IgnoreCase')
    $userHome = [Environment]::GetFolderPath('UserProfile')
    if ($userHome) { $v = [regex]::Replace($v,[regex]::Escape($userHome),'<USER_HOME>','IgnoreCase') }
    $v = [regex]::Replace($v,'(?i)\b(gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)\b','<REDACTED_TOKEN>')
    $v = [regex]::Replace($v,'(?i)\b(token|password|secret|api[_-]?key)\s*[:=]\s*\S+','<REDACTED_CREDENTIAL>')
    $v = [regex]::Replace($v,'(?i)([A-Z]:\\Users\\)[^\\\s]+','$1<USER>')
    return $v
}
$testRows = New-Object 'System.Collections.Generic.List[object]'
$markdownRows = New-Object 'System.Collections.Generic.List[string]'
$diagnostics = New-Object 'System.Collections.Generic.List[string]'
foreach ($test in @($summary.tests)) {
    $name = [string]$test.name
    $status = [string]$test.status
    $exitCode = [int]$test.exit_code
    $fullLog = Join-Path $RunDirectory ($name + '.log')
    $logRel = if (Test-Path -LiteralPath $fullLog) { "$relativeRun/$name.log" } else { $null }
    $safeNote = Sanitize([string]$test.details)
    if ($logRel) { $safeNote = 'See local log'; }
    $testRows.Add([pscustomobject]@{name=$name;status=$status;exit_code=$exitCode;log=$logRel;note=$safeNote})
    $markdownRows.Add("| $name | $status | $exitCode | $(if ($logRel) { $logRel } else { $safeNote }) |")
    if ($status -eq 'FAILED' -and $logRel) {
        # Select diagnostics only, never silently bundle complete raw logs.
        # Even the excerpts need human review before being uploaded to chat.
        $selected = @(Get-Content -LiteralPath $fullLog -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '(?i)\b(error|failed|fatal|exception|timeout|missing|traceback)\b|not found|could not' } |
            Select-Object -Last 15)
        $diagnostics.Add("## $name ($logRel)")
        if ($selected.Count -eq 0) { $diagnostics.Add('No matching error lines; inspect full local log.') }
        foreach ($line in $selected) { $diagnostics.Add((Sanitize([string]$line))) }
        $diagnostics.Add('')
    }
}
$wslRows = New-Object 'System.Collections.Generic.List[object]'
$wslStatus = Join-Path $RunDirectory 'wsl/status.tsv'
if (Test-Path -LiteralPath $wslStatus) {
    foreach ($line in @(Get-Content -LiteralPath $wslStatus)) {
        $fields = $line -split "`t",3
        if ($fields.Count -ge 2) {
            $wslRows.Add([pscustomobject]@{
                stage=Sanitize([string]$fields[0])
                status=Sanitize([string]$fields[1])
                details=$(if ($fields.Count -gt 2) { Sanitize([string]$fields[2]) } else { '' })
            })
        }
    }
}
$handoffData = [pscustomobject]@{
    schema_version='1.0'
    project='yisuhua/robort-contro'
    status_scope='LOCAL_TEST_EVIDENCE_ONLY'
    generated_utc=(Get-Date).ToUniversalTime().ToString('o')
    source_run_utc=[string]$summary.timestamp_utc
    run_id=$runId
    git_sha=[string]$summary.git_sha
    overall=[string]$summary.overall
    test_results_relative=$relativeRun
    tests=$testRows.ToArray()
    wsl_stages=$wslRows.ToArray()
    not_run=@('Actual CAD collision and FEA','Hardware actuation and safety',
              'MATLAB-ROS2 DDS roundtrip unless separately verified')
    notes='Not a validation of full MATLAB/ROS2/Gazebo/CAD integration; inspect local logs for failures.'
}
$md = @(
    '# 工业机器人｜最新实验交付（自动生成）'
    ''
    "> 每次本地测试后更新；仅代表当次执行证据，不表示整套机器人系统已经通过。"
    ''
    '- 项目：yisuhua/robort-contro'
    ('- 运行 ID：{0}' -f $runId)
    ('- UTC：{0}' -f $handoffData.generated_utc)
    ('- Git SHA：{0}' -f $handoffData.git_sha)
    ('- 总状态：**{0}**' -f $handoffData.overall)
    ('- 原始证据：{0}/（本地保存，不自动推送）' -f $relativeRun)
    ''
    '## 各阶段状态'
    ''
    '| 检查项 | 状态 | 退出码 | 原始日志／说明 |'
    '|---|---|---:|---|'
)
$md += @($markdownRows.ToArray())
if ($wslRows.Count -gt 0) {
    $md += @('','## WSL 子阶段','','| 检查项 | 状态 | 说明 |','|---|---|---|')
    foreach ($stage in @($wslRows.ToArray())) {
        $md += "| $($stage.stage) | $($stage.status) | $($stage.details) |"
    }
}
$md += @('','## 尚未获得正式验证的范围','','- MATLAB ↔ ROS2 跨系统 DDS 往返（单独验收）',
          '- 实际 CAD 质量、惯量、碰撞与机械限位',
          '- 实体机械臂、硬件安全及真实动力学性能',
          '','## 提交给 ChatGPT',
          '',
          '优先上传 `handoff/exports/LATEST.zip`（报告、文件清单、相关源码配置、小型生成结果及失败摘要）。',
          '完整原始日志只保存在 `integration/test-results/`，按需检查后再分享。',
          '自己要补充的截图、笔记和外部实验数据放在 `handoff/inbox/`，不会自动写入 ZIP 或上传。',
          '交付前请自行核查可能包含的路径、用户名、设备信息或访问凭据。',
          '',
          '## 失败摘要（最多每项 15 条匹配日志）',
          '')
if ($diagnostics.Count) { $md += @($diagnostics.ToArray()) }
else { $md += '没有采集到 FAILED 项的错误摘录；BLOCKED/SKIPPED 项请看上表。' }
$latestMd = Join-Path $handoff 'LATEST.md'
$latestJson = Join-Path $handoff 'LATEST.json'
# Write new history FIRST; replace LATEST only after the full rendering succeeds.
$mdText = $md -join [Environment]::NewLine
$jsonText = $handoffData | ConvertTo-Json -Depth 9
$mdText | Set-Content -LiteralPath (Join-Path $history ($runId + '.md')) -Encoding UTF8
$jsonText | Set-Content -LiteralPath (Join-Path $history ($runId + '.json')) -Encoding UTF8
$mdText | Set-Content -LiteralPath $latestMd -Encoding UTF8
$jsonText | Set-Content -LiteralPath $latestJson -Encoding UTF8
$tmp = Join-Path $exports ('staging_' + $runId)
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Copy-Item -LiteralPath $latestMd -Destination (Join-Path $tmp 'LATEST.md')
    Copy-Item -LiteralPath $latestJson -Destination (Join-Path $tmp 'LATEST.json')
    # Small, explicit whitelist of the *actual* implementation inputs in this Git SHA.
    # Never traverse .git, inbox, downloads, random .env, credentials or a full dataset.
    $sourcePaths = @(
        'matlab/robot_model/build_robot.m',
        'matlab/robot_model/stage02_joint_motion.m',
        'matlab/robot_model/stage03_inverse_kinematics.m',
        'integration/matlab/ros2_roundtrip_demo.m',
        'integration/ros2_ws/src/industrial_robot_integration/urdf/robot.urdf.xacro',
        'integration/ros2_ws/src/industrial_robot_integration/config/controllers.yaml',
        'integration/ros2_ws/src/industrial_robot_integration/launch/demo.launch.py',
        'integration/ros2_ws/src/industrial_robot_integration/industrial_robot_integration/feedback_probe.py',
        'integration/ros2_ws/src/industrial_robot_integration/industrial_robot_integration/command_probe.py',
        'integration/tests/test_reference_fk.py',
        'integration/tests/test_static_contract.py',
        'integration/tests/validate_expanded_urdf.py',
        'integration/python_adapter/contract_v1.schema.json'
    )
    $includedSource = New-Object 'System.Collections.Generic.List[string]'
    $missingSource = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in $sourcePaths) {
        $inputPath = Join-Path $RepoRoot $relative
        if (!(Test-Path -LiteralPath $inputPath -PathType Leaf)) {
            $missingSource.Add($relative)
            continue
        }
        $fileInfo = Get-Item -LiteralPath $inputPath
        if ($fileInfo.Length -gt 524288) {
            $missingSource.Add("$relative (source exceeds 512 KiB cap)")
            continue
        }
        $destPath = Join-Path $tmp ('sources/' + $relative)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destPath) | Out-Null
        Copy-Item -LiteralPath $inputPath -Destination $destPath
        $includedSource.Add($relative)
    }
    # Bounded, format-specific outputs from this SAME run; no full raw logs.
    $outputPaths = @('wsl/status.tsv','wsl/inventory.txt',
                     'wsl/kinematic.urdf','wsl/demo.urdf','wsl/demo.sdf')
    $includedOutput = New-Object 'System.Collections.Generic.List[string]'
    $excludedOutput = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in $outputPaths) {
        $inputPath = Join-Path $RunDirectory $relative
        if (!(Test-Path -LiteralPath $inputPath -PathType Leaf)) { continue }
        $fileInfo = Get-Item -LiteralPath $inputPath
        if ($fileInfo.Length -gt 1048576) {
            $excludedOutput.Add("$relative (generated evidence exceeds 1 MiB cap)")
            continue
        }
        $destPath = Join-Path $tmp ('evidence/' + $relative)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destPath) | Out-Null
        Copy-Item -LiteralPath $inputPath -Destination $destPath
        $includedOutput.Add($relative)
    }
    $diagnosticFile = Join-Path $tmp 'diagnostics/failure-excerpts.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $diagnosticFile) | Out-Null
    if ($diagnostics.Count) {
        # Trim excerpts to bound package size. Redaction is best effort; review before sharing.
        $excerpts = [string]::Join([Environment]::NewLine,$diagnostics.ToArray())
        if ($excerpts.Length -gt 40000) { $excerpts = $excerpts.Substring(0,40000) + [Environment]::NewLine + '[TRUNCATED]' }
        $excerpts | Set-Content -LiteralPath $diagnosticFile -Encoding UTF8
    } else {
        'No FAILED test diagnostic excerpts collected in this run.' | Set-Content -LiteralPath $diagnosticFile -Encoding UTF8
    }
    $filesMd = @(
        '# 交付文件清单'
        ''
        ('- Git SHA: {0}' -f $handoffData.git_sha)
        ('- Test run: {0}' -f $runId)
        '- sources/: 该版本机器人运动学、控制器、ROS2/Gazebo 和 Python 接口相关关键源码与配置'
        '- evidence/: 当次生成的小型 WSL 状态、版本清单、URDF/SDF（仅在可用时）'
        '- diagnostics/: 失败日志关键摘录，不是完整日志'
        '- LATEST.md, LATEST.json: 最新检查状态'
        '- MANIFEST.json: 实际入包文件 SHA256、大小和遗漏记录'
        ''
        '## 有意不自动打包'
        '- MATLAB .mat、大型 CSV/数据集、Gazebo bag、CAD/STEP/SLDPRT、仿真录像/图片和全部原始日志'
        '- inbox/ 中手工添加的私人文件；只能经人工检查后选择性上传'
        '- 禁止任何密钥、令牌、环境变量文件和自动上传'
        ''
        '需要完整诊断时请从 integration/test-results/<run_id>/ 选择对应日志单独分享。'
    )
    $filesMd -join [Environment]::NewLine | Set-Content -LiteralPath (Join-Path $tmp 'FILES.md') -Encoding UTF8
    $archiveEntries = @(Get-ChildItem -LiteralPath $tmp -Recurse -File | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{
            path=$_.FullName.Substring($tmp.Length+1).Replace('\\','/')
            bytes=[long]$_.Length
            sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $manifest = [pscustomobject]@{
        schema_version='2.0'
        run_id=$runId
        git_sha=[string]$handoffData.git_sha
        entrypoint='LATEST.md'
        source_count=$includedSource.Count
        included_source_paths=$includedSource.ToArray()
        absent_or_oversized_source_paths=$missingSource.ToArray()
        included_run_outputs=$includedOutput.ToArray()
        omitted_run_outputs=$excludedOutput.ToArray()
        entries=$archiveEntries
        note='Small, bounded package. This manifest is not proof that tests passed. Review sensitive content before uploading.'
    }
    $manifest | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $tmp 'MANIFEST.json') -Encoding UTF8
    $archive = Join-Path $exports ('run_' + $runId + '.zip')
    Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $archive -Force
    Copy-Item -LiteralPath $archive -Destination (Join-Path $exports 'LATEST.zip') -Force
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Latest handoff: $latestMd"
Write-Host "Shareable handoff package: $(Join-Path $exports 'LATEST.zip')"
