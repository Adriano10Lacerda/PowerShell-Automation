$ErrorActionPreference = "Stop"

# ============================================================
# CAMINHOS
# ============================================================

$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "Reporting-Functions.psm1"
$ExampleConfigPath = Join-Path $ScriptPath "Reporting-Configuration.example.json"

function Assert-ReportingProjectFile {
    param ([Parameter(Mandatory = $true)][string]$Path)

    $Root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]@('\', '/'))
    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.Path]::IsPathFullyQualified($Path) -or
        $Path.StartsWith('\\') -or $Path.StartsWith('//') -or
        $Path.StartsWith('\\?\') -or $Path.StartsWith('\\.\') -or
        $FullPath.StartsWith('\\') -or
        [System.IO.Path]::GetPathRoot($FullPath).StartsWith('\\')) {
        throw "Caminho local absoluto exigido para arquivo de entrada: '$Path'."
    }
    $VolumeRoot = [System.IO.Path]::GetPathRoot($FullPath)
    if ($FullPath.Substring($VolumeRoot.Length).Contains(':')) {
        throw "ADS ou fluxo alternativo recusado para arquivo de entrada: '$FullPath'."
    }
    $RootPrefix = $Root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Arquivo de entrada fora da pasta Reporting: '$FullPath'."
    }

    $CurrentPath = $VolumeRoot
    foreach ($Segment in @($FullPath.Substring($VolumeRoot.Length) -split '[\\/]+' | Where-Object { $_ })) {
        $CurrentPath = Join-Path -Path $CurrentPath -ChildPath $Segment
        try {
            $Attributes = [System.IO.File]::GetAttributes($CurrentPath)
        }
        catch [System.IO.FileNotFoundException] { break }
        catch [System.IO.DirectoryNotFoundException] { break }
        if (($Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Arquivo de entrada atravessa reparse point: '$CurrentPath'."
        }
    }

    if (-not [System.IO.File]::Exists($FullPath)) {
        throw "Arquivo de entrada ausente: '$FullPath'."
    }
    return $FullPath
}

$ModulePath = Assert-ReportingProjectFile -Path $ModulePath
$ExampleConfigPath = Assert-ReportingProjectFile -Path $ExampleConfigPath


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
# TESTE 2 - ARQUIVO DE CONFIGURAÇÃO DE EXEMPLO
# ============================================================

Test-Result "Arquivo Reporting-Configuration.example.json encontrado" {

    if (-not (Test-Path $ExampleConfigPath)) {

        throw "Arquivo Reporting-Configuration.example.json não encontrado."
    }
}


# ============================================================
# IMPORTAR MÓDULO
# ============================================================

Import-Module $ModulePath -Force

$ReportingModulePath = [System.IO.Path]::GetFullPath($ModulePath)
$ReportingModuleMatches = @(Get-Module | Where-Object {
    $_.Path -and [System.IO.Path]::GetFullPath($_.Path) -eq $ReportingModulePath
})
if ($ReportingModuleMatches.Count -ne 1) {
    throw "A instância de Reporting-Functions não foi identificada univocamente."
}
$ReportingModuleInfo = $ReportingModuleMatches[0]

function Assert-ReportingTestPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot,

        [switch]$AllowRoot,

        [switch]$AllowMissing
    )

    $CanonicalRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
    $LexicalResult = & $script:ReportingModuleInfo {
        param ($CandidatePath, $CandidateRoot)
        Resolve-ReportingOutputPathLexically `
            -Path $CandidatePath `
            -AllowedRoot $CandidateRoot
    } $Path $CanonicalRoot

    $CanonicalPath = [System.IO.Path]::GetFullPath($LexicalResult.OutputPath)
    $RootPrefix = $CanonicalRoot.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )) + [System.IO.Path]::DirectorySeparatorChar
    $IsRoot = $CanonicalPath.Equals(
        $CanonicalRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )

    if ((-not $IsRoot -and -not $CanonicalPath.StartsWith(
                $RootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) -or ($IsRoot -and -not $AllowRoot)) {
        throw "Caminho de teste fora da raiz exclusiva permitida: '$CanonicalPath'."
    }

    $VolumeRoot = [System.IO.Path]::GetPathRoot($CanonicalPath)
    $CurrentPath = $VolumeRoot
    $RemainingPath = $CanonicalPath.Substring($VolumeRoot.Length)
    foreach ($Segment in @($RemainingPath -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($Segment)) { continue }
        $CurrentPath = Join-Path -Path $CurrentPath -ChildPath $Segment
        try {
            $CurrentItem = Get-Item -LiteralPath $CurrentPath -Force -ErrorAction Stop
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            if ($AllowMissing) { break }
            throw
        }
        catch [System.IO.FileNotFoundException] {
            if ($AllowMissing) { break }
            throw
        }
        catch [System.IO.DirectoryNotFoundException] {
            if ($AllowMissing) { break }
            throw
        }

        if (($CurrentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Caminho de teste atravessa reparse point: '$CurrentPath'."
        }
    }

    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $CanonicalPath)) {
        throw "Caminho de teste esperado não existe: '$CanonicalPath'."
    }

    return $CanonicalPath
}

