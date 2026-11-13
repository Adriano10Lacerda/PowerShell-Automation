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
| `Test-Interface-Demo.ps1` | Offline Demo checks with controlled input and fail-closed sentinels; not yet run. |

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

### Offline Demo / ViewOnly

Run the launcher as a script with `-Demo` to browse embedded fictional pages:

```powershell
.\09-Interface\Interface.ps1 -Demo
```

The Demo branch runs before normal initialization. It does not import project
modules, inspect files, load JSON, launch auxiliary scripts, query host identity,
or contact AD, Graph, GPO, CIM, BitLocker, or the network. Options `1`-`8` only
display static examples; ENTER returns to the menu and `0` returns from the script
without closing the caller's PowerShell process. No password is generated and
no administrative action or export is available. Input/output errors terminate
the Demo without falling back to normal startup.

Omitting `-Demo`, or supplying `-Demo:$false`, retains the existing normal flow.
Invoke the launcher as a script, not by dot-sourcing it. This is a console Demo,
not the WPF GUI, and it does not validate any real administrative capability.
It introduces no PowerShell 7-only syntax; Windows PowerShell 5.1 and PowerShell 7
functional compatibility still require authorized testing. The V1-wide PowerShell 7
baseline remains unchanged. For a clean process, use `-NoProfile` when starting
the chosen PowerShell runtime; no execution-policy bypass is required by this mode.

`Test-Interface-Demo.ps1` is prepared but **NOT RUN**. It reads only the launcher
source for static checks, then uses in-memory input/output fixtures, command
sentinels, and normal-startup stubs. It requires no Pester, RSAT, Graph, Git,
temporary files, or project-module imports. Run it only after separate authorization.

### Normal Interactive Menu

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
