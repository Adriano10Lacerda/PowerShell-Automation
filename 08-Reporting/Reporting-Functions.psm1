function Test-ReportingConfiguration {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    if ($Configuration.SimulationMode -isnot [bool]) {
        $Errors += "A configuração 'SimulationMode' deve ser definida como Boolean."
    }

    if ($null -eq $Configuration.Reporting) {
        $Errors += "A seção 'Reporting' não foi definida."
    }
    else {
        foreach ($OptionName in @("IncludeSummary", "IncludeDetails", "IncludeTimestamp")) {
            if ($Configuration.Reporting.$OptionName -isnot [bool]) {
                $Errors += "A propriedade 'Reporting.$OptionName' deve ser definida como Boolean."
            }
        }

        if ($Configuration.Reporting.IncludeSummary -isnot [bool] -or
            $Configuration.Reporting.IncludeDetails -isnot [bool]) {
            $Errors += "As opções de conteúdo do relatório devem ser Boolean."
        }
        elseif (-not $Configuration.Reporting.IncludeSummary -and
            -not $Configuration.Reporting.IncludeDetails) {
            $Errors += "Ative IncludeSummary ou IncludeDetails para produzir conteúdo."
        }
    }

    if ($null -eq $Configuration.Output) {
        $Errors += "A seção 'Output' não foi definida."
    }

    if ($null -eq $Configuration.Sources) {
        $Errors += "A seção 'Sources' não foi definida."
    }

    if ($null -ne $Configuration.Output) {

        if ([string]::IsNullOrWhiteSpace([string]$Configuration.Output.Directory)) {
            $Errors += "A propriedade 'Output.Directory' não foi definida."
        }

        if ($null -eq $Configuration.Output.Formats) {

            $Errors += "A propriedade 'Output.Formats' não foi definida."
        }
        elseif (@($Configuration.Output.Formats).Count -eq 0) {

            $Errors += "A propriedade 'Output.Formats' deve possuir pelo menos um formato."
        }
    }

    if ($null -ne $Configuration.Sources) {

        $SourceProperties = $Configuration.Sources.PSObject.Properties

        if ($SourceProperties.Count -eq 0) {

            $Errors += "A seção 'Sources' deve possuir pelo menos uma fonte de dados."
        }

        foreach ($SourceProperty in $SourceProperties) {

            $Source = $SourceProperty.Value
            $SourceName = $SourceProperty.Name

            if ($Source.Enabled -isnot [bool]) {
                $Errors += "A propriedade 'Enabled' deve ser Boolean para a fonte '$SourceName'."
            }

            if ($Source.Enabled -eq $true) {

                if ([string]::IsNullOrWhiteSpace($Source.Directory)) {
                    $Errors += "O diretório não foi definido para a fonte '$SourceName'."
                }

                if ([string]::IsNullOrWhiteSpace($Source.FilePattern)) {
                    $Errors += "O 'FilePattern' não foi definido para a fonte '$SourceName'."
                }

                if ($null -eq $Source.Formats -or @($Source.Formats).Count -eq 0) {
                    $Errors += "Nenhum formato foi definido para a fonte '$SourceName'."
                }
            }
        }
    }

    if ($Errors.Count -gt 0) {
        throw ($Errors -join "`n")
    }

    return $true
}


function Resolve-ReportingPath {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {

        return $Path
    }

    return Join-Path `
        -Path $PSScriptRoot `
        -ChildPath $Path
}


