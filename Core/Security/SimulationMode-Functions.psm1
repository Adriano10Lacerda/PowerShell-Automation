Set-StrictMode -Version Latest

# Security boundary: this module is not isolated from arbitrary code running in
# the same PowerShell process. PSModuleInfo.SessionState and reflection can
# expose or alter module state. Use a separate, access-controlled process/service
# as the authorization authority when the caller is not trusted.
$script:OperationRegistry = @{}
$script:PermitRegistry = @{}
$script:ModuleInstanceId = [guid]::NewGuid().ToString('D')
$script:OperationTimeout = [TimeSpan]::FromMinutes(30)
$script:ClockProvider = { [System.Diagnostics.Stopwatch]::GetTimestamp() }
$script:StateMutex = [System.Threading.Mutex]::new($false, "PowerShellAutomation.SimulationMode.$PID")
$script:ActiveCallThreads = [System.Collections.Generic.HashSet[int]]::new()

function Get-PrivateTimestamp {
    return [long](& $script:ClockProvider)
}

function Set-PrivateActivity {
    param([Parameter(Mandatory = $true)][hashtable]$Record)
    # Only accepted state transitions count as activity. Rejected calls must
    # not keep abandoned operations alive indefinitely.
    $Record.LastActivityTimestamp = Get-PrivateTimestamp
}

function Invoke-PrivateSynchronized {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    $acquired = $false
    $threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
    $entered = $false
    try {
        try { $acquired = $script:StateMutex.WaitOne() }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Unable to acquire the SimulationMode state lock.' }
        if (-not $script:ActiveCallThreads.Add($threadId)) {
            throw 'Reentrant SimulationMode public calls are not permitted.'
        }
        $entered = $true
        & $Action
    }
    finally {
        if ($entered) { $null = $script:ActiveCallThreads.Remove($threadId) }
        if ($acquired) { $script:StateMutex.ReleaseMutex() }
    }
}

function Remove-PrivateOperation {
    param([string]$OperationId)
    if ($script:OperationRegistry.ContainsKey($OperationId)) {
        $script:OperationRegistry.Remove($OperationId)
    }
    foreach ($permitId in @($script:PermitRegistry.Keys)) {
        if ($script:PermitRegistry[$permitId].OperationId -eq $OperationId) {
            $script:PermitRegistry.Remove($permitId)
        }
    }
}

function Invoke-PrivateExpiry {
    $now = Get-PrivateTimestamp
    $timeoutTicks = [long]($script:OperationTimeout.TotalSeconds * [System.Diagnostics.Stopwatch]::Frequency)
    foreach ($id in @($script:OperationRegistry.Keys)) {
        $record = $script:OperationRegistry[$id]
        if ($record.ModuleInstanceId -cne $script:ModuleInstanceId) {
            Remove-PrivateOperation $id
            continue
        }
        if ($null -eq $record.ActivePermitId -and ($now - $record.LastActivityTimestamp) -ge $timeoutTicks) {
            Remove-PrivateOperation $id
        }
    }
}

function Remove-PrivateContextRecord {
    param([PSCustomObject]$Context)
    foreach ($id in @($script:OperationRegistry.Keys)) {
        if ([object]::ReferenceEquals($Context, $script:OperationRegistry[$id].Context)) {
            Remove-PrivateOperation $id
            return
        }
    }
}

function Get-PrivateConfigurationProperty {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if (-not $InputObject.Contains($Name)) {
            throw "Configuration property '$Name' is required."
        }
        return $InputObject[$Name]
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Configuration property '$Name' is required."
    }
    return $property.Value
}

function Assert-PrivateSimulationConfiguration {
    param([Parameter(Mandatory = $true)][object]$Configuration)

    if ($null -eq $Configuration) {
        throw 'Configuration is required.'
    }

    $value = Get-PrivateConfigurationProperty -InputObject $Configuration -Name 'SimulationMode'
    if ($value -isnot [bool]) {
        throw "Configuration property 'SimulationMode' must be a Boolean value."
    }
    return $value
}

