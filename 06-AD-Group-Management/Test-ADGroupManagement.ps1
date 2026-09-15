$ErrorActionPreference = "Stop"

# ============================================================
# Test-ADGroupManagement.ps1
# Testes automatizados do Module 06 - AD Group Management
# ============================================================

$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "Group-Functions.psm1"
$ConfigPath = Join-Path $ScriptPath "Group-Configuration.json"

$TestsPassed = 0
$TestsFailed = 0
$TotalTests = 0


function Test-Result {

    param (
        [Parameter(Mandatory = $true)]
        [string]$TestName,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Test
    )

    $script:TotalTests++

    try {

        & $Test

        Write-Host "[PASS] $TestName" -ForegroundColor Green
        $script:TestsPassed++
    }
    catch {

        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
        $script:TestsFailed++
    }
}


Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "     Testes - AD Group Management" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""


# ============================================================
# Teste 1 - Arquivo do módulo
# ============================================================

Test-Result `
    -TestName "Arquivo Group-Functions.psm1 encontrado" `
    -Test {

        if (-not (Test-Path $ModulePath)) {
            throw "O arquivo Group-Functions.psm1 não foi encontrado."
        }
    }


# ============================================================
# Teste 2 - Arquivo de configuração
# ============================================================

Test-Result `
    -TestName "Arquivo Group-Configuration.json encontrado" `
    -Test {

        if (-not (Test-Path $ConfigPath)) {
            throw "O arquivo Group-Configuration.json não foi encontrado."
        }
    }


# ============================================================
# Carregar módulo e configuração
# ============================================================

Import-Module $ModulePath -Force

$Configuration = Get-Content $ConfigPath -Raw | ConvertFrom-Json


# ============================================================
# Teste 3 - Configuração válida
# ============================================================

Test-Result `
    -TestName "Configuração válida" `
    -Test {

        Test-ADGroupConfiguration `
            -Configuration $Configuration |
            Out-Null
    }


# ============================================================
# Teste 4 - Modo de simulação
# ============================================================

Test-Result `
    -TestName "SimulationMode habilitado" `
    -Test {

        if ($Configuration.SimulationMode -ne $true) {
            throw "SimulationMode deveria estar habilitado."
        }
    }


# ============================================================
# Teste 5 - Grupo existente
# ============================================================

Test-Result `
    -TestName "Identificar grupo existente" `
    -Test {

        $Exists = Test-ADGroupExists `
            -GroupName "TI-Suporte" `
            -Configuration $Configuration

        if ($Exists -ne $true) {
            throw "O grupo TI-Suporte deveria existir."
        }
    }


# ============================================================
# Teste 6 - Grupo inexistente
# ============================================================

Test-Result `
    -TestName "Identificar grupo inexistente" `
    -Test {

        $Exists = Test-ADGroupExists `
            -GroupName "Grupo-Inexistente" `
            -Configuration $Configuration

        if ($Exists -ne $false) {
            throw "O grupo Grupo-Inexistente não deveria existir."
        }
    }


# ============================================================
# Teste 7 - CheckGroup
# ============================================================

Test-Result `
    -TestName "CheckGroup através da função principal" `
    -Test {

        $Result = Invoke-ADGroupManagement `
            -Operation CheckGroup `
            -Configuration $Configuration `
            -GroupName "TI-Suporte"

        if ($Result.Exists -ne $true) {
            throw "O grupo TI-Suporte deveria existir."
        }

        if ($Result.Simulation -ne $true) {
            throw "O resultado deveria indicar modo de simulação."
        }
    }


# ============================================================
# Teste 8 - Criar grupo
# ============================================================

