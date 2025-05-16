<#
.SYNOPSIS
Validates and remediates the MECM (SCCM) client installation and configuration.

.DESCRIPTION
This script checks the assigned MECM site code and the state of the CcmExec service. If the configuration does not match the expected parameters, or if forced installation is requested, it can uninstall and/or reinstall the MECM client using a specified ccmsetup.exe. The script supports logging, custom setup arguments, and can use a remote ccmsetup.exe if the local one is missing.

.PARAMETER SiteCode
The expected site code for the system. Mandatory.

.PARAMETER ManagementPoint
The management point to use for the MECM client. Mandatory.

.PARAMETER RemoteCcmSetup
The remote path to the ccmsetup.exe file. Mandatory. Used if the local ccmsetup.exe is not found, or when uninstalling first.

.PARAMETER SetupArguments
Custom arguments for ccmsetup.exe. Optional. Defaults to `/mp:$ManagementPoint /logon SMSSITECODE=$SiteCode /forceinstall`.

.PARAMETER UninstallFirst
Switch. If specified, uninstalls the existing MECM client before reinstalling. Requires RemoteCcmSetup to be valid.

.PARAMETER ForceInstall
Switch. Forces installation even if the current configuration is valid.

.OUTPUTS
PSCustomObject

The script outputs a custom object ($JobEngine) containing:
- Execution metadata (timestamps, domain)
- Site code and management point information
- Client state and remediation status
- Logging (array of log messages)

.EXAMPLE
.\CcmExecFix.ps1 -SiteCode "ABC" -ManagementPoint "mp.contoso.com" -RemoteCcmSetup "\\server\share\ccmsetup.exe"

.EXAMPLE
.\CcmExecFix.ps1 -SiteCode "ABC" -ManagementPoint "mp.contoso.com" -RemoteCcmSetup "\\server\share\ccmsetup.exe" -UninstallFirst

.NOTES
- Logs actions and decisions to $JobEngine.Logging.
- The Installer method handles both uninstall and install.
- Assigned site code is revalidated after installation.
- When using UninstallFirst, RemoteCcmSetup must be a valid path.

.LINK
https://github.com/david-steimle-usps/CcmExecFix
#>

[CmdletBinding()]
param(
    [Parameter(
        Mandatory = $true, 
        HelpMessage = "The expected site code for your MECM environment.",
        Position = 0
    )]
    [ValidateNotNullOrEmpty()]
    [string]$SiteCode,

    [Parameter(
        Mandatory = $true, 
        HelpMessage = "A management point for initial installation use.",
        Position = 1
    )]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementPoint,

    [Parameter(
        Mandatory = $true, 
        HelpMessage = "A remote location for the ccmsetup.exe file. It needs to be accessible to the user running the script.",
        Position = 2
    )]
    [ValidateNotNullOrEmpty()]
    [string]$RemoteCcmSetup,

    [Parameter(
        HelpMessage = "Your ccmsetup.exe arguments.",
        Position = 3
    )]
    [string]$SetupArguments = "/mp:$ManagementPoint /logon SMSSITECODE=$SiteCode /forceinstall",

    [Parameter(
        HelpMessage = "Used to uninstall the existing client before install.",
        Position = 4
    )]
    [switch]$UninstallFirst,

    [Parameter(
        HelpMessage = "Runs installation regardless of existing CcmExec state.",
        Position = 5
    )]
    [switch]$ForceInstall
)

$CcmSetup = [system.io.fileinfo]'C:\Windows\ccmsetup\ccmsetup.exe'

$JobEngine = [pscustomobject]@{
    StartTimestamp = $(Get-Date -Format s)
    EndTimestamp = $null
    Domain = $env:USERDOMAIN
    Passed = $null
    Remediated = $false
    SiteCode = $SiteCode
    ManagementPoint = $ManagementPoint
    ClientPath = $(if ($CcmSetup.Exists) {
        Write-Output $CcmSetup.FullName
    } else {
        Write-Output $RemoteCcmSetup
    })
    RemoteCcmSetup = $RemoteCcmSetup
    UninstallFirst = $UninstallFirst
    SetupArguments = $SetupArguments
    CcmExecState = $(try {
        Get-Service -Name CcmExec -ErrorAction Stop | Select-Object -ExpandProperty Status
    } catch {
        Write-Output $null
    })
}

$Logger = [System.Collections.Generic.List[string]]::new()

$JobEngine | Add-Member -MemberType NoteProperty -Name Logging -Value $Logger

$JobEngine | Add-Member -MemberType ScriptMethod -Name Logger -Value {
    param(
        [string]$Message
    )
    $this.Logging.Add($("[$(Get-Date -Format s)] $Message"))
}

function Get-AssignedSiteCode {
    $MyProperty = try {
        Get-ItemProperty -Path "HKLM:\Software\Microsoft\SMS\Mobile Client" -ErrorAction Stop
    } catch {
        Write-Output $null
    }

    $MyValue = try {
        $MyProperty | Select-Object -ExpandProperty AssignedSiteCode -ErrorAction Stop
    } catch {
        Write-Output $null
    }

    if ($MyValue) {
        $MyValue = $MyValue.ToUpper()
    }

    Write-Output $MyValue
}