function New-PrivateContext {
    param(
        [Parameter(Mandatory = $true)][string]$OperationKind,
        [Parameter(Mandatory = $true)][string]$AccessLevel,
        [Parameter(Mandatory = $true)][string]$Outcome,
        [Parameter(Mandatory = $true)][bool]$SimulationMode,
        [Parameter(Mandatory = $true)][bool]$ExecuteRequested,
        [Parameter(Mandatory = $true)][bool]$ExternalReadAllowed,
        [Parameter(Mandatory = $true)][bool]$ExternalWriteAllowed,
        [string]$OperationName,
        [string]$Target,
        [string]$OperationStatus,
        [object[]]$Steps = @()
    )

    $context = [PSCustomObject]@{
        ContextId            = [guid]::NewGuid().ToString('D')
        OperationId          = [guid]::NewGuid().ToString('D')
        OperationKind        = $OperationKind
        OperationName        = $OperationName
        Target                = $Target
        AccessLevel          = $AccessLevel
        Outcome              = $Outcome
        SimulationMode       = $SimulationMode
        ExecuteRequested     = $ExecuteRequested
        ExternalReadAllowed  = $ExternalReadAllowed
        ExternalWriteAllowed = $ExternalWriteAllowed
        OperationStatus      = $OperationStatus
        ModuleInstanceId     = $script:ModuleInstanceId
        Steps                = @($Steps | ForEach-Object { [PSCustomObject]@{ Name=$_.Name; Status=$_.Status; Changed=$_.Changed; Error=$_.Error } })
    }
    $expected = @{}
    foreach ($field in @('ContextId','OperationId','ModuleInstanceId','OperationKind','OperationName','Target','AccessLevel','Outcome','SimulationMode','ExecuteRequested','ExternalReadAllowed','ExternalWriteAllowed','OperationStatus')) { $expected[$field] = $context.$field }
    $privateSteps = @($Steps | ForEach-Object { [PSCustomObject]@{ Name=$_.Name; Status=$_.Status; Changed=$_.Changed; Error=$_.Error } })
    $script:OperationRegistry[$context.OperationId] = @{ Context=$context; Expected=$expected; StepStates=$privateSteps; Finalized=$false; ModuleInstanceId=$script:ModuleInstanceId; ActivePermitId=$null; LastActivityTimestamp=(Get-PrivateTimestamp) }
    return $context
}

function Assert-PrivateContextIntegrity {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Context)

    if ([string]::IsNullOrWhiteSpace($Context.OperationId)) {
        Remove-PrivateContextRecord $Context
        throw 'The operation context is incomplete.'
    }
    if ($Context.ModuleInstanceId -and $Context.ModuleInstanceId -cne $script:ModuleInstanceId) {
        Remove-PrivateContextRecord $Context
        throw 'The operation context belongs to another module instance.'
    }
    if (-not $script:OperationRegistry.ContainsKey($Context.OperationId)) {
        Remove-PrivateContextRecord $Context
        throw 'The operation context is unknown or has expired.'
    }

    $record = $script:OperationRegistry[$Context.OperationId]
    if (-not [object]::ReferenceEquals($Context, $record.Context)) {
        Remove-PrivateContextRecord $Context
        throw 'The operation context is not the registered context instance.'
    }

    foreach ($field in @('ContextId','OperationId','ModuleInstanceId','OperationKind','OperationName','Target',
            'AccessLevel','Outcome','SimulationMode','ExecuteRequested','ExternalReadAllowed',
            'ExternalWriteAllowed','OperationStatus')) {
        if ($Context.$field -cne $record.Expected[$field]) {
            Remove-PrivateOperation $Context.OperationId
            throw "The operation context was altered: '$field'."
        }
    }

    if (@($Context.Steps).Count -ne @($record.StepStates).Count) {
        Remove-PrivateOperation $Context.OperationId
        throw 'The operation context step list was altered.'
    }
    for ($index = 0; $index -lt @($record.StepStates).Count; $index++) {
        $visible = $Context.Steps[$index]
        $expected = $record.StepStates[$index]
        foreach ($field in @('Name','Status','Changed','Error')) {
            if ($visible.$field -cne $expected.$field) {
                Remove-PrivateOperation $Context.OperationId
                throw "The operation context step '$($expected.Name)' was altered."
            }
        }
    }

    if ($record.Finalized) {
        throw 'The operation is already finalized.'
    }
    return $record
}

