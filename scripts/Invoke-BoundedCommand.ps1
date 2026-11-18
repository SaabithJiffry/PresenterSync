param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [int]$TimeoutSeconds = 60,
    [string]$WorkingDirectory = ""
)

$outFile = [System.IO.Path]::GetTempFileName()
$errFile = [System.IO.Path]::GetTempFileName()

function Show-Output([string]$Label, [string]$Path, [int]$Tail = 0) {
    if (-not (Test-Path $Path)) { return }
    $lines = Get-Content -Path $Path -ErrorAction SilentlyContinue
    if ($null -eq $lines) { return }
    if ($Tail -gt 0) { $lines = @($lines) | Select-Object -Last $Tail }
    $lines | ForEach-Object { Write-Output $_ }
}

# `powershell -File` passes "a,b" as ONE string; split it back into an array.
if ($ArgumentList.Count -eq 1 -and $ArgumentList[0] -match ',' -and $ArgumentList[0] -notmatch '"') {
    $ArgumentList = $ArgumentList[0].Split(',')
}
# Quote arguments containing spaces (Start-Process joins with plain spaces).
$ArgumentList = @($ArgumentList | ForEach-Object { if ($_ -match '\s' -and $_ -notmatch '^".*"$') { '"' + $_ + '"' } else { $_ } })

# If the target is an AHK script, prepend AutoHotkey executable
if ($FilePath -like "*.ahk") {
    $ahkPath = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    if (-not (Test-Path $ahkPath)) {
        throw "AutoHotkey executable not found at $ahkPath"
    }
    # The script becomes the first argument, followed by any existing arguments
    $ArgumentList = @($FilePath) + $ArgumentList
    $FilePath = $ahkPath
}

if ($FilePath -like "*.py") {
    $ArgumentList = @($FilePath) + $ArgumentList
    $FilePath = "python"
}

$params = @{
    FilePath               = $FilePath
    PassThru               = $true
    NoNewWindow            = $true
    RedirectStandardOutput = $outFile
    RedirectStandardError  = $errFile
}
if ($ArgumentList.Count -gt 0) { $params.ArgumentList = $ArgumentList }
if ($WorkingDirectory -ne "") { $params.WorkingDirectory = $WorkingDirectory }

$proc = Start-Process @params
$timeoutMs = $TimeoutSeconds * 1000

if (-not $proc.WaitForExit($timeoutMs)) {
    cmd /c "taskkill /T /F /PID $($proc.Id)" >$null 2>&1
    Write-Output "--- stdout (tail) ---"
    Show-Output "stdout" $outFile 50
    Write-Output "--- stderr (tail) ---"
    Show-Output "stderr" $errFile 50
    Write-Output "[TIMEOUT] Process $($proc.Id) exceeded ${TimeoutSeconds}s and was terminated."
    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    exit 124
}

$proc.WaitForExit()
$code = $proc.ExitCode
Show-Output "stdout" $outFile
Show-Output "stderr" $errFile
Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
exit $code
