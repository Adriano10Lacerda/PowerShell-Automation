
# ===========================================
# Enterprise Configuration - Automated Tests
# Author: Adriano Felix Lacerda
# ===========================================

$ErrorActionPreference = "Stop"

$CaminhoModulo = Join-Path $PSScriptRoot "Configuration.psm1"

$TotalTestes = 0
$TestesPassaram = 0
$TestesFalharam = 0

$script:ArquivosCriadosPeloTeste = [System.Collections.Generic.List[string]]::new()
$script:RaizTesteCriada = $false

function Assert-TestPathWithinRoot {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path.StartsWith('\\') -or $Path.StartsWith('//') -or
        $Path.StartsWith('\\?\') -or $Path.StartsWith('\\.\') -or
        $Path.StartsWith('\??\') -or $Path -match '[*?]' -or
        -not [System.IO.Path]::IsPathFullyQualified($Path) -or
        -not [System.IO.Path]::IsPathFullyQualified($Root) -or
        $Path -match '(^|[\\/])\.\.([\\/]|$)' -or
        $Path -match '(^|[\\/])\.([\\/]|$)') {
        throw "Caminho de teste ambíguo ou não permitido: '$Path'."
    }

    $ColonIndexes = @()
    for ($Index = 0; $Index -lt $Path.Length; $Index++) {
        if ($Path[$Index] -eq ':') { $ColonIndexes += $Index }
    }
    $IsDrivePrefix = $ColonIndexes.Count -eq 1 -and
        $ColonIndexes[0] -eq 1 -and
        $Path.Length -gt 2 -and
        ($Path[2] -eq '\' -or $Path[2] -eq '/')
    if ($ColonIndexes.Count -gt 0 -and -not $IsDrivePrefix) {
        throw "ADS ou prefixo de unidade relativo não permitido: '$Path'."
    }

    $CanonicalRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
    $CanonicalPath = [System.IO.Path]::GetFullPath($Path)
    $RelativePath = [System.IO.Path]::GetRelativePath($CanonicalRoot, $CanonicalPath)
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -eq '..' -or
        $RelativePath.StartsWith('..' + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $RelativePath.StartsWith('..' + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Caminho fora da raiz exclusiva do teste: '$CanonicalPath'."
    }

    $VolumeRoot = [System.IO.Path]::GetPathRoot($CanonicalRoot)
    if ([string]::IsNullOrWhiteSpace($VolumeRoot) -or $CanonicalRoot.StartsWith('\\') -or
        $CanonicalPath.Substring($VolumeRoot.Length).Contains(':')) {
        throw "A raiz do teste deve ser um caminho local absoluto."
    }

    $CurrentPath = $VolumeRoot
    $Segments = @($CanonicalPath.Substring($VolumeRoot.Length) -split '[\\/]')
    foreach ($Segment in $Segments) {
        if ([string]::IsNullOrWhiteSpace($Segment)) { continue }
        if ($Segment.EndsWith('.') -or $Segment.EndsWith(' ') -or
            $Segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            throw "Segmento de caminho inválido: '$Segment'."
        }

        $CurrentPath = Join-Path -Path $CurrentPath -ChildPath $Segment
        try {
            $Item = Get-Item -LiteralPath $CurrentPath -Force -ErrorAction Stop
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            break
        }
        catch [System.IO.FileNotFoundException] {
            break
        }
        catch [System.IO.DirectoryNotFoundException] {
            break
        }

        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Caminho de teste atravessa reparse point: '$CurrentPath'."
        }
    }

    return $CanonicalPath
}

function Initialize-TestWorkspace {
    $TempPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not [System.IO.Directory]::Exists($TempPath)) {
        throw "Diretório temporário indisponível: '$TempPath'."
    }

    $script:DiretorioTemporario = Join-Path $TempPath (
        "ConfigurationTests_" + [guid]::NewGuid().ToString("N")
    )
    $script:DiretorioTemporario = Assert-TestPathWithinRoot `
        -Path $script:DiretorioTemporario `
        -Root $TempPath

    if ([System.IO.Directory]::Exists($script:DiretorioTemporario) -or
        [System.IO.File]::Exists($script:DiretorioTemporario)) {
        throw "A raiz exclusiva já existe; execução bloqueada: '$script:DiretorioTemporario'."
    }

    # Sem -Force: uma colisão nunca reutiliza uma pasta preexistente.
    New-Item -Path $script:DiretorioTemporario -ItemType Directory -ErrorAction Stop |
        Out-Null

    $script:RaizTesteCriada = $true
    $script:DiretorioTemporario = Assert-TestPathWithinRoot `
        -Path $script:DiretorioTemporario `
        -Root $TempPath
}

function New-TestFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $CanonicalPath = Assert-TestPathWithinRoot `
        -Path $Path `
        -Root $script:DiretorioTemporario

    if (-not $script:RaizTesteCriada -or
        -not [System.IO.Directory]::Exists($script:DiretorioTemporario)) {
        throw "A raiz criada pelo teste não está disponível."
    }
    if ([System.IO.File]::Exists($CanonicalPath) -or
        [System.IO.Directory]::Exists($CanonicalPath)) {
        throw "O arquivo de fixture já existe; sobrescrita bloqueada: '$CanonicalPath'."
    }

    $Bytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes($Content)
    $Stream = [System.IO.File]::Open(
        $CanonicalPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    $script:ArquivosCriadosPeloTeste.Add($CanonicalPath)
    try {
        $Stream.Write($Bytes, 0, $Bytes.Length)
    }
    finally {
        $Stream.Dispose()
    }
    return $CanonicalPath
}

function Clear-TestWorkspace {
    if (-not $script:RaizTesteCriada) { return }

    foreach ($Path in @($script:ArquivosCriadosPeloTeste)) {
        $CanonicalPath = Assert-TestPathWithinRoot `
            -Path $Path `
            -Root $script:DiretorioTemporario
        if (-not [System.IO.File]::Exists($CanonicalPath)) { continue }

        $Item = Get-Item -LiteralPath $CanonicalPath -Force -ErrorAction Stop
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $Item.PSIsContainer) {
            throw "Limpeza recusada para recurso que não é arquivo regular: '$CanonicalPath'."
        }
        [System.IO.File]::Delete($CanonicalPath)
    }

    $Root = Assert-TestPathWithinRoot `
        -Path $script:DiretorioTemporario `
        -Root ([System.IO.Path]::GetTempPath())
    if ([System.IO.Directory]::Exists($Root)) {
        $RootItem = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
        if (($RootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not $RootItem.PSIsContainer) {
            throw "Limpeza recusada para raiz alterada ou ambígua: '$Root'."
        }
        [System.IO.Directory]::Delete($Root, $false)
    }
}

$CaminhoModulo = Assert-TestPathWithinRoot `
    -Path $CaminhoModulo `
    -Root $PSScriptRoot
if (-not [System.IO.File]::Exists($CaminhoModulo)) {
    throw "Módulo local de configuração não encontrado: '$CaminhoModulo'."
}
Import-Module -Name $CaminhoModulo -Force -ErrorAction Stop

function Invoke-Test {
    param (
        [string]$Nome,
        [scriptblock]$Acao
    )

    $script:TotalTestes++

    try {
        & $Acao

        Write-Host "[PASS] $Nome" -ForegroundColor Green
        $script:TestesPassaram++
    }
    catch {
        Write-Host "[FAIL] $Nome" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor DarkRed
        $script:TestesFalharam++
    }
}

function New-TestConfiguration {
    param (
        [hashtable]$Overrides = @{}
    )

    $Config = @{
        Prefixo = "EMP"
        QuantidadeCaracteres = 12
        FormatoData = "ddMM"
        CaracteresEspeciais = "!@#$%&*"
    }

    foreach ($Chave in $Overrides.Keys) {
        $Config[$Chave] = $Overrides[$Chave]
    }

    $CaminhoArquivo = Join-Path $DiretorioTemporario (
        [guid]::NewGuid().ToString("N") + ".json"
    )

    $Json = $Config | ConvertTo-Json -Depth 10
    $CaminhoArquivo = New-TestFile -Path $CaminhoArquivo -Content $Json

    return $CaminhoArquivo
}

function Assert-ConfigurationThrows {
    param (
        [string]$Caminho
    )

    $ErroEsperado = $false

    try {
        $Caminho = Assert-TestPathWithinRoot `
            -Path $Caminho `
            -Root $DiretorioTemporario
        Get-Configuration -ConfigurationPath $Caminho
    }
    catch {
        $ErroEsperado = $true
    }

    if (-not $ErroEsperado) {
        throw "Era esperado que a configuração fosse rejeitada."
    }
}

try {
    Initialize-TestWorkspace

    # 1. Configuração válida
    Invoke-Test "Configuração válida é aceita" {
        $Caminho = New-TestConfiguration

        $Config = Get-Configuration -ConfigurationPath $Caminho

        if ($Config.Prefixo -ne "EMP") {
            throw "Prefixo inesperado."
        }

        if ($Config.QuantidadeCaracteres -ne 12) {
            throw "Quantidade inesperada."
        }
    }

    # 2. Arquivo inexistente
    Invoke-Test "Arquivo inexistente é rejeitado" {
        $Caminho = Join-Path $DiretorioTemporario "inexistente.json"

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 3. JSON inválido
    Invoke-Test "JSON inválido é rejeitado" {
        $Caminho = Join-Path $DiretorioTemporario "invalido.json"

        $Caminho = New-TestFile -Path $Caminho -Content "{ JSON inválido"

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 4. Prefixo vazio
    Invoke-Test "Prefixo vazio é rejeitado" {
        $Caminho = New-TestConfiguration @{
            Prefixo = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 5. Quantidade ausente
    Invoke-Test "Quantidade ausente é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 6. Quantidade não inteira
    Invoke-Test "Quantidade não inteira é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = "abc"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 7. Quantidade abaixo do mínimo
    Invoke-Test "Quantidade abaixo de 4 é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 3
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 8. Formato de data vazio
    Invoke-Test "Formato de data vazio é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 9. Formato de data inválido
    Invoke-Test "Formato de data sem token válido é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "abc"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

        # 10. Formatos de data permitidos pela V1

    Invoke-Test "Formato ddMM é aceito" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "ddMM"
        }

        $Config = Get-Configuration -ConfigurationPath $Caminho

        if ($Config.FormatoData -ne "ddMM") {
            throw "O formato ddMM não foi preservado."
        }
    }

    Invoke-Test "Formato dd/MM/yyyy é aceito" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "dd/MM/yyyy"
        }

        $Config = Get-Configuration -ConfigurationPath $Caminho

        if ($Config.FormatoData -ne "dd/MM/yyyy") {
            throw "O formato dd/MM/yyyy não foi preservado."
        }
    }

    Invoke-Test "Formato yyyy-MM-dd é aceito" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "yyyy-MM-dd"
        }

        $Config = Get-Configuration -ConfigurationPath $Caminho

        if ($Config.FormatoData -ne "yyyy-MM-dd") {
            throw "O formato yyyy-MM-dd não foi preservado."
        }
    }

    Invoke-Test "Formato xyz é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "xyz"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 10. Caracteres especiais vazios
    Invoke-Test "Caracteres especiais vazios são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 11. Quantidade máxima permitida
    Invoke-Test "Quantidade máxima de 128 é aceita" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 128
        }

        $Config = Get-Configuration -ConfigurationPath $Caminho

        if ($Config.QuantidadeCaracteres -ne 128) {
            throw "A quantidade máxima não foi preservada."
        }
    }

    # 12. Quantidade acima do máximo
    Invoke-Test "Quantidade acima de 128 é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 129
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 13. Caracteres especiais com letras
    Invoke-Test "Caracteres especiais com letras são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@#ABC"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 14. Caracteres especiais com números
    Invoke-Test "Caracteres especiais com números são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@#123"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 15. Caracteres especiais com espaços
    Invoke-Test "Caracteres especiais com espaços são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@# "
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 16. Prefixo ausente
    Invoke-Test "Prefixo ausente é rejeitado" {
        $Caminho = New-TestConfiguration @{
            Prefixo = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 17. Caracteres especiais ausentes
    Invoke-Test "Caracteres especiais ausentes são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }
}
finally {
    Clear-TestWorkspace
}

Write-Host ""
Write-Host "============================================"
Write-Host " RESULTADO DOS TESTES - MODULO 02"
Write-Host "============================================"
Write-Host ""
Write-Host "Total de testes : $TotalTestes"
Write-Host "Passaram        : $TestesPassaram"
Write-Host "Falharam        : $TestesFalharam"
Write-Host ""

if ($TestesFalharam -eq 0) {
    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "STATUS: EXISTEM FALHAS" -ForegroundColor Red
    exit 1
}
