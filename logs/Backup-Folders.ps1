#Requires -Modules 7Zip4Powershell

# Example Usage:
#   .\Backup-Files.ps1 -Source 'C:\inetpub\wwwroot\FOLDER\Folder2\Processed' -Destination 'D:\Backups' -AppName 'Folder_Archive-Processed'

PARAM (
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateScript({ IF (-Not ($_ | Test-Path)) { THROW 'Check source path.' } RETURN $true })]
    [System.IO.FileInfo]$Source,
    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateScript({ IF (-Not ($_ | Test-Path)) { THROW 'Check destination path.' } RETURN $true })]
    [System.IO.FileInfo]$Destination,
    [Parameter(Mandatory = $true)]
    [string]$AppName,
    [Parameter(Mandatory = $false)]
    [int]$KeepDays = 14,
    [Parameter(Mandatory = $false)]
    [string]$CompressDrive = (Split-Path $Source -Qualifier),
    [Parameter(Mandatory = $false)]
    [ValidateScript({ IF (-Not ($_ | Test-Path)) { THROW 'Check log path.' } RETURN $true })]
    [System.IO.FileInfo]$LogFolder = 'D:\Logs\Scripts'
)

# Set application name for logging
$LogType = $AppName

#region FUNCTIONS
FUNCTION New-LogEntry {
    [CmdletBinding()]
    PARAM
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Error', 'Warn', 'Start', 'End')]
        [string]$Level = 'Info',
        [Parameter(Mandatory = $false)]
        [string]$Path = $LogFolder,
        [Parameter(Mandatory = $false)]
        [switch]$NoClobber,
        [Parameter(Mandatory = $false)]
        [string]$Log = $LogType
    )

    BEGIN {
        # Ensure log file exists, if not create it
        $Today = Get-Date -Format 'yyyyMMdd'
        $Year = Get-Date -Format 'yyyy'
        $Month = Get-Date -Format 'MM'
        IF (!(Test-Path -Path "$Path\$Log\$Year\$Month\$Log-$Today.log")) {
            New-Item -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -ItemType File -Force | Out-Null
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value '======================================================='
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "File Created: [$Log]"
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "File Date:    [$Today]"
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "Log Path:     [$Path\$Log\$Year\$Month\$Log-$Today.log]"
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "Server:       [$env:COMPUTERNAME]"
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value '======================================================='
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value ' '
        }
    }
    PROCESS {
        # Process supplied log data to file
        $LogDate = Get-Date -UFormat '%x %r'
        IF ($Level -eq 'Start') {
            # Add a blank line to indicate new execution of script
            Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value ''
        }
        Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "[$Level][$LogDate] $Message"
        Write-Host "[$Level][$LogDate] $Message"
    }
    END {

    }
}
#endregion FUNCTIONS

New-LogEntry -Level 'Start' -Message 'Beginning logging process'

TRY {
    # Obtain list of all files in source folder older than $KeepDays and selecting only the required fields (FullName and LastWriteTimeUtc) This cuts down on memory usage
    # Sort object by LastWriteTimeUtc in Date format, LastWriteTimeUtc is used for date creation accuracy no matter if file is moved/copied or not (Creation timestamp changes)
    $Collection = Get-ChildItem -Path $Source | Where-Object { $_.PSIsContainer -eq 'true' -and [datetime]::parseexact($_.BaseName, 'yyyyMMdd', $null) -lt (Get-Date).AddDays(-$KeepDays) } | Select-Object FullName, Name, @{ Name = 'LastWriteTimeUtc'; Expression = { $_.LastWriteTimeUtc.ToString('yyyyMMdd') } }

    New-LogEntry -Level 'Info' -Message "Source Location: $Source"
    New-LogEntry -Level 'Info' -Message "Destination Location: $Destination"
    New-LogEntry -Level 'Info' -Message "Keepdays: $KeepDays"
    New-LogEntry -Level 'Info' -Message "Located $($Collection.Count) dates to manage"

    # ForEach sorted date, compress to zip archive within local hidden TMP folder
    # Once file compression is completed file will be moved to $Destination
    # Once verification of file move is completed source files will be deleted
    FOREACH ($Date in $Collection){
        # Create TMP zip folder on source drive, thi folder will be hidden
        # Zipping directly to $Destination could be over network, performing local zip is much faster
        IF (!(Test-Path -Path (Join-Path -Path $CompressDrive -ChildPath 'TMP'))) {
            New-Item -Path (Join-Path -Path $CompressDrive -ChildPath 'TMP') -ItemType Directory -Force
            $TMPFolder = Get-Item (Join-Path -Path $CompressDrive -ChildPath 'TMP') -Force
            $TMPFolder.Attributes='Hidden'
        }

        New-LogEntry -Level 'Info' -Message "Working on [$($Date.Name)] with [$($(Get-ChildItem -Path $Date.FullName).Count)] objects"

        New-LogEntry -Level 'Info' -Message "Beginning Compression"
        # Compress $Date.Group.FullName using 7Zip into zip using fastest compression
        $DateFile = "$AppName-$($Date.Name).zip"
        $Date.FullName | Compress-7Zip -ArchiveFileName (Join-Path -Path $CompressDrive -ChildPath "TMP\$DateFile") -Format Zip -CompressionLevel Fast
        Move-Item -Path (Join-Path -Path $CompressDrive -ChildPath "TMP\$DateFile") -Destination $Destination -Force
        New-LogEntry -Level 'Info' -Message 'Completed Compression'

        # Ensure zip file has been created and is in destination location
        IF (Test-Path -Path (Join-Path -Path $Destination -ChildPath $DateFile)) {
            # Zip file has been located, cleanup source
            New-LogEntry -Level 'Info' -Message 'Removing source files'
            Remove-Item -Path $Date.FullName -Recurse -Force -Confirm:$false
        } ELSE {
            # Zip file creation failed, no source file removal
        }
    }
}

CATCH {
    Write-Host $Error[0]
    New-LogEntry -Level 'Error' -Message "Critical Error:  $($Error[0])"
}

New-LogEntry -Level 'End' -Message 'Completed logging process'