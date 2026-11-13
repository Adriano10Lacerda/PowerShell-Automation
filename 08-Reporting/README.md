# Reporting

## Overview

The Reporting module collects and processes configured report source files, generates a summary of the processing results, and exports reporting output in the configured formats.

The module uses a JSON configuration file and provides an interactive PowerShell menu to execute reporting, view a summary, list configured sources, and inspect source files.

## Features

- Process files from configured reporting sources.
- Generate a reporting summary.
- Include summary, details, and timestamps according to configuration.
- Export summary and detail rows as separate CSV files when both are enabled.
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
| `SimulationMode` | Must be Boolean. `true` reads enabled sources only when `-AllowRealRead` is explicitly supplied and previews outputs without writing; `false` requires separate read and write authorization. |
| `Reporting.IncludeSummary` | Boolean. Includes/removes the summary in JSON and controls the summary CSV. |
| `Reporting.IncludeDetails` | Boolean. Includes/removes source details in JSON and controls the details CSV. |
| `Reporting.IncludeTimestamp` | Boolean. Includes/removes report timestamps from exported content. Filenames remain timestamped. |
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

Run the main script from the repository root. Source enumeration and reading require the explicit `-AllowRealRead` opt-in, including while `SimulationMode` is enabled. `-Preview`/`-WhatIf` return before source enumeration or reading. A real export additionally requires separate `-AllowRealOperation`, `ShouldProcess` confirmation, and an explicit operator-selected local `-AllowedRoot`:

```powershell
.\08-Reporting\Reporting.ps1 -AllowRealRead
```

For an actual export, pass both opt-ins and the reviewed local output root:

```powershell
.\08-Reporting\Reporting.ps1 -AllowRealRead -AllowRealOperation -AllowedRoot 'C:\Reports'
```

Exports use unique names and exclusive file creation; existing output files are never overwritten. If a later format fails after an earlier file was created, the result reports failure and preserves the partial artifacts for review.

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

Run the isolated automated test script from the repository root:

```powershell
.\08-Reporting\Test-Reporting.ps1
```

Review the test results before using the module. Tests performed with simulated data do not, by themselves, prove that real source files can be processed successfully in every target environment.

The test script creates its own dummy CSV/JSON input files and temporary output
directories. It does not read the local `Reporting-Configuration.json` or
existing report files. The temporary test workspace is removed in `finally`.

Historical evidence: an earlier isolated run completed 27/27 checks with exit
code 0 on PowerShell 7.6.9. That result predates the explicit read opt-in and
exclusive output creation changes. The current 33-check suite has not been
executed after those changes; do not treat the historical result as current
validation or as a test against live source data.

## Security and Operational Notes

- Keep local configuration files out of version control when they contain environment-specific settings.
- Never commit passwords, access tokens, or other secrets.
- Verify source directories and file patterns before execution.
- Review enabled sources before passing `-AllowRealRead`.
- Pass `-AllowRealOperation` separately for export and use `ShouldProcess` confirmation.
- Select an existing local `-AllowedRoot`; real exports require it explicitly.
- Simulation mode suppresses output writes; enabled source files are still read when `-AllowRealRead` is supplied.
- Validate generated reports before relying on them for operational decisions.

An exported result is unsuccessful if any source file could not be parsed, even
when a partial report was successfully generated.
