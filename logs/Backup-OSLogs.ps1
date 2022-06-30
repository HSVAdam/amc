<#
    .SYNOPSIS
        OS level event log backup.
    .DESCRIPTION
        Copied Windows event log data from remote server to central backup location.  Default set to clear log after backup.
    .PARAMETER DomainGroup
        A domain security group which contains member servers to backup logs from.
    .PARAMETER LogFiles
        Windows event log files to backup from remote server.
    .PARAMETER BackupRoot
        Root location to backup files to.
    .PARAMETER ClearLog
        BOOL parameter to identify if you would like to log cleared after successful backup
    .INPUTS
        String (Hard-Coded Variables)
    .OUTPUTS
        None
    .EXAMPLE
        & Get-OSLogs.ps1
    .LINK
        https://git.powershell.army/abranham/LogManagement
    .NOTES
#>

#region VARIABLES
$DomainGroup = ''
$LogFiles = @('System.evtx', 'Security.evtx', 'Application.evtx')
$BackupRoot = ''
$ClearLog = $true
$Today = Get-Date -Format 'yyyyMMdd'

#Script Logging Variables
$LogFolder = 'D:\Logs\Scripts'  # Root log folder for script logging
$LogType = 'OS-Logs'  # Defines the script name in the log folder
#endregion VARIABLES

#region FUNCTIONS
FUNCTION New-LogEntry
{
	[CmdletBinding()]
	PARAM
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Message,
		[Parameter(Mandatory = $false)]
		[ValidateSet("Info", "Error", "Warn", "Start", "End")]
		[string]$Level = "Info",
		[Parameter(Mandatory = $false)]
		[string]$Path = $LogFolder,
		[Parameter(Mandatory = $false)]
		[switch]$NoClobber,
		[Parameter(Mandatory = $false)]
		[string]$Log = $LogType
	)

	BEGIN
	{
		# Ensure log file exists, if not create it
		$Today = Get-Date -Format 'yyyyMMdd'
		$Year = Get-Date -Format 'yyyy'
		$Month = Get-Date -Format 'MM'
		IF (!(Test-Path -Path "$Path\$Log\$Year\$Month\$Log-$Today.log"))
		{
			New-Item -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -ItemType File -Force | Out-Null
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "======================================================="
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "File Created: [$Log]"
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "File Date:    [$Today]"
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "Log Path:     [$Path\$Log\$Year\$Month\$Log-$Today.log]"
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "Server:       [$env:COMPUTERNAME]"
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "======================================================="
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value " "
		}
	}
	PROCESS
	{
		# Process supplied log data to file
		$LogDate = Get-Date -UFormat '%x %r'
		IF ($Level -eq 'Start')
		{
			# Add a blank line to indicate new execution of script
			Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value ""
		}
		Add-Content -Path "$Path\$Log\$Year\$Month\$Log-$Today.log" -Value "[$Level][$LogDate] $Message"
		Write-Host "[$Level][$LogDate] $Message"
	}
	END
	{

	}
}
#endregion FUNCTIONS

TRY
{
    New-LogEntry -Message 'Beginning OS Log Processing' -Level Start

    # Get listing of all computers from domain security group
    IF ($ServerList = (Get-ADGroupMember -Identity $DomainGroup).Name)
    {
        New-LogEntry -Message "Obtained server list from [$DomainGroup]"
        FOREACH ($Server in $ServerList)
        {
            # Update check name for local execution server
            IF ($Server -eq $env:COMPUTERNAME) { $ServerName = 'localhost' } ELSE { $ServerName = $Server }
            New-LogEntry "     Beginning [$Server]"
            IF ((Test-NetConnection -ComputerName $ServerName -CommonTCPPort RDP -InformationLevel Quiet) -eq $true)
            {
                New-LogEntry -Message "          ONLINE"
                # Server is responding, ensure backup folder exists
                IF (!(Test-Path -Path "$BackupRoot\$Today\$Server"))
                {
                    New-Item -Path "$BackupRoot\$Today\$Server" -ItemType Directory -Force
                    IF (!(Test-Path -Path "$BackupRoot\$Today\$Server"))
                    {
                        # Unable to create log backup folder, cancel all actions
                        New-LogEntry -Message "     Unable to create backup log folder" -Level Error
                        EXIT 1;
                    }
                }
                # Log folder should now exist, begin file backups
                FOREACH ($Log in $LogFiles)
                {
                    New-LogEntry -Message "     Working on [$Log]"
                    IF (Test-Path -Path "\\$ServerName\c$\Windows\System32\winevt\Logs\$Log")
                    {
                        $CopyFile = Copy-Item -Path "\\$ServerName\c$\Windows\System32\winevt\Logs\$Log" -Destination "$BackupRoot\$Today\$Server" -PassThru
                        IF ($CopyFile.Exists -eq $true -and (Test-Path -Path "$BackupRoot\$Today\$Server\$Log") -eq $true)
                        {
                            # File copied successfully, check if $ClearLog is $true
                            New-LogEntry -Message "          Successful"
                            IF ($ClearLog -eq $true)
                            {
                                $ClearLogFile = [io.path]::GetFileNameWithoutExtension($Log)
                                New-LogEntry -Message "          Clearing [$ClearLogFile] from [$Server]"
                                Clear-EventLog -LogName $ClearLogFile -ComputerName $ServerName
                            }
                            ELSE
                            {
                                # Not clearing event log on remote server
                                New-LogEntry -Message "          Leaving event log intact on [$Server]"
                            }
                        }
                    }
                    ELSE
                    {
                        # Log file not found on remote server, possible SMB issue?
                        New-LogEntry -Message "          Log File not found." -Level Error
                    }
                }
            }
            ELSE
            {
                # Server is not responding, could be check above, confirm Test-NetConnection command
                New-LogEntry -Message "          OFFLINE" -Level Error
            }
        }
    }
    ELSE
    {
        # Unable to obtain server list from active directory security group
        New-LogEntry -Message "Unable to obtain server list from domain security group." -Level Error
    }
}

CATCH
{
    RETURN $Error[0]
    New-LogEntry -Message $Error[0] -Level Error
    EXIT 1;
}

New-LogEntry -Message 'Process Completed' -Level End
EXIT 0;