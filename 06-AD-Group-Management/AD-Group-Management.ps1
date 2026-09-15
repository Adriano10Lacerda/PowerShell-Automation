$ErrorActionPreference = "Stop"

# Caminhos
$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "Group-Functions.psm1"
$ConfigPath = Join-Path $ScriptPath "Group-Configuration.json"

# Validar arquivos
if (-not (Test-Path $ModulePath)) {
    throw "O módulo 'Group-Functions.psm1' não foi encontrado."
}

if (-not (Test-Path $ConfigPath)) {
    throw "O arquivo 'Group-Configuration.json' não foi encontrado."
}

# Importar módulo
Import-Module $ModulePath -Force

# Carregar configuração
$Configuration = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Validar configuração
Test-ADGroupConfiguration -Configuration $Configuration | Out-Null

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       AD Group Management" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Modo de simulação: " -NoNewline
Write-Host $Configuration.SimulationMode -ForegroundColor Yellow

Write-Host ""

# Menu
Write-Host "1 - Verificar grupo"
Write-Host "2 - Criar grupo"
Write-Host "3 - Adicionar usuário ao grupo"
Write-Host "4 - Remover usuário do grupo"
Write-Host "5 - Listar membros do grupo"
Write-Host "0 - Sair"
Write-Host ""

$Option = Read-Host "Escolha uma opção"

switch ($Option) {

    "1" {

        $GroupName = Read-Host "Digite o nome do grupo"

        $Result = Invoke-ADGroupManagement `
            -Operation CheckGroup `
            -Configuration $Configuration `
            -GroupName $GroupName

        Write-Host ""
        Write-Host "Resultado:" -ForegroundColor Cyan
        $Result | Format-List
    }

    "2" {

        $GroupName = Read-Host "Digite o nome do grupo"
        $Description = Read-Host "Digite a descrição do grupo"

        $Result = Invoke-ADGroupManagement `
            -Operation CreateGroup `
            -Configuration $Configuration `
            -GroupName $GroupName `
            -Description $Description

        Write-Host ""
        Write-Host "Resultado:" -ForegroundColor Cyan
        $Result | Format-List
    }

    "3" {

        $GroupName = Read-Host "Digite o nome do grupo"
        $UserName = Read-Host "Digite o SamAccountName do usuário"

        $Result = Invoke-ADGroupManagement `
            -Operation AddMember `
            -Configuration $Configuration `
            -GroupName $GroupName `
            -UserName $UserName

        Write-Host ""
        Write-Host "Resultado:" -ForegroundColor Cyan
        $Result | Format-List
    }

    "4" {

        $GroupName = Read-Host "Digite o nome do grupo"
        $UserName = Read-Host "Digite o SamAccountName do usuário"

        $Result = Invoke-ADGroupManagement `
            -Operation RemoveMember `
            -Configuration $Configuration `
            -GroupName $GroupName `
            -UserName $UserName

        Write-Host ""
        Write-Host "Resultado:" -ForegroundColor Cyan
        $Result | Format-List
    }

    "5" {

        $GroupName = Read-Host "Digite o nome do grupo"

        $Result = Invoke-ADGroupManagement `
            -Operation ListMembers `
            -Configuration $Configuration `
            -GroupName $GroupName

        Write-Host ""
        Write-Host "Membros do grupo '$GroupName':" -ForegroundColor Cyan
        $Result | Format-Table -AutoSize
    }

    "0" {

        Write-Host ""
        Write-Host "Operação encerrada." -ForegroundColor Green
    }

    default {

        Write-Host ""
        Write-Host "Opção inválida." -ForegroundColor Red
    }
}