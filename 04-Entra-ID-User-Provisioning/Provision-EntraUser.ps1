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

$Configuration = Get-Content $ConfigurationPath -Raw | ConvertFrom-Json


Write-Host ""
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "       Entra ID User Provisioning       " -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host ""


try {

    # Validação da configuração
    $null = Test-EntraConfiguration -Configuration $Configuration

    Write-Host "Configuration validated successfully." -ForegroundColor Green
    Write-Host ""


    # Em Simulation Mode não existe autenticação no Microsoft Graph.
    if ($Configuration.SimulationMode) {

        Write-Host "Simulation Mode: ENABLED" -ForegroundColor Yellow
        Write-Host "No changes will be made to Entra ID." -ForegroundColor Yellow
        Write-Host ""

    }
    else {

        Write-Host "Simulation Mode: DISABLED" -ForegroundColor Yellow
        Write-Host "Real Entra ID operation selected." -ForegroundColor Yellow
        Write-Host ""

        # Somente no modo real validamos o tenant através do Graph.
        $Connection = Test-EntraTenantConnection `
            -Configuration $Configuration

        Write-Host "Tenant connection validated successfully." -ForegroundColor Green
        Write-Host ""
    }


    # Entrada dos dados
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


    # Obtém o domínio configurado
    $Domain = $Configuration.UserPrincipalName.Domain

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        throw "UserPrincipalName.Domain is not configured."
    }


    # Geração do UPN
    $NormalizedFirstName = ConvertTo-EntraIdentifier $FirstName
    $NormalizedLastName = ConvertTo-EntraIdentifier $LastName

    $UserPrincipalName = "$NormalizedFirstName.$NormalizedLastName@$Domain"

    $UserPrincipalName = $UserPrincipalName.ToLower()

    Write-Host ""
    Write-Host "User to be provisioned:" -ForegroundColor Cyan
    Write-Host "First Name          : $FirstName"
    Write-Host "Last Name           : $LastName"
    Write-Host "User Principal Name : $UserPrincipalName"
    Write-Host ""


    # Objeto padronizado utilizado pela função de provisionamento
    $User = [PSCustomObject]@{

    FirstName         = $FirstName
    LastName          = $LastName
    DisplayName       = "$FirstName $LastName"
    GivenName         = $FirstName
    Surname           = $LastName
    UserPrincipalName = $UserPrincipalName
    MailNickname = "$NormalizedFirstName.$NormalizedLastName".ToLower()
    AccountEnabled    = $true
    }


    # Provisionamento
    New-EntraUserProvision `
        -Configuration $Configuration `
        -User $User


    Write-Host ""
    Write-Host "Provisioning completed successfully." -ForegroundColor Green

}
catch {

    Write-Host ""
    Write-Host "Provisioning failed." -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}


Write-Host ""
Read-Host "Press Enter to continue"