$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    try {
        & $Action
        $script:Passed++
        Write-Host "PASS: $Name" -ForegroundColor Green
    }
    catch {
        $script:Failed++
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "FAIL: $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter()][string]$MessagePattern = '.'
    )
    $thrown = $false
    try { & $Action } catch {
        $thrown = $true
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw "Unexpected error message: $($_.Exception.Message)"
        }
    }
    if (-not $thrown) { throw 'Expected an exception, but none was thrown.' }
}

function Get-ActiveSimulationModule {
    $module = $script:SimulationModeModule
    if ($null -eq $module) { throw 'The SimulationMode PSModuleInfo reference was not retained.' }
    $instanceId = $module.SessionState.PSVariable.GetValue('ModuleInstanceId')
    foreach ($commandName in @('Get-AutomationExecutionContext','Start-AutomationWriteOperation',
            'Assert-AutomationWriteAuthorized','Complete-AutomationWriteStep',
            'Complete-AutomationWriteOperation','Abort-AutomationWriteOperation')) {
        if (-not $module.ExportedFunctions.ContainsKey($commandName)) {
            throw "The retained SimulationMode instance does not export '$commandName'."
        }
    }
    return $module
}

function Get-SimulationModuleForContext {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter()][System.Management.Automation.PSModuleInfo]$Module
    )

    if ($null -eq $Module) { $Module = Get-ActiveSimulationModule }

    $instanceId = $module.SessionState.PSVariable.GetValue('ModuleInstanceId')
    if ($Context.ModuleInstanceId -cne $instanceId) {
        throw 'The context and active command belong to different module instances.'
    }

    $registry = $module.SessionState.PSVariable.GetValue('OperationRegistry')
    if ($registry -isnot [System.Collections.IDictionary] -or
        -not $registry.ContainsKey($Context.OperationId)) {
        throw 'The operation record is not present in the active module instance.'
    }

    $record = $registry[$Context.OperationId]
    if ($null -eq $record -or -not [object]::ReferenceEquals($Context, $record.Context)) {
        throw 'The operation record does not belong to this context instance.'
    }
    return $module
}

function Get-PrivateOperationRecordForTest {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSModuleInfo]$Module
    )

    $instanceId = $Module.SessionState.PSVariable.GetValue('ModuleInstanceId')
    if ($Context.ModuleInstanceId -cne $instanceId) {
        throw 'Refusing to inspect a record from a different module instance.'
    }
    $registry = $Module.SessionState.PSVariable.GetValue('OperationRegistry')
    if ($registry -isnot [System.Collections.IDictionary] -or
        -not $registry.ContainsKey($Context.OperationId)) {
        throw "No private operation record exists for '$($Context.OperationId)'."
    }
    $record = $registry[$Context.OperationId]
    if ($null -eq $record -or -not [object]::ReferenceEquals($Context, $record.Context)) {
        throw 'The private operation record is not bound to the supplied context.'
    }
    return $record
}

function Set-SimulationTestClock {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.PSModuleInfo]$Module,
        [Parameter(Mandatory = $true)][scriptblock]$Provider
    )
    $Module.SessionState.PSVariable.Set('ClockProvider', $Provider)
}

function Reset-SimulationTestClock {
    param([Parameter(Mandatory = $true)][System.Management.Automation.PSModuleInfo]$Module)
    $Module.SessionState.PSVariable.Set('ClockProvider', { [System.Diagnostics.Stopwatch]::GetTimestamp() })
}

function Invoke-SimulationModuleCommand {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.PSModuleInfo]$Module,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Parameters
    )

    $functionInfo = $Module.ExportedFunctions[$Name]
    if ($null -eq $functionInfo) { throw "Module instance does not export '$Name'." }
    $boundScriptBlock = $Module.NewBoundScriptBlock($functionInfo.ScriptBlock)
    & $boundScriptBlock @Parameters
}

$modulePath = Join-Path $PSScriptRoot 'SimulationMode-Functions.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "SimulationMode helper not found: $modulePath"
}

$script:SimulationModeModule = Import-Module -Name $modulePath -Scope Local -PassThru -ErrorAction Stop
$simulation = [PSCustomObject]@{ SimulationMode = $true }
$real = [PSCustomObject]@{ SimulationMode = $false }

# Route the suite through the retained PSModuleInfo. This prevents commands
# exported by fixtures or another module instance from changing test routing.
function Get-AutomationExecutionContext {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Configuration)
    Invoke-SimulationModuleCommand -Module $script:SimulationModeModule `
        -Name 'Get-AutomationExecutionContext' -Parameters $PSBoundParameters
}

function Start-AutomationWriteOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Configuration,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OperationName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Steps,
        [Parameter()][switch]$Execute
    )
    Invoke-SimulationModuleCommand -Module $script:SimulationModeModule `
        -Name 'Start-AutomationWriteOperation' -Parameters $PSBoundParameters
}

