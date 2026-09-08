#requires -Version 5.1

function Set-WinPEStartupUSBDriveLetter {
    <#
    .SYNOPSIS
        Reassigns USB drive letters in WinPE starting at H.

    .DESCRIPTION
        Detects mounted USB partitions that currently have drive letters and
        reassigns them in deterministic order (DiskNumber, PartitionNumber)
        to the next available letters from H through Z.

        Used drive letters are discovered through .NET
        ([System.IO.DriveInfo]::GetDrives()) to improve reliability in WinPE.

    .EXAMPLE
        Set-WinPEStartupUSBDriveLetter

        Reassigns USB partition drive letters starting at H.

    .EXAMPLE
        Set-WinPEStartupUSBDriveLetter -Verbose

        Reassigns USB partition drive letters and writes detailed logs.

    .NOTES
        Author:  David Segura
        Module:  OSDCloud
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    $Error.Clear()

    if ($env:SystemDrive -ne 'X:') {
        Write-Warning 'Set-WinPEStartupUSBDriveLetter: Not running in WinPE (SystemDrive is not X:). Exiting.'
        return
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    $usbDisks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' })
    if (-not $usbDisks) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No USB disks detected"
        return
    }

    $usbPartitions = foreach ($usbDisk in $usbDisks) {
        Get-Partition -DiskNumber $usbDisk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter }
    }

    $usbPartitions = @($usbPartitions | Sort-Object -Property DiskNumber, PartitionNumber)

    if (-not $usbPartitions) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No USB partitions with drive letters detected"
        return
    }

    $usedLetters = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        $driveLetter = $drive.Name.Substring(0, 1).ToUpperInvariant()
        [void]$usedLetters.Add($driveLetter)
    }

    foreach ($usbPartition in $usbPartitions) {
        $currentLetter = ([string]$usbPartition.DriveLetter).ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($currentLetter)) {
            [void]$usedLetters.Remove($currentLetter)
        }
    }

    $candidateLetters = [char[]](72..90)
    $resultCount = 0
    $failureCount = 0

    foreach ($usbPartition in $usbPartitions) {
        $newLetter = $null

        foreach ($candidateLetter in $candidateLetters) {
            $candidate = ([string]$candidateLetter).ToUpperInvariant()
            if (-not $usedLetters.Contains($candidate)) {
                $newLetter = $candidate
                [void]$usedLetters.Add($candidate)
                break
            }
        }

        if (-not $newLetter) {
            Write-Warning "Set-WinPEStartupUSBDriveLetter: No available drive letters remain in the H-Z range for Disk $($usbPartition.DiskNumber) Partition $($usbPartition.PartitionNumber)."
            $failureCount += 1
            continue
        }

        $oldLetter = ([string]$usbPartition.DriveLetter).ToUpperInvariant()

        if ($oldLetter -eq $newLetter) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Disk $($usbPartition.DiskNumber) Partition $($usbPartition.PartitionNumber) already using $newLetter"
            $resultCount += 1
            continue
        }

        try {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] USB DriveLetter: $oldLetter -> $newLetter"
            Set-Partition -DiskNumber $usbPartition.DiskNumber -PartitionNumber $usbPartition.PartitionNumber -NewDriveLetter $newLetter -ErrorAction Stop
            $resultCount += 1
        }
        catch {
            Write-Warning "Set-WinPEStartupUSBDriveLetter: Failed to reassign Disk $($usbPartition.DiskNumber) Partition $($usbPartition.PartitionNumber) from $oldLetter to $newLetter. $($_.Exception.Message)"
            $failureCount += 1
        }
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Complete (Success=$resultCount, Failed=$failureCount)"
}
