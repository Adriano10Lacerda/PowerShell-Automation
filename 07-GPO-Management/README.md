# GPO Management

## Overview

This module provides an interactive PowerShell menu for managing and inspecting Group Policy Objects (GPOs) and their links.

It validates the configuration before execution and checks whether each requested operation is enabled.

## Features

- Check whether a GPO exists.
- List GPOs.
- Create a GPO with a description.
- Check the links associated with a GPO.
- List GPO links.
- Enable or disable individual operations through configuration.
- Configure simulation mode.
- Validate the module configuration before execution.

## Project Files

| File | Description |
|---|---|
| `GPO-Management.ps1` | Main script and interactive menu. |
| `GPO-Functions.psm1` | GPO management functions and configuration validation. |
| `GPO-Configuration.example.json` | Example configuration file. |
| `GPO-Configuration.json` | Local configuration file; do not commit local settings. |
| `Test-GPOManagement.ps1` | Module test script. |

## Requirements

- Windows and PowerShell.
- An Active Directory environment for real GPO operations.
- Appropriate permissions for the requested operations.
- Required Group Policy PowerShell functionality for real operations.

## Configuration

1. Copy `GPO-Configuration.example.json` to `GPO-Configuration.json`.
2. Configure `ActiveDirectory.DomainController`.
3. Configure `ActiveDirectory.TargetDomain`.
4. Review the default GPO description settings.
5. Keep `SimulationMode` set to `true` while testing.
6. Enable or disable operations under `Operations`.

The example configuration enables simulation mode and all five operations by default. Review `GPO-Functions.psm1` to understand the implemented simulation behavior before attempting real operations.

### Configuration Reference

| Setting | Description |
|---|---|
| `SimulationMode` | Enables or disables simulation mode. |
| `ActiveDirectory.DomainController` | Domain controller used for directory operations. |
| `ActiveDirectory.TargetDomain` | Target Active Directory domain. |
| `GPO.DefaultDescription` | Default description for a new GPO. |
| `GPO.RequireDescription` | Indicates whether a description is required. |
| `Operations.CheckGPO` | Enables checking a GPO. |
| `Operations.ListGPOs` | Enables listing GPOs. |
| `Operations.CreateGPO` | Enables creating a GPO. |
| `Operations.CheckLinks` | Enables checking GPO links. |
| `Operations.ListLinks` | Enables listing GPO links. |
| `Simulation.ExistingGPOs` | Example GPO data used by the simulation configuration. |

## Usage

Run the main script from the repository root:

```powershell
.\07-GPO-Management\GPO-Management.ps1
```

### Interactive Menu

| Option | Operation |
|---|---|
| `1` | Check a GPO. |
| `2` | List GPOs. |
| `3` | Create a GPO. |
| `4` | Check a GPO's links. |
| `5` | List GPO links. |
| `0` | Exit. |

Follow the prompts to provide the GPO name and, when creating a GPO, its description.

## Tests

Run the module test script from the repository root:

```powershell
.\07-GPO-Management\Test-GPOManagement.ps1
```

The current test suite has passed 21 tests in simulation. These results do not, by themselves, verify operations against a real Active Directory environment.

## Security Notes

- Keep local configuration files out of version control.
- Never commit passwords, access tokens, or other secrets.
- Keep simulation mode enabled while testing.
- Review configuration and operation flags before execution.
- Use only the permissions necessary for the intended operations.
- Verify the target domain and domain controller before performing real GPO operations.
- Review the implementation and test results before production use.