# These checks reduce path risk for the test fixtures, but filesystem APIs do
# not make check-then-use atomic. This harness is not an OS-level sandbox.
function New-ReportingTestDirectory {
    param ([Parameter(Mandatory = $true)][string]$Path)

    $CanonicalPath = Assert-ReportingTestPath `
        -Path $Path `
        -AllowedRoot $script:TestWorkspace `
        -AllowMissing
    if (Test-Path -LiteralPath $CanonicalPath) {
        throw "Diretório de fixture já existe; não será reutilizado: '$CanonicalPath'."
    }

    New-Item -ItemType Directory -Path $CanonicalPath -ErrorAction Stop |
        Out-Null
    $null = Assert-ReportingTestPath `
        -Path $CanonicalPath `
        -AllowedRoot $script:TestWorkspace
}

function Set-ReportingTestFixture {
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [string]$Encoding = 'UTF8'
    )

    $CanonicalPath = Assert-ReportingTestPath `
        -Path $Path `
        -AllowedRoot $script:TestWorkspace `
        -AllowMissing
    $TextEncoding = switch ($Encoding.ToUpperInvariant()) {
        'UTF8' { [System.Text.UTF8Encoding]::new($false); break }
        'UTF8BOM' { [System.Text.UTF8Encoding]::new($true); break }
        'UNICODE' { [System.Text.Encoding]::Unicode; break }
        'ASCII' { [System.Text.Encoding]::ASCII; break }
        'DEFAULT' { [System.Text.Encoding]::Default; break }
        default { throw "Encoding de fixture não suportado: '$Encoding'." }
    }
    $Bytes = $TextEncoding.GetBytes($Value)
    $Stream = [System.IO.File]::Open(
        $CanonicalPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    try {
        $Stream.Write($Bytes, 0, $Bytes.Length)
    }
    finally {
        $Stream.Dispose()
    }
    $null = Assert-ReportingTestPath `
        -Path $CanonicalPath `
        -AllowedRoot $script:TestWorkspace
}
function Remove-ReportingTestEntry {
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowRoot
    )

    $CanonicalPath = Assert-ReportingTestPath `
        -Path $Path `
        -AllowedRoot $script:TestWorkspace `
        -AllowRoot:$AllowRoot `
        -AllowMissing
    if (-not (Test-Path -LiteralPath $CanonicalPath)) { return }

    $Item = Get-Item -LiteralPath $CanonicalPath -Force -ErrorAction Stop
    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Limpeza recusada para reparse point: '$CanonicalPath'."
    }

    if ($Item.PSIsContainer) {
        foreach ($ChildPath in [System.IO.Directory]::GetFileSystemEntries($CanonicalPath)) {
            Remove-ReportingTestEntry -Path $ChildPath
        }
        [System.IO.Directory]::Delete($CanonicalPath, $false)
        return
    }

    [System.IO.File]::Delete($CanonicalPath)
}

function Assert-ReportingTestConfigurationPaths {
    param (
        [Parameter(Mandatory = $true)][PSCustomObject]$Configuration,
        [switch]$AllowMissingSource
    )

    $null = Assert-ReportingTestPath `
        -Path ([string]$Configuration.Output.Directory) `
        -AllowedRoot $script:TestWorkspace `
        -AllowMissing

    foreach ($SourceProperty in $Configuration.Sources.PSObject.Properties) {
        $Source = $SourceProperty.Value
        if ($Source.Enabled -eq $true) {
            $null = Assert-ReportingTestPath `
                -Path ([string]$Source.Directory) `
                -AllowedRoot $script:TestWorkspace `
                -AllowMissing:$AllowMissingSource
            if ([string]$Source.FilePattern -match '[\\/]' -or
                [string]$Source.FilePattern -match '(^|\.)\.($|\.)') {
                throw "FilePattern de fixture contém caminho ou traversal: '$($Source.FilePattern)'."
            }
        }
    }
}

function New-ReportingTestDataset {
    param ([Parameter(Mandatory = $true)][PSCustomObject]$Configuration)

    Assert-ReportingTestConfigurationPaths -Configuration $Configuration
    New-ReportingDataset -Configuration $Configuration -AllowRealRead
}

