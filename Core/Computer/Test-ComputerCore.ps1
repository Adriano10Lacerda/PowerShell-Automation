# ============================================================
# PowerShell Automation - Computer Core Tests
# ============================================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Computer-Functions.psm1"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COMPUTER CORE - TESTES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$passed = 0
$failed = 0

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        $script:failed++
    }
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
# ------------------------------------------------------------
# TESTE 1 - Funções disponíveis
# ------------------------------------------------------------

Assert-Test `
    "Get-ComputerADInfo disponivel" `
    ($null -ne (Get-Command Get-ComputerADInfo -ErrorAction SilentlyContinue))

Assert-Test `
    "Get-ComputerCimInfo disponivel" `
    ($null -ne (Get-Command Get-ComputerCimInfo -ErrorAction SilentlyContinue))

Assert-Test `
    "Get-ComputerInventory disponivel" `
    ($null -ne (Get-Command Get-ComputerInventory -ErrorAction SilentlyContinue))


# ------------------------------------------------------------
# TESTE 2 - Computer Models
# ------------------------------------------------------------

$ModelsPath = Join-Path $PSScriptRoot "Computer-Models.ps1"

try {
    foreach ($source in @(Get-FixtureFunctionSource $ModelsPath @('New-ComputerInventoryModel'))) { . ([scriptblock]::Create($source)) }

    $model = New-ComputerInventoryModel `
        -Hostname "TEST-PC"

    Assert-Test `
        "Computer Model criado" `
        ($null -ne $model)

    Assert-Test `
        "Model possui Hostname" `
        ($model.Hostname -eq "TEST-PC")

    Assert-Test `
        "Model possui AD" `
        ($null -ne $model.AD)

    Assert-Test `
        "Model possui Connectivity" `
        ($null -ne $model.Connectivity)

    Assert-Test `
        "Model possui System" `
        ($null -ne $model.System)

    Assert-Test `
        "Model possui OperatingSystem" `
        ($null -ne $model.OperatingSystem)

    Assert-Test `
        "Model possui Processor" `
        ($null -ne $model.Processor)

    Assert-Test `
        "Model possui Memory" `
        ($null -ne $model.Memory)

    Assert-Test `
        "Model possui Storage" `
        ($null -ne $model.Storage)

    Assert-Test `
        "Model possui Network" `
        ($null -ne $model.Network)

    Assert-Test `
        "Model possui BitLocker" `
        ($null -ne $model.BitLocker)

    Assert-Test `
        "BitLocker do Model e um objeto" `
        ($model.BitLocker -is [PSCustomObject])

    Assert-Test `
        "BitLocker possui Status" `
        (-not [string]::IsNullOrWhiteSpace($model.BitLocker.Status))

    Assert-Test `
        "BitLocker possui Volumes como array" `
        ($model.BitLocker.Volumes -is [array])

    Assert-Test `
        "BitLocker possui propriedade Error" `
        ($null -ne $model.BitLocker.PSObject.Properties["Error"])

    Assert-Test `
        "Model possui Errors" `
        ($null -ne $model.Errors)
}
catch {
    Write-Host "[FAIL] Erro no Computer Model: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 3 - CIM fixture
# ------------------------------------------------------------

$cimResult = $null

try {

    $cimResult = Get-ComputerCimInfo `
        -ComputerName $FixtureTarget -AllowRealOperation -Confirm:$false

    Assert-Test `
        "CIM fixture executado com sucesso" `
        ($cimResult.Success -eq $true)

    Assert-Test `
        "CIM possui System" `
        ($null -ne $cimResult.Data.System)

    Assert-Test `
        "CIM possui OperatingSystem" `
        ($null -ne $cimResult.Data.OperatingSystem)

    Assert-Test `
        "CIM possui Processor" `
        ($null -ne $cimResult.Data.Processor)

    Assert-Test `
        "CIM possui Memory" `
        ($null -ne $cimResult.Data.Memory)

    Assert-Test `
        "CIM possui Storage" `
        ($null -ne $cimResult.Data.Storage)

    Assert-Test `
        "CIM possui Network" `
        ($null -ne $cimResult.Data.Network)

    Assert-Test `
        "CIM possui BitLocker" `
        ($null -ne $cimResult.Data.BitLocker)

    Assert-Test `
        "CIM possui Connectivity" `
        ($null -ne $cimResult.Data.Connectivity)

}
catch {
    Write-Host "[FAIL] Erro no teste CIM: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 4 - Dados do equipamento
# ------------------------------------------------------------

if ($cimResult -and $cimResult.Success) {

    Assert-Test `
        "Fabricante identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.System.Manufacturer
        ))

    Assert-Test `
        "Modelo identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.System.Model
        ))

    Assert-Test `
        "Serial identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.System.SerialNumber
        ))

    Assert-Test `
        "Sistema operacional identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.OperatingSystem.Caption
        ))

    Assert-Test `
        "Processador identificado" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.Processor.Name
        ))

    Assert-Test `
        "Memoria maior que zero" `
        ($cimResult.Data.Memory.TotalGB -gt 0)

    Assert-Test `
        "Storage coletado" `
        ($cimResult.Data.Storage.Count -gt 0)

    Assert-Test `
        "Network coletada" `
        ($cimResult.Data.Network.Count -gt 0)

    Assert-Test `
        "Connectivity Reachable" `
        ($cimResult.Data.Connectivity.Reachable -eq $true)

    Assert-Test `
        "BitLocker possui Status" `
        (-not [string]::IsNullOrWhiteSpace(
            $cimResult.Data.BitLocker.Status
        ))
}


# ------------------------------------------------------------
# TESTE 5 - Inventory consolidado
# ------------------------------------------------------------

$inventory = $null

try {

    $beforeAD=$script:ADCalls; $beforeCIM=$script:CIMCalls
    $inventory = Get-ComputerInventory `
        -ComputerName $FixtureTarget -AllowRealOperation -Confirm:$false

    Assert-Test 'Success fixture calls each collector exactly once' ($script:ADCalls -eq ($beforeAD+1) -and $script:CIMCalls -eq ($beforeCIM+1))
    Assert-Test 'Success fixture is Complete' ($inventory.CollectionStatus -ceq 'Complete')

    Assert-Test `
        "Computer Inventory executado com sucesso" `
        ($inventory.Success -eq $true)

    Assert-Test `
        "Inventory possui Hostname" `
        ($inventory.Data.Hostname -ceq $FixtureTarget)

    Assert-Test `
        "Inventory possui CollectionDateTime" `
        ($null -ne $inventory.Data.CollectionDateTime)

    Assert-Test `
        "Inventory possui AD" `
        ($null -ne $inventory.Data.AD)

    Assert-Test `
        "Inventory possui Connectivity" `
        ($null -ne $inventory.Data.Connectivity)

    Assert-Test `
        "Inventory possui System" `
        ($null -ne $inventory.Data.System)

    Assert-Test `
        "Inventory possui OperatingSystem" `
        ($null -ne $inventory.Data.OperatingSystem)

    Assert-Test `
        "Inventory possui Processor" `
        ($null -ne $inventory.Data.Processor)

    Assert-Test `
        "Inventory possui Memory" `
        ($null -ne $inventory.Data.Memory)

    Assert-Test `
        "Inventory possui Storage" `
        ($null -ne $inventory.Data.Storage)

    Assert-Test `
        "Inventory possui Network" `
        ($null -ne $inventory.Data.Network)

    Assert-Test `
        "Inventory possui BitLocker" `
        ($null -ne $inventory.Data.BitLocker)

    Assert-Test `
        "Inventory BitLocker possui Status" `
        (-not [string]::IsNullOrWhiteSpace(
        $inventory.Data.BitLocker.Status
    ))

     Assert-Test `
        "Inventory BitLocker possui Volumes como array" `
        ($inventory.Data.BitLocker.Volumes -is [array])

    Assert-Test `
        "Inventory BitLocker possui propriedade Error" `
        ($null -ne $inventory.Data.BitLocker.PSObject.Properties["Error"])

    Assert-Test `
        "Inventory possui Errors" `
        ($null -ne $inventory.Data.Errors)

}
catch {
    Write-Host "[FAIL] Erro no Inventory: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 6 - Tratamento de hostname invalido
# ------------------------------------------------------------

try {

    $beforeAD=$script:ADCalls; $beforeCIM=$script:CIMCalls
    $invalidResult = Get-ComputerInventory `
        -ComputerName $FailureTarget -AllowRealOperation -Confirm:$false

    Assert-Test 'Failure fixture calls each collector exactly once' ($script:ADCalls -eq ($beforeAD+1) -and $script:CIMCalls -eq ($beforeCIM+1))
    Assert-Test 'Failure identifies both sources' (@($invalidResult.Data.Errors.Source) -contains 'ActiveDirectory' -and @($invalidResult.Data.Errors.Source) -contains 'CIM')

    Assert-Test `
        "Hostname invalido tratado sem crash" `
        (-not $invalidResult.Success -and $invalidResult.Data.Errors.Count -eq 2 -and $invalidResult.CollectionStatus -ceq "Error")

}
catch {
    Write-Host "[FAIL] Hostname invalido causou excecao inesperada." -ForegroundColor Red
    $failed++
}


# ------------------------------------------------------------
# TESTE 7 - JSON
# ------------------------------------------------------------

try {

    $json = $inventory.Data |
        ConvertTo-Json -Depth 8

    Assert-Test `
        "Inventory pode ser convertido para JSON" `
        (-not [string]::IsNullOrWhiteSpace($json))

}
catch {
    Write-Host "[FAIL] Falha ao gerar JSON: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}



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
    Write-Host ('[FAIL] Harness: ' + $_.Exception.Message)
    $script:failed++
} finally {
    Assert-Test 'External calls remained zero (including caught failures)' ($script:ExternalCalls -eq 0)
}
# ------------------------------------------------------------
# RESULTADO
# ------------------------------------------------------------

$total = $passed + $failed

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $total"
Write-Host "PASS  : $passed" -ForegroundColor Green
Write-Host "FAIL  : $failed" -ForegroundColor Red

Write-Host ""

if ($failed -eq 0) {

    Write-Host "COMPUTER CORE: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {

    Write-Host "COMPUTER CORE: EXISTEM TESTES FALHANDO." -ForegroundColor Red
    exit 1
}