<#
.SYNOPSIS
    Native Windows PowerShell batch runner for Last Route playtest bots.

.DESCRIPTION
    Runs headless Godot playtest bot batches on Windows without requiring
    Python or Bash. Adheres to the single-Godot-process rule by checking for active
    Godot processes before each step. Reads each resulting report.json and formats
    a Markdown summary table.

.PARAMETER Worktree
    Path to the Godot project worktree directory (default: current directory '.').

.PARAMETER GodotBin
    Path to Godot executable (default: auto-detected console exe in Original-Godot-Ref or PATH).

.PARAMETER Seeds
    Array of seed strings to run the scenario with (default: @('ALPHA', 'BETA', 'GAMMA')).

.PARAMETER Minutes
    Game minutes per survive/bot scenario run (default: 5).

.PARAMETER Scenario
    Playtest scenario to run for the seeds (default: 'survive').

.PARAMETER IncludeTour
    If specified, runs the 'menu_tour' scenario before running the seed batch.

.PARAMETER Game
    Game identifier to pass to --game (default: 'last_route').

.PARAMETER FixedFps
    Fixed physics fps for the headless runner (default: 60).

.PARAMETER OutDir
    Base directory where report outputs are written (default: '<Worktree>/.playtest').

.PARAMETER ExtraArgs
    Additional command-line arguments to append to user args after '--'.

.PARAMETER WaitTimeout
    Maximum seconds to wait if an existing Godot process is detected (default: 600).
    If set to 0, immediately aborts if any Godot process is active.

.PARAMETER DryRun
    If specified, prints the commands that would be executed without running them.

.EXAMPLE
    .\run_batch.ps1 -IncludeTour
    Runs menu_tour followed by survive on ALPHA, BETA, GAMMA (5 minutes each).

.EXAMPLE
    .\run_batch.ps1 -Seeds @('ALPHA') -Minutes 3
    Runs survive on seed ALPHA for 3 minutes.

.EXAMPLE
    .\run_batch.ps1 -IncludeTour -Seeds @()
    Runs only the menu_tour scenario.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Worktree = '.',

    [Parameter(Position = 1)]
    [string]$GodotBin = '',

    [Parameter(Position = 2)]
    [string[]]$Seeds = @('ALPHA', 'BETA', 'GAMMA'),

    [Parameter()]
    [int]$Minutes = 5,

    [Parameter()]
    [string]$Scenario = 'survive',

    [Parameter()]
    [switch]$IncludeTour,

    [Parameter()]
    [string]$Game = 'last_route',

    [Parameter()]
    [int]$FixedFps = 60,

    [Parameter()]
    [string]$OutDir = '',

    [Parameter()]
    [string]$ExtraArgs = '',

    [Parameter()]
    [int]$WaitTimeout = 600,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-WorktreePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = '.'
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        $full = [System.IO.Path]::GetFullPath($Path)
    } else {
        $full = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
    }
    $projectGodot = Join-Path $full 'project.godot'
    if (Test-Path -LiteralPath $projectGodot -PathType Leaf) {
        return $full
    }
    # If default '.' was used and not found in current working directory,
    # fall back to the script's enclosing worktree root ($PSScriptRoot/../..)
    if ($Path -eq '.' -and $PSScriptRoot) {
        $scriptWorktree = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $scriptGodot = Join-Path $scriptWorktree 'project.godot'
        if (Test-Path -LiteralPath $scriptGodot -PathType Leaf) {
            return $scriptWorktree
        }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "Worktree directory does not exist: $full"
    }
    throw "No 'project.godot' found in worktree: $full"
}