function Assert-AutomationWriteAuthorized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target
    )
    Invoke-SimulationModuleCommand -Module $script:SimulationModeModule `
        -Name 'Assert-AutomationWriteAuthorized' -Parameters $PSBoundParameters
}

function Complete-AutomationWriteStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][PSCustomObject]$Permit,
        [Parameter(Mandatory = $true)][object]$Succeeded,
        [Parameter(Mandatory = $true)][object]$Changed,
        [Parameter()][AllowEmptyString()][string]$ErrorMessage = ''
    )
    Invoke-SimulationModuleCommand -Module $script:SimulationModeModule `
        -Name 'Complete-AutomationWriteStep' -Parameters $PSBoundParameters
}

function Complete-AutomationWriteOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][PSCustomObject]$Context)
    Invoke-SimulationModuleCommand -Module $script:SimulationModeModule `
        -Name 'Complete-AutomationWriteOperation' -Parameters $PSBoundParameters
}

function Abort-AutomationWriteOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Failed','Interrupted','Cancelled','Incomplete')][string]$Reason,
        [Parameter()][AllowEmptyString()][string]$ErrorMessage = ''
    )
    Invoke-SimulationModuleCommand -Module $script:SimulationModeModule `
        -Name 'Abort-AutomationWriteOperation' -Parameters $PSBoundParameters
}

Assert-Check 'same-process module state is reachable and limitation is documented' {
    $module = Get-ActiveSimulationModule
    $registry = $module.SessionState.PSVariable.GetValue('OperationRegistry')
    if ($registry -isnot [System.Collections.IDictionary]) { throw 'Expected this same-process state to be inspectable for the documented limitation.' }
    $source = Get-Content -LiteralPath $modulePath -Raw
    $normalizedSource = $source -replace '(?m)^[ \t]*#[ \t]?', '' -replace '[\r\n]+', ' '
    if ($normalizedSource -notmatch 'not isolated from arbitrary code running in the same PowerShell process') { throw 'Same-process limitation is not documented.' }
}

Assert-Check 'reentrant public calls are rejected' {
    $configuration = [PSCustomObject]@{}
    $script:ReentrantAttemptBlocked = $false
    $script:ReentrantAttemptSucceeded = $false
    $configuration | Add-Member -MemberType ScriptProperty -Name SimulationMode -Value {
        try {
            $null = Get-AutomationExecutionContext -Configuration @{ SimulationMode = $false }
            $script:ReentrantAttemptSucceeded = $true
        }
        catch {
            if ($_.Exception.Message -match 'Reentrant') { $script:ReentrantAttemptBlocked = $true }
            else { throw }
        }
        return $false
    }
    $null = Get-AutomationExecutionContext -Configuration $configuration
    if (-not $script:ReentrantAttemptBlocked -or $script:ReentrantAttemptSucceeded) {
        throw 'The nested public call was not explicitly rejected.'
    }
}

Assert-Check 'valid Boolean configuration: simulation context is offline' {
    $context = Get-AutomationExecutionContext -Configuration $simulation
    if ($context.AccessLevel -ne 'Simulation' -or $context.Outcome -ne 'Simulated' -or
        $context.ExternalReadAllowed -or $context.ExternalWriteAllowed) {
        throw 'Simulation context grants external access.'
    }
}

Assert-Check 'valid Boolean configuration: ReadOnly context permits reads only' {
    $context = Get-AutomationExecutionContext -Configuration $real
    if ($context.AccessLevel -ne 'ReadOnly' -or $context.Outcome -ne 'ReadOnly' -or
        -not $context.ExternalReadAllowed -or $context.ExternalWriteAllowed) {
        throw 'ReadOnly context has incorrect permissions.'
    }
}

Assert-Check 'simulation and ReadOnly context tampering is detected' {
    $simContext = Get-AutomationExecutionContext -Configuration $simulation
    $readContext = Get-AutomationExecutionContext -Configuration $real
    $simContext.ExternalWriteAllowed = $true
    $readContext.AccessLevel = 'Write'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $simContext -StepName 'x' -Target 'x' } 'altered'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $readContext -StepName 'x' -Target 'x' } 'altered'
}

Assert-Check 'operation and context identifiers are unique GUIDs' {
    $a = Get-AutomationExecutionContext -Configuration $real
    $b = Get-AutomationExecutionContext -Configuration $real
    if ($a.OperationId -eq $b.OperationId -or $a.ContextId -eq $b.ContextId) { throw 'Generated identifiers were reused.' }
    if ($a.OperationId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw 'OperationId is not a GUID.' }
}

Assert-Check 'missing SimulationMode is rejected' {
    Assert-Throws { Get-AutomationExecutionContext -Configuration ([PSCustomObject]@{ Other = $true }) } 'required'
}

