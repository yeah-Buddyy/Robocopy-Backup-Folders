### Edit here ###
# Your backup path
$roboCopyBackupPath = "E:\RoboCopyBackup"

# How many robocopy instances should run at the same time
$maxThreads = 5

$excludeFiles = @(
    "Thumbs.db"
)

$excludeDirectories = @(
    '$Recycle.Bin'
    "System Volume Information"
    "F:\Program Files\7-Zip"
    "F:\Program Files\Notepad++"
    "F:\Program Files\LibreOffice"
    "Windows"
    "Temp"
)

$sourceDirectories = @(
    "$env:systemdrive\Users\$env:username" # C:\Users\Admin
    "D:\MyFolderIwantToBackup"
    "C:\Program Files"
)

function Get-DriveLetter {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Validate the path format
    if ($Path -match '^[A-Za-z]:\\') {
        # Extract the drive letter
        $driveLetter = ($Path -split ':')[0]
        return $driveLetter
    } else {
        throw "Invalid path format. The path must start with a drive letter followed by a colon and a backslash (e.g., C:\)."
    }
}

try {
    $driveLetter = Get-DriveLetter -Path $roboCopyBackupPath
    Write-Output "Drive letter for '$roboCopyBackupPath' is '$driveLetter'"
} catch {
    Write-Output "Error processing '$roboCopyBackupPath': $_"
    pause
    exit
}

# Remove duplicates
$excludeFiles = $excludeFiles | Select-Object -Unique

# Remove duplicates
$excludeDirectories = $excludeDirectories | Select-Object -Unique

# Remove duplicates
$sourceDirectories = $sourceDirectories | Select-Object -Unique

# Create an array to store formatted strings
$quotedFiles = @()

# Format each entry in double quotes and add to the array
foreach ($file in $excludeFiles) {
    $quotedFiles += '"' + $file + '"'
}

# Join all formatted strings into a single line separated by space and output them
$singleLineFiles = $quotedFiles -join ' '

# Create an array to store formatted strings
$quotedDirectories = @()

# Format each entry in double quotes and add to the array
foreach ($dir in $excludeDirectories) {
    $quotedDirectories += '"' + $dir + '"'
}

# Join all formatted strings into a single line separated by space and output them
$singleLineDirectories = $quotedDirectories -join ' '

# Get the current date and time formatted as 'yyyy-MM-dd_HH-mm-ss'
$dateString = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Define the path where you want to create the folder
$parentPath = Join-Path -Path $PSScriptRoot -ChildPath "Robocopy-logs"

# Combine the parent path and date string to form the full path
$logFolder = Join-Path -Path $parentPath -ChildPath $dateString

