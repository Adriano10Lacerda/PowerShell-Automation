$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Entra-Functions.psm1"
$ConfigurationPath = Join-Path $PSScriptRoot "Entra-Configuration.json"

if (-not (Test-Path $ModulePath)) {
    throw "Entra-Functions.psm1 não encontrado."
}

if (-not (Test-Path $ConfigurationPath)) {
    throw "Entra-Configuration.json não encontrado."
}

Import-Module $ModulePath -Force

$Configuration = Get-Content $ConfigurationPath -Raw |
    ConvertFrom-Json

Write-Host ""
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "       Entra ID User Provisioning       " -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host ""

try {

    # ============================================================
    # CONFIGURATION VALIDATION
    # ============================================================

    $null = Test-EntraConfiguration `
                -Configuration $Configuration

    Write-Host "Configuration validated successfully." -ForegroundColor Green
    Write-Host ""

    # ============================================================
    # CONNECTION VALIDATION
    # ============================================================

    if ($Configuration.SimulationMode) {

        Write-Host "Simulation Mode: ENABLED" -ForegroundColor Yellow
        Write-Host "No changes will be made to Entra ID." -ForegroundColor Yellow
        Write-Host ""
    }
    else {

        Write-Host "Simulation Mode: DISABLED" -ForegroundColor Yellow
        Write-Host "REAL Entra ID operation selected." -ForegroundColor Red
        Write-Host ""

        $Connection = Test-EntraTenantConnection `
            -Configuration $Configuration

        Write-Host "Tenant connection validated successfully." -ForegroundColor Green
        Write-Host ""
        Write-Host "Tenant ID : $($Connection.TenantId)"
        Write-Host "Account   : $($Connection.Account)"
        Write-Host ""
    }

    # ============================================================
    # USER INPUT
    # ============================================================

    $FirstName = Read-Host "First Name"
    $LastName = Read-Host "Last Name"

    if ([string]::IsNullOrWhiteSpace($FirstName)) {
        throw "First Name cannot be empty."
    }

    if ([string]::IsNullOrWhiteSpace($LastName)) {
        throw "Last Name cannot be empty."
    }

    $FirstName = $FirstName.Trim()
    $LastName = $LastName.Trim()

    # ============================================================
    # NORMALIZE USER IDENTIFIERS
    # ============================================================

    $NormalizedFirstName = ConvertTo-EntraIdentifier `
        -Text $FirstName

    $NormalizedLastName = ConvertTo-EntraIdentifier `
        -Text $LastName

    if ([string]::IsNullOrWhiteSpace($NormalizedFirstName)) {
        throw "Não foi possível gerar um identificador válido para o First Name."
    }

    if ([string]::IsNullOrWhiteSpace($NormalizedLastName)) {
        throw "Não foi possível gerar um identificador válido para o Last Name."
    }

    # ============================================================
    # UPN DOMAIN
    # ============================================================

    $Domain = $Configuration.UserPrincipalName.Domain

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        throw "UserPrincipalName.Domain is not configured."
    }

    $UserPrincipalName = "$NormalizedFirstName.$NormalizedLastName@$Domain"
    $UserPrincipalName = $UserPrincipalName.ToLower()

    # ============================================================
    # MAIL NICKNAME
    # ============================================================

    $MailNickname = "$NormalizedFirstName.$NormalizedLastName"
    $MailNickname = $MailNickname.ToLower()

    # ============================================================
    # USER OBJECT
    # ============================================================

    $User = [PSCustomObject]@{
        FirstName         = $FirstName
        LastName          = $LastName
        DisplayName       = "$FirstName $LastName"
        GivenName         = $FirstName
        Surname           = $LastName
        UserPrincipalName = $UserPrincipalName
        MailNickname      = $MailNickname
        AccountEnabled    = $true
    }

    # ============================================================
    # DISPLAY USER
    # ============================================================

    Write-Host ""
    Write-Host "User to be provisioned:" -ForegroundColor Cyan
    Write-Host "----------------------------------------"
    Write-Host "First Name          : $($User.FirstName)"
    Write-Host "Last Name           : $($User.LastName)"
    Write-Host "Display Name        : $($User.DisplayName)"
    Write-Host "User Principal Name : $($User.UserPrincipalName)"
    Write-Host "Mail Nickname       : $($User.MailNickname)"
    Write-Host "Account Enabled     : $($User.AccountEnabled)"
    Write-Host "----------------------------------------"
    Write-Host ""

    # ============================================================
    # VALIDATE USER
    # ============================================================

    $null = Test-EntraUserProvisioning `
          -User $User `
          -Configuration $Configuration

    # ============================================================
    # DUPLICATE CHECK
    # ============================================================

    $ExistingUser = Test-EntraUserExists `
        -Configuration $Configuration `
        -UserPrincipalName $User.UserPrincipalName

    if ($ExistingUser) {

        throw "A user with the UPN '$($User.UserPrincipalName)' already exists."
    }

    Write-Host "User validation completed successfully." -ForegroundColor Green
    Write-Host ""

    # ============================================================
    # EXPLICIT CONFIRMATION
    # ============================================================

    if ($Configuration.SimulationMode) {

        Write-Host "Simulation Mode is ENABLED." -ForegroundColor Yellow
        Write-Host "The following operation is only a simulation." -ForegroundColor Yellow
        Write-Host ""
    }
    else {

        Write-Host "WARNING: THIS WILL CREATE A REAL USER." -ForegroundColor Red
        Write-Host "Tenant : $($Configuration.TenantId)" -ForegroundColor Red
        Write-Host "UPN    : $($User.UserPrincipalName)" -ForegroundColor Red
        Write-Host ""
    }

    $Confirmation = Read-Host "Confirm provisioning? [Y/N]"

    if ($Confirmation -notmatch '^(Y|y|S|s)$') {

        Write-Host ""
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        return
    }

    # ============================================================
    # PROVISION
    # ============================================================

    $Result = New-EntraUserProvision `
        -Configuration $Configuration `
        -User $User

    # ============================================================
    # RESULT
    # ============================================================

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "       Provisioning Result              " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    $Result |
        Format-List

    if ($Result.Simulation) {

        Write-Host "Simulation completed successfully." -ForegroundColor Yellow
        Write-Host "No changes were made to Entra ID." -ForegroundColor Yellow
    }
    else {

        Write-Host "REAL user created successfully." -ForegroundColor Green
    }
}
catch {

    Write-Host ""
    Write-Host "Provisioning failed." -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to continue"