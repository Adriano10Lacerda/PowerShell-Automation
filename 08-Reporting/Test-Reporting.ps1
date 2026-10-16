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
# TESTE 13 - EXPORTAÇÃO EM SIMULAÇÃO
# ============================================================

Test-Result "Exportar Dataset em simulação sem gravar arquivos" {

    $Dataset = New-ReportingDataset -Configuration $Configuration

    $Export = Export-ReportingDataset `
        -Dataset $Dataset `
        -Configuration $Configuration

    if ($Export.Success -ne $true) {
        throw "A exportação simulada não retornou sucesso."
    }

    if ($Export.SimulationMode -ne $true) {
        throw "O resultado deveria indicar modo de simulação."
    }

    if (@($Export.Files).Count -lt 2) {
        throw "Deveriam ser previstos pelo menos dois arquivos."
    }

    foreach ($File in $Export.Files) {
        if (Test-Path -LiteralPath $File) {
            throw "A simulação não deveria criar o arquivo: $File"
        }
    }
}


# ============================================================
# TESTE 14 - INVOKE REPORTING EM SIMULAÇÃO
# ============================================================

Test-Result "Executar Invoke-Reporting em simulação" {

    $Result = Invoke-Reporting -Configuration $Configuration

    if ($Result.Success -ne $true) {
        throw "Invoke-Reporting não retornou sucesso."
    }

    if ($Result.Summary.TotalFiles -eq 0) {
        throw "Invoke-Reporting não processou arquivos."
    }

    if ($Result.Summary.FailedFiles -ne 0) {
        throw "Invoke-Reporting identificou falhas."
    }

    if (@($Result.Files).Count -lt 2) {
        throw "A simulação deveria informar os caminhos previstos."
    }

    foreach ($File in $Result.Files) {
        if (Test-Path -LiteralPath $File) {
            throw "Foi encontrado arquivo durante a simulação: $File"
        }
    }
}


# ============================================================
# TESTE 15 - BLOQUEAR FORMATO DE EXPORTAÇÃO INVÁLIDO
# ============================================================