Test-Result `
    -TestName "Criar grupo em modo de simulação" `
    -Test {

        $TestGroupName = "TI-Teste-Criacao"

        $Result = Invoke-ADGroupManagement `
            -Operation CreateGroup `
            -Configuration $Configuration `
            -GroupName $TestGroupName `
            -Description "Grupo criado durante teste automatizado"

        if ($Result.Success -ne $true) {
            throw "A criação simulada deveria retornar Success=True."
        }

        if ($Result.Simulation -ne $true) {
            throw "A operação deveria ocorrer em modo de simulação."
        }

        if ($Result.Operation -ne "CreateGroup") {
            throw "A operação retornada deveria ser CreateGroup."
        }

        if ($Result.GroupName -ne $TestGroupName) {
            throw "O nome do grupo retornado está incorreto."
        }

        $Exists = Test-ADGroupExists `
            -GroupName $TestGroupName `
            -Configuration $Configuration

        if ($Exists -ne $true) {
            throw "O grupo criado não foi encontrado na simulação."
        }
    }


# ============================================================
# Teste 9 - Usuário existente
# ============================================================

Test-Result `
    -TestName "Identificar usuário existente na simulação" `
    -Test {

        if ($Configuration.Simulation.ExistingUsers -notcontains "joao.silva") {
            throw "O usuário joao.silva deveria existir na simulação."
        }
    }


# ============================================================
# Teste 10 - Estado inicial do grupo
# ============================================================

Test-Result `
    -TestName "Validar membro inicial do grupo" `
    -Test {

        $Result = Test-ADGroupMember `
            -GroupName "TI-Suporte" `
            -UserName "maria.santos" `
            -Configuration $Configuration

        if ($Result.Member -ne $true) {
            throw "maria.santos deveria ser membro inicial do grupo TI-Suporte."
        }
    }


# ============================================================
# Teste 11 - Adicionar usuário
# ============================================================

Test-Result `
    -TestName "Adicionar usuário ao grupo" `
    -Test {

        $TestGroupName = "TI-Suporte"
        $TestUserName = "joao.silva"

        # Garantir que o usuário não seja membro antes do teste
        $InitialState = Test-ADGroupMember `
            -GroupName $TestGroupName `
            -UserName $TestUserName `
            -Configuration $Configuration

        if ($InitialState.Member -eq $true) {
            throw "O usuário joao.silva já pertence ao grupo antes do teste."
        }

        $Result = Invoke-ADGroupManagement `
            -Operation AddMember `
            -Configuration $Configuration `
            -GroupName $TestGroupName `
            -UserName $TestUserName

        if ($Result.Success -ne $true) {
            throw "A adição do usuário deveria retornar Success=True."
        }

        $FinalState = Test-ADGroupMember `
            -GroupName $TestGroupName `
            -UserName $TestUserName `
            -Configuration $Configuration

        if ($FinalState.Member -ne $true) {
            throw "O usuário não foi encontrado como membro após a adição."
        }
    }


# ============================================================
# Teste 12 - Listar membros
# ============================================================

Test-Result `
    -TestName "Listar membros do grupo" `
    -Test {

        $Members = @(Get-ADGroupMembers `
            -GroupName "TI-Suporte" `
            -Configuration $Configuration)

        if ($Members.Count -lt 2) {
            throw "O grupo deveria possuir pelo menos dois membros neste momento."
        }

        $MemberNames = $Members.SamAccountName

        if ($MemberNames -notcontains "maria.santos") {
            throw "maria.santos deveria estar no grupo."
        }

        if ($MemberNames -notcontains "joao.silva") {
            throw "joao.silva deveria estar no grupo."
        }
    }


# ============================================================
# Teste 13 - Verificar membro adicionado
# ============================================================

Test-Result `
    -TestName "Verificar usuário adicionado como membro" `
    -Test {

        $Result = Test-ADGroupMember `
            -GroupName "TI-Suporte" `
            -UserName "joao.silva" `
            -Configuration $Configuration

        if ($Result.Member -ne $true) {
            throw "joao.silva deveria ser membro do grupo TI-Suporte."
        }
    }


# ============================================================
# Teste 14 - Remover usuário
# ============================================================

