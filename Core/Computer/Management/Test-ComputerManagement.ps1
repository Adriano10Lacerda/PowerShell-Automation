$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        $script:Failed++
    }
}

$modulePath = Join-Path $PSScriptRoot "Computer-Management.psm1"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " COMPUTER MANAGEMENT - TESTES" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

try {
    Import-Module $modulePath -Force
    Assert-Test "Modulo Computer-Management carregado." $true
}
catch {
    Assert-Test "Modulo Computer-Management carregado." $false
    Write-Host ""
    Write-Host "Erro ao carregar modulo:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}


# --------------------------------------------------
# TESTES DE DISPONIBILIDADE
# --------------------------------------------------

Assert-Test `
    "Get-ComputerManagement disponivel" `
    ($null -ne (Get-Command Get-ComputerManagement -ErrorAction SilentlyContinue))

Assert-Test `
    "Get-ComputerManagementSummary disponivel" `
    ($null -ne (Get-Command Get-ComputerManagementSummary -ErrorAction SilentlyContinue))

Assert-Test `
    "Test-ComputerManagement disponivel" `
    ($null -ne (Get-Command Test-ComputerManagement -ErrorAction SilentlyContinue))


# --------------------------------------------------
# TESTE DO MANAGEMENT
# --------------------------------------------------

$moduleTest = Test-ComputerManagement

Assert-Test `
    "Test-ComputerManagement executado" `
    ($null -ne $moduleTest)

Assert-Test `
    "Computer Core disponivel" `
    ($moduleTest.ComputerCoreAvailable -eq $true)

Assert-Test `
    "Computer Management disponivel" `
    ($moduleTest.ManagementAvailable -eq $true)


# --------------------------------------------------
# CONSULTA REAL
# --------------------------------------------------

$hostname = $env:COMPUTERNAME

Write-Host ""
Write-Host "Consultando computador local: $hostname" -ForegroundColor Yellow
Write-Host ""

$result = Get-ComputerManagement `
    -Hostname $hostname `
    -SimulationMode


Assert-Test `
    "Resultado da consulta não é nulo" `
    ($null -ne $result)

Assert-Test `
    "Hostname retornado" `
    ($result.Hostname -eq $hostname.ToUpperInvariant())

Assert-Test `
    "SimulationMode identificado" `
    ($result.SimulationMode -eq $true)

Assert-Test `
    "Status retornado" `
    (-not [string]::IsNullOrWhiteSpace($result.Status))

Assert-Test `
    "Summary retornado" `
    ($null -ne $result.Summary)

Assert-Test `
    "Data retornada" `
    ($null -ne $result.Data)

Assert-Test `
    "Errors retornado" `
    ($null -ne $result.Errors)


# --------------------------------------------------
# TESTES DO SUMMARY
# --------------------------------------------------

if ($null -ne $result.Summary) {

    Assert-Test `
        "Summary possui Hostname" `
        ($result.Summary.Hostname -eq $hostname.ToUpperInvariant())

    Assert-Test `
        "Summary possui Status" `
        (-not [string]::IsNullOrWhiteSpace($result.Summary.Status))

    Assert-Test `
        "Summary possui ADFound" `
        ($null -ne $result.Summary.ADFound)

    Assert-Test `
        "Summary possui Reachable" `
        ($null -ne $result.Summary.Reachable)

    Assert-Test `
        "Summary possui ErrorCount" `
        ($null -ne $result.Summary.ErrorCount)

    Assert-Test `
        "Summary possui SimulationMode" `
        ($result.Summary.SimulationMode -eq $true)
}
else {
    Assert-Test "Summary possui Hostname" $false
    Assert-Test "Summary possui Status" $false
    Assert-Test "Summary possui ADFound" $false
    Assert-Test "Summary possui Reachable" $false
    Assert-Test "Summary possui ErrorCount" $false
    Assert-Test "Summary possui SimulationMode" $false
}


# --------------------------------------------------
# TESTES DO CORE DENTRO DO MANAGEMENT
# --------------------------------------------------

if ($null -ne $result.Data) {

    Assert-Test `
        "Data possui Hostname" `
        ($null -ne $result.Data.Hostname)

    Assert-Test `
        "Data possui CollectionDateTime" `
        ($null -ne $result.Data.CollectionDateTime)

    Assert-Test `
        "Data possui AD" `
        ($null -ne $result.Data.AD)

    Assert-Test `
        "Data possui Connectivity" `
        ($null -ne $result.Data.Connectivity)

    Assert-Test `
        "Data possui System" `
        ($null -ne $result.Data.System)

    Assert-Test `
        "Data possui OperatingSystem" `
        ($null -ne $result.Data.OperatingSystem)

    Assert-Test `
        "Data possui Processor" `
        ($null -ne $result.Data.Processor)

    Assert-Test `
        "Data possui Memory" `
        ($null -ne $result.Data.Memory)

    Assert-Test `
        "Data possui Storage" `
        ($null -ne $result.Data.Storage)

    Assert-Test `
        "Data possui Network" `
        ($null -ne $result.Data.Network)

    Assert-Test `
        "Data possui BitLocker" `
        ($null -ne $result.Data.BitLocker)

    Assert-Test `
        "Data possui Errors" `
        ($null -ne $result.Data.Errors)
}
else {
    Assert-Test "Data possui Hostname" $false
    Assert-Test "Data possui CollectionDateTime" $false
    Assert-Test "Data possui AD" $false
    Assert-Test "Data possui Connectivity" $false
    Assert-Test "Data possui System" $false
    Assert-Test "Data possui OperatingSystem" $false
    Assert-Test "Data possui Processor" $false
    Assert-Test "Data possui Memory" $false
    Assert-Test "Data possui Storage" $false
    Assert-Test "Data possui Network" $false
    Assert-Test "Data possui BitLocker" $false
    Assert-Test "Data possui Errors" $false
}


# --------------------------------------------------
# TESTE DE SUMMARY ISOLADO
# --------------------------------------------------

$summary = Get-ComputerManagementSummary `
    -Hostname $hostname `
    -SimulationMode

Assert-Test `
    "Get-ComputerManagementSummary retornou resultado" `
    ($null -ne $summary)

Assert-Test `
    "Summary isolado possui Hostname" `
    ($null -ne $summary.Hostname)

Assert-Test `
    "Summary isolado possui Status" `
    (-not [string]::IsNullOrWhiteSpace($summary.Status))


# --------------------------------------------------
# TESTE DE HOSTNAME INVALIDO
# --------------------------------------------------

$invalidResult = Get-ComputerManagement `
    -Hostname "   " `
    -SimulationMode

Assert-Test `
    "Hostname invalido tratado sem crash" `
    ($null -ne $invalidResult)

Assert-Test `
    "Hostname invalido retorna Status Invalid" `
    ($invalidResult.Status -eq "Invalid")

Assert-Test `
    "Hostname invalido retorna Success False" `
    ($invalidResult.Success -eq $false)


# --------------------------------------------------
# TESTE JSON
# --------------------------------------------------

$json = $result | ConvertTo-Json -Depth 20

Assert-Test `
    "Resultado pode ser convertido para JSON" `
    (-not [string]::IsNullOrWhiteSpace($json))


# --------------------------------------------------
# RESUMO
# --------------------------------------------------

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $($script:Passed + $script:Failed)"
Write-Host "PASS  : $script:Passed" -ForegroundColor Green
Write-Host "FAIL  : $script:Failed" -ForegroundColor Red

Write-Host ""

if ($script:Failed -eq 0) {
    Write-Host "COMPUTER MANAGEMENT: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "COMPUTER MANAGEMENT: EXISTEM TESTES COM FALHA!" -ForegroundColor Red
    exit 1
}