# Performance pass for Windows (windowed, needs a GPU; close other Godot processes first).
# Runs dev/look/stream_bench.tscn per mode, then the perf-related headless validator suites,
# and writes everything to .artifacts/perf/<timestamp>/ (git-ignored).
#   tools\build\perf_pass.ps1                      route, ladder, sewer, flashlight, then suites
#   tools\build\perf_pass.ps1 -Quick               route only, 30 s, no suites
#   tools\build\perf_pass.ps1 -Modes route,city -Seconds 120
#   tools\build\perf_pass.ps1 -SkipSuites
# Godot: $env:GODOT_BIN, else G:\Projects\Godot\Godot_console.exe.
param(
	[string[]]$Modes = @('route', 'levels', 'play', 'ladder', 'sewer', 'flashlight'),
	[int]$Seconds = 90,
	[double]$Speed = 14,   # metres per second; 7 is a sprint, 14 stresses streaming twice as hard
	[string]$Seed = '-',
	[string]$Graphics = '',   # force a tier: LOW / MEDIUM / HIGH (ULTRA is accepted and means HIGH; default: auto-detected)
	[switch]$Quick,
	[switch]$SkipSuites
)
# Godot writes warnings to stderr; 'Stop' would turn those into script failures.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'G:\Projects\Godot\Godot_console.exe' }
if (-not (Test-Path $godot)) { Write-Error "Godot not found at $godot (set GODOT_BIN)"; exit 2 }
# `powershell -File ... -Modes route,ladder` delivers one comma-joined string
$Modes = @($Modes | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Quick) { $Modes = @('route'); $Seconds = 30; $SkipSuites = $true }

$busy = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' })
if ($busy.Count -gt 0) {
	Write-Warning "Godot already running ($($busy.Count) process(es)); frame-time results will be unreliable."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $root ".artifacts\perf\$stamp"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $root
try {
	if (-not (Test-Path '.godot\imported')) {
		Write-Host 'Importing project...'
		& $godot --headless --path . --import | Out-Null
	}

	$summary = @()
	foreach ($mode in $Modes) {
		Write-Host "== bench: $mode ($Seconds s)"
		$log = Join-Path $out "bench_$mode.log"
		$tier = if ($Graphics) { @("--graphics=$Graphics") } else { @() }
		# --graphics must come AFTER `--`: PlatformProfile reads only the user arguments (before it, the flag is ignored)
		& $godot --path . res://dev/look/stream_bench.tscn -- $out $mode $mode $Seconds $Seed $Speed @tier 2>&1 | Tee-Object $log | Select-String '^(BENCH|TRIP|HITCH|COLLECT|PLAY|TOGGLE|STARTUP)' | ForEach-Object { $_.Line }
		$summary += "bench ${mode}: exit $LASTEXITCODE"
	}

	if (-not $SkipSuites) {
		$suites = @('stream_perf', 'prop_perf', 'lods', 'quality_tiers', 'maze_culling', 'lens_cull', 'idle_stability')
		$bench = Get-ChildItem $out -Filter 'stream_bench_route.json' -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($bench) { $env:STREAM_BENCH_JSON = $bench.FullName }
		Write-Host "== suites: $($suites -join ' ')"
		$log = Join-Path $out 'suites.log'
		& $godot --headless --path . res://tests/scenes/validate.tscn -- @suites 2>&1 | Tee-Object $log | Select-String -Pattern 'suite .* (PASS|FAIL)|FAIL' | ForEach-Object { $_.Line }
		$summary += "suites: exit $LASTEXITCODE"
	}
	$summary | Tee-Object (Join-Path $out 'summary.txt')
	Write-Host "Results: $out"
} finally {
	Pop-Location
}
