Set-StrictMode -Version Latest

$script:ComputerCorePath = Join-Path $PSScriptRoot "..\Computer-Functions.psm1"

if (-not (Test-Path -LiteralPath $script:ComputerCorePath)) {
    throw "Computer Core não encontrado em: $script:ComputerCorePath"
}

$script:ComputerCoreModule = Import-Module $script:ComputerCorePath -Force -PassThru -ErrorAction Stop
if ($null -eq $script:ComputerCoreModule -or
    [System.IO.Path]::GetFullPath($script:ComputerCoreModule.Path) -ne [System.IO.Path]::GetFullPath($script:ComputerCorePath)) {
    throw "A instância esperada do Computer Core não foi carregada: $script:ComputerCorePath"
}

$script:ComputerCoreInventoryCommand = $script:ComputerCoreModule.ExportedCommands["Get-ComputerInventory"]
if ($null -eq $script:ComputerCoreInventoryCommand -or
    $script:ComputerCoreInventoryCommand.Module -ne $script:ComputerCoreModule) {
    throw "Get-ComputerInventory não foi exportada pela instância esperada do Computer Core."
}

function Invoke-ComputerCoreInventory {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments
    )

    # Preserve a module-local test/extension seam while rejecting commands
    # supplied by unrelated modules with the same exported function name.
    $localOverride = Microsoft.PowerShell.Core\Get-Command `
        Get-ComputerInventory `
        -CommandType Function `
        -ErrorAction SilentlyContinue

    if ($null -ne $localOverride -and
        $localOverride.Module -eq $ExecutionContext.SessionState.Module) {
        return & $localOverride @Arguments
    }

    if ($null -eq $script:ComputerCoreInventoryCommand -or
        $script:ComputerCoreInventoryCommand.Module -ne $script:ComputerCoreModule) {
        throw "A referência da função Get-ComputerInventory do Computer Core está indisponível."
    }

    return & $script:ComputerCoreInventoryCommand @Arguments
}

function Invoke-ComputerManagementShouldProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Action
    )
    return $Cmdlet.ShouldProcess($Target, $Action)
}

function Get-ComputerManagement {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname,

        [switch]$SimulationMode,
        [switch]$Preview,
        [switch]$AllowRealOperation
    )

    $whatIfRequested = [bool]$WhatIfPreference
    $explicitPreview = $Preview.IsPresent
    $simulationRequested = $SimulationMode.IsPresent
    $realRequested = $AllowRealOperation.IsPresent
    $conflictingModes = ($simulationRequested -and ($explicitPreview -or $whatIfRequested -or $realRequested)) -or
        ($explicitPreview -and $realRequested)
    $modeRequested = $simulationRequested -or $explicitPreview -or $whatIfRequested -or $realRequested

    if (-not $modeRequested -or $conflictingModes) {
        return [PSCustomObject]@{
            Success = $false; Hostname = $Hostname; SimulationMode = $false
            Preview = $false; Mode = "Error"; Status = "Error"; Cancelled = $false
            CollectionStatus = "Error"; QueryStatus = $null
            Summary = $null; Data = $null
            Errors = @([PSCustomObject]@{ Source = "ComputerManagement"; Message = if ($conflictingModes) { "Modos conflitantes; nenhuma consulta foi realizada." } else { "Informe um modo: SimulationMode, Preview/WhatIf ou AllowRealOperation." } })
        }
    }

    # WhatIf is an unconditional preview request, including when the caller
    # also supplies the real-operation capability switch.
    $mode = if ($simulationRequested) { "Simulation" } elseif ($explicitPreview -or $whatIfRequested) { "Preview" } else { "Real" }

    $hostnameNormalized = $Hostname.Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($hostnameNormalized)) {
        return [PSCustomObject]@{
            Success = $false; Hostname = $Hostname; SimulationMode = ($mode -eq "Simulation")
            Preview = ($mode -eq "Preview"); Mode = $mode; Status = "Invalid"; Cancelled = $false
            CollectionStatus = "Error"; QueryStatus = $null; Summary = $null; Data = $null
            Errors = @([PSCustomObject]@{ Source = "ComputerManagement"; Message = "Hostname não pode ser vazio." })
        }
    }

    if ($mode -eq "Real" -and -not (Invoke-ComputerManagementShouldProcess -Cmdlet $PSCmdlet -Target $hostnameNormalized -Action "Consultar inventário do computador")) {
        return [PSCustomObject]@{
            Success = $false; Hostname = $hostnameNormalized; SimulationMode = $false
            Preview = $true; Mode = "Preview"; Status = "Cancelled"; Cancelled = $true
            CollectionStatus = "Cancelled"; QueryStatus = $null; Summary = $null; Data = $null
            Errors = @([PSCustomObject]@{ Source = "ComputerManagement"; Message = "Coleta cancelada pelo usuário; nenhuma consulta externa foi realizada." })
        }
    }

    try {
        $coreArguments = @{ ComputerName = $hostnameNormalized }
        if ($mode -eq "Simulation") { $coreArguments.SimulationMode = $true }
        elseif ($mode -eq "Preview") { $coreArguments.Preview = $true }
        else { $coreArguments.AllowRealOperation = $true; $coreArguments.Confirm = $false }
        $coreResult = Invoke-ComputerCoreInventory -Arguments $coreArguments

        if ($null -eq $coreResult) { throw "O Computer Core não retornou resultado." }
        $inventory = $coreResult.Data
        $queryStatus = $null
        if ($null -ne $coreResult.PSObject.Properties["QueryStatus"]) { $queryStatus = $coreResult.PSObject.Properties["QueryStatus"].Value }
        elseif ($null -ne $inventory -and $null -ne $inventory.PSObject.Properties["QueryStatus"]) { $queryStatus = $inventory.PSObject.Properties["QueryStatus"].Value }
        $collectionStatus = $null
        if ($null -ne $coreResult.PSObject.Properties["CollectionStatus"]) { $collectionStatus = $coreResult.PSObject.Properties["CollectionStatus"].Value }
        elseif ($null -ne $inventory -and $null -ne $inventory.PSObject.Properties["CollectionStatus"]) { $collectionStatus = $inventory.PSObject.Properties["CollectionStatus"].Value }
        $errors = @()
        if ($null -ne $inventory -and $null -ne $inventory.Errors) { $errors += @($inventory.Errors) }
        elseif ($null -ne $coreResult.PSObject.Properties["Errors"] -and $null -ne $coreResult.PSObject.Properties["Errors"].Value) { $errors += @($coreResult.PSObject.Properties["Errors"].Value) }
        if ($errors.Count -eq 0 -and $null -ne $coreResult.PSObject.Properties["Error"] -and -not [string]::IsNullOrWhiteSpace([string]$coreResult.PSObject.Properties["Error"].Value)) {
            $errors += [PSCustomObject]@{ Source = "ComputerCore"; Message = [string]$coreResult.PSObject.Properties["Error"].Value }
        }

        if ($coreResult.Cancelled -or $coreResult.Status -eq "Cancelled") {
            return [PSCustomObject]@{
                Success = $false; Hostname = $hostnameNormalized; SimulationMode = $false
                Preview = $true; Mode = "Preview"; Status = "Cancelled"; Cancelled = $true
                CollectionStatus = "Cancelled"; QueryStatus = $queryStatus
                Summary = $null; Data = $null; Errors = $errors
            }
        }

        if ($null -eq $inventory) {
            return [PSCustomObject]@{
                Success = [bool]$coreResult.Success; Hostname = $hostnameNormalized
                SimulationMode = ($mode -eq "Simulation"); Preview = ($mode -eq "Preview")
                Mode = $mode; Status = [string]$coreResult.Status; Cancelled = $false
                CollectionStatus = $collectionStatus; QueryStatus = $queryStatus
                Summary = $null; Data = $null; Errors = $errors
            }
        }

        # Mode is authoritative. Core uses IsSimulated to label its harmless
        # preview payload too; that must never turn Preview into Simulation.
        $isSimulated = ($mode -eq "Simulation") -or ($mode -eq "Real" -and [bool]$coreResult.IsSimulated)
        $adFound = $null
        $reachable = $null
        $adQueryStatus = if ($null -ne $inventory.AD -and $inventory.AD.QueryStatus) { [string]$inventory.AD.QueryStatus } else { "Unknown" }
        $connectivityStatus = if ($null -ne $inventory.Connectivity -and $inventory.Connectivity.Status) { [string]$inventory.Connectivity.Status } else { "Unknown" }
        if (-not $isSimulated -and $mode -eq "Real") {
            if ($adQueryStatus -eq "Found" -and $inventory.AD.Found -eq $true) { $adFound = $true }
            elseif ($adQueryStatus -eq "NotFound" -and $inventory.AD.Found -eq $false) { $adFound = $false }
            if ($connectivityStatus -eq "Responded" -and $inventory.Connectivity.Reachable -eq $true) { $reachable = $true }
            elseif ($connectivityStatus -eq "NoResponse" -and $inventory.Connectivity.Reachable -eq $false) { $reachable = $false }
        }
        $status = if ($mode -eq "Preview") { "Preview" } elseif ($isSimulated) { "Simulated" } else { "Unknown" }
        if (-not $isSimulated -and $mode -eq "Real") {
            if ($adFound -eq $true -and $reachable -eq $true) { $status = "Online" }
            elseif ($adFound -eq $true -and $reachable -eq $false) { $status = "Offline" }
            elseif ($adFound -eq $false -and $reachable -eq $true) { $status = "ReachableOnly" }
            elseif ($adFound -eq $false -and $reachable -eq $false) { $status = "Unavailable" }
        }

        $summary = [PSCustomObject]@{
            Hostname = $inventory.Hostname; Status = $status; ADFound = $adFound; Reachable = $reachable
            OperatingSystem = if ($mode -eq "Real") { $inventory.OperatingSystem.Caption } else { $null }
            Model = if ($mode -eq "Real") { $inventory.System.Model } else { $null }
            MemoryGB = if ($mode -eq "Real") { $inventory.Memory.TotalGB } else { $null }
            Processor = if ($mode -eq "Real") { $inventory.Processor.Name } else { $null }
            BitLockerStatus = if ($mode -eq "Real" -and $null -ne $inventory.BitLocker) { $inventory.BitLocker.Status } else { "NotCollected" }
            ErrorCount = $errors.Count; SimulationMode = $isSimulated; Preview = ($mode -eq "Preview")
            Mode = $mode; Cancelled = $false; IsSimulated = $isSimulated
            Success = [bool]$coreResult.Success; Errors = $errors
            CollectionStatus = $collectionStatus
            QueryStatus = $queryStatus
            ADQueryStatus = $adQueryStatus
            ConnectivityStatus = $connectivityStatus
        }

        [PSCustomObject]@{
            Success = [bool]$coreResult.Success; Hostname = $inventory.Hostname
            SimulationMode = $isSimulated; Preview = ($mode -eq "Preview"); Mode = $mode
            Status = $status; Cancelled = $false; CollectionStatus = $collectionStatus
            QueryStatus = $queryStatus; Summary = $summary; Data = $inventory; Errors = $errors
        }
    }
    catch {
        [PSCustomObject]@{
            Success = $false; Hostname = $hostnameNormalized; SimulationMode = ($mode -eq "Simulation")
            Preview = ($mode -eq "Preview"); Mode = "Error"; Status = "Error"; Cancelled = $false
            CollectionStatus = "Error"; QueryStatus = $null; Summary = $null; Data = $null
            Errors = @([PSCustomObject]@{ Source = "ComputerManagement"; Message = $_.Exception.Message })
        }
    }
}

function Get-ComputerManagementSummary {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname,
        [switch]$SimulationMode,
        [switch]$Preview,
        [switch]$AllowRealOperation
    )

    $whatIfRequested = [bool]$WhatIfPreference
    $conflictingModes = ($SimulationMode -and ($Preview -or $whatIfRequested -or $AllowRealOperation)) -or ($Preview -and $AllowRealOperation)
    if ($conflictingModes) {
        return [PSCustomObject]@{
            Hostname = $Hostname; Status = "Error"; ADFound = $null; Reachable = $null
            OperatingSystem = $null; Model = $null; MemoryGB = $null; Processor = $null
            BitLockerStatus = "NotCollected"; ErrorCount = 1; SimulationMode = $false
            Preview = $false; Mode = "Error"; Cancelled = $false; Success = $false
            Errors = @([PSCustomObject]@{ Source = "ComputerManagement"; Message = "Modos conflitantes; nenhuma consulta foi realizada." })
            IsSimulated = $false; CollectionStatus = "Error"; QueryStatus = $null
            ADQueryStatus = "NotQueried"; ConnectivityStatus = "NotQueried"
        }
    }

    $arguments = @{ Hostname = $Hostname }
    if ($SimulationMode) { $arguments.SimulationMode = $true }
    elseif ($Preview -or $whatIfRequested) { $arguments.Preview = $true }
    elseif ($AllowRealOperation) { $arguments.AllowRealOperation = $true; $arguments.Confirm = $false }
    $result = Get-ComputerManagement @arguments
    if ($null -eq $result) { return $null }
    if ($null -ne $result.Summary) { return $result.Summary }

    [PSCustomObject]@{
        Hostname = $result.Hostname; Status = $result.Status; ADFound = $null; Reachable = $null
        OperatingSystem = $null; Model = $null; MemoryGB = $null; Processor = $null
        BitLockerStatus = "NotCollected"; ErrorCount = @($result.Errors).Count
        SimulationMode = [bool]$result.SimulationMode; Preview = [bool]$result.Preview
        Mode = $result.Mode; Cancelled = [bool]$result.Cancelled; Success = [bool]$result.Success
        Errors = @($result.Errors); IsSimulated = ($result.Mode -eq "Simulation")
        CollectionStatus = $result.CollectionStatus; QueryStatus = $result.QueryStatus
        ADQueryStatus = "NotQueried"; ConnectivityStatus = "NotQueried"
    }
}

function Test-ComputerManagement {
    [CmdletBinding()]
    param()

    $coreFunctionAvailable = ($null -ne $script:ComputerCoreInventoryCommand -and
        $script:ComputerCoreInventoryCommand.Module -eq $script:ComputerCoreModule)
    $managementFunctionAvailable = $null -ne (Get-Command Get-ComputerManagement -ErrorAction SilentlyContinue)
    [PSCustomObject]@{
        Success = ($coreFunctionAvailable -and $managementFunctionAvailable)
        ComputerCoreAvailable = $coreFunctionAvailable
        ManagementAvailable = $managementFunctionAvailable
        ModulePath = $PSCommandPath
        ComputerCorePath = $script:ComputerCorePath
    }
}

Export-ModuleMember -Function @("Get-ComputerManagement", "Get-ComputerManagementSummary", "Test-ComputerManagement")
