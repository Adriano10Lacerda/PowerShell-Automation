# ============================================================
# PowerShell Automation - Computer Core Tests
# ============================================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Computer-Functions.psm1"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COMPUTER CORE - TESTES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Carrega módulo
# ------------------------------------------------------------

try {
    Import-Module $ModulePath -Force -ErrorAction Stop
    Write-Host "[PASS] Modulo Computer-Functions carregado." -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Falha ao carregar modulo: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$passed = 0
$failed = 0

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        $script:failed++
    }
}

# ------------------------------------------------------------
# TESTE 1 - Funções disponíveis
# ------------------------------------------------------------

Assert-Test `
    "Get-ComputerADInfo disponivel" `
    ($null -ne (Get-Command Get-ComputerADInfo -ErrorAction SilentlyContinue))

Assert-Test `
    "Get-ComputerCimInfo disponivel" `
    ($null -ne (Get-Command Get-ComputerCimInfo -ErrorAction SilentlyContinue))

Assert-Test `
    "Get-ComputerInventory disponivel" `
    ($null -ne (Get-Command Get-ComputerInventory -ErrorAction SilentlyContinue))


# ------------------------------------------------------------
# TESTE 2 - Computer Models
# ------------------------------------------------------------

$ModelsPath = Join-Path $PSScriptRoot "Computer-Models.ps1"

try {
    . $ModelsPath

    $model = New-ComputerInventoryModel `
        -Hostname "TEST-PC"

    Assert-Test `
        "Computer Model criado" `
        ($null -ne $model)

    Assert-Test `
        "Model possui Hostname" `
        ($model.Hostname -eq "TEST-PC")

    Assert-Test `
        "Model possui AD" `
        ($null -ne $model.AD)

    Assert-Test `
        "Model possui Connectivity" `
        ($null -ne $model.Connectivity)

    Assert-Test `
        "Model possui System" `
        ($null -ne $model.System)

    Assert-Test `
        "Model possui OperatingSystem" `
        ($null -ne $model.OperatingSystem)

    Assert-Test `
        "Model possui Processor" `
        ($null -ne $model.Processor)

    Assert-Test `
        "Model possui Memory" `
        ($null -ne $model.Memory)

    Assert-Test `
        "Model possui Storage" `
        ($null -ne $model.Storage)

    Assert-Test `
        "Model possui Network" `
        ($null -ne $model.Network)

    Assert-Test `
        "Model possui BitLocker" `
        ($null -ne $model.BitLocker)

    Assert-Test `
        "Model possui Errors" `
        ($null -ne $model.Errors)
}
catch {
    Write-Host "[FAIL] Erro no Computer Model: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 3 - CIM local
# ------------------------------------------------------------

$cimResult = $null

try {

    $cimResult = Get-ComputerCimInfo `
        -ComputerName $env:COMPUTERNAME

    Assert-Test `
        "CIM local executado com sucesso" `
        ($cimResult.Success -eq $true)

    Assert-Test `
        "CIM possui System" `
        ($null -ne $cimResult.Data.System)

    Assert-Test `
        "CIM possui OperatingSystem" `
        ($null -ne $cimResult.Data.OperatingSystem)

    Assert-Test `
        "CIM possui Processor" `
        ($null -ne $cimResult.Data.Processor)

    Assert-Test `
        "CIM possui Memory" `
        ($null -ne $cimResult.Data.Memory)

    Assert-Test `
        "CIM possui Storage" `
        ($null -ne $cimResult.Data.Storage)

    Assert-Test `
        "CIM possui Network" `
        ($null -ne $cimResult.Data.Network)

    Assert-Test `
        "CIM possui BitLocker" `
        ($null -ne $cimResult.Data.BitLocker)

    Assert-Test `
        "CIM possui Connectivity" `
        ($null -ne $cimResult.Data.Connectivity)

}
catch {
    Write-Host "[FAIL] Erro no teste CIM: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 4 - Dados do equipamento
# ------------------------------------------------------------

if ($cimResult -and $cimResult.Success) {

    Assert-Test `
        "Fabricante identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.System.Manufacturer
        ))

    Assert-Test `
        "Modelo identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.System.Model
        ))

    Assert-Test `
        "Serial identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.System.SerialNumber
        ))

    Assert-Test `
        "Sistema operacional identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.OperatingSystem.Caption
        ))

    Assert-Test `
        "Processador identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.Processor.Name
        ))

    Assert-Test `
        "Memoria maior que zero" `
        ($cimResult.Data.Memory.TotalGB -gt 0)

    Assert-Test `
        "Storage coletado" `
        ($cimResult.Data.Storage.Count -gt 0)

    Assert-Test `
        "Network coletada" `
        ($cimResult.Data.Network.Count -gt 0)

    Assert-Test `
        "Connectivity Reachable" `
        ($cimResult.Data.Connectivity.Reachable -eq $true)

    Assert-Test `
        "BitLocker possui Status" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.BitLocker.Status
        ))
}


