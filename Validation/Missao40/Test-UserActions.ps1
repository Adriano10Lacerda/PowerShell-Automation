#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('SyntheticOnly','ProductionStubbed','InterfaceStubbed')][string]$Mode='SyntheticOnly',[ValidateSet('Unlock','Enable','Disable','ForcePasswordChange')][string]$InterfaceAction='Unlock',[ValidateSet('Simulation','AuthorizationDenied','AuthorizedExecute','ConfirmationDeclined','WriteAuthorizationDenied','ShouldProcessDeclined','NotFound','QueryError')][string]$InterfaceScenario='AuthorizedExecute')
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'Integration.Common.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $here 'Integration.Fixtures.psm1') -Force -ErrorAction Stop
if ($Mode -eq 'InterfaceStubbed') {
    Write-Output ("HARNESS_START:INTERFACE_USER action={0} scenario={1}" -f $InterfaceAction,$InterfaceScenario)
    $root=Split-Path -Parent (Split-Path -Parent $here)
    $operation=@{
        Unlock=@{Start='Start-V2UserUnlockAccount';Command='Unlock-ADAccount';Counter='Unlock';State='LockedOut'}
        Enable=@{Start='Start-V2UserEnableAccount';Command='Enable-ADAccount';Counter='Enable';State='Disabled'}
        Disable=@{Start='Start-V2UserDisableAccount';Command='Disable-ADAccount';Counter='Disable';State='Enabled'}
        ForcePasswordChange=@{Start='Start-V2UserForcePasswordChange';Command='Set-ADUser';Counter='SetUser';State='Enabled'}
    }[$InterfaceAction]
    $fixture=New-AdminScenarioFixture -Operation $InterfaceAction -ScenarioName $InterfaceScenario
    $fixture.User.State=$operation.State
    $fixture.User.Enabled=($operation.State -ne 'Disabled')
    $fixture.User.LockedOut=($operation.State -eq 'LockedOut')
    $fixture.User.PasswordChangeAtLogon=$false
    if($InterfaceScenario -eq 'NotFound'){$fixture.User.QueryStatus='NotFound'}
    if($InterfaceScenario -eq 'QueryError'){$fixture.User.QueryStatus='Error';$fixture.User.Error='Synthetic user query error.'}
    $state=New-AdminProductionGateState -ProjectRoot $root -Domain User -Operation $InterfaceAction -Fixture $fixture -Scenario ([pscustomobject]@{ShouldProcess=($InterfaceScenario -ne 'ShouldProcessDeclined')})
    try {
        $interface=Import-AdminInterfaceModuleSafe -State $state -Path (Join-Path $root '10-Interface-V2/Interface-V2-Functions.psm1')
        Install-AdminInterfaceTransactionGuard -State $state -Module $interface -ExpectedRole Actions | Out-Null
        Install-AdminInterfaceUiStubs -State $state -Module $interface | Out-Null
        $inputs=switch ($InterfaceScenario) {
            'Simulation' { @('S','') }
            'AuthorizationDenied' { @('DENY') }
            'AuthorizedExecute' { @('AUTORIZAR LEITURA','S','AUTORIZAR ALTERAÇÃO','') }
            'ConfirmationDeclined' { @('AUTORIZAR LEITURA','N','') }
            'WriteAuthorizationDenied' { @('AUTORIZAR LEITURA','S','DENY') }
            'ShouldProcessDeclined' { @('AUTORIZAR LEITURA','S','AUTORIZAR ALTERAÇÃO','') }
            'NotFound' { @('AUTORIZAR LEITURA','') }
            'QueryError' { @('AUTORIZAR LEITURA','') }
        }
        foreach($input in $inputs){$state.InterfaceInputQueue.Add($input)|Out-Null}
        $simulation=$InterfaceScenario -eq 'Simulation'
        $locked=if($InterfaceAction -eq 'Unlock'){@('fixture.user')}else{@()}
        $disabled=if($InterfaceAction -eq 'Enable'){@('fixture.user')}else{@()}
        $passwordChange=if($InterfaceAction -eq 'ForcePasswordChange'){@()}else{@()}
        $configuration=[pscustomobject]@{
            SimulationMode=$simulation; DomainController='dc.fixture.invalid'; Domain='fixture.invalid'
            UserPrincipalName=[pscustomobject]@{Domain='fixture.invalid'}
            Simulation=[pscustomobject]@{ExistingSamAccountNames=@('fixture.user');LockedSamAccountNames=$locked;DisabledSamAccountNames=$disabled;PasswordChangeAtLogonSamAccountNames=$passwordChange}
        }
        & $interface { param($StartName,$Config) & $StartName -SamAccountName 'fixture.user' -Configuration $Config } $operation.Start $configuration | Out-Null
        $referenceEvidence=Assert-AdminInterfaceReferencesCurrent -State $state
        if(-not $state.GatePassed -or $state.Counters.Unexpected -ne 0 -or (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory)){throw 'FAIL-CLOSED: Interface User gate or external isolation failed.'}
        if($state.InterfaceInputIndex -ne $state.InterfaceInputQueue.Count){throw 'ASSERTION-FAIL: Interface User prompt sequence did not consume exactly the deterministic fixture inputs.'}
        Write-Output 'HARNESS_GATE:INTERFACE_IMPORT_TRANSACTION'
        $mutation=[int]$state.Counters[$operation.Counter]
        $shouldMutate=$InterfaceScenario -eq 'AuthorizedExecute'
        if($mutation -ne [int]$shouldMutate){throw "ASSERTION-FAIL:Interface $InterfaceAction/$InterfaceScenario mutator count=$mutation."}
        if($InterfaceScenario -in @('Simulation','AuthorizationDenied') -and ($state.Counters.GetADUser+$state.Counters.GetModule+$state.Counters.ADImportBlocked -ne 0)){throw "ASSERTION-FAIL:Interface $InterfaceAction/$InterfaceScenario performed a protected read."}
        if($InterfaceScenario -in @('ConfirmationDeclined','WriteAuthorizationDenied','ShouldProcessDeclined') -and $mutation -ne 0){throw "ASSERTION-FAIL:Interface $InterfaceAction/$InterfaceScenario mutated after refusal."}
        if($InterfaceScenario -in @('NotFound','QueryError') -and ($mutation -ne 0 -or $state.Counters.GetADUser -lt 1)){throw "ASSERTION-FAIL:Interface $InterfaceAction/$InterfaceScenario did not preserve a non-mutating query result."}
        if($InterfaceScenario -eq 'AuthorizedExecute' -and ($null -eq $state.LastMutation -or $state.LastMutation.Command -ne $operation.Command -or $state.LastMutation.Identity -ne 'fixture.user')){throw 'ASSERTION-FAIL: Interface User authorized call did not reach the expected stub.'}
        $checks=6
        Write-Output ('INTERFACE_EVIDENCE_JSON:' + ([pscustomobject]@{Domain='User';Action=$InterfaceAction;Scenario=$InterfaceScenario;GatePassed=$state.GatePassed;ReferencesValidated=$referenceEvidence.Passed;CapturedReferences=$referenceEvidence.CapturedReferences;Modules=@($state.ModuleInstances|ForEach-Object{[pscustomobject]@{Role=$_.Role;Path=$_.Path;Guid=$_.Guid}});Stubs=@($state.StubEvidence|ForEach-Object{[pscustomobject]@{Role=$_.Role;Name=$_.Name;Sentinel=$_.Sentinel;Parameters=$_.Parameters}});Counters=$state.Counters;LastMutation=$state.LastMutation;InputsConsumed=$state.InterfaceInputIndex;InputsProvided=$state.InterfaceInputQueue.Count;ADLoaded=[bool](Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory);RealExternalCalls=0;Checks=$checks}|ConvertTo-Json -Depth 8 -Compress))
        Write-Output ("HARNESS_COMPLETE:PASS checks={0} failed=0" -f $checks)
    }
    finally { Restore-AdminProductionImportGuard -State $state }
    return
}
if ($Mode -eq 'ProductionStubbed') {
    Write-Output 'HARNESS_START:USER_ACTIONS_PRODUCTION_STUBBED'
    $root = Split-Path -Parent (Split-Path -Parent $here)
    $operations = @(
        @{Name='Unlock';Command='Invoke-UserUnlockAccount';Counter='Unlock';Mutator='Unlock-ADAccount';State='LockedOut'},
        @{Name='Enable';Command='Invoke-UserEnableAccount';Counter='Enable';Mutator='Enable-ADAccount';State='Disabled'},
        @{Name='Disable';Command='Invoke-UserDisableAccount';Counter='Disable';Mutator='Disable-ADAccount';State='Enabled'},
        @{Name='ForcePasswordChange';Command='Invoke-UserForcePasswordChange';Counter='SetUser';Mutator='Set-ADUser';State='Enabled'}
    )
    $definitions = @(
        @{Name='Simulation';Simulation=$true;Execute=$true},
        @{Name='PreviewRead';Read=$true},
        @{Name='WhatIf';Read=$true;Write=$true;Execute=$true;WhatIf=$true},
        @{Name='NoAuthorization';Execute=$true},
        @{Name='ReadOnly';Read=$true},
        @{Name='NoWriteAuthorization';Read=$true;Execute=$true},
        @{Name='AuthorizedExecute';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true},
        @{Name='ShouldProcessDeclined';Read=$true;Write=$true;Execute=$true;ShouldProcess=$false},
        @{Name='NotFound';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;Query='NotFound'},
        @{Name='QueryError';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;Query='Error'},
        @{Name='MutationFailure';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;MutationFails=$true},
        @{Name='AuditFailure';Read=$true;Write=$true;Execute=$true;ShouldProcess=$true;AuditFails=$true}
    )
    $fixture = New-AdminScenarioFixture -Operation 'Unlock' -ScenarioName 'ProductionGate'
    $state = New-AdminProductionGateState -ProjectRoot $root -Domain User -Operation 'UserActions' -Fixture $fixture -Scenario ([pscustomobject]@{ShouldProcess=$true})
    try {
        $gate = Import-AdminProductionModuleChain -State $state
        if (-not $gate.Passed) { throw 'FAIL-CLOSED: User production gate was not approved.' }
        Write-Output 'HARNESS_GATE:PRODUCTION_MODULE_CHAIN_STUBBED'
        $module = @($state.ModuleInstances | Where-Object Role -eq 'Actions')[0].Module
        $invoke = {
            param($CommandName,$OperationName,$Configuration,$Execute,$ReadAuth,$WriteAuth,$WhatIf)
            $parameters = @{ SamAccountName='fixture.user'; Configuration=$Configuration; Execute=[bool]$Execute; AllowRealRead=[bool]$ReadAuth; AllowRealWrite=[bool]$WriteAuth; Confirm=$false }
            if ($WhatIf) { $parameters.WhatIf=$true }
            & $CommandName @parameters
        }
        $evidence = [System.Collections.Generic.List[object]]::new()
        $passed = 0; $total = 0
        foreach ($operation in $operations) {
            foreach ($definition in $definitions) {
                $total++
                $fixture = New-AdminScenarioFixture -Operation $operation.Name -ScenarioName $definition.Name
                $fixture.User.State=$operation.State
                $fixture.User.Enabled=($operation.State -ne 'Disabled')
                $fixture.User.LockedOut=($operation.State -eq 'LockedOut')
                if ($definition.ContainsKey('Query')) { $fixture.User.QueryStatus=$definition.Query }
                $fixture.OperationResult=New-AdminOperationFixture -QueryStatus Found -MutationFails:([bool]$definition.MutationFails) -AuditFails:([bool]$definition.AuditFails)
                $state.Fixture=$fixture
                $state.Scenario=[pscustomobject]@{ShouldProcess=if($definition.ContainsKey('ShouldProcess')){[bool]$definition.ShouldProcess}else{$true}}
                foreach ($counterName in @($state.Counters.Keys)) { $state.Counters[$counterName]=0 }
                $state.LastMutation=$null
                $simulation = [bool]$definition.Simulation
                $configuration = [pscustomobject]@{
                    SimulationMode=$simulation; DomainController='dc.fixture.invalid'; Domain='fixture.invalid'
                    UserPrincipalName=[pscustomobject]@{Domain='fixture.invalid'}
                    Simulation=[pscustomobject]@{ExistingSamAccountNames=@('fixture.user');LockedSamAccountNames=@('fixture.user');DisabledSamAccountNames=@('fixture.user')}
                }
                $result = & $module $invoke $operation.Command $operation.Name $configuration ([bool]$definition.Execute) ([bool]$definition.Read) ([bool]$definition.Write) ([bool]$definition.WhatIf)
                if ($result -is [array] -or $null -eq $result -or $state.Counters.Unexpected -ne 0 -or (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory)) { throw "FAIL-CLOSED: resultado ou fronteira inválida em $($operation.Name)/$($definition.Name)." }
                $mutationCount=[int]$state.Counters[$operation.Counter]
                $expectedMutation = $definition.Name -in @('AuthorizedExecute','MutationFailure','AuditFailure')
                if ($mutationCount -ne [int]$expectedMutation) { throw "ASSERTION-FAIL:$($operation.Name)/$($definition.Name):mutator-count=$mutationCount" }
                if ($definition.Name -in @('Simulation','WhatIf','NoAuthorization','NoWriteAuthorization','ShouldProcessDeclined')) {
                    if (($state.Counters.GetADUser + $state.Counters.ADImportBlocked + $state.Counters.GetModule) -ne 0) { throw "ASSERTION-FAIL:$($operation.Name)/$($definition.Name):protected-read-counter" }
                }
                if ($definition.Name -eq 'AuthorizedExecute' -and (-not $result.Success -or $null -eq $state.LastMutation -or $state.LastMutation.Command -ne $operation.Mutator)) { throw "ASSERTION-FAIL:$($operation.Name):authorized-result-or-arguments" }
                if ($definition.Name -in @('NotFound','QueryError') -and ($result.Success -or $mutationCount -ne 0)) { throw "ASSERTION-FAIL:$($operation.Name)/$($definition.Name):query-failure" }
                if ($definition.Name -eq 'MutationFailure' -and $result.Success) { throw "ASSERTION-FAIL:$($operation.Name):mutation-failure-result" }
                if ($definition.Name -eq 'AuditFailure' -and ($result.Success -or -not $result.Changed -or $mutationCount -ne 1)) { throw "ASSERTION-FAIL:$($operation.Name):partial-audit-result" }
                if ($definition.Name -eq 'ShouldProcessDeclined' -and (-not $result.Cancelled -or $result.Status -ne 'Cancelled')) { throw "ASSERTION-FAIL:$($operation.Name):cancel-result" }
                if ($definition.Name -eq 'WhatIf' -and ($result.Mode -ne 'Preview' -or $result.Cancelled)) { throw "ASSERTION-FAIL:$($operation.Name):whatif-result" }
                if ($definition.Name -in @('PreviewRead','ReadOnly') -and ($mutationCount -ne 0 -or $state.Counters.GetADUser -lt 1)) { throw "ASSERTION-FAIL:$($operation.Name)/$($definition.Name):read-only-preview" }
                $passed++
                $counterSnapshot=[ordered]@{}
                foreach($counterName in $state.Counters.Keys){$counterSnapshot[$counterName]=$state.Counters[$counterName]}
                $evidence.Add([pscustomobject]@{Operation=$operation.Name;Scenario=$definition.Name;Success=$result.Success;Status=$result.Status;Counters=[pscustomobject]$counterSnapshot;LastMutation=$state.LastMutation;ActiveDirectoryLoaded=$false}) | Out-Null
            }
        }
        $beforeModules=$state.ModuleInstances.Count
        $reimportBlocked=$false
        try { Import-AdminProductionModuleChain -State $state | Out-Null } catch { $reimportBlocked=$true }
        if (-not $reimportBlocked -or $state.ModuleInstances.Count -ne $beforeModules) { throw 'FAIL-CLOSED: reimportação após gate não foi bloqueada antes de substituir instâncias.' }
        $passed++; $total++
        $summary=[pscustomobject]@{Mode='ProductionStubbed';Gate=$gate;Scenarios=@($evidence);ReimportBlocked=$reimportBlocked;ProductionModulesLoaded=$true;RealCalls=0;RepositoryWrites=0;Checks=$passed;Total=$total;Counters=$state.Counters}
        Write-Output ('PRODUCTION_EVIDENCE_JSON:' + ($summary | ConvertTo-Json -Depth 10 -Compress))
        Write-Output ("HARNESS_COMPLETE:PASS passed={0} failed=0 scenarios={1}" -f $passed,$total)
    }
    finally { Restore-AdminProductionImportGuard -State $state }
    return
}
Write-Output 'HARNESS_START:USER_ACTIONS_SYNTHETIC'
Write-Output 'HARNESS_GATE:SYNTHETIC_ONLY_NO_PRODUCTION_IMPORT'
$state = New-AdminHarnessState -ProjectRoot (Split-Path -Parent (Split-Path -Parent $here))
$passed = 0
$failed = 0
$failures = [System.Collections.Generic.List[string]]::new()
$operations = @(
    @{ Name='Unlock'; Counter='Unlock' }, @{ Name='Enable'; Counter='Enable' },
    @{ Name='Disable'; Counter='Disable' }, @{ Name='ForcePasswordChange'; Counter='SetUser' }
)
$scenarios = @(
    @{ Name='SimulationMode'; SimulationMode=$true }, @{ Name='Preview'; Preview=$true },
    @{ Name='WhatIf'; WhatIf=$true }, @{ Name='NoAuthorization'; Execute=$true },
    @{ Name='ReadOnlyAuthorization'; Execute=$true; AllowRealRead=$true },
    @{ Name='InvalidWriteAuthorization'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$false },
    @{ Name='AuthorizedExecute'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$true },
    @{ Name='ShouldProcessDeclined'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$false },
    @{ Name='Cancelled'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$true; Cancelled=$true },
    @{ Name='NotFound'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$true; QueryStatus='NotFound' },
    @{ Name='QueryError'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$true; QueryStatus='Error' },
    @{ Name='MutationFailure'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$true; MutationFails=$true },
    @{ Name='AuditFailureAfterMutation'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$true; AuditFails=$true },
    @{ Name='WrongOperationAuthorization'; Execute=$true; AllowRealRead=$true; AllowRealWrite=$true; WriteAuthorizationValid=$true; ShouldProcess=$true; AuthorizationOperation='Other' }
)
foreach ($operation in $operations) {
    foreach ($definition in $scenarios) {
        $fixture = New-AdminScenarioFixture -Operation $operation.Name -ScenarioName $definition.Name
        $scenario = [ordered]@{
            Operation=$operation.Name; SimulationMode=[bool]$definition.SimulationMode; Preview=[bool]$definition.Preview; WhatIf=[bool]$definition.WhatIf
            Execute=[bool]$definition.Execute; AllowRealRead=[bool]$definition.AllowRealRead; AllowRealWrite=[bool]$definition.AllowRealWrite
            WriteAuthorizationValid=if ($definition.ContainsKey('WriteAuthorizationValid')) { $definition.WriteAuthorizationValid } else { $false }
            AuthorizationOperation=if ($definition.ContainsKey('AuthorizationOperation')) { $definition.AuthorizationOperation } else { $operation.Name }
            ShouldProcess=if ($definition.ContainsKey('ShouldProcess')) { $definition.ShouldProcess } else { $false }
            Cancelled=[bool]$definition.Cancelled
        }
        $gate = Test-AdminSyntheticMutationGate -Scenario ([pscustomobject]$scenario)
        $fixture.OperationResult = New-AdminOperationFixture -QueryStatus $(if ($definition.ContainsKey('QueryStatus')) { $definition.QueryStatus } else { 'Found' }) -MutationFails:([bool]$definition.MutationFails) -AuditFails:([bool]$definition.AuditFails)
        $mutationsBefore = [int]$state.Counters[$operation.Counter]
        $readsBefore = [int]$state.Counters.GetADUser
        $auditBefore = [int]$state.Counters.Audit
        $result = Invoke-AdminSyntheticMutation -State $state -Fixture $fixture.OperationResult -Scenario ([pscustomobject]$scenario) -MutationCounter $operation.Counter
        $expectedAllowed = ($definition.Name -in @('AuthorizedExecute','NotFound','QueryError','MutationFailure','AuditFailureAfterMutation'))
        $ok = ($gate.Allowed -eq $expectedAllowed)
        if ($definition.Name -eq 'NotFound') { $ok = $ok -and $result.Status -eq 'NotFound' -and -not $result.Changed }
        if ($definition.Name -eq 'QueryError') { $ok = $ok -and $result.Status -eq 'Error' -and -not $result.Changed }
        if ($definition.Name -eq 'MutationFailure') { $ok = $ok -and $result.Status -eq 'Error' -and -not $result.Changed }
        if ($definition.Name -eq 'AuditFailureAfterMutation') { $ok = $ok -and $result.Status -eq 'Partial' -and $result.Changed -and $result.Error -like '*rollback não executado*' }
        if ($definition.Name -eq 'AuthorizedExecute') { $ok = $ok -and $result.Status -eq 'Completed' -and $result.Changed }
        if (-not $expectedAllowed) { $ok = $ok -and $result.Status -eq 'Blocked' -and -not $result.Changed }
        $expectedMutationCall = $definition.Name -in @('AuthorizedExecute','MutationFailure','AuditFailureAfterMutation')
        $ok = $ok -and (($state.Counters[$operation.Counter] - $mutationsBefore) -eq [int]$expectedMutationCall)
        $expectedReadCall = $expectedAllowed
        $expectedAuditCall = $definition.Name -in @('AuthorizedExecute','AuditFailureAfterMutation')
        $ok = $ok -and (($state.Counters.GetADUser - $readsBefore) -eq [int]$expectedReadCall)
        $ok = $ok -and (($state.Counters.Audit - $auditBefore) -eq [int]$expectedAuditCall)
        if ($ok) { $passed++ } else { $failed++; $failures.Add($operation.Name + '/' + $definition.Name + ' -> ' + $result.Status) }
    }
}
if ($failed -ne 0) { foreach ($failure in $failures) { Write-Output ('FAIL_CASE:' + $failure) }; Write-Output ("HARNESS_COMPLETE:FAIL passed={0} failed={1}" -f $passed,$failed); exit 1 }
Write-Output ('COUNTERS_JSON:' + ([pscustomobject]@{ GetADUser=$state.Counters.GetADUser; Unlock=$state.Counters.Unlock; Enable=$state.Counters.Enable; Disable=$state.Counters.Disable; SetUser=$state.Counters.SetUser; Audit=$state.Counters.Audit } | ConvertTo-Json -Compress))
Write-Output ("HARNESS_COMPLETE:PASS passed={0} failed=0 scenarios={1}" -f $passed,($operations.Count*$scenarios.Count))