Assert-Check 'null SimulationMode is rejected' {
    Assert-Throws { Get-AutomationExecutionContext -Configuration ([PSCustomObject]@{ SimulationMode = $null }) } 'Boolean'
}

Assert-Check 'string SimulationMode is rejected without conversion' {
    Assert-Throws { Get-AutomationExecutionContext -Configuration ([PSCustomObject]@{ SimulationMode = 'false' }) } 'Boolean'
}

Assert-Check 'numeric SimulationMode is rejected without conversion' {
    Assert-Throws { Get-AutomationExecutionContext -Configuration ([PSCustomObject]@{ SimulationMode = 0 }) } 'Boolean'
}

Assert-Check 'hashtable configuration is supported, but mode remains strict' {
    $context = Get-AutomationExecutionContext -Configuration @{ SimulationMode = $true }
    if ($context.AccessLevel -ne 'Simulation') { throw 'Hashtable configuration was not read.' }
    Assert-Throws { Get-AutomationExecutionContext -Configuration @{ SimulationMode = 'true' } } 'Boolean'
}

Assert-Check 'write without Execute is Preview and cannot be authorized' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'TestWrite' `
        -Target 'target-a' -Steps @('StepA')
    if ($context.AccessLevel -ne 'ReadOnly' -or $context.Outcome -ne 'Preview' -or
        $context.ExternalWriteAllowed) { throw 'Write without Execute was not reduced to Preview.' }
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' }
}

Assert-Check 'Execute cannot turn simulation into a real write' {
    $context = Start-AutomationWriteOperation -Configuration $simulation -OperationName 'TestWrite' `
        -Target 'target-a' -Steps @('StepA') -Execute
    if ($context.AccessLevel -ne 'Simulation' -or $context.ExternalReadAllowed -or
        $context.ExternalWriteAllowed) { throw 'Simulation granted external access.' }
}

Assert-Check 'write authorization requires Execute and explicit false mode' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'TestWrite' `
        -Target 'target-a' -Steps @('StepA') -Execute
    if ($context.AccessLevel -ne 'Write' -or $context.Outcome -ne 'WriteAuthorized' -or
        -not $context.ExternalWriteAllowed) { throw 'Write context was not authorized.' }
}

Assert-Check 'step order and target binding are enforced' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'OrderedWrite' `
        -Target 'target-a' -Steps @('First','Second') -Execute
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'Second' -Target 'target-a' } 'next'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-b' } 'target'
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $true | Out-Null
    $next = Assert-AutomationWriteAuthorized -Context $context -StepName 'Second' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $next -Succeeded $true -Changed $false | Out-Null
    $result = Complete-AutomationWriteOperation -Context $context
    if (-not $result.Success -or -not $result.Executed -or -not $result.Changed -or
        $result.Outcome -ne 'Completed') { throw 'Successful operation result is incorrect.' }
}

