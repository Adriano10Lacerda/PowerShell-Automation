#Requires -Version 5.1

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$global:PSModuleAutoLoadingPreference = 'None'
Write-Output 'HARNESS_START:GROUP_MANAGEMENT_V1'

if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) {
    throw "ActiveDirectory já está carregado neste processo; o harness não continuará."
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$modulePath = Join-Path `
    $scriptRoot `
    "Group-Management.psm1"

$configPath = Join-Path `
    (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptRoot))) `
    "06-AD-Group-Management\Group-Configuration.json"

$auditPath = Join-Path `
    (Split-Path -Parent (Split-Path -Parent $scriptRoot)) `
    "Audit\Audit-Functions.psm1"

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
Write-Host " TESTES - GROUP MANAGEMENT + AUDIT V2" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------
# ESTRUTURA
# ---------------------------------------------------------

Test-Result `
    -Name "Group-Management.psm1 existe" `
    -Condition (Test-Path -LiteralPath $modulePath)

Test-Result `
    -Name "Audit-Functions.psm1 existe" `
    -Condition (Test-Path -LiteralPath $auditPath)

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Group-Management.psm1 não encontrado."
}

if (-not (Test-Path -LiteralPath $auditPath)) {
    throw "Audit-Functions.psm1 não encontrado."
}

Import-Module $modulePath -Force -ErrorAction Stop
Import-Module $auditPath -Force -ErrorAction Stop

