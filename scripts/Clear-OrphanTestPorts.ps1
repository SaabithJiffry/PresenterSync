param(
    [switch]$IncludeServicePorts,
    [switch]$CleanLogs
)

$ports = 14455..14499
if ($IncludeServicePorts) { $ports += 4455..4457 }
$names = @('AutoHotkey64', 'python', 'PresenterSync', 'PresenterSync_Remote')

$pids = New-Object System.Collections.Generic.HashSet[int]
foreach ($c in @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $ports -contains $_.LocalPort })) {
    [void]$pids.Add([int]$c.OwningProcess)
}
foreach ($e in @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $ports -contains $_.LocalPort })) {
    [void]$pids.Add([int]$e.OwningProcess)
}

foreach ($procId in $pids) {
    if ($procId -le 4 -or $procId -eq $PID) { continue }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($p -and ($names -contains $p.ProcessName)) {
        Write-Output "Stopping $($p.ProcessName) (PID $procId)"
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    }
}

if ($CleanLogs) {
    $logs = Join-Path $PSScriptRoot '..\tests\*_results.log'
    Remove-Item -Path $logs -Force -ErrorAction SilentlyContinue
}
exit 0