Assert-Check 'permit alteration, reuse, and cross-target use are rejected' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'PermitWrite' `
        -Target 'target-a' -Steps @('StepA','StepB') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    $permit.Target = 'target-b'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit `
        -Succeeded $true -Changed $true } 'invalid'
    $permit.Target = 'target-a'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $true } 'unknown|expired'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'unknown|expired'

    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'PermitReuse' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $true | Out-Null
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit `
        -Succeeded $true -Changed $true } 'consumed|invalid'
}

Assert-Check 'permits cannot cross operations, steps, or targets' {
    $a = Start-AutomationWriteOperation -Configuration $real -OperationName 'CrossA' -Target 'target-a' -Steps @('First','Second') -Execute
    $permitA = Assert-AutomationWriteAuthorized -Context $a -StepName 'First' -Target 'target-a'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $a -StepName 'Second' -Target 'target-a' } 'previous|next'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $a -StepName 'First' -Target 'target-b' } 'target'

    $b = Start-AutomationWriteOperation -Configuration $real -OperationName 'CrossB' -Target 'target-a' -Steps @('First') -Execute
    $permitB = Assert-AutomationWriteAuthorized -Context $b -StepName 'First' -Target 'target-a'
    Assert-Throws { Complete-AutomationWriteStep -Context $b -Permit $permitA -Succeeded $true -Changed $false } 'another operation context'

    # A cross-operation attempt must reject without revoking either legitimate
    # permit. Both operations must still complete through their own permits.
    Complete-AutomationWriteStep -Context $b -Permit $permitB -Succeeded $true -Changed $false | Out-Null
    $resultB = Complete-AutomationWriteOperation -Context $b
    if (-not $resultB.Success -or $resultB.OperationId -cne $b.OperationId) {
        throw 'Operation B was damaged by the cross-operation permit attempt.'
    }

    Complete-AutomationWriteStep -Context $a -Permit $permitA -Succeeded $true -Changed $false | Out-Null
    $permitA2 = Assert-AutomationWriteAuthorized -Context $a -StepName 'Second' -Target 'target-a'
    Complete-AutomationWriteStep -Context $a -Permit $permitA2 -Succeeded $true -Changed $false | Out-Null
    $resultA = Complete-AutomationWriteOperation -Context $a
    if (-not $resultA.Success -or $resultA.OperationId -cne $a.OperationId) {
        throw 'Operation A or its legitimate permit was damaged by the cross-operation attempt.'
    }

    $c = Start-AutomationWriteOperation -Configuration $real -OperationName 'CrossStep' -Target 'target-a' -Steps @('First','Second') -Execute
    $permitC = Assert-AutomationWriteAuthorized -Context $c -StepName 'First' -Target 'target-a'
    $permitC.StepName = 'Second'
    Assert-Throws { Complete-AutomationWriteStep -Context $c -Permit $permitC -Succeeded $true -Changed $false } 'invalid'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $c -StepName 'First' -Target 'target-a' } 'unknown|expired'
}

Assert-Check 'altered permit status is detected before cross-context rejection and invalidates only its owner' {
    $a = Start-AutomationWriteOperation -Configuration $real -OperationName 'AlteredStatusA' `
        -Target 'target-a' -Steps @('First','Second') -Execute
    $permitA = Assert-AutomationWriteAuthorized -Context $a -StepName 'First' -Target 'target-a'

    $b = Start-AutomationWriteOperation -Configuration $real -OperationName 'AlteredStatusB' `
        -Target 'target-a' -Steps @('First') -Execute
    $permitB = Assert-AutomationWriteAuthorized -Context $b -StepName 'First' -Target 'target-a'

    $permitA.Status = 'Tampered'
    Assert-Throws {
        Complete-AutomationWriteStep -Context $b -Permit $permitA -Succeeded $true -Changed $false
    } 'invalid|altered'

    # A's altered permit and operation are revoked, even though the attempt
    # supplied B's otherwise valid context.
    Assert-Throws {
        Complete-AutomationWriteStep -Context $a -Permit $permitA -Succeeded $true -Changed $false
    } 'unknown|expired'
    Assert-Throws {
        Assert-AutomationWriteAuthorized -Context $a -StepName 'Second' -Target 'target-a'
    } 'unknown|expired'
    Assert-Throws {
        Complete-AutomationWriteStep -Context $b -Permit $permitA -Succeeded $true -Changed $false
    } 'unknown|consumed'

    # B's own permit remains valid; the failed cross-context call cannot alter B.
    Complete-AutomationWriteStep -Context $b -Permit $permitB -Succeeded $true -Changed $false | Out-Null
    $resultB = Complete-AutomationWriteOperation -Context $b
    if (-not $resultB.Success -or $resultB.OperationId -cne $b.OperationId) {
        throw 'Operation B was damaged by detection of A permit tampering.'
    }
}

Assert-Check 'operation cannot be completed without valid permits for every step' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'NoPermitCompletion' `
        -Target 'target-a' -Steps @('StepA') -Execute
    Assert-Throws { Complete-AutomationWriteOperation -Context $context } 'pending or failed'
    $fakePermit = [PSCustomObject]@{ PermitId=[guid]::NewGuid().ToString('D'); OperationId=$context.OperationId; StepName='StepA'; Target='target-a'; Status='Authorized' }
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $fakePermit -Succeeded $true -Changed $true } 'unknown|consumed'
    Assert-Throws { Complete-AutomationWriteOperation -Context $context } 'pending or failed'
}

Assert-Check 'altered context is rejected' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'TamperTest' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $context.Outcome = 'Preview'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'altered'
    Assert-Throws { Abort-AutomationWriteOperation -Context $context -Reason Cancelled } 'unknown|expired'
}

Assert-Check 'context integrity is checked before invalid result values' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'TamperBeforeBoolean' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    $context.Target = 'changed-target'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded 'true' -Changed $false } 'altered'
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'unknown|expired'
}

