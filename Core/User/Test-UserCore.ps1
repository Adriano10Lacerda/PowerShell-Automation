#Requires -Version 5.1

<#
.SYNOPSIS
    Testes do User Core V2.

.DESCRIPTION
    Valida modelos, consulta de usuário, Simulation Mode,
    usuários existentes/inexistentes e tratamento de erros.

.NOTES
    PowerShell Automation V2
#>

$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success
    )

    if ($Success) {
        Write-Host "PASSOU: $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "FALHOU: $Name" -ForegroundColor Red
        $script:Failed++
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             TESTES - USER CORE V2" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$modelsPath = Join-Path `
    $PSScriptRoot `
    "User-Models.ps1"

$functionsPath = Join-Path `
    $PSScriptRoot `
    "User-Functions.psm1"

Write-TestResult `
    "User-Models.ps1 existe" `
    (Test-Path -LiteralPath $modelsPath)

Write-TestResult `
    "User-Functions.psm1 existe" `
    (Test-Path -LiteralPath $functionsPath)

# ============================================================
# IMPORTAÇÃO
# ============================================================

$moduleImported = $false

try {

    Import-Module `
        $functionsPath `
        -Force `
        -ErrorAction Stop

    $userCoreModule = Get-Module | Where-Object { $_.Path -eq [System.IO.Path]::GetFullPath($functionsPath) } | Select-Object -First 1

    if ($null -ne $userCoreModule) {
        & $userCoreModule {
            $script:ExternalCallCounts = @{ GetModule=0; ImportModule=0; GetADUser=0 }
            $script:ADFixtureNull = $false
            Set-Item Function:\script:Get-Module {
                param([string]$Name, [switch]$ListAvailable, [string]$FullyQualifiedName)
                if ($Name -eq 'ActiveDirectory') { $script:ExternalCallCounts.GetModule++; return [PSCustomObject]@{ Name='ActiveDirectory' } }
                Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
            } -Force
            Set-Item Function:\script:Import-Module {
                param([string]$Name, [string]$FullyQualifiedName, [string]$Function, [string]$Cmdlet, [string]$Variable, [string]$Alias, [switch]$Force, [switch]$Global, [switch]$PassThru, [string]$Prefix, [string]$Scope, [string]$NameParameter, [string]$ErrorAction)
                if ($Name -eq 'ActiveDirectory') { $script:ExternalCallCounts.ImportModule++; return }
                Microsoft.PowerShell.Core\Import-Module @PSBoundParameters
            } -Force
            Set-Item Function:\script:Get-ADUser {
                param([string]$Identity,[string]$Server,[string[]]$Properties,[string]$ErrorAction)
                $script:ExternalCallCounts.GetADUser++
                if ($script:ADFixtureError) { throw 'Fixture AD failure' }
                if ($script:ADFixtureNull) { return $null }
                [PSCustomObject]@{ SamAccountName='fixture.user'; UserPrincipalName='fixture.user@example.invalid'; Name='Fixture User'; Enabled=$true; LockedOut=$false; MemberOf=@() }
            } -Force
            $script:ADFixtureError = $false
        }
    }

    $moduleImported = $true
}
catch {

    $moduleImported = $false
}

Write-TestResult `
    "User Core importa sem erro" `
    $moduleImported

Write-TestResult "User Core resolve fail-closed AD/import stubs no escopo do módulo" ($null -ne $userCoreModule)
$userCoreStubResolution = & $userCoreModule {
    [PSCustomObject]@{
        ADUser = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).CommandType
        Loader = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
    }
}
Write-TestResult "User Core resolve AD e loader para funções stub" ($userCoreStubResolution.ADUser -eq 'Function' -and $userCoreStubResolution.Loader -eq 'Function')

# ============================================================
# FUNÇÕES
# ============================================================

Write-TestResult `
    "Test-UserADExists disponível" `
    ($null -ne (Get-Command Test-UserADExists -ErrorAction SilentlyContinue))

