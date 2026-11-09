#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$functionsPath = Join-Path $scriptRoot "Group-Functions.psm1"

$configPath = Join-Path `
    (Split-Path -Parent (Split-Path -Parent $scriptRoot)) `
    "06-AD-Group-Management\Group-Configuration.json"

$testsPassed = 0
$testsFailed = 0

function Test-Result {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "[PASSOU] $Name" -ForegroundColor Green
        $script:testsPassed++
    }
    else {
        Write-Host "[FALHOU] $Name" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       TESTES - GROUP CORE V2" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------
# TESTE 1 - Arquivo do módulo
# ---------------------------------------------------------

Test-Result `
    -Name "Group-Functions.psm1 existe" `
    -Condition (Test-Path -LiteralPath $functionsPath)

# ---------------------------------------------------------
# TESTE 2 - Arquivo de configuração
# ---------------------------------------------------------

if (-not (Test-Path -LiteralPath $functionsPath)) {
    throw "Group-Functions.psm1 não encontrado."
}

# ---------------------------------------------------------
# Importação
# ---------------------------------------------------------

Import-Module $functionsPath -Force -ErrorAction Stop
$groupCoreModule = Get-Module | Where-Object { $_.Path -eq [System.IO.Path]::GetFullPath($functionsPath) } | Select-Object -First 1
if ($null -eq $groupCoreModule) { throw "Group Core não foi localizado após importação." }
& $groupCoreModule {
    $script:ExternalCallCounts = @{ GetModule=0; ImportModule=0; GetADDomain=0; GetADGroup=0; GetADGroupMember=0 }
    $script:GroupFixtureMode = 'Success'
    Set-Item Function:\script:Get-Module { param([string]$Name,[switch]$ListAvailable); if ($Name -eq 'ActiveDirectory') { $script:ExternalCallCounts.GetModule++; return [PSCustomObject]@{Name='ActiveDirectory'} }; Microsoft.PowerShell.Core\Get-Module @PSBoundParameters } -Force
    Set-Item Function:\script:Import-Module { param([string]$Name,[string]$ErrorAction); if ($Name -eq 'ActiveDirectory') { $script:ExternalCallCounts.ImportModule++; return }; Microsoft.PowerShell.Core\Import-Module @PSBoundParameters } -Force
    Set-Item Function:\script:Get-ADDomain { param([string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.GetADDomain++; [PSCustomObject]@{DNSRoot='fixture.invalid';DomainMode='Windows2016Domain'} } -Force
    Set-Item Function:\script:Get-ADGroup { param([string]$Identity,[string]$Server,[string[]]$Properties,[string]$ErrorAction); $script:ExternalCallCounts.GetADGroup++; if ($script:GroupFixtureMode -eq 'Error') { throw 'Fixture group query failure' }; if ($script:GroupFixtureMode -eq 'Null') { return $null }; [PSCustomObject]@{Name='Fixture Group';SamAccountName='Fixture Group';Description='fixture';GroupCategory='Security';GroupScope='Global';DistinguishedName='CN=Fixture'} } -Force
    Set-Item Function:\script:Get-ADGroupMember { param($Identity,[string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.GetADGroupMember++; @([PSCustomObject]@{SamAccountName='fixture.user';Name='Fixture User';objectClass='user'}) } -Force
}
$groupCoreStubResolution = & $groupCoreModule {
    [PSCustomObject]@{
        Group = (Get-Command Get-ADGroup -CommandType Function -ErrorAction SilentlyContinue).CommandType
        Members = (Get-Command Get-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).CommandType
        Loader = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
    }
}
Test-Result -Name "Group Core resolve comandos AD e loader para stubs" -Condition ($groupCoreStubResolution.Group -eq 'Function' -and $groupCoreStubResolution.Members -eq 'Function' -and $groupCoreStubResolution.Loader -eq 'Function')

$config = [PSCustomObject]@{
    SimulationMode = $true
    ActiveDirectory = [PSCustomObject]@{ DomainController = 'fixture.invalid' }
    Group = [PSCustomObject]@{ DefaultCategory = 'Security'; DefaultScope = 'Global' }
    Simulation = [PSCustomObject]@{
        ExistingGroups = @(
            [PSCustomObject]@{ Name='TI-Suporte'; Description='Grupo de suporte de TI'; Members=@('maria.santos') },
            [PSCustomObject]@{ Name='TI-Infraestrutura'; Description='Grupo de infraestrutura'; Members=@('carlos.oliveira') },
            [PSCustomObject]@{ Name='Administradores'; Description='Administradores'; Members=@('joao.silva') }
        )
        ExistingUsers = @('maria.santos','joao.silva','carlos.oliveira')
    }
}

$realConfig = [PSCustomObject]@{ SimulationMode=$false; ActiveDirectory=[PSCustomObject]@{DomainController='fixture.invalid'}; Group=[PSCustomObject]@{DefaultCategory='Security';DefaultScope='Global'}; Simulation=[PSCustomObject]@{ExistingGroups=@();ExistingUsers=@()} }
$countsBeforeGates = & $groupCoreModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Caminhos simulados anteriores não chamaram fronteiras" -Condition (($countsBeforeGates.Values | Measure-Object -Sum).Sum -eq 0)
$blockedGroupRead = Get-GroupADInfo -GroupName 'Fixture Group' -Configuration $realConfig
$countsAfterBlockedRead = & $groupCoreModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Group read sem autorização falha fechada" -Condition (-not $blockedGroupRead.Success -and $blockedGroupRead.Error -match 'AllowRealRead')
Test-Result -Name "Group read sem autorização não chama fronteiras" -Condition (($countsBeforeGates.Values | Measure-Object -Sum).Sum -eq ($countsAfterBlockedRead.Values | Measure-Object -Sum).Sum)
$previewGroupRead = Get-GroupInventory -GroupName 'Fixture Group' -Configuration $realConfig -WhatIf
$countsAfterWhatIf = & $groupCoreModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Group WhatIf não consulta" -Condition ($previewGroupRead.Mode -eq 'Preview' -and $previewGroupRead.QueryStatus -eq 'NotQueried')
Test-Result -Name "Group WhatIf mantém contadores" -Condition (($countsAfterWhatIf.Values | Measure-Object -Sum).Sum -eq ($countsAfterBlockedRead.Values | Measure-Object -Sum).Sum)
$conflictingConfig = Get-GroupADInfo -GroupName 'TI-Suporte' -Configuration $config -AllowRealRead
$countsAfterConflict = & $groupCoreModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Simulation com autorização real é rejeitada" -Condition (-not $conflictingConfig.Success -and $conflictingConfig.Error -match 'contradit')
Test-Result -Name "Combinação conflitante não chama fronteiras" -Condition (($countsAfterConflict.Values | Measure-Object -Sum).Sum -eq ($countsAfterWhatIf.Values | Measure-Object -Sum).Sum)
$fixtureGroupRead = Get-GroupADInfo -GroupName 'Fixture Group' -Configuration $realConfig -AllowRealRead
$countsAfterFixtureRead = & $groupCoreModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Group real autorizado retorna fixture" -Condition ($fixtureGroupRead.Success -and $fixtureGroupRead.QueryStatus -eq 'Found')
Test-Result -Name "Group real autorizado usou stubs contados" -Condition ($countsAfterFixtureRead.GetADGroup -eq 1 -and $countsAfterFixtureRead.GetADGroupMember -eq 1 -and $countsAfterFixtureRead.ImportModule -eq 1)
$whatIfConflict = Get-GroupADInfo -GroupName 'Fixture Group' -Configuration $config -AllowRealRead -WhatIf
$countsAfterWhatIfConflict = & $groupCoreModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "WhatIf conflitante falha antes de fronteiras externas" -Condition (-not $whatIfConflict.Success -and (($countsAfterWhatIfConflict.Values | Measure-Object -Sum).Sum -eq ($countsAfterFixtureRead.Values | Measure-Object -Sum).Sum))
& $groupCoreModule { $script:GroupFixtureMode='Error' }
$groupErrorFixture = Get-GroupADInfo -GroupName 'Fixture Group' -Configuration $realConfig -AllowRealRead
Test-Result -Name "Erro AD fixture preserva estado Error" -Condition (-not $groupErrorFixture.Success -and $groupErrorFixture.QueryStatus -eq 'Error')
& $groupCoreModule { $script:GroupFixtureMode='Null' }
$groupNullFixture = Get-GroupADInfo -GroupName 'Fixture Group' -Configuration $realConfig -AllowRealRead
Test-Result -Name "Resultado nulo normal distingue NotFound" -Condition (-not $groupNullFixture.Success -and $groupNullFixture.QueryStatus -eq 'NotFound')
& $groupCoreModule { $script:GroupFixtureMode='Success' }

# ---------------------------------------------------------
# TESTE 3 - SimulationMode
# ---------------------------------------------------------

Test-Result `
    -Name "Configuration está em SimulationMode" `
    -Condition ([bool]$config.SimulationMode -eq $true)

# ---------------------------------------------------------
# TESTE 4 - Grupo TI-Suporte
# ---------------------------------------------------------

$result = Get-GroupADInfo `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Get-GroupADInfo retorna sucesso para TI-Suporte" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 5 - SimulationMode no resultado
# ---------------------------------------------------------

Test-Result `
    -Name "Get-GroupADInfo informa SimulationMode" `
    -Condition ($result.SimulationMode -eq $true)

# ---------------------------------------------------------
# TESTE 6 - Nome
# ---------------------------------------------------------

Test-Result `
    -Name "Nome do grupo é TI-Suporte" `
    -Condition ($result.Data.Identity.Name -eq "TI-Suporte")

# ---------------------------------------------------------
# TESTE 7 - Description
# ---------------------------------------------------------

Test-Result `
    -Name "Descrição do grupo foi carregada" `
    -Condition ($result.Data.Description -eq "Grupo de suporte de TI")

# ---------------------------------------------------------
# TESTE 8 - Scope
# ---------------------------------------------------------

Test-Result `
    -Name "Scope padrão é Global" `
    -Condition ($result.Data.Identity.GroupScope -eq "Global")

# ---------------------------------------------------------
# TESTE 9 - Category
# ---------------------------------------------------------

Test-Result `
    -Name "Category padrão é Security" `
    -Condition ($result.Data.Identity.GroupCategory -eq "Security")

# ---------------------------------------------------------
# TESTE 10 - Exists
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Suporte existe" `
    -Condition ($result.Data.Exists -eq $true)

# ---------------------------------------------------------
# TESTE 11 - MemberCount
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Suporte possui 1 membro" `
    -Condition ($result.Data.MemberCount -eq 1)

# ---------------------------------------------------------
# TESTE 12 - Membros
# ---------------------------------------------------------

$result = Get-GroupMembers `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Get-GroupMembers retorna sucesso" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 13 - Quantidade
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Suporte possui 1 membro na consulta" `
    -Condition (@($result.Data).Count -eq 1)

# ---------------------------------------------------------
# TESTE 14 - Maria Santos
# ---------------------------------------------------------

Test-Result `
    -Name "maria.santos está em TI-Suporte" `
    -Condition ($result.Data[0].SamAccountName -eq "maria.santos")

# ---------------------------------------------------------
# TESTE 15 - ObjectClass
# ---------------------------------------------------------

Test-Result `
    -Name "Membro possui ObjectClass user" `
    -Condition ($result.Data[0].ObjectClass -eq "user")

# ---------------------------------------------------------
# TESTE 16 - Membership verdadeiro
# ---------------------------------------------------------

$result = Get-GroupMembership `
    -GroupName "TI-Suporte" `
    -SamAccountName "maria.santos" `
    -Configuration $config

Test-Result `
    -Name "maria.santos é membro de TI-Suporte" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.IsMember -eq $true
    )

# ---------------------------------------------------------
# TESTE 17 - Membership falso
# ---------------------------------------------------------

$result = Get-GroupMembership `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "joao.silva não é membro de TI-Suporte" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.IsMember -eq $false
    )

# ---------------------------------------------------------
# TESTE 18 - Grupo TI-Infraestrutura
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "TI-Infraestrutura" `
    -Configuration $config

Test-Result `
    -Name "Inventário de TI-Infraestrutura retorna sucesso" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 19 - Carlos Oliveira
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Infraestrutura possui carlos.oliveira" `
    -Condition (
        @($result.Data.Members).Count -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "carlos.oliveira"
    )

# ---------------------------------------------------------
# TESTE 20 - Administradores
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "Administradores" `
    -Configuration $config

Test-Result `
    -Name "Inventário de Administradores retorna sucesso" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 21 - João Silva
# ---------------------------------------------------------

Test-Result `
    -Name "Administradores possui joao.silva" `
    -Condition (
        @($result.Data.Members).Count -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "joao.silva"
    )

# ---------------------------------------------------------
# TESTE 22 - Grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupADInfo `
    -GroupName "Grupo-Inexistente" `
    -Configuration $config

Test-Result `
    -Name "Grupo inexistente retorna falha controlada" `
    -Condition (
        $result.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($result.Error)
    )

# ---------------------------------------------------------
# TESTE 23 - Membros de grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupMembers `
    -GroupName "Grupo-Inexistente" `
    -Configuration $config

Test-Result `
    -Name "Consulta de membros de grupo inexistente falha controladamente" `
    -Condition (
        $result.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($result.Error)
    )

# ---------------------------------------------------------
# TESTE 24 - Membership de grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupMembership `
    -GroupName "Grupo-Inexistente" `
    -SamAccountName "maria.santos" `
    -Configuration $config

Test-Result `
    -Name "Membership de grupo inexistente falha controladamente" `
    -Condition (
        $result.Success -eq $false
    )

# ---------------------------------------------------------
# TESTE 25 - Inventário de grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "Grupo-Inexistente" `
    -Configuration $config

Test-Result `
    -Name "Inventário de grupo inexistente falha controladamente" `
    -Condition (
        $result.Success -eq $false
    )

# ---------------------------------------------------------
# TESTE 26 - Modelo de erro
# ---------------------------------------------------------

Test-Result `
    -Name "Resultado de erro possui campo Error" `
    -Condition (
        $null -ne $result.PSObject.Properties["Error"]
    )

# ---------------------------------------------------------
# TESTE 27 - Modelo de sucesso
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Resultado de sucesso possui campo Data" `
    -Condition (
        $null -ne $result.PSObject.Properties["Data"]
    )

# ---------------------------------------------------------
# TESTE 28 - Inventário consolidado
# ---------------------------------------------------------

Test-Result `
    -Name "Inventário possui Identity" `
    -Condition (
        $null -ne $result.Data.PSObject.Properties["Identity"]
    )

# ---------------------------------------------------------
# TESTE 29 - Inventário possui Members
# ---------------------------------------------------------

Test-Result `
    -Name "Inventário possui Members" `
    -Condition (
        $null -ne $result.Data.PSObject.Properties["Members"]
    )

# ---------------------------------------------------------
# TESTE 30 - Inventário possui MemberCount
# ---------------------------------------------------------

Test-Result `
    -Name "Inventário possui MemberCount" `
    -Condition (
        $result.Data.MemberCount -eq 1
    )

# ---------------------------------------------------------
# RESUMO
# ---------------------------------------------------------

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "              RESULTADO FINAL" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host "Testes aprovados : $testsPassed" -ForegroundColor Green
Write-Host "Testes falhos    : $testsFailed" -ForegroundColor Red
Write-Host "Total            : $($testsPassed + $testsFailed)"

Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}