Assert-Check 'altered and foreign ModuleInstanceId contexts are rejected' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'TamperModuleId' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $localModule = Get-SimulationModuleForContext -Context $context
    $localModuleId = $localModule.SessionState.PSVariable.GetValue('ModuleInstanceId')
    $context.ModuleInstanceId = [guid]::NewGuid().ToString('D')
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'another module instance'

    $foreignModuleName = 'SimulationModeIsolationTest_' + [guid]::NewGuid().ToString('N')
    $moduleSource = [System.IO.File]::ReadAllText($modulePath)
    $foreignModule = New-Module -AsCustomObject -Name $foreignModuleName `
        -ScriptBlock ([scriptblock]::Create($moduleSource))
    $foreign = $foreignModule.'Start-AutomationWriteOperation'(
        $real, 'ForeignInstance', 'target-a', [string[]]@('StepA'), $true
    )
    if ($foreign.AccessLevel -ne 'Write' -or $foreign.Outcome -ne 'WriteAuthorized') {
        throw 'The foreign instance fixture did not produce a valid write context.'
    }
    $foreignModuleId = $foreign.ModuleInstanceId
    if ([string]::IsNullOrWhiteSpace($foreignModuleId) -or $foreignModuleId -ceq $localModuleId) {
        throw 'New-Module did not create a context with a distinct ModuleInstanceId.'
    }
    $foreignPermit = $foreignModule.'Assert-AutomationWriteAuthorized'(
        $foreign, 'StepA', 'target-a'
    )
    if ($foreignPermit.OperationId -cne $foreign.OperationId) {
        throw 'The distinct New-Module instance did not authorize its own write context.'
    }
    $null = $foreignModule.'Abort-AutomationWriteOperation'($foreign, 'Cancelled')

    # These test wrappers dispatch to the PSModuleInfo retained by Import-Module -PassThru.
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $foreign -StepName 'StepA' -Target 'target-a' } 'another module instance'
}

Assert-Check 'altered visible steps fail closed and invalidate permits' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'TamperSteps' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    $context.Steps[0].Name = 'Altered'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $false } 'altered'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $false } 'unknown|expired'
}

Assert-Check 'Boolean step results reject coercible strings' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'StrictBoolean' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded 'true' -Changed $false } 'Boolean'
    $null = Abort-AutomationWriteOperation -Context $context -Reason Interrupted
}

Assert-Check 'expired operation IDs are rejected and permits are invalidated' {
    $module = Get-ActiveSimulationModule
    $clock = [PSCustomObject]@{ Ticks = [long]700000 }
    $provider = { $clock.Ticks }.GetNewClosure()
    Set-SimulationTestClock -Module $module -Provider $provider
    try {
        $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'Expire' `
            -Target 'target-a' -Steps @('First','Second') -Execute
        $contextModule = Get-SimulationModuleForContext -Context $context
        $record = Get-PrivateOperationRecordForTest -Context $context -Module $contextModule
        if ($null -ne $record.ActivePermitId) { throw 'A new operation unexpectedly has an active permit.' }

        $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-a'
        $record = Get-PrivateOperationRecordForTest -Context $context -Module $contextModule
        if ($record.ActivePermitId -cne $permit.PermitId) { throw 'The issued permit is not registered as active.' }
        Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $false | Out-Null
        $record = Get-PrivateOperationRecordForTest -Context $context -Module $contextModule
        if ($null -ne $record.ActivePermitId) { throw 'A completed step left a permit active.' }

        $clock.Ticks += [long]([TimeSpan]::FromMinutes(30).TotalSeconds * [System.Diagnostics.Stopwatch]::Frequency)
        $null = Get-AutomationExecutionContext -Configuration $real
        Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'Second' -Target 'target-a' } 'unknown|expired'

        $other = Start-AutomationWriteOperation -Configuration $real -OperationName 'AfterExpiry' `
            -Target 'target-a' -Steps @('StepA') -Execute
        Assert-Throws { Complete-AutomationWriteStep -Context $other -Permit $permit `
            -Succeeded $true -Changed $false } 'unknown|consumed'
    }
    finally { Reset-SimulationTestClock -Module $module }
}

Assert-Check 'active permit prevents inactivity expiration' {
    $module = Get-ActiveSimulationModule
    $clock = [PSCustomObject]@{ Ticks = [long]900000 }
    $provider = { $clock.Ticks }.GetNewClosure()
    Set-SimulationTestClock -Module $module -Provider $provider
    try {
        $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'ActivePermitExpiry' `
            -Target 'target-a' -Steps @('StepA') -Execute
        $contextModule = Get-SimulationModuleForContext -Context $context
        $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
        $record = Get-PrivateOperationRecordForTest -Context $context -Module $contextModule
        if ($record.ActivePermitId -cne $permit.PermitId) { throw 'The active permit was not registered.' }

        $clock.Ticks += [long]([TimeSpan]::FromMinutes(31).TotalSeconds * [System.Diagnostics.Stopwatch]::Frequency)
        $null = Get-AutomationExecutionContext -Configuration $real
        $record = Get-PrivateOperationRecordForTest -Context $context -Module $contextModule
        if ($record.ActivePermitId -cne $permit.PermitId) { throw 'Expiration removed an active permit.' }
        Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $false | Out-Null
        $null = Complete-AutomationWriteOperation -Context $context
    }
    finally { Reset-SimulationTestClock -Module $module }
}

Assert-Check 'valid activity at 30 minutes minus one tick renews expiry and exactly 30 inactive minutes expires' {
    $module = Get-ActiveSimulationModule
    $clock = [PSCustomObject]@{ Ticks = [long]100000 }
    $provider = { $clock.Ticks }.GetNewClosure()
    Set-SimulationTestClock -Module $module -Provider $provider
    try {
        $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'ExactExpiry' `
            -Target 'target-a' -Steps @('StepA') -Execute
        $contextModule = Get-SimulationModuleForContext -Context $context
        $timeoutTicks = [long]([TimeSpan]::FromMinutes(30).TotalSeconds * [System.Diagnostics.Stopwatch]::Frequency)
        $clock.Ticks += $timeoutTicks - 1
        $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
        Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $false | Out-Null
        $clock.Ticks += $timeoutTicks - 1
        $null = Get-AutomationExecutionContext -Configuration $real
        $clock.Ticks += 1
        $null = Get-AutomationExecutionContext -Configuration $real
        Assert-Throws { Complete-AutomationWriteOperation -Context $context } 'unknown|expired'
    }
    finally {
        Reset-SimulationTestClock -Module $module
    }
}