$managementModules = @(Get-Module | Where-Object { $_.Path -eq [System.IO.Path]::GetFullPath($modulePath) })
$managementModule = if ($managementModules.Count -eq 1) { $managementModules[0] } else { $null }
$groupCorePath = Join-Path $scriptRoot "..\Group-Functions.psm1"
$expectedGroupCorePath = [System.IO.Path]::GetFullPath($groupCorePath)
if ($null -eq $managementModule) { throw "Esperada uma instância Group Management; encontradas $($managementModules.Count)." }
$groupCoreModule = & $managementModule { (Get-Command Get-GroupInventory -CommandType Function -ErrorAction Stop).Module }
if ($null -eq $groupCoreModule -or $groupCoreModule.Path -ne $expectedGroupCorePath) {
    throw "Get-GroupInventory não resolve para a instância esperada do Group Core."
}
& $managementModule {
    $script:ExternalCallCounts = @{ GetModule=0; ImportModule=0; GetADUser=0; AddADGroupMember=0; RemoveADGroupMember=0 }
    $script:ADUserFixtureMode = 'Found'
    $script:ShouldProcessDecision = $true
    Set-Item Function:\script:Invoke-GroupManagementShouldProcess { param($Cmdlet,$Target,$Action); return $script:ShouldProcessDecision } -Force
    Set-Item Function:\script:Get-Module { param([string]$Name,[switch]$ListAvailable); if ($Name -ne 'ActiveDirectory') { throw "Get-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.GetModule++; [PSCustomObject]@{Name='ActiveDirectory'} } -Force
    Set-Item Function:\script:Import-Module { param([string]$Name,[string]$ErrorAction); if ($Name -ne 'ActiveDirectory') { throw "Import-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.ImportModule++ } -Force
    Set-Item Function:\script:Get-ADUser { param([string]$Identity,[string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.GetADUser++; if ($script:ADUserFixtureMode -eq 'Error') { throw 'Fixture AD user failure' }; if ($script:ADUserFixtureMode -eq 'Null') { return $null }; [PSCustomObject]@{SamAccountName='joao.silva'} } -Force
    Set-Item Function:\script:Add-ADGroupMember { param([string]$Identity,[string]$Members,[string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.AddADGroupMember++ } -Force
    Set-Item Function:\script:Remove-ADGroupMember { param([string]$Identity,[string]$Members,[string]$Server,[switch]$Confirm,[string]$ErrorAction); $script:ExternalCallCounts.RemoveADGroupMember++ } -Force
}
& $groupCoreModule {
    $script:ExternalCallCounts = @{ GetModule=0; ImportModule=0; GetADDomain=0; GetADGroup=0; GetADGroupMember=0 }
    Set-Item Function:\script:Get-Module { param([string]$Name,[switch]$ListAvailable); if ($Name -ne 'ActiveDirectory') { throw "Get-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.GetModule++; [PSCustomObject]@{Name='ActiveDirectory'} } -Force
    Set-Item Function:\script:Import-Module { param([string]$Name,[string]$ErrorAction); if ($Name -ne 'ActiveDirectory') { throw "Import-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.ImportModule++ } -Force
    Set-Item Function:\script:Get-ADDomain { param([string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.GetADDomain++; [PSCustomObject]@{DNSRoot='fixture.invalid'} } -Force
    Set-Item Function:\script:Get-ADGroup { param([string]$Identity,[string]$Server,[string[]]$Properties,[string]$ErrorAction); $script:ExternalCallCounts.GetADGroup++; [PSCustomObject]@{Name='TI-Suporte';SamAccountName='TI-Suporte';Description='Grupo de suporte de TI';GroupCategory='Security';GroupScope='Global';DistinguishedName='CN=TI-Suporte'} } -Force
    Set-Item Function:\script:Get-ADGroupMember { param($Identity,[string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.GetADGroupMember++; @([PSCustomObject]@{SamAccountName='maria.santos';Name='Maria Santos';objectClass='user'}) } -Force
}

$groupManagementStubResolution = & $managementModule {
    [PSCustomObject]@{
        Loader = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
        ModuleLookup = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
        ADUser = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).CommandType
        LoaderModule = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Module
        ModuleLookupModule = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Module
        ADUserModule = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).Module
        AddModule = (Get-Command Add-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).Module
        RemoveModule = (Get-Command Remove-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).Module
        LoaderIdentity = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.ImportModule'
        ModuleLookupIdentity = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetModule'
        ADUserIdentity = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetADUser'
        AddIdentity = (Get-Command Add-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.AddADGroupMember'
        RemoveIdentity = (Get-Command Remove-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.RemoveADGroupMember'
    }
}
$groupCoreStubResolution = & $groupCoreModule {
    [PSCustomObject]@{
        Loader = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
        ModuleLookup = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
        ADGroup = (Get-Command Get-ADGroup -CommandType Function -ErrorAction SilentlyContinue).CommandType
        ADGroupMember = (Get-Command Get-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).CommandType
        ADDomain = (Get-Command Get-ADDomain -CommandType Function -ErrorAction SilentlyContinue).CommandType
        LoaderModule = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Module
        ModuleLookupModule = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Module
        ADGroupModule = (Get-Command Get-ADGroup -CommandType Function -ErrorAction SilentlyContinue).Module
        ADGroupMemberModule = (Get-Command Get-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).Module
        ADDomainModule = (Get-Command Get-ADDomain -CommandType Function -ErrorAction SilentlyContinue).Module
        LoaderIdentity = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.ImportModule'
        ModuleLookupIdentity = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetModule'
        ADGroupIdentity = (Get-Command Get-ADGroup -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetADGroup'
        ADGroupMemberIdentity = (Get-Command Get-ADGroupMember -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetADGroupMember'
        ADDomainIdentity = (Get-Command Get-ADDomain -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetADDomain'
    }
}
if ($groupManagementStubResolution.Loader -ne 'Function' -or $groupManagementStubResolution.ModuleLookup -ne 'Function' -or $groupManagementStubResolution.ADUser -ne 'Function' -or
    $groupCoreStubResolution.Loader -ne 'Function' -or $groupCoreStubResolution.ModuleLookup -ne 'Function' -or $groupCoreStubResolution.ADGroup -ne 'Function' -or
    $groupCoreStubResolution.ADGroupMember -ne 'Function' -or $groupCoreStubResolution.ADDomain -ne 'Function' -or
    $groupManagementStubResolution.LoaderModule -ne $managementModule -or $groupManagementStubResolution.ModuleLookupModule -ne $managementModule -or
    $groupManagementStubResolution.ADUserModule -ne $managementModule -or $groupManagementStubResolution.AddModule -ne $managementModule -or
    $groupManagementStubResolution.RemoveModule -ne $managementModule -or
    $groupCoreStubResolution.LoaderModule -ne $groupCoreModule -or $groupCoreStubResolution.ModuleLookupModule -ne $groupCoreModule -or
    $groupCoreStubResolution.ADGroupModule -ne $groupCoreModule -or $groupCoreStubResolution.ADGroupMemberModule -ne $groupCoreModule -or
    $groupCoreStubResolution.ADDomainModule -ne $groupCoreModule -or
    -not $groupManagementStubResolution.LoaderIdentity -or -not $groupManagementStubResolution.ModuleLookupIdentity -or
    -not $groupManagementStubResolution.ADUserIdentity -or -not $groupManagementStubResolution.AddIdentity -or -not $groupManagementStubResolution.RemoveIdentity -or
    -not $groupCoreStubResolution.LoaderIdentity -or -not $groupCoreStubResolution.ModuleLookupIdentity -or
    -not $groupCoreStubResolution.ADGroupIdentity -or -not $groupCoreStubResolution.ADGroupMemberIdentity -or -not $groupCoreStubResolution.ADDomainIdentity) {
    throw "Resolução incompleta dos stubs nos SessionStates de Group Management/Core."
}

$config = [PSCustomObject]@{
    SimulationMode = $true
    ActiveDirectory = [PSCustomObject]@{ DomainController = 'fixture.invalid' }
    Group = [PSCustomObject]@{ DefaultCategory='Security'; DefaultScope='Global'; RequireDescription=$true }
    Simulation = [PSCustomObject]@{
        ExistingGroups = @(
            [PSCustomObject]@{ Name='TI-Suporte'; Description='Grupo de suporte de TI'; Members=@('maria.santos') },
            [PSCustomObject]@{ Name='TI-Infraestrutura'; Description='Grupo de infraestrutura'; Members=@('carlos.oliveira') },
            [PSCustomObject]@{ Name='Administradores'; Description='Administradores'; Members=@('joao.silva') }
        )
        ExistingUsers = @('maria.santos','joao.silva','carlos.oliveira')
    }
}

# ---------------------------------------------------------
# CONFIGURAÇÃO
# ---------------------------------------------------------

Test-Result `
    -Name "Configuration está em SimulationMode" `
    -Condition ($config.SimulationMode -eq $true)

# ---------------------------------------------------------
# AUDIT CORE
# ---------------------------------------------------------

$audit = New-AuditRecord `
    -Action "GroupTest" `
    -SamAccountName "joao.silva" `
    -Result "Success" `
    -SimulationMode $true `
    -Changed $false

Test-Result `
    -Name "Audit Core cria registro" `
    -Condition ($audit.Success -eq $true)

Test-Result `
    -Name "Audit possui Timestamp" `
    -Condition ($null -ne $audit.Data.Timestamp)

Test-Result `
    -Name "Audit possui Action" `
    -Condition ($audit.Data.Action -eq "GroupTest")

Test-Result `
    -Name "Audit possui SamAccountName" `
    -Condition ($audit.Data.SamAccountName -eq "joao.silva")

$validation = Test-AuditRecord `
    -Record $audit.Data

Test-Result `
    -Name "Registro de Audit é validado" `
    -Condition ($validation.Success -eq $true -and $validation.Data -eq $true)

# ---------------------------------------------------------
# CONSULTA
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Consulta de TI-Suporte retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Consulta retorna SimulationMode" `
    -Condition ($result.SimulationMode -eq $true)

Test-Result `
    -Name "TI-Suporte inicia com 1 membro" `
    -Condition ($result.Data.MemberCount -eq 1)

# ---------------------------------------------------------
# PREVIEW ADD
# ---------------------------------------------------------

$result = Get-GroupManagementPreview `
    -Action "AddMember" `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "Preview de adição retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Preview exige confirmação" `
    -Condition ($result.Data.RequiresConfirm -eq $true)

# ---------------------------------------------------------
# EXECUTE ADD + AUDIT
# ---------------------------------------------------------

$result = Invoke-GroupAddMember `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config `
    -Execute

Test-Result `
    -Name "Adição simulada retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Adição informa Changed=true" `
    -Condition ($result.Changed -eq $true)

Test-Result `
    -Name "Adição permanece em SimulationMode" `
    -Condition ($result.SimulationMode -eq $true)

Test-Result `
    -Name "Adição retorna Audit" `
    -Condition ($null -ne $result.Audit)

Test-Result `
    -Name "Audit da adição possui Action AddMember" `
    -Condition ($result.Audit.Action -eq "AddMember")

Test-Result `
    -Name "Audit da adição possui usuário correto" `
    -Condition ($result.Audit.SamAccountName -eq "joao.silva")

Test-Result `
    -Name "Audit da adição possui Result Success" `
    -Condition ($result.Audit.Result -eq "Success")

Test-Result `
    -Name "Audit da adição informa SimulationMode=true" `
    -Condition ($result.Audit.SimulationMode -eq $true)

Test-Result `
    -Name "Audit da adição informa Changed=true" `
    -Condition ($result.Audit.Changed -eq $true)

$validation = Test-AuditRecord `
    -Record $result.Audit

Test-Result `
    -Name "Audit da adição passa na validação" `
    -Condition ($validation.Success -eq $true -and $validation.Data -eq $true)

# ---------------------------------------------------------
# PERSISTÊNCIA
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Membro adicionado permanece no inventário" `
    -Condition (
        $result.Data.MemberCount -eq 2 -and
        @($result.Data.Members | Where-Object {
            $_.SamAccountName -eq "joao.silva"
        }).Count -eq 1
    )

# ---------------------------------------------------------
# DUPLICIDADE
# ---------------------------------------------------------

$result = Get-GroupManagementPreview `
    -Action "AddMember" `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "Adição duplicada é bloqueada" `
    -Condition ($result.Success -eq $false)

# ---------------------------------------------------------
# PREVIEW REMOVE
# ---------------------------------------------------------

$result = Get-GroupManagementPreview `
    -Action "RemoveMember" `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "Preview de remoção retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Preview de remoção exige confirmação" `
    -Condition ($result.Data.RequiresConfirm -eq $true)

# ---------------------------------------------------------
# EXECUTE REMOVE + AUDIT
# ---------------------------------------------------------

$result = Invoke-GroupRemoveMember `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config `
    -Execute

Test-Result `
    -Name "Remoção simulada retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Remoção informa Changed=true" `
    -Condition ($result.Changed -eq $true)

Test-Result `
    -Name "Remoção retorna Audit" `
    -Condition ($null -ne $result.Audit)

Test-Result `
    -Name "Audit da remoção possui Action RemoveMember" `
    -Condition ($result.Audit.Action -eq "RemoveMember")

Test-Result `
    -Name "Audit da remoção possui usuário correto" `
    -Condition ($result.Audit.SamAccountName -eq "joao.silva")

Test-Result `
    -Name "Audit da remoção possui Result Success" `
    -Condition ($result.Audit.Result -eq "Success")

Test-Result `
    -Name "Audit da remoção informa SimulationMode=true" `
    -Condition ($result.Audit.SimulationMode -eq $true)

Test-Result `
    -Name "Audit da remoção informa Changed=true" `
    -Condition ($result.Audit.Changed -eq $true)

$validation = Test-AuditRecord `
    -Record $result.Audit

Test-Result `
    -Name "Audit da remoção passa na validação" `
    -Condition ($validation.Success -eq $true -and $validation.Data -eq $true)

# ---------------------------------------------------------
# PERSISTÊNCIA DA REMOÇÃO
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Membro removido não aparece mais" `
    -Condition (
        $result.Data.MemberCount -eq 1 -and
        @($result.Data.Members | Where-Object {
            $_.SamAccountName -eq "joao.silva"
        }).Count -eq 0
    )

# ---------------------------------------------------------
# PROTEÇÃO DE AUDIT
# ---------------------------------------------------------

$badRecord = [PSCustomObject]@{
    Timestamp      = Get-Date
    Operator       = "Test"
    Action         = "Invalid"
    SamAccountName = "joao.silva"
    Result         = "Failed"
    SimulationMode = $true
    Changed        = $false
    Password       = "NAO-DEVE-EXISTIR"
}

$validation = Test-AuditRecord `
    -Record $badRecord

Test-Result `
    -Name "Audit rejeita registro contendo Password" `
    -Condition ($validation.Success -eq $false)

# ---------------------------------------------------------
# OUTROS GRUPOS
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Infraestrutura" `
    -Configuration $config

Test-Result `
    -Name "TI-Infraestrutura continua íntegro" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.MemberCount -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "carlos.oliveira"
    )

$result = Get-GroupManagement `
    -GroupName "Administradores" `
    -Configuration $config

Test-Result `
    -Name "Administradores continua íntegro" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.MemberCount -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "joao.silva"
    )

# ---------------------------------------------------------
# ISOLAMENTO FAIL-CLOSED
# ---------------------------------------------------------

$realConfig = [PSCustomObject]@{
    SimulationMode=$false
    ActiveDirectory=[PSCustomObject]@{DomainController='fixture.invalid'}
    Group=[PSCustomObject]@{DefaultCategory='Security';DefaultScope='Global';RequireDescription=$true}
    Simulation=[PSCustomObject]@{ExistingGroups=@();ExistingUsers=@()}
}
$groupCountsBefore = & $groupCoreModule { @{} + $script:ExternalCallCounts }
$managementCountsBefore = & $managementModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Caminhos simulados anteriores não chamaram fronteiras" -Condition ((($groupCountsBefore.Values | Measure-Object -Sum).Sum -eq 0) -and (($managementCountsBefore.Values | Measure-Object -Sum).Sum -eq 0))
$groupManagementStubResolution = & $managementModule { (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).CommandType }
$groupCoreStubResolution = & $groupCoreModule { (Get-Command Get-ADGroup -CommandType Function -ErrorAction SilentlyContinue).CommandType }
Test-Result -Name "Management e Core aninhado resolvem stubs AD" -Condition ($groupManagementStubResolution -eq 'Function' -and $groupCoreStubResolution -eq 'Function')
$blockedPreview = Get-GroupManagementPreview -Action AddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig
$blockedAdd = Invoke-GroupAddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -Execute -AllowRealOperation -Confirm:$false
$groupCountsBlocked = & $groupCoreModule { @{} + $script:ExternalCallCounts }
$managementCountsBlocked = & $managementModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Preview Group sem autorização de leitura falha fechada" -Condition (-not $blockedPreview.Success -and $blockedPreview.Error -match 'AllowRealRead')
Test-Result -Name "Execute e AllowRealOperation não autorizam mutação" -Condition (-not $blockedAdd.Success -and $blockedAdd.Error -match 'AllowRealRead')
Test-Result -Name "Ausência de autorização mantém fronteiras zeradas" -Condition ((($groupCountsBefore.Values | Measure-Object -Sum).Sum -eq ($groupCountsBlocked.Values | Measure-Object -Sum).Sum) -and (($managementCountsBefore.Values | Measure-Object -Sum).Sum -eq ($managementCountsBlocked.Values | Measure-Object -Sum).Sum))
$readOnlyGroupWrite = Invoke-GroupAddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -Execute -AllowRealRead -Confirm:$false
$writeOnlyGroupAction = Invoke-GroupAddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -Execute -AllowRealWrite -Confirm:$false
$countsAfterSplit = & $managementModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "AllowRealRead não autoriza escrita Group" -Condition (-not $readOnlyGroupWrite.Success -and $readOnlyGroupWrite.Error -match 'AllowRealWrite')
Test-Result -Name "AllowRealWrite não autoriza leitura Group" -Condition (-not $writeOnlyGroupAction.Success -and $writeOnlyGroupAction.Error -match 'AllowRealRead')
Test-Result -Name "Autorizações Group independentes falham antes das fronteiras" -Condition (($countsAfterSplit.Values | Measure-Object -Sum).Sum -eq ($managementCountsBlocked.Values | Measure-Object -Sum).Sum)

$whatIfGroupWrite = Invoke-GroupAddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -Execute -AllowRealRead -AllowRealWrite -WhatIf
$groupCountsWhatIf = & $groupCoreModule { @{} + $script:ExternalCallCounts }
$managementCountsWhatIf = & $managementModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Group WhatIf é Preview sem cancelamento" -Condition ($whatIfGroupWrite.Mode -eq 'Preview' -and $whatIfGroupWrite.Cancelled -eq $false)
Test-Result -Name "Group WhatIf não alcança fronteiras" -Condition ((($groupCountsWhatIf.Values | Measure-Object -Sum).Sum -eq ($groupCountsBlocked.Values | Measure-Object -Sum).Sum) -and (($managementCountsWhatIf.Values | Measure-Object -Sum).Sum -eq ($managementCountsBlocked.Values | Measure-Object -Sum).Sum))
$conflictingGroupWhatIf = Invoke-GroupAddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration ([PSCustomObject]@{SimulationMode=$true}) -Execute -AllowRealRead -AllowRealWrite -WhatIf
$countsAfterConflictingGroupWhatIf = & $managementModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Group rejeita autorizações conflitantes antes de WhatIf" -Condition (-not $conflictingGroupWhatIf.Success -and $conflictingGroupWhatIf.Error -match 'conflit' -and (($countsAfterConflictingGroupWhatIf.Values | Measure-Object -Sum).Sum -eq ($managementCountsWhatIf.Values | Measure-Object -Sum).Sum))

& $managementModule { $script:ShouldProcessDecision = $false }
$countsBeforeDecline = & $managementModule { @{} + $script:ExternalCallCounts }
$declinedGroupWrite = Invoke-GroupAddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -Execute -AllowRealRead -AllowRealWrite -Confirm:$false
$countsAfterDecline = & $managementModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Recusa ShouldProcess é cancelamento determinístico" -Condition ($declinedGroupWrite.Cancelled -and $declinedGroupWrite.Mode -eq 'Preview')
Test-Result -Name "Recusa ShouldProcess ocorre antes das leituras AD" -Condition (($countsBeforeDecline.Values | Measure-Object -Sum).Sum -eq ($countsAfterDecline.Values | Measure-Object -Sum).Sum)
& $managementModule { $script:ShouldProcessDecision = $true }

$stubAdd = Invoke-GroupAddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -Execute -AllowRealRead -AllowRealWrite -Confirm:$false
$stubRemove = Invoke-GroupRemoveMember -GroupName 'TI-Suporte' -SamAccountName 'maria.santos' -Configuration $realConfig -Execute -AllowRealRead -AllowRealWrite -Confirm:$false
$groupCountsAuthorized = & $groupCoreModule { @{} + $script:ExternalCallCounts }
$managementCountsAuthorized = & $managementModule { @{} + $script:ExternalCallCounts }
Test-Result -Name "Inclusão autorizada chama somente o stub" -Condition ($stubAdd.Success -and $managementCountsAuthorized.AddADGroupMember -eq 1)
Test-Result -Name "Remoção autorizada chama somente o stub" -Condition ($stubRemove.Success -and $managementCountsAuthorized.RemoveADGroupMember -eq 1)
Test-Result -Name "Leituras autorizadas passaram por stubs contados" -Condition ($groupCountsAuthorized.GetADGroup -gt 0 -and $groupCountsAuthorized.GetADGroupMember -gt 0 -and $managementCountsAuthorized.GetADUser -gt 0)
& $managementModule { $script:ADUserFixtureMode='Null' }
$notFoundPreview = Get-GroupManagementPreview -Action AddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -AllowRealRead
Test-Result -Name "Resultado nulo concluído é NotFound" -Condition (-not $notFoundPreview.Success -and $notFoundPreview.QueryStatus -eq 'NotFound')
& $managementModule { $script:ADUserFixtureMode='Error' }
$errorPreview = Get-GroupManagementPreview -Action AddMember -GroupName 'TI-Suporte' -SamAccountName 'joao.silva' -Configuration $realConfig -AllowRealRead
& $managementModule { $script:ADUserFixtureMode='Found' }
Test-Result -Name "Erro de consulta Group permanece Error" -Condition (-not $errorPreview.Success -and $errorPreview.QueryStatus -eq 'Error' -and $errorPreview.Error -match 'Fixture AD user failure')

# ---------------------------------------------------------
# REGRESSÃO - COLEÇÕES DE MEMBROS EM SIMULATION MODE
# ---------------------------------------------------------

$emptyGroupFixture = [PSCustomObject]@{ Name='Fixture-Empty'; Description='Grupo fictício vazio'; Members=@() }
$singleMemberFixture = [PSCustomObject]@{ Name='Fixture-Single'; Description='Grupo fictício com um membro'; Members=@('fixture.user') }
$multipleMemberFixture = [PSCustomObject]@{ Name='Fixture-Multiple'; Description='Grupo fictício com vários membros'; Members=@('fixture.user','fixture.other') }
$edgeConfig = [PSCustomObject]@{
    SimulationMode = $true
    ActiveDirectory = [PSCustomObject]@{ DomainController='fixture.invalid' }
    Group = [PSCustomObject]@{ DefaultCategory='Security'; DefaultScope='Global'; RequireDescription=$true }
    Simulation = [PSCustomObject]@{
        ExistingGroups = @($emptyGroupFixture,$singleMemberFixture,$multipleMemberFixture)
        ExistingUsers = @('fixture.user','fixture.other')
    }
}

$externalCountsBeforeSimulationRegression = [PSCustomObject]@{
    Core = & $groupCoreModule { @{} + $script:ExternalCallCounts }
    Management = & $managementModule { @{} + $script:ExternalCallCounts }
}

$addToEmpty = Invoke-GroupAddMember -GroupName 'Fixture-Empty' -SamAccountName 'fixture.user' -Configuration $edgeConfig -Execute
Test-Result -Name "Adição simulada a grupo vazio funciona" -Condition ($addToEmpty.Success -and $addToEmpty.SimulationMode -and @($emptyGroupFixture.Members).Count -eq 1 -and $emptyGroupFixture.Members[0] -eq 'fixture.user')
Test-Result -Name "Adição simulada registra auditoria correta" -Condition ($null -ne $addToEmpty.Audit -and $addToEmpty.Audit.Action -eq 'AddMember' -and $addToEmpty.Audit.SimulationMode -and $addToEmpty.Audit.Changed)

$duplicateAdd = Invoke-GroupAddMember -GroupName 'Fixture-Empty' -SamAccountName 'fixture.user' -Configuration $edgeConfig -Execute
Test-Result -Name "Adição simulada duplicada não cria duplicação" -Condition (-not $duplicateAdd.Success -and @($emptyGroupFixture.Members).Count -eq 1 -and @($emptyGroupFixture.Members | Where-Object { $_ -eq 'fixture.user' }).Count -eq 1)

$removeLastMember = Invoke-GroupRemoveMember -GroupName 'Fixture-Single' -SamAccountName 'fixture.user' -Configuration $edgeConfig -Execute
Test-Result -Name "Remoção simulada do último membro funciona" -Condition ($removeLastMember.Success -and $removeLastMember.SimulationMode -and $removeLastMember.Changed -and @($singleMemberFixture.Members).Count -eq 0 -and $null -ne $singleMemberFixture.Members)
Test-Result -Name "Remoção do último membro audita a alteração" -Condition ($null -ne $removeLastMember.Audit -and $removeLastMember.Audit.Action -eq 'RemoveMember' -and $removeLastMember.Audit.SimulationMode -and $removeLastMember.Audit.Changed)
$emptyAfterRemoval = Get-GroupManagementMembers -GroupName 'Fixture-Single' -Configuration $edgeConfig
Test-Result -Name "Grupo permanece consultável com zero membros" -Condition ($emptyAfterRemoval.Success -and @($emptyAfterRemoval.Data).Count -eq 0)

$removeOneOfSeveral = Invoke-GroupRemoveMember -GroupName 'Fixture-Multiple' -SamAccountName 'fixture.user' -Configuration $edgeConfig -Execute
Test-Result -Name "Remoção simulada preserva os demais membros" -Condition ($removeOneOfSeveral.Success -and @($multipleMemberFixture.Members).Count -eq 1 -and $multipleMemberFixture.Members[0] -eq 'fixture.other')

$membersBeforeMissingRemoval = @($multipleMemberFixture.Members)
$removeMissingMember = Invoke-GroupRemoveMember -GroupName 'Fixture-Multiple' -SamAccountName 'fixture.user' -Configuration $edgeConfig -Execute
Test-Result -Name "Remoção simulada de membro inexistente não altera o grupo" -Condition (-not $removeMissingMember.Success -and @($multipleMemberFixture.Members).Count -eq $membersBeforeMissingRemoval.Count -and $multipleMemberFixture.Members[0] -eq 'fixture.other')

$nullMembersRejected = & $managementModule {
    $fixtureGroup = [PSCustomObject]@{ Name='Fixture-Null'; Members=@('fixture.user') }
    try { Set-SimulationGroupMembers -Group $fixtureGroup -Members $null -ErrorAction Stop; return $false }
    catch { return $true }
}
Test-Result -Name "Set-SimulationGroupMembers continua rejeitando null" -Condition $nullMembersRejected

$externalCountsAfterSimulationRegression = [PSCustomObject]@{
    Core = & $groupCoreModule { @{} + $script:ExternalCallCounts }
    Management = & $managementModule { @{} + $script:ExternalCallCounts }
}
$simulationNoExternalCalls = $true
foreach ($scopeName in @('Core','Management')) {
    foreach ($counterName in $externalCountsBeforeSimulationRegression.$scopeName.Keys) {
        if ($externalCountsAfterSimulationRegression.$scopeName[$counterName] -ne $externalCountsBeforeSimulationRegression.$scopeName[$counterName]) { $simulationNoExternalCalls = $false }
    }
}
Test-Result -Name "Regressões SimulationMode não acionaram fronteiras externas" -Condition $simulationNoExternalCalls

# ---------------------------------------------------------
# RESULTADO
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
    Write-Output 'HARNESS_PASS:GROUP_MANAGEMENT_V1'
    exit 0
}
else {
    Write-Host "EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}