function Resolve-GodotBinary {
    param(
        [string]$SpecifiedBin,
        [string]$TargetWorktree
    )
    if (-not [string]::IsNullOrWhiteSpace($SpecifiedBin)) {
        if (Test-Path -LiteralPath $SpecifiedBin -PathType Leaf) {
            return (Resolve-Path -LiteralPath $SpecifiedBin).Path
        }
        throw "Specified Godot binary not found: $SpecifiedBin"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        if (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:GODOT_BIN).Path
        }
    }

    # Search for Original-Godot-Ref console exe from candidate search roots
    $searchRoots = @(
        $TargetWorktree,
        (Get-Location).Path,
        $PSScriptRoot,
        (Join-Path $PSScriptRoot "..\.."),
        (Join-Path $PSScriptRoot "..\..\.."),
        (Join-Path $TargetWorktree ".."),
        (Join-Path $TargetWorktree "..\..")
    )

    foreach ($root in $searchRoots) {
        if (-not $root) { continue }
        $candidateDir = Join-Path $root "Original-Godot-Ref\tools\godot"
        if (Test-Path -LiteralPath $candidateDir -PathType Container) {
            # Prefer console exe for clean stdout
            $consoleExe = Get-ChildItem -LiteralPath $candidateDir -Filter "*console*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($consoleExe) {
                return $consoleExe.FullName
            }
            $anyExe = Get-ChildItem -LiteralPath $candidateDir -Filter "*godot*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($anyExe) {
                return $anyExe.FullName
            }
        }
    }

    # Check PATH
    $fromPath = Get-Command godot4, godot -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "Could not locate Godot console executable in 'Original-Godot-Ref\tools\godot' or in PATH. Specify -GodotBin <path> or set `$env:GODOT_BIN."
}

function Wait-ForGodotIdle {
    param(
        [int]$TimeoutSeconds,
        [int]$CheckIntervalSeconds = 3
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $running = Get-Process -Name "Godot*" -ErrorAction SilentlyContinue
        if (-not $running) {
            return $true
        }
        $procSummary = ($running | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ", "
        if ($TimeoutSeconds -le 0) {
            Write-Warning "Single-Godot process rule: Godot process(es) already active: $procSummary."
            return $false
        }
        $elapsed = [int]$sw.Elapsed.TotalSeconds
        Write-Warning "Single-Godot process rule: Godot process(es) currently running: $procSummary. Waiting for idle... (${elapsed}s / ${TimeoutSeconds}s)"
        if ($elapsed -ge $TimeoutSeconds) {
            Write-Warning "Single-Godot process rule: timed out waiting for existing Godot process(es) to finish: $procSummary"
            return $false
        }
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
}

$resolvedWorktree = Resolve-WorktreePath -Path $Worktree
$resolvedGodot = Resolve-GodotBinary -SpecifiedBin $GodotBin -TargetWorktree $resolvedWorktree

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $baseOutDir = Join-Path $resolvedWorktree ".playtest"
} else {
    if ([System.IO.Path]::IsPathRooted($OutDir)) {
        $baseOutDir = [System.IO.Path]::GetFullPath($OutDir)
    } else {
        $baseOutDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutDir))
    }
}

# Construct the plan of steps
$steps = @()

if ($IncludeTour) {
    $steps += [PSCustomObject]@{
        Name     = "menu-tour"
        Scenario = "menu_tour"
        Seed     = $null
        Minutes  = $null
    }
}

if ($Seeds -and $Seeds.Count -gt 0) {
    foreach ($s in $Seeds) {
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $cleanSeed = $s.Trim()
        $steps += [PSCustomObject]@{
            Name     = "$Scenario-$cleanSeed"
            Scenario = $Scenario
            Seed     = $cleanSeed
            Minutes  = $Minutes
        }
    }
}

if ($steps.Count -eq 0) {
    Write-Warning "No playtest runs scheduled. Provide -Seeds or specify -IncludeTour."
    exit 0
}

Write-Host "Playtest batch: $($steps.Count) run(s) scheduled" -ForegroundColor Cyan
Write-Host "  Worktree: $resolvedWorktree"
Write-Host "  Godot:    $resolvedGodot"
Write-Host "  OutDir:   $baseOutDir"
Write-Host ""