Write-TestResult `
    "Get-UserADInfo disponível" `
    ($null -ne (Get-Command Get-UserADInfo -ErrorAction SilentlyContinue))

$realReadConfiguration = [PSCustomObject]@{ Domain='example.invalid'; DomainController='fixture.invalid'; SimulationMode=$false; UserPrincipalName=[PSCustomObject]@{Domain='example.invalid'}; Simulation=[PSCustomObject]@{ExistingSamAccountNames=@()} }
$beforeUnauthorizedRead = & $userCoreModule { @{} + $script:ExternalCallCounts }
$unauthorizedRead = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $realReadConfiguration
$afterUnauthorizedRead = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Leitura sem AllowRealRead falha fechada" (-not $unauthorizedRead.Success -and $unauthorizedRead.QueryStatus -eq 'NotQueried')
Write-TestResult "Leitura não autorizada não alcança fronteira externa" (($beforeUnauthorizedRead.Values | Measure-Object -Sum).Sum -eq ($afterUnauthorizedRead.Values | Measure-Object -Sum).Sum)
$legacyRead = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $realReadConfiguration -AllowRealOperation
$afterLegacyRead = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "AllowRealOperation legado não autoriza leitura" (-not $legacyRead.Success -and $legacyRead.QueryStatus -eq 'NotQueried')
Write-TestResult "Autorização legada não chama AD" (($afterLegacyRead.Values | Measure-Object -Sum).Sum -eq ($afterUnauthorizedRead.Values | Measure-Object -Sum).Sum)

$previewRead = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $realReadConfiguration -WhatIf
$afterPreviewRead = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "WhatIf retorna sem consulta" ($previewRead.Mode -eq 'Preview' -and $previewRead.QueryStatus -eq 'NotQueried')
Write-TestResult "WhatIf não alcança fronteira externa" (($afterPreviewRead.Values | Measure-Object -Sum).Sum -eq ($afterLegacyRead.Values | Measure-Object -Sum).Sum)
Write-TestResult "Simulation, autorização ausente e WhatIf não chamaram AD" (($afterPreviewRead.Values | Measure-Object -Sum).Sum -eq 0)
$conflictingUserRead = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration ([PSCustomObject]@{SimulationMode=$true}) -AllowRealRead
$afterUserConflict = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Simulation com AllowRealRead é rejeitado" (-not $conflictingUserRead.Success -and $conflictingUserRead.Error -match 'contradit')
Write-TestResult "Modo conflitante não chama AD" (($afterUserConflict.Values | Measure-Object -Sum).Sum -eq ($afterLegacyRead.Values | Measure-Object -Sum).Sum)

$authorizedRead = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $realReadConfiguration -AllowRealRead
$afterAuthorizedRead = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Leitura autorizada usa apenas fixture interceptada" ($authorizedRead.Success -and $authorizedRead.QueryStatus -eq 'Found' -and $authorizedRead.Data.Identity.SamAccountName -eq 'fixture.user')
Write-TestResult "Contadores registram exclusivamente stubs AD" (($afterAuthorizedRead.GetModule -gt $afterPreviewRead.GetModule) -and ($afterAuthorizedRead.ImportModule -gt $afterPreviewRead.ImportModule) -and ($afterAuthorizedRead.GetADUser -gt $afterPreviewRead.GetADUser))
$authorizedExists = Test-UserADExists -SamAccountName 'fixture.user' -Configuration $realReadConfiguration -AllowRealRead
Write-TestResult "Usuário AD encontrado não é rotulado como Simulation" ($authorizedExists.Success -and $authorizedExists.Data -and $authorizedExists.QueryStatus -eq 'Found' -and -not $authorizedExists.IsSimulated)
$afterAuthorizedExists = & $userCoreModule { @{} + $script:ExternalCallCounts }

# ============================================================
# CONFIGURAÇÃO DE SIMULAÇÃO
# ============================================================

