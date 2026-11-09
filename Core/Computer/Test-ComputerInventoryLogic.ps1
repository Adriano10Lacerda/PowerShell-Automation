$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Computer-Functions.psm1"

$script:Passed = 0
$script:Failed = 0

# ------------------------------------------------------------
# FUNCAO DE ASSERT
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# RESULTADOS SIMULADOS
# ------------------------------------------------------------

function New-MockADResult {
    param(
        [bool]$Success
    )

    $data = $null
    $errorMessage = $null

    if ($Success) {
        $data = [PSCustomObject]@{
            ComputerName = "PC-TESTE"
            Found        = $true
            Manufacturer = "Fabricante Teste"
            Model        = "Modelo Teste"
        }
    }
    else {
        $errorMessage = "Falha simulada no Active Directory"
    }

    return [PSCustomObject]@{
        Success = $Success
        Data    = $data
        Error   = $errorMessage
    }
}

function New-MockCIMResult {
    param(
        [bool]$Success
    )

    $data = $null
    $errorMessage = $null

    if ($Success) {
        $data = [PSCustomObject]@{
            ComputerName = "PC-TESTE"
            Manufacturer = "Fabricante Teste"
            Model        = "Modelo Teste"
            SerialNumber = "SERIAL-123"
        }
    }
    else {
        $errorMessage = "Falha simulada no CIM"
    }

    return [PSCustomObject]@{
        Success = $Success
        Data    = $data
        Error   = $errorMessage
    }
}

# ------------------------------------------------------------
# MOCKS
# Estas funcoes substituem os coletores reais durante o teste.
# ------------------------------------------------------------

$script:MockADResult = $null
$script:MockCIMResult = $null
$script:ADCalls = 0
$script:CIMCalls = 0

function Get-ComputerADInfo {
    param(
        [string]$ComputerName
    )

    $script:ADCalls++
    return $script:MockADResult
}

function Get-ComputerCimInfo {
    param(
        [string]$ComputerName
    )

    $script:CIMCalls++
    return $script:MockCIMResult
}

# ------------------------------------------------------------
# CARREGAR A FUNCAO REAL DO ARQUIVO DO MODULO
# Sem importar o modulo e sem executar os coletores reais.
# ------------------------------------------------------------

