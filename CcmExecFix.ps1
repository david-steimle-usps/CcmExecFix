<# 
.SYNOPSIS
Processes MECM client setup and validation based on user-provided parameters.

.DESCRIPTION
This script validates the MECM site code and management point, and optionally installs or reinstalls the MECM client based on the provided parameters.

.PARAMETER SiteCode
The expected site code for the system. This parameter is mandatory and accepts pipeline input.

.PARAMETER ManagementPoint
The management point to use for the MECM client. This parameter is mandatory and accepts pipeline input.

.PARAMETER RemoteCcmSetup
The remote path to the `ccmsetup.exe` file. This parameter is optional and accepts pipeline input.

.PARAMETER SetupArguments
Custom arguments to pass to the `ccmsetup.exe` installer. This parameter is optional and accepts pipeline input.

.PARAMETER UninstallFirst
A switch to indicate whether the existing MECM client should be uninstalled before reinstalling. This parameter is optional and accepts pipeline input.

.EXAMPLE
.\CcmExecFix.ps1 -SiteCode "ABC" -ManagementPoint "managementpoint.mycompany.com"

.EXAMPLE
.\CcmExecFix.ps1 -SiteCode "ABC" -ManagementPoint "managementpoint.mycompany.com" -RemoteCcmSetup "\\server\path\ccmsetup.exe" -UninstallFirst
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$SiteCode,

    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$ManagementPoint,

    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$RemoteCcmSetup,

    [Parameter(ValueFromPipeline = $true)]
    [string]$SetupArguments = "/logon SMSSITECODE=$SiteCode /forceinstall",

    [Parameter(ValueFromPipeline = $true)]
    [switch]$UninstallFirst,

    [Parameter(ValueFromPipeline = $true)]
    [switch]$ForceInstall
)

$CcmSetup = [system.io.fileinfo]'C:\Windows\ccmsetup\ccmsetup.exe'

$JobEngine = [pscustomobject]@{
    StartTimestamp = $(Get-Date -Format s)
    EndTimestamp = $null
    Domain = $env:USERDOMAIN
    Passed = $null
    SiteCode = $SiteCode
    ManagementPoint = $ManagementPoint
    ClientPath = $(if ($CcmSetup.Exists) {
        Write-Output $CcmSetup.FullName
    } else {
        Write-Output $RemoteCcmSetup
    })
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
    $JobEngine.Logger(' - Expected site code and assigned site code do not match')
    $JobEngine.Passed = $false
}
$JobEngine.Logger("End decision tree, Passed = $($JobEngine.Passed)")

$JobEngine | Add-Member -MemberType ScriptMethod -Name Installer -Value {
    $ClientPath = $this.ClientPath
    $Arguments = $SetupArguments
    if ($UninstallFirst) {
        $JobEngine.Logger('Uninstalling existing client...')
        # Add uninstallation logic here
    }
    $JobEngine.Logger('Installing client with arguments...')
    # Add installation logic here
}

if ($JobEngine.Passed) {
    $JobEngine.Logger('No action needed.')
} else {
    $JobEngine.Logger('System requires remediation.')
    $JobEngine.Logger("Install from $($JobEngine.ClientPath)")
    $JobEngine.Installer()
    $JobEngine.AssignedSiteCode = $(Get-AssignedSiteCode)
}

$JobEngine.EndTimestamp = $(Get-Date -Format s)

Write-Output $JobEngine