$results = @()
$batchStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($step in $steps) {
    Write-Host "------------------------------------------------------------"
    Write-Host "Step: $($step.Name) [Scenario: $($step.Scenario)$(if ($step.Seed) { ", Seed: $($step.Seed)" })]" -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------"

    $stepOut = Join-Path $baseOutDir $step.Name
    $reportJsonPath = Join-Path $stepOut "report.json"
    if (-not $DryRun) {
        if (-not (Test-Path -LiteralPath $stepOut -PathType Container)) {
            New-Item -ItemType Directory -Path $stepOut -Force | Out-Null
        }
        if (Test-Path -LiteralPath $reportJsonPath -PathType Leaf) {
            Remove-Item -LiteralPath $reportJsonPath -Force
        }
    }

    # 1. Enforce single-Godot process rule before launching
    if (-not $DryRun) {
        $idle = Wait-ForGodotIdle -TimeoutSeconds $WaitTimeout
        if (-not $idle) {
            $results += [PSCustomObject]@{
                Scenario      = $step.Scenario
                Seed          = if ($step.Seed) { $step.Seed } else { "-" }
                Name          = $step.Name
                WallTime      = "-"
                Outcome       = "blocked"
                Deaths        = "-"
                Distance      = "-"
                ChunksVisited = "-"
                Errors        = "-"
                Result        = "BLOCKED"
                Failures      = @("Aborted: single-Godot process rule prevented execution (another Godot process was active).")
            }
            continue
        }
    }

    # 2. Build argument list
    $cmdArgs = @(
        "--headless",
        "--fixed-fps", "$FixedFps",
        "--path", $resolvedWorktree,
        "res://dev/playtest/playtest_runner.tscn",
        "--",
        "--playtest-runner",
        "--game=$Game",
        "--scenario=$($step.Scenario)",
        "--name=$($step.Name)",
        "--out=$stepOut"
    )

    if ($step.Seed) {
        $cmdArgs += "--seed=$($step.Seed)"
    }
    if ($step.Minutes) {
        $cmdArgs += "--minutes=$($step.Minutes)"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExtraArgs)) {
        $extraTokens = $ExtraArgs -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $cmdArgs += $extraTokens
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] & '$resolvedGodot' $($cmdArgs -join ' ')" -ForegroundColor DarkGray
        $results += [PSCustomObject]@{
            Scenario      = $step.Scenario
            Seed          = if ($step.Seed) { $step.Seed } else { "-" }
            Name          = $step.Name
            WallTime      = "dry-run"
            Outcome       = "dry_run"
            Deaths        = "-"
            Distance      = "-"
            ChunksVisited = "-"
            Errors        = "-"
            Result        = "DRY_RUN"
            Failures      = @()
        }
        continue
    }

    # 3. Execute
    $stepStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $resolvedGodot @cmdArgs
    $exitCode = $LASTEXITCODE
    $stepStopwatch.Stop()
    $stepWall = [math]::Round($stepStopwatch.Elapsed.TotalSeconds, 1)

    # Allow filesystem flush
    Start-Sleep -Milliseconds 300

    # 4. Parse report.json
    if (Test-Path -LiteralPath $reportJsonPath -PathType Leaf) {
        try {
            $rawText = Get-Content -LiteralPath $reportJsonPath -Raw -Encoding UTF8
            $rep = $rawText | ConvertFrom-Json

            $repScenario = if ($rep.scenario) { "$($rep.scenario)" } else { $step.Scenario }
            $repSeed = if ($step.Scenario -eq 'menu_tour') { '-' } elseif ($rep.seed) { "$($rep.seed)" } else { if ($step.Seed) { $step.Seed } else { "-" } }
            $repWall = if ($null -ne $rep.wall_seconds) { "{0}s" -f [math]::Round([double]$rep.wall_seconds, 1) } else { "{0}s" -f $stepWall }
            $repOutcome = if ($rep.outcome) { "$($rep.outcome)" } else { "-" }

            $repDeaths = "-"
            $repDist = "-"
            $repChunks = "-"
            if ($rep.bot) {
                if ($null -ne $rep.bot.deaths) { $repDeaths = "$($rep.bot.deaths)" }
                if ($null -ne $rep.bot.distance_m) { $repDist = "{0} m" -f [math]::Round([double]$rep.bot.distance_m, 1) }
                if ($null -ne $rep.bot.chunks_visited) { $repChunks = "$($rep.bot.chunks_visited)" }
            }

            $repErrors = "0"
            if ($rep.log -and ($null -ne $rep.log.errors)) {
                $repErrors = "$($rep.log.errors)"
            }

            $repResult = if ($rep.pass -eq $true) { "PASS" } else { "FAIL" }

            $failures = @()
            if ($rep.failures) {
                foreach ($f in $rep.failures) { $failures += "$f" }
            }
            if ($rep.scenario_failure) {
                $failures += "$($rep.scenario_failure)"
            }

            $results += [PSCustomObject]@{
                Scenario      = $repScenario
                Seed          = $repSeed
                Name          = $step.Name
                WallTime      = $repWall
                Outcome       = $repOutcome
                Deaths        = $repDeaths
                Distance      = $repDist
                ChunksVisited = $repChunks
                Errors        = $repErrors
                Result        = $repResult
                Failures      = $failures
            }
        } catch {
            $results += [PSCustomObject]@{
                Scenario      = $step.Scenario
                Seed          = if ($step.Seed) { $step.Seed } else { "-" }
                Name          = $step.Name
                WallTime      = "{0}s" -f $stepWall
                Outcome       = "json_parse_error"
                Deaths        = "-"
                Distance      = "-"
                ChunksVisited = "-"
                Errors        = "-"
                Result        = "FAIL"
                Failures      = @("Failed to parse report.json: $($_.Exception.Message)")
            }
        }
    } else {
        $results += [PSCustomObject]@{
            Scenario      = $step.Scenario
            Seed          = if ($step.Seed) { $step.Seed } else { "-" }
            Name          = $step.Name
            WallTime      = "{0}s" -f $stepWall
            Outcome       = "no_report (exit $exitCode)"
            Deaths        = "-"
            Distance      = "-"
            ChunksVisited = "-"
            Errors        = "-"
            Result        = if ($exitCode -eq 0) { "PASS" } else { "CRASH" }
            Failures      = @("Process exited with code $exitCode; report.json was not generated at $reportJsonPath.")
        }
    }
}

