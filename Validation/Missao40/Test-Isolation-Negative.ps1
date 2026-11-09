#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'Integration.Common.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $here 'Integration.Fixtures.psm1') -Force -ErrorAction Stop
Write-Output 'HARNESS_START:ISOLATION_NEGATIVE_SYNTHETIC'
Write-Output 'HARNESS_GATE:SYNTHETIC_ONLY_NO_PRODUCTION_IMPORT'
$root = Split-Path -Parent (Split-Path -Parent $here)
$state = New-AdminHarnessState -ProjectRoot $root
$checks = 0
function Assert-Throws { param([scriptblock]$Action,[string]$Name) $thrown=$false; try { & $Action } catch { $thrown=$true }; if (-not $thrown) { throw "NEGATIVE-TEST-FAILED:$Name" }; $script:checks++ }
$productionScenario = [pscustomobject]@{ ShouldProcess=$true }
$userProductionFixture = New-AdminScenarioFixture -Operation Unlock -ScenarioName StaticClosureOnly
$userGate = New-AdminProductionGateState -ProjectRoot $root -Domain User -Operation Unlock -Fixture $userProductionFixture -Scenario $productionScenario
if ($userGate.AllowedPaths.Count -ne 3 -or $userGate.StaticEvidence.Modules.Count -ne 3 -or $userGate.StaticEvidence.Scripts.Count -ne 2 -or @($userGate.StaticEvidence.ExternalImports | Where-Object Name -ne 'ActiveDirectory').Count -ne 0) { throw 'NEGATIVE-TEST-FAILED:user-static-closure-allowlist' }; $checks++
$groupProductionFixture = New-AdminScenarioFixture -Operation GroupAdd -ScenarioName StaticClosureOnly
$groupGate = New-AdminProductionGateState -ProjectRoot $root -Domain Group -Operation GroupAdd -Fixture $groupProductionFixture -Scenario $productionScenario
if ($groupGate.AllowedPaths.Count -ne 3 -or $groupGate.StaticEvidence.Modules.Count -ne 3 -or $groupGate.StaticEvidence.Scripts.Count -ne 2 -or @($groupGate.StaticEvidence.ExternalImports | Where-Object Name -ne 'ActiveDirectory').Count -ne 0) { throw 'NEGATIVE-TEST-FAILED:group-static-closure-allowlist' }; $checks++
$virtualSource = Join-Path $root 'Validation/Missao40/Virtual-Path-Probe.ps1'
$tokens = $null; $parseErrors = $null
$virtualAst = [System.Management.Automation.Language.Parser]::ParseInput('$dependencyPath = Join-Path $PSScriptRoot "Child.ps1"; . $dependencyPath',[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'NEGATIVE-TEST-FAILED:static-path-fixture-parse' }
$dotAst = $virtualAst.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot },$true)
$resolvedVirtualPath = Resolve-AdminStaticAstValue -Expression $dotAst.CommandElements[0] -RootAst $virtualAst -SourcePath $virtualSource -ProjectRoot $root
if ([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $virtualSource) 'Child.ps1')) -ne [IO.Path]::GetFullPath($resolvedVirtualPath)) { throw 'NEGATIVE-TEST-FAILED:static-dot-source-relative-resolution' }; $checks++
$dynamicAst = [System.Management.Automation.Language.Parser]::ParseInput('. $unassignedPath',[ref]$tokens,[ref]$parseErrors)
$dynamicDot = $dynamicAst.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot },$true)
Assert-Throws { Resolve-AdminStaticAstValue -Expression $dynamicDot.CommandElements[0] -RootAst $dynamicAst -SourcePath $virtualSource -ProjectRoot $root } 'dynamic-dot-source-rejected'
$cycleAst = [System.Management.Automation.Language.Parser]::ParseInput('$pathA = $pathB; $pathB = $pathA; . $pathA',[ref]$tokens,[ref]$parseErrors)
$cycleDot = $cycleAst.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot },$true)
Assert-Throws { Resolve-AdminStaticAstValue -Expression $cycleDot.CommandElements[0] -RootAst $cycleAst -SourcePath $virtualSource -ProjectRoot $root } 'static-path-variable-cycle-rejected'
Assert-Throws { Resolve-AdminAllowedPath -Path (Join-Path $root 'Core/*/Unexpected.psm1') -AllowedRoot $root } 'wildcard-path-rejected'
Assert-Throws { Resolve-AdminAllowedPath -Path '\\synthetic.invalid\share\unexpected.psm1' -AllowedRoot $root } 'network-path-rejected'
Assert-Throws { Resolve-AdminAllowedPath -Path (Join-Path $root 'Core/DefinitelyMissing.psm1') -AllowedRoot $root -RequireExisting } 'missing-dependency-rejected'
Assert-Throws { Invoke-AdminGuardedProductionImport -State $userGate -Name $groupGate.Paths.Management } 'production-import-outside-domain-allowlist'
if ($userGate.ImportLog.Count -ne 0 -or $userGate.ModuleInstances.Count -ne 0 -or $userGate.Counters.Unexpected -ne 1) { throw 'NEGATIVE-TEST-FAILED:unauthorized-production-import-blocked-before-loader' }; $checks++
Write-Output ('STATIC_CLOSURE_JSON:' + ([pscustomobject]@{
    UserModules=@($userGate.StaticEvidence.Modules); UserScripts=@($userGate.StaticEvidence.Scripts)
    UserAllowlist=@($userGate.AllowedPaths.Keys); UserExternalImports=@($userGate.StaticEvidence.ExternalImports)
    GroupModules=@($groupGate.StaticEvidence.Modules); GroupScripts=@($groupGate.StaticEvidence.Scripts)
    GroupAllowlist=@($groupGate.AllowedPaths.Keys); GroupExternalImports=@($groupGate.StaticEvidence.ExternalImports)
    UnauthorizedImportBlockedBeforeLoader=($userGate.ImportLog.Count -eq 0 -and $userGate.ModuleInstances.Count -eq 0)
    ProductionModulesLoaded=$false; ExternalCalls=0
} | ConvertTo-Json -Depth 6 -Compress))
$commonPath = [IO.Path]::GetFullPath((Join-Path $here 'Integration.Common.psm1'))
$commonModule = @(Get-Module | Where-Object { $_.Path -eq $commonPath })
if ($commonModule.Count -ne 1) { throw 'FAIL-CLOSED: módulo sintético Common não identificado univocamente.' }
$moduleStub = { [CmdletBinding()] param([string]$Identity) # INSTALL-STUB-SENTINEL
    if ($Identity -ne 'fixture.user') { throw 'FAIL-CLOSED: identity fixture inesperada.' }
    return 'INSTALL-STUB-SENTINEL'
}
$installed = Install-AdminModuleStub -Module $commonModule[0] -CommandName 'Invoke-SyntheticOnlyProbe' -Stub $moduleStub -Sentinel 'INSTALL-STUB-SENTINEL' -RequiredParameters @('Identity') -ExpectedModulePath $commonPath -ProjectRoot $root
$installedResult = & $commonModule[0] { param($identity) Invoke-SyntheticOnlyProbe -Identity $identity } 'fixture.user'
if ($installed.CommandType -ne 'Function' -or -not [object]::ReferenceEquals($installed.Module,$commonModule[0]) -or $installed.ModulePath -ne $commonPath -or $installedResult -ne 'INSTALL-STUB-SENTINEL') { throw 'NEGATIVE-TEST-FAILED:real-module-sessionstate-stub-install' }; $checks++
$mockPath = Join-Path $root 'Validation/Missao40/Synthetic/Fake.psm1'
[void](Register-AdminSyntheticModule -State $state -Name 'Synthetic.Fake' -Path $mockPath)
Assert-Throws { Assert-AdminImportAllowed -State $state -Path (Join-Path ([IO.Path]::GetTempPath()) 'untrusted.psm1') } 'path-outside-project'
Assert-Throws { Assert-AdminImportAllowed -State $state -Path (Join-Path $root 'Validation/Missao40/Synthetic/Unexpected.psm1') } 'unexpected-import'
$module = Register-AdminModuleInstance -State $state -Name 'Synthetic.Core' -Path $mockPath
Register-AdminSyntheticStub -State $state -Name 'Get-SentinelFixture' -Module $module -Parameters @('Identity') -Sentinel 'SYNTHETIC-STUB-SENTINEL' -Handler {
    param($s,$a)
    if ($a.Identity -ne 'fixture.user') { throw 'FAIL-CLOSED: argumento de fixture inesperado.' }
    $s.Counters.GetADUser++
    return 'SYNTHETIC-STUB-SENTINEL'
} | Out-Null
$sentinelStub = Assert-AdminSyntheticStub -State $state -Module $module -Name 'Get-SentinelFixture' -RequiredParameters @('Identity') -Sentinel 'SYNTHETIC-STUB-SENTINEL'
$sentinelResult = Invoke-AdminSyntheticCommand -State $state -Module $module -Name 'Get-SentinelFixture' -Arguments @{ Identity='fixture.user' }
if ($sentinelStub.CommandType -ne 'Function' -or $sentinelResult -ne 'SYNTHETIC-STUB-SENTINEL' -or $state.Counters.GetADUser -ne 1) { throw 'NEGATIVE-TEST-FAILED:synthetic-sentinel-or-counter' }; $checks++
Assert-Throws { Assert-AdminSyntheticStub -State $state -Module $module -Name 'Get-Fake' -RequiredParameters @('Identity') -Sentinel 'STUB-GET-1' } 'missing-stub'
Register-AdminSyntheticStub -State $state -Name 'Get-Fake' -Module $module -Parameters @('Wrong') -Sentinel 'STUB-GET-1' -Handler { param($s,$a) 'STUB-GET-1' } | Out-Null
Assert-Throws { Assert-AdminSyntheticStub -State $state -Module $module -Name 'Get-Fake' -RequiredParameters @('Identity') -Sentinel 'STUB-GET-1' } 'wrong-signature'
$replaced = Register-AdminModuleInstance -State $state -Name 'Synthetic.Core' -Path $mockPath
Assert-Throws { Assert-AdminModuleIdentity -Expected $module -Actual $replaced } 'instance-replaced'
$reloadPath = Join-Path $root 'Validation/Missao40/Synthetic/Reloadable.psm1'
[void](Register-AdminSyntheticModule -State $state -Name 'Synthetic.Reloadable' -Path $reloadPath)
$firstReload = Invoke-AdminSyntheticImport -State $state -Path $reloadPath -Instrument {
    param($s,$m)
    Register-AdminSyntheticStub -State $s -Name 'Get-ReloadFixture' -Module $m -Parameters @() -Sentinel 'RELOAD-STUB' -Handler { param($state,$arguments) 'RELOAD-STUB' } | Out-Null
    return $true
}
Register-AdminCapturedReference -State $state -CommandName 'Get-ReloadFixture' -Module $firstReload -Sentinel 'RELOAD-STUB' | Out-Null
Assert-Throws { Invoke-AdminSyntheticImport -State $state -Path $reloadPath -Force -Instrument {
    param($s,$m)
    Register-AdminSyntheticStub -State $s -Name 'Get-ReloadFixture' -Module $m -Parameters @() -Sentinel 'RELOAD-STUB' -Handler { param($state,$arguments) 'RELOAD-STUB' } | Out-Null
    return $true
} } 'reimport-stale-reference-blocked-before-return'
$currentReload = $state.ActiveModules[$reloadPath]
Assert-AdminSyntheticStub -State $state -Module $currentReload -Name 'Get-ReloadFixture' -RequiredParameters @() -Sentinel 'RELOAD-STUB' | Out-Null
if ($firstReload.InstanceId -eq $currentReload.InstanceId -or -not $state.ImportLog[$state.ImportLog.Count - 1].Force) { throw 'NEGATIVE-TEST-FAILED:force-reimport-generation-not-recorded' }
$checks++
$state.CapturedReferences.Clear()
$nestedPath = Join-Path $root 'Validation/Missao40/Synthetic/NestedCore.psm1'
$parentPath = Join-Path $root 'Validation/Missao40/Synthetic/ParentActions.psm1'
[void](Register-AdminSyntheticModule -State $state -Name 'Synthetic.NestedCore' -Path $nestedPath)
[void](Register-AdminSyntheticModule -State $state -Name 'Synthetic.ParentActions' -Path $parentPath)
$parentInstance = Invoke-AdminSyntheticImport -State $state -Path $parentPath -Force -NestedImports {
    param($s)
    $nestedModule = Invoke-AdminSyntheticImport -State $s -Path $nestedPath -Force -Instrument {
        param($innerState,$innerModule)
        Register-AdminSyntheticStub -State $innerState -Name 'Get-NestedFixture' -Module $innerModule -Parameters @() -Sentinel 'NESTED-STUB' -Handler { param($state,$arguments) 'NESTED-STUB' } | Out-Null
        return $true
    }
    return [pscustomobject]@{ Success=($null -ne $nestedModule) }
} -Instrument {
    param($s,$m)
    $nestedActive = $s.ActiveModules[$nestedPath]
    $null = Assert-AdminSyntheticStub -State $s -Module $nestedActive -Name 'Get-NestedFixture' -RequiredParameters @() -Sentinel 'NESTED-STUB'
    return $true
}
if ($parentInstance.Name -ne 'Synthetic.ParentActions' -or $state.ImportDepth -ne 0 -or @($state.ImportLog | Where-Object { $_.Depth -eq 2 }).Count -ne 1) { throw 'NEGATIVE-TEST-FAILED:nested-import-transaction' }; $checks++
$refModule = Register-AdminModuleInstance -State $state -Name 'Synthetic.Reference' -Path $mockPath
Register-AdminSyntheticStub -State $state -Name 'Get-Old' -Module $refModule -Parameters @() -Sentinel 'OLD-REF' -Handler { param($s,$a) 'OLD-REF' } | Out-Null
Register-AdminCapturedReference -State $state -CommandName 'Get-Old' -Module $refModule -Sentinel 'OLD-REF' | Out-Null
$state.Commands.Remove($refModule.InstanceId + '|Get-Old') | Out-Null
Assert-Throws { Assert-AdminCapturedReferencesCurrent -State $state } 'stale-reference'
$failPath = Join-Path $root 'Validation/Missao40/Synthetic/FailImport.psm1'
[void](Register-AdminSyntheticModule -State $state -Name 'Synthetic.Fail' -Path $failPath -FailImport)
Assert-Throws { Invoke-AdminSyntheticImport -State $state -Path $failPath -Instrument { $true } } 'import-failure'
$instrumentPath = Join-Path $root 'Validation/Missao40/Synthetic/FailInstrument.psm1'
[void](Register-AdminSyntheticModule -State $state -Name 'Synthetic.FailInstrument' -Path $instrumentPath -FailInstrumentation)
Assert-Throws { Invoke-AdminSyntheticImport -State $state -Path $instrumentPath -Instrument { $true } } 'instrumentation-failure'
$authFailure = New-AdminScenarioFixture -Operation Unlock -ScenarioName NoAuthorization
$blockedScenario = [pscustomobject]@{Operation='Unlock';SimulationMode=$false;Preview=$false;WhatIf=$false;Execute=$true;AllowRealRead=$false;AllowRealWrite=$false;WriteAuthorizationValid=$false;AuthorizationOperation='Unlock';ShouldProcess=$true;Cancelled=$false}
$readsBeforeBlocked = [int]$state.Counters.GetADUser
$blocked = Invoke-AdminSyntheticMutation -State $state -Fixture $authFailure.OperationResult -Scenario $blockedScenario -MutationCounter Unlock
if ($blocked.Status -ne 'Blocked' -or $state.Counters.Unlock -ne 0 -or $state.Counters.GetADUser -ne $readsBeforeBlocked) { throw 'NEGATIVE-TEST-FAILED:unauthorized-mutation' }; $checks++
$allowedScenario = [pscustomobject]@{Operation='Unlock';SimulationMode=$false;Preview=$false;WhatIf=$false;Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;AuthorizationOperation='Unlock';ShouldProcess=$true;Cancelled=$false}
$auditFailureFixture = New-AdminOperationFixture -AuditFails
$partial = Invoke-AdminSyntheticMutation -State $state -Fixture $auditFailureFixture -Scenario $allowedScenario -MutationCounter Unlock
if ($partial.Status -ne 'Partial' -or -not $partial.Changed -or $partial.Error -notlike '*rollback não executado*' -or $state.Counters.Unlock -ne 1) { throw 'NEGATIVE-TEST-FAILED:audit-partial-result' }; $checks++

# Synthetic preflight checks for the transactional Interface importer. No project module is imported here.
$interfaceProbeFixture=New-AdminScenarioFixture -Operation Unlock -ScenarioName TransactionImportPreflight
$interfaceProbeState=New-AdminProductionGateState -ProjectRoot $root -Domain User -Operation Unlock -Fixture $interfaceProbeFixture -Scenario $productionScenario
$interfaceProbe=New-Module -Name 'M47-Synthetic-Interface-Consumer' -ScriptBlock { }
$interfaceProbeState.InterfaceModule=$interfaceProbe
$interfaceProbeState.InterfaceImportRole='Actions'
Assert-Throws { Assert-AdminInterfaceImportRequest -State $interfaceProbeState -Consumer $interfaceProbe -RequestedPath 'ActiveDirectory' -Force } 'transaction-import-rejects-unapproved-target-before-loader'
Assert-Throws { Assert-AdminInterfaceImportRequest -State $interfaceProbeState -Consumer $interfaceProbe -RequestedPath $interfaceProbeState.Paths.Actions } 'transaction-import-rejects-missing-force-before-loader'
$wrongInterfaceProbe=New-Module -Name 'M47-Synthetic-Wrong-Consumer' -ScriptBlock { }
Assert-Throws { Assert-AdminInterfaceImportRequest -State $interfaceProbeState -Consumer $wrongInterfaceProbe -RequestedPath $interfaceProbeState.Paths.Actions -Force } 'transaction-import-rejects-wrong-sessionstate-before-loader'
$interfaceProbeState.InterfaceImportCount=1
Assert-Throws { Assert-AdminInterfaceImportRequest -State $interfaceProbeState -Consumer $interfaceProbe -RequestedPath $interfaceProbeState.Paths.Actions -Force } 'transaction-import-rejects-reuse-before-loader'
if($interfaceProbeState.ImportLog.Count -ne 0 -or $interfaceProbeState.ModuleInstances.Count -ne 0 -or $interfaceProbeState.GatePassed){throw 'NEGATIVE-TEST-FAILED:transaction-preflight-failure-reached-loader-or-approved-gate.'}
Write-Output ('COUNTERS_JSON:' + ([pscustomobject]@{ GetADUser=$state.Counters.GetADUser; Unlock=$state.Counters.Unlock; Audit=$state.Counters.Audit; Unexpected=$state.Counters.Unexpected; ImportModule=$state.Counters.ImportModule } | ConvertTo-Json -Compress))

# Real PowerShell module loader experiment using only New-Module and synthetic commands.
$previousImportFunction = Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue
$global:M43PowerShellLab = [pscustomobject]@{
    Allowed = [System.Collections.ArrayList]::new()
    Imports = [System.Collections.ArrayList]::new()
    ExternalCalls = 0
}
function global:Import-Module {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]$Name,
        [System.Management.Automation.PSModuleInfo]$ModuleInfo,
        [switch]$Force,
        [switch]$PassThru
    )
    $target = if ($null -ne $ModuleInfo) { $ModuleInfo } else { $Name }
    $allowedEntry = @($global:M43PowerShellLab.Allowed | Where-Object { [object]::ReferenceEquals($_.Source,$target) })
    if ($allowedEntry.Count -ne 1) { throw 'LAB-FAIL-CLOSED: unexpected Import-Module target.' }
    $global:M43PowerShellLab.Imports.Add([pscustomobject]@{ Role=$allowedEntry[0].Role; Force=[bool]$Force; Source=$target }) | Out-Null
    $loaded = Microsoft.PowerShell.Core\Import-Module -ModuleInfo $target -Force:$Force -PassThru -ErrorAction Stop
    if ($allowedEntry[0].Role -eq 'Core') {
        & $loaded {
            Set-Item Function:\script:Get-LabExternal {
                [CmdletBinding()] param([switch]$Probe)
                $global:M43PowerShellLab.ExternalCalls++
                if ($Probe) { return 'LAB-EXTERNAL-STUB' }
            } -Force
        }
        $resolvedStub = & $loaded { Get-Command Get-LabExternal -CommandType Function -ErrorAction Stop }
        if (-not [object]::ReferenceEquals((& $loaded { $ExecutionContext.SessionState.Module }),$loaded) -or
            $resolvedStub.Definition -notlike '*LAB-EXTERNAL-STUB*') { throw 'LAB-FAIL-CLOSED: nested Core stub was not resolved in its module SessionState.' }
    }
    if ($PassThru) { return $loaded }
}
try {
    $labCore = New-Module -Name 'M43-Lab-Core' -ScriptBlock {
        function Get-LabReader { Get-LabExternal -Probe }
        Export-ModuleMember -Function Get-LabReader
    }
    [void]$global:M43PowerShellLab.Allowed.Add([pscustomobject]@{ Role='Core'; Source=$labCore })
    $labManagement = New-Module -ArgumentList $labCore -ScriptBlock {
        param($CoreModule)
        Import-Module -ModuleInfo $CoreModule -Force -ErrorAction Stop | Out-Null
        function Invoke-LabReader { Get-LabReader }
        Export-ModuleMember -Function Invoke-LabReader
    }
    [void]$global:M43PowerShellLab.Allowed.Add([pscustomobject]@{ Role='Management'; Source=$labManagement })
    $labInterface = New-Module -ArgumentList $labManagement -ScriptBlock {
        param($ManagementModule)
        Import-Module -ModuleInfo $ManagementModule -Force -ErrorAction Stop | Out-Null
        function Invoke-LabFlow { Invoke-LabReader }
        Export-ModuleMember -Function Invoke-LabFlow
    }
    [void]$global:M43PowerShellLab.Allowed.Add([pscustomobject]@{ Role='Interface'; Source=$labInterface })
    $loadedInterface = Import-Module -ModuleInfo $labInterface -Force -PassThru
    $flowResult = & $loadedInterface { Invoke-LabFlow }
    if ($flowResult -ne 'LAB-EXTERNAL-STUB' -or $global:M43PowerShellLab.Imports.Count -ne 3 -or $global:M43PowerShellLab.ExternalCalls -ne 1) { throw 'LAB-FAIL:nested Import-Module interception and stub resolution.' }
    $beforeForce = $global:M43PowerShellLab.Imports.Count
    $null = Import-Module -ModuleInfo $labCore -Force -PassThru
    if ($global:M43PowerShellLab.Imports.Count -ne ($beforeForce + 1) -or -not $global:M43PowerShellLab.Imports[$global:M43PowerShellLab.Imports.Count - 1].Force) { throw 'LAB-FAIL:Import-Module -Force was not recorded.' }
    $flowAfterForce = & $loadedInterface { Invoke-LabFlow }
    if ($flowAfterForce -ne 'LAB-EXTERNAL-STUB' -or $global:M43PowerShellLab.ExternalCalls -ne 2) { throw 'LAB-FAIL:stub was not effective after forced reimport.' }
    Assert-Throws { Import-Module -Name 'Unapproved-Lab-Module' } 'real-loader-unexpected-import'
    $checks += 4
    Write-Output ('POWERSHELL_IMPORT_LAB_JSON:' + ([pscustomobject]@{
        PowerShell=$PSVersionTable.PSVersion.ToString(); NestedImportCount=$global:M43PowerShellLab.Imports.Count
        ForceCount=@($global:M43PowerShellLab.Imports | Where-Object Force).Count
        ExternalStubCalls=$global:M43PowerShellLab.ExternalCalls; ExternalRealCalls=0
        Result=$flowResult; ResultAfterForce=$flowAfterForce; UnexpectedImportBlocked=$true
    } | ConvertTo-Json -Compress))
}
finally {
    Remove-Item Function:\global:Import-Module -Force -ErrorAction SilentlyContinue
    if ($null -ne $previousImportFunction) { Set-Item Function:\global:Import-Module -Value $previousImportFunction.ScriptBlock -Force }
    Remove-Variable -Name M43PowerShellLab -Scope Global -ErrorAction SilentlyContinue
}
Write-Output ("HARNESS_COMPLETE:PASS checks={0} productionImports=0 externalCalls=0" -f $checks)