# ------------------------------------------------------------
# TESTE 5 - Inventory consolidado
# ------------------------------------------------------------

$inventory = $null

try {

    $inventory = Get-ComputerInventory `
        -ComputerName $env:COMPUTERNAME

    Assert-Test `
        "Computer Inventory executado com sucesso" `
        ($inventory.Success -eq $true)

    Assert-Test `
        "Inventory possui Hostname" `
        ($inventory.Data.Hostname -eq $env:COMPUTERNAME)

    Assert-Test `
        "Inventory possui CollectionDateTime" `
        ($null -ne $inventory.Data.CollectionDateTime)

    Assert-Test `
        "Inventory possui AD" `
        ($null -ne $inventory.Data.AD)

    Assert-Test `
        "Inventory possui Connectivity" `
        ($null -ne $inventory.Data.Connectivity)

    Assert-Test `
        "Inventory possui System" `
        ($null -ne $inventory.Data.System)

    Assert-Test `
        "Inventory possui OperatingSystem" `
        ($null -ne $inventory.Data.OperatingSystem)

    Assert-Test `
        "Inventory possui Processor" `
        ($null -ne $inventory.Data.Processor)

    Assert-Test `
        "Inventory possui Memory" `
        ($null -ne $inventory.Data.Memory)

    Assert-Test `
        "Inventory possui Storage" `
        ($null -ne $inventory.Data.Storage)

    Assert-Test `
        "Inventory possui Network" `
        ($null -ne $inventory.Data.Network)

    Assert-Test `
        "Inventory possui BitLocker" `
        ($null -ne $inventory.Data.BitLocker)

    Assert-Test `
        "Inventory possui Errors" `
        ($null -ne $inventory.Data.Errors)

}
catch {
    Write-Host "[FAIL] Erro no Inventory: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 6 - Tratamento de hostname invalido
# ------------------------------------------------------------

try {

    $invalidResult = Get-ComputerInventory `
        -ComputerName "COMPUTER-THAT-DOES-NOT-EXIST-999999"

    Assert-Test `
        "Hostname invalido tratado sem crash" `
        ($null -ne $invalidResult)

}
catch {
    Write-Host "[FAIL] Hostname invalido causou excecao inesperada." -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 7 - JSON
# ------------------------------------------------------------

try {

    $json = $inventory.Data |
        ConvertTo-Json -Depth 8

    Assert-Test `
        "Inventory pode ser convertido para JSON" `
        (-not [string]::IsNullOrWhiteSpace($json))

}
catch {
    Write-Host "[FAIL] Falha ao gerar JSON: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# RESULTADO
# ------------------------------------------------------------

$total = $passed + $failed

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $total"
Write-Host "PASS  : $passed" -ForegroundColor Green
Write-Host "FAIL  : $failed" -ForegroundColor Red

Write-Host ""

if ($failed -eq 0) {

    Write-Host "COMPUTER CORE: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {

    Write-Host "COMPUTER CORE: EXISTEM TESTES FALHANDO." -ForegroundColor Red
    exit 1
}