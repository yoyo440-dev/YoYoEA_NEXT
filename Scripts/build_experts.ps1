param(
    [string]$MetaEditorPath = 'D:\Rakuten_MT4\metaeditor.exe',
    [string]$SourceRoot = 'D:\EA開発2025_10_26\YoYoEA_NEXT\MQL4\Experts',
    [string]$TerminalExperts = 'D:\Rakuten_MT4\MQL4\Experts',
    [string]$LogDirectory = 'D:\EA開発2025_10_26\CompileLog'
)

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

function Ensure-Path {
    param([string]$PathValue, [string]$Description)
    if (-not (Test-Path -LiteralPath $PathValue)) {
        Write-Error "$Description not found: $PathValue"
        exit 1
    }
}

Ensure-Path -PathValue $MetaEditorPath -Description 'MetaEditor'
Ensure-Path -PathValue $SourceRoot -Description 'Source root'
Ensure-Path -PathValue $TerminalExperts -Description 'Terminal Experts folder'

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
    Write-Status "No MQ4 files found under $($sourceDir.FullName)" -Color Yellow
    exit 0
}

$metaEditor = Get-Item -LiteralPath $MetaEditorPath
$terminalDir = Get-Item -LiteralPath $TerminalExperts
$overallSuccess = $true

foreach ($mq4 in $mq4Files) {
    Write-Status "=== Compile: $($mq4.FullName)" -Color Cyan

    $logPath = Join-Path -Path $LogDirectory -ChildPath (([System.IO.Path]::GetFileNameWithoutExtension($mq4.Name)) + '_compile.log')
    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    $arguments = @(
        "/compile:`"$($mq4.FullName)`"",
        "/log:`"$logPath`"",
        "/portable"
    )
    $process = Start-Process -FilePath $metaEditor.FullName -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        Write-Status "MetaEditor exit code $($process.ExitCode) (see log)" -Color Yellow
    }

    if (-not (Test-Path -LiteralPath $logPath)) {
        Write-Error "Compile log was not generated: $logPath"
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
        Write-Error "Compile failed: $($mq4.Name) (errors: $errorCount)"
        $overallSuccess = $false
        continue
    }

    if ($warningCount -gt 0) {
        Write-Status "Warnings: $warningCount" -Color Yellow
    }

    $relative = $mq4.FullName.Substring($sourceDir.FullName.Length).TrimStart([char]92,[char]47)
    $destRelative = [System.IO.Path]::ChangeExtension($relative, '.ex4')
    $destPath = [System.IO.Path]::Combine($terminalDir.FullName, $destRelative)
    $destDir = [System.IO.Path]::GetDirectoryName($destPath)

    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $ex4Path -Destination $destPath -Force
    Write-Status "Copied: $destPath" -Color Green
}

if ($overallSuccess) {
    Write-Status "All MQ4 compiled and copied" -Color Green
    exit 0
}
else {
    Write-Error "One or more files failed to compile"
    exit 1
}
