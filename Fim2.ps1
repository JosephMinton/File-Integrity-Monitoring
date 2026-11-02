# ============================================================

# PowerShell File Integrity Monitoring (FIM) v2
# Author: Joseph Minton
# Hashing Algorithm: SHA-512

# ============================================================

# ============================================================

# 1. CONFIGURATION

# ============================================================
# $PSScriptRoot is the directory containing this script.
# The projectPath line points to the existing project folder that contains Files.
# Keep this folder name in sync with your actual directory structure.
$projectPath = Join-Path $PSScriptRoot "PowerShell-Integrity-FIM-main"
# baseline.csv stores the original file paths and their trusted SHA-512 hashes.
$baselinePath = Join-Path $projectPath "baseline.csv"
# fim_events.csv is the activity log. New events are appended while monitoring.
$logPath = Join-Path $projectPath "fim_events.csv"
# Files is the directory being monitored, including all nested subdirectories.
$filesPath = Join-Path $projectPath "Files"
# Number of seconds to wait between monitoring scans.
# A shorter interval detects changes sooner but makes the script scan more often.
$pollingInterval = 1

# ============================================================

# 2. HELPER FUNCTIONS

# ============================================================
# Calculate SHA-512 hash for a specified file.

# FUNCTION: Get-FileHashValue
# Purpose: Calculate and return the SHA-512 fingerprint of one file.
# FilePath is a parameter, so the same function can be reused for different files.
function Get-FileHashValue {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    # Get-FileHash reads the file and calculates its SHA-512 digest.
    # LiteralPath treats characters such as [ and ] as ordinary path characters.
    # ErrorAction Stop turns a hashing error into a catchable terminating error.
    # Select-Object extracts only the Hash property instead of returning the full object.
    Get-FileHash -LiteralPath $FilePath -Algorithm SHA512 -ErrorAction Stop |
        Select-Object -ExpandProperty Hash
}
# Retrieve files from the monitored directory.
# Recursive scanning includes nested directories.

# FUNCTION: Get-MonitoredFiles
# Purpose: Return all files under the monitoring directory.
# The -Recurse switch includes files in child folders and deeper nested folders.
function Get-MonitoredFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    # Confirm that the supplied path exists and is a directory (Container).
    # The ! / -not operator reverses the result: throw an error if it is missing.
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Monitoring directory does not exist: $Path"
    }
    # Get-ChildItem lists directory contents.
    # -File excludes folders, -Recurse searches nested folders, and -Force
    # includes hidden/system items where permissions allow.
    # @() ensures the result is an array, even when zero or one file is found.
    @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop)
}
# Display the main menu and normalize user input.

# FUNCTION: Show-Menu
# Purpose: Display the options and return the user's selection.
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
    # Trim removes accidental spaces; ToUpperInvariant makes a, b, and q
    # behave the same as A, B, and Q. Return sends the normalized value back.
    return $response.Trim().ToUpperInvariant()
}

# ============================================================

# 3. BASELINE MANAGEMENT

# ============================================================
# Generate a fresh baseline containing file paths and SHA-512 hashes.

