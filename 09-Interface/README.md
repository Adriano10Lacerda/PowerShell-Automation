# PowerShell Automation Toolkit — Interface

## Overview

The Interface module provides an interactive command-line menu for the PowerShell Automation Toolkit. It serves as a central entry point for launching the toolkit's main modules.

The interface imports its function module, checks whether the selected script exists, launches the requested module, and handles execution errors.

## Features

- Centralized interactive menu.
- Launch the Password Generator.
- Launch the Configuration Validator.
- Launch Active Directory user provisioning.
- Launch Microsoft Entra ID user provisioning.
- Launch Computer Inventory.
- Launch Active Directory Group Management.
- Launch Group Policy Object (GPO) Management.
- Launch Reporting.
- Validate the existence of module scripts before execution.
- Display error messages when a module fails.
- Return to the menu after an operation.

## Project Files

| File | Description |
|---|---|
| `Interface.ps1` | Main script that displays the menu and routes user selections. |
| `Interface-Functions.psm1` | Functions that locate and launch the individual modules. |
| `Test-Interface.ps1` | Automated test script for the interface module. |

## Requirements

- Windows and PowerShell.
- The PowerShell Automation Toolkit repository with its expected directory structure.
- The scripts for the modules being launched.
- Any additional requirements and permissions needed by the selected module.

## Usage

From the repository root, run:

```powershell id="0g4yzt"
.\09-Interface\Interface.ps1
```

### Interactive Menu

| Option | Module |
|---|---|
| `1` | Password Generator |
| `2` | Active Directory User Provisioning |
| `3` | Microsoft Entra ID User Provisioning |
| `4` | Computer Inventory |
| `5` | Active Directory Group Management |
| `6` | GPO Management |
| `7` | Reporting |
| `8` | Configuration Validator |
| `0` | Exit |

Select an option to launch the corresponding script. After the selected operation completes, the interface pauses before returning to the menu.

If a required script is missing or an execution error occurs, the interface displays an error message.

## Module Integration

The interface invokes the following scripts relative to the toolkit directory:

| Module | Script |
|---|---|
| Password Generator | `01-Password-Generator\Generate-Password.ps1` |
| Configuration Validator | `02-Configuration\Validate-Configuration.ps1` |
| AD User Provisioning | `03-AD-User-Provisioning\Provision-ADUser.ps1` |
| Entra ID User Provisioning | `04-Entra-ID-User-Provisioning\Provision-EntraUser.ps1` |
| Computer Inventory | `05-Computer-Inventory\Computer-Inventory.ps1` |
| AD Group Management | `06-AD-Group-Management\AD-Group-Management.ps1` |
| GPO Management | `07-GPO-Management\GPO-Management.ps1` |
| Reporting | `08-Reporting\Reporting.ps1` |

## Tests

Run the automated test script from the repository root:

```powershell id="8tb8dt"
.\09-Interface\Test-Interface.ps1
```

Review the test results before relying on the interface. Interface tests do not replace testing the individual modules and their required environment-specific permissions.

## Operational Notes

- Run the interface from the repository root when following the documented command.
- Keep the toolkit's expected directory structure intact.
- Ensure that the selected module's script and configuration files are present.
- Review error messages when a module cannot be launched.
- Apply the security controls and permissions required by each individual module.