function Assert-ReportingPathLexicallySafe {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$RequireAbsolute
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "O caminho não pode ser vazio."
    }

    if ($Path.StartsWith('\\?\') -or
        $Path.StartsWith('\\.\') -or
        $Path.StartsWith('\??\') -or
        $Path.StartsWith('//?/') -or
        $Path.StartsWith('//./')) {
        throw "Namespaces de dispositivo não são permitidos em caminhos de saída."
    }

    if ($Path.StartsWith('\\') -or $Path.StartsWith('//')) {
        throw "Caminhos UNC não são permitidos em caminhos de saída."
    }

    $IsFullyQualified = [System.IO.Path]::IsPathFullyQualified($Path)
    if (($RequireAbsolute -and -not $IsFullyQualified) -or
        ([System.IO.Path]::IsPathRooted($Path) -and -not $IsFullyQualified)) {
        throw "Caminhos relativos a unidade ou raiz não são permitidos."
    }

    $ColonIndexes = @()
    for ($Index = 0; $Index -lt $Path.Length; $Index++) {
        if ($Path[$Index] -eq ':') { $ColonIndexes += $Index }
    }

    if ($ColonIndexes.Count -gt 0) {
        $IsDrivePrefix = $IsFullyQualified -and
            $ColonIndexes.Count -eq 1 -and
            $ColonIndexes[0] -eq 1 -and
            $Path.Length -gt 2 -and
            ($Path[2] -eq '\' -or $Path[2] -eq '/')
        if (-not $IsDrivePrefix) {
            throw "ADS e prefixos de unidade relativos não são permitidos."
        }
    }

    if ($Path.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) {
        throw "O caminho contém caracteres inválidos."
    }

    $Segments = @($Path -split '[\\/]')
    foreach ($Segment in $Segments) {
        if ([string]::IsNullOrEmpty($Segment)) { continue }
        if ($Segment -eq '..') {
            throw "O segmento '..' não é permitido em caminhos de saída."
        }
        if ($Segment -eq '.' -and
            ($RequireAbsolute -or [System.IO.Path]::IsPathRooted($Path))) {
            throw "O segmento '.' não é permitido em raízes ou caminhos absolutos."
        }
        if ($Segment -eq '.') {
            continue
        }
        if ($Segment.EndsWith('.') -or $Segment.EndsWith(' ')) {
            throw "Segmentos terminados em ponto ou espaço não são permitidos."
        }

        if ($Segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\..*)?$') {
            throw "Nomes de dispositivo reservados não são permitidos."
        }
    }
}


function Resolve-ReportingOutputPathLexically {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    Assert-ReportingPathLexicallySafe -Path $AllowedRoot -RequireAbsolute
    Assert-ReportingPathLexicallySafe -Path $Path

    $CanonicalRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
    $CanonicalOutput = if ([System.IO.Path]::IsPathFullyQualified($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path -Path $CanonicalRoot -ChildPath $Path))
    }

    Assert-ReportingPathLexicallySafe -Path $CanonicalRoot -RequireAbsolute
    Assert-ReportingPathLexicallySafe -Path $CanonicalOutput -RequireAbsolute

    $RootPrefix = $CanonicalRoot.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $CanonicalOutput.Equals($CanonicalRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $CanonicalOutput.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "O destino de saída está fora da raiz permitida '$CanonicalRoot'."
    }

    return [PSCustomObject]@{
        AllowedRoot = $CanonicalRoot
        OutputPath  = $CanonicalOutput
    }
}


function Resolve-ReportingOutputPath {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    $CanonicalPaths = Resolve-ReportingOutputPathLexically `
        -Path $Path `
        -AllowedRoot $AllowedRoot
    $CanonicalRoot = $CanonicalPaths.AllowedRoot
    if (-not (Test-Path -LiteralPath $CanonicalRoot -PathType Container)) {
        throw "A raiz permitida de saída deve existir: '$CanonicalRoot'."
    }

    $CanonicalOutput = $CanonicalPaths.OutputPath

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($CanonicalOutput)) {
        throw "O caminho de saída não pode conter curingas."
    }

    # Reject reparse points in the root ancestry and every existing path component.
    $CurrentPath = $CanonicalRoot
    while ($true) {
        if (Test-Path -LiteralPath $CurrentPath) {
            $CurrentItem = Get-Item -LiteralPath $CurrentPath -Force -ErrorAction Stop
            if (($CurrentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "A raiz permitida contém reparse point: '$CurrentPath'."
            }
        }
        $ParentPath = [System.IO.Directory]::GetParent($CurrentPath)
        if ($null -eq $ParentPath) { break }
        $CurrentPath = $ParentPath.FullName
    }

    $RelativeOutput = [System.IO.Path]::GetRelativePath($CanonicalRoot, $CanonicalOutput)
    $CurrentPath = $CanonicalRoot
    foreach ($Segment in ($RelativeOutput -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($Segment) -or $Segment -eq '.') { continue }
        $CurrentPath = Join-Path -Path $CurrentPath -ChildPath $Segment
        if (-not (Test-Path -LiteralPath $CurrentPath)) { break }
        $CurrentItem = Get-Item -LiteralPath $CurrentPath -Force -ErrorAction Stop
        if (($CurrentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "O destino de saída atravessa reparse point: '$CurrentPath'."
        }
        if ($CurrentPath -ne $CanonicalOutput -and -not $CurrentItem.PSIsContainer) {
            throw "Um componente pai do destino não é diretório: '$CurrentPath'."
        }
    }

    if (Test-Path -LiteralPath $CanonicalOutput -PathType Leaf) {
        throw "O destino de saída já existe como arquivo: '$CanonicalOutput'."
    }

    return $CanonicalOutput
}


function Assert-ReportingFileTargetSafe {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        $ExistingTarget = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($ExistingTarget.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "O arquivo de saída já existe como reparse point: '$Path'."
        }
        throw "O arquivo de saída já existe; a exportação não sobrescreve destinos: '$Path'."
    }
}


function Assert-ReportingOutputPathMatches {

    param (
        [Parameter(Mandatory = $true)]
        [string]$ExpectedPath,

        [Parameter(Mandatory = $true)]
        [string]$ResolvedPath
    )

    if (-not $ExpectedPath.Equals($ResolvedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "O caminho de saída mudou após sua validação inicial."
    }
}


function Assert-ReportingOutputDirectoryStillSafe {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedOutputDirectory
    )

    $CurrentOutputDirectory = Resolve-ReportingOutputPath `
        -Path $Path `
        -AllowedRoot $AllowedRoot

    Assert-ReportingOutputPathMatches `
        -ExpectedPath $ExpectedOutputDirectory `
        -ResolvedPath $CurrentOutputDirectory

    return $CurrentOutputDirectory
}


function Get-ReportingSourceFiles {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Source
    )

    $InputDirectory = Resolve-ReportingPath `
        -Path $Source.Directory

    if (-not (Test-Path $InputDirectory)) {

        return @()
    }

    try {

        $Files = Get-ChildItem `
            -Path $InputDirectory `
            -File `
            -Filter $Source.FilePattern `
            -ErrorAction Stop

        $AllowedFormats = @(
            $Source.Formats |
                ForEach-Object {
                    "." + $_.ToString().TrimStart(".").ToLowerInvariant()
                }
        )

        return @(
            $Files | Where-Object {

                $AllowedFormats -contains $_.Extension.ToLower()
            }
        )
    }
    catch {

        throw "Não foi possível localizar os arquivos da fonte '$($Source.FilePattern)'. Detalhes: $($_.Exception.Message)"
    }
}


function Get-ReportingData {

    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory = $false)]
        [string]$SourceName = "Unknown"
    )

    try {

        switch ($File.Extension.ToLower()) {

            ".json" {

                $Content = Get-Content `
                    -Path $File.FullName `
                    -Raw `
                    -ErrorAction Stop

                if ([string]::IsNullOrWhiteSpace($Content)) {

                    throw "O arquivo JSON está vazio."
                }

                return [PSCustomObject]@{
                    SourceName = $SourceName
                    FileName   = $File.Name
                    FullPath   = $File.FullName
                    Format     = "JSON"
                    Data       = ($Content | ConvertFrom-Json)
                    Success    = $true
                    Message    = "Arquivo JSON carregado com sucesso."
                }
            }

            ".csv" {

                $Data = Import-Csv `
                    -Path $File.FullName `
                    -ErrorAction Stop

                return [PSCustomObject]@{
                    SourceName = $SourceName
                    FileName   = $File.Name
                    FullPath   = $File.FullName
                    Format     = "CSV"
                    Data       = @($Data)
                    Success    = $true
                    Message    = "Arquivo CSV carregado com sucesso."
                }
            }

            default {

                throw "Formato '$($File.Extension)' não suportado."
            }
        }
    }
    catch {

        return [PSCustomObject]@{
            SourceName = $SourceName
            FileName   = $File.Name
            FullPath   = $File.FullName
            Format     = $File.Extension.ToUpper().TrimStart(".")
            Data       = $null
            Success    = $false
            Message    = "Não foi possível carregar o arquivo. Detalhes: $($_.Exception.Message)"
        }
    }
}


