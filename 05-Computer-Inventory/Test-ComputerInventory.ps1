# ============================================
# Test-ComputerInventory.ps1
# PowerShell Automation
# Testes do módulo Computer Inventory
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Inventory-Functions.psm1"
$ConfigPath = Join-Path $PSScriptRoot "Inventory-Configuration.json"
$ReportPath = Join-Path $PSScriptRoot "Reports"

$TotalTests = 0
$PassedTests = 0
$FailedTests = 0

# ============================================
# FUNÇÃO DE TESTE
# ============================================

function Invoke-Test {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Test
    )

    $script:TotalTests++

    Write-Host "Teste $($script:TotalTests) - $Name" -ForegroundColor Yellow

    try {

        & $Test

        $script:PassedTests++

        Write-Host "PASSOU - $Name" -ForegroundColor Green
    }
    catch {

        $script:FailedTests++

        Write-Host "FALHOU - $Name" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

    Write-Host ""
}

# ============================================
# CABEÇALHO
# ============================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       TESTES - COMPUTER INVENTORY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# TESTE 1 - MÓDULO
# ============================================

Invoke-Test `
    -Name "Carregamento do módulo" `
    -Test {

        if (-not (Test-Path $ModulePath)) {

            throw "Inventory-Functions.psm1 não foi encontrado."
        }

        Import-Module $ModulePath -Force -ErrorAction Stop

        if (-not (Get-Command Get-ComputerInventory -ErrorAction SilentlyContinue)) {

            throw "A função Get-ComputerInventory não está disponível."
        }
    }

# ============================================
# TESTE 2 - CONFIGURAÇÃO
# ============================================

Invoke-Test `
    -Name "Carregamento da configuração" `
    -Test {

        if (-not (Test-Path $ConfigPath)) {

            throw "Inventory-Configuration.json não foi encontrado."
        }

        $Configuration = Get-Content `
            $ConfigPath `
            -Raw `
            -ErrorAction Stop |
            ConvertFrom-Json `
            -ErrorAction Stop

        if ($null -eq $Configuration.Inventory) {

            throw "A seção Inventory não foi encontrada."
        }

        if ($null -eq $Configuration.Output) {

            throw "A seção Output não foi encontrada."
        }
    }

# ============================================
# CARREGAR CONFIGURAÇÃO PARA OS TESTES
# ============================================

$Configuration = Get-Content `
    $ConfigPath `
    -Raw |
    ConvertFrom-Json

# ============================================
# TESTE 3 - COMPUTER SYSTEM
# ============================================

Invoke-Test `
    -Name "Coleta de informações do computador" `
    -Test {

        $Result = Get-ComputerSystemInventory

        if ($null -eq $Result) {

            throw "A função não retornou resultado."
        }

        if ([string]::IsNullOrWhiteSpace($Result.ComputerName)) {

            throw "ComputerName não foi coletado."
        }

        if ([string]::IsNullOrWhiteSpace($Result.Manufacturer)) {

            throw "Manufacturer não foi coletado."
        }

        if ([string]::IsNullOrWhiteSpace($Result.Model)) {

            throw "Model não foi coletado."
        }
    }

# ============================================
# TESTE 4 - SISTEMA OPERACIONAL
# ============================================

Invoke-Test `
    -Name "Coleta do sistema operacional" `
    -Test {

        $Result = Get-OperatingSystemInventory

        if ($null -eq $Result) {

            throw "A função não retornou resultado."
        }

        if ([string]::IsNullOrWhiteSpace($Result.OperatingSystem)) {

            throw "Sistema operacional não foi identificado."
        }

        if ([string]::IsNullOrWhiteSpace($Result.Version)) {

            throw "Versão do sistema operacional não foi coletada."
        }

        if ([string]::IsNullOrWhiteSpace($Result.Build)) {

            throw "Build do sistema operacional não foi coletada."
        }
    }

# ============================================
# TESTE 5 - PROCESSADOR
# ============================================

Invoke-Test `
    -Name "Coleta do processador" `
    -Test {

        $Result = Get-ProcessorInventory

        if ($null -eq $Result) {

            throw "A função não retornou resultado."
        }

        if ([string]::IsNullOrWhiteSpace($Result.ProcessorName)) {

            throw "Nome do processador não foi coletado."
        }

        if ($Result.PhysicalCores -le 0) {

            throw "Quantidade de núcleos inválida."
        }

        if ($Result.LogicalProcessors -le 0) {

            throw "Quantidade de processadores lógicos inválida."
        }
    }

# ============================================
# TESTE 6 - MEMÓRIA
# ============================================

Invoke-Test `
    -Name "Coleta de memória RAM" `
    -Test {

        $Result = Get-MemoryInventory

        if ($null -eq $Result) {

            throw "A função não retornou resultado."
        }

        if ($Result.TotalMemoryGB -le 0) {

            throw "Quantidade de memória RAM inválida."
        }
    }

# ============================================
# TESTE 7 - DISCO
# ============================================

Invoke-Test `
    -Name "Coleta de discos" `
    -Test {

        $Result = Get-DiskInventory `
            -Configuration $Configuration

        $Disks = @($Result)

        if ($Disks.Count -eq 0) {

            throw "Nenhum disco foi encontrado."
        }

        $ValidDisk = $Disks |
            Where-Object {
                $null -ne $_.Drive
            } |
            Select-Object -First 1

        if ($null -eq $ValidDisk) {

            throw "Nenhum disco válido foi retornado."
        }

        if ($ValidDisk.SizeGB -le 0) {

            throw "Tamanho do disco inválido."
        }
    }

# ============================================
# TESTE 8 - REDE
# ============================================

Invoke-Test `
    -Name "Coleta de informações de rede" `
    -Test {

        $Result = Get-NetworkInventory `
            -Configuration $Configuration

        $Adapters = @($Result)

        if ($Adapters.Count -eq 0) {

            throw "Nenhum adaptador de rede foi encontrado."
        }

        $ValidAdapter = $Adapters |
            Where-Object {
                $null -ne $_.Description
            } |
            Select-Object -First 1

        if ($null -eq $ValidAdapter) {

            throw "Nenhum adaptador de rede válido foi retornado."
        }
    }

