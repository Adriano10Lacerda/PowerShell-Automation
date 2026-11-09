$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        $script:Failed++
    }
}

$modulePath = Join-Path $PSScriptRoot "Computer-Management.psm1"
$hostname = "COMPUTER-MOCK"
$global:ComputerManagementUnexpectedExternalCalls = 0

$inventoryFixture = [PSCustomObject]@{
    Success = $true
    Error   = $null
    Mode = "Simulation"
    Status = "Simulated"
    SimulationMode = $true
    Preview = $false
    IsSimulated = $true
    Cancelled = $false
    Data    = [PSCustomObject]@{
        Hostname           = $hostname
        CollectionDateTime = [datetime]::UtcNow
        AD                 = [PSCustomObject]@{ Found = $true; QueryStatus = "NotQueried"; IsSimulated = $true }
        Connectivity       = [PSCustomObject]@{ Reachable = $true; Status = "Responded"; IsSimulated = $true }
        System             = [PSCustomObject]@{ Model = "Mock Model" }
        OperatingSystem    = [PSCustomObject]@{ Caption = "Mock OS" }
        Processor          = [PSCustomObject]@{ Name = "Mock CPU" }
        Memory             = [PSCustomObject]@{ TotalGB = 8 }
        Storage            = @()
        Network            = @()
        BitLocker          = [PSCustomObject]@{ Status = "NotAvailable" }
        Errors             = @()
        QueryStatus        = [PSCustomObject]@{ ActiveDirectory = "NotQueried"; CIM = "NotQueried" }
    }
    CollectionStatus = "Simulation"
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " COMPUTER MANAGEMENT - TESTES" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

try {
    $managementModule = Import-Module $modulePath -Force -PassThru
    $coreModulePath = [System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "..\Computer-Functions.psm1")
    )
    $coreModule = $managementModule.NestedModules |
        Where-Object { $_.Path -eq $coreModulePath }

    if ($null -eq $coreModule) {
        throw "Computer Core importado não foi encontrado para instalar stubs fail-closed."
    }

    & $coreModule {
        Set-Item -LiteralPath "Function:\script:Get-ComputerADInfo" -Value {
            $global:ComputerManagementUnexpectedExternalCalls++
            throw "FAIL-CLOSED: consulta AD inesperada no teste Computer Management."
        } -Force

        Set-Item -LiteralPath "Function:\script:Get-ComputerCimInfo" -Value {
            $global:ComputerManagementUnexpectedExternalCalls++
            throw "FAIL-CLOSED: consulta CIM inesperada no teste Computer Management."
        } -Force
    }

    & $managementModule {
        param($Fixture)
        $script:ComputerManagementInventoryCallCount = 0
        $script:ComputerManagementInventoryCalls = @()
        $script:ComputerManagementInventoryFixture = $Fixture
        $script:ComputerManagementShouldProcessDecision = $true
        $script:ComputerManagementShouldProcessCallCount = 0

        Set-Item -LiteralPath "Function:\script:Get-ComputerInventory" -Value {
            [CmdletBinding(SupportsShouldProcess = $true)]
            param(
                [string]$ComputerName,
                [switch]$SimulationMode,
                [switch]$Preview,
                [switch]$AllowRealOperation
            )
            $script:ComputerManagementInventoryCallCount++
            $script:ComputerManagementInventoryCalls += @(@{
                Bound = @{} + $PSBoundParameters
                WhatIf = [bool]$WhatIfPreference
            })
            $fixture = $script:ComputerManagementInventoryFixture
            if ($fixture.Status -ne "Cancelled") {
                if ($SimulationMode) {
                    $fixture.Mode = "Simulation"; $fixture.Status = "Simulated"
                    $fixture.SimulationMode = $true; $fixture.Preview = $false
                    $fixture.IsSimulated = $true; $fixture.CollectionStatus = "Simulation"
                    $fixture.Data.AD.Found = $null; $fixture.Data.AD.QueryStatus = "NotQueried"
                    $fixture.Data.Connectivity.Reachable = $null; $fixture.Data.Connectivity.Status = "NotQueried"
                }
                elseif ($Preview -or $WhatIfPreference) {
                    $fixture.Mode = "Preview"; $fixture.Status = "Preview"
                    $fixture.SimulationMode = $false; $fixture.Preview = $true
                    $fixture.IsSimulated = $false; $fixture.CollectionStatus = "Preview"
                    $fixture.Data.AD.Found = $null; $fixture.Data.AD.QueryStatus = "NotQueried"
                    $fixture.Data.Connectivity.Reachable = $null; $fixture.Data.Connectivity.Status = "NotQueried"
                }
                else {
                    $fixture.Mode = "Real"
                    if ($fixture.CollectionStatus -notin @("Partial", "Error")) {
                        $fixture.Status = "Complete"; $fixture.CollectionStatus = "Complete"
                    }
                    $fixture.SimulationMode = $false; $fixture.Preview = $false
                    $fixture.IsSimulated = $false
                }
            }
            return $fixture
        } -Force
        Set-Item -LiteralPath "Function:\script:Invoke-ComputerManagementShouldProcess" -Value {
            param($Cmdlet, [string]$Target, [string]$Action)
            $script:ComputerManagementShouldProcessCallCount++
            return [bool]$script:ComputerManagementShouldProcessDecision
        } -Force
    } $inventoryFixture

    Assert-Test "Modulo Computer-Management carregado." $true
}
catch {
    Assert-Test "Modulo Computer-Management carregado." $false
    Write-Host ""
    Write-Host "Erro ao carregar modulo:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}


# --------------------------------------------------
# TESTES DE DISPONIBILIDADE
# --------------------------------------------------

Assert-Test `
    "Get-ComputerManagement disponivel" `
    ($null -ne (Get-Command Get-ComputerManagement -ErrorAction SilentlyContinue))

Assert-Test `
    "Get-ComputerManagementSummary disponivel" `
    ($null -ne (Get-Command Get-ComputerManagementSummary -ErrorAction SilentlyContinue))

Assert-Test `
    "Test-ComputerManagement disponivel" `
    ($null -ne (Get-Command Test-ComputerManagement -ErrorAction SilentlyContinue))


# --------------------------------------------------
# TESTE DO MANAGEMENT
# --------------------------------------------------

$moduleTest = Test-ComputerManagement

Assert-Test `
    "Test-ComputerManagement executado" `
    ($null -ne $moduleTest)

Assert-Test `
    "Computer Core disponivel" `
    ($moduleTest.ComputerCoreAvailable -eq $true)

Assert-Test `
    "Computer Management disponivel" `
    ($moduleTest.ManagementAvailable -eq $true)


# --------------------------------------------------
# CONSULTA COM FIXTURE ISOLADA
# --------------------------------------------------

Write-Host ""
Write-Host "Consultando fixture isolada: $hostname" -ForegroundColor Yellow
Write-Host ""

$result = Get-ComputerManagement `
    -Hostname $hostname `
    -SimulationMode

if ($result.Mode -eq "Error") {
    Write-Host ("Management fixture error: " + (($result.Errors | ForEach-Object { $_.Message }) -join "; ")) -ForegroundColor Red
}


Assert-Test `
    "Resultado da consulta não é nulo" `
    ($null -ne $result)

Assert-Test `
    "Hostname retornado" `
    ($result.Hostname -eq $hostname.ToUpperInvariant())

Assert-Test `
    "SimulationMode identificado" `
    ($result.SimulationMode -eq $true)

Assert-Test `
    "Status retornado" `
    (-not [string]::IsNullOrWhiteSpace($result.Status))

Assert-Test `
    "Summary retornado" `
    ($null -ne $result.Summary)

Assert-Test `
    "Data retornada" `
    ($null -ne $result.Data)

Assert-Test `
    "Errors retornado" `
    ($null -ne $result.Errors)


# --------------------------------------------------
# TESTES DO SUMMARY
# --------------------------------------------------

if ($null -ne $result.Summary) {

    Assert-Test `
        "Summary possui Hostname" `
        ($result.Summary.Hostname -eq $hostname.ToUpperInvariant())

    Assert-Test `
        "Summary possui Status" `
        (-not [string]::IsNullOrWhiteSpace($result.Summary.Status))

    Assert-Test `
        "Summary possui ADFound" `
        ($null -eq $result.Summary.ADFound)

    Assert-Test `
        "Summary possui Reachable" `
        ($null -eq $result.Summary.Reachable)

    Assert-Test `
        "Summary possui ErrorCount" `
        ($null -ne $result.Summary.ErrorCount)

    Assert-Test `
        "Summary possui SimulationMode" `
        ($result.Summary.SimulationMode -eq $true)

    Assert-Test "Simulation informa Status Simulated" ($result.Summary.Status -eq "Simulated")
    Assert-Test "Simulation identifica dados demonstrativos" ($result.Summary.IsSimulated -eq $true)
}
else {
    Assert-Test "Summary possui Hostname" $false
    Assert-Test "Summary possui Status" $false
    Assert-Test "Summary possui ADFound" $false
    Assert-Test "Summary possui Reachable" $false
    Assert-Test "Summary possui ErrorCount" $false
    Assert-Test "Summary possui SimulationMode" $false
}


# --------------------------------------------------
# TESTES DO CORE DENTRO DO MANAGEMENT
# --------------------------------------------------

if ($null -ne $result.Data) {

    Assert-Test `
        "Data possui Hostname" `
        ($null -ne $result.Data.Hostname)

    Assert-Test `
        "Data possui CollectionDateTime" `
        ($null -ne $result.Data.CollectionDateTime)

    Assert-Test `
        "Data possui AD" `
        ($null -ne $result.Data.AD)

    Assert-Test `
        "Data possui Connectivity" `
        ($null -ne $result.Data.Connectivity)

    Assert-Test `
        "Data possui System" `
        ($null -ne $result.Data.System)

    Assert-Test `
        "Data possui OperatingSystem" `
        ($null -ne $result.Data.OperatingSystem)

    Assert-Test `
        "Data possui Processor" `
        ($null -ne $result.Data.Processor)

    Assert-Test `
        "Data possui Memory" `
        ($null -ne $result.Data.Memory)

    Assert-Test `
        "Data possui Storage" `
        ($null -ne $result.Data.Storage)

    Assert-Test `
        "Data possui Network" `
        ($null -ne $result.Data.Network)

    Assert-Test `
        "Data possui BitLocker" `
        ($null -ne $result.Data.BitLocker)

    Assert-Test `
        "Data possui Errors" `
        ($null -ne $result.Data.Errors)
}
else {
    Assert-Test "Data possui Hostname" $false
    Assert-Test "Data possui CollectionDateTime" $false
    Assert-Test "Data possui AD" $false
    Assert-Test "Data possui Connectivity" $false
    Assert-Test "Data possui System" $false
    Assert-Test "Data possui OperatingSystem" $false
    Assert-Test "Data possui Processor" $false
    Assert-Test "Data possui Memory" $false
    Assert-Test "Data possui Storage" $false
    Assert-Test "Data possui Network" $false
    Assert-Test "Data possui BitLocker" $false
    Assert-Test "Data possui Errors" $false
}


# --------------------------------------------------
# TESTE DE SUMMARY ISOLADO
# --------------------------------------------------

$summary = Get-ComputerManagementSummary `
    -Hostname $hostname `
    -SimulationMode

Assert-Test `
    "Get-ComputerManagementSummary retornou resultado" `
    ($null -ne $summary)

Assert-Test `
    "Summary isolado possui Hostname" `
    ($null -ne $summary.Hostname)

Assert-Test `
    "Summary isolado possui Status" `
    (-not [string]::IsNullOrWhiteSpace($summary.Status))

Assert-Test "Chamada sem modo falha fechada" ((Get-ComputerManagement -Hostname $hostname).Mode -eq "Error")
Assert-Test "Preview encaminha modo ao Core stub" ((Get-ComputerManagement -Hostname $hostname -Preview).Mode -eq "Preview")
Assert-Test "WhatIf encaminha modo ao Core stub" ((Get-ComputerManagement -Hostname $hostname -WhatIf).Mode -eq "Preview")
$realFixtureResult = Get-ComputerManagement -Hostname $hostname -AllowRealOperation -Confirm:$false
Assert-Test "AllowRealOperation encaminha autorização ao Core stub" ($realFixtureResult.Mode -eq "Real")
$conflictingResult = Get-ComputerManagement -Hostname $hostname -SimulationMode -AllowRealOperation
Assert-Test "Modos conflitantes falham sem chamar Core" ($conflictingResult.Mode -eq "Error")
$previewRealConflict = Get-ComputerManagement -Hostname $hostname -Preview -AllowRealOperation
Assert-Test "Preview explícito combinado com autorização real é rejeitado" ($previewRealConflict.Mode -eq "Error" -and $previewRealConflict.CollectionStatus -eq "Error")
$forwardedCalls = & $managementModule { $script:ComputerManagementInventoryCalls }
Assert-Test "Core stub recebeu SimulationMode" ($forwardedCalls[0].Bound.SimulationMode -eq $true)
Assert-Test "Core stub recebeu Preview" (($forwardedCalls | Where-Object { $_.Bound.Preview -eq $true }).Count -ge 1)
Assert-Test "WhatIf não recebe autorização real" (($forwardedCalls | Where-Object { $_.WhatIf -and $_.Bound.AllowRealOperation }).Count -eq 0)
Assert-Test "AllowRealOperation só foi encaminhado na chamada autorizada" (@($forwardedCalls | Where-Object { $_.Bound.AllowRealOperation.IsPresent }).Count -eq 1)
$whatIfRealResult = Get-ComputerManagement -Hostname $hostname -AllowRealOperation -WhatIf
Assert-Test "WhatIf com AllowRealOperation resolve Preview antes da confirmação" ($whatIfRealResult.Mode -eq "Preview" -and $whatIfRealResult.Status -eq "Preview" -and -not $whatIfRealResult.Cancelled)
$whatIfRealSummary = Get-ComputerManagementSummary -Hostname $hostname -AllowRealOperation -WhatIf
Assert-Test "Summary não converte WhatIf com autorização em cancelamento" ($whatIfRealSummary.Mode -eq "Preview" -and $whatIfRealSummary.Status -eq "Preview" -and -not $whatIfRealSummary.Cancelled)
$whatIfRealCall = (& $managementModule { $script:ComputerManagementInventoryCalls[-1] })
Assert-Test "WhatIf com autorização encaminha Preview sem AllowRealOperation" ($whatIfRealCall.Bound.Preview.IsPresent -and -not $whatIfRealCall.Bound.AllowRealOperation.IsPresent)
$previewSummary = Get-ComputerManagementSummary -Hostname $hostname -Preview
Assert-Test "Summary preserva Mode Preview" ($previewSummary.Mode -eq "Preview" -and $previewSummary.Preview -eq $true)
Assert-Test "Preview tem Status Preview e SimulationMode falso" ($previewSummary.Status -eq "Preview" -and -not $previewSummary.SimulationMode -and -not $previewSummary.IsSimulated)
Assert-Test "Summary inclui sucesso, erros e estado de coleta" ($null -ne $previewSummary.PSObject.Properties["Success"] -and $null -ne $previewSummary.PSObject.Properties["Errors"] -and $previewSummary.CollectionStatus -eq "Preview")
$whatIfSummary = Get-ComputerManagementSummary -Hostname $hostname -WhatIf
Assert-Test "Summary preserva WhatIf como Preview" ($whatIfSummary.Mode -eq "Preview" -and $whatIfSummary.Preview -eq $true)
$cancelledFixture = [PSCustomObject]@{
    Success = $false; Data = $null; Error = "Coleta cancelada"; Mode = "Preview"
    Status = "Cancelled"; Cancelled = $true; Preview = $true; SimulationMode = $false; IsSimulated = $false
}
& $managementModule { param($Fixture) $script:ComputerManagementInventoryFixture = $Fixture } $cancelledFixture
$cancelledSummary = Get-ComputerManagementSummary -Hostname $hostname -AllowRealOperation -Confirm:$false
Assert-Test "Summary preserva cancelamento do Core sem sucesso operacional" (-not $cancelledSummary.Success -and $cancelledSummary.Cancelled -and $cancelledSummary.Mode -eq "Preview")
& $managementModule { param($Fixture) $script:ComputerManagementInventoryFixture = $Fixture } $inventoryFixture

$beforeDeclineInventoryCalls = & $managementModule { $script:ComputerManagementInventoryCallCount }
& $managementModule { $script:ComputerManagementShouldProcessDecision = $false }
$declinedManagement = Get-ComputerManagement -Hostname $hostname -AllowRealOperation
$declinedSummary = Get-ComputerManagementSummary -Hostname $hostname -AllowRealOperation
& $managementModule { $script:ComputerManagementShouldProcessDecision = $true }
Assert-Test "ShouldProcess recusado retorna cancelamento uniforme no Management e Summary" (-not $declinedManagement.Success -and $declinedManagement.Cancelled -and $declinedManagement.Status -eq "Cancelled" -and $declinedManagement.CollectionStatus -eq "Cancelled" -and -not $declinedSummary.Success -and $declinedSummary.Cancelled -and $declinedSummary.Mode -eq "Preview")
Assert-Test "ShouldProcess recusado não encaminha consulta ao Core" ((& $managementModule { $script:ComputerManagementInventoryCallCount }) -eq $beforeDeclineInventoryCalls)

$partialFixture = [PSCustomObject]@{
    Success = $true; Error = "Consulta AD falhou"; Mode = "Real"; Status = "Partial"
    SimulationMode = $false; Preview = $false; IsSimulated = $false; Cancelled = $false
    CollectionStatus = "Partial"
    Data = [PSCustomObject]@{
        Hostname = $hostname; AD = [PSCustomObject]@{ Found = $null; QueryStatus = "Error" }
        Connectivity = [PSCustomObject]@{ Reachable = $false; Status = "NoResponse" }
        System = [PSCustomObject]@{ Model = "Valid Partial Model" }
        OperatingSystem = [PSCustomObject]@{ Caption = "Valid Partial OS" }
        Processor = [PSCustomObject]@{ Name = "Valid Partial CPU" }
        Memory = [PSCustomObject]@{ TotalGB = 8 }; BitLocker = [PSCustomObject]@{ Status = "Protected" }
        Errors = @([PSCustomObject]@{ Source = "ActiveDirectory"; Message = "Consulta AD falhou" })
        QueryStatus = [PSCustomObject]@{ ActiveDirectory = "Error"; CIM = "Complete" }
    }
}
& $managementModule { param($Fixture) $script:ComputerManagementInventoryFixture = $Fixture } $partialFixture
$partialResult = Get-ComputerManagement -Hostname $hostname -AllowRealOperation -Confirm:$false
$unknownFixture = $partialFixture
$unknownFixture.Data.AD.Found = $false; $unknownFixture.Data.AD.QueryStatus = "UnexpectedState"
$unknownFixture.Data.Connectivity.Reachable = $false; $unknownFixture.Data.Connectivity.Status = "UnexpectedState"
& $managementModule { param($Fixture) $script:ComputerManagementInventoryFixture = $Fixture } $unknownFixture
$unknownResult = Get-ComputerManagement -Hostname $hostname -AllowRealOperation -Confirm:$false
Assert-Test "Estados desconhecidos não convertem false em NotFound ou NoResponse" ($null -eq $unknownResult.Summary.ADFound -and $unknownResult.Summary.ADQueryStatus -eq "UnexpectedState" -and $null -eq $unknownResult.Summary.Reachable -and $unknownResult.Summary.ConnectivityStatus -eq "UnexpectedState")
Assert-Test "Falha AD não vira NotFound nem conectividade operacional desconhecida" ($partialResult.Summary.ADQueryStatus -eq "Error" -and $null -eq $partialResult.Summary.ADFound -and $partialResult.Summary.ConnectivityStatus -eq "NoResponse" -and $partialResult.Summary.Reachable -eq $false)
Assert-Test "Summary preserva Partial, estados de consulta, erros e dados CIM válidos" ($partialResult.CollectionStatus -eq "Partial" -and $partialResult.Summary.CollectionStatus -eq "Partial" -and $partialResult.Summary.QueryStatus.CIM -eq "Complete" -and $partialResult.Summary.Model -eq "Valid Partial Model" -and $partialResult.Summary.Errors.Count -eq 1)
$partialSummary = Get-ComputerManagementSummary -Hostname $hostname -AllowRealOperation -Confirm:$false
Assert-Test "Summary público preserva sucesso parcial, erro, consultas e dados válidos" ($partialSummary.Success -and $partialSummary.CollectionStatus -eq "Partial" -and $partialSummary.QueryStatus.ActiveDirectory -eq "Error" -and $partialSummary.Errors.Count -eq 1 -and $partialSummary.Model -eq "Valid Partial Model")
& $managementModule { param($Fixture) $script:ComputerManagementInventoryFixture = $Fixture } $inventoryFixture


# --------------------------------------------------
# TESTE DE HOSTNAME INVALIDO
# --------------------------------------------------

$invalidResult = Get-ComputerManagement `
    -Hostname "   " `
    -SimulationMode

Assert-Test `
    "Hostname invalido tratado sem crash" `
    ($null -ne $invalidResult)

Assert-Test `
    "Hostname invalido retorna Status Invalid" `
    ($invalidResult.Status -eq "Invalid")

Assert-Test `
    "Hostname invalido retorna Success False" `
    ($invalidResult.Success -eq $false)

Assert-Test `
    "Computer Core não recebeu chamadas AD/CIM externas" `
    ($global:ComputerManagementUnexpectedExternalCalls -eq 0)

Assert-Test `
    "Fixture foi utilizada somente nas consultas válidas" `
    ((& $managementModule { $script:ComputerManagementInventoryCallCount }) -eq (& $managementModule { $script:ComputerManagementInventoryCalls.Count }))


# --------------------------------------------------
# TESTE JSON
# --------------------------------------------------

$json = $result | ConvertTo-Json -Depth 20

Assert-Test `
    "Resultado pode ser convertido para JSON" `
    (-not [string]::IsNullOrWhiteSpace($json))


# --------------------------------------------------
# RESUMO
# --------------------------------------------------

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $($script:Passed + $script:Failed)"
Write-Host "PASS  : $script:Passed" -ForegroundColor Green
Write-Host "FAIL  : $script:Failed" -ForegroundColor Red

Write-Host ""

Remove-Variable ComputerManagementUnexpectedExternalCalls -Scope Global -ErrorAction SilentlyContinue

if ($script:Failed -eq 0) {
    Write-Host "COMPUTER MANAGEMENT: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "COMPUTER MANAGEMENT: EXISTEM TESTES COM FALHA!" -ForegroundColor Red
    exit 1
}
