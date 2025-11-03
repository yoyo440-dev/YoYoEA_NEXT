$ErrorActionPreference = 'Stop'

$metaEditor = 'D:\Rakuten_MT4\metaeditor.exe'
$sourceMq4 = 'D:\EA開発2025_10_26\YoYoEA_NEXT\MQL4\Experts\YoYoEntryTester.mq4'
$targetMq4 = 'D:\Rakuten_MT4\MQL4\Experts\YoYoEntryTester.mq4'
$logDir     = 'D:\EA開発2025_10_26\CompileLog'

if (-not (Test-Path -LiteralPath $metaEditor)) {
    throw "MetaEditor を検出できません: $metaEditor"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetMq4) | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Copy-Item -LiteralPath $sourceMq4 -Destination $targetMq4 -Force

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile   = Join-Path $logDir "YoYoEntryTester_$timestamp.log"

$arguments = @(
    '/portable'
    "/compile:$targetMq4"
    "/log:$logFile"
)

$process = Start-Process -FilePath $metaEditor -ArgumentList $arguments -Wait -PassThru

$ex4Path = [System.IO.Path]::ChangeExtension($targetMq4, '.ex4')
if (-not (Test-Path -LiteralPath $ex4Path)) {
    throw "コンパイルで EX4 が生成されませんでした: $ex4Path"
}

if ($process.ExitCode -ne 0) {
    $logLines = Get-Content -LiteralPath $logFile -ErrorAction Ignore
    $compiledOk = $false
    foreach ($line in $logLines) {
        if ($line -match 'Result:\s*0\s+errors') {
            $compiledOk = $true
            break
        }
    }
    if (-not $compiledOk) {
        throw "MetaEditor が異常終了しました (ExitCode=$($process.ExitCode))。ログ: $logFile"
    }
}

Write-Output ("Compilation succeeded.`nMQ4 : {0}`nEX4 : {1}`nLOG : {2}" -f $targetMq4, $ex4Path, $logFile)