Assert-Check 'invalid target attempts do not renew operation inactivity' {
    $module = Get-ActiveSimulationModule
    $clock = [PSCustomObject]@{ Ticks = [long]500000 }
    $provider = { $clock.Ticks }.GetNewClosure()
    Set-SimulationTestClock -Module $module -Provider $provider
    try {
        $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'InvalidAttemptExpiry' `
            -Target 'target-a' -Steps @('StepA') -Execute
        $contextModule = Get-SimulationModuleForContext -Context $context
        $record = Get-PrivateOperationRecordForTest -Context $context -Module $contextModule
        $activityBefore = $record.LastActivityTimestamp
        $timeoutTicks = [long]([TimeSpan]::FromMinutes(30).TotalSeconds * [System.Diagnostics.Stopwatch]::Frequency)
        $clock.Ticks += $timeoutTicks - 1
        Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'wrong-target' } 'target'
        $record = Get-PrivateOperationRecordForTest -Context $context -Module $contextModule
        if ($record.LastActivityTimestamp -ne $activityBefore) { throw 'An invalid target attempt renewed operation activity.' }
        $clock.Ticks += 1
        $null = Get-AutomationExecutionContext -Configuration $real
        Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'unknown|expired'
    }
    finally {
        Reset-SimulationTestClock -Module $module
    }
}

Assert-Check 'failure before any completed step reports no confirmed execution' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'FailEarly' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $false `
        -Changed $false -ErrorMessage 'Known failure without change' | Out-Null
    $result = Abort-AutomationWriteOperation -Context $context -Reason Failed -ErrorMessage 'Failed'
    if ($result.Outcome -ne 'Failed' -or $result.Status -ne 'FailedNoChanges' -or
        $result.Success -or $result.Executed -or $result.Changed -or $result.EffectsUnknown) {
        throw 'Failure without confirmed changes was misreported.'
    }
}

Assert-Check 'a failed step prevents authorization of later steps' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'NoAdvanceAfterFailure' `
        -Target 'target-a' -Steps @('First','Second') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $false -Changed $false -ErrorMessage 'failure' | Out-Null
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'Second' -Target 'target-a' } 'failed step'
    $null = Abort-AutomationWriteOperation -Context $context -Reason Failed
}

Assert-Check 'failure after confirmed change reports PartialFailure' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'FailLate' `
        -Target 'target-a' -Steps @('First','Second') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $true | Out-Null
    $result = Abort-AutomationWriteOperation -Context $context -Reason Failed -ErrorMessage 'Second failed'
    if ($result.Outcome -ne 'PartialFailure' -or $result.Status -ne 'FailedAfterChanges' -or
        $result.Success -or -not $result.Executed -or -not $result.Changed) {
        throw 'Partial failure was misreported.'
    }
}

Assert-Check 'cancel before writes reports CancelledNoChanges' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'Cancel' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $result = Abort-AutomationWriteOperation -Context $context -Reason Cancelled
    if ($result.Outcome -ne 'Cancelled' -or $result.Status -ne 'CancelledNoChanges' -or
        $result.Success -or $result.Executed -or $result.Changed -or $result.EffectsUnknown) {
        throw 'Cancellation without changes was misreported.'
    }
}