$JobEngine | Add-Member -MemberType NoteProperty -Name InitialSiteCode -Value $(Get-AssignedSiteCode)
$JobEngine | Add-Member -MemberType NoteProperty -Name AssignedSiteCode -Value $JobEngine.InitialSiteCode

$JobEngine.Logger('Begin decision tree:')
if ($JobEngine.SiteCode -eq $JobEngine.AssignedSiteCode) {
    $JobEngine.Logger(' + Expected site code and assigned site code match')
    if($JobEngine.CcmExecState){
        $JobEngine.Logger(' + CcmExec service exists')
        if($JobEngine.CcmExecState -eq 'Running'){
            $JobEngine.Logger(' + CcmExec service is running')
            if($ForceInstall){
                $JobEngine.Logger(' - Forced installation was requested.')
                $JobEngine.Passed = $false
            } else {
                $JobEngine.Logger(' + No action required')
                $JobEngine.Passed = $true
            }
        } else {
            $JobEngine.Logger(' - CcmExec service exists but is not running')
            $JobEngine.Passed = $false
        }
    } else {
        $JobEngine.Logger(' - CcmExec service not found')
        $JobEngine.Passed = $false
    }
} else {
    if($JobEngine.AssignedSiteCode) {
        $JobEngine.Logger(' - Expected site code and assigned site code do not match')
    } else {
        $JobEngine.Logger(' - No site code assigned')
    }
    $JobEngine.Passed = $false
}
$JobEngine.Logger("End decision tree, Passed = $($JobEngine.Passed)")

$JobEngine | Add-Member -MemberType ScriptMethod -Name Installer -Value {
    $ClientPath = $this.ClientPath
    $Arguments = $SetupArguments
    if ($UninstallFirst) {
        if(Test-Path $this.RemoteCcmSetup){
            $this.Logger('Uninstalling existing client...')
            if($this.CcmExecState){
                $this.Logger(' * Running uninstall')
                $this.Logger(" * Start-Process -FilePath $ClientPath -ArgumentList `"/uninstall`" -Wait -NoNewWindow")
                try {
                    Start-Process -FilePath $ClientPath -ArgumentList "/uninstall" -Wait -NoNewWindow
                    $this.Logger(' * Uninstall complete')
                    $this.ClientPath = $this.RemoteCcmSetup
                } catch {
                    $this.Logger(" ! Uninstall failed: $($PSItem.Exception.Message)")
                }
            } else {
                $this.Logger(' * No client to uninstall')
            }
        } else {
            $this.Logger(" ! Could not locate $($this.RemoteCcmSetup)")
            $this.Logger(" * Ignoring uninstall, as it will remove $($this.ClientPath)")
        }
    }
    $this.Logger('Installing client...')
    $ClientPath = $this.ClientPath
    $this.Logger(' * Running install')
    $this.Logger(" * Start-Process -FilePath $ClientPath -ArgumentList `"$Arguments`" -Wait -NoNewWindow")
    try {
        Start-Process -FilePath $ClientPath -ArgumentList "$Arguments" -Wait -NoNewWindow
        $this.Logger(" * Install complete")
    } catch {
        $this.Logger(" ! Install failed: $($PSItem.Exception.Message)")
    }
}

if ($JobEngine.Passed) {
    $JobEngine.Logger('No action needed.')
} else {
    $JobEngine.Logger('System requires remediation.')
    $JobEngine.Logger("Install from $($JobEngine.ClientPath)")
    $JobEngine.Installer()
    $JobEngine.AssignedSiteCode = $(Get-AssignedSiteCode)
}

if( -not ($(Get-AssignedSiteCode) -eq $SiteCode)-and (Get-Service -Name CcmExec -ErrorAction Ignore | Where-Object -Property Status -eq 'Running')){
    try {
        $SMSClient = New-Object -ComObject Microsoft.SMS.Client
        $SMSClient.SetAssignedSite("$SiteCode")
        $JobEngine.Logger("Site assignment $SiteCode set successfully")
    } catch {
        $JobEngine.Logger("Site assignment failed: $($PSItem.Exception.Message)")
    }
    try {
        Get-Service -Name CcmExec | Restart-Service
        $JobEngine.Logger("Restarted CcmExec")
    } catch {
        $JobEngine.Logger("Failed to restart CcmExec")
    }
}

if(($(Get-AssignedSiteCode) -eq $SiteCode) -and (Get-Service -Name CcmExec -ErrorAction Ignore | Where-Object -Property Status -eq 'Running')){
    $SMSClient = New-Object -ComObject Microsoft.SMS.Client
    $JobEngine.AssignedSiteCode = $SMSClient.GetAssignedSite()
    $JobEngine.Remediated = $true
}

$JobEngine.EndTimestamp = $(Get-Date -Format s)

Write-Output $JobEngine