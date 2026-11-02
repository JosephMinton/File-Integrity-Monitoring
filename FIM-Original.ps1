# File Integrity Monitor (FIM)
# This script creates a SHA-512 baseline for files in the Files folder and
# continuously checks those files for changes, additions, and deletions.

# Ask the user which operation to perform: create a baseline or monitor files.
Write-Host ""
Write-Host "What would you like to do?"
Write-Host ""
Write-Host "    A) Collect new Baseline?"
Write-Host "    B) Begin monitoring files with saved Baseline?"
Write-Host ""
$response = Read-Host -Prompt "Please enter 'A' or 'B'"
Write-Host ""

# Calculate a SHA-512 hash for the file supplied to the function.
# Get-FileHash returns an object containing the file path and its hash value.
Function Calculate-File-Hash($filepath) {
    $filehash = Get-FileHash -Path $filepath -Algorithm SHA512
    return $filehash
}

# Remove an existing baseline before creating a replacement.
# This prevents old entries from being left behind when a new baseline is generated.
Function Erase-Baseline-If-Already-Exists() {
    $baselineExists = Test-Path -Path .\baseline.txt

    if ($baselineExists) {
        # Delete the existing baseline file.
        Remove-Item -Path .\baseline.txt
    }
}

if ($response -eq "A".ToUpper()) {
    # BASELINE CREATION
    # Remove any previous baseline so the new baseline represents the current files.
    Erase-Baseline-If-Already-Exists

    # Retrieve the files located in the directory being monitored.
    # This command scans the Files folder's top level, not its subdirectories.
    $files = Get-ChildItem -Path .\Files

    # Process each file individually: calculate its SHA-512 hash, then
    # append the file path and hash to baseline.txt, separated by a pipe.
    foreach ($f in $files) {
        $hash = Calculate-File-Hash $f.FullName
        "$($hash.Path)|$($hash.Hash)" | Out-File -FilePath .\baseline.txt -Append
    }

}

elseif ($response -eq "B".ToUpper()) {
    # BASELINE IMPORT
    # Create a hashtable to store each baseline file path as a key and its
    # corresponding SHA-512 hash as the value. This allows quick lookups later.
    $fileHashDictionary = @{}

    # Read the saved baseline one line at a time. Each line is expected to
    # contain a file path and hash separated by the pipe character.
    $filePathsAndHashes = Get-Content -Path .\baseline.txt

    # Split each baseline entry into its path and hash, then add that pair
    # to the hashtable for comparison during monitoring.
    foreach ($f in $filePathsAndHashes) {
         $fileHashDictionary.add($f.Split("|")[0],$f.Split("|")[1])
    }

    # CONTINUOUS MONITORING
    # Keep checking the monitored directory until the script is stopped.
    while ($true) {
        # Pause between scans to avoid running the checks continuously at full speed.
        Start-Sleep -Seconds 1

        # Get the current files in the monitored folder for this scan.
        $files = Get-ChildItem -Path .\Files

        # Check each current file against the imported baseline.
        foreach ($f in $files) {
            # Calculate the current SHA-512 hash for this file.
            $hash = Calculate-File-Hash $f.FullName

            # NEW FILE DETECTION
            # If this file path is not a key in the baseline hashtable, it was
            # not present when the baseline was created.
            if ($fileHashDictionary[$hash.Path] -eq $null) {
                # Report that a file has appeared since the baseline was created.
                Write-Host "$($hash.Path) has been created!" -ForegroundColor Green
            }
            else {
                # EXISTING FILE COMPARISON
                # Compare the current hash with the saved hash for this file path.
                if ($fileHashDictionary[$hash.Path] -eq $hash.Hash) {
                    # Matching hashes indicate that the file contents are unchanged.
                }
                else {
                    # Different hashes indicate that the file contents have changed.
                    Write-Host "$($hash.Path) has changed!!!" -ForegroundColor Yellow
                }
            }
        }

        # DELETED FILE DETECTION
        # Check every path recorded in the baseline. If the path no longer exists,
        # the corresponding baseline file has been deleted or moved.
        foreach ($key in $fileHashDictionary.Keys) {
            $baselineFileStillExists = Test-Path -Path $key
            if (-Not $baselineFileStillExists) {
                # Report that a file from the original baseline is no longer present.
                Write-Host "$($key) has been deleted!" -ForegroundColor DarkRed -BackgroundColor Gray
            }
        }
    }
}
