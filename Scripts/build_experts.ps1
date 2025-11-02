param(
    [string]$MetaEditorPath,
    [string]$SourceRoot,
    [string]$TerminalExperts,
    [string]$LogDirectory
)

$projectRoot = Split-Path -Path $PSScriptRoot -Parent

if (-not $MetaEditorPath -or [string]::IsNullOrWhiteSpace($MetaEditorPath)) {
    $metaCandidates = @(
        (Join-Path -Path $HOME -ChildPath 'Rakuten_MT4/metaeditor.exe'),
        '/mnt/d/Rakuten_MT4/metaeditor.exe'
    )
    $MetaEditorPath = $metaCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $MetaEditorPath) {
        $MetaEditorPath = $metaCandidates[0]
    }
}

if (-not $SourceRoot -or [string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path -Path $projectRoot -ChildPath 'YoYoEA_NEXT/MQL4/Experts'
}

if (-not $TerminalExperts -or [string]::IsNullOrWhiteSpace($TerminalExperts)) {
    $terminalCandidates = @(
        (Join-Path -Path $HOME -ChildPath 'Rakuten_MT4/MQL4/Experts'),
        '/mnt/d/Rakuten_MT4/MQL4/Experts'
    )
    $TerminalExperts = $terminalCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $TerminalExperts) {
        $TerminalExperts = $terminalCandidates[0]
    }
}

if (-not $LogDirectory -or [string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path -Path $projectRoot -ChildPath 'Log'
}

function Write-Status {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    $previous = $Host.UI.RawUI.ForegroundColor
    try {
        $Host.UI.RawUI.ForegroundColor = $Color
        Write-Host $Message
    }
    finally {
        $Host.UI.RawUI.ForegroundColor = $previous
    }
}

function Convert-ToMetaPath {
    param([string]$PathValue)

    if ($IsWindows -or [string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

    $converted = & wslpath -w -- $PathValue 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $converted) {
        return $PathValue
    }

    return $converted.Trim()
}

function Ensure-Path {
    param([string]$PathValue, [string]$Description)
    if (-not (Test-Path -LiteralPath $PathValue)) {
        Write-Error "$Description が見つかりません: $PathValue"
        exit 1
    }
}

Ensure-Path -PathValue $MetaEditorPath -Description 'MetaEditor'
Ensure-Path -PathValue $SourceRoot -Description 'ソースフォルダ'
Ensure-Path -PathValue $TerminalExperts -Description 'MT4のExpertsフォルダ'

if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}

$sourceDir = Get-Item -LiteralPath $SourceRoot
$gciParams = @{
    LiteralPath = $sourceDir.FullName
    Filter      = '*.mq4'
    Recurse     = $true
    File        = $true
    ErrorAction = [System.Management.Automation.ActionPreference]::SilentlyContinue
}
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $gciParams['FollowSymlink'] = $true
}
$mq4Files = Get-ChildItem @gciParams

if (-not $mq4Files -or $mq4Files.Count -eq 0) {
    Write-Status "MQ4ファイルが見つかりません: $($sourceDir.FullName)" -Color Yellow
    exit 0
}

$metaEditor = Get-Item -LiteralPath $MetaEditorPath
$terminalDir = Get-Item -LiteralPath $TerminalExperts
$overallSuccess = $true

foreach ($mq4 in $mq4Files) {
    Write-Status "=== コンパイル開始: $($mq4.FullName)" -Color Cyan

    $logPath = Join-Path -Path $LogDirectory -ChildPath (([System.IO.Path]::GetFileNameWithoutExtension($mq4.Name)) + '_compile.log')
    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    $compileTarget = Convert-ToMetaPath -PathValue $mq4.FullName
    $logTarget = Convert-ToMetaPath -PathValue $logPath

    $arguments = @(
        "/compile:`"$compileTarget`"",
        "/log:`"$logTarget`"",
        "/portable"
    )
    $startParams = @{
        FilePath      = $metaEditor.FullName
        ArgumentList  = $arguments
        Wait          = $true
        PassThru      = $true
    }
    if ($IsWindows) {
        $startParams['WindowStyle'] = 'Hidden'
    }

    try {
        $process = Start-Process @startParams
    }
    catch {
        Write-Error "MetaEditor の起動に失敗しました: $_"
        $overallSuccess = $false
        continue
    }

    if ($process.ExitCode -ne 0) {
        Write-Status "MetaEditor の終了コード: $($process.ExitCode)（詳細はログを参照）" -Color Yellow
    }

    if (-not (Test-Path -LiteralPath $logPath)) {
        Write-Error "コンパイルログが生成されませんでした: $logTarget"
        if (-not $IsWindows) {
            Write-Status "WSL から実行する場合はログ出力先を Windows パスに変更するか、Windows 側の PowerShell でスクリプトを実行してください。" -Color Yellow
        }
        $overallSuccess = $false
        continue
    }

    $logLines = Get-Content -LiteralPath $logPath
    $logSummary = $logLines | Where-Object { $_ -match '\\berror\\(s\\)' } | Select-Object -Last 1

    $errorCount = 0
    $warningCount = 0
    if ($logSummary) {
        if ($logSummary -match '(\d+) error\(s\)') {
            $errorCount = [int]$Matches[1]
        }
        if ($logSummary -match '(\d+) warning\(s\)') {
            $warningCount = [int]$Matches[1]
        }
    }

    $ex4Path = [System.IO.Path]::ChangeExtension($mq4.FullName, '.ex4')

    if ($errorCount -gt 0 -or -not (Test-Path -LiteralPath $ex4Path)) {
        Write-Error "コンパイル失敗: $($mq4.Name)（エラー数: $errorCount）"
        $overallSuccess = $false
        continue
    }

    if ($warningCount -gt 0) {
        Write-Status "警告数: $warningCount" -Color Yellow
    }

    $relative = $mq4.FullName.Substring($sourceDir.FullName.Length).TrimStart([char]92,[char]47)
    $destRelative = [System.IO.Path]::ChangeExtension($relative, '.ex4')
    $destPath = [System.IO.Path]::Combine($terminalDir.FullName, $destRelative)
    $destDir = [System.IO.Path]::GetDirectoryName($destPath)

    try {
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
    }
    catch {
        Write-Error "出力先フォルダを作成できません: $destDir (`$_)"
        if (-not $IsWindows) {
            Write-Status "WSL の /mnt 経由で書き込みできない場合は Windows 側のフォルダ権限を確認してください。" -Color Yellow
        }
        $overallSuccess = $false
        continue
    }

    try {
        Copy-Item -LiteralPath $ex4Path -Destination $destPath -Force
        Write-Status "コピー完了: $destPath" -Color Green
    }
    catch {
        Write-Error "EX4 コピーに失敗しました: $destPath (`$_)"
        if (-not $IsWindows) {
            Write-Status "WSL 環境で失敗する場合は、Windows 側で同等のコピー処理を実行することを検討してください。" -Color Yellow
        }
        $overallSuccess = $false
        continue
    }
}

if ($overallSuccess) {
    Write-Status "すべてのMQ4ファイルをコンパイルしてコピーしました" -Color Green
    exit 0
}
else {
    Write-Error "コンパイルに失敗したファイルがあります"
    exit 1
}