$configuration = [PSCustomObject]@{
    Domain           = "BRSPO"
    DomainController = ""
    TargetOU         = ""
    SimulationMode   = $true

    UserPrincipalName = [PSCustomObject]@{
        Enabled = $true
        Domain  = "example.local"
    }

    Simulation = [PSCustomObject]@{
        ExistingSamAccountNames = @(
            "silva.maria.ext",
            "silva.maria2.ext",
            "silva.maria3.ext"
        )
    }
}

Write-TestResult `
    "Configuração de simulação criada" `
    ($configuration.SimulationMode -eq $true)

# ============================================================
# TESTE 1 - USUÁRIO EXISTENTE
# ============================================================

$existsResult = Test-UserADExists `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Usuário existente é encontrado em Simulation Mode" `
    (
        $existsResult.Success -eq $true -and
        $existsResult.Data -eq $true
    )

# ============================================================
# TESTE 2 - USUÁRIO INEXISTENTE
# ============================================================

$notExistsResult = Test-UserADExists `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration

Write-TestResult `
    "Usuário inexistente é identificado corretamente" `
    (
        $notExistsResult.Success -eq $true -and
        $notExistsResult.Data -eq $false
    )

# ============================================================
# TESTE 3 - SAMACCOUNTNAME VAZIO
# ============================================================

$emptyResult = Test-UserADExists `
    -SamAccountName " " `
    -Configuration $configuration

Write-TestResult `
    "SamAccountName vazio gera erro controlado" `
    (
        $emptyResult.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($emptyResult.Error)
    )

# ============================================================
# TESTE 4 - CONSULTAR USUÁRIO EXISTENTE
# ============================================================

$userResult = Get-UserADInfo `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Consulta de usuário existente retorna sucesso" `
    (
        $userResult.Success -eq $true -and
        $null -ne $userResult.Data
    )

# ============================================================
# TESTE 5 - MODELO IDENTITY
# ============================================================

Write-TestResult `
    "Modelo Identity possui SamAccountName" `
    (
        $null -ne $userResult.Data.Identity -and
        $userResult.Data.Identity.SamAccountName -eq "silva.maria.ext"
    )

# ============================================================
# TESTE 6 - UPN
# ============================================================

Write-TestResult `
    "UPN é gerado no modelo de simulação" `
    (
        $userResult.Data.Identity.UserPrincipalName -eq
        "silva.maria.ext@example.local"
    )

# ============================================================
# TESTE 7 - DISTINGUISHED NAME
# ============================================================

Write-TestResult `
    "DistinguishedName está disponível" `
    (
        -not [string]::IsNullOrWhiteSpace(
            $userResult.Data.Identity.DistinguishedName
        )
    )

# ============================================================
# TESTE 8 - DISPLAY NAME
# ============================================================

Write-TestResult `
    "DisplayName está disponível" `
    (
        -not [string]::IsNullOrWhiteSpace(
            $userResult.Data.Personal.DisplayName
        )
    )

# ============================================================
# TESTE 9 - ACCOUNT ENABLED
# ============================================================

Write-TestResult `
    "Status Enabled está disponível" `
    (
        $null -ne $userResult.Data.Account.Enabled
    )

# ============================================================
# TESTE 10 - LOCKED OUT
# ============================================================

Write-TestResult `
    "Status LockedOut está disponível" `
    (
        $null -ne $userResult.Data.Account.LockedOut
    )

# ============================================================
# TESTE 11 - PASSWORD EXPIRED
# ============================================================

Write-TestResult `
    "PasswordExpired está disponível" `
    (
        $null -ne $userResult.Data.Account.PasswordExpired
    )

# ============================================================
# TESTE 12 - ACTIVITY
# ============================================================

Write-TestResult `
    "Modelo Activity está disponível" `
    (
        $null -ne $userResult.Data.Activity
    )

# ============================================================
# TESTE 13 - GROUPS
# ============================================================

Write-TestResult `
    "Modelo Groups está disponível" `
    (
        $null -ne $userResult.Data.Groups
    )

# ============================================================
# TESTE 14 - USUÁRIO INEXISTENTE
# ============================================================

