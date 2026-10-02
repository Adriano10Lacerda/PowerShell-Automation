#Requires -Version 5.1

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
Write-Host "             TESTES - AUDIT CORE V2" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$modelsPath = Join-Path $PSScriptRoot "Audit-Models.ps1"
$functionsPath = Join-Path $PSScriptRoot "Audit-Functions.psm1"

Write-TestResult `
    "Audit-Models.ps1 existe" `
    (Test-Path -LiteralPath $modelsPath)

Write-TestResult `
    "Audit-Functions.psm1 existe" `
    (Test-Path -LiteralPath $functionsPath)

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
    "Audit Core importa sem erro" `
    $moduleImported

Write-TestResult `
    "New-AuditRecord disponível" `
    ($null -ne (
        Get-Command New-AuditRecord -ErrorAction SilentlyContinue
    ))

Write-TestResult `
    "Test-AuditRecord disponível" `
    ($null -ne (
        Get-Command Test-AuditRecord -ErrorAction SilentlyContinue
    ))

$auditResult = New-AuditRecord `
    -Action "UnlockUserAccount" `
    -SamAccountName "silva.maria.ext" `
    -Result "Simulated" `
    -SimulationMode $true `
    -Changed $false `
    -Operator "TESTUSER"

Write-TestResult `
    "Criação do registro retorna sucesso" `
    ($auditResult.Success -eq $true)

Write-TestResult `
    "Registro retornado em Data" `
    ($null -ne $auditResult.Data)

$record = $auditResult.Data

Write-TestResult `
    "Registro possui Timestamp" `
    ($null -ne $record.Timestamp)

Write-TestResult `
    "Registro possui Operator" `
    ($record.Operator -eq "TESTUSER")

Write-TestResult `
    "Registro possui Action" `
    ($record.Action -eq "UnlockUserAccount")

Write-TestResult `
    "Registro possui SamAccountName" `
    ($record.SamAccountName -eq "silva.maria.ext")

Write-TestResult `
    "Registro possui Result" `
    ($record.Result -eq "Simulated")

Write-TestResult `
    "Registro informa SimulationMode" `
    ($record.SimulationMode -eq $true)

Write-TestResult `
    "Registro informa Changed" `
    ($record.Changed -eq $false)

$validationResult = Test-AuditRecord `
    -Record $record

Write-TestResult `
    "Registro válido passa na validação" `
    ($validationResult.Success -eq $true -and $validationResult.Data -eq $true)

Write-TestResult `
    "Registro não possui Password" `
    ($record.PSObject.Properties.Name -notcontains "Password")

Write-TestResult `
    "Registro não possui Credential" `
    ($record.PSObject.Properties.Name -notcontains "Credential")

$invalidRecord = [PSCustomObject]@{
    Action = "UnlockUserAccount"
}

$invalidValidation = Test-AuditRecord `
    -Record $invalidRecord

Write-TestResult `
    "Registro incompleto é rejeitado" `
    ($invalidValidation.Success -eq $false)

$validRecord = [PSCustomObject]@{
    Timestamp      = Get-Date
    Operator       = "TEST"
    Action         = "Test"
    SamAccountName = "test"
    Result         = "Test"
    SimulationMode = $true
    Changed        = $false
}

$validValidation = Test-AuditRecord `
    -Record $validRecord

Write-TestResult `
    "Registro completo é aceito" `
    ($validValidation.Success -eq $true)

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
    Write-Host "AUDIT CORE V2: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "AUDIT CORE V2: EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}