Assert-Check 'cancel after a confirmed change reports PartialFailure' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'CancelLate' `
        -Target 'target-a' -Steps @('First','Second') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $true | Out-Null
    $result = Abort-AutomationWriteOperation -Context $context -Reason Cancelled
    if ($result.Outcome -ne 'PartialFailure' -or $result.Status -ne 'CancelledAfterChanges' -or
        $result.Success -or -not $result.Executed -or -not $result.Changed -or $result.EffectsUnknown) {
        throw 'Cancellation after a confirmed change was misreported.'
    }
}

Assert-Check 'interruption during a write reports unknown effects' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'Interrupt' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $null = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    $result = Abort-AutomationWriteOperation -Context $context -Reason Interrupted
    if ($result.Outcome -ne 'Interrupted' -or $result.Status -ne 'InterruptedUnknownEffects' -or
        $result.Success -or $result.Executed -or $result.Changed -or -not $result.EffectsUnknown) {
        throw 'Unknown interruption was misreported.'
    }
}

Assert-Check 'interruption after confirmed change reports partial failure and unknown effects' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'InterruptLate' `
        -Target 'target-a' -Steps @('First','Second') -Execute
    $first = Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $first -Succeeded $true -Changed $true | Out-Null
    $null = Assert-AutomationWriteAuthorized -Context $context -StepName 'Second' -Target 'target-a'
    $result = Abort-AutomationWriteOperation -Context $context -Reason Interrupted
    if ($result.Outcome -ne 'PartialFailure' -or $result.Status -ne 'InterruptedAfterChanges' -or
        $result.Success -or -not $result.Executed -or -not $result.Changed -or -not $result.EffectsUnknown) {
        throw 'Interruption after a confirmed change was misreported.'
    }
}

Assert-Check 'incomplete operation cannot be completed successfully' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'Incomplete' `
        -Target 'target-a' -Steps @('StepA','StepB') -Execute
    Assert-Throws { Complete-AutomationWriteOperation -Context $context } 'pending or failed'
    $result = Abort-AutomationWriteOperation -Context $context -Reason Incomplete
    if ($result.Outcome -ne 'Incomplete' -or $result.Status -ne 'IncompleteNoChanges' -or $result.Success) {
        throw 'Incomplete operation was misreported.'
    }
}

Assert-Check 'repeated imports without Force preserve active private state' {
    # Import into this test scope, retain that PSModuleInfo, then invoke only through it.
    $moduleBefore = Import-Module -Name $modulePath -Scope Local -PassThru -ErrorAction Stop
    $moduleBeforeId = $moduleBefore.SessionState.PSVariable.GetValue('ModuleInstanceId')
    $context = Invoke-SimulationModuleCommand -Module $moduleBefore -Name 'Start-AutomationWriteOperation' `
        -Parameters @{ Configuration=$real; OperationName='ImportIdempotency'; Target='target-a'; Steps=@('StepA'); Execute=$true }
    $contextModule = Get-SimulationModuleForContext -Context $context -Module $moduleBefore
    $null = Get-PrivateOperationRecordForTest -Context $context -Module $moduleBefore

    $null = Import-Module -Name $modulePath -Scope Local -PassThru -ErrorAction Stop
    $moduleAfter = Import-Module -Name $modulePath -Scope Local -PassThru -ErrorAction Stop
    $moduleAfterId = $moduleAfter.SessionState.PSVariable.GetValue('ModuleInstanceId')
    if ($moduleAfterId -cne $moduleBeforeId -or $context.ModuleInstanceId -cne $moduleAfterId) {
        throw 'Repeated no-Force imports changed the active module instance.'
    }
    $null = Get-PrivateOperationRecordForTest -Context $context -Module $moduleAfter

    $permit = Invoke-SimulationModuleCommand -Module $moduleAfter -Name 'Assert-AutomationWriteAuthorized' `
        -Parameters @{ Context=$context; StepName='StepA'; Target='target-a' }
    $null = Invoke-SimulationModuleCommand -Module $moduleAfter -Name 'Complete-AutomationWriteStep' `
        -Parameters @{ Context=$context; Permit=$permit; Succeeded=$true; Changed=$false }
    $result = Invoke-SimulationModuleCommand -Module $moduleAfter -Name 'Complete-AutomationWriteOperation' `
        -Parameters @{ Context=$context }
    if (-not $result.Success) { throw 'Active operation did not survive repeated import.' }
}

Assert-Check 'operations cannot be reopened or rewritten after final state' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'FinalState' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $false | Out-Null
    $null = Complete-AutomationWriteOperation -Context $context
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'finalized|unknown'
    Assert-Throws { Abort-AutomationWriteOperation -Context $context -Reason Failed } 'finalized|unknown'
}

Assert-Check 'aborted operation and its permits cannot be reused' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'AbortedFinalState' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    $null = Abort-AutomationWriteOperation -Context $context -Reason Cancelled
    Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'unknown|expired'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit `
        -Succeeded $true -Changed $false } 'unknown|expired'
}

