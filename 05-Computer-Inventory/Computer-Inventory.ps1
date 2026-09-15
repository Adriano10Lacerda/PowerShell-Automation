# ============================================
# Computer-Inventory.ps1
# PowerShell Automation
# Script principal do Inventário de Computadores
# ============================================

$ErrorActionPreference = "Stop"

# ============================================
# CAMINHOS
# ============================================

$ModulePath = Join-Path $PSScriptRoot "Inventory-Functions.psm1"
$ConfigPath = Join-Path $PSScriptRoot "Inventory-Configuration.json"

# ============================================
# VALIDAÇÃO DOS ARQUIVOS
# ============================================

if (-not (Test-Path $ModulePath)) {

    Write-Host ""
    Write-Host "ERRO: O módulo Inventory-Functions.psm1 não foi encontrado." -ForegroundColor Red
    Write-Host ""
    exit 1
}

if (-not (Test-Path $ConfigPath)) {

    Write-Host ""
    Write-Host "ERRO: O arquivo Inventory-Configuration.json não foi encontrado." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ============================================
# CARREGAR MÓDULO
# ============================================

try {

    Import-Module $ModulePath -Force -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERRO: Não foi possível carregar o módulo de inventário." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ============================================
# CARREGAR CONFIGURAÇÃO
# ============================================

try {

    $Configuration = Get-Content `
        $ConfigPath `
        -Raw `
        -ErrorAction Stop |
        ConvertFrom-Json `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERRO: Não foi possível carregar a configuração." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ============================================
# CABEÇALHO
# ============================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       POWERSHELL AUTOMATION" -ForegroundColor Cyan
Write-Host "        COMPUTER INVENTORY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Computador : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "Iniciando coleta de inventário..." -ForegroundColor Yellow
Write-Host ""

# ============================================
# COLETA DO INVENTÁRIO
# ============================================

try {

    $Inventory = Get-ComputerInventory `
        -Configuration $Configuration `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERRO: Falha durante a coleta do inventário." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ============================================
# RESUMO
# ============================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "             INVENTÁRIO COLETADO" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# COMPUTADOR
# ============================================

if ($null -ne $Inventory.ComputerSystem) {

    Write-Host "Computador    : $($Inventory.ComputerSystem.ComputerName)"
    Write-Host "Usuário       : $($Inventory.ComputerSystem.LoggedOnUser)"
    Write-Host "Fabricante    : $($Inventory.ComputerSystem.Manufacturer)"
    Write-Host "Modelo        : $($Inventory.ComputerSystem.Model)"
    Write-Host "Serial        : $($Inventory.ComputerSystem.SerialNumber)"
}

Write-Host ""

# ============================================
# SISTEMA OPERACIONAL
# ============================================

if ($null -ne $Inventory.OperatingSystem) {

    Write-Host "Sistema       : $($Inventory.OperatingSystem.OperatingSystem)"
    Write-Host "Versão        : $($Inventory.OperatingSystem.Version)"
    Write-Host "Build         : $($Inventory.OperatingSystem.Build)"
    Write-Host "Arquitetura   : $($Inventory.OperatingSystem.Architecture)"
}

Write-Host ""

# ============================================
# PROCESSADOR
# ============================================

if ($null -ne $Inventory.Processor) {

    Write-Host "Processador   : $($Inventory.Processor.ProcessorName)"
    Write-Host "Núcleos       : $($Inventory.Processor.PhysicalCores)"
    Write-Host "Processadores : $($Inventory.Processor.LogicalProcessors)"
}

Write-Host ""

# ============================================
# MEMÓRIA
# ============================================

if ($null -ne $Inventory.Memory) {

    Write-Host "Memória RAM   : $($Inventory.Memory.TotalMemoryGB) GB"
}

Write-Host ""

# ============================================
# DISCOS
# ============================================

if ($null -ne $Inventory.Disk) {

    Write-Host "Discos:"

    foreach ($Disk in @($Inventory.Disk)) {

        if ($null -ne $Disk.Drive) {

            Write-Host "  $($Disk.Drive) - $($Disk.SizeGB) GB - Livre: $($Disk.FreeSpaceGB) GB"
        }
    }
}

Write-Host ""

# ============================================
# REDE
# ============================================

if ($null -ne $Inventory.Network) {

    Write-Host "Rede:"

    foreach ($Adapter in @($Inventory.Network)) {

        if ($null -ne $Adapter.Description) {

            Write-Host "  Adaptador : $($Adapter.Description)"
            Write-Host "  IPv4      : $($Adapter.IPv4Address)"
            Write-Host "  MAC       : $($Adapter.MACAddress)"
        }
    }
}

Write-Host ""

# ============================================
# BITLOCKER
# ============================================

if ($null -ne $Inventory.BitLocker) {

    switch ($Inventory.BitLocker.Status) {

        "Success" {

            Write-Host "BitLocker    : Informações coletadas" -ForegroundColor Green
        }

        "Unavailable" {

            Write-Host "BitLocker    : Recurso indisponível" -ForegroundColor Yellow
            Write-Host "Motivo       : $($Inventory.BitLocker.Message)" -ForegroundColor Yellow
        }

        "Error" {

            Write-Host "BitLocker    : Erro durante a coleta" -ForegroundColor Yellow
            Write-Host "Motivo       : $($Inventory.BitLocker.Message)" -ForegroundColor Yellow
        }

        default {

            Write-Host "BitLocker    : Status desconhecido" -ForegroundColor Yellow
            Write-Host "Motivo       : $($Inventory.BitLocker.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""

# ============================================
# DATA DA COLETA
# ============================================

Write-Host "Data da coleta: $($Inventory.CollectionDateTime)" -ForegroundColor Gray

Write-Host ""

# ============================================
# EXPORTAÇÃO
# ============================================

Write-Host "Exportando inventário..." -ForegroundColor Yellow
Write-Host ""

try {

    $ExportResult = Export-ComputerInventory `
        -Inventory $Inventory `
        -Configuration $Configuration `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERRO: Falha durante a exportação do inventário." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($ExportResult.Success -eq $true) {

    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "          ARQUIVOS GERADOS" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($File in @($ExportResult.Files)) {

        Write-Host $File -ForegroundColor Green
    }

    Write-Host ""
}
else {

    Write-Host ""
    Write-Host "ERRO: O inventário foi coletado, mas a exportação falhou." -ForegroundColor Red
    Write-Host $ExportResult.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ============================================
# FINALIZAÇÃO
# ============================================

Write-Host "============================================" -ForegroundColor Green
Write-Host "       INVENTÁRIO CONCLUÍDO COM SUCESSO" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""