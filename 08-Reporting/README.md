# Reporting

## Overview

The Reporting module collects and processes configured report source files, generates a summary of the processing results, and exports reporting output in the configured formats.

The module uses a JSON configuration file and provides an interactive PowerShell menu to execute reporting, view a summary, list configured sources, and inspect source files.

## Features

- Process files from configured reporting sources.
- Generate a reporting summary.
- Include summary, details, and timestamps according to configuration.
- Configure JSON and CSV output formats.
- Enable or disable individual reporting sources.
- Configure source directories and file patterns.
- List configured sources and their status.
- Inspect available source files.
- Configure simulation mode.
- Validate configuration before execution.

## Project Files

| File | Description |
|---|---|
| `Reporting.ps1` | Main script and interactive menu. |
| `Reporting-Functions.psm1` | Reporting functions, processing logic, and configuration validation. |
| `Reporting-Configuration.example.json` | Example configuration file. |
| `Reporting-Configuration.json` | Local configuration used by the main script. |
| `Test-Reporting.ps1` | Automated test script. |

## Requirements

- Windows and PowerShell.
- Access to the configured source directories.
- Source files compatible with the configured file patterns and formats.
- Write permissions for the output directory.
- Appropriate configuration for the sources being processed.

## Configuration

1. Copy `Reporting-Configuration.example.json` to `Reporting-Configuration.json`.
2. Set `SimulationMode` according to the intended execution.
3. Configure the reporting options.
4. Set the output directory and supported output formats.
5. Enable the required sources.
6. Configure each enabled source's directory, file pattern, and input formats.

Keep simulation mode enabled while testing. Review `Reporting-Functions.psm1` to understand the actual behavior of simulation mode before using the module in a production environment.

### Configuration Reference

| Setting | Description |
|---|---|
| `SimulationMode` | Configures simulation mode. |
| `Reporting.IncludeSummary` | Controls whether the report includes a summary. |
| `Reporting.IncludeDetails` | Controls whether report details are included. |
| `Reporting.IncludeTimestamp` | Controls whether a timestamp is included. |
| `Output.Directory` | Destination directory for generated reports. |
| `Output.Formats` | Configured output formats, such as JSON and CSV. |
| `Sources.ComputerInventory.Enabled` | Enables or disables the computer inventory source. |
| `Sources.ADUsers.Enabled` | Enables or disables the Active Directory users source. |
| `Sources.ADGroups.Enabled` | Enables or disables the Active Directory groups source. |
| `Sources.GPOs.Enabled` | Enables or disables the Group Policy Objects source. |
| `Sources.EntraUsers.Enabled` | Enables or disables the Microsoft Entra ID users source. |
| `Sources.*.Directory` | Directory containing files for the source. |
| `Sources.*.FilePattern` | File pattern used to locate source files. |
| `Sources.*.Formats` | Configured input formats for the source. |

In the example configuration, all five sources are disabled by default. Their directories are empty and should be configured before enabling them.

## Usage

Run the main script from the repository root:

```powershell
.\08-Reporting\Reporting.ps1
```

### Interactive Menu

| Option | Operation |
|---|---|
| `1` | Execute reporting. |
| `2` | View the reporting summary. |
| `3` | List configured sources. |
| `4` | List source files for enabled sources. |
| `0` | Exit. |

When reporting executes, the script displays processing totals, successful and failed file counts, generated file paths, and the output directory.

## Tests

Run the automated test script from the repository root:

```powershell
.\08-Reporting\Test-Reporting.ps1
```

Review the test results before using the module. Tests performed with simulated data do not, by themselves, prove that real source files can be processed successfully in every target environment.

## Security and Operational Notes

- Keep local configuration files out of version control when they contain environment-specific settings.
- Never commit passwords, access tokens, or other secrets.
- Verify source directories and file patterns before execution.
- Confirm that the output directory is appropriate and writable.
- Review simulation mode and enabled sources before processing.
- Validate generated reports before relying on them for operational decisions.
