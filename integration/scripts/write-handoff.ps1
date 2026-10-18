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
    "- 项目：`yisuhua/robort-contro`"
    "- 运行 ID：`$runId`"
    "- UTC：`$($handoffData.generated_utc)`"
    "- Git SHA：`$($handoffData.git_sha)`"
    "- 总状态：**$($handoffData.overall)**"
    "- 原始证据：`$relativeRun/`（本地保存，不自动推送）"
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
          '优先上传 `handoff/exports/LATEST.zip`（本文件、结构化状态及少量失败摘录）。',
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
    $archive = Join-Path $exports ('run_' + $runId + '.zip')
    Compress-Archive -Path (Join-Path $tmp 'LATEST.md'),(Join-Path $tmp 'LATEST.json') -DestinationPath $archive -Force
    Copy-Item -LiteralPath $archive -Destination (Join-Path $exports 'LATEST.zip') -Force
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Latest handoff: $latestMd"
Write-Host "Shareable handoff package: $(Join-Path $exports 'LATEST.zip')"
