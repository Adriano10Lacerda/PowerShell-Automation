function Test-ReportingConfiguration {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    if ($null -eq $Configuration.SimulationMode) {
        $Errors += "A configuração 'SimulationMode' não foi definida."
    }

    if ($null -eq $Configuration.Reporting) {
        $Errors += "A seção 'Reporting' não foi definida."
    }

    if ($null -eq $Configuration.Output) {
        $Errors += "A seção 'Output' não foi definida."
    }

    if ($null -eq $Configuration.Sources) {
        $Errors += "A seção 'Sources' não foi definida."
    }

    if ($null -ne $Configuration.Output) {

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

            if ($null -eq $Source.Enabled) {

                $Errors += "A propriedade 'Enabled' não foi definida para a fonte '$SourceName'."
            }

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
                    $_.ToString().ToLower()
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

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Dataset,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    Test-ReportingConfiguration `
        -Configuration $Configuration |
        Out-Null

    $OutputDirectory = Resolve-ReportingPath `
        -Path $Configuration.Output.Directory

    if (-not (Test-Path $OutputDirectory)) {

        New-Item `
            -ItemType Directory `
            -Path $OutputDirectory `
            -Force |
            Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $ExportedFiles = @()

    foreach ($Format in $Configuration.Output.Formats) {

        switch ($Format.ToUpper()) {

            "JSON" {

                $FilePath = Join-Path `
                    -Path $OutputDirectory `
                    -ChildPath "Reporting-$Timestamp.json"

                $Dataset |
                    ConvertTo-Json -Depth 10 |
                    Set-Content `
                        -Path $FilePath `
                        -Encoding UTF8

                $ExportedFiles += $FilePath
            }

            "CSV" {

                $FilePath = Join-Path `
                    -Path $OutputDirectory `
                    -ChildPath "Reporting-Summary-$Timestamp.csv"

                $Dataset.Summary |
                    Export-Csv `
                        -Path $FilePath `
                        -NoTypeInformation `
                        -Encoding UTF8

                $ExportedFiles += $FilePath
            }

            default {

                throw "Formato de exportação '$Format' não suportado."
            }
        }
    }

    return [PSCustomObject]@{
        Success         = $true
        OutputDirectory = $OutputDirectory
        Files           = $ExportedFiles
        Message         = "Relatórios exportados com sucesso."
    }
}


function Invoke-Reporting {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    Test-ReportingConfiguration `
        -Configuration $Configuration |
        Out-Null

    $Dataset = New-ReportingDataset `
        -Configuration $Configuration

    $Export = Export-ReportingDataset `
        -Dataset $Dataset `
        -Configuration $Configuration

    return [PSCustomObject]@{
        Success         = $Export.Success
        GeneratedAt     = $Dataset.GeneratedAt
        Summary         = $Dataset.Summary
        OutputDirectory = $Export.OutputDirectory
        Files           = $Export.Files
        Message         = $Export.Message
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