$batchStopwatch.Stop()
$totalElapsed = [math]::Round($batchStopwatch.Elapsed.TotalSeconds, 1)

$allPassed = ($results.Count -gt 0) -and (-not ($results | Where-Object { $_.Result -ne 'PASS' -and $_.Result -ne 'DRY_RUN' }))

$bt = [char]96
$mdLines = @()
$mdLines += "# Playtest Batch Results: $Game"
$mdLines += ""
$mdLines += "- **Worktree:** $bt$resolvedWorktree$bt"
$mdLines += "- **Godot:** $bt$resolvedGodot$bt"
$mdLines += "- **Runs:** {0}, total wall time: {1}s" -f $results.Count, $totalElapsed
$mdLines += "- **Verdict:** **$(if ($allPassed) { 'ALL PASSED' } else { 'FAILURES DETECTED' })**"
$mdLines += ""
$mdLines += "| Scenario | Seed | Wall Time | Outcome | Deaths | Distance | Chunks Visited | Errors | Result |"
$mdLines += "|---|---|---|---|---|---|---|---|---|"

foreach ($r in $results) {
    $mdLines += "| $($r.Scenario) | $($r.Seed) | $($r.WallTime) | $($r.Outcome) | $($r.Deaths) | $($r.Distance) | $($r.ChunksVisited) | $($r.Errors) | **$($r.Result)** |"
}

$failedRuns = $results | Where-Object { $_.Failures -and $_.Failures.Count -gt 0 }
if ($failedRuns) {
    $mdLines += ""
    $mdLines += "### Failures & Notes"
    foreach ($fr in $failedRuns) {
        $mdLines += "- **$($fr.Name)** ($($fr.Result)):"
        foreach ($msg in $fr.Failures) {
            $mdLines += "  - $msg"
        }
    }
}

$markdown = $mdLines -join "`n"

# Write summary.md to OutDir
if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $baseOutDir -PathType Container)) {
        New-Item -ItemType Directory -Path $baseOutDir -Force | Out-Null
    }
    $summaryFile = Join-Path $baseOutDir "summary.md"
    $markdown | Set-Content -LiteralPath $summaryFile -Encoding UTF8
}

Write-Host ""
Write-Host $markdown
Write-Host ""
if (-not $DryRun) {
    Write-Host "Summary written to: $summaryFile" -ForegroundColor Cyan
}

if ($DryRun) {
    exit 0
}

if ($allPassed) {
    exit 0
} else {
    exit 1
}