Test-Result "Rejeitar formas ambíguas de caminho somente por validação lexical" {
    $ReportingModuleMatches = @(Get-Module | Where-Object { $_.Path -eq $ModulePath })
    if ($ReportingModuleMatches.Count -ne 1) {
        throw "A instância do módulo de Reporting não foi identificada univocamente."
    }

    $InvalidPaths = @(
        [PSCustomObject]@{ Path = "Reports:stream"; RequireAbsolute = $false },
        [PSCustomObject]@{ Path = "C:\Reports\file:stream"; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "C:Reports"; RequireAbsolute = $false },
        [PSCustomObject]@{ Path = "\Reports"; RequireAbsolute = $false },
        [PSCustomObject]@{ Path = "\\?\C:\Reports"; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "\\.\PhysicalDrive0"; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "C:\Reports\.\Output"; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "C:\Reports\..\Outside"; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "C:\Reports\Name."; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "C:\Reports\Name "; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "C:\Reports\NUL.txt"; RequireAbsolute = $true },
        [PSCustomObject]@{ Path = "C:\Reports\COM1.csv"; RequireAbsolute = $true }
    )

    foreach ($InvalidPath in $InvalidPaths) {
        $Rejected = $false
        try {
            & $ReportingModuleMatches[0] {
                param ($CandidatePath, $MustBeAbsolute)
                Assert-ReportingPathLexicallySafe `
                    -Path $CandidatePath `
                    -RequireAbsolute:$MustBeAbsolute
            } $InvalidPath.Path $InvalidPath.RequireAbsolute
        }
        catch {
            $Rejected = $true
        }

        if (-not $Rejected) {
            throw "O caminho lexicalmente inválido foi aceito: '$($InvalidPath.Path)'."
        }
    }

    $ValidPathResult = & $ReportingModuleMatches[0] {
        param ($CandidatePath)
        Assert-ReportingPathLexicallySafe -Path $CandidatePath
        return $true
    } "Reports"

    if ($ValidPathResult -ne $true) {
        throw "O caminho relativo simples foi rejeitado."
    }

    $DotPathResolution = & $ReportingModuleMatches[0] {
        param ($CandidatePath, $CandidateRoot)
        Resolve-ReportingOutputPathLexically `
            -Path $CandidatePath `
            -AllowedRoot $CandidateRoot
    } './Reports' 'C:\AuthorizedRoot'

    if ($DotPathResolution.OutputPath -ne 'C:\AuthorizedRoot\Reports') {
        throw "O prefixo relativo './' não foi normalizado sob a raiz autorizada."
    }

    $CaseInsensitivePathMatch = & $ReportingModuleMatches[0] {
        Assert-ReportingOutputPathMatches `
            -ExpectedPath 'C:\AuthorizedRoot\Reports' `
            -ResolvedPath 'c:\authorizedroot\reports'
        return $true
    }
    if ($CaseInsensitivePathMatch -ne $true) {
        throw "A comparação de caminhos canônicos não respeitou a semântica Windows."
    }

    $ChangedPathRejected = $false
    try {
        & $ReportingModuleMatches[0] {
            Assert-ReportingOutputPathMatches `
                -ExpectedPath 'C:\AuthorizedRoot\Reports' `
                -ResolvedPath 'C:\AuthorizedRoot\Other'
        }
    }
    catch {
        $ChangedPathRejected = $true
    }
    if (-not $ChangedPathRejected) {
        throw "Um caminho de saída alterado passou pela comparação."
    }
}


# ============================================================
# FIXTURES ISOLADAS EM MEMÓRIA E TEMP
# ============================================================

$TestTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$TestWorkspace = Join-Path $TestTempRoot (
    "Reporting-Test-" + [guid]::NewGuid().ToString("N")
)
$TestWorkspaceCreated = $false
$null = Assert-ReportingTestPath `
    -Path $TestTempRoot `
    -AllowedRoot $TestTempRoot `
    -AllowRoot
$TestWorkspace = Assert-ReportingTestPath `
    -Path $TestWorkspace `
    -AllowedRoot $TestTempRoot `
    -AllowMissing
if (Test-Path -LiteralPath $TestWorkspace) {
    throw "A raiz temporária exclusiva já existe; execução bloqueada: '$TestWorkspace'."
}
$TestInputDirectory = Join-Path $TestWorkspace "Input"

