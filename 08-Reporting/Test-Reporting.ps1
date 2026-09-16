$ErrorActionPreference = "Stop"

# ============================================================
# CAMINHOS
# ============================================================

$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "Reporting-Functions.psm1"
$ConfigPath = Join-Path $ScriptPath "Reporting-Configuration.json"


# ============================================================
# CONTADORES
# ============================================================

$TotalTests = 0
$PassedTests = 0
$FailedTests = 0


# ============================================================
# FUNÇÃO DE TESTE
# ============================================================

function Test-Result {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Test
    )

    $script:TotalTests++

    try {

        & $Test

        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:PassedTests++
    }
    catch {

        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Red

        $script:FailedTests++
    }
}


# ============================================================
# CABEÇALHO
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "          Testes - Reporting" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""


# ============================================================
# TESTE 1 - ARQUIVO DE FUNÇÕES
# ============================================================

Test-Result "Arquivo Reporting-Functions.psm1 encontrado" {

    if (-not (Test-Path $ModulePath)) {

        throw "Arquivo Reporting-Functions.psm1 não encontrado."
    }
}


# ============================================================
# TESTE 2 - ARQUIVO DE CONFIGURAÇÃO
# ============================================================

Test-Result "Arquivo Reporting-Configuration.json encontrado" {

    if (-not (Test-Path $ConfigPath)) {

        throw "Arquivo Reporting-Configuration.json não encontrado."
    }
}


# ============================================================
# IMPORTAR MÓDULO
# ============================================================

Import-Module $ModulePath -Force


# ============================================================
# CARREGAR CONFIGURAÇÃO
# ============================================================

$Configuration = Get-Content `
    $ConfigPath `
    -Raw |
    ConvertFrom-Json


# ============================================================
# TESTE 3 - CONFIGURAÇÃO VÁLIDA
# ============================================================

Test-Result "Configuração válida" {

    $Result = Test-ReportingConfiguration `
        -Configuration $Configuration

    if ($Result -ne $true) {

        throw "A configuração não foi validada."
    }
}


# ============================================================
# TESTE 4 - SIMULATION MODE
# ============================================================

Test-Result "SimulationMode habilitado" {

    if ($Configuration.SimulationMode -ne $true) {

        throw "SimulationMode deveria estar habilitado."
    }
}


# ============================================================
# TESTE 5 - FONTE COMPUTER INVENTORY HABILITADA
# ============================================================

Test-Result "Fonte ComputerInventory habilitada" {

    if ($Configuration.Sources.ComputerInventory.Enabled -ne $true) {

        throw "ComputerInventory deveria estar habilitado."
    }
}


# ============================================================
# TESTE 6 - FONTES FUTURAS DESABILITADAS
# ============================================================

Test-Result "Fontes futuras desabilitadas" {

    $FutureSources = @(
        "ADUsers",
        "ADGroups",
        "GPOs",
        "EntraUsers"
    )

    foreach ($SourceName in $FutureSources) {

        if ($Configuration.Sources.$SourceName.Enabled -ne $false) {

            throw "A fonte '$SourceName' deveria estar desabilitada."
        }
    }
}


# ============================================================
# TESTE 7 - DESCOBERTA DOS ARQUIVOS
# ============================================================

Test-Result "Descobrir arquivos do Computer Inventory" {

    $Source = $Configuration.Sources.ComputerInventory

    $Files = @(Get-ReportingSourceFiles `
        -Source $Source)

    if ($Files.Count -eq 0) {

        throw "Nenhum arquivo do Computer Inventory foi encontrado."
    }

    foreach ($File in $Files) {

        if ($File.Name -notlike "ComputerInventory_*") {

            throw "Foi encontrado um arquivo fora do padrão esperado: $($File.Name)"
        }
    }
}


# ============================================================
# TESTE 8 - NÃO ENCONTRAR ARQUIVOS DE CONFIGURAÇÃO
# ============================================================

Test-Result "Ignorar arquivos de configuração" {

    $Source = $Configuration.Sources.ComputerInventory

    $Files = @(Get-ReportingSourceFiles `
        -Source $Source)

    $ConfigurationFiles = @(
        $Files | Where-Object {
            $_.Name -eq "Inventory-Configuration.json"
        }
    )

    if ($ConfigurationFiles.Count -gt 0) {

        throw "O Reporting encontrou Inventory-Configuration.json."
    }
}


# ============================================================
# TESTE 9 - LEITURA DE CSV
# ============================================================

Test-Result "Ler arquivo CSV" {

    $Source = $Configuration.Sources.ComputerInventory

    $CSVFile = @(
        Get-ReportingSourceFiles `
            -Source $Source |
        Where-Object {
            $_.Extension -eq ".csv"
        }
    ) | Select-Object -First 1

    if ($null -eq $CSVFile) {

        throw "Nenhum arquivo CSV foi encontrado."
    }

    $Result = Get-ReportingData `
        -File $CSVFile `
        -SourceName "ComputerInventory"

    if ($Result.Success -ne $true) {

        throw "O arquivo CSV não foi carregado corretamente."
    }

    if ($Result.Format -ne "CSV") {

        throw "O formato identificado não corresponde a CSV."
    }
}


# ============================================================
# TESTE 10 - LEITURA DE JSON
# ============================================================