function Set-PrivateExpectedField {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Record,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $Record.Expected[$Name] = $Value
    $Record.Context.$Name = $Value
}

function Get-PrivateOperationSummary {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Record,
        [Parameter(Mandatory = $true)][string]$Outcome,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][bool]$EffectsUnknown
    )

    $succeeded = @($Record.StepStates | Where-Object Status -eq 'Succeeded')
    $executed = $succeeded.Count -gt 0
    $changed = @($succeeded | Where-Object Changed).Count -gt 0
    return [PSCustomObject]@{
        OperationId      = $Record.Context.OperationId
        OperationName    = $Record.Context.OperationName
        Target            = $Record.Context.Target
        AccessLevel      = $Record.Context.AccessLevel
        Outcome          = $Outcome
        WriteAuthorized  = $Record.Context.Outcome -eq 'WriteAuthorized'
        Executed         = [bool]$executed
        Changed          = [bool]$changed
        Success          = ($Outcome -eq 'Completed')
        Status           = $Status
        EffectsUnknown   = $EffectsUnknown
        Steps            = @($Record.StepStates | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name; Status = $_.Status; Changed = $_.Changed; Error = $_.Error
            }
        })
        Errors           = @($Record.StepStates | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Error) } |
            ForEach-Object Error)
    }
}

function Invoke-GetAutomationExecutionContextCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Configuration
    )

    Invoke-PrivateExpiry
    $simulation = Assert-PrivateSimulationConfiguration -Configuration $Configuration
    if ($simulation) {
        return New-PrivateContext -OperationKind 'ReadOnly' -AccessLevel 'Simulation' `
            -Outcome 'Simulated' -SimulationMode $true -ExecuteRequested $false `
            -ExternalReadAllowed $false -ExternalWriteAllowed $false -OperationStatus 'NotStarted'
    }

    return New-PrivateContext -OperationKind 'ReadOnly' -AccessLevel 'ReadOnly' `
        -Outcome 'ReadOnly' -SimulationMode $false -ExecuteRequested $false `
        -ExternalReadAllowed $true -ExternalWriteAllowed $false -OperationStatus 'NotStarted'
}

function Invoke-StartAutomationWriteOperationCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Configuration,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OperationName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Steps,
        [Parameter()][switch]$Execute
    )

    Invoke-PrivateExpiry
    $simulation = Assert-PrivateSimulationConfiguration -Configuration $Configuration
    if ($Steps.Count -eq 0) { throw 'At least one write step is required.' }
    if (@($Steps | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'Write step names cannot be empty.'
    }
    if (@($Steps | Select-Object -Unique).Count -ne $Steps.Count) {
        throw 'Write step names must be unique.'
    }

    if ($simulation) {
        return New-PrivateContext -OperationKind 'Write' -OperationName $OperationName -Target $Target `
            -AccessLevel 'Simulation' -Outcome 'Simulated' -SimulationMode $true `
            -ExecuteRequested ([bool]$Execute) -ExternalReadAllowed $false `
            -ExternalWriteAllowed $false -OperationStatus 'Simulated'
    }
    if (-not $Execute) {
        return New-PrivateContext -OperationKind 'Write' -OperationName $OperationName -Target $Target `
            -AccessLevel 'ReadOnly' -Outcome 'Preview' -SimulationMode $false `
            -ExecuteRequested $false -ExternalReadAllowed $true `
            -ExternalWriteAllowed $false -OperationStatus 'Preview'
    }

    $stepStates = @($Steps | ForEach-Object {
        [PSCustomObject]@{ Name = $_; Status = 'Pending'; Changed = $false; Error = '' }
    })
    $context = New-PrivateContext -OperationKind 'Write' -OperationName $OperationName -Target $Target `
        -AccessLevel 'Write' -Outcome 'WriteAuthorized' -SimulationMode $false `
        -ExecuteRequested $true -ExternalReadAllowed $true -ExternalWriteAllowed $true `
        -OperationStatus 'Issued' -Steps $stepStates

    return $context
}

function Invoke-AssertAutomationWriteAuthorizedCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target
    )

    Invoke-PrivateExpiry
    $record = Assert-PrivateContextIntegrity -Context $Context
    if ($Context.AccessLevel -ne 'Write' -or $Context.Outcome -ne 'WriteAuthorized' -or
        $Context.SimulationMode -ne $false -or -not $Context.ExecuteRequested -or
        -not $Context.ExternalWriteAllowed) {
        throw 'Write authorization is not active for this context.'
    }
    if ($Target -cne $Context.Target) { throw 'The write target does not match the authorized target.' }
    if ($null -ne $record.ActivePermitId) { throw 'The previous write step has not been completed.' }

    if (@($record.StepStates | Where-Object Status -in @('Failed','Unknown','Cancelled','Skipped')).Count -gt 0) { throw 'A failed step prevents further operation progress.' }
    $nextStep = $record.StepStates | Where-Object Status -eq 'Pending' | Select-Object -First 1
    if ($null -eq $nextStep -or $StepName -cne $nextStep.Name) {
        throw 'The requested write step is not the next authorized step.'
    }

    $nextStep.Status = 'Started'
    $contextStep = $Context.Steps | Where-Object Name -CEQ $StepName | Select-Object -First 1
    $contextStep.Status = 'Started'
    Set-PrivateExpectedField -Record $record -Name 'OperationStatus' -Value 'InProgress'

    $permit = [PSCustomObject]@{
        PermitId = [guid]::NewGuid().ToString('D')
        OperationId = $Context.OperationId
        StepName = $StepName
        Target = $Target
        Status = 'Authorized'
    }
    $record.ActivePermitId = $permit.PermitId
    $script:PermitRegistry[$permit.PermitId] = @{
        Permit = $permit; Context = $Context; Step = $nextStep; Consumed = $false; OperationId = $Context.OperationId
    }
    Set-PrivateActivity -Record $record
    return $permit
}

function Invoke-CompleteAutomationWriteStepCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][PSCustomObject]$Permit,
        [Parameter(Mandatory = $true)][object]$Succeeded,
        [Parameter(Mandatory = $true)][object]$Changed,
        [Parameter()][AllowEmptyString()][string]$ErrorMessage = ''
    )

    Invoke-PrivateExpiry
    $record = Assert-PrivateContextIntegrity -Context $Context
    $permitRegistryKey = $null
    $permitRecord = $null
    if ($script:PermitRegistry.ContainsKey($Permit.PermitId)) {
        $permitRegistryKey = $Permit.PermitId
        $permitRecord = $script:PermitRegistry[$permitRegistryKey]
    }

    # PermitId is caller-visible and mutable. If it was changed to another
    # permit's ID, find the original record by object identity so only the
    # operation whose permit was altered can be invalidated.
    if ($null -eq $permitRecord -or
        -not [object]::ReferenceEquals($Permit, $permitRecord.Permit)) {
        foreach ($candidateId in @($script:PermitRegistry.Keys)) {
            $candidate = $script:PermitRegistry[$candidateId]
            if ([object]::ReferenceEquals($Permit, $candidate.Permit)) {
                $permitRegistryKey = $candidateId
                $permitRecord = $candidate
                break
            }
        }
    }
    if ($null -eq $permitRecord) {
        throw 'The write permit is unknown or has already been consumed.'
    }

    if (-not [object]::ReferenceEquals($Permit, $permitRecord.Permit)) {
        throw 'The write permit is not the registered permit instance.'
    }
    $expectedPermitStatus = if ($permitRecord.Consumed) { 'Consumed' } else { 'Authorized' }
    if ($Permit.PermitId -cne $permitRegistryKey -or
        $Permit.OperationId -cne $permitRecord.OperationId -or
        $Permit.Target -cne $permitRecord.Context.Target -or
        $Permit.StepName -cne $permitRecord.Step.Name -or
        $Permit.Status -cne $expectedPermitStatus) {
        Remove-PrivateOperation $permitRecord.OperationId
        throw 'The write permit is invalid or altered.'
    }

    # A genuine permit presented with a different, otherwise valid context is
    # a cross-operation attempt. Reject it without revoking the permit's owner.
    if (-not [object]::ReferenceEquals($Context, $permitRecord.Context)) {
        throw 'The write permit is bound to another operation context.'
    }
    if ($permitRecord.Consumed) {
        Remove-PrivateOperation $permitRecord.OperationId
        throw 'The write permit has already been consumed or reused.'
    }
    if ($record.ActivePermitId -cne $Permit.PermitId -or $permitRecord.Step.Status -cne 'Started') {
        throw 'The write permit is not active for this operation step.'
    }
    if ($Succeeded -isnot [bool] -or $Changed -isnot [bool]) { throw 'Succeeded and Changed must be Boolean values.' }
    if (-not $Succeeded -and $Changed) {
        throw 'A failed step cannot report a confirmed change; leave it Started and abort if effects are unknown.'
    }

    $permitRecord.Consumed = $true
    $Permit.Status = 'Consumed'
    $record.ActivePermitId = $null
    $permitRecord.Step.Status = if ($Succeeded) { 'Succeeded' } else { 'Failed' }
    $permitRecord.Step.Changed = $Changed
    $permitRecord.Step.Error = if ($Succeeded) { '' } else { $ErrorMessage }
    $visible = $Context.Steps | Where-Object Name -CEQ $Permit.StepName | Select-Object -First 1
    $visible.Status = $permitRecord.Step.Status
    $visible.Changed = $Changed
    $visible.Error = $permitRecord.Step.Error
    Set-PrivateActivity -Record $record

    return [PSCustomObject]@{
        OperationId = $Context.OperationId
        StepName = $Permit.StepName
        Target = $Permit.Target
        Status = $permitRecord.Step.Status
        Changed = $Changed
        Error = $permitRecord.Step.Error
    }
}

function Assert-PrivateWriteOperation {
    param([Parameter(Mandatory = $true)][hashtable]$Record)

    $context = $Record.Context
    if ($context.OperationKind -cne 'Write' -or $context.AccessLevel -cne 'Write' -or
        $context.Outcome -cne 'WriteAuthorized' -or $context.SimulationMode -ne $false -or
        -not $context.ExecuteRequested -or -not $context.ExternalWriteAllowed -or
        @($Record.StepStates).Count -eq 0) {
        throw 'An authorized write operation with registered steps is required.'
    }
}

function Invoke-CompleteAutomationWriteOperationCore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][PSCustomObject]$Context)

    Invoke-PrivateExpiry
    $record = Assert-PrivateContextIntegrity -Context $Context
    Assert-PrivateWriteOperation -Record $record
    if ($null -ne $record.ActivePermitId) { throw 'An active write step must be completed or aborted first.' }
    if (@($record.StepStates | Where-Object Status -ne 'Succeeded').Count -gt 0) {
        throw 'The operation has pending or failed steps and cannot be completed successfully.'
    }
    $record.Finalized = $true
    Set-PrivateExpectedField -Record $record -Name 'OperationStatus' -Value 'Completed'
    Set-PrivateActivity -Record $record
    return Get-PrivateOperationSummary -Record $record -Outcome 'Completed' -Status 'Completed' -EffectsUnknown $false
}

function Invoke-AbortAutomationWriteOperationCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Failed','Interrupted','Cancelled','Incomplete')][string]$Reason,
        [Parameter()][AllowEmptyString()][string]$ErrorMessage = ''
    )

    Invoke-PrivateExpiry
    $record = Assert-PrivateContextIntegrity -Context $Context
    Assert-PrivateWriteOperation -Record $record
    $hasUnknown = $false
    foreach ($step in $record.StepStates) {
        if ($step.Status -eq 'Started') {
            $step.Status = 'Unknown'
            $step.Error = if ($ErrorMessage) { $ErrorMessage } else { 'Write outcome is unknown.' }
            $hasUnknown = $true
        }
        elseif ($step.Status -eq 'Pending') {
            $step.Status = if ($Reason -eq 'Cancelled') { 'Cancelled' } else { 'Skipped' }
        }
        $visible = $Context.Steps | Where-Object Name -CEQ $step.Name | Select-Object -First 1
        $visible.Status = $step.Status
        $visible.Changed = $step.Changed
        $visible.Error = $step.Error
    }

    $hasSucceeded = @($record.StepStates | Where-Object Status -eq 'Succeeded').Count -gt 0
    $hasChanged = @($record.StepStates | Where-Object { $_.Status -eq 'Succeeded' -and $_.Changed }).Count -gt 0
    switch ($Reason) {
        'Failed' {
            $outcome = if ($hasSucceeded) { 'PartialFailure' } else { 'Failed' }
            if ($hasUnknown) { $status = 'FailedWithUnknownEffects' }
            elseif ($hasChanged) { $status = 'FailedAfterChanges' }
            else { $status = 'FailedNoChanges' }
        }
        'Interrupted' {
            $outcome = if ($hasSucceeded) { 'PartialFailure' } else { 'Interrupted' }
            if ($hasChanged) { $status = 'InterruptedAfterChanges' }
            elseif ($hasUnknown) { $status = 'InterruptedUnknownEffects' }
            else { $status = 'InterruptedNoChanges' }
        }
        'Cancelled' {
            if ($hasUnknown) { $outcome = 'Interrupted'; $status = 'CancelledWithUnknownEffects' }
            else {
                $outcome = if ($hasSucceeded) { 'PartialFailure' } else { 'Cancelled' }
                $status = if ($hasChanged) { 'CancelledAfterChanges' } else { 'CancelledNoChanges' }
            }
        }
        'Incomplete' {
            if ($hasUnknown) { $outcome = 'Incomplete'; $status = 'IncompleteUnknownEffects' }
            else {
                $outcome = if ($hasSucceeded) { 'PartialFailure' } else { 'Incomplete' }
                $status = if ($hasChanged) { 'IncompleteAfterChanges' } else { 'IncompleteNoChanges' }
            }
        }
    }

    $record.Finalized = $true
    $record.ActivePermitId = $null
    $script:OperationRegistry.Remove($Context.OperationId)
    foreach ($permitId in @($script:PermitRegistry.Keys)) {
        if ($script:PermitRegistry[$permitId].Context.OperationId -eq $Context.OperationId) {
            $script:PermitRegistry.Remove($permitId)
        }
    }
    $Context.OperationStatus = $status
    return Get-PrivateOperationSummary -Record $record -Outcome $outcome -Status $status -EffectsUnknown $hasUnknown
}

function Get-AutomationExecutionContext {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Configuration)
    $arguments = @{}; foreach ($key in $PSBoundParameters.Keys) { $arguments[$key] = $PSBoundParameters[$key] }
    $action = { Invoke-GetAutomationExecutionContextCore @arguments }
    Invoke-PrivateSynchronized -Action $action
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
    $arguments = @{}; foreach ($key in $PSBoundParameters.Keys) { $arguments[$key] = $PSBoundParameters[$key] }
    $action = { Invoke-StartAutomationWriteOperationCore @arguments }
    Invoke-PrivateSynchronized -Action $action
}

function Assert-AutomationWriteAuthorized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target
    )
    $arguments = @{}; foreach ($key in $PSBoundParameters.Keys) { $arguments[$key] = $PSBoundParameters[$key] }
    $action = { Invoke-AssertAutomationWriteAuthorizedCore @arguments }
    Invoke-PrivateSynchronized -Action $action
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
    $arguments = @{}; foreach ($key in $PSBoundParameters.Keys) { $arguments[$key] = $PSBoundParameters[$key] }
    $action = { Invoke-CompleteAutomationWriteStepCore @arguments }
    Invoke-PrivateSynchronized -Action $action
}

function Complete-AutomationWriteOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][PSCustomObject]$Context)
    $arguments = @{}; foreach ($key in $PSBoundParameters.Keys) { $arguments[$key] = $PSBoundParameters[$key] }
    $action = { Invoke-CompleteAutomationWriteOperationCore @arguments }
    Invoke-PrivateSynchronized -Action $action
}

function Abort-AutomationWriteOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Failed','Interrupted','Cancelled','Incomplete')][string]$Reason,
        [Parameter()][AllowEmptyString()][string]$ErrorMessage = ''
    )
    $arguments = @{}; foreach ($key in $PSBoundParameters.Keys) { $arguments[$key] = $PSBoundParameters[$key] }
    $action = { Invoke-AbortAutomationWriteOperationCore @arguments }
    Invoke-PrivateSynchronized -Action $action
}

Export-ModuleMember -Function @(
    'Get-AutomationExecutionContext',
    'Start-AutomationWriteOperation',
    'Assert-AutomationWriteAuthorized',
    'Complete-AutomationWriteStep',
    'Complete-AutomationWriteOperation',
    'Abort-AutomationWriteOperation'
)