try {
    # New-Item sem -Force falha se outra execução já tiver criado o GUID.
    New-Item -ItemType Directory -Path $TestWorkspace -ErrorAction Stop | Out-Null
    $TestWorkspaceCreated = $true
    $null = Assert-ReportingTestPath `
        -Path $TestWorkspace `
        -AllowedRoot $TestTempRoot

    New-ReportingTestDirectory -Path $TestInputDirectory

    Set-ReportingTestFixture `
        -Path (Join-Path $TestInputDirectory "ComputerInventory_fixture.csv") `
        -Value "ComputerName,Manufacturer`nREPORTING-TEST-PC,Example"

    Set-ReportingTestFixture `
        -Path (Join-Path $TestInputDirectory "ComputerInventory_fixture.json") `
        -Value '{"ComputerName":"REPORTING-TEST-PC","Manufacturer":"Example"}'

    $Configuration = [PSCustomObject]@{
        SimulationMode = $true
        Reporting = [PSCustomObject]@{
            IncludeSummary = $true
            IncludeDetails = $true
            IncludeTimestamp = $true
        }
        Output = [PSCustomObject]@{
            Directory = Join-Path $TestWorkspace "Output"
            Formats = @("JSON", "CSV")
        }
        Sources = [PSCustomObject]@{
            ComputerInventory = [PSCustomObject]@{
                Enabled = $true
                Directory = $TestInputDirectory
                FilePattern = "ComputerInventory_*"
                Formats = @("JSON", "CSV")
            }
            ADUsers = [PSCustomObject]@{
                Enabled = $false
                Directory = ""
                FilePattern = "*.csv"
                Formats = @("CSV")
            }
            ADGroups = [PSCustomObject]@{
                Enabled = $false
                Directory = ""
                FilePattern = "*.csv"
                Formats = @("CSV")
            }
            GPOs = [PSCustomObject]@{
                Enabled = $false
                Directory = ""
                FilePattern = "*.csv"
                Formats = @("CSV")
            }
            EntraUsers = [PSCustomObject]@{
                Enabled = $false
                Directory = ""
                FilePattern = "*.csv"
                Formats = @("CSV")
            }
        }
    }

    function Copy-ReportingTestConfiguration {
        $Configuration | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }

# ============================================================
# TESTES FUNCIONAIS
# ============================================================

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
        -Source $Source `
        -AllowRealRead)

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
        -Source $Source `
        -AllowRealRead)

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
            -Source $Source `
            -AllowRealRead |
        Where-Object {
            $_.Extension -eq ".csv"
        }
    ) | Select-Object -First 1

    if ($null -eq $CSVFile) {

        throw "Nenhum arquivo CSV foi encontrado."
    }

    $Result = Get-ReportingData `
        -File $CSVFile `
        -SourceName "ComputerInventory" `
        -AllowRealRead

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
            -Source $Source `
            -AllowRealRead |
        Where-Object {
            $_.Extension -eq ".json"
        }
    ) | Select-Object -First 1

    if ($null -eq $JSONFile) {

        throw "Nenhum arquivo JSON foi encontrado."
    }

    $Result = Get-ReportingData `
        -File $JSONFile `
        -SourceName "ComputerInventory" `
        -AllowRealRead

    if ($Result.Success -ne $true) {

        throw "O arquivo JSON não foi carregado corretamente."
    }

    if ($Result.Format -ne "JSON") {

        throw "O formato identificado não corresponde a JSON."
    }

    $WildcardFilePath = Join-Path $TestInputDirectory 'ComputerInventory_[1].json'
    Set-ReportingTestFixture `
        -Path $WildcardFilePath `
        -Value '{"ComputerName":"REPORTING-META-PC"}'
    $WildcardResult = Get-ReportingData `
        -File ([System.IO.FileInfo]::new($WildcardFilePath)) `
        -SourceName "ComputerInventory" `
        -AllowRealRead
    if ($WildcardResult.Success -ne $true -or
        $WildcardResult.Data.ComputerName -ne 'REPORTING-META-PC') {
        throw "Get-ReportingData não leu literalmente o arquivo cujo nome contém metacaracteres."
    }
}


# ============================================================
# TESTE 11 - RESUMO
# ============================================================

Test-Result "Gerar resumo dos dados" {

    $Source = $Configuration.Sources.ComputerInventory

    $Files = @(Get-ReportingSourceFiles `
        -Source $Source `
        -AllowRealRead)

    $Data = @()

    foreach ($File in $Files) {

        $Data += Get-ReportingData `
            -File $File `
            -SourceName "ComputerInventory" `
            -AllowRealRead
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

    $Dataset = New-ReportingTestDataset `
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

    $Dataset = New-ReportingTestDataset -Configuration $Configuration

    $Export = Export-ReportingDataset `
        -Dataset $Dataset `
        -Configuration $Configuration `
        -AllowedRoot $TestWorkspace

    if ($Export.Success -ne $true) {
        throw "A exportação simulada não retornou sucesso."
    }

    if ($Export.SimulationMode -ne $true) {
        throw "O resultado deveria indicar modo de simulação."
    }

    if (@($Export.Files).Count -ne 3) {
        throw "Deveriam ser previstos um JSON e dois CSVs (resumo e detalhes)."
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

    Assert-ReportingTestConfigurationPaths -Configuration $Configuration
    $Result = Invoke-Reporting -Configuration $Configuration -AllowRealRead -AllowedRoot $TestWorkspace

    if ($Result.Success -ne $true) {
        throw "Invoke-Reporting não retornou sucesso."
    }

    if ($Result.Summary.TotalFiles -eq 0) {
        throw "Invoke-Reporting não processou arquivos."
    }

    if ($Result.Summary.FailedFiles -ne 0) {
        throw "Invoke-Reporting identificou falhas."
    }

    if (@($Result.Files).Count -ne 3) {
        throw "A simulação deveria informar um JSON e dois CSVs."
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
        -Path $TestWorkspace `
        -ChildPath ("Reporting-InvalidFormat-" + [guid]::NewGuid().ToString("N"))

    $TestConfiguration.Output.Directory = $TestOutputDirectory
    $TestConfiguration.Output.Formats = @("INVALID")
    $TestConfiguration.SimulationMode = $false

    $Dataset = New-ReportingTestDataset -Configuration $TestConfiguration
    $ErrorCaptured = $false

    try {
        Export-ReportingDataset `
            -Dataset $Dataset `
            -Configuration $TestConfiguration `
            -AllowRealOperation `
            -AllowedRoot $TestWorkspace `
            -Confirm:$false |
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

    $TestConfiguration = Copy-ReportingTestConfiguration

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

    $TestConfiguration = Copy-ReportingTestConfiguration

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

    $TestConfiguration = Copy-ReportingTestConfiguration

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

    $TestOutputDirectory = Join-Path $TestWorkspace (
        "Reporting-RealExport-" + [guid]::NewGuid().ToString("N")
    )

    try {
        $TestConfiguration = Copy-ReportingTestConfiguration

        $TestConfiguration.Output.Directory = $TestOutputDirectory
        $TestConfiguration.Output.Formats = @("JSON", "CSV")
        $TestConfiguration.SimulationMode = $false

        $Dataset = New-ReportingTestDataset -Configuration $TestConfiguration

        $Export = Export-ReportingDataset `
            -Dataset $Dataset `
            -Configuration $TestConfiguration `
            -AllowRealOperation `
            -AllowedRoot $TestWorkspace `
            -Confirm:$false

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

        if ($CsvFiles.Count -ne 2) {
            throw "Esperados 2 arquivos CSV; encontrados: $($CsvFiles.Count)."
        }

        foreach ($File in @($JsonFiles) + @($CsvFiles)) {
            if ($File.Length -le 0) {
                throw "O arquivo exportado está vazio: $($File.FullName)"
            }
        }

        Get-Content -LiteralPath $JsonFiles[0].FullName -Raw |
            ConvertFrom-Json |
            Out-Null

        if ($Export.Files.Count -ne 3) {
            throw "O resultado deveria informar os três arquivos exportados."
        }
    }
    finally {
        if (Test-Path -LiteralPath $TestOutputDirectory -PathType Container) {
            Remove-ReportingTestEntry -Path $TestOutputDirectory
        }
    }
}

# ============================================================
# TESTE 20 - FALHA NA GRAVAÇÃO
# ============================================================

Test-Result "Bloquear exportação quando o destino impede gravação" {

    $TempRoot = Join-Path $TestWorkspace (
        "Reporting-WriteFailure-" + [guid]::NewGuid().ToString("N")
    )

    $BlockingFile = Join-Path $TempRoot "DestinoOcupado"
    $TestOutputDirectory = Join-Path $BlockingFile "Reports"

    try {
        New-ReportingTestDirectory -Path $TempRoot
        Set-ReportingTestFixture -Path $BlockingFile -Value "arquivo de bloqueio"

        $TestConfiguration = Copy-ReportingTestConfiguration

        $TestConfiguration.Output.Directory = $TestOutputDirectory
        $TestConfiguration.Output.Formats = @("JSON")
        $TestConfiguration.SimulationMode = $false

        $Dataset = New-ReportingTestDataset -Configuration $TestConfiguration

        $ExportFailed = $false

        try {
            Export-ReportingDataset `
                -Dataset $Dataset `
                -Configuration $TestConfiguration `
                -AllowRealOperation `
                -AllowedRoot $TestWorkspace `
                -Confirm:$false |
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
            Remove-ReportingTestEntry -Path $TempRoot
        }
    }
}
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

