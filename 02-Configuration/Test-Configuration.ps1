
# ===========================================
# Enterprise Configuration - Automated Tests
# Author: Adriano Felix Lacerda
# ===========================================

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot
)

$ErrorActionPreference = "Stop"

$CaminhoModulo = Join-Path $PSScriptRoot "Configuration.psm1"

$TotalTestes = 0
$TestesPassaram = 0
$TestesFalharam = 0
$TestesBloqueados = 0
$script:SetupFailure = $null
$script:SetupComplete = $false

$script:ArquivosCriadosPeloTeste = [System.Collections.Generic.List[object]]::new()
$script:WorkspaceReady = $false
$script:WorkspaceIdentity = $null
$script:CleanupIncomplete = $false

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

function Assert-TestWorkspace {
    if (-not $script:WorkspaceReady -or [string]::IsNullOrWhiteSpace($script:WorkspaceIdentity)) {
        throw 'BLOCKED: workspace explícito ainda não foi validado.'
    }
    Assert-ConfinedWorkspace -Root $script:DiretorioTemporario -Identity $script:WorkspaceIdentity
}

function Initialize-TestWorkspace {
    $script:DiretorioTemporario = Assert-TestPathWithinRoot `
        -Path $WorkspaceRoot `
        -Root $WorkspaceRoot

    $commonModule = Join-Path (Split-Path -Parent $PSScriptRoot) 'Validation/ConfinedWorkspace.psm1'
    if (-not [System.IO.File]::Exists($commonModule)) {
        throw 'BLOCKED: validador comum ausente.'
    }
    Import-Module -Name $commonModule -ErrorAction Stop

    if (-not [System.IO.Directory]::Exists($script:DiretorioTemporario)) {
        throw 'BLOCKED: WorkspaceRoot deve existir previamente; o harness não cria diretórios.'
    }
    $rootItem = Get-Item -LiteralPath $script:DiretorioTemporario -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer -or
        ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BLOCKED: WorkspaceRoot deve ser um diretório local existente sem reparse point.'
    }
    $script:WorkspaceIdentity = Get-ConfinedObjectIdentity -Path $script:DiretorioTemporario
    Assert-ConfinedWorkspace -Root $script:DiretorioTemporario -Identity $script:WorkspaceIdentity

    if (@(Get-ChildItem -LiteralPath $script:DiretorioTemporario -Force -ErrorAction Stop).Count -ne 0) {
        throw 'BLOCKED: WorkspaceRoot exclusivo deve estar vazio.'
    }
    $script:WorkspaceReady = $true

    $CaminhoModulo = Assert-TestPathWithinRoot -Path $CaminhoModulo -Root $PSScriptRoot
    if (-not [System.IO.File]::Exists($CaminhoModulo)) {
        throw "Módulo local de configuração não encontrado: '$CaminhoModulo'."
    }
    Import-Module -Name $CaminhoModulo -Force -ErrorAction Stop
}

function Resolve-TestWorkspacePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    Assert-TestWorkspace
    Resolve-ConfinedWorkspacePath `
        -Root $script:DiretorioTemporario `
        -Identity $script:WorkspaceIdentity `
        -Path $Path
}

function Invoke-ConfinedConfiguration {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = Resolve-TestWorkspacePath -Path $Path
    Get-Configuration `
        -ConfigurationPath $resolved `
        -ApprovedRoot $script:DiretorioTemporario `
        -ApprovedRootIdentity $script:WorkspaceIdentity
}

function New-TestFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    Assert-TestWorkspace
    if (-not $script:WorkspaceReady -or -not [System.IO.Directory]::Exists($script:DiretorioTemporario)) { throw 'BLOCKED: workspace provisionado indisponível.' }
    $CanonicalPath = Resolve-TestWorkspacePath -Path $Path
    if ([System.IO.File]::Exists($CanonicalPath) -or
        [System.IO.Directory]::Exists($CanonicalPath)) {
        throw "O arquivo de fixture já existe; sobrescrita bloqueada: '$CanonicalPath'."
    }

    $Bytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes($Content)
    Assert-TestWorkspace
    $Stream = $null
    $record = $null
    try {
        $Stream = [System.IO.File]::Open(
            $CanonicalPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $record = [pscustomobject]@{
            Path = $CanonicalPath
            Identity = Get-ConfinedObjectIdentity -Handle $Stream.SafeFileHandle
            Length = $Bytes.Length
            Sha256 = $null
        }
        $script:ArquivosCriadosPeloTeste.Add($record)
        $Stream.Write($Bytes, 0, $Bytes.Length)
    }
    catch {
        if ($null -ne $Stream -or $null -ne $record) {
            $script:CleanupIncomplete = $true
        }
        throw
    }
    finally {
        if ($null -ne $Stream) { $Stream.Dispose() }
    }
    Assert-TestWorkspace
    $record.Sha256 = (Get-FileHash -LiteralPath $CanonicalPath -Algorithm SHA256 -ErrorAction Stop).Hash
    return $CanonicalPath
}

