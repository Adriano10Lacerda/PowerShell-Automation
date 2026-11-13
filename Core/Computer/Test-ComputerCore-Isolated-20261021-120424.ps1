$ErrorActionPreference = 'Stop'
$ModulePath=Join-Path $PSScriptRoot 'Computer-Functions.psm1'
$script:passed=0
$script:failed=0
function Assert-Test {
    param([string]$Name,[bool]$Condition)
    if ($Condition) { $script:passed++; Write-Host "[PASS] $Name" }
    else { $script:failed++; Write-Host "[FAIL] $Name" }
}
# Fixture-only harness: production collectors are never loaded.
$script:ExternalCalls = 0
$script:ADCalls = 0
$script:CIMCalls = 0
$script:CancelFixtureCollection = $false
$FixtureTarget = 'TEST-PC-SIMULADO'
$FailureTarget = 'COMPUTER-THAT-DOES-NOT-EXIST-999999'
function Deny-FixtureExternalCall {
    $script:ExternalCalls++
    throw 'External command blocked by Computer Core fixture harness.'
}
function Get-ADComputer { Deny-FixtureExternalCall }
function Get-CimInstance { Deny-FixtureExternalCall }
function Get-BitLockerVolume { Deny-FixtureExternalCall }
function Invoke-Command { Deny-FixtureExternalCall }
function Test-Connection { Deny-FixtureExternalCall }
function Assert-FixtureRequest {
    param([string]$Target, [bool]$Authorized, [bool]$Simulation, [bool]$Preview)
    if (-not $Authorized -or $Simulation -or $Preview) { throw 'Fixture requires explicit real-path authorization only.' }
    if ($Target -cnotin @('TEST-PC-SIMULADO','COMPUTER-THAT-DOES-NOT-EXIST-999999')) { throw 'Target is outside fixture allowlist.' }
}
function Get-ComputerADInfo {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Hostname,
        [switch]$SimulationMode, [switch]$Preview, [switch]$AllowRealOperation)
    $script:ADCalls++
    Assert-FixtureRequest $Hostname ([bool]$AllowRealOperation) ([bool]$SimulationMode) ([bool]$Preview -or [bool]$WhatIfPreference)
    $ok = $Hostname -ceq 'TEST-PC-SIMULADO'
    [PSCustomObject]@{
        Success=$ok; Data=$(if ($ok) { [PSCustomObject]@{ Found=$true; Name=$Hostname; Enabled=$true } } else { $null })
        Error=$(if ($ok) { $null } else { 'Falha AD simulada' })
        QueryStatus=$(if ($ok) { 'Complete' } else { 'Error' })
        CollectionStatus=$(if ($ok) { 'Complete' } else { 'Error' })
        Mode='Real'; IsSimulated=$false; SimulationMode=$false; Preview=$false; Cancelled=$false
        Status=$(if ($ok) { 'Collected' } else { 'Error' })
    }
}
function Get-ComputerCimInfo {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ComputerName,
        [switch]$SimulationMode, [switch]$Preview, [switch]$AllowRealOperation)
    $script:CIMCalls++
    Assert-FixtureRequest $ComputerName ([bool]$AllowRealOperation) ([bool]$SimulationMode) ([bool]$Preview -or [bool]$WhatIfPreference)
    $ok = $ComputerName -ceq 'TEST-PC-SIMULADO'
    $data = $null
    if ($ok) {
        $data = [PSCustomObject]@{
            System=[PSCustomObject]@{ Manufacturer='MOCK-OK'; Model='ModeloTeste'; SerialNumber='SERIAL-TESTE' }
            OperatingSystem=[PSCustomObject]@{ Caption='Windows Teste' }
            Processor=[PSCustomObject]@{ Name='CPU Teste' }
            Memory=[PSCustomObject]@{ TotalGB=8 }
            Storage=@([PSCustomObject]@{ DeviceID='C:'; SizeGB=100 })
            Network=@([PSCustomObject]@{ Name='Rede Teste' })
            BitLocker=[PSCustomObject]@{ Status='NotAvailable'; Volumes=@(); Error=$null }
            Connectivity=[PSCustomObject]@{ Reachable=$true; Status='Responded'; ResponseTimeMs=1; Error=$null }
        }
    }
    [PSCustomObject]@{
        Success=$ok; Data=$data; Error=$(if ($ok) { $null } else { 'Falha CIM simulada' })
        Errors=@(if (-not $ok) { [PSCustomObject]@{ Source='CIM'; Message='Falha CIM simulada' } })
        QueryStatus=$(if ($ok) { 'Complete' } else { 'Error' })
        CollectionStatus=$(if ($ok) { 'Complete' } else { 'Error' })
        Mode='Real'; IsSimulated=$false; SimulationMode=$false; Preview=$false; Cancelled=$false
        Status=$(if ($ok) { 'Collected' } else { 'Error' })
    }
}
function Get-FixtureFunctionSource {
    param([string]$Path, [string[]]$Names)
    $tokens=$null; $errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { throw "Parser rejected fixture source: $Path" }
    foreach ($name in $Names) {
        $matches=@($ast.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
        }, $true))
        if ($matches.Count -ne 1 -or $matches[0].Parent.Parent -ne $ast) { throw "Expected one top-level allowlisted function: $name" }
        $matches[0].Extent.Text
    }
}
try {
    # Extract only pure helpers and aggregator; never import production modules.
    $names=@('Resolve-ComputerCoreMode','Invoke-ComputerCoreShouldProcess','New-ComputerCoreCancelledResult',
        'New-ComputerCoreDemoADInfo','New-ComputerCoreDemoCimInfo','New-ComputerCoreModeResult','Get-ComputerInventory')
    foreach ($source in @(Get-FixtureFunctionSource $ModulePath $names)) { . ([scriptblock]::Create($source)) }
    # Deterministic ShouldProcess seam; no host prompts and cancellation is observable.
    function Invoke-ComputerCoreShouldProcess {
        param([System.Management.Automation.PSCmdlet]$Cmdlet,[string]$Target,[string]$Action)
        return (-not $script:CancelFixtureCollection)
    }
    # Resolve by normal precedence: a same-name alias must never bypass fixtures.
    foreach ($commandName in @('Get-ComputerADInfo','Get-ComputerCimInfo','Deny-FixtureExternalCall',
        'Assert-FixtureRequest','Get-ADComputer','Get-CimInstance','Get-BitLockerVolume','Invoke-Command','Test-Connection')) {
        $resolved=Microsoft.PowerShell.Core\Get-Command -Name $commandName -ErrorAction Stop
        if ($resolved.CommandType -ne 'Function' -or $resolved.ScriptBlock.File -cne $PSCommandPath) {
            throw "Fixture/sentinel command resolution was replaced: $commandName"
        }
    }
    foreach ($commandName in $names) {
        $resolved=Microsoft.PowerShell.Core\Get-Command -Name $commandName -ErrorAction Stop
        if ($resolved.CommandType -ne 'Function') { throw "Allowlisted function resolution was replaced: $commandName" }
    }
    $cim=Get-ComputerCimInfo -ComputerName $FixtureTarget -AllowRealOperation -Confirm:$false
    $beforeAD=$script:ADCalls; $beforeCIM=$script:CIMCalls
    $inventory=Get-ComputerInventory -ComputerName $FixtureTarget -AllowRealOperation -Confirm:$false
    Assert-Test 'Success fixture calls each collector exactly once' ($script:ADCalls -eq ($beforeAD+1) -and $script:CIMCalls -eq ($beforeCIM+1))
    Assert-Test 'Success fixture is Complete' ($inventory.CollectionStatus -ceq 'Complete')
    $beforeAD=$script:ADCalls; $beforeCIM=$script:CIMCalls
    $invalid=Get-ComputerInventory -ComputerName $FailureTarget -AllowRealOperation -Confirm:$false
    Assert-Test 'Failure fixture calls each collector exactly once' ($script:ADCalls -eq ($beforeAD+1) -and $script:CIMCalls -eq ($beforeCIM+1))
    Assert-Test 'Failure identifies both sources' (@($invalid.Data.Errors.Source) -contains 'ActiveDirectory' -and @($invalid.Data.Errors.Source) -contains 'CIM')
        $checks = @(
            @{ Name="CIM simulado retorna sucesso"; Pass=($cim.Success -eq $true) }
            @{ Name="CIM inclui fabricante"; Pass=($cim.Data.System.Manufacturer -eq "MOCK-OK") }
            @{ Name="CIM inclui sistema operacional"; Pass=(-not [string]::IsNullOrWhiteSpace($cim.Data.OperatingSystem.Caption)) }
            @{ Name="CIM inclui processador"; Pass=(-not [string]::IsNullOrWhiteSpace($cim.Data.Processor.Name)) }
            @{ Name="CIM inclui memória"; Pass=($cim.Data.Memory.TotalGB -gt 0) }
            @{ Name="CIM inclui armazenamento"; Pass=($cim.Data.Storage.Count -gt 0) }
            @{ Name="CIM inclui rede"; Pass=($cim.Data.Network.Count -gt 0) }
            @{ Name="CIM inclui BitLocker"; Pass=(-not [string]::IsNullOrWhiteSpace($cim.Data.BitLocker.Status)) }
            @{ Name="CIM BitLocker possui Volumes como array"; Pass=($cim.Data.BitLocker.Volumes -is [array]) }
            @{ Name="CIM BitLocker possui propriedade Error"; Pass=($null -ne $cim.Data.BitLocker.PSObject.Properties["Error"]) }
            @{ Name="CIM inclui conectividade"; Pass=($cim.Data.Connectivity.Reachable -eq $true) }
            @{ Name="Inventário retorna sucesso"; Pass=($inventory.Success -eq $true) }
            @{ Name="Hostname preservado"; Pass=($inventory.Data.Hostname -eq "TEST-PC-SIMULADO") }
            @{ Name="Data de coleta preenchida"; Pass=($null -ne $inventory.Data.CollectionDateTime) }
            @{ Name="Inventário inclui AD"; Pass=($null -ne $inventory.Data.AD) }
            @{ Name="Inventário inclui sistema"; Pass=($inventory.Data.System.Manufacturer -eq "MOCK-OK") }
            @{ Name="Inventário BitLocker possui Status"; Pass=(-not [string]::IsNullOrWhiteSpace($inventory.Data.BitLocker.Status)) }
            @{ Name="Inventário BitLocker possui Volumes como array"; Pass=($inventory.Data.BitLocker.Volumes -is [array]) }
            @{ Name="Inventário BitLocker possui propriedade Error"; Pass=($null -ne $inventory.Data.BitLocker.PSObject.Properties["Error"]) }
            @{ Name="Inventário inclui Errors"; Pass=($null -ne $inventory.Data.Errors) }
            @{ Name="Inventário sem erros simulados"; Pass=($inventory.Data.Errors.Count -eq 0) }
            @{ Name="JSON gerado"; Pass=(-not [string]::IsNullOrWhiteSpace(($inventory.Data | ConvertTo-Json -Depth 8))) }
            @{ Name="Hostname inválido tratado"; Pass=($null -ne $invalid) }
            @{ Name="Falhas AD e CIM registradas"; Pass=($invalid.Data.Errors.Count -eq 2 -and $invalid.CollectionStatus -ceq "Error") }
            @{ Name="Falha total retorna Success false"; Pass=($invalid.Success -eq $false) }
        )


    foreach ($check in $checks) { Assert-Test $check.Name $check.Pass }
    # Snapshot every negative path: collectors must not run before authorization.
    $beforeAD=$script:ADCalls; $beforeCIM=$script:CIMCalls
    foreach ($mode in @('Simulation','Preview','WhatIf','Missing','ConflictSP','ConflictSR','ConflictPR','ConflictSW')) {
        $parameters=@{ ComputerName=$FixtureTarget }
        switch ($mode) {
            'Simulation' { $parameters.SimulationMode=$true }
            'Preview' { $parameters.Preview=$true }
            'WhatIf' { $parameters.AllowRealOperation=$true; $parameters.WhatIf=$true }
            'ConflictSP' { $parameters.SimulationMode=$true; $parameters.Preview=$true }
            'ConflictSR' { $parameters.SimulationMode=$true; $parameters.AllowRealOperation=$true }
            'ConflictPR' { $parameters.Preview=$true; $parameters.AllowRealOperation=$true }
            'ConflictSW' { $parameters.SimulationMode=$true; $parameters.WhatIf=$true }
        }
        $modeResult=Get-ComputerInventory @parameters
        if ($mode -in @('Simulation','Preview','WhatIf')) {
            $expectedMode=if ($mode -eq 'Simulation') { 'Simulation' } else { 'Preview' }
            Assert-Test "Safe mode $mode returns identified demo data" ($modeResult.Success -and $modeResult.Mode -ceq $expectedMode -and $modeResult.IsSimulated)
        } else {
            Assert-Test "Invalid mode $mode fails closed" (-not $modeResult.Success -and $modeResult.Mode -ceq 'Error' -and -not [string]::IsNullOrWhiteSpace($modeResult.Error))
        }
        Assert-Test "Mode $mode does not invoke collectors" ($script:ADCalls -eq $beforeAD -and $script:CIMCalls -eq $beforeCIM)
    }
    $script:CancelFixtureCollection=$true
    try { $cancelled=Get-ComputerInventory -ComputerName $FixtureTarget -AllowRealOperation -Confirm:$false }
    finally { $script:CancelFixtureCollection=$false }
    Assert-Test 'Cancelled collection performs no fixture calls' ($cancelled.Cancelled -and -not $cancelled.Success -and $script:ADCalls -eq $beforeAD -and $script:CIMCalls -eq $beforeCIM)
    $emptyRejected=$false
    try { Get-ComputerInventory -ComputerName '' -SimulationMode | Out-Null } catch { $emptyRejected=$true }
    Assert-Test 'Empty target is rejected before collection' ($emptyRejected -and $script:ADCalls -eq $beforeAD -and $script:CIMCalls -eq $beforeCIM)
    foreach ($collector in @('Get-ComputerADInfo','Get-ComputerCimInfo')) {
        foreach ($scenario in @('Unauthorized','UnknownTarget','ConflictingMode','WhatIf')) {
            $p=if ($collector -ceq 'Get-ComputerADInfo') { @{ Hostname=$FixtureTarget } } else { @{ ComputerName=$FixtureTarget } }
            if ($scenario -ne 'Unauthorized') { $p.AllowRealOperation=$true }
            if ($scenario -eq 'ConflictingMode') { $p.SimulationMode=$true }
            if ($scenario -eq 'WhatIf') { $p.WhatIf=$true }
            if ($scenario -eq 'UnknownTarget') {
                if ($collector -ceq 'Get-ComputerADInfo') { $p.Hostname='OUTSIDE-FIXTURE' } else { $p.ComputerName='OUTSIDE-FIXTURE' }
            }
            $rejected=$false
            try { & $collector @p | Out-Null } catch { $rejected=$true }
            Assert-Test "$collector rejects $scenario" $rejected
        }
    }
} catch {
    Write-Host ('[FAIL] Harness: '+$_.Exception.Message)
    $script:failed++
} finally {
    Assert-Test 'External calls remained zero (including caught failures)' ($script:ExternalCalls -eq 0)
}
Write-Host "Fixture-only Computer Core: $script:passed passed; $script:failed failed."
if ($script:failed -gt 0) { exit 1 } else { exit 0 }