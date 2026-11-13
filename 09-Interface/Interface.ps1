param([switch]$Demo)

if ($Demo) {
    # Script-local preference: an input/output error must stop before normal startup.
    $ErrorActionPreference = 'Stop'
    $demoPages = @{
        '1' = 'Password Generator | Senha: [MASCARADA; NAO GERADA]'
        '2' = 'AD User Provisioning | Usuario ficticio: usuario.demo'
        '3' = 'Entra ID User Provisioning | UPN ficticio: usuario.demo@example.invalid'
        '4' = 'Computer Inventory | Host ficticio: DEMO-PC-001 | RAM: 8 GB | BitLocker: FICTICIO'
        '5' = 'AD Group Management | Grupo ficticio: DEMO-GROUP | Membro: usuario.demo'
        '6' = 'GPO Management | Politica ficticia: DEMO-POLICY | Vinculos: 0'
        '7' = 'Reporting | Resumo ficticio: 3 registros | Exportacao desabilitada'
        '8' = 'Configuration | Exemplo embutido: SimulationMode=true | Nenhum JSON carregado'
    }

    do {
        Write-Host ''
        Write-Host 'POWERSHELL AUTOMATION TOOLKIT | DEMO / SOMENTE VISUALIZACAO'
        Write-Host 'Dados ficticios. Operacoes reais e exportacoes desabilitadas.'
        Write-Host '1 - Password Generator'
        Write-Host '2 - AD User Provisioning'
        Write-Host '3 - Entra ID User Provisioning'
        Write-Host '4 - Computer Inventory'
        Write-Host '5 - AD Group Management'
        Write-Host '6 - GPO Management'
        Write-Host '7 - Reporting'
        Write-Host '8 - Configuration'
        Write-Host '0 - Exit'
        $demoOption = Read-Host 'Selecione uma opcao Demo'

        if ($demoOption -eq '0') {
            Write-Host 'Demo encerrado. Nenhuma operacao real foi executada.'
        }
        elseif ($null -ne $demoOption -and $demoPages.ContainsKey($demoOption)) {
            Write-Host $demoPages[$demoOption]
            Write-Host 'SOMENTE VISUALIZACAO: nenhuma acao ou exportacao disponivel.'
            $null = Read-Host 'ENTER para voltar ao menu Demo'
        }
        else {
            Write-Host 'Opcao invalida. Escolha 1-8 ou 0.'
        }
    } while ($demoOption -ne '0')

    return
}

$InterfaceFunctionsPath = Join-Path $PSScriptRoot "Interface-Functions.psm1"

if (-not (Test-Path $InterfaceFunctionsPath)) {
    Write-Host ""
    Write-Host "Erro: Interface-Functions.psm1 não encontrado." -ForegroundColor Red
    exit 1
}

Import-Module $InterfaceFunctionsPath -Force


function Show-MainMenu {

    Clear-Host

    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "          POWERSHELL AUTOMATION TOOLKIT           " -ForegroundColor Cyan
    Write-Host "             Enterprise IT Automation             " -ForegroundColor DarkCyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  1 - Password Generator"
    Write-Host "  2 - AD User Provisioning"
    Write-Host "  3 - Entra ID User Provisioning"
    Write-Host "  4 - Computer Inventory"
    Write-Host "  5 - AD Group Management"
    Write-Host "  6 - GPO Management"
    Write-Host "  7 - Reporting"
    Write-Host "  8 - Configuration"
    Write-Host ""
    Write-Host "  0 - Exit"
    Write-Host ""

    return Read-Host "Select an option"
}


do {

    $Option = Show-MainMenu

    try {

        switch ($Option) {

            "1" {
                Write-Host ""
                Write-Host "Starting Password Generator..." -ForegroundColor Green
                Write-Host ""

                Start-PasswordGenerator

                Pause
            }

            "2" {
                Write-Host ""
                Write-Host "Starting AD User Provisioning..." -ForegroundColor Green
                Write-Host ""

                Start-ADUserProvisioning

                Pause
            }

            "3" {
                Write-Host ""
                Write-Host "Starting Entra ID User Provisioning..." -ForegroundColor Green
                Write-Host ""

                Start-EntraUserProvisioning

                Pause
            }

            "4" {
                Write-Host ""
                Write-Host "Starting Computer Inventory..." -ForegroundColor Green
                Write-Host ""

                Start-ComputerInventory

                Pause
            }

            "5" {
                Write-Host ""
                Write-Host "Starting AD Group Management..." -ForegroundColor Green
                Write-Host ""

                Start-ADGroupManagement

                Pause
            }

            "6" {
                Write-Host ""
                Write-Host "Starting GPO Management..." -ForegroundColor Green
                Write-Host ""

                Start-GPOManagement

                Pause
            }

            "7" {
                Write-Host ""
                Write-Host "Starting Reporting..." -ForegroundColor Green
                Write-Host ""

                Start-Reporting

                Pause
            }

            "8" {
                Write-Host ""
                Write-Host "Starting Configuration Validator..." -ForegroundColor Green
                Write-Host ""

                Start-Configuration

                Pause
            }

            "0" {
                Write-Host ""
                Write-Host "Exiting PowerShell Automation Toolkit..." -ForegroundColor Yellow
            }

            default {
                Write-Host ""
                Write-Host "Invalid option. Please try again." -ForegroundColor Red

                Pause
            }
        }

    }
    catch {

        Write-Host ""
        Write-Host "An error occurred while executing the selected module." -ForegroundColor Red
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Yellow

        Pause
    }

} while ($Option -ne "0")