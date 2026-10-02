#Requires -Version 5.1

<#
.SYNOPSIS
    Testes da Interface Central V2.

.DESCRIPTION
    Valida a estrutura, funções, integração com Computer Management
    e arquivos necessários da Interface V2.

.NOTES
    V2 - Interface Central
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
Write-Host "        TESTES - INTERFACE V2" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$functionsPath = Join-Path `
    $PSScriptRoot `
    "Interface-V2-Functions.psm1"

$launcherPath = Join-Path `
    $PSScriptRoot `
    "Interface-V2.ps1"

$computerManagementPath = Join-Path `
    $PSScriptRoot `
    "..\Core\Computer\Management\Computer-Management.psm1"

# ============================================================
# TESTES DE ARQUIVOS
# ============================================================

Write-TestResult `
    "Interface-V2-Functions.psm1 existe" `
    (Test-Path -LiteralPath $functionsPath)

Write-TestResult `
    "Interface-V2.ps1 existe" `
    (Test-Path -LiteralPath $launcherPath)

Write-TestResult `
    "Computer-Management.psm1 existe" `
    (Test-Path -LiteralPath $computerManagementPath)

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
    "Interface V2 importa sem erro" `
    $moduleImported

# ============================================================
# FUNÇÕES
# ============================================================

$expectedFunctions = @(
    "Write-V2Header",
    "Pause-V2",
    "Show-V2DevelopmentMessage",
    "Start-V2ComputerManagement",
    "Show-V2MainMenu",
    "Start-V2Interface"
)

foreach ($functionName in $expectedFunctions) {

    $command = Get-Command `
        $functionName `
        -ErrorAction SilentlyContinue

    Write-TestResult `
        "Função '$functionName' disponível" `
        ($null -ne $command)
}

# ============================================================
# CONTEÚDO DO LAUNCHER
# ============================================================

$launcherContent = ""

try {
    $launcherContent = Get-Content `
        -LiteralPath $launcherPath `
        -Raw `
        -ErrorAction Stop
}
catch {
    $launcherContent = ""
}

Write-TestResult `
    "Launcher referencia Interface-V2-Functions.psm1" `
    ($launcherContent -match "Interface-V2-Functions\.psm1")

Write-TestResult `
    "Launcher chama Start-V2Interface" `
    ($launcherContent -match "Start-V2Interface")

# ============================================================
# CONTEÚDO DO MÓDULO
# ============================================================

$moduleContent = ""

try {
    $moduleContent = Get-Content `
        -LiteralPath $functionsPath `
        -Raw `
        -ErrorAction Stop
}
catch {
    $moduleContent = ""
}

Write-TestResult `
    "Menu contém Users" `
    ($moduleContent -match "Users")

Write-TestResult `
    "Menu contém Accounts" `
    ($moduleContent -match "Accounts")

Write-TestResult `
    "Menu contém Groups" `
    ($moduleContent -match "Groups")

Write-TestResult `
    "Menu contém Computers" `
    ($moduleContent -match "Computers")

Write-TestResult `
    "Menu contém Policies" `
    ($moduleContent -match "Policies")

Write-TestResult `
    "Menu contém Reports" `
    ($moduleContent -match "Reports")

Write-TestResult `
    "Menu contém Settings" `
    ($moduleContent -match "Settings")

Write-TestResult `
    "Menu contém Exit" `
    ($moduleContent -match "Exit")

Write-TestResult `
    "Computer Management é integrado" `
    ($moduleContent -match "Computer-Management\.psm1")

Write-TestResult `
    "Get-ComputerManagementSummary é utilizado" `
    ($moduleContent -match "Get-ComputerManagementSummary")

Write-TestResult `
    "Hostname é solicitado ao operador" `
    ($moduleContent -match 'Read-Host "  Hostname"')

Write-TestResult `
    "Modo simulação é apresentado" `
    ($moduleContent -match "SimulationMode")

Write-TestResult `
    "Erros da consulta são tratados" `
    ($moduleContent -match "ErrorCount")

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
Write-Host "FAIL  : $script:Failed" -ForegroundColor $(if ($script:Failed -eq 0) { "Green" } else { "Red" })

Write-Host ""

if ($script:Failed -eq 0) {
    Write-Host "INTERFACE V2: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "INTERFACE V2: EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}