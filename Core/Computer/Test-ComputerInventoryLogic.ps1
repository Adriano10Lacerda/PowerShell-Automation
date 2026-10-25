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

function Get-ComputerADInfo {
    param(
        [string]$ComputerName
    )

    return $script:MockADResult
}

function Get-ComputerCimInfo {
    param(
        [string]$ComputerName
    )

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

    # Carrega a definicao real da funcao no escopo deste teste.
    . ([ScriptBlock]::Create($inventoryFunctionAst.Extent.Text))

    Assert-Test `
        -Name "Funcao Get-ComputerInventory carregada" `
        -Condition ($null -ne (Get-Command Get-ComputerInventory -ErrorAction SilentlyContinue))

    # --------------------------------------------------------
    # CENARIO 1: AD E CIM FUNCIONANDO
    # --------------------------------------------------------

    $script:MockADResult = New-MockADResult -Success $true
    $script:MockCIMResult = New-MockCIMResult -Success $true

    $result = Get-ComputerInventory -ComputerName "PC-TESTE"

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

    $result = Get-ComputerInventory -ComputerName "PC-TESTE"

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

    $result = Get-ComputerInventory -ComputerName "PC-TESTE"

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

    $result = Get-ComputerInventory -ComputerName "PC-TESTE"

    Assert-Test `
        -Name "AD e CIM falham - Success False" `
        -Condition ($result.Success -eq $false)

    Assert-Test `
        -Name "AD e CIM falham - dois erros registrados" `
        -Condition (@($result.Data.Errors).Count -eq 2)

    Assert-Test `
        -Name "AD e CIM falham - mensagem geral presente" `
        -Condition (
            $result.Error -eq
            "Não foi possível obter informações do computador via AD ou CIM."
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