Test-Result "Bloquear formato inválido sem criar pasta" {

    $TestConfiguration = $Configuration |
        ConvertTo-Json -Depth 20 |
        ConvertFrom-Json

    $TestOutputDirectory = Join-Path `
        -Path $env:TEMP `
        -ChildPath ("Reporting-InvalidFormat-" + [guid]::NewGuid().ToString("N"))

    $TestConfiguration.Output.Directory = $TestOutputDirectory
    $TestConfiguration.Output.Formats = @("INVALID")
    $TestConfiguration.SimulationMode = $false

    $Dataset = New-ReportingDataset -Configuration $TestConfiguration
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

    if (-not $ErrorCaptured) {
        throw "Um formato inválido deveria ser bloqueado."
    }

    if (Test-Path -LiteralPath $TestOutputDirectory) {
        throw "A validação criou uma pasta indevidamente."
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
# TESTE 19 - EXPORTAÇÃO REAL ISOLADA
# ============================================================

Test-Result "Exportação real isolada em diretório temporário" {

    $TestOutputDirectory = Join-Path $env:TEMP (
        "Reporting-RealExport-" + [guid]::NewGuid().ToString("N")
    )

    try {
        $TestConfiguration = Get-Content -LiteralPath $ConfigPath -Raw |
            ConvertFrom-Json

        $TestConfiguration = $TestConfiguration |
            ConvertTo-Json -Depth 20 |
            ConvertFrom-Json

        $TestConfiguration.Output.Directory = $TestOutputDirectory
        $TestConfiguration.Output.Formats = @("JSON", "CSV")
        $TestConfiguration.SimulationMode = $false

        $Dataset = New-ReportingDataset -Configuration $TestConfiguration

        $Export = Export-ReportingDataset `
            -Dataset $Dataset `
            -Configuration $TestConfiguration

        if ($Export.Success -ne $true) {
            throw "A exportação real não retornou sucesso."
        }

        if ($Export.SimulationMode -ne $false) {
            throw "O resultado deveria indicar exportação real."
        }

        if (-not (Test-Path -LiteralPath $TestOutputDirectory -PathType Container)) {
            throw "A pasta temporária de exportação não foi criada."
        }

        $JsonFiles = @(Get-ChildItem -LiteralPath $TestOutputDirectory -Filter "*.json" -File)
        $CsvFiles = @(Get-ChildItem -LiteralPath $TestOutputDirectory -Filter "*.csv" -File)

        if ($JsonFiles.Count -ne 1) {
            throw "Esperado 1 arquivo JSON; encontrados: $($JsonFiles.Count)."
        }

        if ($CsvFiles.Count -ne 1) {
            throw "Esperado 1 arquivo CSV; encontrados: $($CsvFiles.Count)."
        }

        foreach ($File in @($JsonFiles) + @($CsvFiles)) {
            if ($File.Length -le 0) {
                throw "O arquivo exportado está vazio: $($File.FullName)"
            }
        }

        Get-Content -LiteralPath $JsonFiles[0].FullName -Raw |
            ConvertFrom-Json |
            Out-Null

        if ($Export.Files.Count -ne 2) {
            throw "O resultado deveria informar os dois arquivos exportados."
        }
    }
    finally {
        if (Test-Path -LiteralPath $TestOutputDirectory -PathType Container) {
            Remove-Item -LiteralPath $TestOutputDirectory -Recurse -Force
        }
    }
}

# ============================================================
# TESTE 20 - FALHA NA GRAVAÇÃO
# ============================================================

Test-Result "Bloquear exportação quando o destino impede gravação" {

    $TempRoot = Join-Path $env:TEMP (
        "Reporting-WriteFailure-" + [guid]::NewGuid().ToString("N")
    )

    $BlockingFile = Join-Path $TempRoot "DestinoOcupado"
    $TestOutputDirectory = Join-Path $BlockingFile "Reports"

    try {
        New-Item -ItemType Directory -Path $TempRoot -Force -ErrorAction Stop |
            Out-Null

        Set-Content -LiteralPath $BlockingFile -Value "arquivo de bloqueio" -ErrorAction Stop

        $TestConfiguration = Get-Content -LiteralPath $ConfigPath -Raw |
            ConvertFrom-Json

        $TestConfiguration = $TestConfiguration |
            ConvertTo-Json -Depth 20 |
            ConvertFrom-Json

        $TestConfiguration.Output.Directory = $TestOutputDirectory
        $TestConfiguration.Output.Formats = @("JSON")
        $TestConfiguration.SimulationMode = $false

        $Dataset = New-ReportingDataset -Configuration $TestConfiguration

        $ExportFailed = $false

        try {
            Export-ReportingDataset `
                -Dataset $Dataset `
                -Configuration $TestConfiguration |
                Out-Null
        }
        catch {
            $ExportFailed = $true
        }

        if (-not $ExportFailed) {
            throw "A exportação deveria falhar porque o caminho pai é um arquivo."
        }

        if (Test-Path -LiteralPath $TestOutputDirectory) {
            throw "O destino inválido não deveria ter sido criado."
        }
    }
    finally {
        if (Test-Path -LiteralPath $TempRoot) {
            Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

# Teste 21 - Bloquear formatos duplicados antes de criar a pasta
Test-Result "Bloquear formatos duplicados antes de criar a pasta" {
    $DuplicateConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$DuplicateConfig = $DuplicateConfig | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $DuplicateOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("Reporting-Duplicados-" + [guid]::NewGuid().ToString("N"))
    $DuplicateConfig.Output.Directory = $DuplicateOutput
    $DuplicateConfig.Output.Formats = @("JSON", "json")
    $DuplicateConfig.SimulationMode = $false

    try {
        $DuplicateDataset = New-ReportingDataset -Configuration $DuplicateConfig
        $DuplicateError = $null

        try {
            Export-ReportingDataset -Configuration $DuplicateConfig -Dataset $DuplicateDataset | Out-Null
        }
        catch {
            $DuplicateError = $_.Exception.Message
        }

        if (-not $DuplicateError -or $DuplicateError -notmatch "duplicados") {
            throw "A exportação não rejeitou os formatos duplicados."
        }

        if (Test-Path -LiteralPath $DuplicateOutput) {
            throw "A pasta de saída foi criada apesar da configuração inválida."
        }
    }
    finally {
        if (Test-Path -LiteralPath $DuplicateOutput) {
            Remove-Item -LiteralPath $DuplicateOutput -Recurse -Force
        }
    }
}

# Teste 22 - Validar conteúdo do CSV exportado
Test-Result "Validar cabeçalhos e registros do CSV exportado" {
    $CsvConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$CsvConfig = $CsvConfig | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $CsvOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("Reporting-CSV-" + [guid]::NewGuid().ToString("N"))
    $CsvConfig.Output.Directory = $CsvOutput
    $CsvConfig.Output.Formats = @("CSV")
    $CsvConfig.SimulationMode = $false

    try {
        $CsvDataset = New-ReportingDataset -Configuration $CsvConfig
        $CsvResult = Export-ReportingDataset -Configuration $CsvConfig -Dataset $CsvDataset
        $CsvFile = @($CsvResult.Files | Where-Object { $_ -match '\.csv$' }) | Select-Object -First 1

        if (-not $CsvFile -or -not (Test-Path -LiteralPath $CsvFile)) {
            throw "Arquivo CSV não encontrado."
        }

        $CsvRows = @(Import-Csv -LiteralPath $CsvFile)

        if ($CsvRows.Count -eq 0) {
            throw "O CSV não contém registros."
        }

        if (@($CsvRows[0].PSObject.Properties).Count -eq 0) {
            throw "O CSV não contém cabeçalhos reconhecíveis."
        }
    }
    finally {
        if (Test-Path -LiteralPath $CsvOutput) {
            Remove-Item -LiteralPath $CsvOutput -Recurse -Force
        }
    }
}
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