function Get-ReportingSummary {

    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Data
    )

    $TotalFiles = @($Data).Count

    $SuccessfulFiles = @(
        $Data | Where-Object {
            $_.Success -eq $true
        }
    ).Count

    $FailedFiles = @(
        $Data | Where-Object {
            $_.Success -eq $false
        }
    ).Count

    $JSONFiles = @(
        $Data | Where-Object {
            $_.Format -eq "JSON"
        }
    ).Count

    $CSVFiles = @(
        $Data | Where-Object {
            $_.Format -eq "CSV"
        }
    ).Count

    $Sources = @(
        $Data |
            Where-Object {
                $_.Success -eq $true
            } |
            Select-Object -ExpandProperty SourceName -Unique
    )

    return [PSCustomObject]@{
        GeneratedAt     = Get-Date
        TotalFiles      = $TotalFiles
        SuccessfulFiles = $SuccessfulFiles
        FailedFiles     = $FailedFiles
        JSONFiles       = $JSONFiles
        CSVFiles        = $CSVFiles
        Sources         = @($Sources)
    }
}

function New-ReportingExportPayload {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Dataset,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Payload = [ordered]@{}

    if ($Configuration.Reporting.IncludeTimestamp) {
        $Payload.GeneratedAt = $Dataset.GeneratedAt
    }

    if ($Configuration.Reporting.IncludeSummary) {
        $Summary = [ordered]@{}

        foreach ($Property in $Dataset.Summary.PSObject.Properties) {
            if ($Configuration.Reporting.IncludeTimestamp -or $Property.Name -ne "GeneratedAt") {
                $Summary[$Property.Name] = $Property.Value
            }
        }

        $Payload.Summary = [PSCustomObject]$Summary
    }

    if ($Configuration.Reporting.IncludeDetails) {
        $Payload.Files = @($Dataset.Files)
    }

    return [PSCustomObject]$Payload
}


