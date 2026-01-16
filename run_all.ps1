param(
    [string]$Edges = ".\\edges.csv",
    [string]$NodesFile = ".\\test nodes",
    [string]$ZigFile = ".\\zig-out\\bin\\the.exe",
    [string]$ResultsDir = ".\\results",
    [string]$CsvFile = ".\\results.csv"
)

if (-not (Test-Path $ResultsDir)) { New-Item -ItemType Directory -Path $ResultsDir | Out-Null }

# Ensure CSV header exists
if (-not (Test-Path $CsvFile)) {
    "from,to,heap,graph,exitCode,tookMs" | Out-File -FilePath $CsvFile -Encoding UTF8
}

$heapTypes = @("binary","fibonacci")
$graphTypes = @("array","linked")

Get-Content $NodesFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $parts = $line -split '\s+'
    if ($parts.Count -lt 2) { return }
    $from = $parts[0]; $to = $parts[1]
    if ($from -eq $to) { Write-Host "Skipping identical nodes $from -> $to"; return }

    foreach ($heap in $heapTypes) {
        foreach ($graph in $graphTypes) {
            $outfile = Join-Path $ResultsDir ("result_{0}_{1}_{2}_{3}.log" -f $from, $to, $heap, $graph)
            Write-Host "Running: zig run $ZigFile -- $Edges $heap $graph $from $to"
            $procArgs = @($Edges, $heap, $graph, $from, $to)
            $errfile = "$outfile.err"
            if (Test-Path $errfile) { Remove-Item $errfile -ErrorAction SilentlyContinue }
            if (Test-Path $outfile) { Remove-Item $outfile -ErrorAction SilentlyContinue }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $proc = Start-Process -FilePath "$ZigFile" -ArgumentList $procArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outfile -RedirectStandardError $errfile
            $sw.Stop()

            if (Test-Path $errfile) {
                Get-Content $errfile | Add-Content $outfile
                Remove-Item $errfile -ErrorAction SilentlyContinue
            }
            if ($proc.ExitCode -ne 0) { Write-Host "zig exited with code $($proc.ExitCode). See $outfile for details." }

            # Extract `took:{value}ms` from the log (preferred over measured elapsed time)
            $tookMs = ""
            try {
                $logText = Get-Content $outfile -Raw -ErrorAction Stop
                $m = [regex]::Match($logText, 'took\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*ms', 'IgnoreCase')
                if ($m.Success) { $tookMs = $m.Groups[1].Value }
            } catch {
                # ignore read errors, leave tookMs empty
            }

            # Append a CSV row: from,to,heap,graph,exitCode,tookMs
            $row = "{0},{1},{2},{3},{4},{5}" -f $from, $to, $heap, $graph, $proc.ExitCode, $tookMs
            Add-Content -Path $CsvFile -Value $row
        }
    }
}