function Clear-TestWorkspace {
    if (-not $script:WorkspaceReady -or [string]::IsNullOrWhiteSpace($script:WorkspaceIdentity)) { return }

    foreach ($record in @($script:ArquivosCriadosPeloTeste)) {
        if ([string]::IsNullOrWhiteSpace([string]$record.Sha256)) {
            $script:CleanupIncomplete = $true
            continue
        }
        try {
            Assert-TestWorkspace
            $CanonicalPath = Resolve-TestWorkspacePath -Path ([string]$record.Path)
            if (-not [System.IO.File]::Exists($CanonicalPath)) {
                continue
            }
            $Item = Get-Item -LiteralPath $CanonicalPath -Force -ErrorAction Stop
            if ($Item.PSIsContainer -or
                ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                (Get-ConfinedObjectIdentity -Path $CanonicalPath) -cne $record.Identity -or
                $Item.Length -ne $record.Length -or
                (Get-FileHash -LiteralPath $CanonicalPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $record.Sha256) {
                throw 'A fixture mudou de identidade ou conteúdo; será preservada.'
            }
            Assert-TestWorkspace
            [System.IO.File]::Delete($CanonicalPath)
        }
        catch {
            $script:CleanupIncomplete = $true
        }
    }
}

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

function Assert-TestPathRejected {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedText
    )

    try {
        Assert-TestPathWithinRoot -Path $Path -Root $script:DiretorioTemporario | Out-Null
    }
    catch {
        if ($_.Exception.Message.Contains($ExpectedText, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        throw "Rejeição de caminho inesperada; esperado '$ExpectedText', recebido '$($_.Exception.Message)'."
    }
    throw "O caminho inseguro foi aceito: '$Path'."
}

function Assert-ActionThrows {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$ExpectedText
    )

    try {
        & $Action
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($ExpectedText) -or
            $_.Exception.Message.Contains($ExpectedText, [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        throw "Falha inesperada: $($_.Exception.Message)"
    }
    throw "A ação deveria falhar com '$ExpectedText'."
}

function Get-TestExitCode {
    param(
        [int]$FailureCount,
        [bool]$SetupFailed,
        [bool]$CleanupFailed,
        [int]$BlockedCount
    )

    if ($FailureCount -gt 0 -or $SetupFailed -or $CleanupFailed -or $BlockedCount -gt 0) {
        return 1
    }
    return 0
}

function Invoke-ReparsePointGateTest {
    $script:TotalTestes++
    $linkPath = Join-Path $script:DiretorioTemporario ('reparse-' + [guid]::NewGuid().ToString('N'))
    $linkCreated = $false
    $gatePassed = $false
    $blockedReason = $null
    $failureReason = $null
    try {
        Assert-TestWorkspace
        [System.IO.Directory]::CreateSymbolicLink($linkPath, $script:DiretorioTemporario) | Out-Null
        $linkCreated = $true
        $linkItem = Get-Item -LiteralPath $linkPath -Force -ErrorAction Stop
        if (($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw 'A fixture simbólica não foi identificada como reparse point.'
        }
        Assert-ActionThrows -ExpectedText 'reparse point' -Action {
            Assert-ConfigurationPathRejected `
                -Path $linkPath `
                -ExpectedText 'Reparse points and multiply linked files are prohibited'
        }
        $gatePassed = $true
    }
    catch {
        if (-not $linkCreated -and
            ($_.Exception -is [System.UnauthorizedAccessException] -or
             $_.Exception -is [System.PlatformNotSupportedException] -or
             $_.Exception -is [System.NotSupportedException] -or
             $_.Exception -is [System.IO.IOException])) {
            $blockedReason = $_.Exception.Message
        }
        else {
            $failureReason = $_.Exception.Message
        }
    }
    finally {
        if ($linkCreated) {
            try {
                Assert-TestWorkspace
                $linkItem = Get-Item -LiteralPath $linkPath -Force -ErrorAction Stop
                if (($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                    throw 'A fixture deixou de ser um reparse point; remoção recusada.'
                }
                [System.IO.Directory]::Delete($linkPath, $false)
            }
            catch {
                $script:CleanupIncomplete = $true
                $failureReason = "Falha ao remover somente o link criado pelo teste: $($_.Exception.Message)"
            }
        }
    }

    if ($null -ne $failureReason) {
        $TestesFalharam++
        Write-Host "[FAIL] Reparse point: $failureReason" -ForegroundColor Red
    }
    elseif ($null -ne $blockedReason) {
        $TestesBloqueados++
        Write-Host "[BLOCKED] Reparse point: o ambiente não permite criar a fixture no workspace: $blockedReason" -ForegroundColor Yellow
    }
    elseif ($gatePassed) {
        $TestesPassaram++
        Write-Host '[PASS] Reparse point é rejeitado' -ForegroundColor Green
    }
    else {
        $TestesFalharam++
        Write-Host '[FAIL] Reparse point: estado do teste não conclusivo.' -ForegroundColor Red
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
        [Parameter(Mandatory = $true)][string]$Caminho,
        [Parameter(Mandatory = $true)][string]$ExpectedErrorId,
        [string]$ExpectedField
    )

    # Fixture/path preparation is deliberately outside the catch: harness or
    # filesystem failures must never count as an expected Configuration error.
    $CaminhoResolvido = Resolve-TestWorkspacePath -Path $Caminho
    $ErroObtido = $null

    try {
        Invoke-ConfinedConfiguration -Path $CaminhoResolvido | Out-Null
    }
    catch {
        $ErroObtido = $_
    }

    if ($null -eq $ErroObtido) {
        throw "Era esperado ErrorId '$ExpectedErrorId', mas a configuração foi aceita."
    }

    $ActualErrorId = ([string]$ErroObtido.FullyQualifiedErrorId -split ',')[0]
    if (-not [StringComparer]::Ordinal.Equals($ActualErrorId, $ExpectedErrorId)) {
        throw "Erro inesperado. Esperado '$ExpectedErrorId'; recebido '$ActualErrorId': $($ErroObtido.Exception.Message)"
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedField) -and
        -not $ErroObtido.Exception.Message.Contains($ExpectedField, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Erro de schema não identifica o campo esperado '$ExpectedField': $($ErroObtido.Exception.Message)"
    }
}

function Assert-ConfigurationPathRejected {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedText
    )

    $ErrorRecord = $null
    try {
        Get-Configuration `
            -ConfigurationPath $Path `
            -ApprovedRoot $script:DiretorioTemporario `
            -ApprovedRootIdentity $script:WorkspaceIdentity | Out-Null
    }
    catch {
        $ErrorRecord = $_
    }

    if ($null -eq $ErrorRecord) {
        throw "Get-Configuration aceitou caminho que deveria ser bloqueado: '$Path'."
    }

    $ActualErrorId = ([string]$ErrorRecord.FullyQualifiedErrorId -split ',')[0]
    if (-not [StringComparer]::Ordinal.Equals($ActualErrorId, 'Configuration.UnsafePath')) {
        throw "Get-Configuration retornou erro inesperado para caminho inseguro: '$ActualErrorId'."
    }
    if (-not $ErrorRecord.Exception.Message.Contains($ExpectedText, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Get-Configuration bloqueou por motivo inesperado; esperado '$ExpectedText', recebido '$($ErrorRecord.Exception.Message)'."
    }
}

try {
    Initialize-TestWorkspace
    $script:SetupComplete = $true

    # 1. Configuração válida
    Invoke-Test "Configuração válida é aceita" {
        $Caminho = New-TestConfiguration

        $Config = Invoke-ConfinedConfiguration -Path $Caminho

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

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.NotFound'
    }

    # 3. JSON inválido
    Invoke-Test "JSON inválido é rejeitado" {
        $Caminho = Join-Path $DiretorioTemporario "invalido.json"

        $Caminho = New-TestFile -Path $Caminho -Content "{ JSON inválido"

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidJson'
    }

    # 4. Prefixo vazio
    Invoke-Test "Prefixo vazio é rejeitado" {
        $Caminho = New-TestConfiguration @{
            Prefixo = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'Prefixo'
    }

    # 5. Quantidade ausente
    Invoke-Test "Quantidade ausente é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'QuantidadeCaracteres'
    }

    # 6. Quantidade não inteira
    Invoke-Test "Quantidade não inteira é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = "abc"
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'QuantidadeCaracteres'
    }

    # 7. Quantidade abaixo do mínimo
    Invoke-Test "Quantidade abaixo de 4 é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 3
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'QuantidadeCaracteres'
    }

    # 8. Formato de data vazio
    Invoke-Test "Formato de data vazio é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'FormatoData'
    }

    # 9. Formato de data inválido
    Invoke-Test "Formato de data sem token válido é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "abc"
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'FormatoData'
    }

        # 10. Formatos de data permitidos pela V1

    Invoke-Test "Formato ddMM é aceito" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "ddMM"
        }

        $Config = Invoke-ConfinedConfiguration -Path $Caminho

        if ($Config.FormatoData -ne "ddMM") {
            throw "O formato ddMM não foi preservado."
        }
    }

    Invoke-Test "Formato dd/MM/yyyy é aceito" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "dd/MM/yyyy"
        }

        $Config = Invoke-ConfinedConfiguration -Path $Caminho

        if ($Config.FormatoData -ne "dd/MM/yyyy") {
            throw "O formato dd/MM/yyyy não foi preservado."
        }
    }

    Invoke-Test "Formato yyyy-MM-dd é aceito" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "yyyy-MM-dd"
        }

        $Config = Invoke-ConfinedConfiguration -Path $Caminho

        if ($Config.FormatoData -ne "yyyy-MM-dd") {
            throw "O formato yyyy-MM-dd não foi preservado."
        }
    }

    Invoke-Test "Formato xyz é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "xyz"
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'FormatoData'
    }

    # 10. Caracteres especiais vazios
    Invoke-Test "Caracteres especiais vazios são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'CaracteresEspeciais'
    }

    # 11. Quantidade máxima permitida
    Invoke-Test "Quantidade máxima de 128 é aceita" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 128
        }

        $Config = Invoke-ConfinedConfiguration -Path $Caminho

        if ($Config.QuantidadeCaracteres -ne 128) {
            throw "A quantidade máxima não foi preservada."
        }
    }

    # 12. Quantidade acima do máximo
    Invoke-Test "Quantidade acima de 128 é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 129
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'QuantidadeCaracteres'
    }

    # 13. Caracteres especiais com letras
    Invoke-Test "Caracteres especiais com letras são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@#ABC"
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'CaracteresEspeciais'
    }

    # 14. Caracteres especiais com números
    Invoke-Test "Caracteres especiais com números são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@#123"
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'CaracteresEspeciais'
    }

    # 15. Caracteres especiais com espaços
    Invoke-Test "Caracteres especiais com espaços são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@# "
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'CaracteresEspeciais'
    }

    # 16. Prefixo ausente
    Invoke-Test "Prefixo ausente é rejeitado" {
        $Caminho = New-TestConfiguration @{
            Prefixo = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'Prefixo'
    }

    # 17. Caracteres especiais ausentes
    Invoke-Test "Caracteres especiais ausentes são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho -ExpectedErrorId 'Configuration.InvalidSchema' -ExpectedField 'CaracteresEspeciais'
    }

    Invoke-Test "Traversal é rejeitado antes de acessar o filesystem" {
        Assert-TestPathRejected -Path (Join-Path $script:DiretorioTemporario '..\fora.json') -ExpectedText 'ambíguo ou não permitido'
    }

    Invoke-Test "Configuration Confined bloqueia traversal" {
        Assert-ConfigurationPathRejected `
            -Path (Join-Path $script:DiretorioTemporario '..\fora.json') `
            -ExpectedText 'not canonical'
    }

    Invoke-Test "UNC é rejeitado" {
        Assert-TestPathRejected -Path '\\server\share\config.json' -ExpectedText 'ambíguo ou não permitido'
    }

    Invoke-Test "Configuration Confined bloqueia UNC" {
        Assert-ConfigurationPathRejected -Path '\\server\share\config.json' -ExpectedText 'absolute local drive path'
    }

    Invoke-Test "Caminho de dispositivo é rejeitado" {
        Assert-TestPathRejected -Path '\\.\PhysicalDrive0' -ExpectedText 'ambíguo ou não permitido'
    }

    Invoke-Test "Configuration Confined bloqueia caminho de dispositivo" {
        Assert-ConfigurationPathRejected -Path '\\.\PhysicalDrive0' -ExpectedText 'absolute local drive path'
    }

    Invoke-Test "Alternate Data Stream é rejeitado" {
        Assert-TestPathRejected -Path (Join-Path $script:DiretorioTemporario 'config.json:stream') -ExpectedText 'ADS'
    }

    Invoke-Test "Configuration Confined bloqueia Alternate Data Stream" {
        Assert-ConfigurationPathRejected `
            -Path (Join-Path $script:DiretorioTemporario 'config.json:stream') `
            -ExpectedText 'absolute local drive path'
    }

    Invoke-Test "WorkspaceRoot inexistente bloqueia setup sem criá-lo" {
        $originalRoot = $script:WorkspaceRoot
        $originalWorkspace = $script:DiretorioTemporario
        $missingRoot = Join-Path $originalWorkspace ('missing-' + [guid]::NewGuid().ToString('N'))
        try {
            $script:WorkspaceRoot = $missingRoot
            Assert-ActionThrows -ExpectedText 'WorkspaceRoot deve existir previamente' -Action {
                Initialize-TestWorkspace
            }
            if ([System.IO.Directory]::Exists($missingRoot)) {
                throw 'O setup criou um WorkspaceRoot que deveria permanecer inexistente.'
            }
        }
        finally {
            $script:WorkspaceRoot = $originalRoot
            $script:DiretorioTemporario = $originalWorkspace
        }
    }

    Invoke-Test "WorkspaceRoot não vazio bloqueia setup" {
        $sentinel = New-TestFile -Path (Join-Path $script:DiretorioTemporario 'root-nonempty.json') -Content '{}'
        Assert-ActionThrows -ExpectedText 'deve estar vazio' -Action {
            Initialize-TestWorkspace
        }
        if (-not [System.IO.File]::Exists($sentinel)) {
            throw 'O setup alterou a fixture que tornou a raiz não vazia.'
        }
    }

    Invoke-Test "Identidade divergente bloqueia acesso ao workspace" {
        $originalIdentity = $script:WorkspaceIdentity
        try {
            $script:WorkspaceIdentity = 'identity-mismatch-sentinel'
            Assert-ActionThrows -Action { Assert-TestWorkspace }
        }
        finally {
            $script:WorkspaceIdentity = $originalIdentity
        }
    }

    Invoke-Test "Falha de identidade durante cleanup preserva a fixture" {
        $fixture = New-TestFile -Path (Join-Path $script:DiretorioTemporario 'identity-cleanup.json') -Content '{}'
        $record = @($script:ArquivosCriadosPeloTeste | Where-Object { $_.Path -eq $fixture })[0]
        $originalIdentity = $record.Identity
        $originalCleanupState = $script:CleanupIncomplete
        try {
            $record.Identity = 'identity-mismatch-sentinel'
            Clear-TestWorkspace
            if (-not [System.IO.File]::Exists($fixture)) {
                throw 'Cleanup removeu uma fixture cuja identidade não correspondia.'
            }
            if (-not $script:CleanupIncomplete) {
                throw 'Cleanup não registrou a identidade divergente como incompleta.'
            }
        }
        finally {
            $record.Identity = $originalIdentity
            $script:CleanupIncomplete = $originalCleanupState
        }
    }

    Invoke-Test "Cleanup preserva arquivo não registrado como próprio" {
        $fixture = New-TestFile -Path (Join-Path $script:DiretorioTemporario 'untracked-sentinel.json') -Content '{}'
        $record = @($script:ArquivosCriadosPeloTeste | Where-Object { $_.Path -eq $fixture })[0]
        if (-not $script:ArquivosCriadosPeloTeste.Remove($record)) {
            throw 'Não foi possível preparar a condição sintética de fixture não registrada.'
        }
        try {
            Clear-TestWorkspace
            if (-not [System.IO.File]::Exists($fixture)) {
                throw 'Cleanup removeu um arquivo que não estava registrado como próprio.'
            }
        }
        finally {
            $script:ArquivosCriadosPeloTeste.Add($record)
        }
    }

    Invoke-Test "Cleanup preserva fixture com conteúdo divergente" {
        $fixture = New-TestFile -Path (Join-Path $script:DiretorioTemporario 'cleanup-mismatch.json') -Content '{}'
        $record = @($script:ArquivosCriadosPeloTeste | Where-Object { $_.Path -eq $fixture })[0]
        $originalHash = $record.Sha256
        $originalCleanupState = $script:CleanupIncomplete
        try {
            $record.Sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
            Clear-TestWorkspace
            if (-not [System.IO.File]::Exists($fixture)) {
                throw 'Cleanup removeu uma fixture com hash divergente.'
            }
            if (-not $script:CleanupIncomplete) {
                throw 'Cleanup não registrou a divergência como incompleta.'
            }
        }
        finally {
            $record.Sha256 = $originalHash
            $script:CleanupIncomplete = $originalCleanupState
        }
    }

    Invoke-Test "Falha de setup produz ExitCode diferente de zero" {
        if ((Get-TestExitCode -FailureCount 0 -SetupFailed $true -CleanupFailed $false -BlockedCount 0) -ne 1) {
            throw 'Falha de setup não resultaria em ExitCode 1.'
        }
    }

    Invoke-Test "Falha de cleanup produz ExitCode diferente de zero" {
        if ((Get-TestExitCode -FailureCount 0 -SetupFailed $false -CleanupFailed $true -BlockedCount 0) -ne 1) {
            throw 'Falha de cleanup não resultaria em ExitCode 1.'
        }
    }

    Invoke-Test "TrustedPath permanece compatível com chamada somente ConfigurationPath" {
        $Caminho = New-TestConfiguration
        $Config = Get-Configuration -ConfigurationPath $Caminho
        if ($Config.Prefixo -ne 'EMP') {
            throw 'TrustedPath não preservou o resultado esperado.'
        }
    }

    Invoke-ReparsePointGateTest
}
catch {
    if (-not $script:SetupComplete) {
        $script:SetupFailure = $_.Exception.Message
    }
    else {
        $script:HarnessFailure = $_.Exception.Message
    }
}
finally {
    try {
        Clear-TestWorkspace
    }
    catch {
        $script:CleanupIncomplete = $true
        $script:CleanupFailure = $_.Exception.Message
    }
}

if (-not [string]::IsNullOrWhiteSpace($script:SetupFailure)) {
    $TotalTestes++
    $TestesFalharam++
    Write-Host "[FAIL] Setup: $($script:SetupFailure)" -ForegroundColor Red
}
if (-not [string]::IsNullOrWhiteSpace($script:HarnessFailure)) {
    $TotalTestes++
    $TestesFalharam++
    Write-Host "[FAIL] Harness: $($script:HarnessFailure)" -ForegroundColor Red
}
if (-not [string]::IsNullOrWhiteSpace($script:CleanupFailure)) {
    $TotalTestes++
    $TestesFalharam++
    Write-Host "[FAIL] Cleanup: $($script:CleanupFailure)" -ForegroundColor Red
}

if ($script:CleanupIncomplete) {
    $TotalTestes++
    $TestesFalharam++
    Write-Host '[FAIL] CLEANUP_INCOMPLETE: fixtures ambíguas foram preservadas.' -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================"
Write-Host " RESULTADO DOS TESTES - MODULO 02"
Write-Host "============================================"
Write-Host ""
Write-Host "Total de testes : $TotalTestes"
Write-Host "Passaram        : $TestesPassaram"
Write-Host "Falharam        : $TestesFalharam"
Write-Host "Bloqueados      : $TestesBloqueados"
Write-Host ""

$FinalExitCode = Get-TestExitCode `
    -FailureCount $TestesFalharam `
    -SetupFailed (-not [string]::IsNullOrWhiteSpace($script:SetupFailure)) `
    -CleanupFailed ($script:CleanupIncomplete -or -not [string]::IsNullOrWhiteSpace($script:CleanupFailure)) `
    -BlockedCount $TestesBloqueados

if ($TestesBloqueados -gt 0) {
    Write-Host "STATUS: EXECUÇÃO BLOQUEADA OU INCOMPLETA" -ForegroundColor Yellow
    exit 1
}
elseif ($FinalExitCode -eq 0) {
    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "STATUS: EXISTEM FALHAS" -ForegroundColor Red
    exit 1
}
