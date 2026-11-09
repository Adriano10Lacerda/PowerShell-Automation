#requires -Version 5.1

<#
.SYNOPSIS
    Testes do User Management V2.

.DESCRIPTION
    Valida a camada de gerenciamento de usuários
    utilizando o User Core em Simulation Mode.

.NOTES
    Projeto: PowerShell-Automation
    Versão: V2
#>

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$global:PSModuleAutoLoadingPreference = 'None'
Write-Output 'HARNESS_START:USER_MANAGEMENT_V1'

if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) {
    throw "ActiveDirectory já está carregado neste processo; o harness não continuará."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "           TESTES - USER MANAGEMENT V2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$script:Total = 0
$script:Pass = 0
$script:Fail = 0

function Test-Condition {
    param(
        [string]$Name,
        [bool]$Condition
    )

    $script:Total++

    if ($Condition) {
        $script:Pass++
        Write-Host "PASSOU: $Name" -ForegroundColor Green
    }
    else {
        $script:Fail++
        Write-Host "FALHOU: $Name" -ForegroundColor Red
    }
}

# ============================================================
# CAMINHOS
# ============================================================

$managementPath = Join-Path $PSScriptRoot "User-Management.psm1"
$corePath = Join-Path $PSScriptRoot "..\User-Functions.psm1"
$configPath = Join-Path $PSScriptRoot "..\..\03-AD-User-Provisioning\AD-Configuration.json"


# ============================================================
# TESTE 1 - ARQUIVOS
# ============================================================

Test-Condition `
    -Name "User-Management.psm1 existe" `
    -Condition (Test-Path -LiteralPath $managementPath)

Test-Condition `
    -Name "User Core existe" `
    -Condition (Test-Path -LiteralPath $corePath)


# ============================================================
# IMPORTAÇÃO
# ============================================================

try {
    Import-Module $managementPath -Force

    $managementModule = Get-Module | Where-Object { $_.Path -eq [System.IO.Path]::GetFullPath($managementPath) }
    if (@($managementModule).Count -ne 1) { throw "Esperada uma instância User Management; encontradas $(@($managementModule).Count)." }
    $coreModule = & $managementModule { (Get-Command Get-UserADInfo -CommandType Function -ErrorAction Stop).Module }
    $expectedCorePath = [System.IO.Path]::GetFullPath($corePath)
    if ($null -eq $coreModule -or $coreModule.Path -ne $expectedCorePath) {
        throw "O comando Get-UserADInfo não resolve para a instância esperada do User Core."
    }

    & $coreModule {
        $script:ExternalCallCounts = @{ GetModule=0; ImportModule=0; GetADUser=0 }
        $script:ADFixtureError = $false
        $script:ADFixtureNull = $false
        Set-Item Function:\script:Get-Module { param([string]$Name,[switch]$ListAvailable); if ($Name -ne 'ActiveDirectory') { throw "Get-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.GetModule++; [PSCustomObject]@{Name='ActiveDirectory'} } -Force
        Set-Item Function:\script:Import-Module { param([string]$Name,[string]$ErrorAction); if ($Name -ne 'ActiveDirectory') { throw "Import-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.ImportModule++ } -Force
        Set-Item Function:\script:Get-ADUser { param([string]$Identity,[string]$Server,[string[]]$Properties,[string]$ErrorAction); $script:ExternalCallCounts.GetADUser++; if ($script:ADFixtureError) { throw 'Fixture AD failure' }; if ($script:ADFixtureNull) { return $null }; [PSCustomObject]@{SamAccountName='fixture.user';UserPrincipalName='fixture.user@example.invalid';Name='Fixture User';Enabled=$true;LockedOut=$false;MemberOf=@()} } -Force
    }

    $stubResolution = & $coreModule {
        [PSCustomObject]@{
            Loader = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
            ModuleLookup = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
            ADUser = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).CommandType
            LoaderModule = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Module
            ModuleLookupModule = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Module
            ADUserModule = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).Module
            LoaderIdentity = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.ImportModule'
            ModuleLookupIdentity = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetModule'
            ADUserIdentity = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetADUser'
        }
    }
    if ($stubResolution.Loader -ne 'Function' -or $stubResolution.ModuleLookup -ne 'Function' -or $stubResolution.ADUser -ne 'Function' -or
        $stubResolution.LoaderModule -ne $coreModule -or $stubResolution.ModuleLookupModule -ne $coreModule -or $stubResolution.ADUserModule -ne $coreModule -or
        -not $stubResolution.LoaderIdentity -or -not $stubResolution.ModuleLookupIdentity -or -not $stubResolution.ADUserIdentity) {
        throw "Resolução incompleta dos stubs no SessionState do User Core."
    }

    Test-Condition `
        -Name "User Management importa sem erro" `
        -Condition $true
}
catch {
    Test-Condition `
        -Name "User Management importa sem erro" `
        -Condition $false

    Write-Host ""
    Write-Host "Erro de importação:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}


# ============================================================
# FUNÇÕES DISPONÍVEIS
# ============================================================

Test-Condition `
    -Name "New-UserManagementSummary disponível" `
    -Condition ($null -ne (Get-Command New-UserManagementSummary -ErrorAction SilentlyContinue))

Test-Condition `
    -Name "Get-UserManagement disponível" `
    -Condition ($null -ne (Get-Command Get-UserManagement -ErrorAction SilentlyContinue))

Test-Condition `
    -Name "Get-UserManagementSummary disponível" `
    -Condition ($null -ne (Get-Command Get-UserManagementSummary -ErrorAction SilentlyContinue))


# ============================================================
# CONFIGURAÇÃO DE SIMULAÇÃO
# ============================================================

$configuration = [PSCustomObject]@{
    Domain = "BRSPO"

    DomainController = ""

    SimulationMode = $true

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

Test-Condition `
    -Name "Configuração de simulação criada" `
    -Condition (
        $configuration.SimulationMode -eq $true -and
        $configuration.Simulation.ExistingSamAccountNames.Count -eq 3
    )


# ============================================================
# CONSULTA DE USUÁRIO EXISTENTE
# ============================================================

$existingResult = Get-UserManagement `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Test-Condition `
    -Name "Usuário existente retorna sucesso" `
    -Condition ($existingResult.Success -eq $true)

Test-Condition `
    -Name "SamAccountName retornado corretamente" `
    -Condition ($existingResult.SamAccountName -eq "silva.maria.ext")

Test-Condition `
    -Name "SimulationMode está ativo" `
    -Condition ($existingResult.SimulationMode -eq $true)

Test-Condition `
    -Name "Status do usuário está disponível" `
    -Condition (-not [string]::IsNullOrWhiteSpace($existingResult.Status))

Test-Condition `
    -Name "Summary foi criado" `
    -Condition ($null -ne $existingResult.Summary)

Test-Condition `
    -Name "Data completa do usuário está disponível" `
    -Condition ($null -ne $existingResult.Data)


# ============================================================
# CAMPOS DO SUMMARY
# ============================================================

Test-Condition `
    -Name "Summary possui SamAccountName" `
    -Condition ($existingResult.Summary.SamAccountName -eq "silva.maria.ext")

Test-Condition `
    -Name "Summary possui DisplayName" `
    -Condition (-not [string]::IsNullOrWhiteSpace($existingResult.Summary.DisplayName))

Test-Condition `
    -Name "Summary possui UPN" `
    -Condition (-not [string]::IsNullOrWhiteSpace($existingResult.Summary.UserPrincipalName))

Test-Condition `
    -Name "Summary possui Enabled" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Enabled")

Test-Condition `
    -Name "Summary possui LockedOut" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "LockedOut")

Test-Condition `
    -Name "Summary possui PasswordExpired" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "PasswordExpired")

Test-Condition `
    -Name "Summary possui Department" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Department")

Test-Condition `
    -Name "Summary possui Title" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Title")

Test-Condition `
    -Name "Summary possui Mail" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Mail")

Test-Condition `
    -Name "Summary possui LastLogonDate" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "LastLogonDate")


# ============================================================
# CONSULTA DE USUÁRIO INEXISTENTE
# ============================================================

$missingResult = Get-UserManagement `
    -SamAccountName "usuario.nao.existe" `
    -Configuration $configuration

Test-Condition `
    -Name "Usuário inexistente gera falha controlada" `
    -Condition ($missingResult.Success -eq $false)

Test-Condition `
    -Name "Usuário inexistente possui mensagem de erro" `
    -Condition (@($missingResult.Errors).Count -gt 0)


# ============================================================
# ENTRADA INVÁLIDA
# ============================================================

$invalidResult = Get-UserManagement `
    -SamAccountName " " `
    -Configuration $configuration

Test-Condition `
    -Name "SamAccountName inválido é tratado" `
    -Condition ($invalidResult.Success -eq $false)

Test-Condition `
    -Name "Entrada inválida gera erro controlado" `
    -Condition (@($invalidResult.Errors).Count -gt 0)


# ============================================================
# SUMMARY HELPER
# ============================================================

$summaryResult = Get-UserManagementSummary `
    -ManagementResult $existingResult

Test-Condition `
    -Name "Get-UserManagementSummary retorna sucesso" `
    -Condition ($summaryResult.Success -eq $true)

Test-Condition `
    -Name "Get-UserManagementSummary retorna Data" `
    -Condition ($null -ne $summaryResult.Data)


# ============================================================
# ERRO CONTROLADO DO SUMMARY
# ============================================================

$failedManagement = [PSCustomObject]@{
    Success = $false
    Errors  = @(
        "Usuário não encontrado."
    )
}

$failedSummary = Get-UserManagementSummary `
    -ManagementResult $failedManagement

Test-Condition `
    -Name "Summary de resultado com erro é tratado" `
    -Condition ($failedSummary.Success -eq $false)

Test-Condition `
    -Name "Summary de erro preserva mensagem" `
    -Condition (
        $failedSummary.Error -like "*Usuário não encontrado*"
    )


# ============================================================
# ISOLAMENTO FAIL-CLOSED
$realConfiguration = [PSCustomObject]@{
    Domain='example.invalid'; DomainController='fixture.invalid'; SimulationMode=$false
    UserPrincipalName=[PSCustomObject]@{Enabled=$true;Domain='example.invalid'}
    Simulation=[PSCustomObject]@{ExistingSamAccountNames=@();LockedSamAccountNames=@();DisabledSamAccountNames=@();PasswordChangeAtLogonSamAccountNames=@()}
}
$countsBefore = & $coreModule { @{} + $script:ExternalCallCounts }
Test-Condition -Name "Caminhos simulados anteriores não chamaram AD" -Condition (($countsBefore.Values | Measure-Object -Sum).Sum -eq 0)
$userManagementStubResolution = & $coreModule { (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).CommandType }
Test-Condition -Name "Management usa stub AD instalado no Core aninhado" -Condition ($userManagementStubResolution -eq 'Function')
$unauthorized = Get-UserManagement -SamAccountName 'fixture.user' -Configuration $realConfiguration
$countsUnauthorized = & $coreModule { @{} + $script:ExternalCallCounts }
Test-Condition -Name "Management sem AllowRealRead falha fechado" -Condition (-not $unauthorized.Success -and $unauthorized.Status -eq 'Unauthorized')
Test-Condition -Name "Management sem autorização não alcança AD" -Condition (($countsBefore.Values | Measure-Object -Sum).Sum -eq ($countsUnauthorized.Values | Measure-Object -Sum).Sum)
$preview = Get-UserManagement -SamAccountName 'fixture.user' -Configuration $realConfiguration -WhatIf
$countsPreview = & $coreModule { @{} + $script:ExternalCallCounts }
Test-Condition -Name "Management WhatIf não consulta" -Condition ($preview.Status -eq 'Preview' -and $preview.Mode -eq 'Preview')
Test-Condition -Name "Management WhatIf mantém contadores" -Condition (($countsPreview.Values | Measure-Object -Sum).Sum -eq ($countsUnauthorized.Values | Measure-Object -Sum).Sum)
$conflictingSimulationWhatIf = Get-UserManagement -SamAccountName 'fixture.user' -Configuration ([PSCustomObject]@{SimulationMode=$true}) -AllowRealRead -WhatIf
Test-Condition -Name "Management rejeita autorização conflitante em WhatIf" -Condition (-not $conflictingSimulationWhatIf.Success -and $conflictingSimulationWhatIf.Errors -match 'contradit')
$authorized = Get-UserManagement -SamAccountName 'fixture.user' -Configuration $realConfiguration -AllowRealRead
$countsAuthorized = & $coreModule { @{} + $script:ExternalCallCounts }
Test-Condition -Name "Management encaminha leitura autorizada a fixture" -Condition ($authorized.Success -and $authorized.Data.Identity.SamAccountName -eq 'fixture.user')
Test-Condition -Name "Management consulta somente stubs contados" -Condition ($countsAuthorized.GetModule -gt 0 -and $countsAuthorized.ImportModule -gt 0 -and $countsAuthorized.GetADUser -gt 0)
$conflictingWhatIf = Get-UserManagement -SamAccountName 'fixture.user' -Configuration ([PSCustomObject]@{SimulationMode=$true}) -AllowRealRead -WhatIf
$countsAfterConflict = & $coreModule { @{} + $script:ExternalCallCounts }
Test-Condition -Name "Management rejeita conflito antes de WhatIf sem AD" -Condition (-not $conflictingWhatIf.Success -and (($countsAfterConflict.Values | Measure-Object -Sum).Sum -eq ($countsAuthorized.Values | Measure-Object -Sum).Sum))
& $coreModule { $script:ADFixtureError = $true }
$failedADManagement = Get-UserManagement -SamAccountName 'fixture.user' -Configuration $realConfiguration -AllowRealRead
& $coreModule { $script:ADFixtureError = $false }
Test-Condition -Name "Management preserva falha AD como Error" -Condition (-not $failedADManagement.Success -and $failedADManagement.QueryStatus -eq 'Error' -and $failedADManagement.Errors -match 'Fixture AD failure')
& $coreModule { $script:ADFixtureNull = $true }
$notFoundManagement = Get-UserManagement -SamAccountName 'missing.fixture' -Configuration $realConfiguration -AllowRealRead
$notFoundSummary = Get-UserManagementSummary -ManagementResult $notFoundManagement
& $coreModule { $script:ADFixtureNull = $false }
Test-Condition -Name "Management preserva NotFound sem fabricar erro" -Condition (-not $notFoundManagement.Success -and $notFoundManagement.Status -eq 'NotFound' -and $notFoundManagement.QueryStatus -eq 'NotFound' -and @($notFoundManagement.Errors).Count -eq 0)
Test-Condition -Name "Summary preserva NotFound sem erro de consulta" -Condition (-not $notFoundSummary.Success -and $notFoundSummary.Status -eq 'NotFound' -and $notFoundSummary.QueryStatus -eq 'NotFound' -and $notFoundSummary.Error -eq $null)

# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                  RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $script:Total"
Write-Host "PASS  : $script:Pass" -ForegroundColor Green
Write-Host "FAIL  : $script:Fail" -ForegroundColor Red

Write-Host ""

if ($script:Fail -eq 0) {
    Write-Host "USER MANAGEMENT: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    Write-Output 'HARNESS_PASS:USER_MANAGEMENT_V1'
    exit 0
}
else {
    Write-Host "USER MANAGEMENT: EXISTEM TESTES COM FALHA!" -ForegroundColor Red
    exit 1
}