Assert-Check 'non-executable contexts cannot authorize, complete, or abort write operations' {
    $contexts = @(
        (Get-AutomationExecutionContext -Configuration $simulation)
        (Get-AutomationExecutionContext -Configuration $real)
        (Start-AutomationWriteOperation -Configuration $simulation -OperationName 'Simulated' -Target 'target-a' -Steps @('StepA'))
        (Start-AutomationWriteOperation -Configuration $simulation -OperationName 'SimulatedExecute' -Target 'target-a' -Steps @('StepA') -Execute)
        (Start-AutomationWriteOperation -Configuration $real -OperationName 'PreviewOnly' -Target 'target-a' -Steps @('StepA'))
    )
    foreach ($context in $contexts) {
        Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a' } 'authorization is not active'
        Assert-Throws { Complete-AutomationWriteOperation -Context $context } 'authorized write operation'
        foreach ($reason in @('Failed','Interrupted','Cancelled','Incomplete')) {
            Assert-Throws { Abort-AutomationWriteOperation -Context $context -Reason $reason } 'authorized write operation'
        }
        if ($context.OperationStatus -eq 'Completed' -or $context.ExternalWriteAllowed) {
            throw 'A non-executable context acquired write completion or authorization.'
        }
    }
}

Assert-Check 'abort matrix distinguishes completed work, confirmed changes, and unknown effects' {
    foreach ($reason in @('Failed','Interrupted','Cancelled','Incomplete')) {
        foreach ($changed in @($false,$true)) {
            foreach ($startSecond in @($false,$true)) {
                $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'AbortMatrix' `
                    -Target 'target-a' -Steps @('First','Second') -Execute
                $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'First' -Target 'target-a'
                Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed $changed | Out-Null
                if ($startSecond) {
                    $null = Assert-AutomationWriteAuthorized -Context $context -StepName 'Second' -Target 'target-a'
                }
                $result = Abort-AutomationWriteOperation -Context $context -Reason $reason
                $expectedOutcome = 'PartialFailure'
                switch ($reason) {
                    'Failed' {
                        $expectedStatus = if ($startSecond) { 'FailedWithUnknownEffects' } elseif ($changed) { 'FailedAfterChanges' } else { 'FailedNoChanges' }
                    }
                    'Interrupted' {
                        $expectedStatus = if ($changed) { 'InterruptedAfterChanges' } elseif ($startSecond) { 'InterruptedUnknownEffects' } else { 'InterruptedNoChanges' }
                    }
                    'Cancelled' {
                        if ($startSecond) { $expectedOutcome = 'Interrupted'; $expectedStatus = 'CancelledWithUnknownEffects' }
                        else { $expectedStatus = if ($changed) { 'CancelledAfterChanges' } else { 'CancelledNoChanges' } }
                    }
                    'Incomplete' {
                        if ($startSecond) { $expectedOutcome = 'Incomplete'; $expectedStatus = 'IncompleteUnknownEffects' }
                        else { $expectedStatus = if ($changed) { 'IncompleteAfterChanges' } else { 'IncompleteNoChanges' } }
                    }
                }
                if ($result.Success -or -not $result.Executed -or $result.Changed -ne $changed -or
                    $result.EffectsUnknown -ne $startSecond -or $result.Outcome -ne $expectedOutcome -or
                    $result.Status -ne $expectedStatus -or ($result.Status -match 'AfterChanges' -and -not $result.Changed)) {
                    throw "Abort matrix mismatch: reason=$reason changed=$changed started=$startSecond."
                }
                Assert-Throws { Complete-AutomationWriteOperation -Context $context } 'unknown|expired'
                Assert-Throws { Assert-AutomationWriteAuthorized -Context $context -StepName 'Second' -Target 'target-a' } 'unknown|expired'
            }
        }
    }
}

Assert-Check 'invalid change reports and cloned permits cannot complete a write step' {
    $context = Start-AutomationWriteOperation -Configuration $real -OperationName 'InvalidChange' `
        -Target 'target-a' -Steps @('StepA') -Execute
    $permit = Assert-AutomationWriteAuthorized -Context $context -StepName 'StepA' -Target 'target-a'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $true -Changed 'false' } 'Boolean'
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $permit -Succeeded $false -Changed $true } 'failed step cannot report a confirmed change'
    $clone = [PSCustomObject]@{
        PermitId=$permit.PermitId; OperationId=$permit.OperationId; StepName=$permit.StepName
        Target=$permit.Target; Status=$permit.Status
    }
    Assert-Throws { Complete-AutomationWriteStep -Context $context -Permit $clone -Succeeded $true -Changed $false } 'registered permit instance'
    Assert-Throws { Complete-AutomationWriteOperation -Context $context } 'active write step'
    $result = Abort-AutomationWriteOperation -Context $context -Reason Failed
    if ($result.Success -or $result.Executed -or $result.Changed -or -not $result.EffectsUnknown) {
        throw 'Rejected result values or a cloned permit confirmed an uncompleted step.'
    }
}

Write-Host "`nSimulationMode isolated test summary: $script:Passed passed; $script:Failed failed." -ForegroundColor Cyan
if ($script:Failed -gt 0) {
    $script:Failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
exit 0
