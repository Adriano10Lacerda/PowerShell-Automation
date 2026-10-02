#Requires -Version 5.1

<#
.SYNOPSIS
    Testes do User Core V2.

.DESCRIPTION
    Valida modelos, consulta de usuário, Simulation Mode,
    usuários existentes/inexistentes e tratamento de erros.

.NOTES
    PowerShell Automation V2
#>

$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success
    )

    if ($Success) {
        Write-Host "PASSOU: $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "FALHOU: $Name" -ForegroundColor Red
        $script:Failed++
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             TESTES - USER CORE V2" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$modelsPath = Join-Path `
    $PSScriptRoot `
    "User-Models.ps1"

$functionsPath = Join-Path `
    $PSScriptRoot `
    "User-Functions.psm1"

Write-TestResult `
    "User-Models.ps1 existe" `
    (Test-Path -LiteralPath $modelsPath)

Write-TestResult `
    "User-Functions.psm1 existe" `
    (Test-Path -LiteralPath $functionsPath)

# ============================================================
# IMPORTAÇÃO
# ============================================================

$moduleImported = $false

try {

    Import-Module `
        $functionsPath `
        -Force `
        -ErrorAction Stop

    $moduleImported = $true
}
catch {

    $moduleImported = $false
}

Write-TestResult `
    "User Core importa sem erro" `
    $moduleImported

# ============================================================
# FUNÇÕES
# ============================================================

Write-TestResult `
    "Test-UserADExists disponível" `
    ($null -ne (Get-Command Test-UserADExists -ErrorAction SilentlyContinue))

Write-TestResult `
    "Get-UserADInfo disponível" `
    ($null -ne (Get-Command Get-UserADInfo -ErrorAction SilentlyContinue))

# ============================================================
# CONFIGURAÇÃO DE SIMULAÇÃO
# ============================================================

$configuration = [PSCustomObject]@{
    Domain           = "BRSPO"
    DomainController = ""
    TargetOU         = ""
    SimulationMode   = $true

    UserPrincipalName = [PSCustomObject]@{
        Enabled = $true
        Domain  = "example.local"
    }

    Simulation = [PSCustomObject]@{
        ExistingSamAccountNames = @(
            "silva.maria.ext",
            "silva.maria2.ext",
            "silva.maria3.ext"
        )
    }
}

Write-TestResult `
    "Configuração de simulação criada" `
    ($configuration.SimulationMode -eq $true)

# ============================================================
# TESTE 1 - USUÁRIO EXISTENTE
# ============================================================

$existsResult = Test-UserADExists `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Usuário existente é encontrado em Simulation Mode" `
    (
        $existsResult.Success -eq $true -and
        $existsResult.Data -eq $true
    )

# ============================================================
# TESTE 2 - USUÁRIO INEXISTENTE
# ============================================================

$notExistsResult = Test-UserADExists `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration

Write-TestResult `
    "Usuário inexistente é identificado corretamente" `
    (
        $notExistsResult.Success -eq $true -and
        $notExistsResult.Data -eq $false
    )

# ============================================================
# TESTE 3 - SAMACCOUNTNAME VAZIO
# ============================================================

$emptyResult = Test-UserADExists `
    -SamAccountName " " `
    -Configuration $configuration

Write-TestResult `
    "SamAccountName vazio gera erro controlado" `
    (
        $emptyResult.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($emptyResult.Error)
    )

# ============================================================
# TESTE 4 - CONSULTAR USUÁRIO EXISTENTE
# ============================================================

$userResult = Get-UserADInfo `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Consulta de usuário existente retorna sucesso" `
    (
        $userResult.Success -eq $true -and
        $null -ne $userResult.Data
    )

# ============================================================
# TESTE 5 - MODELO IDENTITY
# ============================================================

Write-TestResult `
    "Modelo Identity possui SamAccountName" `
    (
        $null -ne $userResult.Data.Identity -and
        $userResult.Data.Identity.SamAccountName -eq "silva.maria.ext"
    )

# ============================================================
# TESTE 6 - UPN
# ============================================================

Write-TestResult `
    "UPN é gerado no modelo de simulação" `
    (
        $userResult.Data.Identity.UserPrincipalName -eq
        "silva.maria.ext@example.local"
    )

# ============================================================
# TESTE 7 - DISTINGUISHED NAME
# ============================================================

Write-TestResult `
    "DistinguishedName está disponível" `
    (
        -not [string]::IsNullOrWhiteSpace(
            $userResult.Data.Identity.DistinguishedName
        )
    )

# ============================================================
# TESTE 8 - DISPLAY NAME
# ============================================================

Write-TestResult `
    "DisplayName está disponível" `
    (
        -not [string]::IsNullOrWhiteSpace(
            $userResult.Data.Personal.DisplayName
        )
    )

# ============================================================
# TESTE 9 - ACCOUNT ENABLED
# ============================================================

Write-TestResult `
    "Status Enabled está disponível" `
    (
        $null -ne $userResult.Data.Account.Enabled
    )

# ============================================================
# TESTE 10 - LOCKED OUT
# ============================================================

Write-TestResult `
    "Status LockedOut está disponível" `
    (
        $null -ne $userResult.Data.Account.LockedOut
    )

# ============================================================
# TESTE 11 - PASSWORD EXPIRED
# ============================================================

Write-TestResult `
    "PasswordExpired está disponível" `
    (
        $null -ne $userResult.Data.Account.PasswordExpired
    )

# ============================================================
# TESTE 12 - ACTIVITY
# ============================================================

Write-TestResult `
    "Modelo Activity está disponível" `
    (
        $null -ne $userResult.Data.Activity
    )

# ============================================================
# TESTE 13 - GROUPS
# ============================================================

Write-TestResult `
    "Modelo Groups está disponível" `
    (
        $null -ne $userResult.Data.Groups
    )

# ============================================================
# TESTE 14 - USUÁRIO INEXISTENTE
# ============================================================

$missingUserResult = Get-UserADInfo `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration

Write-TestResult `
    "Consulta de usuário inexistente gera erro controlado" `
    (
        $missingUserResult.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($missingUserResult.Error)
    )

# ============================================================
# TESTE 15 - MODULE ACTIVE DIRECTORY INDISPONÍVEL
# ============================================================

$realConfiguration = [PSCustomObject]@{
    Domain           = "BRSPO"
    DomainController = "dc.invalid.local"
    SimulationMode   = $false

    UserPrincipalName = [PSCustomObject]@{
        Enabled = $true
        Domain  = "example.local"
    }
}

$realResult = Test-UserADExists `
    -SamAccountName "teste" `
    -Configuration $realConfiguration

$realHandled =
    (
        $realResult.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($realResult.Error)
    )

Write-TestResult `
    "Erro de ambiente real é tratado sem exceção não controlada" `
    $realHandled

# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RESULTADO DOS TESTES" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $($script:Passed + $script:Failed)"
Write-Host "PASS  : $script:Passed" -ForegroundColor Green

if ($script:Failed -eq 0) {
    Write-Host "FAIL  : $script:Failed" -ForegroundColor Green
}
else {
    Write-Host "FAIL  : $script:Failed" -ForegroundColor Red
}

Write-Host ""

if ($script:Failed -eq 0) {
    Write-Host "USER CORE: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "USER CORE: EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}