# FUNCTION: New-FileBaseline
# Purpose: Build a new reference list of every monitored file and its SHA-512 hash.
function New-FileBaseline {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,
        [Parameter(Mandatory)]
        [string]$BaselineFile
    )
    Write-Host ""
    Write-Host "Generating file integrity baseline..." -ForegroundColor Cyan
    # Get the current file list. This scan is recursive.
    $files = @(Get-MonitoredFiles -Path $Directory)
    # This array will hold one PowerShell object per file.
    # Each object contains the file path and its calculated hash.
    $baselineEntries = @()
    foreach ($file in $files) {
        try {
            # FullName is the complete path to the file.
            # Calculate-File-HashValue returns the SHA-512 hash string.
            $hash = Get-FileHashValue -FilePath $file.FullName
            # PSCustomObject creates a record with named properties.
            # Export-Csv later turns these properties into CSV columns.
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
    # Write to a temporary file first. This reduces the chance of leaving
    # a partially written baseline if the export fails.
    $tempPath = "$BaselineFile.tmp"
    try {
        if ($baselineEntries.Count -gt 0) {
            # Export the records as CSV with column headers.
            $baselineEntries |
                Export-Csv -LiteralPath $tempPath -NoTypeInformation -Encoding UTF8
        }
        else {
            # If the directory is empty, still create a CSV with the expected headers.
            "FilePath,Hash" | Set-Content -LiteralPath $tempPath -Encoding UTF8
        }
        # Replace the old baseline only after the temporary file was written.
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

# FUNCTION: Import-FileBaseline
# Purpose: Load the CSV baseline and check that its records look valid.
# Returns a hashtable: file path -> expected SHA-512 hash.
function Import-FileBaseline {
    param(
        [Parameter(Mandatory)]
        [string]$BaselineFile
    )
    if (-not (Test-Path -LiteralPath $BaselineFile -PathType Leaf)) {
        throw "Baseline file not found. Create a baseline before monitoring."
    }
    # A hashtable stores key/value pairs. Here the full file path is the key
    # and its expected SHA-512 hash is the value.
    $baseline = @{}
    try {
        # Import-Csv converts each CSV row into an object with named properties.
        $entries = @(Import-Csv -LiteralPath $BaselineFile -ErrorAction Stop)
        foreach ($entry in $entries) {
            $path = $entry.FilePath
            $hash = $entry.Hash
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Invalid baseline entry: missing file path."
            }
            # A SHA-512 digest is 512 bits, represented by 128 hexadecimal characters.
            # This checks the shape of the hash, not whether the baseline is authentic.
            if ($hash -notmatch '^[A-Fa-f0-9]{128}$') {
                throw "Invalid SHA-512 hash found for: $path"
            }
            if ($baseline.ContainsKey($path)) {
                throw "Duplicate file path found in baseline: $path"
            }
            # Add this path/hash pair to the lookup table.
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

# FUNCTION: Write-FIMEvent
# Purpose: Display one detected event and record it in the CSV event log.
function Write-FIMEvent {
    param(
        [Parameter(Mandatory)]
        [string]$EventType,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string]$ExpectedHash = "",
        [string]$CurrentHash = ""
    )
    # Record the time the event was detected.
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Build one structured event record. Empty hash fields are allowed when
    # a hash is not applicable, such as a newly created file.
    $event = [PSCustomObject]@{
        Timestamp    = $timestamp
        Event        = $EventType
        FilePath     = $FilePath
        ExpectedHash = $ExpectedHash
        CurrentHash  = $CurrentHash
    }
    # Select a console message and color based on the event category.
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
        # If the log already exists, append a row. Otherwise create it with headers.
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

# FUNCTION: Compare-FileIntegrity
# Purpose: Compare the current scan with both:
#   1. Baseline: the original reference state, which is not changed during monitoring.
#   2. PreviousState: the last successfully observed state, used to suppress repeat alerts.
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
    # First examine every file found in the current scan.
    foreach ($path in @($CurrentState.Keys)) {
        $currentHash = $CurrentState[$path]
        # ContainsKey checks whether this path is present in each hashtable.
        $existsInBaseline = $Baseline.ContainsKey($path)
        $existsPreviously = $PreviousState.ContainsKey($path)
        # A path absent from the baseline is a file created after baseline generation.
        if (-not $existsInBaseline) {
            # If it was also absent from the previous scan, this is a new creation event.
            if (-not $existsPreviously) {
                Write-FIMEvent `
                    -EventType "CREATED" `
                    -FilePath $path `
                    -CurrentHash $currentHash
            }
            # If the file was already seen but its hash changed since the last scan,
            # report a modification. This also works for files created after the baseline.
            elseif ($PreviousState[$path] -ne $currentHash) {
                Write-FIMEvent `
                    -EventType "MODIFIED" `
                    -FilePath $path `
                    -CurrentHash $currentHash `
                    -ExpectedHash ""
            }
        }
        else {
            # Retrieve the original expected hash for this baseline file.
            $baselineHash = $Baseline[$path]
            # If the current hash matches the original baseline, the file is in
            # its original content state. Report RESTORED only if the previous
            # observed state was different or the file had disappeared.
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
            # Otherwise, the file differs from its baseline. Report only when
            # it is first noticed in this state or its hash changed since last scan.
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
    # Next look for files that were present in the previous scan but are missing now.
    foreach ($path in @($PreviousState.Keys)) {
        # Missing from CurrentState means the file disappeared between scans.
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

# FUNCTION: Start-FileMonitoring
# Purpose: Run the repeated scan/hash/compare cycle until the user stops the script.
function Start-FileMonitoring {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,
        [Parameter(Mandatory)]
        [string]$BaselineFile
    )
# Load the original trusted baseline.
    # Load the original baseline once. This reference is kept unchanged
    # throughout the monitoring session.
    $baseline = Import-FileBaseline -BaselineFile $BaselineFile
# Initialize previous state using the original baseline.
    # PreviousState tracks what the script last observed.
    # It starts as a copy of the baseline so the first scan can detect missing
    # baseline files and changes that happened after baseline creation.
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
    # An infinite loop keeps monitoring until CTRL+C or the host stops execution.
    while ($true) {
        Start-Sleep -Seconds $pollingInterval
        try {
            $files = @(Get-MonitoredFiles -Path $Directory)
            # Build a fresh state table for this scan.
            # failedPaths tracks files that exist but could not be hashed this time.
            $currentState = @{}
            $failedPaths = @{}
# Calculate hashes for currently accessible files.
            foreach ($file in $files) {
                try {
                    $hash = Get-FileHashValue -FilePath $file.FullName
                    # Store the latest hash, keyed by the file's full path.
                    $currentState[$file.FullName] = $hash
                }
                catch {
                    Write-Warning "Unable to hash $($file.FullName): $($_.Exception.Message)"
                    $failedPaths[$file.FullName] = $true
                }
            }
# Preserve the previous state of files that could not be hashed.
# This prevents temporary access errors from creating false deletion alerts.
            # Do not treat a temporary access/hash error as a deletion.
            # If we knew the file's previous hash, carry that state forward for this scan.
            foreach ($path in $failedPaths.Keys) {
                if ($previousState.ContainsKey($path)) {
                    $currentState[$path] = $previousState[$path]
                }
            }
# Compare the previous and current file states.
            # Compare this scan against the original baseline and last scan.
            Compare-FileIntegrity `
                -Baseline $baseline `
                -PreviousState $previousState `
                -CurrentState $currentState
# Update the observed state without modifying the trusted baseline.
            # Save this scan as the previous state for the next loop.
            # Notice that the original baseline is NOT overwritten here.
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
# MAIN PROGRAM
# Check the target directory, show the menu, and call the selected operation.
try {
# Verify that the monitored directory exists.
    # Stop early with a clear error if the configured Files directory is missing.
    if (-not (Test-Path -LiteralPath $filesPath -PathType Container)) {
        throw "The Files directory does not exist: $filesPath"
    }
# Present the interactive menu.
    $response = Show-Menu
    # Run the function that matches the user's menu selection.
    switch ($response) {
        # A: create or replace the reference baseline.
        "A" {
            New-FileBaseline `
                -Directory $filesPath `
                -BaselineFile $baselinePath
        }
        # B: load the baseline and begin continuous monitoring.
        "B" {
            Start-FileMonitoring `
                -Directory $filesPath `
                -BaselineFile $baselinePath
        }
        # Q: exit without starting an operation.
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