Test-Result `
    -TestName "Remover usuário do grupo" `
    -Test {

        $Result = Invoke-ADGroupManagement `
            -Operation RemoveMember `
            -Configuration $Configuration `
            -GroupName "TI-Suporte" `
            -UserName "joao.silva"

        if ($Result.Success -ne $true) {
            throw "A remoção do usuário deveria retornar Success=True."
        }

        $FinalState = Test-ADGroupMember `
            -GroupName "TI-Suporte" `
            -UserName "joao.silva" `
            -Configuration $Configuration

        if ($FinalState.Member -ne $false) {
            throw "O usuário deveria ter sido removido do grupo."
        }
    }


# ============================================================
# Teste 15 - Usuário inexistente
# ============================================================

Test-Result `
    -TestName "Bloquear usuário inexistente" `
    -Test {

        $OperationFailed = $false

        try {

            Invoke-ADGroupManagement `
                -Operation AddMember `
                -Configuration $Configuration `
                -GroupName "TI-Suporte" `
                -UserName "usuario.inexistente"

        }
        catch {

            $OperationFailed = $true

            if ($_.Exception.Message -notmatch "não existe") {
                throw "A mensagem de erro não corresponde ao cenário esperado."
            }
        }

        if (-not $OperationFailed) {
            throw "A operação deveria ter sido bloqueada."
        }
    }


# ============================================================
# Teste 16 - Membro duplicado
# ============================================================

Test-Result `
    -TestName "Impedir usuário duplicado no grupo" `
    -Test {

        $OperationFailed = $false

        try {

            Invoke-ADGroupManagement `
                -Operation AddMember `
                -Configuration $Configuration `
                -GroupName "TI-Suporte" `
                -UserName "maria.santos"

        }
        catch {

            $OperationFailed = $true

            if ($_.Exception.Message -notmatch "já pertence") {
                throw "A mensagem de erro não corresponde ao cenário esperado."
            }
        }

        if (-not $OperationFailed) {
            throw "A operação deveria ter sido bloqueada."
        }
    }


# ============================================================
# Teste 17 - Grupo inexistente
# ============================================================

Test-Result `
    -TestName "Bloquear operação em grupo inexistente" `
    -Test {

        $OperationFailed = $false

        try {

            Invoke-ADGroupManagement `
                -Operation AddMember `
                -Configuration $Configuration `
                -GroupName "Grupo-Inexistente" `
                -UserName "joao.silva"

        }
        catch {

            $OperationFailed = $true

            if ($_.Exception.Message -notmatch "não existe") {
                throw "A mensagem de erro não corresponde ao cenário esperado."
            }
        }

        if (-not $OperationFailed) {
            throw "A operação deveria ter sido bloqueada."
        }
    }


# ============================================================
# Teste 18 - Remover usuário que não é membro
# ============================================================

Test-Result `
    -TestName "Bloquear remoção de usuário que não é membro" `
    -Test {

        $OperationFailed = $false

        try {

            Invoke-ADGroupManagement `
                -Operation RemoveMember `
                -Configuration $Configuration `
                -GroupName "TI-Suporte" `
                -UserName "carlos.oliveira"

        }
        catch {

            $OperationFailed = $true

            if ($_.Exception.Message -notmatch "não pertence") {
                throw "A mensagem de erro não corresponde ao cenário esperado."
            }
        }

        if (-not $OperationFailed) {
            throw "A operação deveria ter sido bloqueada."
        }
    }


# ============================================================
# Teste 19 - Estado final do grupo
# ============================================================

Test-Result `
    -TestName "Validar estado final do grupo" `
    -Test {

        $Members = @(Get-ADGroupMembers `
            -GroupName "TI-Suporte" `
            -Configuration $Configuration)

        $MemberNames = $Members.SamAccountName

        if ($MemberNames -notcontains "maria.santos") {
            throw "maria.santos deveria continuar no grupo."
        }

        if ($MemberNames -contains "joao.silva") {
            throw "joao.silva não deveria mais estar no grupo."
        }
    }


# ============================================================
# Resumo
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "             RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total de testes : $TotalTests"
Write-Host "Passaram        : $TestsPassed" -ForegroundColor Green
Write-Host "Falharam        : $TestsFailed" -ForegroundColor Red
Write-Host ""

if ($TestsFailed -eq 0) {

    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green
}
else {

    Write-Host "STATUS: EXISTEM TESTES COM FALHA" -ForegroundColor Red

    throw "O conjunto de testes possui $TestsFailed falha(s)."
}