# Teste 21 - Bloquear formatos duplicados antes de criar a pasta
Test-Result "Bloquear formatos duplicados antes de criar a pasta" {
    $DuplicateConfig = Copy-ReportingTestConfiguration
    $DuplicateOutput = Join-Path $TestWorkspace ("Reporting-Duplicados-" + [guid]::NewGuid().ToString("N"))
    $DuplicateConfig.Output.Directory = $DuplicateOutput
    $DuplicateConfig.Output.Formats = @("JSON", "json")
    $DuplicateConfig.SimulationMode = $false

    try {
        $DuplicateDataset = New-ReportingTestDataset -Configuration $DuplicateConfig
        $DuplicateError = $null

        try {
            Export-ReportingDataset -Configuration $DuplicateConfig -Dataset $DuplicateDataset -AllowRealOperation -AllowedRoot $TestWorkspace -Confirm:$false | Out-Null
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
            Remove-ReportingTestEntry -Path $DuplicateOutput
        }
    }
}

# Teste 22 - Validar conteúdo do CSV exportado
Test-Result "Validar cabeçalhos e registros do CSV exportado" {
    $CsvConfig = Copy-ReportingTestConfiguration
    $CsvOutput = Join-Path $TestWorkspace ("Reporting-CSV-" + [guid]::NewGuid().ToString("N"))
    $CsvConfig.Output.Directory = $CsvOutput
    $CsvConfig.Output.Formats = @("CSV")
    $CsvConfig.SimulationMode = $false

    try {
        $CsvDataset = New-ReportingTestDataset -Configuration $CsvConfig
        $CsvResult = Export-ReportingDataset -Configuration $CsvConfig -Dataset $CsvDataset -AllowRealOperation -AllowedRoot $TestWorkspace -Confirm:$false
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
            Remove-ReportingTestEntry -Path $CsvOutput
        }
    }
}
# TESTE 23 - Opções de inclusão aplicadas na exportação
Test-Result "Aplicar opções de resumo, detalhes e timestamp" {
    $OptionConfig = Copy-ReportingTestConfiguration
    $OptionConfig.Reporting.IncludeSummary = $false
    $OptionConfig.Reporting.IncludeTimestamp = $false
    $OptionConfig.Output.Formats = @("JSON", "CSV")
    $OptionOutput = Join-Path $TestWorkspace (
        "Reporting-Options-" + [guid]::NewGuid().ToString("N")
    )
    $OptionConfig.Output.Directory = $OptionOutput
    $OptionConfig.SimulationMode = $false

    try {
        $OptionDataset = New-ReportingTestDataset -Configuration $OptionConfig
        $OptionExport = Export-ReportingDataset `
            -Dataset $OptionDataset `
            -Configuration $OptionConfig `
            -AllowRealOperation `
            -AllowedRoot $TestWorkspace `
            -Confirm:$false

        $JsonPath = @($OptionExport.Files | Where-Object { $_ -like "*.json" }) |
            Select-Object -First 1
        $DetailsPath = @($OptionExport.Files | Where-Object { $_ -like "*Details*.csv" }) |
            Select-Object -First 1

        if (-not $JsonPath -or -not $DetailsPath) {
            throw "A exportação não gerou JSON e CSV de detalhes."
        }

        $Json = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
        if ($null -ne $Json.Summary -or $null -ne $Json.GeneratedAt) {
            throw "O JSON incluiu campos desativados na configuração."
        }

        if (@(Get-ChildItem -LiteralPath $OptionOutput -Filter "Reporting-Summary-*.csv" -File).Count -gt 0) {
            throw "Foi exportado CSV de resumo apesar de IncludeSummary=false."
        }

        $DetailRows = @(Import-Csv -LiteralPath $DetailsPath)
        if ($DetailRows.Count -eq 0 -or
            $DetailRows[0].PSObject.Properties.Name -contains "GeneratedAt") {
            throw "O CSV de detalhes está vazio ou incluiu timestamp desativado."
        }
    }
    finally {
        if (Test-Path -LiteralPath $OptionOutput -PathType Container) {
            Remove-ReportingTestEntry -Path $OptionOutput
        }
    }
}

# TESTE 24 - Falha de origem não relatada como sucesso
Test-Result "Falhas ao processar fontes afetam o resultado geral" {
    $InvalidJsonPath = Join-Path $TestInputDirectory "ComputerInventory_invalid.json"
    Set-ReportingTestFixture -Path $InvalidJsonPath -Value "{ invalid json" -Encoding UTF8

    Assert-ReportingTestConfigurationPaths -Configuration $Configuration
    $Result = Invoke-Reporting -Configuration $Configuration -AllowRealRead -AllowedRoot $TestWorkspace

    if ($Result.Success -ne $false -or $Result.Summary.FailedFiles -ne 1) {
        throw "Falha de leitura de origem deveria tornar o resultado geral malsucedido."
    }
}

# TESTE 25 - Configuração SimulationMode tipada
Test-Result "Rejeitar SimulationMode não Boolean" {
    $InvalidConfiguration = Copy-ReportingTestConfiguration
    $InvalidConfiguration.SimulationMode = "true"

    $Rejected = $false
    try {
        Test-ReportingConfiguration -Configuration $InvalidConfiguration |
            Out-Null
    }
    catch {
        $Rejected = $_.Exception.Message -match "SimulationMode"
    }

    if (-not $Rejected) {
        throw "SimulationMode não Boolean deveria ser rejeitado."
    }
}

# TESTE 26 - Opções de relatório tipadas
Test-Result "Rejeitar flags de relatório não Boolean" {
    $InvalidConfiguration = Copy-ReportingTestConfiguration
    $InvalidConfiguration.Reporting.IncludeDetails = "true"

    $Rejected = $false
    try {
        Test-ReportingConfiguration -Configuration $InvalidConfiguration |
            Out-Null
    }
    catch {
        $Rejected = $_.Exception.Message -match "IncludeDetails"
    }

    if (-not $Rejected) {
        throw "Flags de relatório não Boolean deveriam ser rejeitadas."
    }
}

# TESTE 27 - Fontes vazias são um dataset válido
Test-Result "Aceitar dataset sem arquivos de origem" {
    $EmptyDirectory = Join-Path $TestWorkspace "EmptyInput"
    New-ReportingTestDirectory -Path $EmptyDirectory

    $EmptyConfiguration = Copy-ReportingTestConfiguration
    $EmptyConfiguration.Sources.ComputerInventory.Directory = $EmptyDirectory
    $EmptyDataset = New-ReportingTestDataset -Configuration $EmptyConfiguration

    if ($EmptyDataset.Summary.TotalFiles -ne 0 -or
        $EmptyDataset.Summary.FailedFiles -ne 0) {
        throw "O resumo vazio deveria conter zero arquivos e zero falhas."
    }
}

# TESTE 28 - Bloquear exportação real sem autorização
Test-Result "Bloquear exportação real sem AllowRealOperation" {
    $UnauthorizedConfig = Copy-ReportingTestConfiguration
    $UnauthorizedConfig.SimulationMode = $false
    $UnauthorizedConfig.Output.Directory = Join-Path $TestWorkspace "UnauthorizedOutput"
    $DatasetFixture = [PSCustomObject]@{ Files = @(); Summary = [PSCustomObject]@{ TotalFiles = 0 } }
    Assert-ReportingTestConfigurationPaths -Configuration $UnauthorizedConfig

    $Blocked = $false
    try {
        Export-ReportingDataset -Dataset $DatasetFixture -Configuration $UnauthorizedConfig -AllowedRoot $TestWorkspace | Out-Null
    }
    catch {
        $Blocked = $_.Exception.Message -match "AllowRealOperation"
    }

    if (-not $Blocked -or (Test-Path -LiteralPath $UnauthorizedConfig.Output.Directory)) {
        throw "A exportação sem autorização não foi bloqueada antes de criar o destino."
    }
}

# TESTE 29 - WhatIf não lê fontes nem grava arquivos
Test-Result "WhatIf retorna Preview sem materializar dataset ou saída" {
    $PreviewConfig = Copy-ReportingTestConfiguration
    $PreviewConfig.SimulationMode = $false
    $PreviewConfig.Output.Directory = Join-Path $TestWorkspace "WhatIfOutput"
    $PreviewConfig.Sources.ComputerInventory.Directory = Join-Path $TestWorkspace "MissingInput"

    Assert-ReportingTestConfigurationPaths `
        -Configuration $PreviewConfig `
        -AllowMissingSource
    $PreviewResult = Invoke-Reporting -Configuration $PreviewConfig -WhatIf

    if ($PreviewResult.Mode -ne "Preview" -or
        $PreviewResult.Cancelled -ne $false -or
        $PreviewResult.SimulationMode -ne $false -or
        (Test-Path -LiteralPath $PreviewConfig.Output.Directory)) {
        throw "WhatIf não retornou Preview sem criar a pasta de saída."
    }
}

# TESTE 31 - Bloquear leituras reais sem autorização explícita
Test-Result "Bloquear leituras reais sem autorização explícita" {
    $ReadConfig = Copy-ReportingTestConfiguration
    $ReadConfig.SimulationMode = $true
    $ReadOperations = @(
        { Get-ReportingSourceFiles -Source $ReadConfig.Sources.ComputerInventory },
        { Get-ReportingData -File ([System.IO.FileInfo]::new((Join-Path $TestWorkspace 'not-present.json'))) },
        { New-ReportingDataset -Configuration $ReadConfig },
        { Invoke-Reporting -Configuration $ReadConfig }
    )

    foreach ($ReadOperation in $ReadOperations) {
        $Rejected = $false
        try {
            & $ReadOperation | Out-Null
        }
        catch {
            $Rejected = $_.FullyQualifiedErrorId.StartsWith(
                'Reporting.ReadAuthorizationRequired',
                [System.StringComparison]::Ordinal
            )
        }

        if (-not $Rejected) {
            throw "Uma operação de leitura não bloqueou sem -AllowRealRead."
        }
    }
}

# TESTE 32 - Rejeitar destinos fora da raiz autorizada
Test-Result "Rejeitar caminho absoluto fora de AllowedRoot" {
    $OutsideConfig = Copy-ReportingTestConfiguration
    $OutsideConfig.SimulationMode = $false
    $OutsideConfig.Output.Directory = Join-Path ([System.IO.Path]::GetTempPath()) ("Reporting-Outside-" + [guid]::NewGuid().ToString("N"))
    $DatasetFixture = [PSCustomObject]@{ Files = @(); Summary = [PSCustomObject]@{ TotalFiles = 0 } }

    $Rejected = $false
    try {
        Export-ReportingDataset -Dataset $DatasetFixture -Configuration $OutsideConfig -AllowRealOperation -AllowedRoot $TestWorkspace -Confirm:$false | Out-Null
    }
    catch {
        $Rejected = $_.Exception.Message -match "fora da raiz permitida"
    }

    if (-not $Rejected) {
        throw "Um destino externo à raiz permitida não foi rejeitado."
    }
}

# TESTE 33 - WhatIf bloqueia leituras diretas da interface interativa
Test-Result "WhatIf bloqueia resumo e listagem de arquivos antes da leitura" {
    $EntryPointPath = Join-Path $PSScriptRoot 'Reporting.ps1'
    $EntryPointText = Get-Content -LiteralPath $EntryPointPath -Raw -ErrorAction Stop

    $SummaryStart = $EntryPointText.IndexOf('function Show-Summary', [System.StringComparison]::Ordinal)
    $SummaryEnd = $EntryPointText.IndexOf('function Invoke-Report', $SummaryStart, [System.StringComparison]::Ordinal)
    if ($SummaryStart -lt 0 -or $SummaryEnd -le $SummaryStart) {
        throw 'Não foi possível delimitar estaticamente Show-Summary.'
    }
    $SummaryBody = $EntryPointText.Substring($SummaryStart, $SummaryEnd - $SummaryStart)
    $SummaryWhatIf = $SummaryBody.IndexOf('if ($WhatIfPreference)', [System.StringComparison]::Ordinal)
    $SummaryRead = $SummaryBody.IndexOf('New-ReportingDataset', [System.StringComparison]::Ordinal)
    if ($SummaryWhatIf -lt 0 -or $SummaryRead -lt 0 -or $SummaryWhatIf -ge $SummaryRead) {
        throw 'Show-Summary não bloqueia WhatIf antes da leitura de fontes.'
    }

    $FileMenuStart = $EntryPointText.IndexOf('"4" {', [System.StringComparison]::Ordinal)
    $FileMenuEnd = $EntryPointText.IndexOf('"0" {', $FileMenuStart, [System.StringComparison]::Ordinal)
    if ($FileMenuStart -lt 0 -or $FileMenuEnd -le $FileMenuStart) {
        throw 'Não foi possível delimitar estaticamente a opção 4.'
    }
    $FileMenuBody = $EntryPointText.Substring($FileMenuStart, $FileMenuEnd - $FileMenuStart)
    $MenuWhatIf = $FileMenuBody.IndexOf('if ($WhatIfPreference)', [System.StringComparison]::Ordinal)
    $MenuRead = $FileMenuBody.IndexOf('Get-ReportingSourceFiles', [System.StringComparison]::Ordinal)
    if ($MenuWhatIf -lt 0 -or $MenuRead -lt 0 -or $MenuWhatIf -ge $MenuRead) {
        throw 'A opção 4 não bloqueia WhatIf antes da enumeração de arquivos.'
    }

    $FunctionsPath = Join-Path $PSScriptRoot 'Reporting-Functions.psm1'
    $FunctionsText = Get-Content -LiteralPath $FunctionsPath -Raw -ErrorAction Stop
    $DirectReadFunctions = @(
        [PSCustomObject]@{
            Start = 'function Get-ReportingSourceFiles {'
            End = 'function Get-ReportingData {'
            Read = 'Get-ChildItem'
        },
        [PSCustomObject]@{
            Start = 'function Get-ReportingData {'
            End = 'function Get-ReportingSummary {'
            Read = 'Get-Content'
        },
        [PSCustomObject]@{
            Start = 'function New-ReportingDataset {'
            End = 'function Write-ReportingTextCreateNew {'
            Read = 'Get-ReportingSourceFiles'
        }
    )

    foreach ($DirectReadFunction in $DirectReadFunctions) {
        $FunctionStart = $FunctionsText.IndexOf($DirectReadFunction.Start, [System.StringComparison]::Ordinal)
        $FunctionEnd = $FunctionsText.IndexOf($DirectReadFunction.End, $FunctionStart, [System.StringComparison]::Ordinal)
        if ($FunctionStart -lt 0 -or $FunctionEnd -le $FunctionStart) {
            throw "Não foi possível delimitar estaticamente '$($DirectReadFunction.Start)'."
        }
        $FunctionBody = $FunctionsText.Substring($FunctionStart, $FunctionEnd - $FunctionStart)
        $WhatIfPosition = $FunctionBody.IndexOf('if ($WhatIfPreference)', [System.StringComparison]::Ordinal)
        $ReadPosition = $FunctionBody.IndexOf($DirectReadFunction.Read, [System.StringComparison]::Ordinal)
        if ($WhatIfPosition -lt 0 -or $ReadPosition -lt 0 -or $WhatIfPosition -ge $ReadPosition) {
            throw "WhatIf não bloqueia leitura em '$($DirectReadFunction.Start)'."
        }
    }

    $DataStart = $FunctionsText.IndexOf('function Get-ReportingData {', [System.StringComparison]::Ordinal)
    $DataEnd = $FunctionsText.IndexOf('function Get-ReportingSummary {', $DataStart, [System.StringComparison]::Ordinal)
    $DataBody = $FunctionsText.Substring($DataStart, $DataEnd - $DataStart)
    if ($DataBody -notmatch '(?s)Get-Content\s+`?\s*-LiteralPath\s+\$File\.FullName' -or
        $DataBody -notmatch '(?s)Import-Csv\s+`?\s*-LiteralPath\s+\$File\.FullName') {
        throw 'Get-ReportingData deve usar LiteralPath para nomes de arquivo sem interpretação de wildcard.'
    }

    $ReadProbeCounters = [PSCustomObject]@{
        GetChildItem = 0
        GetContent = 0
        ImportCsv = 0
    }
    $GetChildItemStub = {
        $ReadProbeCounters.GetChildItem++
        throw 'WhatIf read probe blocked Get-ChildItem.'
    }.GetNewClosure()
    $GetContentStub = {
        $ReadProbeCounters.GetContent++
        throw 'WhatIf read probe blocked Get-Content.'
    }.GetNewClosure()
    $ImportCsvStub = {
        $ReadProbeCounters.ImportCsv++
        throw 'WhatIf read probe blocked Import-Csv.'
    }.GetNewClosure()
    $ReadProbeStubs = @{
        'Get-ChildItem' = $GetChildItemStub
        'Get-Content' = $GetContentStub
        'Import-Csv' = $ImportCsvStub
    }
    $ReadProbeFile = [System.IO.FileInfo]::new(
        (Join-Path $TestWorkspace 'missing-[whatif].json')
    )
    $ReadProbeSource = [PSCustomObject]@{
        Directory = Join-Path $TestWorkspace 'missing-[whatif]'
        FilePattern = '*.json'
        Formats = @('json')
        Enabled = $true
    }
    $ReadProbeConfiguration = Copy-ReportingTestConfiguration
    $ReadProbeConfiguration.Sources.ComputerInventory.Directory = $ReadProbeSource.Directory

    & $ReportingModuleInfo {
        param ($SourceFixture, $ConfigurationFixture, $FileFixture, $Counters, $Stubs)

        $SavedWhatIfPreference = $WhatIfPreference
        $FunctionNames = @('Get-ChildItem', 'Get-Content', 'Import-Csv')
        $OriginalFunctions = @{}
        foreach ($FunctionName in $FunctionNames) {
            $FunctionPath = "Function:\script:$FunctionName"
            $ExistingFunction = Get-Item -LiteralPath $FunctionPath -ErrorAction SilentlyContinue
            if ($null -ne $ExistingFunction) {
                $OriginalFunctions[$FunctionName] = $ExistingFunction.ScriptBlock
            }
        }

        try {
            foreach ($FunctionName in $FunctionNames) {
                Set-Item `
                    -LiteralPath "Function:\script:$FunctionName" `
                    -Value $Stubs[$FunctionName] `
                    -Force |
                    Out-Null
            }
            $WhatIfPreference = $true

            $SourceResults = @(Get-ReportingSourceFiles -Source $SourceFixture -AllowRealRead)
            $DataResult = Get-ReportingData -File $FileFixture -AllowRealRead
            $DatasetResult = New-ReportingDataset -Configuration $ConfigurationFixture -AllowRealRead

            if ($SourceResults.Count -ne 0 -or
                $DataResult.Mode -ne 'Preview' -or
                $DatasetResult.Mode -ne 'Preview' -or
                $DatasetResult.Files.Count -ne 0) {
                throw 'As APIs diretas não retornaram os estados Preview esperados.'
            }

            if ($Counters.GetChildItem -ne 0 -or
                $Counters.GetContent -ne 0 -or
                $Counters.ImportCsv -ne 0) {
                throw 'Um cmdlet de leitura foi alcançado apesar de WhatIfPreference.'
            }
        }
        finally {
            $WhatIfPreference = $SavedWhatIfPreference
            foreach ($FunctionName in $FunctionNames) {
                $FunctionPath = "Function:\script:$FunctionName"
                if ($OriginalFunctions.ContainsKey($FunctionName)) {
                    Set-Item -LiteralPath $FunctionPath -Value $OriginalFunctions[$FunctionName] -Force | Out-Null
                }
                else {
                    Remove-Item -LiteralPath $FunctionPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } $ReadProbeSource $ReadProbeConfiguration $ReadProbeFile $ReadProbeCounters $ReadProbeStubs
}
}
finally {
    if ($TestWorkspaceCreated) {
        Remove-ReportingTestEntry -Path $TestWorkspace -AllowRoot
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

# V1 EXIT CODE HANDLING
if ($FailedTests -gt 0) {
    exit 1
}

exit 0
