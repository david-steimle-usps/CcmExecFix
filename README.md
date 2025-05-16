# MECM Client Remediation Script

This PowerShell script automates the validation and remediation of Microsoft Endpoint Configuration Manager (MECM) client installations on Windows endpoints. Designed for use via WinRM, it checks the assigned site code and the state of the CcmExec service, and can perform uninstall and reinstall operations as needed.

**Key Features:**
- **Parameterization:** Accepts site code, management point, remote ccmsetup.exe path, custom setup arguments, and switches for uninstalling first or forcing install.
- **Decision Logic:** Determines if remediation is needed based on current site code and service state.
- **Automated Remediation:** Can uninstall the existing client and reinstall from a specified source, logging all actions.
- **Site Assignment:** Attempts to set the assigned site code using COM automation if needed.
- **Comprehensive Logging:** All actions and decisions are logged for auditing and troubleshooting.
- **Output:** Returns a custom object summarizing execution details, results, and logs.

**Intended Use:**  
This script is suitable for IT administrators managing MECM clients across diverse environments, enabling consistent client health and configuration with minimal manual intervention.

## Features

- **Site Code and Service Validation:**  
  Checks the assigned MECM site code and the state of the CcmExec service using both registry and COM methods.

- **Automated Remediation:**  
  If the endpoint is not compliant (wrong or missing site code, CcmExec not running, or forced install requested), the script can uninstall and/or reinstall the MECM client using a specified `ccmsetup.exe`.

- **Flexible Installation Source:**  
  Uses a local `ccmsetup.exe` if available, or a remote path if specified.

- **Customizable Arguments:**  
  Allows custom setup arguments for client installation.

- **Uninstall Option:**  
  Supports uninstalling the existing client before reinstalling, if requested.

- **Site Assignment:**  
  Uses COM automation to set the assigned site code if needed, and restarts the CcmExec service to apply changes.

- **Comprehensive Logging:**  
  All actions, decisions, and errors are logged to an in-memory log array, which is included in the output object.

- **Detailed Output:**  
  Returns a custom object (`$JobEngine`) containing execution metadata, site and client state, remediation status, and logs.

## Parameters

- `SiteCode` (string, required):  
  The expected site code for the endpoint.

- `ManagementPoint` (string, required):  
  The management point FQDN to use for the MECM client.

- `RemoteCcmSetup` (string, required):  
  UNC path to the `ccmsetup.exe` file, used if the local copy is missing or when uninstalling first.

- `SetupArguments` (string, optional):  
  Custom arguments for `ccmsetup.exe`. Defaults to `/mp:$ManagementPoint /logon SMSSITECODE=$SiteCode /forceinstall`.

- `UninstallFirst` (switch, optional):  
  If specified, uninstalls the existing MECM client before reinstalling.

- `ForceInstall` (switch, optional):  
  If specified, forces installation even if the current configuration is valid.

## How It Works

1. **Initialization:**  
   The script gathers the current site code and CcmExec service state, and prepares a logging mechanism.

2. **Decision Tree:**  
   - If the assigned site code matches the expected value and CcmExec is running (unless forced install is requested), no action is taken.
   - Otherwise, the script logs the need for remediation.

3. **Remediation:**  
   - If `UninstallFirst` is set and the remote setup file exists, the script uninstalls the current client.
   - Installs the client using the specified or default arguments.
   - Logs all actions and errors.

4. **Site Assignment and Service Restart:**  
   - If the assigned site code is still incorrect but CcmExec is running, the script uses COM automation to set the site code and restarts the service.

5. **Final Validation:**  
   - If the assigned site code is correct and CcmExec is running, the script marks the endpoint as remediated.

6. **Output:**  
   - The script outputs a custom object with all relevant details and logs.

## Example Usage

```powershell
.\CcmExecFix.ps1 -SiteCode "ABC" -ManagementPoint "mp.contoso.com" -RemoteCcmSetup "\\server\share\ccmsetup.exe"
.\CcmExecFix.ps1 -SiteCode "ABC" -ManagementPoint "mp.contoso.com" -RemoteCcmSetup "\\server\share\ccmsetup.exe" -UninstallFirst
```

## Output

The script outputs a `[PSCustomObject]` containing:
- Execution metadata (timestamps, domain)
- Site code and management point information
- Client state and remediation status
- Logging (array of log messages)

## Notes

- All actions and decisions are logged to `$JobEngine.Logging`.
- The `Installer` method handles both uninstall and install logic.
- Assigned site code is revalidated after installation.
- When using `UninstallFirst`, `RemoteCcmSetup` must be a valid path.
- Requires administrative privileges on the endpoint.

## Link

[GitHub Repository](https://github.com/david-steimle-usps/CcmExecFix)