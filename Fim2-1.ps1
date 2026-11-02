# ============================================================
# PowerShell File Integrity Monitoring (FIM) v2
# Author: Joseph Minton
# Hashing Algorithm: SHA-512
# ============================================================


# ============================================================
# 1. CONFIGURATION
# ============================================================

$projectPath = Join-Path $PSScriptRoot "PowerShell-Integrity-FIM-main"

$baselinePath = Join-Path $projectPath "baseline.csv"
$logPath = Join-Path $projectPath "fim_events.csv"
$filesPath = Join-Path $projectPath "Files"

$pollingInterval = 1


# ============================================================
# 2. HELPER FUNCTIONS
# ============================================================

# Calculate SHA-512 hash for a specified file.

function Get-FileHashValue {

    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    Get-FileHash -LiteralPath $FilePath -Algorithm SHA512 -ErrorAction Stop |
        Select-Object -ExpandProperty Hash
}


# Retrieve files from the monitored directory.
# Recursive scanning includes nested directories.

function Get-MonitoredFiles {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Monitoring directory does not exist: $Path"
    }

    @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop)
}


# Display the main menu and normalize user input.

function Show-Menu {

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "       POWERSHELL FILE INTEGRITY MONITOR" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "A) Create a new file integrity baseline"
    Write-Host "B) Begin continuous file monitoring"
    Write-Host "Q) Quit"
    Write-Host ""

    $response = Read-Host "Select an option (A/B/Q)"

    return $response.Trim().ToUpperInvariant()
}


# ============================================================
# 3. BASELINE MANAGEMENT
# ============================================================

# Generate a fresh baseline containing file paths and SHA-512 hashes.