# ============================================
# TESTE 9 - BITLOCKER
# ============================================

Invoke-Test `
    -Name "Tratamento da coleta do BitLocker" `
    -Test {

        $Result = Get-BitLockerInventory

        if ($null -eq $Result) {

            throw "A função não retornou resultado."
        }

        $ValidStatuses = @(
            "Success",
            "Unavailable",
            "Error"
        )

        if ($Result.Status -notin $ValidStatuses) {

            throw "Status de BitLocker inválido: $($Result.Status)"
        }

        if ($null -eq $Result.Available) {

            throw "A propriedade Available não foi retornada."
        }
    }

# ============================================
# TESTE 10 - INVENTÁRIO COMPLETO
# ============================================

Invoke-Test `
    -Name "Geração do inventário completo" `
    -Test {

        $Inventory = Get-ComputerInventory `
            -Configuration $Configuration

        if ($null -eq $Inventory) {

            throw "O inventário não foi gerado."
        }

        if ([string]::IsNullOrWhiteSpace($Inventory.CollectionDateTime)) {

            throw "CollectionDateTime não foi gerado."
        }

        if ($null -eq $Inventory.ComputerSystem) {

            throw "ComputerSystem não foi incluído."
        }

        if ($null -eq $Inventory.OperatingSystem) {

            throw "OperatingSystem não foi incluído."
        }

        if ($null -eq $Inventory.Processor) {

            throw "Processor não foi incluído."
        }

        if ($null -eq $Inventory.Memory) {

            throw "Memory não foi incluído."
        }

        if ($null -eq $Inventory.Disk) {

            throw "Disk não foi incluído."
        }

        if ($null -eq $Inventory.Network) {

            throw "Network não foi incluído."
        }

        if ($null -eq $Inventory.BitLocker) {

            throw "BitLocker não foi incluído."
        }
    }

# ============================================
# TESTE 11 - EXPORTAÇÃO
# ============================================

Invoke-Test `
    -Name "Exportação do inventário" `
    -Test {

        if (-not (Test-Path $ReportPath)) {

            New-Item `
                -ItemType Directory `
                -Path $ReportPath `
                -Force |
                Out-Null
        }

        $Inventory = Get-ComputerInventory `
            -Configuration $Configuration

        $ExportResult = Export-ComputerInventory `
            -Inventory $Inventory `
            -Configuration $Configuration

        if ($ExportResult.Success -ne $true) {

            throw "A exportação falhou: $($ExportResult.Message)"
        }

        if (@($ExportResult.Files).Count -eq 0) {

            throw "Nenhum arquivo foi gerado."
        }

        foreach ($File in @($ExportResult.Files)) {

            if (-not (Test-Path $File)) {

                throw "Arquivo não encontrado após exportação: $File"
            }
        }
    }

# ============================================
# TESTE 12 - VALIDAÇÃO DO JSON
# ============================================

Invoke-Test `
    -Name "Validação do arquivo JSON" `
    -Test {

        $JsonFiles = Get-ChildItem `
            -Path $ReportPath `
            -Filter "*.json" `
            -File |
            Sort-Object LastWriteTime -Descending

        if ($JsonFiles.Count -eq 0) {

            throw "Nenhum arquivo JSON encontrado."
        }

        $LatestJson = $JsonFiles | Select-Object -First 1

        $JsonContent = Get-Content `
            $LatestJson.FullName `
            -Raw `
            -ErrorAction Stop

        $JsonObject = $JsonContent |
            ConvertFrom-Json `
            -ErrorAction Stop

        if ($null -eq $JsonObject.ComputerSystem) {

            throw "O JSON não contém ComputerSystem."
        }

        if ($null -eq $JsonObject.OperatingSystem) {

            throw "O JSON não contém OperatingSystem."
        }
    }

# ============================================
# TESTE 13 - VALIDAÇÃO DO CSV
# ============================================

Invoke-Test `
    -Name "Validação do arquivo CSV" `
    -Test {

        $CsvFiles = Get-ChildItem `
            -Path $ReportPath `
            -Filter "*.csv" `
            -File |
            Sort-Object LastWriteTime -Descending

        if ($CsvFiles.Count -eq 0) {

            throw "Nenhum arquivo CSV encontrado."
        }

        $LatestCsv = $CsvFiles | Select-Object -First 1

        $CsvObject = Import-Csv `
            $LatestCsv.FullName `
            -ErrorAction Stop

        if ($null -eq $CsvObject) {

            throw "O CSV não retornou dados."
        }

        if ([string]::IsNullOrWhiteSpace($CsvObject.ComputerName)) {

            throw "O CSV não contém ComputerName."
        }

        if ([string]::IsNullOrWhiteSpace($CsvObject.OperatingSystem)) {

            throw "O CSV não contém OperatingSystem."
        }
    }

# ============================================
# RESUMO
# ============================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "              RESUMO DOS TESTES" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total de testes : $TotalTests"
Write-Host "Passaram        : $PassedTests" -ForegroundColor Green
Write-Host "Falharam        : $FailedTests" -ForegroundColor Red
Write-Host ""

if ($FailedTests -eq 0) {

    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green
}
else {

    Write-Host "STATUS: EXISTEM TESTES COM FALHA" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan