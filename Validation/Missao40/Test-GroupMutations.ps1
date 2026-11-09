#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('SyntheticOnly','ProductionStubbed','InterfaceStubbed')][string]$Mode='SyntheticOnly',[ValidateSet('Add','Remove')][string]$InterfaceAction='Add',[ValidateSet('Simulation','AuthorizationDenied','AuthorizedExecute','ConfirmationDeclined','WriteAuthorizationDenied','ShouldProcessDeclined','NotFound','QueryError')][string]$InterfaceScenario='AuthorizedExecute')
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'Integration.Common.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $here 'Integration.Fixtures.psm1') -Force -ErrorAction Stop
if ($Mode -eq 'InterfaceStubbed') {
    Write-Output ("HARNESS_START:INTERFACE_GROUP action={0} scenario={1}" -f $InterfaceAction,$InterfaceScenario)
    $root=Split-Path -Parent (Split-Path -Parent $here)
    $actionData=if($InterfaceAction -eq 'Add'){@{Start='Start-V2GroupAddMember';Command='Add-ADGroupMember';Counter='AddGroupMember';Mutation='AddMember'}}else{@{Start='Start-V2GroupRemoveMember';Command='Remove-ADGroupMember';Counter='RemoveGroupMember';Mutation='RemoveMember'}}
    $fixture=New-AdminScenarioFixture -Operation ('Group'+$InterfaceAction) -ScenarioName $InterfaceScenario
    if($InterfaceAction -eq 'Add'){$fixture.Group.Members=@()}else{$fixture.Group.Members=@('fixture.member')}
    if($InterfaceScenario -eq 'NotFound'){$fixture.Group.QueryStatus='NotFound'}
    if($InterfaceScenario -eq 'QueryError'){$fixture.Group.QueryStatus='Error';$fixture.Group.Error='Synthetic group query error.'}
    $state=New-AdminProductionGateState -ProjectRoot $root -Domain Group -Operation ('Group'+$InterfaceAction) -Fixture $fixture -Scenario ([pscustomobject]@{ShouldProcess=($InterfaceScenario -ne 'ShouldProcessDeclined')})
    try {
        $interface=Import-AdminInterfaceModuleSafe -State $state -Path (Join-Path $root '10-Interface-V2/Interface-V2-Functions.psm1')
        Install-AdminInterfaceTransactionGuard -State $state -Module $interface -ExpectedRole Management | Out-Null
        Install-AdminInterfaceUiStubs -State $state -Module $interface | Out-Null
        $null=& $interface { param($Path) Import-Module -Name $Path -Force -ErrorAction Stop } $state.Paths.Management
        if(-not $state.GatePassed){throw 'FAIL-CLOSED: Interface Group import transaction did not pass.'}
        Write-Output 'HARNESS_GATE:INTERFACE_IMPORT_TRANSACTION'
        $inputs=switch ($InterfaceScenario) {
            'Simulation' { @('fixture.member','S','') }
            'AuthorizationDenied' { @('fixture.member','DENY') }
            'AuthorizedExecute' { @('fixture.member','AUTORIZAR LEITURA','S','AUTORIZAR ALTERAÇÃO','') }
            'ConfirmationDeclined' { @('fixture.member','AUTORIZAR LEITURA','N','') }
            'WriteAuthorizationDenied' { @('fixture.member','AUTORIZAR LEITURA','S','DENY') }
            'ShouldProcessDeclined' { @('fixture.member','AUTORIZAR LEITURA','S','AUTORIZAR ALTERAÇÃO','') }
            'NotFound' { @('fixture.member','AUTORIZAR LEITURA','') }
            'QueryError' { @('fixture.member','AUTORIZAR LEITURA','') }
        }
        $state.InterfaceInputQueue.Clear(); foreach($input in $inputs){$state.InterfaceInputQueue.Add($input)|Out-Null}
        $simulation=$InterfaceScenario -eq 'Simulation'
        $members=if($InterfaceAction -eq 'Add'){@()}else{@('fixture.member')}
        $configuration=[pscustomobject]@{
            SimulationMode=$simulation
            ActiveDirectory=[pscustomobject]@{DomainController='dc.fixture.invalid'}
            Group=[pscustomobject]@{DefaultCategory='Security';DefaultScope='Global'}
            Simulation=[pscustomobject]@{ExistingGroups=@([pscustomobject]@{Name='fixture.group';Members=@($members)});ExistingUsers=@('fixture.member')}
        }
        & $interface { param($StartName,$Config) & $StartName -GroupName 'fixture.group' -Configuration $Config } $actionData.Start $configuration | Out-Null
        $referenceEvidence=Assert-AdminInterfaceReferencesCurrent -State $state
        if(-not $state.GatePassed -or $state.Counters.Unexpected -ne 0 -or (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory)){throw 'FAIL-CLOSED: Interface Group gate or external isolation failed.'}
        if($state.InterfaceInputIndex -ne $state.InterfaceInputQueue.Count){throw 'ASSERTION-FAIL: Interface Group prompt sequence did not consume exactly the deterministic fixture inputs.'}
        $mutation=[int]$state.Counters[$actionData.Counter]
        $shouldMutate=$InterfaceScenario -eq 'AuthorizedExecute'
        if($mutation -ne [int]$shouldMutate){throw "ASSERTION-FAIL:Interface Group $InterfaceAction/$InterfaceScenario mutator count=$mutation."}
        if($InterfaceScenario -in @('Simulation','AuthorizationDenied') -and ($state.Counters.GetADGroup+$state.Counters.GetADGroupMember+$state.Counters.GetADUser+$state.Counters.GetModule+$state.Counters.ADImportBlocked -ne 0)){throw "ASSERTION-FAIL:Interface Group $InterfaceAction/$InterfaceScenario performed a protected read."}
        if($InterfaceScenario -in @('ConfirmationDeclined','WriteAuthorizationDenied','ShouldProcessDeclined') -and $mutation -ne 0){throw "ASSERTION-FAIL:Interface Group $InterfaceAction/$InterfaceScenario mutated after refusal."}
        if($InterfaceScenario -in @('NotFound','QueryError') -and ($mutation -ne 0 -or $state.Counters.GetADGroup -lt 1)){throw "ASSERTION-FAIL:Interface Group $InterfaceAction/$InterfaceScenario did not preserve a non-mutating query result."}
        if($InterfaceScenario -eq 'AuthorizedExecute' -and ($null -eq $state.LastMutation -or $state.LastMutation.Command -ne $actionData.Command -or $state.LastMutation.Identity -ne 'fixture.group' -or $state.LastMutation.Members -ne 'fixture.member')){throw 'ASSERTION-FAIL: Interface Group authorized call did not reach expected stub.'}
        $checks=7
        Write-Output ('INTERFACE_EVIDENCE_JSON:' + ([pscustomobject]@{Domain='Group';Action=$InterfaceAction;Scenario=$InterfaceScenario;GatePassed=$state.GatePassed;ReferencesValidated=$referenceEvidence.Passed;CapturedReferences=$referenceEvidence.CapturedReferences;Modules=@($state.ModuleInstances|ForEach-Object{[pscustomobject]@{Role=$_.Role;Path=$_.Path;Guid=$_.Guid}});Stubs=@($state.StubEvidence|ForEach-Object{[pscustomobject]@{Role=$_.Role;Name=$_.Name;Sentinel=$_.Sentinel;Parameters=$_.Parameters}});Counters=$state.Counters;LastMutation=$state.LastMutation;InputsConsumed=$state.InterfaceInputIndex;InputsProvided=$state.InterfaceInputQueue.Count;ADLoaded=[bool](Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory);RealExternalCalls=0;Checks=$checks}|ConvertTo-Json -Depth 8 -Compress))
        Write-Output ("HARNESS_COMPLETE:PASS checks={0} failed=0" -f $checks)
    }
    finally { Restore-AdminProductionImportGuard -State $state }
    return
}
if ($Mode -eq 'ProductionStubbed') {
    Write-Output 'HARNESS_START:GROUP_MUTATIONS_PRODUCTION_STUBBED'
    $root = Split-Path -Parent (Split-Path -Parent $here)
    $operations = @(
        @{Name='GroupAdd';Command='Invoke-GroupAddMember';Counter='AddGroupMember';Mutator='Add-ADGroupMember';Action='AddMember'},
        @{Name='GroupRemove';Command='Invoke-GroupRemoveMember';Counter='RemoveGroupMember';Mutator='Remove-ADGroupMember';Action='RemoveMember'}
    )
    $definitions = @(
        @{Name='Simulation';Simulation=$true;Execute=$true},
        @{Name='ExplicitPreview';ExplicitPreview=$true},
        @{Name='WhatIf';Read=$true;Write=$true;Execute=$true;WhatIf=$true},
        @{Name='NoAuthorization';Execute=$true},
        @{Name='ReadOnly';Read=$true},
        @{Name='NoWriteAuthorization';Read=$true;Execute=$true},
        @{Name='AuthorizedExecute';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true},
        @{Name='ShouldProcessDeclined';Read=$true;Write=$true;Execute=$true;ShouldProcess=$false},
        @{Name='GroupNotFound';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;GroupQuery='NotFound'},
        @{Name='UserNotFound';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;UserQuery='NotFound'},
        @{Name='GroupQueryError';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;GroupQuery='Error'},
        @{Name='UserQueryError';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;UserQuery='Error'},
        @{Name='MutationFailure';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;MutationFails=$true},
        @{Name='AuditFailure';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;AuditFails=$true},
        @{Name='MemberConflict'}
    )
    $fixture = New-AdminScenarioFixture -Operation GroupAdd -ScenarioName ProductionGate
    $state = New-AdminProductionGateState -ProjectRoot $root -Domain Group -Operation 'GroupMutations' -Fixture $fixture -Scenario ([pscustomobject]@{ShouldProcess=$true})
    try {
        $gate = Import-AdminProductionModuleChain -State $state
        if (-not $gate.Passed) { throw 'FAIL-CLOSED: Group production gate was not approved.' }
        Write-Output 'HARNESS_GATE:PRODUCTION_MODULE_CHAIN_STUBBED'
        $module = @($state.ModuleInstances | Where-Object Role -eq 'Management')[0].Module
        $invoke = {
            param($OperationName,$CommandName,$ActionName,$Configuration,$Execute,$ReadAuth,$WriteAuth,$WhatIf,$ExplicitPreview)
            if ($ExplicitPreview) { return Get-GroupManagementPreview -Action $ActionName -GroupName 'fixture.group' -SamAccountName 'fixture.member' -Configuration $Configuration -Preview }
            $parameters = @{ GroupName='fixture.group'; SamAccountName='fixture.member'; Configuration=$Configuration; Execute=[bool]$Execute; AllowRealRead=[bool]$ReadAuth; AllowRealWrite=[bool]$WriteAuth; Confirm=$false }
            if ($WhatIf) { $parameters.WhatIf=$true }
            & $CommandName @parameters
        }
        $evidence = [System.Collections.Generic.List[object]]::new()
        $passed=0; $total=0
        foreach ($operation in $operations) {
            foreach ($definition in $definitions) {
                $total++
                $fixture=New-AdminScenarioFixture -Operation $operation.Name -ScenarioName $definition.Name
                if ($definition.ContainsKey('GroupQuery')) { $fixture.Group.QueryStatus=$definition.GroupQuery }
                if ($definition.ContainsKey('UserQuery')) { $fixture.User.QueryStatus=$definition.UserQuery }
                if ($definition.Name -eq 'MemberConflict') { if($operation.Action -eq 'AddMember'){$fixture.Group.Members=@('fixture.member')}else{$fixture.Group.Members=@()} }
                $fixture.OperationResult=New-AdminOperationFixture -QueryStatus Found -MutationFails:([bool]$definition.MutationFails) -AuditFails:([bool]$definition.AuditFails)
                $state.Scenario=[pscustomobject]@{ShouldProcess=if($definition.ContainsKey('ShouldProcess')){[bool]$definition.ShouldProcess}else{$true}}
                foreach($counterName in @($state.Counters.Keys)){$state.Counters[$counterName]=0}
                $state.LastMutation=$null
                $simulation=[bool]$definition.Simulation
                $members=if($operation.Action -eq 'AddMember'){@()}else{@('fixture.member','fixture.other')}
                if($definition.Name -eq 'MemberConflict' -and $operation.Action -eq 'AddMember'){$members=@('fixture.member')}
                if($definition.Name -eq 'MemberConflict' -and $operation.Action -eq 'RemoveMember'){$members=@()}
                $fixture.Group.Members=@($members)
                $state.Fixture=$fixture
                $configuration=[pscustomobject]@{
                    SimulationMode=$simulation
                    ActiveDirectory=[pscustomobject]@{DomainController='dc.fixture.invalid'}
                    Group=[pscustomobject]@{DefaultCategory='Security';DefaultScope='Global'}
                    Simulation=[pscustomobject]@{
                        ExistingGroups=@([pscustomobject]@{Name='fixture.group';Members=@($members)})
                        ExistingUsers=@('fixture.member')
                    }
                }
                $result=& $module $invoke $operation.Name $operation.Command $operation.Action $configuration ([bool]$definition.Execute) ([bool]$definition.Read) ([bool]$definition.Write) ([bool]$definition.WhatIf) ([bool]$definition.ExplicitPreview)
                if($result -is [array] -or $null -eq $result -or $state.Counters.Unexpected -ne 0 -or (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory)){throw "FAIL-CLOSED: resultado ou fronteira inválida em $($operation.Name)/$($definition.Name)."}
                $mutationCount=[int]$state.Counters[$operation.Counter]
                $expectedMutation=$definition.Name -in @('AuthorizedExecute','MutationFailure','AuditFailure')
                if($mutationCount -ne [int]$expectedMutation){throw "ASSERTION-FAIL:$($operation.Name)/$($definition.Name):mutator-count=$mutationCount;result=$($result|ConvertTo-Json -Depth 8 -Compress);counters=$($state.Counters|ConvertTo-Json -Compress)"}
                if($definition.Name -in @('Simulation','ExplicitPreview','WhatIf','NoAuthorization','NoWriteAuthorization','ShouldProcessDeclined') -and ($state.Counters.GetADDomain+$state.Counters.GetADGroup+$state.Counters.GetADGroupMember+$state.Counters.GetADUser+$state.Counters.ADImportBlocked+$state.Counters.GetModule) -ne 0){throw "ASSERTION-FAIL:$($operation.Name)/$($definition.Name):protected-read-counter"}
                if($definition.Name -eq 'AuthorizedExecute' -and (-not $result.Success -or $null -eq $state.LastMutation -or $state.LastMutation.Command -ne $operation.Mutator -or $state.LastMutation.Identity -ne 'fixture.group' -or $state.LastMutation.Members -ne 'fixture.member')){throw "ASSERTION-FAIL:$($operation.Name):authorized-result-or-arguments"}
                if($definition.Name -in @('GroupNotFound','UserNotFound','GroupQueryError','UserQueryError','MemberConflict') -and ($result.Success -or $mutationCount -ne 0)){throw "ASSERTION-FAIL:$($operation.Name)/$($definition.Name):failure-or-conflict-result"}
                if($definition.Name -eq 'MutationFailure' -and $result.Success){throw "ASSERTION-FAIL:$($operation.Name):mutation-failure-result"}
                if($definition.Name -eq 'AuditFailure' -and ($result.Success -or -not $result.Changed -or $mutationCount -ne 1)){throw "ASSERTION-FAIL:$($operation.Name):partial-audit-result"}
                if($definition.Name -eq 'ShouldProcessDeclined' -and (-not $result.Cancelled -or $result.Mode -ne 'Preview')){throw "ASSERTION-FAIL:$($operation.Name):cancel-result"}
                if($definition.Name -eq 'WhatIf' -and ($result.Mode -ne 'Preview' -or $result.Cancelled)){throw "ASSERTION-FAIL:$($operation.Name):whatif-result"}
                if($definition.Name -eq 'ReadOnly' -and ($mutationCount -ne 0 -or $state.Counters.GetADGroup -lt 1)){throw "ASSERTION-FAIL:$($operation.Name):read-only-preview"}
                $passed++
                $counterSnapshot=[ordered]@{};foreach($counterName in $state.Counters.Keys){$counterSnapshot[$counterName]=$state.Counters[$counterName]}
                $evidence.Add([pscustomobject]@{Operation=$operation.Name;Scenario=$definition.Name;Success=$result.Success;Status=$result.Status;Counters=[pscustomobject]$counterSnapshot;LastMutation=$state.LastMutation;ActiveDirectoryLoaded=$false})|Out-Null
            }
        }
        $lastMemberFixture=New-AdminScenarioFixture -Operation GroupRemove -ScenarioName SimulationLastMember
        $lastMemberFixture.Group.Members=@('fixture.member')
        $lastMemberFixture.OperationResult=New-AdminOperationFixture -QueryStatus Found
        $state.Fixture=$lastMemberFixture
        $state.Scenario=[pscustomobject]@{ShouldProcess=$true}
        foreach($counterName in @($state.Counters.Keys)){$state.Counters[$counterName]=0}
        $state.LastMutation=$null
        $lastMemberConfiguration=[pscustomobject]@{
            SimulationMode=$true
            ActiveDirectory=[pscustomobject]@{DomainController='dc.fixture.invalid'}
            Group=[pscustomobject]@{DefaultCategory='Security';DefaultScope='Global'}
            Simulation=[pscustomobject]@{
                ExistingGroups=@([pscustomobject]@{Name='fixture.group';Members=@('fixture.member')})
                ExistingUsers=@('fixture.member')
            }
        }
        $lastMemberResult=& $module $invoke 'GroupRemove' 'Invoke-GroupRemoveMember' 'RemoveMember' $lastMemberConfiguration $true $false $false $false $false
        if(-not $lastMemberResult.Success -or -not $lastMemberResult.SimulationMode -or -not $lastMemberResult.Changed -or @($lastMemberConfiguration.Simulation.ExistingGroups[0].Members).Count -ne 0 -or $null -eq $lastMemberConfiguration.Simulation.ExistingGroups[0].Members -or $null -eq $lastMemberResult.Audit -or $lastMemberResult.Audit.Action -ne 'RemoveMember' -or $state.Counters.RemoveGroupMember -ne 0 -or $state.Counters.GetADGroup -ne 0 -or $state.Counters.GetADGroupMember -ne 0 -or $state.Counters.GetADUser -ne 0 -or $state.Counters.ADImportBlocked -ne 0 -or $state.Counters.Unexpected -ne 0){throw 'ASSERTION-FAIL:GroupRemove/SimulationLastMember did not preserve empty membership, audit, or zero-external-call contract.'}
        $passed++;$total++
        $counterSnapshot=[ordered]@{};foreach($counterName in $state.Counters.Keys){$counterSnapshot[$counterName]=$state.Counters[$counterName]}
        $evidence.Add([pscustomobject]@{Operation='GroupRemove';Scenario='SimulationLastMember';Success=$lastMemberResult.Success;Status=$lastMemberResult.Status;Counters=[pscustomobject]$counterSnapshot;LastMutation=$state.LastMutation;RemainingMemberCount=0;AuditAction=$lastMemberResult.Audit.Action;ActiveDirectoryLoaded=$false})|Out-Null
        $beforeModules=$state.ModuleInstances.Count;$reimportBlocked=$false
        try{Import-AdminProductionModuleChain -State $state|Out-Null}catch{$reimportBlocked=$true}
        if(-not $reimportBlocked -or $state.ModuleInstances.Count -ne $beforeModules){throw 'FAIL-CLOSED: reimportação após gate não foi bloqueada antes de substituir instâncias.'}
        $passed++;$total++
        $summary=[pscustomobject]@{Mode='ProductionStubbed';Gate=$gate;Scenarios=@($evidence);ReimportBlocked=$reimportBlocked;ProductionModulesLoaded=$true;RealCalls=0;RepositoryWrites=0;Checks=$passed;Total=$total;Counters=$state.Counters}
        Write-Output ('PRODUCTION_EVIDENCE_JSON:'+($summary|ConvertTo-Json -Depth 10 -Compress))
        Write-Output ("HARNESS_COMPLETE:PASS passed={0} failed=0 scenarios={1}" -f $passed,$total)
    }
    finally { Restore-AdminProductionImportGuard -State $state }
    return
}
Write-Output 'HARNESS_START:GROUP_MUTATIONS_SYNTHETIC'
Write-Output 'HARNESS_GATE:SYNTHETIC_ONLY_NO_PRODUCTION_IMPORT'
$state = New-AdminHarnessState -ProjectRoot (Split-Path -Parent (Split-Path -Parent $here))
$passed = 0
$failed = 0
$failures = [System.Collections.Generic.List[string]]::new()
$operations = @(@{Name='GroupAdd';Counter='AddGroupMember'},@{Name='GroupRemove';Counter='RemoveGroupMember'})
$scenarios = @(
    @{Name='SimulationMode';SimulationMode=$true}, @{Name='Preview';Preview=$true}, @{Name='WhatIf';WhatIf=$true},
    @{Name='NoAuthorization';Execute=$true}, @{Name='ReadOnlyAuthorization';Execute=$true;AllowRealRead=$true},
    @{Name='InvalidWriteAuthorization';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$false},
    @{Name='AuthorizedExecute';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true},
    @{Name='ShouldProcessDeclined';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$false},
    @{Name='Cancelled';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true;Cancelled=$true},
    @{Name='GroupNotFound';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true},
    @{Name='UserNotFound';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true},
    @{Name='GroupQueryError';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true},
    @{Name='UserQueryError';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true},
    @{Name='MutationFailure';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true;MutationFails=$true},
    @{Name='AuditFailureAfterMutation';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true;AuditFails=$true},
    @{Name='WrongOperationAuthorization';Execute=$true;AllowRealRead=$true;AllowRealWrite=$true;WriteAuthorizationValid=$true;ShouldProcess=$true;AuthorizationOperation='Other'},
    @{Name='MemberAlreadyPresent';MemberState='Present'}, @{Name='MemberAbsent';MemberState='Absent'}
)
foreach ($operation in $operations) {
    foreach ($definition in $scenarios) {
        $fixture = New-AdminScenarioFixture -Operation $operation.Name -ScenarioName $definition.Name
        if ($definition.Name -eq 'GroupNotFound') { $fixture.Group = New-AdminGroupFixture -QueryStatus NotFound }
        if ($definition.Name -eq 'UserNotFound') { $fixture.User = New-AdminUserFixture -QueryStatus NotFound }
        if ($definition.Name -eq 'MemberAlreadyPresent') { $fixture.Group = New-AdminGroupFixture -Members @('fixture.user') }
        if ($definition.Name -eq 'MemberAbsent') { $fixture.Group = New-AdminGroupFixture -Members @() }
        $scenario = [pscustomobject]@{
            Operation=$operation.Name; SimulationMode=[bool]$definition.SimulationMode; Preview=[bool]$definition.Preview; WhatIf=[bool]$definition.WhatIf
            Execute=[bool]$definition.Execute; AllowRealRead=[bool]$definition.AllowRealRead; AllowRealWrite=[bool]$definition.AllowRealWrite
            WriteAuthorizationValid=if ($definition.ContainsKey('WriteAuthorizationValid')) { $definition.WriteAuthorizationValid } else { $false }
            AuthorizationOperation=if ($definition.ContainsKey('AuthorizationOperation')) { $definition.AuthorizationOperation } else { $operation.Name }
            ShouldProcess=if ($definition.ContainsKey('ShouldProcess')) { $definition.ShouldProcess } else { $false }
            Cancelled=[bool]$definition.Cancelled
        }
        $gate = Test-AdminSyntheticMutationGate -Scenario $scenario
        $fixture.OperationResult = New-AdminOperationFixture -QueryStatus Found -MutationFails:([bool]$definition.MutationFails) -AuditFails:([bool]$definition.AuditFails)
        $readStatuses = @{ GetADGroup='Found'; GetADGroupMember='Found'; GetADUser='Found' }
        if ($definition.Name -eq 'GroupNotFound') { $readStatuses.GetADGroup='NotFound' }
        if ($definition.Name -eq 'UserNotFound') { $readStatuses.GetADUser='NotFound' }
        if ($definition.Name -eq 'GroupQueryError') { $readStatuses.GetADGroup='Error'; $fixture.OperationResult.Error='Synthetic group query error.' }
        if ($definition.Name -eq 'UserQueryError') { $readStatuses.GetADUser='Error'; $fixture.OperationResult.Error='Synthetic user query error.' }
        $mutationsBefore = [int]$state.Counters[$operation.Counter]
        $readsBefore = [int]$state.Counters.GetADUser
        $groupReadsBefore = [int]$state.Counters.GetADGroup
        $memberReadsBefore = [int]$state.Counters.GetADGroupMember
        $auditBefore = [int]$state.Counters.Audit
        $result = Invoke-AdminSyntheticMutation -State $state -Fixture $fixture.OperationResult -Scenario $scenario -MutationCounter $operation.Counter -ReadCounters @('GetADGroup','GetADGroupMember','GetADUser') -ReadStatuses $readStatuses
        $expectedAllowed = ($definition.Name -in @('AuthorizedExecute','GroupNotFound','UserNotFound','GroupQueryError','UserQueryError','MutationFailure','AuditFailureAfterMutation'))
        $ok = ($gate.Allowed -eq $expectedAllowed)
        if ($definition.Name -eq 'GroupNotFound' -or $definition.Name -eq 'UserNotFound') { $ok = $ok -and $result.Status -eq 'NotFound' -and -not $result.Changed }
        if ($definition.Name -eq 'GroupQueryError' -or $definition.Name -eq 'UserQueryError') { $ok = $ok -and $result.Status -eq 'Error' -and $result.Error -like 'Synthetic * query error.' }
        if ($definition.Name -eq 'MutationFailure') { $ok = $ok -and $result.Status -eq 'Error' -and -not $result.Changed }
        if ($definition.Name -eq 'AuditFailureAfterMutation') { $ok = $ok -and $result.Status -eq 'Partial' -and $result.Changed }
        if ($definition.Name -eq 'AuthorizedExecute') { $ok = $ok -and $result.Status -eq 'Completed' -and $result.Changed }
        if ($definition.Name -eq 'MemberAlreadyPresent') { $ok = $ok -and $fixture.Group.Members -contains 'fixture.user' }
        if ($definition.Name -eq 'MemberAbsent') { $ok = $ok -and $fixture.Group.Members -notcontains 'fixture.user' }
        if (-not $expectedAllowed) { $ok = $ok -and -not $result.Changed }
        $expectedMutationCall = $definition.Name -in @('AuthorizedExecute','MutationFailure','AuditFailureAfterMutation')
        $ok = $ok -and (($state.Counters[$operation.Counter] - $mutationsBefore) -eq [int]$expectedMutationCall)
        $expectedUserRead = $expectedAllowed -and $definition.Name -notin @('GroupNotFound','GroupQueryError')
        $expectedGroupRead = $expectedAllowed
        $expectedMemberRead = $expectedAllowed -and $definition.Name -notin @('GroupNotFound','GroupQueryError')
        $expectedAuditCall = $definition.Name -in @('AuthorizedExecute','AuditFailureAfterMutation')
        $ok = $ok -and (($state.Counters.GetADUser - $readsBefore) -eq [int]$expectedUserRead)
        $ok = $ok -and (($state.Counters.GetADGroup - $groupReadsBefore) -eq [int]$expectedGroupRead)
        $ok = $ok -and (($state.Counters.GetADGroupMember - $memberReadsBefore) -eq [int]$expectedMemberRead)
        $ok = $ok -and (($state.Counters.Audit - $auditBefore) -eq [int]$expectedAuditCall)
        if ($ok) { $passed++ } else { $failed++; $failures.Add($operation.Name + '/' + $definition.Name + ' -> ' + $result.Status) }
    }
}
if ($failed -ne 0) { foreach ($failure in $failures) { Write-Output ('FAIL_CASE:' + $failure) }; Write-Output ("HARNESS_COMPLETE:FAIL passed={0} failed={1}" -f $passed,$failed); exit 1 }
Write-Output ('COUNTERS_JSON:' + ([pscustomobject]@{ GetADGroup=$state.Counters.GetADGroup; GetADGroupMember=$state.Counters.GetADGroupMember; GetADUser=$state.Counters.GetADUser; AddGroupMember=$state.Counters.AddGroupMember; RemoveGroupMember=$state.Counters.RemoveGroupMember; Audit=$state.Counters.Audit } | ConvertTo-Json -Compress))
Write-Output ("HARNESS_COMPLETE:PASS passed={0} failed=0 scenarios={1}" -f $passed,($operations.Count*$scenarios.Count))