function New-ReportingDataset {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    Test-ReportingConfiguration `
        -Configuration $Configuration |
        Out-Null

    $LoadedData = @()

    $SourceProperties = $Configuration.Sources.PSObject.Properties

    foreach ($SourceProperty in $SourceProperties) {

        $SourceName = $SourceProperty.Name
        $Source = $SourceProperty.Value

        if ($Source.Enabled -ne $true) {

            continue
        }

        $Files = Get-ReportingSourceFiles `
            -Source $Source

        foreach ($File in $Files) {

            $Result = Get-ReportingData `
                -File $File `
                -SourceName $SourceName

            $LoadedData += $Result
        }
    }

    $Summary = Get-ReportingSummary `
        -Data $LoadedData

    return [PSCustomObject]@{
        GeneratedAt     = Get-Date
        Summary         = $Summary
        Files           = $LoadedData
    }
}



function Export-ReportingDataset {

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Dataset,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$Preview,

        [string]$AllowedRoot = $PSScriptRoot
    )

    Test-ReportingConfiguration `
        -Configuration $Configuration |
        Out-Null
$SupportedFormats = @("JSON", "CSV")
$Formats = @($Configuration.Output.Formats)

$DuplicateFormats = @(
    $Formats |
        ForEach-Object { ([string]$_).ToUpperInvariant() } |
        Group-Object |
        Where-Object { $_.Count -gt 1 }
)

if ($DuplicateFormats.Count -gt 0) {
    $DuplicateNames = ($DuplicateFormats | ForEach-Object { $_.Name }) -join ", "
    throw "Formatos de exportação duplicados: $DuplicateNames."
}