Test-Result "Ler arquivo JSON" {

    $Source = $Configuration.Sources.ComputerInventory

    $JSONFile = @(
        Get-ReportingSourceFiles `
            -Source $Source |
        Where-Object {
            $_.Extension -eq ".json"
        }
    ) | Select-Object -First 1

    if ($null -eq $JSONFile) {

        throw "Nenhum arquivo JSON foi encontrado."
    }

    $Result = Get-ReportingData `
        -File $JSONFile `
        -SourceName "ComputerInventory"

    if ($Result.Success -ne $true) {

        throw "O arquivo JSON não foi carregado corretamente."
    }

    if ($Result.Format -ne "JSON") {

        throw "O formato identificado não corresponde a JSON."
    }
}


# ============================================================
# TESTE 11 - RESUMO
# ============================================================

Test-Result "Gerar resumo dos dados" {

    $Source = $Configuration.Sources.ComputerInventory

    $Files = @(Get-ReportingSourceFiles `
        -Source $Source)

    $Data = @()

    foreach ($File in $Files) {

        $Data += Get-ReportingData `
            -File $File `
            -SourceName "ComputerInventory"
    }

    $Summary = Get-ReportingSummary `
        -Data $Data

    if ($Summary.TotalFiles -ne $Files.Count) {

        throw "O total de arquivos do resumo não corresponde ao esperado."
    }

    if ($Summary.SuccessfulFiles -ne $Files.Count) {

        throw "Nem todos os arquivos foram processados com sucesso."
    }

    if ($Summary.FailedFiles -ne 0) {

        throw "O resumo identificou arquivos com falha."
    }
}


# ============================================================
# TESTE 12 - DATASET
# ============================================================

Test-Result "Gerar Dataset consolidado" {

    $Dataset = New-ReportingDataset `
        -Configuration $Configuration

    if ($null -eq $Dataset) {

        throw "O Dataset não foi criado."
    }

    if ($Dataset.Summary.TotalFiles -eq 0) {

        throw "O Dataset não possui arquivos."
    }

    if ($Dataset.Summary.FailedFiles -ne 0) {

        throw "O Dataset possui arquivos com falha."
    }
}


# ============================================================
# TESTE 13 - EXPORTAÇÃO
# ============================================================

Test-Result "Exportar Dataset" {

    $Dataset = New-ReportingDataset `
        -Configuration $Configuration

    $Export = Export-ReportingDataset `
        -Dataset $Dataset `
        -Configuration $Configuration

    if ($Export.Success -ne $true) {

        throw "A exportação não retornou sucesso."
    }

    if (@($Export.Files).Count -lt 2) {

        throw "A exportação deveria gerar pelo menos dois arquivos."
    }

    foreach ($File in $Export.Files) {

        if (-not (Test-Path $File)) {

            throw "O arquivo exportado não foi encontrado: $File"
        }
    }
}


# ============================================================
# TESTE 14 - INVOKE REPORTING
# ============================================================

Test-Result "Executar Invoke-Reporting" {

    $Result = Invoke-Reporting `
        -Configuration $Configuration

    if ($Result.Success -ne $true) {

        throw "Invoke-Reporting não retornou sucesso."
    }

    if ($Result.Summary.TotalFiles -eq 0) {

        throw "Invoke-Reporting não processou arquivos."
    }

    if ($Result.Summary.FailedFiles -ne 0) {

        throw "Invoke-Reporting identificou falhas."
    }
}


# ============================================================
# TESTE 15 - BLOQUEAR FORMATO DE EXPORTAÇÃO INVÁLIDO
# ============================================================

Test-Result "Bloquear formato de exportação inválido" {

    $TestConfiguration = $Configuration.PSObject.Copy()

    $TestConfiguration.Output.Formats = @(
        "INVALID"
    )

    $Dataset = New-ReportingDataset `
        -Configuration $Configuration

    $ErrorCaptured = $false

    try {

        Export-ReportingDataset `
            -Dataset $Dataset `
            -Configuration $TestConfiguration |
            Out-Null
    }
    catch {

        $ErrorCaptured = $true
    }

    if ($ErrorCaptured -ne $true) {

        throw "Um formato de exportação inválido deveria ser bloqueado."
    }
}


# ============================================================
# TESTE 16 - BLOQUEAR CONFIGURAÇÃO SEM SOURCES
# ============================================================

Test-Result "Bloquear configuração sem Sources" {

    $TestConfiguration = $Configuration.PSObject.Copy()

    $TestConfiguration.Sources = $null

    $ErrorCaptured = $false

    try {

        Test-ReportingConfiguration `
            -Configuration $TestConfiguration |
            Out-Null
    }
    catch {

        $ErrorCaptured = $true
    }

    if ($ErrorCaptured -ne $true) {

        throw "Uma configuração sem Sources deveria ser bloqueada."
    }
}


# ============================================================
# TESTE 17 - BLOQUEAR FONTE SEM DIRETÓRIO
# ============================================================

Test-Result "Bloquear fonte sem diretório" {

    $TestConfiguration = $Configuration.PSObject.Copy()

    $TestConfiguration.Sources.ComputerInventory.Directory = ""

    $ErrorCaptured = $false

    try {

        Test-ReportingConfiguration `
            -Configuration $TestConfiguration |
            Out-Null
    }
    catch {

        $ErrorCaptured = $true
    }

    if ($ErrorCaptured -ne $true) {

        throw "Uma fonte sem diretório deveria ser bloqueada."
    }
}


# ============================================================
# TESTE 18 - BLOQUEAR FONTE SEM FILE PATTERN
# ============================================================

Test-Result "Bloquear fonte sem FilePattern" {

    $TestConfiguration = $Configuration.PSObject.Copy()

    $TestConfiguration.Sources.ComputerInventory.FilePattern = ""

    $ErrorCaptured = $false

    try {

        Test-ReportingConfiguration `
            -Configuration $TestConfiguration |
            Out-Null
    }
    catch {

        $ErrorCaptured = $true
    }

    if ($ErrorCaptured -ne $true) {

        throw "Uma fonte sem FilePattern deveria ser bloqueada."
    }
}


# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "             RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
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