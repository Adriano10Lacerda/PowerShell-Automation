$ErrorActionPreference = "Stop"

# ============================================================
# CAMINHOS
# ============================================================

$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "GPO-Functions.psm1"
$ConfigPath = Join-Path $ScriptPath "GPO-Configuration.json"


# ============================================================
# VALIDAR ARQUIVOS
# ============================================================

if (-not (Test-Path $ModulePath)) {
    throw "O módulo 'GPO-Functions.psm1' não foi encontrado."
}

if (-not (Test-Path $ConfigPath)) {
    throw "O arquivo 'GPO-Configuration.json' não foi encontrado."
}


# ============================================================
# IMPORTAR MÓDULO
# ============================================================

Import-Module $ModulePath -Force


# ============================================================
# CARREGAR CONFIGURAÇÃO
# ============================================================

$Configuration = Get-Content $ConfigPath -Raw | ConvertFrom-Json


# ============================================================
# VALIDAR CONFIGURAÇÃO
# ============================================================

Test-GPOConfiguration `
    -Configuration $Configuration |
    Out-Null


# ============================================================
# FUNÇÃO AUXILIAR - VERIFICAR OPERAÇÃO
# ============================================================

function Test-OperationEnabled {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    return ($Configuration.Operations.$Operation -eq $true)
}


# ============================================================
# CABEÇALHO
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "             GPO Management" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Modo de simulação: " -NoNewline
Write-Host $Configuration.SimulationMode -ForegroundColor Yellow

Write-Host ""


# ============================================================
# MENU
# ============================================================

Write-Host "1 - Verificar GPO" -ForegroundColor White
Write-Host "2 - Listar GPOs" -ForegroundColor White
Write-Host "3 - Criar GPO" -ForegroundColor White
Write-Host "4 - Verificar vínculos da GPO" -ForegroundColor White
Write-Host "5 - Listar vínculos da GPO" -ForegroundColor White
Write-Host "0 - Sair" -ForegroundColor White
Write-Host ""

$Option = Read-Host "Escolha uma opção"


# ============================================================
# PROCESSAMENTO
# ============================================================

switch ($Option) {

    # --------------------------------------------------------
    # 1 - VERIFICAR GPO
    # --------------------------------------------------------

    "1" {

        if (-not (Test-OperationEnabled "CheckGPO")) {
            Write-Host ""
            Write-Host "A operação 'CheckGPO' está desabilitada na configuração." -ForegroundColor Red
            break
        }

        $GPOName = Read-Host "Digite o nome da GPO"

        $Result = Invoke-GPOManagement `
            -Operation CheckGPO `
            -Configuration $Configuration `
            -GPOName $GPOName

        Write-Host ""
        Write-Host "Resultado:" -ForegroundColor Cyan
        $Result | Format-List
    }


    # --------------------------------------------------------
    # 2 - LISTAR GPOS
    # --------------------------------------------------------

    "2" {

        if (-not (Test-OperationEnabled "ListGPOs")) {
            Write-Host ""
            Write-Host "A operação 'ListGPOs' está desabilitada na configuração." -ForegroundColor Red
            break
        }

        $Result = Invoke-GPOManagement `
            -Operation ListGPOs `
            -Configuration $Configuration

        Write-Host ""
        Write-Host "GPOs encontradas:" -ForegroundColor Cyan
        Write-Host ""

        $Result |
            Format-Table Name, DisplayName, Description, Links, Simulation -AutoSize
    }


    # --------------------------------------------------------
    # 3 - CRIAR GPO
    # --------------------------------------------------------

    "3" {

        if (-not (Test-OperationEnabled "CreateGPO")) {
            Write-Host ""
            Write-Host "A operação 'CreateGPO' está desabilitada na configuração." -ForegroundColor Red
            break
        }

        $GPOName = Read-Host "Digite o nome da nova GPO"
        $Description = Read-Host "Digite a descrição da GPO"

        $Result = Invoke-GPOManagement `
            -Operation CreateGPO `
            -Configuration $Configuration `
            -GPOName $GPOName `
            -Description $Description

        Write-Host ""
        Write-Host "Resultado:" -ForegroundColor Cyan
        $Result | Format-List
    }


    # --------------------------------------------------------
    # 4 - VERIFICAR VÍNCULOS
    # --------------------------------------------------------

    "4" {

        if (-not (Test-OperationEnabled "CheckLinks")) {
            Write-Host ""
            Write-Host "A operação 'CheckLinks' está desabilitada na configuração." -ForegroundColor Red
            break
        }

        $GPOName = Read-Host "Digite o nome da GPO"

        $Result = Invoke-GPOManagement `
            -Operation CheckLinks `
            -Configuration $Configuration `
            -GPOName $GPOName

        Write-Host ""
        Write-Host "Vínculos da GPO '$GPOName':" -ForegroundColor Cyan
        Write-Host ""

        if ($null -eq $Result -or @($Result).Count -eq 0) {

            Write-Host "Nenhum vínculo encontrado." -ForegroundColor Yellow
        }
        else {

            $Result |
                Format-Table GPOName, Target, Simulation -AutoSize
        }
    }


    # --------------------------------------------------------
    # 5 - LISTAR VÍNCULOS
    # --------------------------------------------------------

    "5" {

        if (-not (Test-OperationEnabled "ListLinks")) {
            Write-Host ""
            Write-Host "A operação 'ListLinks' está desabilitada na configuração." -ForegroundColor Red
            break
        }

        $GPOName = Read-Host "Digite o nome da GPO"

        $Result = Invoke-GPOManagement `
            -Operation ListLinks `
            -Configuration $Configuration `
            -GPOName $GPOName

        Write-Host ""
        Write-Host "Vínculos da GPO '$GPOName':" -ForegroundColor Cyan
        Write-Host ""

        if ($null -eq $Result -or @($Result).Count -eq 0) {

            Write-Host "Nenhum vínculo encontrado." -ForegroundColor Yellow
        }
        else {

            $Result |
                Format-Table GPOName, Target, Simulation -AutoSize
        }
    }


    # --------------------------------------------------------
    # 0 - SAIR
    # --------------------------------------------------------

    "0" {

        Write-Host ""
        Write-Host "Operação encerrada." -ForegroundColor Green
    }


    # --------------------------------------------------------
    # OPÇÃO INVÁLIDA
    # --------------------------------------------------------

    default {

        Write-Host ""
        Write-Host "Opção inválida." -ForegroundColor Red
    }
}