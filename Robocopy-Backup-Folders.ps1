# If you close the powershell script and robocopy is not finished yet, the started robocopy processes are still running in backround. You need to close them manually via taskmanager.

### Edit here ###
$usbDriveLetter = "E"
$roboCopyBackupPath = "E:\RoboCopyBackup"

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

function Remove-DriveLettersAndSubstring {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputString
    )

    # Define a regex pattern to match drive letters from A:\ to Z:\
    $drivePattern = '[A-Za-z]:\\'

    # Replace all occurrences of the drive letter pattern with an empty string
    $result = $InputString -creplace $drivePattern

    # Find the index of the first backslash (\) after removing drive letters
    $index = $result.IndexOf("\")
    
    if ($index -ge 0) {
        # Extract the substring before the first backslash
        $result = $result.Substring(0, $index)
    }

    return $result
}

# Check if the drive letter exists
$driveExists = Get-PSDrive -Name $usbDriveLetter -ErrorAction SilentlyContinue

if ($driveExists) {
    Write-Output "Drive $usbDriveLetter exists."

    # create backup folder if not exists
    If(!(test-path -PathType container $roboCopyBackupPath)) {
        New-Item -ItemType Directory -Path $roboCopyBackupPath -Force
    }

    $jobs = @()
    $totalJobs = $sourceDirectories.Count
    $completedJobs = 0

    # Start multiple robocopy processes as background jobs
    foreach ($source in $sourceDirectories) {
        $cleanPath = $source -creplace '^[A-Za-z]:\\', ''

        $driveLetter = [System.IO.Path]::GetPathRoot($source)
        $trimmedString = $driveLetter.Trim(':\\')

        $newPath = $cleanPath -replace '\\', '-'

        $logName = Join-Path -Path $logFolder -ChildPath $trimmedString"-"$newPath".log"
        $quotedLogName = '"' + $logName + '"'

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
    foreach ($job in $jobs) {
        while ($job.State -ne 'Completed') {
            $completedJobs = ($jobs | Where-Object { $_.State -eq 'Completed' }).Count
            $percentComplete = ($completedJobs / $totalJobs) * 100
            Write-Progress -Activity "Running Robocopy" -Status "$completedJobs of $totalJobs jobs completed." -PercentComplete $percentComplete
            Start-Sleep -Seconds 1
        }

        $jobResult = Receive-Job -Job $job -Wait
        $exitCode = $jobResult

        # Output the exit code
        # Write-Output "Robocopy exit code: $exitCode"

        # Check the exit code
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
    #}
} else {
    Write-Output "Drive $usbDriveLetter does not exist."
    pause
    exit
}