foreach ($Format in $Formats) {
        if (
            [string]::IsNullOrWhiteSpace([string]$Format) -or
            $SupportedFormats -notcontains ([string]$Format).ToUpperInvariant()
        ) {
            throw "Formato de exportação '$Format' não suportado."
        }
    }

    $ConfiguredOutputDirectory = if ([System.IO.Path]::IsPathRooted($Configuration.Output.Directory)) {
        [System.IO.Path]::GetFullPath($Configuration.Output.Directory)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path -Path $AllowedRoot -ChildPath $Configuration.Output.Directory))
    }

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $ExportedFiles = @()
    $ExpectedFiles = @()

    foreach ($Format in $Formats) {
        switch (([string]$Format).ToUpperInvariant()) {
            "JSON" {
                $ExpectedFiles += Join-Path `
                    -Path $ConfiguredOutputDirectory `
                    -ChildPath "Reporting-$Timestamp.json"
            }

            "CSV" {
                if ($Configuration.Reporting.IncludeSummary) {
                    $ExpectedFiles += Join-Path `
                        -Path $ConfiguredOutputDirectory `
                        -ChildPath "Reporting-Summary-$Timestamp.csv"
                }

                if ($Configuration.Reporting.IncludeDetails -and @($Dataset.Files).Count -gt 0) {
                    $ExpectedFiles += Join-Path `
                        -Path $ConfiguredOutputDirectory `
                        -ChildPath "Reporting-Details-$Timestamp.csv"
                }
            }
        }
    }

    if ($Preview -or $WhatIfPreference) {
        return [PSCustomObject]@{
            Success         = $false
            SimulationMode  = $false
            Mode            = "Preview"
            IsSimulated     = $false
            Cancelled       = $false
            OutputDirectory = $ConfiguredOutputDirectory
            Files           = @()
            Message         = "Pré-visualização concluída. Nenhum arquivo foi gravado."
        }
    }

    if ($Configuration.SimulationMode -eq $true) {
        return [PSCustomObject]@{
            Success         = $true
            SimulationMode  = $true
            Mode            = "Simulation"
            IsSimulated     = $true
            Cancelled       = $false
            OutputDirectory = $ConfiguredOutputDirectory
            Files           = $ExpectedFiles
            Message         = "Simulação concluída. Nenhum arquivo foi gravado."
        }
    }

    if (-not $AllowRealOperation) {
        throw "Exportação real bloqueada. Informe -AllowRealOperation explicitamente."
    }

    $OutputDirectory = Resolve-ReportingOutputPath `
        -Path $Configuration.Output.Directory `
        -AllowedRoot $AllowedRoot

    foreach ($FilePath in $ExpectedFiles) {
        Assert-ReportingFileTargetSafe -Path $FilePath
    }

    if (-not $PSCmdlet.ShouldProcess($OutputDirectory, "Exportar relatórios")) {
        return [PSCustomObject]@{
            Success         = $false
            SimulationMode  = $false
            Mode            = "Preview"
            IsSimulated     = $false
            Cancelled       = $true
            OutputDirectory = $OutputDirectory
            Files           = @()
            Message         = "Exportação cancelada por ShouldProcess. Nenhum arquivo foi gravado."
        }
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $OutputDirectory `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }

    $null = Assert-ReportingOutputDirectoryStillSafe `
        -Path $Configuration.Output.Directory `
        -AllowedRoot $AllowedRoot `
        -ExpectedOutputDirectory $OutputDirectory

    foreach ($Format in $Formats) {
        switch (([string]$Format).ToUpperInvariant()) {
            "JSON" {
                $FilePath = Join-Path `
                    -Path $OutputDirectory `
                    -ChildPath "Reporting-$Timestamp.json"

                $null = Assert-ReportingOutputDirectoryStillSafe `
                    -Path $Configuration.Output.Directory `
                    -AllowedRoot $AllowedRoot `
                    -ExpectedOutputDirectory $OutputDirectory
                Assert-ReportingFileTargetSafe -Path $FilePath

                (New-ReportingExportPayload `
                    -Dataset $Dataset `
                    -Configuration $Configuration) |
                    ConvertTo-Json -Depth 10 |
                    Set-Content `
                        -LiteralPath $FilePath `
                        -Encoding UTF8 `
                        -ErrorAction Stop

                $ExportedFiles += $FilePath
            }

            "CSV" {
                if ($Configuration.Reporting.IncludeSummary) {
                    $FilePath = Join-Path `
                        -Path $OutputDirectory `
                        -ChildPath "Reporting-Summary-$Timestamp.csv"

                    $null = Assert-ReportingOutputDirectoryStillSafe `
                        -Path $Configuration.Output.Directory `
                        -AllowedRoot $AllowedRoot `
                        -ExpectedOutputDirectory $OutputDirectory
                    Assert-ReportingFileTargetSafe -Path $FilePath

                    $SummaryPayload = (New-ReportingExportPayload `
                        -Dataset $Dataset `
                        -Configuration $Configuration).Summary

                    $SummaryPayload |
                        Export-Csv `
                            -LiteralPath $FilePath `
                            -NoTypeInformation `
                            -Encoding UTF8 `
                            -ErrorAction Stop

                    $ExportedFiles += $FilePath
                }

                if ($Configuration.Reporting.IncludeDetails -and @($Dataset.Files).Count -gt 0) {
                    $FilePath = Join-Path `
                        -Path $OutputDirectory `
                        -ChildPath "Reporting-Details-$Timestamp.csv"

                    $null = Assert-ReportingOutputDirectoryStillSafe `
                        -Path $Configuration.Output.Directory `
                        -AllowedRoot $AllowedRoot `
                        -ExpectedOutputDirectory $OutputDirectory
                    Assert-ReportingFileTargetSafe -Path $FilePath

                    $DetailRows = foreach ($File in $Dataset.Files) {
                        $DetailRow = [ordered]@{
                            SourceName = $File.SourceName
                            FileName = $File.FileName
                            Format = $File.Format
                            Success = $File.Success
                            Message = $File.Message
                            Data = if ($null -eq $File.Data) {
                                $null
                            }
                            else {
                                $File.Data | ConvertTo-Json -Depth 10 -Compress
                            }
                        }

                        if ($Configuration.Reporting.IncludeTimestamp) {
                            $DetailRow.GeneratedAt = $Dataset.GeneratedAt
                        }

                        [PSCustomObject]$DetailRow
                    }

                    $DetailRows |
                        Export-Csv `
                            -LiteralPath $FilePath `
                            -NoTypeInformation `
                            -Encoding UTF8 `
                            -ErrorAction Stop

                    $ExportedFiles += $FilePath
                }
            }
        }
    }

    return [PSCustomObject]@{
        Success         = $true
        SimulationMode  = $false
        Mode            = "Real"
        IsSimulated     = $false
        Cancelled       = $false
        OutputDirectory = $OutputDirectory
        Files           = $ExportedFiles
        Message         = "Relatórios exportados com sucesso."
    }
}
function Invoke-Reporting {

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$Preview,

        [string]$AllowedRoot = $PSScriptRoot
    )

    Test-ReportingConfiguration `
        -Configuration $Configuration |
        Out-Null

    if ($Configuration.SimulationMode -isnot [bool]) {
        throw "SimulationMode deve ser definido explicitamente como Boolean."
    }

    if ($Preview -or $WhatIfPreference) {
        return [PSCustomObject]@{
            Success         = $false
            SimulationMode  = $false
            Mode            = "Preview"
            IsSimulated     = $false
            Cancelled       = $false
            GeneratedAt     = $null
            Summary         = $null
            OutputDirectory = $Configuration.Output.Directory
            Files           = @()
            Message         = "Pré-visualização concluída. Nenhum arquivo foi lido ou gravado."
        }
    }

    if ($Configuration.SimulationMode -eq $false) {
        if (-not $AllowRealOperation) {
            throw "Exportação real bloqueada. Informe -AllowRealOperation explicitamente."
        }

        $OutputDirectory = Resolve-ReportingOutputPath `
            -Path $Configuration.Output.Directory `
            -AllowedRoot $AllowedRoot

        if (-not $PSCmdlet.ShouldProcess($OutputDirectory, "Executar Reporting e exportar relatórios")) {
            return [PSCustomObject]@{
                Success         = $false
                SimulationMode  = $false
                Mode            = "Preview"
                IsSimulated     = $false
                Cancelled       = $true
                GeneratedAt     = $null
                Summary         = $null
                OutputDirectory = $OutputDirectory
                Files           = @()
                Message         = "Execução cancelada por ShouldProcess. Nenhum arquivo foi lido ou gravado."
            }
        }
    }

    $Dataset = New-ReportingDataset `
        -Configuration $Configuration

    $Export = Export-ReportingDataset `
        -Dataset $Dataset `
        -Configuration $Configuration `
        -AllowRealOperation:$AllowRealOperation `
        -Preview:$Preview `
        -AllowedRoot $AllowedRoot `
        -Confirm:$false

    return [PSCustomObject]@{
        Success         = ($Export.Success -and $Dataset.Summary.FailedFiles -eq 0)
        Mode            = $Export.Mode
        IsSimulated     = $Export.IsSimulated
        Cancelled       = $Export.Cancelled
        GeneratedAt     = $Dataset.GeneratedAt
        Summary         = $Dataset.Summary
        OutputDirectory = $Export.OutputDirectory
        Files           = $Export.Files
        Message         = if ($Dataset.Summary.FailedFiles -gt 0) {
            "$($Export.Message) $($Dataset.Summary.FailedFiles) arquivo(s) de origem não puderam ser processados."
        }
        else {
            $Export.Message
        }
    }
}


Export-ModuleMember -Function `
    Test-ReportingConfiguration,
    Resolve-ReportingPath,
    Get-ReportingSourceFiles,
    Get-ReportingData,
    Get-ReportingSummary,
    New-ReportingDataset,
    Export-ReportingDataset,
    Invoke-Reporting