If(!(test-path -PathType container $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force
}

# Define blacklist of drive roots
$blacklist = @('A:\', 'B:\', 'C:\', 'D:\', 'E:\', 'F:\', 'G:\', 'H:\', 'I:\', 'J:\', 
               'K:\', 'L:\', 'M:\', 'N:\', 'O:\', 'P:\', 'Q:\', 'R:\', 'S:\', 'T:\', 
               'U:\', 'V:\', 'W:\', 'X:\', 'Y:\', 'Z:\')

# Function to check if a path exactly matches any blacklist drive root
function IsPathInBlacklist([string]$path) {
    # Normalize the path to ensure consistent format
    $normalizedPath = $path.TrimEnd('\') + '\'

    # Check if the path exactly matches any of the blacklist roots
    foreach ($root in $blacklist) {
        if ($normalizedPath -eq $root) {
            return $true
        }
    }

    return $false
}

foreach ($path in $sourceDirectories) {
    if (IsPathInBlacklist $path) {
        # Write-Output "$path exactly matches a blacklist drive root."
        Write-Output "Backup a whole drive is not supported, must be a folder"
        pause
        exit
    } else {
        # Write-Output "$path does not exactly match a blacklist drive root."
    }
}

foreach ($path in $sourceDirectories) {
    if (Test-Path -Path $path -PathType Container) {
        # It's a directory
        # Write-Output "Processing directory: $path"
    }
    elseif (Test-Path -Path $path -PathType Leaf) {
        # It's a file
        Write-Output "Backup a single file is not supported."
        pause
        exit
    }
    else {
        Write-Output "Path '$path' does not exist or is not accessible."
        pause
        exit
    }
}

$monitorScriptContent = @'
param (
    [int]$MainScriptProcessId
)

# Monitor the main script process
try {
    $mainScriptProcess = Get-Process -Id $MainScriptProcessId -ErrorAction Stop
    while ($true) {
        Start-Sleep -Seconds 5
        if ($mainScriptProcess.HasExited) {
            Write-Output "Main script process has terminated. Terminating all robocopy.exe processes..."
            Get-Process robocopy -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
            break
        }
    }
} catch {
    Write-Output "Main script process not found or already terminated."
    Get-Process robocopy -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
}

exit
'@

# Save the monitor script to a temporary file
$tempFolder = [System.IO.Path]::GetTempPath()
$monitorScriptPath = [System.IO.Path]::Combine($tempFolder, "monitor.ps1")
Set-Content -Path $monitorScriptPath -Value $monitorScriptContent -Force

# Start the monitor script
$mainScriptProcessId = $PID
if (Test-Path "$monitorScriptPath" -PathType Leaf) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -NoLogo -ExecutionPolicy Bypass -File `"$monitorScriptPath`" -MainScriptProcessId $mainScriptProcessId" -WindowStyle Hidden
}

# Check if the drive letter exists
$driveExists = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue

if ($driveExists) {
    Write-Output "Drive $driveLetter exists."

    # create backup folder if not exists
    If(!(test-path -PathType container $roboCopyBackupPath)) {
        New-Item -ItemType Directory -Path $roboCopyBackupPath -Force
    }

    $jobs = @()
    $totalJobs = $sourceDirectories.Count
    $completedJobs = 0
    $maxConcurrentJobs = $maxThreads

    # Start multiple robocopy processes as background jobs with a limit of $maxConcurrentJobs at a time
    foreach ($source in $sourceDirectories) {
        while (($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $maxConcurrentJobs) {
            Start-Sleep -Seconds 1
        }

        # Remove the drive letter and colon (e.g., C:\) from the source path
        $cleanPath = $source -creplace '^[A-Za-z]:\\', ''

        # Get the drive letter part of the source path (e.g., C:\)
        $driveLetter = [System.IO.Path]::GetPathRoot($source)
        # Remove the colon and backslash from the drive letter (e.g., C)
        $trimmedString = $driveLetter.Trim(':\\')

        # Replace backslashes in the cleaned path with hyphens (e.g., users\test\hello -> users-test-hello)
        $newPath = $cleanPath -replace '\\', '-'

        # Combine the log folder path and the modified path to create the log file name
        # e.g., "C:\LogFolder\C-users-test-hello.log"
        $logName = Join-Path -Path $logFolder -ChildPath $trimmedString"-"$newPath".log"
        # Add double quotes around the log file name to handle paths with spaces
        $quotedLogName = '"' + $logName + '"'

        # Combine the backup path and the cleaned source path to create the destination path
        # e.g., "C:\BackupPath\C\users\test\hello"
        $destination = Join-Path -Path $roboCopyBackupPath -ChildPath $trimmedString"\"$cleanPath

        $job = Start-Job -ScriptBlock {
            param ($src, $dest, $excFile, $excDirectorie, $logPath)
            # /XA:SH to exclude hidden and system files
            $process = Start-Process -FilePath "robocopy.exe" -ArgumentList "`"$src`" `"$dest`" /E /DCOPY:DAT /COPY:DAT /MT:16 /R:0 /W:0 /NFL /NDL /NP /V /XF $excFile /XD $excDirectorie /TEE /UNILOG+:$logPath" -Wait -PassThru -WindowStyle Hidden
            return $process.ExitCode
        } -ArgumentList $source, $destination, $singleLineFiles, $singleLineDirectories, $quotedLogName

        $jobs += $job
    }

    # Monitor progress and wait for all jobs to complete
    while (($jobs | Where-Object { $_.State -ne 'Completed' }).Count -gt 0) {
        $completedJobs = ($jobs | Where-Object { $_.State -eq 'Completed' }).Count
        $percentComplete = ($completedJobs / $totalJobs) * 100
        Write-Progress -Activity "Running Robocopy" -Status "$completedJobs of $totalJobs jobs completed." -PercentComplete $percentComplete

        Start-Sleep -Seconds 1
    }

    # Collect results and clean up jobs
    foreach ($job in $jobs) {
        $jobResult = Receive-Job -Job $job -Wait
        $exitCode = $jobResult

        # Output the exit code
        if ($exitCode -eq 0) {
            Write-Output "No files were copied. No failure was met. No files were mismatched. The files already exist in the destination directory; so the copy operation was skipped."
        }
        elseif ($exitCode -eq 1) {
            Write-Output "All files were copied successfully."
        } else {
            Write-Output "Exit code is $exitCode. See here for more information https://learn.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility"
            Write-Output "Check your robocopy log --> $logFolder"
        }

        # Remove the job
        Remove-Job -Job $job
    }

    # Final progress bar update
    Write-Progress -Activity "Running Robocopy" -Status "All jobs completed." -PercentComplete 100 -Completed
} else {
    Write-Output "Drive $driveLetter does not exist."
    pause
    exit
}

pause
exit
