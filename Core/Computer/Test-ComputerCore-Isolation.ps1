$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "Computer-Functions.psm1"
$module = Import-Module $modulePath -Force -PassThru -ErrorAction Stop
$script:Passed = 0
$script:Failed = 0
$global:ComputerCoreIsolationState = @{
    Decision = $true
    ADBehavior = "Found"
    CimNullClasses = @()
    CimErrorClasses = @()
    ConnectivityBehavior = "Responded"
    BitLockerBehavior = "Success"
    Calls = [ordered]@{
        GetModule = 0
        ImportModule = 0
        GetADComputer = 0
        GetCimInstance = 0
        GetWmiObject = 0
        GetBitLockerVolume = 0
        InvokeCommand = 0
        TestConnection = 0
        ShouldProcess = 0
    }
    CimTargets = @()
    RemoteScriptBlockReceived = $false
    RemoteScriptBlockExecuted = $false
}
$expectedMocks = @(
    "Get-Module", "Import-Module", "Get-ADComputer", "Get-CimInstance",
    "Get-WmiObject", "Get-BitLockerVolume", "Invoke-Command", "Test-Connection"
)

function Assert-Test {
    param([string]$Name, [bool]$Condition)
    if ($Condition) {
        $script:Passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        $script:Failed++
        Write-Host "[FAIL] $Name" -ForegroundColor Red
    }
}

function Get-ExternalCallCount {
    $total = 0
    foreach ($key in $global:ComputerCoreIsolationState.Calls.Keys) {
        if ($key -ne "ShouldProcess") { $total += $global:ComputerCoreIsolationState.Calls[$key] }
    }
    return $total
}

function Reset-ExternalCallCounts {
    foreach ($key in @($global:ComputerCoreIsolationState.Calls.Keys)) {
        $global:ComputerCoreIsolationState.Calls[$key] = 0
    }
    $global:ComputerCoreIsolationState.CimTargets = @()
    $global:ComputerCoreIsolationState.RemoteScriptBlockReceived = $false
    $global:ComputerCoreIsolationState.RemoteScriptBlockExecuted = $false
    $global:ComputerCoreIsolationState.ADBehavior = "Found"
    $global:ComputerCoreIsolationState.CimNullClasses = @()
    $global:ComputerCoreIsolationState.CimErrorClasses = @()
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "Responded"
    $global:ComputerCoreIsolationState.BitLockerBehavior = "Success"
}