$missingUserResult = Get-UserADInfo `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration

Write-TestResult `
    "Consulta de usuário inexistente gera erro controlado" `
    (
        $missingUserResult.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($missingUserResult.Error)
    )

# ============================================================
# TESTE 15 - CONFIGURAÇÃO AD INDISPONÍVEL
# ============================================================

$realConfiguration = [PSCustomObject]@{
    Domain           = "BRSPO"
    DomainController = ""
    SimulationMode   = $false

    UserPrincipalName = [PSCustomObject]@{
        Enabled = $true
        Domain  = "example.local"
    }
}

$realResult = Test-UserADExists `
    -SamAccountName "teste" `
    -Configuration $realConfiguration

$realHandled =
    (
        $realResult.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($realResult.Error)
    )

Write-TestResult `
    "Indisponibilidade do AD é tratada sem exceção não controlada" `
    $realHandled

$authorizedFixtureConfiguration = [PSCustomObject]@{
    Domain = 'example.invalid'; DomainController = 'fixture.invalid'; SimulationMode = $false
    UserPrincipalName = [PSCustomObject]@{ Enabled = $true; Domain = 'example.invalid' }
}
$userCoreCountsBeforeFixturePaths = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Caminhos demonstrativos posteriores não acrescentaram chamadas" (($userCoreCountsBeforeFixturePaths.Values | Measure-Object -Sum).Sum -eq ($afterAuthorizedExists.Values | Measure-Object -Sum).Sum)
$directUserWhatIf = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $authorizedFixtureConfiguration -AllowRealRead -WhatIf
& $userCoreModule { $script:ADFixtureError = $false }
$directUserPreview = Test-UserADExists -SamAccountName 'fixture.user' -Configuration $authorizedFixtureConfiguration -Preview
$userCoreCountsAfterPreview = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "User Core WhatIf e Preview diretos não consultam AD" ($directUserWhatIf.Mode -eq 'Preview' -and $directUserPreview.Mode -eq 'Preview' -and (($userCoreCountsAfterPreview.Values | Measure-Object -Sum).Sum -eq ($userCoreCountsBeforeFixturePaths.Values | Measure-Object -Sum).Sum))
$conflictingUserWhatIf = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $configuration -AllowRealRead -WhatIf
$userCountsAfterConflict = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "User Core rejeita autorização contraditória mesmo com WhatIf" (-not $conflictingUserWhatIf.Success -and $conflictingUserWhatIf.Error -match 'contradit' -and (($userCountsAfterConflict.Values | Measure-Object -Sum).Sum -eq ($userCoreCountsAfterPreview.Values | Measure-Object -Sum).Sum))

& $userCoreModule { $script:ADFixtureError = $true }
$failedADFixture = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $authorizedFixtureConfiguration -AllowRealRead
& $userCoreModule { $script:ADFixtureError = $false; $script:ADFixtureNull = $true }
$nullADFixture = Get-UserADInfo -SamAccountName 'fixture.user' -Configuration $authorizedFixtureConfiguration -AllowRealRead
& $userCoreModule { $script:ADFixtureNull = $false }
Write-TestResult "Erro AD autorizado permanece Error, não NotFound" ($failedADFixture.QueryStatus -eq 'Error' -and -not $failedADFixture.Success)
Write-TestResult "Resposta nula normal é NotFound sem erro de consulta" ($nullADFixture.QueryStatus -eq 'NotFound' -and -not $nullADFixture.Success -and $nullADFixture.Data -eq $null -and $nullADFixture.Error -eq $null)

# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RESULTADO DOS TESTES" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $($script:Passed + $script:Failed)"
Write-Host "PASS  : $script:Passed" -ForegroundColor Green

if ($script:Failed -eq 0) {
    Write-Host "FAIL  : $script:Failed" -ForegroundColor Green
}
else {
    Write-Host "FAIL  : $script:Failed" -ForegroundColor Red
}

Write-Host ""

if ($script:Failed -eq 0) {
    Write-Host "USER CORE: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "USER CORE: EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}
