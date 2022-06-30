<#
    .SYNOPSIS
    Processes structured MS-SQL scripts for server execution.

    .DESCRIPTION
    Executes sctructured MS-SQL scripts for code deployments directly to SQL server.
    After each script execution the line is commented out in the controller file.

    .PARAMETER Server
    The Server name and SQL instance is needed.

    .PARAMETER MainPath
    FullName path to the Versions.txt folder of deployment.

    .INPUTS
    None

    .OUTPUTS
    System.String. Outputs simple logging along with flat file.

    .EXAMPLE
    PS> .\Execute-SQLDeployment.ps1 -Server 'MySQLServer' -MainPath 'C:\Deployment\Folder'

    .LINK
    NA
#>

[CmdletBinding()]
PARAM
(
    [Parameter(Mandatory = $true)]
    [string]$Server,
    [Parameter(Mandatory = $true)]
    [ValidateScript({ IF (Test-Path $_) { $true } ELSE { THROW "Path $_ is not valid" } })]
    [string]$MainPath,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ IF (Test-Path $_) { $true } ELSE { THROW "Path $_ is not valid" } })]
    [string]$LogFolder = 'D:\Logs\Scripts\',
    [Parameter(Mandatory = $false)]
    [string]$LogType = 'SQL-Deployment'
)

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

TRY {
    New-LogEntry -Level Start -Message 'Beginning SQL Script Executions'
    # Import Versions.txt file from MainPath, sorting them from lowest number to largest
    IF ($SQLVersions = Get-Content -Path (Join-Path -Path $MainPath -ChildPath 'Versions.txt') | Sort-Object) {
        New-LogEntry -Message "Versions.txt file successfully imported"
        # Process each version in file seperately
        FOREACH ($Version in $SQLVersions) {
            New-LogEntry -Message "Processing Version: $Version"
            # Build this version path
            IF (Test-Path -Path ($VersionPath = Join-Path -Path $MainPath -ChildPath $Version)) {
                New-LogEntry -Message "Version Path: $VersionPath"
                # Build this version controller file location
                IF (Test-Path -Path ($VersionController = Join-Path -Path $VersionPath -ChildPath "$Version.Controller.sql")) {
                    New-LogEntry -Message "Version Controller: $VersionController"
                    # Import list of SQL files for this version
                    IF ($VersionFiles = Get-Content -Path $VersionController) {
                        New-LogEntry -Message "Imported Version Controller"
                        # Process each SQL file for version individually
                        FOREACH ($SQLFile in $VersionFiles) {
                            # Ignore commented lines
                            IF (-Not (($SQLFile.StartsWith('/*')))) {
                                New-LogEntry -Message "Processing: $SQLFile"
                                # Ensure SQL file exists
                                IF (Test-Path -Path ($ThisFile = Join-Path -Path $VersionPath -ChildPath $SQLFile)) {
                                    New-LogEntry -Message "File Located"
                                    # Process this SQL file on server
                                    Invoke-Sqlcmd -ServerInstance $Server -InputFile $ThisFile -QueryTimeout 65535 -ErrorAction Stop
                                    New-LogEntry -Message "     Completed"

                                    # If no errors are detected, comment out script in controller file
                                    # This will allow for multiple executions without running completed scripts
                                    IF (-Not ($Error)) { (Get-Content -Path $VersionController).replace($SQLFile, "/* $SQLFile */") | Set-Content -Path $VersionController }
                                } ELSE {
                                    # SQL file is missing
                                    New-LogEntry -Level Error -Message "SQL file is missing: $ThisFile"
                                    EXIT 1;
                                }
                            }
                        }
                    } ELSE {
                        # Unable to get contents of VersionController file
                        New-LogEntry -Level Error -Message "Version controller file not readable: $VersionController"
                        EXIT 1;
                    }
                } ELSE {
                    # Version controller file does not exist
                    New-LogEntry -Level Error -Message "Version controller file not found: $VersionController"
                    EXIT 1;
                }
            } ELSE {
                # Version folder does not exist
                New-LogEntry -Level Error -Message "Version folder does not exist: $VersionPath"
                EXIT 1;
            }
            # All scripts should now be executed, lets update version
            $SetVersion = "Version $Version"
            Invoke-Sqlcmd -ServerInstance $Server -Query "EXEC AMCHealth.Reference.setCCVersion `'$SetVersion'" -ErrorAction Stop
            New-LogEntry -Message "Updating CareConsole version to: $Version"
            IF (-Not ($Error)) { New-LogEntry -Message "Updated CC Version to $Version" }
        }
    } ELSE {
        # Versions.txt file import failed
        New-LogEntry -Level Error -Message "Unable to import Versions.txt file"
        EXIT 1;
    }
}

CATCH {
    New-LogEntry -Level Error -Message $Error[0]
    EXIT 1;
}

New-LogEntry -Level End -Message '<<< Process Completed >>>'
EXIT 0;