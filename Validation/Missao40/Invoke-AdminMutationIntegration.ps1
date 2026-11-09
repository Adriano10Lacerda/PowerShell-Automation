#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('All','User','Group','Negative')][string]$Suite = 'All',
    [ValidateSet('SyntheticOnly','ProductionStubbed','InterfaceStubbed')][string]$Mode = 'SyntheticOnly',
    [ValidateRange(5,300)][int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
$harnessRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $harnessRoot)
$jobs = [System.Collections.Generic.List[object]]::new()
if ($Mode -eq 'InterfaceStubbed') {
    $scenarios=@('Simulation','AuthorizationDenied','AuthorizedExecute','ConfirmationDeclined','WriteAuthorizationDenied','ShouldProcessDeclined','NotFound','QueryError')
    if ($Suite -in @('All','User')) {
        foreach($action in @('Unlock','Enable','Disable','ForcePasswordChange')) { foreach($scenario in $scenarios) { $jobs.Add([pscustomobject]@{Script='Test-UserActions.ps1';Mode='InterfaceStubbed';Action=$action;Scenario=$scenario})|Out-Null } }
    }
    if ($Suite -in @('All','Group')) {
        foreach($action in @('Add','Remove')) { foreach($scenario in $scenarios) { $jobs.Add([pscustomobject]@{Script='Test-GroupMutations.ps1';Mode='InterfaceStubbed';Action=$action;Scenario=$scenario})|Out-Null } }
    }
    if ($Suite -eq 'Negative' -or $Suite -eq 'All') { $jobs.Add([pscustomobject]@{Script='Test-Isolation-Negative.ps1';Mode='SyntheticOnly'})|Out-Null }
}
else {
    $childScripts = switch ($Suite) {
        'User' { @('Test-UserActions.ps1') }
        'Group' { @('Test-GroupMutations.ps1') }
        'Negative' { @('Test-Isolation-Negative.ps1') }
        default { @('Test-UserActions.ps1','Test-GroupMutations.ps1','Test-Isolation-Negative.ps1') }
    }
    foreach($scriptName in $childScripts) {
        $childMode=if($Mode -eq 'ProductionStubbed' -and $scriptName -ne 'Test-Isolation-Negative.ps1'){'ProductionStubbed'}else{'SyntheticOnly'}
        $jobs.Add([pscustomobject]@{Script=$scriptName;Mode=$childMode})|Out-Null
    }
}
$results = [System.Collections.Generic.List[object]]::new()
$expectedChecks = @{
    'Test-UserActions.ps1' = if ($Mode -eq 'ProductionStubbed') { 49 } else { 56 }
    'Test-GroupMutations.ps1' = if ($Mode -eq 'ProductionStubbed') { 32 } else { 36 }
    'Test-Isolation-Negative.ps1' = 34
}
$integrityRelativePaths = @(
    'Core/User/Actions/User-Account-Actions.psm1','Core/User/User-Functions.psm1',
    'Core/Group/Management/Group-Management.psm1','Core/Group/Group-Functions.psm1',
    'Core/Audit/Audit-Functions.psm1','10-Interface-V2/Interface-V2-Functions.psm1',
    'Core/User/Actions/Test-User-Account-Actions.ps1','Core/Group/Management/Test-GroupManagement.ps1',
    '10-Interface-V2/Test-Interface-V2.ps1',
    'Validation/Missao40/Invoke-AdminMutationIntegration.ps1','Validation/Missao40/Integration.Common.psm1',
    'Validation/Missao40/Integration.Fixtures.psm1','Validation/Missao40/Test-UserActions.ps1',
    'Validation/Missao40/Test-GroupMutations.ps1','Validation/Missao40/Test-Isolation-Negative.ps1',
    'Validation/Missao40/README.md'
)
$integrityBefore = @{}
foreach ($relativePath in $integrityRelativePaths) {
    $fullPath = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "FAIL-CLOSED: arquivo de integridade ausente: $relativePath" }
    $integrityBefore[$relativePath] = (Get-FileHash -Algorithm SHA256 -LiteralPath $fullPath -ErrorAction Stop).Hash
}
Write-Output ("HARNESS_START:ADMIN_MUTATION suite={0} mode={1}" -f $Suite,$Mode)
foreach ($job in $jobs) {
    $scriptName=$job.Script
    $childMode=$job.Mode
    $scriptPath = [IO.Path]::GetFullPath((Join-Path $harnessRoot $scriptName))
    if (-not $scriptPath.StartsWith(([IO.Path]::GetFullPath($harnessRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'FAIL-CLOSED: script filho fora da raiz.' }
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "FAIL-CLOSED: script filho não existe: $scriptName" }
    $childPowerShell = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $childPowerShell -PathType Leaf)) { throw 'FAIL-CLOSED: executável pwsh do runtime atual não encontrado.' }
    $psi = [Diagnostics.ProcessStartInfo]::new($childPowerShell)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    [void]$psi.ArgumentList.Add('-NoLogo'); [void]$psi.ArgumentList.Add('-NoProfile'); [void]$psi.ArgumentList.Add('-NonInteractive')
    [void]$psi.ArgumentList.Add('-File'); [void]$psi.ArgumentList.Add($scriptPath)
    if ($scriptName -ne 'Test-Isolation-Negative.ps1') { [void]$psi.ArgumentList.Add('-Mode'); [void]$psi.ArgumentList.Add($childMode) }
    if ($childMode -eq 'InterfaceStubbed') {
        [void]$psi.ArgumentList.Add('-InterfaceAction'); [void]$psi.ArgumentList.Add([string]$job.Action)
        [void]$psi.ArgumentList.Add('-InterfaceScenario'); [void]$psi.ArgumentList.Add([string]$job.Scenario)
    }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $psi
    if (-not $process.Start()) { throw "FAIL-CLOSED: não foi possível iniciar $scriptName" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult()
    $startMarker = $stdout -match 'HARNESS_START:'
    $expectedGateMarker = if ($childMode -eq 'ProductionStubbed') { 'HARNESS_GATE:PRODUCTION_MODULE_CHAIN_STUBBED' } elseif ($childMode -eq 'InterfaceStubbed') { 'HARNESS_GATE:INTERFACE_IMPORT_TRANSACTION' } else { 'HARNESS_GATE:SYNTHETIC_ONLY_NO_PRODUCTION_IMPORT' }
    $gateMarker = $stdout -match [regex]::Escape($expectedGateMarker)
    $completeMarker = $stdout -match 'HARNESS_COMPLETE:PASS'
    $counterEvidence = $null
    if ($stdout -match '(?m)^COUNTERS_JSON:(\{[^\r\n]+\})\s*$') {
        try { $counterEvidence = $Matches[1] | ConvertFrom-Json -ErrorAction Stop } catch { $counterEvidence = $null }
    }
    $productionEvidence = $null
    if ($childMode -eq 'ProductionStubbed' -and $stdout -match '(?m)^PRODUCTION_EVIDENCE_JSON:(\{[^\r\n]+\})\s*$') {
        try { $productionEvidence = $Matches[1] | ConvertFrom-Json -ErrorAction Stop } catch { $productionEvidence = $null }
    }
    $interfaceEvidence=$null
    if($childMode -eq 'InterfaceStubbed' -and $stdout -match '(?m)^INTERFACE_EVIDENCE_JSON:(\{[^\r\n]+\})\s*$'){
        try{$interfaceEvidence=$Matches[1]|ConvertFrom-Json -ErrorAction Stop}catch{$interfaceEvidence=$null}
    }
    $moduleLabEvidence = $null
    if ($scriptName -eq 'Test-Isolation-Negative.ps1' -and $stdout -match '(?m)^POWERSHELL_IMPORT_LAB_JSON:(\{[^\r\n]+\})\s*$') {
        try { $moduleLabEvidence = $Matches[1] | ConvertFrom-Json -ErrorAction Stop } catch { $moduleLabEvidence = $null }
    }
    $staticClosureEvidence = $null
    if ($scriptName -eq 'Test-Isolation-Negative.ps1' -and $stdout -match '(?m)^STATIC_CLOSURE_JSON:(\{[^\r\n]+\})\s*$') {
        try { $staticClosureEvidence = $Matches[1] | ConvertFrom-Json -ErrorAction Stop } catch { $staticClosureEvidence = $null }
    }
    $observedChecks = -1
    if ($childMode -eq 'InterfaceStubbed') {
        if($stdout -match 'HARNESS_COMPLETE:PASS checks=(\d+) failed=0'){$observedChecks=[int]$Matches[1]}
        $expectedForInterface=if($job.Script -eq 'Test-UserActions.ps1'){6}else{7}
        if($observedChecks -ne $expectedForInterface){$observedChecks=-1}
    }
    elseif ($scriptName -eq 'Test-Isolation-Negative.ps1') {
        if ($stdout -match 'HARNESS_COMPLETE:PASS checks=(\d+) productionImports=0 externalCalls=0') { $observedChecks = [int]$Matches[1] }
    }
    elseif ($stdout -match 'HARNESS_COMPLETE:PASS passed=(\d+) failed=0 scenarios=(\d+)') {
        $observedChecks = [int]$Matches[1]
        if ([int]$Matches[2] -ne $expectedChecks[$scriptName]) { $observedChecks = -1 }
    }
    if ($childMode -eq 'ProductionStubbed' -and $null -ne $productionEvidence -and
        ($productionEvidence.Mode -ne 'ProductionStubbed' -or -not $productionEvidence.Gate.Passed -or
         $productionEvidence.Checks -ne $expectedChecks[$scriptName] -or $productionEvidence.Total -ne $expectedChecks[$scriptName] -or
         $productionEvidence.RealCalls -ne 0 -or $productionEvidence.RepositoryWrites -ne 0 -or -not $productionEvidence.ReimportBlocked -or
         @($productionEvidence.Scenarios | Where-Object { $_.ActiveDirectoryLoaded -or $_.Counters.Unexpected -ne 0 }).Count -gt 0)) {
        $observedChecks = -1
    }
    $countValid = if($childMode -eq 'InterfaceStubbed'){$observedChecks -eq $expectedForInterface}else{$observedChecks -eq $expectedChecks[$scriptName]}
    $moduleLabValid = $scriptName -ne 'Test-Isolation-Negative.ps1' -or (
        $null -ne $moduleLabEvidence -and $moduleLabEvidence.PowerShell -like '7.*' -and
        $moduleLabEvidence.NestedImportCount -eq 4 -and $moduleLabEvidence.ForceCount -eq 4 -and
        $moduleLabEvidence.ExternalRealCalls -eq 0 -and $moduleLabEvidence.Result -eq 'LAB-EXTERNAL-STUB' -and
        $moduleLabEvidence.ResultAfterForce -eq 'LAB-EXTERNAL-STUB' -and $moduleLabEvidence.UnexpectedImportBlocked
    )
    $staticClosureValid = $scriptName -ne 'Test-Isolation-Negative.ps1' -or (
        $null -ne $staticClosureEvidence -and $staticClosureEvidence.UserModules.Count -eq 3 -and
        $staticClosureEvidence.UserScripts.Count -eq 2 -and $staticClosureEvidence.UserAllowlist.Count -eq 3 -and
        $staticClosureEvidence.GroupModules.Count -eq 3 -and $staticClosureEvidence.GroupScripts.Count -eq 2 -and
        $staticClosureEvidence.GroupAllowlist.Count -eq 3 -and $staticClosureEvidence.UnauthorizedImportBlockedBeforeLoader -and
        -not $staticClosureEvidence.ProductionModulesLoaded -and $staticClosureEvidence.ExternalCalls -eq 0 -and
        @($staticClosureEvidence.UserExternalImports | Where-Object Name -ne 'ActiveDirectory').Count -eq 0 -and
        @($staticClosureEvidence.GroupExternalImports | Where-Object Name -ne 'ActiveDirectory').Count -eq 0
    )
    $interfaceValid=$true
    if($childMode -eq 'InterfaceStubbed'){
        $expectedCounter=if($job.Action -in @('Add','Remove')){if($job.Action -eq 'Add'){'AddGroupMember'}else{'RemoveGroupMember'}}else{switch($job.Action){Unlock{'Unlock'}Enable{'Enable'}Disable{'Disable'}ForcePasswordChange{'SetUser'}}}
        $expectedMutation=$job.Scenario -eq 'AuthorizedExecute'
        $observedMutation=-1
        if($null -ne $interfaceEvidence -and $null -ne $interfaceEvidence.Counters.PSObject.Properties[$expectedCounter]){$observedMutation=[int]$interfaceEvidence.Counters.PSObject.Properties[$expectedCounter].Value}
        $interfaceRoleCount=if($null -ne $interfaceEvidence){@($interfaceEvidence.Modules|Where-Object Role -in @('Interface','Core','Audit')).Count}else{0}
        $interfaceValid=$null -ne $interfaceEvidence -and $interfaceEvidence.GatePassed -and $interfaceEvidence.ReferencesValidated -and $interfaceEvidence.CapturedReferences -ge 4 -and -not $interfaceEvidence.ADLoaded -and $interfaceEvidence.RealExternalCalls -eq 0 -and $interfaceEvidence.Checks -eq $expectedForInterface -and $interfaceEvidence.Counters.Unexpected -eq 0 -and $observedMutation -eq [int]$expectedMutation -and $interfaceRoleCount -eq 3
        if($interfaceValid -and $expectedMutation){$interfaceValid=$null -ne $interfaceEvidence.LastMutation -and $interfaceEvidence.LastMutation.Command -in @('Unlock-ADAccount','Enable-ADAccount','Disable-ADAccount','Set-ADUser','Add-ADGroupMember','Remove-ADGroupMember')}
        if(-not $interfaceValid){Write-Output ("INTERFACE_GATE_VALIDATION:Evidence={0} Gate={1} AD={2} Real={3} Checks={4}/{5} Unexpected={6} Mutation={7}/{8} Roles={9}" -f ($null -ne $interfaceEvidence),$interfaceEvidence.GatePassed,$interfaceEvidence.ADLoaded,$interfaceEvidence.RealExternalCalls,$interfaceEvidence.Checks,$expectedForInterface,$interfaceEvidence.Counters.Unexpected,$observedMutation,[int]$expectedMutation,$interfaceRoleCount)}
    }
    $evidenceValid = if ($childMode -eq 'ProductionStubbed') { $null -ne $productionEvidence } elseif($childMode -eq 'InterfaceStubbed'){$interfaceValid} else { $null -ne $counterEvidence }
    $status = if (-not $timedOut -and $process.ExitCode -eq 0 -and $startMarker -and $gateMarker -and $completeMarker -and $countValid -and $evidenceValid -and $moduleLabValid -and $staticClosureValid) { 'PASS' } elseif ($timedOut) { 'BLOCKED' } else { 'FAIL' }
    $childExitCode = if ($timedOut) { $null } else { $process.ExitCode }
    $results.Add([pscustomobject]@{ Script=$scriptName; Mode=$childMode; Action=$job.Action; Scenario=$job.Scenario; Status=$status; ExitCode=$childExitCode; Start=$startMarker; Gate=$gateMarker; Complete=$completeMarker; Checks=$observedChecks; Counters=$counterEvidence; ProductionEvidence=$productionEvidence; InterfaceEvidence=$interfaceEvidence; PowerShellImportLab=$moduleLabEvidence; StaticClosure=$staticClosureEvidence; TimedOut=$timedOut; StdOut=$stdout; StdErr=$stderr })
    Write-Output ("CHILD:{0} ACTION={1} SCENARIO={2} STATUS={3} EXIT={4} CHECKS={5} START={6} GATE={7} COMPLETE={8} TIMEOUT={9}" -f $scriptName,$job.Action,$job.Scenario,$status,$childExitCode,$observedChecks,$startMarker,$gateMarker,$completeMarker,$timedOut)
    $process.Dispose()
    if ($status -ne 'PASS') { Write-Output $stdout; if ($stderr) { [Console]::Error.WriteLine($stderr) }; throw "FAIL-CLOSED: child não aprovou: $scriptName" }
}
$integrityChanged = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in $integrityRelativePaths) {
    $fullPath = Join-Path $projectRoot $relativePath
    $hashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $fullPath -ErrorAction Stop).Hash
    if ($hashAfter -ne $integrityBefore[$relativePath]) { $integrityChanged.Add($relativePath) }
}
if ($integrityChanged.Count -gt 0) { throw ('FAIL-CLOSED: hashes alterados durante a regressão: ' + ($integrityChanged -join ', ')) }
$summary = [pscustomobject]@{ Mode=$Mode; Suite=$Suite; Results=@($results); ChecksTotal=($results | Measure-Object -Property Checks -Sum).Sum; IntegrityFilesChecked=$integrityRelativePaths.Count; IntegrityChanged=@($integrityChanged); ProductionModulesLoaded=($Mode -eq 'ProductionStubbed' -and $Suite -ne 'Negative'); RealInfrastructureCalls=0; RepositoryWrites=0 }
Write-Output ('EVIDENCE_JSON:' + ($summary | ConvertTo-Json -Depth 8 -Compress))
Write-Output ("HARNESS_COMPLETE:PASS children={0} mode={1}" -f $results.Count,$Mode)
