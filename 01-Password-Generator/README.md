# Enterprise Password Generator

## Overview

A PowerShell-based password generator designed to automate secure password creation for IT and Windows administration environments.

This module is part of the **PowerShell-Automation** toolkit and focuses on secure random generation, input validation, configuration management, and maintainability.

## Features

- Cryptographically secure random number generation
- Configurable random password segment length
- Uppercase and lowercase characters
- Numeric characters
- Configurable special characters
- Configurable password prefix
- Configurable date format
- Input validation and error handling
- Required character categories
- Randomized character positions
- Automated tests

## Project Structure

```text
01-Password-Generator/
├── Generate-Password.ps1
├── Password-Functions.psm1
├── Test-PasswordGenerator.ps1
└── README.md
```

## Configuration

The generator uses a JSON configuration file located in the `02-Configuration` module.

Configuration file:

```text
02-Configuration/config.json
```

Example:

```json
{
  "Prefixo": "EMP",
  "QuantidadeCaracteres": 12,
  "FormatoData": "ddMM",
  "CaracteresEspeciais": "!@#$%&*"
}
```

### Configuration Parameters

| Parameter | Description |
|---|---|
| `Prefixo` | Prefix included at the beginning of the generated password |
| `QuantidadeCaracteres` | Number of characters in the random password segment |
| `FormatoData` | Date format included in the password |
| `CaracteresEspeciais` | Allowed special characters for random generation |

### Password Length

The `QuantidadeCaracteres` parameter defines the length of the **random segment**, not the total password length.

The final password is composed of:

```text
Prefix + Date + Random Segment
```

For example, with the configuration above:

- Prefix: `EMP` — 3 characters
- Date: `ddMM` — 4 characters
- Random segment: 12 characters
- Total password length: 19 characters

The actual generated password is random and will vary with each execution.

### Supported Date Formats

The following date formats are supported:

- `ddMM` — day and month
- `dd/MM/yyyy` — day, month, and four-digit year
- `yyyy-MM-dd` — year, month, and day

Unsupported formats are rejected during configuration validation.

## Security

The password generator uses:

```powershell
[System.Security.Cryptography.RandomNumberGenerator]::GetInt32()
```

This provides cryptographically secure random values for character selection.

The generated random segment includes at least one character from each of the following categories:

- Uppercase letters
- Lowercase letters
- Numeric characters
- Special characters

The required characters are shuffled using the Fisher-Yates algorithm before the remaining random characters are generated.

The final password is assembled by combining the configured prefix, formatted date, and random segment.

## Usage

Run the generator from the repository root:

```powershell
.\01-Password-Generator\Generate-Password.ps1
```

The script loads and validates the configuration from:

```text
02-Configuration/config.json
```

To change the generated password settings, update the configuration file before running the script.

### Example Output

The script displays:

- Configured prefix
- Formatted date
- Random segment length
- Generated password

**Security note:** Avoid sharing generated passwords or including them in screenshots, logs, or public repositories.

## Testing

Run the automated password generator tests:

```powershell
.\01-Password-Generator\Test-PasswordGenerator.ps1
```

The automated tests cover password generation and validation behavior, including:

- Password generation
- Required character categories
- Password length boundaries
- Configuration validation
- Supported date formats
- Invalid date formats
- Special character validation
- Invalid configuration values

The configuration module also has its own automated test suite:

```powershell
.\02-Configuration\Test-Configuration.ps1
```

## Technologies

- PowerShell 7
- Windows
- .NET cryptographic APIs
- Visual Studio Code

## Project Status

The Password Generator module has undergone automated testing and documentation review as part of the PowerShell-Automation V1 validation process.

The final V1 release remains subject to the overall repository review, including documentation, security, integration readiness, and regression testing.

## Related Modules

- [Configuration](../02-Configuration/README.md) — configuration loading and validation
- [PowerShell-Automation](../README.md) — main toolkit documentation
