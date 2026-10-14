
# ============================================
# Test-ComputerInventory.ps1
# PowerShell Automation
# Testes do modulo Computer Inventory
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Inventory-Functions.psm1"
$ConfigPath = Join-Path $PSScriptRoot "Inventory-Configuration.json"

$TotalTests = 0
$PassedTests = 0
$FailedTests = 0

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Test
    )

    $script:TotalTests++

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
}

Write-Host "`n=== TESTES - COMPUTER INVENTORY ===" -ForegroundColor Cyan

Invoke-Test -Name "Modulo encontrado" -Test {
    if (-not (Test-Path $ModulePath)) {
        throw "Modulo nao encontrado."
    }
}

Invoke-Test -Name "Configuracao JSON valida" -Test {
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuracao nao encontrada."
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    if ($null -eq $config.Inventory -or $null -eq $config.Output) {
        throw "Secoes Inventory ou Output ausentes."
    }
}

Import-Module $ModulePath -Force

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$config.SimulationMode = $true
Invoke-Test -Name "Coleta simulada identificada" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($inventory.SimulationMode -ne $true) {
        throw "O inventario nao identificou o modo de simulacao."
    }
}

Invoke-Test -Name "Dados ficticios do computador" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.ComputerSystem -and
        $inventory.ComputerSystem.ComputerName -ne "SIMULATED-PC") {
        throw "Identificacao simulada inesperada."
    }
}

Invoke-Test -Name "Sistema operacional simulado" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.OperatingSystem -and
        $inventory.OperatingSystem.OperatingSystem -ne "Windows (Simulacao)") {
        throw "Sistema operacional simulado inesperado."
    }
}

Invoke-Test -Name "Processador simulado" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Processor -and
        $inventory.Processor.ProcessorName -ne "CPU de Demonstracao") {
        throw "Processador simulado inesperado."
    }
}

Invoke-Test -Name "Memoria simulada" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Memory -and
        $inventory.Memory.TotalMemoryGB -ne 16) {
        throw "Memoria simulada inesperada."
    }
}

Invoke-Test -Name "Disco simulado" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Disk -and @($inventory.Disk).Count -eq 0) {
        throw "Nenhum disco simulado retornado."
    }
}

Invoke-Test -Name "Rede simulada" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Network -and @($inventory.Network).Count -eq 0) {
        throw "Nenhum adaptador simulado retornado."
    }
}

Invoke-Test -Name "BitLocker sem consulta real" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.BitLocker -and
        $inventory.BitLocker.Message -notlike "*nao foi consultado*") {
        throw "A resposta simulada do BitLocker nao corresponde ao esperado."
    }
}

Invoke-Test -Name "Exportacao simulada sem arquivos" -Test {
    $inventory = Get-ComputerInventory -Configuration $config
    $result = Export-ComputerInventory -Inventory $inventory -Configuration $config

    if ($result.Success -ne $true) {
        throw "A simulacao da exportacao falhou."
    }

    if (@($result.Files).Count -ne 0) {
        throw "A simulacao informou arquivos gerados."
    }

    if ($null -ne $result.Directory) {
        throw "A simulacao informou um diretorio de saida."
    }

    if ($result.SimulationMode -ne $true) {
        throw "O resultado nao identificou o modo de simulacao."
    }
}


# ============================================
# Testes adicionais de exportação (dados fictícios)
# ============================================

$testRoot = Join-Path $env:TEMP (
    "PSAutomation-InventoryTests-" + [guid]::NewGuid().ToString("N")
)

try {
    $configExport = $config | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json

    $configExport.SimulationMode = $true
    $inventoryExport = Get-ComputerInventory -Configuration $configExport

    Invoke-Test -Name "Exportação JSON válida" -Test {
        $configJson = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configJson.SimulationMode = $false
        $configJson.Output.Directory = Join-Path $testRoot "JSON"
        $configJson.Output.Formats = @("JSON")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configJson

        if (-not $result.Success -or @($result.Files).Count -ne 1) {
            throw "A exportação JSON não retornou exatamente um arquivo."
        }

        $json = Get-Content -LiteralPath $result.Files[0] -Raw |
            ConvertFrom-Json -ErrorAction Stop

        if ($json.ComputerSystem.ComputerName -ne "SIMULATED-PC") {
            throw "O JSON não contém o computador fictício esperado."
        }
    }

    Invoke-Test -Name "Exportação CSV válida com 18 colunas" -Test {
        $configCsv = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configCsv.SimulationMode = $false
        $configCsv.Output.Directory = Join-Path $testRoot "CSV"
        $configCsv.Output.Formats = @("CSV")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configCsv

        if (-not $result.Success -or @($result.Files).Count -ne 1) {
            throw "A exportação CSV não retornou exatamente um arquivo."
        }

        $rows = @(Import-Csv -LiteralPath $result.Files[0] -ErrorAction Stop)

        if ($rows.Count -ne 1) {
            throw "O CSV deveria conter exatamente um registro."
        }

        if (@($rows[0].PSObject.Properties).Count -ne 18) {
            throw "O CSV não contém as 18 colunas esperadas."
        }

        if ($rows[0].ComputerName -ne "SIMULATED-PC") {
            throw "O CSV não contém o computador fictício esperado."
        }
    }

    Invoke-Test -Name "Exportação para caminho absoluto" -Test {
        $configAbs = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configAbs.SimulationMode = $false
        $configAbs.Output.Directory = Join-Path $testRoot "Absolute"
        $configAbs.Output.Formats = @("JSON", "CSV")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configAbs

        if (-not $result.Success) {
            throw "Falha no caminho absoluto: $($result.Message)"
        }

        if (@($result.Files).Count -ne 2) {
            throw "Esperados dois arquivos no caminho absoluto."
        }

        foreach ($file in $result.Files) {
            if (-not (Test-Path -LiteralPath $file)) {
                throw "Arquivo não encontrado: $file"
            }
        }
    }

    Invoke-Test -Name "Diretório inválido tratado como falha" -Test {
        $configInvalid = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configInvalid.SimulationMode = $false
        $configInvalid.Output.Directory = " "
        $configInvalid.Output.Formats = @("JSON")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configInvalid

        if ($result.Success -ne $false) {
            throw "A função deveria informar falha para diretório vazio."
        }

        if ([string]::IsNullOrWhiteSpace($result.Message)) {
            throw "A função deveria retornar uma mensagem de erro."
        }
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Remove-Module Inventory-Functions -ErrorAction SilentlyContinue
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "Total: $TotalTests | Passaram: $PassedTests | Falharam: $FailedTests"
Write-Host "============================================" -ForegroundColor Cyan

if ($FailedTests -gt 0) {
    throw "Existem testes com falha."
}