try {
    # Install stubs in the imported module's script scope. Each command name
    # shadows its native cmdlet and none of the stubs delegates to a command.
    & $module {
        param([string[]]$Names)
        Set-Item -LiteralPath "Function:\script:Get-Module" -Force -Value {
            [CmdletBinding()]
            param([string]$Name, [switch]$ListAvailable)
            $global:ComputerCoreIsolationState.Calls.GetModule++
            return [PSCustomObject]@{ Name = $Name }
        }
        Set-Item -LiteralPath "Function:\script:Import-Module" -Force -Value {
            [CmdletBinding()]
            param([string]$Name)
            $global:ComputerCoreIsolationState.Calls.ImportModule++
        }
        Set-Item -LiteralPath "Function:\script:Get-ADComputer" -Force -Value {
            [CmdletBinding()]
            param([string]$Identity, [string[]]$Properties)
            $global:ComputerCoreIsolationState.Calls.GetADComputer++
            if ($global:ComputerCoreIsolationState.ADBehavior -eq "Error") {
                throw "Fixture AD query failure."
            }
            if ($global:ComputerCoreIsolationState.ADBehavior -eq "Null") {
                return $null
            }
            return [PSCustomObject]@{
                Name = $Identity
                Enabled = $true
                OperatingSystem = "Fixture OS"
                Description = "Fixture AD object"
                ManagedBy = "Fixture Manager"
                whenCreated = [datetime]"2020-01-01"
                whenChanged = [datetime]"2020-01-02"
                DistinguishedName = "CN=$Identity,OU=Fixtures,DC=example,DC=invalid"
            }
        }
        Set-Item -LiteralPath "Function:\script:Get-CimInstance" -Force -Value {
            [CmdletBinding()]
            param([string]$ClassName, [string]$ComputerName, [string]$Filter)
            $global:ComputerCoreIsolationState.Calls.GetCimInstance++
            if ($ComputerName) {
                $global:ComputerCoreIsolationState.CimTargets += $ComputerName
            }
            if ($ClassName -in $global:ComputerCoreIsolationState.CimErrorClasses) {
                throw "Fixture CIM query failure for $ClassName."
            }
            if ($ClassName -in $global:ComputerCoreIsolationState.CimNullClasses) {
                return $null
            }
            switch ($ClassName) {
                "Win32_ComputerSystem" {
                    return [PSCustomObject]@{ Manufacturer="Fixture Vendor"; Model="Fixture Model"; TotalPhysicalMemory=8589934592 }
                }
                "Win32_OperatingSystem" {
                    return [PSCustomObject]@{ Caption="Fixture OS"; Version="10.0"; BuildNumber="Fixture"; OSArchitecture="64-bit" }
                }
                "Win32_Processor" {
                    return [PSCustomObject]@{ Name="Fixture CPU"; NumberOfCores=4; NumberOfLogicalProcessors=8 }
                }
                "Win32_BIOS" {
                    return [PSCustomObject]@{ SerialNumber="FIXTURE-SERIAL" }
                }
                "Win32_ComputerSystemProduct" {
                    return [PSCustomObject]@{ IdentifyingNumber="FIXTURE-PRODUCT-ID" }
                }
                "Win32_LogicalDisk" {
                    return @([PSCustomObject]@{ DeviceID="C:"; VolumeName="Fixture"; FileSystem="NTFS"; Size=107374182400; FreeSpace=53687091200 })
                }
                "Win32_NetworkAdapterConfiguration" {
                    return @([PSCustomObject]@{ Description="Fixture NIC"; MACAddress="00-00-00-00-00-01"; IPAddress=@("192.0.2.20", "2001:db8::20") })
                }
                default {
                    throw "FAIL-CLOSED MOCK: classe CIM inesperada '$ClassName'."
                }
            }
        }
        Set-Item -LiteralPath "Function:\script:Get-WmiObject" -Force -Value {
            [CmdletBinding()]
            param()
            $global:ComputerCoreIsolationState.Calls.GetWmiObject++
            throw "FAIL-CLOSED MOCK: Get-WmiObject sem fixture."
        }
        Set-Item -LiteralPath "Function:\script:Get-BitLockerVolume" -Force -Value {
            [CmdletBinding()]
            param()
            $global:ComputerCoreIsolationState.Calls.GetBitLockerVolume++
            if ($global:ComputerCoreIsolationState.BitLockerBehavior -eq "Error") {
                throw "Fixture BitLocker query failure."
            }
            return @([PSCustomObject]@{ MountPoint="C:"; VolumeStatus="FullyEncrypted"; ProtectionStatus=1; EncryptionMethod="XtsAes256" })
        }
        Set-Item -LiteralPath "Function:\script:Invoke-Command" -Force -Value {
            [CmdletBinding()]
            param([string]$ComputerName, [scriptblock]$ScriptBlock)
            $global:ComputerCoreIsolationState.Calls.InvokeCommand++
            $global:ComputerCoreIsolationState.RemoteScriptBlockReceived = ($null -ne $ScriptBlock)
            # Deliberately do not invoke ScriptBlock: this represents remote output.
            return @([PSCustomObject]@{ MountPoint="C:"; VolumeStatus="FullyEncrypted"; ProtectionStatus=1; EncryptionMethod="XtsAes256" })
        }
        Set-Item -LiteralPath "Function:\script:Test-Connection" -Force -Value {
            [CmdletBinding()]
            param([string]$ComputerName, [int]$Count)
            $global:ComputerCoreIsolationState.Calls.TestConnection++
            switch ($global:ComputerCoreIsolationState.ConnectivityBehavior) {
                "NoResponse" { return [PSCustomObject]@{ StatusCode = 11010; Latency = $null } }
                "StatusCodeError" { return [PSCustomObject]@{ StatusCode = 11050; Latency = $null } }
                "ModernNoResponse" { return [PSCustomObject]@{ Status = "TimedOut"; Latency = $null } }
                "Empty" { return }
                "Error" { throw "Fixture connectivity query failure." }
                "Unknown" { return [PSCustomObject]@{ Status = "Indeterminate"; Latency = 1 } }
                "ModernResponded" { return [PSCustomObject]@{ Status = "Success"; Latency = 2 } }
                default { return [PSCustomObject]@{ StatusCode = 0; Latency = 1 } }
            }
        }
        Set-Item -LiteralPath "Function:\script:Invoke-ComputerCoreShouldProcess" -Force -Value {
            param($Cmdlet, [string]$Target, [string]$Action)
            $global:ComputerCoreIsolationState.Calls.ShouldProcess++
            return [bool]$global:ComputerCoreIsolationState.Decision
        }

        foreach ($name in $Names) {
            $command = Get-Command $name -CommandType Function -ErrorAction Stop
            if ($command.ModuleName -ne $ExecutionContext.SessionState.Module.Name) {
                throw "Mock fora do escopo do módulo: $name"
            }
        }
        $shouldProcessMock = Get-Command Invoke-ComputerCoreShouldProcess -CommandType Function -ErrorAction Stop
        if ($shouldProcessMock.ModuleName -ne $ExecutionContext.SessionState.Module.Name) {
            throw "Stub de ShouldProcess fora do escopo do módulo."
        }
    } $expectedMocks

    # Static source inventory must account for every external command before
    # any API flow is exercised. Unknown commands abort the harness.
    $tokens = $null
    $parseErrors = $null
    $moduleAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $modulePath, [ref]$tokens, [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) { throw "Core contém erro de sintaxe; isolamento não será testado." }
    $commandNames = @($moduleAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object { $_.GetCommandName() } | Sort-Object -Unique)
    $externalCommands = @(
        "Get-Module", "Import-Module", "Get-ADComputer", "Get-CimInstance",
        "Get-WmiObject", "Get-BitLockerVolume", "Invoke-Command", "Test-Connection"
    )
    $safeCommands = @(
        "Add-Member", "Export-ModuleMember", "ForEach-Object", "Get-Date", "Select-Object", "Where-Object",
        "Get-ComputerADInfo", "Get-ComputerCimInfo", "Get-ComputerInventory",
        "Resolve-ComputerCoreMode", "Invoke-ComputerCoreShouldProcess",
        "Invoke-ComputerCoreCimQuery", "Resolve-ComputerCoreConnectivity",
        "New-ComputerCoreDemoADInfo", "New-ComputerCoreDemoCimInfo",
        "New-ComputerCoreModeResult", "New-ComputerCoreCancelledResult"
    )
    $unclassified = @($commandNames | Where-Object { $_ -notin $externalCommands -and $_ -notin $safeCommands })
    if ($unclassified.Count -gt 0) {
        throw "Comandos sem classificação de isolamento: $($unclassified -join ', ')"
    }
    $missingStubs = @($externalCommands | Where-Object { $_ -notin $expectedMocks })
    if ($missingStubs.Count -gt 0) { throw "Fronteiras sem stub: $($missingStubs -join ', ')" }

    # Smoke-test the module-scoped external stubs themselves, then clear counts.
    & $module {
        param([string[]]$Names)
        foreach ($name in $Names) {
            try { $null = & $name } catch { }
        }
    } $expectedMocks
    if (@($global:ComputerCoreIsolationState.Calls.GetEnumerator() |
        Where-Object { $_.Key -ne "ShouldProcess" -and $_.Value -ne 1 }).Count -gt 0) {
        throw "Nem todos os stubs interceptaram sua chamada de verificação."
    }
    Reset-ExternalCallCounts

    $remoteProbe = { $global:ComputerCoreIsolationState.RemoteScriptBlockExecuted = $true }
    $null = & $module {
        param([scriptblock]$Probe)
        Invoke-Command -ComputerName "MOCK-PROBE" -ScriptBlock $Probe
    } $remoteProbe
    if ($global:ComputerCoreIsolationState.Calls.InvokeCommand -ne 1 -or
        -not $global:ComputerCoreIsolationState.RemoteScriptBlockReceived -or
        $global:ComputerCoreIsolationState.RemoteScriptBlockExecuted) {
        throw "O stub Invoke-Command não conteve o scriptblock de verificação."
    }
    Reset-ExternalCallCounts

    $simulation = Get-ComputerInventory -ComputerName "SIM-CORE" -SimulationMode
    Assert-Test "SimulationMode retorna dados fictícios identificados" (
        $simulation.Success -and $simulation.Mode -eq "Simulation" -and
        $simulation.CollectionStatus -eq "Simulation" -and
        $simulation.IsSimulated -and $simulation.Data.Status -eq "Simulated" -and
        $simulation.Data.AD.IsSimulated -and $simulation.Data.BitLocker.IsSimulated
    )
    Assert-Test "SimulationMode não afirma descoberta AD nem conectividade" (
        $null -eq $simulation.Data.AD.Found -and
        $null -eq $simulation.Data.Connectivity.Reachable
    )
    $simAD = Get-ComputerADInfo -Hostname "SIM-AD" -SimulationMode
    $simCim = Get-ComputerCimInfo -ComputerName "SIM-CIM" -SimulationMode
    Assert-Test "Helpers exportados simulam sem consultas" (
        $simAD.Success -and $simAD.IsSimulated -and
        $null -eq $simAD.Data.Found -and
        $simCim.Success -and $simCim.IsSimulated -and
        $null -eq $simCim.Data.Connectivity.Reachable
    )

    $previewInventory = Get-ComputerInventory -ComputerName "PREVIEW" -Preview
    $previewAD = Get-ComputerADInfo -Hostname "PREVIEW-AD" -Preview
    $previewCim = Get-ComputerCimInfo -ComputerName "PREVIEW-CIM" -Preview
    Assert-Test "Preview explícito é não cancelado nas três funções" (
        $previewInventory.Mode -eq "Preview" -and -not $previewInventory.Cancelled -and
        $previewInventory.CollectionStatus -eq "Preview" -and
        $previewAD.Mode -eq "Preview" -and -not $previewAD.Cancelled -and
        $previewAD.CollectionStatus -eq "Preview" -and $previewAD.QueryStatus -eq "NotQueried" -and
        $previewCim.Mode -eq "Preview" -and -not $previewCim.Cancelled
    )

    $whatIfInventory = Get-ComputerInventory -ComputerName "WHATIF" -AllowRealOperation -WhatIf
    $whatIfAD = Get-ComputerADInfo -Hostname "WHATIF-AD" -AllowRealOperation -WhatIf
    $whatIfCim = Get-ComputerCimInfo -ComputerName "WHATIF-CIM" -AllowRealOperation -WhatIf
    Assert-Test "WhatIf é Preview não cancelado nas três funções" (
        $whatIfInventory.Mode -eq "Preview" -and -not $whatIfInventory.Cancelled -and
        $whatIfInventory.CollectionStatus -eq "Preview" -and
        $whatIfAD.Mode -eq "Preview" -and -not $whatIfAD.Cancelled -and
        $whatIfCim.Mode -eq "Preview" -and -not $whatIfCim.Cancelled
    )

    $noModeInventory = Get-ComputerInventory -ComputerName "NO-MODE"
    $noModeAD = Get-ComputerADInfo -Hostname "NO-MODE-AD"
    $noModeCim = Get-ComputerCimInfo -ComputerName "NO-MODE-CIM"
    Assert-Test "Sem modo as três funções falham sem coleta" (
        (-not $noModeInventory.Success) -and $noModeInventory.Error -match "Modo obrigatório" -and
        (-not $noModeAD.Success) -and $noModeAD.Error -match "Modo obrigatório" -and
        (-not $noModeCim.Success) -and $noModeCim.Error -match "Modo obrigatório"
    )

    $conflictInventory = Get-ComputerInventory -ComputerName "CONFLICT" -SimulationMode -AllowRealOperation
    $conflictAD = Get-ComputerADInfo -Hostname "CONFLICT-AD" -Preview -AllowRealOperation
    $conflictCim = Get-ComputerCimInfo -ComputerName "CONFLICT-CIM" -SimulationMode -Preview
    Assert-Test "Combinações conflitantes são rejeitadas nas três funções" (
        $conflictInventory.Error -match "Modos conflitantes" -and
        $conflictAD.Error -match "Modos conflitantes" -and
        $conflictCim.Error -match "Modos conflitantes"
    )

    Assert-Test "Simulation, Preview, WhatIf e rejeições mantêm zero chamadas externas" (
        (Get-ExternalCallCount) -eq 0 -and $global:ComputerCoreIsolationState.Calls.ShouldProcess -eq 0
    )

    # Deterministically model a declined confirmation without prompting a
    # human or invoking the actual ShouldProcess implementation.
    $global:ComputerCoreIsolationState.Decision = $false
    $cancelInventory = Get-ComputerInventory -ComputerName "CANCEL" -AllowRealOperation -Confirm
    $cancelAD = Get-ComputerADInfo -Hostname "CANCEL-AD" -AllowRealOperation -Confirm
    $cancelCim = Get-ComputerCimInfo -ComputerName "CANCEL-CIM" -AllowRealOperation -Confirm
    $cancelResults = @($cancelInventory, $cancelAD, $cancelCim)
    Assert-Test "Confirm recusado retorna cancelamento uniforme" (
        @($cancelResults | Where-Object {
            -not $_.Success -and $_.Mode -eq "Preview" -and $_.Cancelled -and
            $_.Status -eq "Cancelled" -and $_.CollectionStatus -eq "Cancelled" -and
            $_.Message -match "cancelada"
        }).Count -eq 3
    )
    Assert-Test "Confirm recusado não alcança fronteiras externas" (
        (Get-ExternalCallCount) -eq 0 -and
        $global:ComputerCoreIsolationState.Calls.ShouldProcess -eq 3
    )

    # Real helper calls remain isolated by the module-scoped fixtures above.
    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.Decision = $true
    $adFound = Get-ComputerADInfo -Hostname "AD-FOUND" -AllowRealOperation
    Assert-Test "AD válido retorna Found=true e estado Found" (
        $adFound.Success -and $adFound.Data.Found -eq $true -and
        $adFound.QueryStatus -eq "Found" -and $adFound.Data.QueryStatus -eq "Found"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ADBehavior = "Null"
    $adNotFound = Get-ComputerADInfo -Hostname "AD-NOT-FOUND" -AllowRealOperation
    Assert-Test "AD sem resultado normal retorna Found=false e NotFound" (
        $adNotFound.Success -and $adNotFound.Data.Found -eq $false -and
        $adNotFound.QueryStatus -eq "NotFound" -and $adNotFound.CollectionStatus -eq "Complete"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ADBehavior = "Error"
    $adError = Get-ComputerADInfo -Hostname "AD-ERROR" -AllowRealOperation
    Assert-Test "Erro AD mantém Found nulo e detalhes do erro" (
        (-not $adError.Success) -and $null -eq $adError.Data.Found -and
        $adError.QueryStatus -eq "Error" -and $adError.Error -match "Fixture AD query failure"
    )

    Reset-ExternalCallCounts
    $cimComplete = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "CIM com dados retorna Complete" (
        $cimComplete.Success -and $cimComplete.QueryStatus -eq "Complete" -and
        $cimComplete.CollectionStatus -eq "Complete"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.CimNullClasses = @("Win32_OperatingSystem")
    $cimNoData = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Resultado CIM nulo é distinto de erro e preserva dados parciais" (
        $cimNoData.Success -and $cimNoData.QueryStatus -eq "Partial" -and
        $cimNoData.CollectionStatus -eq "Partial" -and
        $cimNoData.Data.QueryStates.OperatingSystem -eq "NoData" -and
        $null -eq $cimNoData.Data.OperatingSystem.Caption
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.CimErrorClasses = @("Win32_OperatingSystem")
    $cimError = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Erro CIM mantém estado parcial e erro por seção" (
        $cimError.Success -and $cimError.QueryStatus -eq "Partial" -and
        $cimError.CollectionStatus -eq "Partial" -and
        @($cimError.Errors | Where-Object { $_.Message -match "Fixture CIM query failure" }).Count -eq 1
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.CimNullClasses = @(
        "Win32_ComputerSystem", "Win32_OperatingSystem", "Win32_Processor",
        "Win32_BIOS", "Win32_ComputerSystemProduct", "Win32_LogicalDisk",
        "Win32_NetworkAdapterConfiguration"
    )
    $cimAllNull = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "CIM sem resultados tem QueryStatus NoData e CollectionStatus Error" (
        (-not $cimAllNull.Success) -and $cimAllNull.QueryStatus -eq "NoData" -and
        $cimAllNull.CollectionStatus -eq "Error" -and $cimAllNull.Error -match "no usable data"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "Responded"
    $connectivityResponded = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "StatusCode de Test-Connection confirma Responded" (
        $connectivityResponded.Data.Connectivity.Reachable -eq $true -and
        $connectivityResponded.Data.Connectivity.Status -eq "Responded"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "ModernResponded"
    $connectivityModern = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Status textual de Test-Connection confirma Responded" (
        $connectivityModern.Data.Connectivity.Reachable -eq $true -and
        $connectivityModern.Data.Connectivity.Status -eq "Responded"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "NoResponse"
    $connectivityNoResponse = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "StatusCode sem resposta retorna Reachable=false" (
        $connectivityNoResponse.Data.Connectivity.Reachable -eq $false -and
        $connectivityNoResponse.Data.Connectivity.Status -eq "NoResponse"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "StatusCodeError"
    $connectivityStatusError = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "StatusCode ICMP de erro não vira NoResponse" (
        $null -eq $connectivityStatusError.Data.Connectivity.Reachable -and
        $connectivityStatusError.Data.Connectivity.Status -eq "Error"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "ModernNoResponse"
    $connectivityModernNoResponse = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Status textual sem resposta retorna Reachable=false" (
        $connectivityModernNoResponse.Data.Connectivity.Reachable -eq $false -and
        $connectivityModernNoResponse.Data.Connectivity.Status -eq "NoResponse"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "Empty"
    $connectivityEmpty = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Probe concluído sem resposta retorna NoResponse" (
        $connectivityEmpty.Data.Connectivity.Reachable -eq $false -and
        $connectivityEmpty.Data.Connectivity.Status -eq "NoResponse"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "Error"
    $connectivityError = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Erro Test-Connection mantém Reachable nulo e estado Error" (
        $null -eq $connectivityError.Data.Connectivity.Reachable -and
        $connectivityError.Data.Connectivity.Status -eq "Error" -and
        @($connectivityError.Errors | Where-Object { $_.Source -eq "Connectivity" }).Count -eq 1
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "Unknown"
    $connectivityUnknown = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Tipo de resposta desconhecido não vira false" (
        $null -eq $connectivityUnknown.Data.Connectivity.Reachable -and
        $connectivityUnknown.Data.Connectivity.Status -eq "Error"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.BitLockerBehavior = "Error"
    $bitLockerPartial = Get-ComputerCimInfo -ComputerName "." -AllowRealOperation
    Assert-Test "Falha BitLocker é preservada como erro parcial" (
        $bitLockerPartial.Success -and $bitLockerPartial.CollectionStatus -eq "Partial" -and
        $bitLockerPartial.Data.BitLocker.Status -eq "NotAvailable" -and
        @($bitLockerPartial.Errors | Where-Object { $_.Source -eq "BitLocker" }).Count -eq 1
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ADBehavior = "Error"
    $partialADFailure = Get-ComputerInventory -ComputerName "." -AllowRealOperation
    Assert-Test "Falha AD preserva Found nulo e CIM parcial utilizável" (
        $partialADFailure.Success -and $partialADFailure.CollectionStatus -eq "Partial" -and
        $null -eq $partialADFailure.Data.AD.Found -and
        $partialADFailure.Data.AD.QueryStatus -eq "Error" -and
        $partialADFailure.Data.System.Model -eq "Fixture Model"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ADBehavior = "Null"
    $adNotFoundInventory = Get-ComputerInventory -ComputerName "." -AllowRealOperation
    Assert-Test "AD NotFound é sucesso de consulta e não falha parcial" (
        $adNotFoundInventory.Success -and $adNotFoundInventory.CollectionStatus -eq "Complete" -and
        $adNotFoundInventory.Data.AD.Found -eq $false -and
        $adNotFoundInventory.Data.AD.QueryStatus -eq "NotFound"
    )

    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.ConnectivityBehavior = "Error"
    $global:ComputerCoreIsolationState.CimErrorClasses = @(
        "Win32_ComputerSystem", "Win32_OperatingSystem", "Win32_Processor",
        "Win32_BIOS", "Win32_ComputerSystemProduct", "Win32_LogicalDisk",
        "Win32_NetworkAdapterConfiguration"
    )
    $partialCimFailure = Get-ComputerInventory -ComputerName "." -AllowRealOperation
    Assert-Test "Falha CIM preserva AD e não inventa conectividade" (
        $partialCimFailure.Success -and $partialCimFailure.CollectionStatus -eq "Partial" -and
        $partialCimFailure.Data.AD.Found -eq $true -and
        $null -eq $partialCimFailure.Data.Connectivity.Reachable -and
        $partialCimFailure.Data.QueryStatus.CIM -eq "Error"
    )

    # Authorized paths use fixtures for every boundary; Invoke-Command returns
    # canned output and never invokes the remote ScriptBlock.
    Reset-ExternalCallCounts
    $global:ComputerCoreIsolationState.Decision = $true
    $localInventory = Get-ComputerInventory -ComputerName "." -AllowRealOperation
    Assert-Test "Fluxo local autorizado completa com fixtures" (
        $localInventory.Success -and $localInventory.Mode -eq "Real" -and
        $localInventory.Data.AD.Found -and $localInventory.Data.Connectivity.Reachable -and
        $global:ComputerCoreIsolationState.Calls.GetADComputer -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.GetCimInstance -eq 7 -and
        $global:ComputerCoreIsolationState.Calls.GetBitLockerVolume -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.TestConnection -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.InvokeCommand -eq 0
    )

    Reset-ExternalCallCounts
    $remoteInventory = Get-ComputerInventory -ComputerName "MOCK-REMOTE" -AllowRealOperation
    Assert-Test "Fluxo remoto autorizado usa fixtures e remoting stub" (
        $remoteInventory.Success -and $remoteInventory.Mode -eq "Real" -and
        $global:ComputerCoreIsolationState.Calls.GetADComputer -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.GetCimInstance -eq 7 -and
        $global:ComputerCoreIsolationState.Calls.InvokeCommand -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.GetBitLockerVolume -eq 0 -and
        $global:ComputerCoreIsolationState.Calls.TestConnection -eq 1 -and
        $global:ComputerCoreIsolationState.RemoteScriptBlockReceived -and
        -not $global:ComputerCoreIsolationState.RemoteScriptBlockExecuted -and
        @($global:ComputerCoreIsolationState.CimTargets | Where-Object { $_ -ne "MOCK-REMOTE" }).Count -eq 0
    )

    Assert-Test "Todas as fronteiras externas autorizadas ficaram stubadas" (
        $global:ComputerCoreIsolationState.Calls.GetModule -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.ImportModule -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.GetADComputer -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.GetCimInstance -eq 7 -and
        $global:ComputerCoreIsolationState.Calls.InvokeCommand -eq 1 -and
        $global:ComputerCoreIsolationState.Calls.TestConnection -eq 1 -and
        -not $global:ComputerCoreIsolationState.RemoteScriptBlockExecuted
    )
}
catch {
    $script:Failed++
    Write-Host "[FAIL] Erro inesperado no teste de isolamento: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Remove-Module $module.Name -ErrorAction SilentlyContinue
    Remove-Variable ComputerCoreIsolationState -Scope Global -ErrorAction SilentlyContinue
}

Write-Host "Total: $($script:Passed + $script:Failed) | PASS: $script:Passed | FAIL: $script:Failed"
if ($script:Failed -gt 0) { exit 1 }
exit 0
