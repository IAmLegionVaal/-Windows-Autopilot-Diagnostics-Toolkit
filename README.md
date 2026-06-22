# Windows Autopilot Diagnostics and Safe Recovery Toolkit

PowerShell tooling for collecting Windows Autopilot, Entra ID and Intune enrolment evidence plus guarded local recovery actions, created by **Dewald Pretorius**.

## Files

- `src/Get-AutopilotDiagnostics.ps1` — read-only Autopilot, Entra, MDM, provisioning and endpoint-readiness reporting.
- `src/Invoke-AutopilotSafeRecovery.ps1` — guarded local recovery for Intune Management Extension, Windows MDM services, EnterpriseMgmt scheduled tasks, DNS and the current user's Primary Refresh Token.
- `Launch_Autopilot_Recovery.bat` — interactive technician menu.

## Diagnostic collection

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\src\Get-AutopilotDiagnostics.ps1
```

The diagnostic script collects:

- Windows edition, build, hardware, TPM, Secure Boot and firmware context
- `dsregcmd /status`
- Autopilot and MDM registry information
- Autopilot, provisioning, AAD and Device Management event logs
- Intune Management Extension service and log inventory
- Microsoft enrolment endpoint connectivity
- CSV, JSON, HTML and text evidence

## Safe recovery diagnostic default

Running the recovery script without a recovery switch captures current service, EnterpriseMgmt task, join-state and connectivity information without changing the device:

```powershell
.\src\Invoke-AutopilotSafeRecovery.ps1
```

## Safe recovery set

The standard recovery workflow:

1. Archives Intune Management Extension logs when present.
2. Starts or restarts Intune Management Extension.
3. Starts or restarts available Windows MDM client services.
4. Flushes the DNS resolver cache.
5. Starts existing enabled EnterpriseMgmt sync candidate tasks.

```powershell
.\src\Invoke-AutopilotSafeRecovery.ps1 -RepairAllSafe -DryRun
```

## Individual recovery actions

```powershell
.\src\Invoke-AutopilotSafeRecovery.ps1 -RestartIntuneManagementExtension
.\src\Invoke-AutopilotSafeRecovery.ps1 -RestartMdmServices
.\src\Invoke-AutopilotSafeRecovery.ps1 -TriggerMdmSync
.\src\Invoke-AutopilotSafeRecovery.ps1 -RefreshPrimaryRefreshToken
.\src\Invoke-AutopilotSafeRecovery.ps1 -FlushDns
.\src\Invoke-AutopilotSafeRecovery.ps1 -ArchiveIntuneLogs
```

## Recovery behaviour

- Intune Management Extension is restarted only when installed.
- Available `dmwappushservice` and `DmEnrollmentSvc` services are started or restarted.
- Only existing, enabled EnterpriseMgmt tasks matching recognised MDM sync patterns are triggered.
- `dsregcmd /refreshprt` is run only for the currently signed-in user.
- Existing EnterpriseMgmt scheduled tasks are exported before recovery.
- Intune logs are compressed into the backup folder without deleting the originals.

## Logs, evidence and backups

Each recovery run creates a timestamped desktop folder containing:

- `before.json` and `after.json`
- `recovery.log`
- Before-and-after `dsregcmd` output
- Exported EnterpriseMgmt task XML files
- Optional Intune Management Extension log archive

## Safety boundaries

The recovery tool deliberately does **not**:

- Unenrol the device
- Leave Entra ID or the on-premises domain
- Delete MDM enrolment registry keys
- Remove certificates
- Reset or wipe Windows
- Re-register the device as a new Autopilot device
- Delete Intune Management Extension content or logs
- Create or rewrite scheduled tasks

Service and scheduled-task recovery normally require elevation. PRT refresh should be run inside the affected user's interactive session.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Completed successfully, including diagnosis or dry-run |
| 2 | Device not enrolled, required task absent or invalid target |
| 4 | Elevation required |
| 10 | User cancelled |
| 20 | Recovery action failed |

## Interactive launcher

Double-click:

```text
Launch_Autopilot_Recovery.bat
```

## Validation status

Tested successfully by the author on his own Windows machines in his available Autopilot, Entra ID and Intune environments. The documented diagnostic, service, scheduled-task, PRT, DNS and log-archive workflows worked as intended on those systems.

Results may vary with the Windows edition and build, device join state, Intune enrolment type, tenant policy, assigned applications and scripts, scheduled-task names, permissions, network access and user-specific identity state. Successful author testing does not guarantee identical behaviour in every tenant, so use `-DryRun` and validate on a non-critical managed device before broader deployment.