try {
    if (-not (Test-Path -LiteralPath $ModulePath)) {
        throw "Arquivo nao encontrado: $ModulePath"
    }

    $tokens = $null
    $parseErrors = $null

    $moduleAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $ModulePath,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if ($parseErrors.Count -gt 0) {
        throw "O arquivo Computer-Functions.psm1 possui erro de sintaxe."
    }

    $inventoryFunctionAst = $moduleAst.Find(
        {
            param($node)

            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "Get-ComputerInventory"
        },
        $true
    )

    if ($null -eq $inventoryFunctionAst) {
        throw "A funcao Get-ComputerInventory nao foi encontrada."
    }

    # Carrega somente o agregador e helpers puros de modo/dados demonstrativos.
    # Os coletores externos nunca são carregados do módulo de produção.
    $pureHelperNames = @(
        "Resolve-ComputerCoreMode",
        "Invoke-ComputerCoreShouldProcess",
        "New-ComputerCoreCancelledResult",
        "New-ComputerCoreDemoADInfo",
        "New-ComputerCoreDemoCimInfo",
        "New-ComputerCoreModeResult"
    )
    foreach ($helperName in $pureHelperNames) {
        $helperAst = $moduleAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $helperName
        }, $true)
        if ($null -eq $helperAst) { throw "Helper puro não encontrado: $helperName" }
        . ([ScriptBlock]::Create($helperAst.Extent.Text))
    }
    . ([ScriptBlock]::Create($inventoryFunctionAst.Extent.Text))

    Assert-Test `
        -Name "Funcao Get-ComputerInventory carregada" `
        -Condition ($null -ne (Get-Command Get-ComputerInventory -ErrorAction SilentlyContinue))

    Assert-Test -Name "Coletores substituídos por fixtures locais" -Condition (
        (Get-Command Get-ComputerADInfo).CommandType -eq 'Function' -and
        (Get-Command Get-ComputerCimInfo).CommandType -eq 'Function'
    )

    # Modos sem coleta precisam sair antes dos helpers de AD/CIM.
    $beforeAD = $script:ADCalls; $beforeCIM = $script:CIMCalls
    $simulation = Get-ComputerInventory -ComputerName 'PC-DEMO' -SimulationMode
    $preview = Get-ComputerInventory -ComputerName 'PC-PREVIEW' -Preview
    $whatIf = Get-ComputerInventory -ComputerName 'PC-WHATIF' -AllowRealOperation -WhatIf
    Assert-Test -Name "Simulation retorna dados fictícios identificados" -Condition (
        $simulation.Mode -eq 'Simulation' -and $simulation.IsSimulated -and
        $simulation.Data.AD.Found -eq $null -and $simulation.Data.Connectivity.Reachable -eq $null
    )
    Assert-Test -Name "Preview não é marcado como Simulation" -Condition (
        $preview.Mode -eq 'Preview' -and $preview.Status -eq 'Preview' -and
        -not $preview.SimulationMode -and -not $preview.Cancelled
    )
    Assert-Test -Name "WhatIf com autorização produz Preview" -Condition (
        $whatIf.Mode -eq 'Preview' -and $whatIf.Status -eq 'Preview' -and -not $whatIf.Cancelled
    )
    Assert-Test -Name "Simulation, Preview e WhatIf não chamam fixtures AD/CIM" -Condition (
        $script:ADCalls -eq $beforeAD -and $script:CIMCalls -eq $beforeCIM
    )

    $noMode = Get-ComputerInventory -ComputerName 'PC-NO-MODE'
    Assert-Test -Name "Ausência de modo falha sem coletar" -Condition (
        -not $noMode.Success -and $noMode.CollectionStatus -eq 'Error' -and
        $script:ADCalls -eq $beforeAD -and $script:CIMCalls -eq $beforeCIM
    )

    $conflictSimulationPreview = Get-ComputerInventory -ComputerName 'PC-CONFLICT-1' -SimulationMode -Preview
    $conflictSimulationReal = Get-ComputerInventory -ComputerName 'PC-CONFLICT-2' -SimulationMode -AllowRealOperation
    Assert-Test -Name "Modos conflitantes falham de forma controlada" -Condition (
        -not $conflictSimulationPreview.Success -and
        -not $conflictSimulationReal.Success -and
        $conflictSimulationPreview.Error -like '*conflit*' -and
        $conflictSimulationReal.Error -like '*conflit*'
    )
    Assert-Test -Name "Modos conflitantes não chamam fixtures AD/CIM" -Condition (
        $script:ADCalls -eq $beforeAD -and $script:CIMCalls -eq $beforeCIM
    )

    $invalidNameRejected = $false
    try { Get-ComputerInventory -ComputerName '' -SimulationMode | Out-Null }
    catch { $invalidNameRejected = $true }
    Assert-Test -Name "ComputerName vazio é rejeitado antes de coleta" -Condition (
        $invalidNameRejected -and $script:ADCalls -eq $beforeAD -and $script:CIMCalls -eq $beforeCIM
    )

    # --------------------------------------------------------
    # CENARIO 1: AD E CIM FUNCIONANDO
    # --------------------------------------------------------

    $script:MockADResult = New-MockADResult -Success $true
    $script:MockCIMResult = New-MockCIMResult -Success $true

    $result = Get-ComputerInventory -ComputerName "PC-TESTE" -AllowRealOperation -Confirm:$false

    Assert-Test `
        -Name "AD e CIM funcionando - Success True" `
        -Condition ($result.Success -eq $true)

    Assert-Test `
        -Name "AD e CIM funcionando - Errors vazio" `
        -Condition (@($result.Data.Errors).Count -eq 0)

    # --------------------------------------------------------
    # CENARIO 2: AD FALHA, CIM FUNCIONA
    # --------------------------------------------------------

    $script:MockADResult = New-MockADResult -Success $false
    $script:MockCIMResult = New-MockCIMResult -Success $true

    $result = Get-ComputerInventory -ComputerName "PC-TESTE" -AllowRealOperation -Confirm:$false

    Assert-Test `
        -Name "AD falha e CIM funciona - Success True" `
        -Condition ($result.Success -eq $true)

    $adErrorFound = @(
        $result.Data.Errors |
            Where-Object { $_.Source -eq "ActiveDirectory" }
    ).Count -gt 0

    Assert-Test `
        -Name "AD falha e CIM funciona - erro AD registrado" `
        -Condition $adErrorFound

    # --------------------------------------------------------
    # CENARIO 3: AD FUNCIONA, CIM FALHA
    # --------------------------------------------------------

    $script:MockADResult = New-MockADResult -Success $true
    $script:MockCIMResult = New-MockCIMResult -Success $false

    $result = Get-ComputerInventory -ComputerName "PC-TESTE" -AllowRealOperation -Confirm:$false

    Assert-Test `
        -Name "AD funciona e CIM falha - Success True" `
        -Condition ($result.Success -eq $true)

    $cimErrorFound = @(
        $result.Data.Errors |
            Where-Object { $_.Source -eq "CIM" }
    ).Count -gt 0

    Assert-Test `
        -Name "AD funciona e CIM falha - erro CIM registrado" `
        -Condition $cimErrorFound

    # --------------------------------------------------------
    # CENARIO 4: AD E CIM FALHAM
    # --------------------------------------------------------

    $script:MockADResult = New-MockADResult -Success $false
    $script:MockCIMResult = New-MockCIMResult -Success $false

    $result = Get-ComputerInventory -ComputerName "PC-TESTE" -AllowRealOperation -Confirm:$false

    Assert-Test `
        -Name "AD e CIM falham - Success False" `
        -Condition ($result.Success -eq $false)

    Assert-Test `
        -Name "AD e CIM falham - dois erros registrados" `
        -Condition (@($result.Data.Errors).Count -eq 2)

    Assert-Test `
        -Name "AD e CIM falham - mensagens específicas preservadas" `
        -Condition (
            $result.Error -like "*Falha simulada no Active Directory*" -and
            $result.Error -like "*Falha simulada no CIM*"
        )

    Assert-Test -Name "Caminho autorizado atingiu somente os coletores fixture esperados" -Condition (
        $script:ADCalls -eq 4 -and $script:CIMCalls -eq 4
    )
}
catch {
    Write-Host ""
    Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
    $script:Failed++
}

# ------------------------------------------------------------
# RESUMO
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host " RESULTADO DOS TESTES"
Write-Host "========================================"
Write-Host "Total : $($script:Passed + $script:Failed)"
Write-Host "PASS  : $script:Passed"
Write-Host "FAIL  : $script:Failed"
Write-Host "========================================"

if ($script:Failed -eq 0) {
    Write-Host "TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}