function New-FileBaseline {

    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$BaselineFile
    )

    Write-Host ""
    Write-Host "Generating file integrity baseline..." -ForegroundColor Cyan

    $files = @(Get-MonitoredFiles -Path $Directory)

    $baselineEntries = @()

    foreach ($file in $files) {

        try {

            $hash = Get-FileHashValue -FilePath $file.FullName

            $baselineEntries += [PSCustomObject]@{
                FilePath = $file.FullName
                Hash     = $hash
            }

        }
        catch {

            throw "Unable to hash file '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    # Write to a temporary file before replacing the existing baseline.

    $tempPath = "$BaselineFile.tmp"

    try {

        if ($baselineEntries.Count -gt 0) {

            $baselineEntries |
                Export-Csv -LiteralPath $tempPath -NoTypeInformation -Encoding UTF8

        }
        else {

            "FilePath,Hash" | Set-Content -LiteralPath $tempPath -Encoding UTF8
        }

        Move-Item -LiteralPath $tempPath -Destination $BaselineFile -Force -ErrorAction Stop

    }
    catch {

        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        throw "Baseline creation failed: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Baseline successfully created!" -ForegroundColor Green
    Write-Host "Files recorded: $($baselineEntries.Count)" -ForegroundColor Green
    Write-Host "Location: $BaselineFile" -ForegroundColor Gray
    Write-Host ""
}


# Load and validate an existing baseline.

function Import-FileBaseline {

    param(
        [Parameter(Mandatory)]
        [string]$BaselineFile
    )

    if (-not (Test-Path -LiteralPath $BaselineFile -PathType Leaf)) {

        throw "Baseline file not found. Create a baseline before monitoring."
    }

    $baseline = @{}

    try {

        $entries = @(Import-Csv -LiteralPath $BaselineFile -ErrorAction Stop)

        foreach ($entry in $entries) {

            $path = $entry.FilePath
            $hash = $entry.Hash

            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Invalid baseline entry: missing file path."
            }

            if ($hash -notmatch '^[A-Fa-f0-9]{128}$') {
                throw "Invalid SHA-512 hash found for: $path"
            }

            if ($baseline.ContainsKey($path)) {
                throw "Duplicate file path found in baseline: $path"
            }

            $baseline[$path] = $hash
        }

    }
    catch {

        throw "Unable to load baseline: $($_.Exception.Message)"
    }

    Write-Host "Baseline loaded successfully." -ForegroundColor Green
    Write-Host "Files in baseline: $($baseline.Count)" -ForegroundColor Gray

    return $baseline
}


# ============================================================
# 4. SECURITY EVENT LOGGING
# ============================================================

# Display security events and append them to a CSV log.

function Write-FIMEvent {

    param(
        [Parameter(Mandatory)]
        [string]$EventType,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [string]$ExpectedHash = "",

        [string]$CurrentHash = ""
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $event = [PSCustomObject]@{
        Timestamp    = $timestamp
        Event        = $EventType
        FilePath     = $FilePath
        ExpectedHash = $ExpectedHash
        CurrentHash  = $CurrentHash
    }

    switch ($EventType) {

        "CREATED" {
            Write-Host "[$timestamp] NEW FILE: $FilePath" -ForegroundColor Green
        }

        "MODIFIED" {
            Write-Host "[$timestamp] FILE MODIFIED: $FilePath" -ForegroundColor Red
        }

        "DELETED" {
            Write-Host "[$timestamp] FILE DELETED: $FilePath" -ForegroundColor DarkRed
        }

        "RESTORED" {
            Write-Host "[$timestamp] FILE RESTORED: $FilePath" -ForegroundColor Cyan
        }
    }

    try {

        if (Test-Path -LiteralPath $logPath) {

            $event | Export-Csv -LiteralPath $logPath -Append -NoTypeInformation -Encoding UTF8
        }
        else {

            $event | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8
        }

    }
    catch {

        Write-Warning "Unable to write security event to log: $($_.Exception.Message)"
    }
}


# ============================================================
# 5. FILE INTEGRITY COMPARISON
# ============================================================

# Compare the current file state against the trusted baseline
# and the previously observed state.

function Compare-FileIntegrity {

    param(
        [Parameter(Mandatory)]
        [hashtable]$Baseline,

        [Parameter(Mandatory)]
        [hashtable]$PreviousState,

        [Parameter(Mandatory)]
        [hashtable]$CurrentState
    )

    # Check files currently present in the monitored directory.

    foreach ($path in @($CurrentState.Keys)) {

        $currentHash = $CurrentState[$path]

        $existsInBaseline = $Baseline.ContainsKey($path)
        $existsPreviously = $PreviousState.ContainsKey($path)

        if (-not $existsInBaseline) {

            if (-not $existsPreviously) {

                Write-FIMEvent `
                    -EventType "CREATED" `
                    -FilePath $path `
                    -CurrentHash $currentHash
            }
            elseif ($PreviousState[$path] -ne $currentHash) {

                Write-FIMEvent `
                    -EventType "MODIFIED" `
                    -FilePath $path `
                    -CurrentHash $currentHash `
                    -ExpectedHash ""
            }

        }
        else {

            $baselineHash = $Baseline[$path]

            if ($currentHash -eq $baselineHash) {

                if (-not $existsPreviously -or
                    $PreviousState[$path] -ne $currentHash) {

                    Write-FIMEvent `
                        -EventType "RESTORED" `
                        -FilePath $path `
                        -ExpectedHash $baselineHash `
                        -CurrentHash $currentHash
                }

            }
            elseif (-not $existsPreviously -or
                    $PreviousState[$path] -ne $currentHash) {

                Write-FIMEvent `
                    -EventType "MODIFIED" `
                    -FilePath $path `
                    -ExpectedHash $baselineHash `
                    -CurrentHash $currentHash
            }
        }
    }

    # Check whether previously observed files have disappeared.

    foreach ($path in @($PreviousState.Keys)) {

        if (-not $CurrentState.ContainsKey($path)) {

            Write-FIMEvent `
                -EventType "DELETED" `
                -FilePath $path `
                -ExpectedHash $(if ($Baseline.ContainsKey($path)) {
                    $Baseline[$path]
                } else {
                    ""
                })
        }
    }
}


# ============================================================
# 6. CONTINUOUS MONITORING ENGINE
# ============================================================

function Start-FileMonitoring {

    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$BaselineFile
    )

    # Load the original trusted baseline.

    $baseline = Import-FileBaseline -BaselineFile $BaselineFile

    # Initialize previous state using the original baseline.

    $previousState = @{}

    foreach ($path in $baseline.Keys) {
        $previousState[$path] = $baseline[$path]
    }

    Write-Host ""
    Write-Host "File monitoring started." -ForegroundColor Green
    Write-Host "Monitoring directory: $Directory" -ForegroundColor Gray
    Write-Host "Polling interval: $pollingInterval second(s)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Press CTRL+C to stop monitoring." -ForegroundColor Yellow
    Write-Host ""

    # Begin continuous monitoring.

    while ($true) {

        Start-Sleep -Seconds $pollingInterval

        try {

            $files = @(Get-MonitoredFiles -Path $Directory)

            $currentState = @{}
            $failedPaths = @{}

            # Calculate hashes for currently accessible files.

            foreach ($file in $files) {

                try {

                    $hash = Get-FileHashValue -FilePath $file.FullName

                    $currentState[$file.FullName] = $hash

                }
                catch {

                    Write-Warning "Unable to hash $($file.FullName): $($_.Exception.Message)"

                    $failedPaths[$file.FullName] = $true
                }
            }

            # Preserve the previous state of files that could not be hashed.
            # This prevents temporary access errors from creating false deletion alerts.

            foreach ($path in $failedPaths.Keys) {

                if ($previousState.ContainsKey($path)) {
                    $currentState[$path] = $previousState[$path]
                }
            }

            # Compare the previous and current file states.

            Compare-FileIntegrity `
                -Baseline $baseline `
                -PreviousState $previousState `
                -CurrentState $currentState

            # Update the observed state without modifying the trusted baseline.

            $previousState = $currentState

        }
        catch {

            Write-Warning "Monitoring scan failed: $($_.Exception.Message)"
            Write-Warning "The previous monitoring state has been preserved."
        }
    }
}


# ============================================================
# 7. MAIN PROGRAM
# ============================================================

try {

    # Verify that the monitored directory exists.

    if (-not (Test-Path -LiteralPath $filesPath -PathType Container)) {

        throw "The Files directory does not exist: $filesPath"
    }

    # Present the interactive menu.

    $response = Show-Menu

    switch ($response) {

        "A" {

            New-FileBaseline `
                -Directory $filesPath `
                -BaselineFile $baselinePath
        }

        "B" {

            Start-FileMonitoring `
                -Directory $filesPath `
                -BaselineFile $baselinePath
        }

        "Q" {

            Write-Host "Exiting FIM..." -ForegroundColor Gray
            return
        }

        default {

            Write-Warning "Invalid selection. Please enter A, B, or Q."
        }
    }

}
catch {

    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}
