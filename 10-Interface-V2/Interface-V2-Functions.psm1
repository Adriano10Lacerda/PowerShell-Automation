#Requires -Version 5.1

<#
.SYNOPSIS
    Funções da Interface Central V2 do PowerShell Automation.

.DESCRIPTION
    Interface central da V2.
    Responsável pela navegação e apresentação dos módulos.

.NOTES
    V2 - Interface Central
#>

function Write-V2Header {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Subtitle
    )

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                 POWER SHELL AUTOMATION V2" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  $Title" -ForegroundColor Yellow

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host "  $Subtitle" -ForegroundColor Gray
    }

    Write-Host ""
}

function Pause-V2 {
    [CmdletBinding()]
    param()

    Write-Host ""
    Read-Host "Pressione ENTER para continuar"
}

function Show-V2DevelopmentMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    Write-V2Header `
        -Title $ModuleName `
        -Subtitle "Módulo V2"

    Write-Host "  Este módulo está em desenvolvimento." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  A funcionalidade será disponibilizada nas próximas" -ForegroundColor Gray
    Write-Host "  etapas da V2." -ForegroundColor Gray

    Pause-V2
}

function Get-V2StatusColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    switch ($Status) {
        "Online"        { return "Green" }
        "ReachableOnly" { return "Yellow" }
        "Offline"       { return "Red" }
        "Unavailable"   { return "Red" }
        default         { return "Yellow" }
    }
}

function Get-V2BitLockerColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    switch ($Status) {
        "Protected"    { return "Green" }
        "NotProtected" { return "Red" }
        "NotAvailable" { return "Yellow" }
        default        { return "Yellow" }
    }
}

function Show-V2ComputerSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Summary
    )

    Write-V2Header `
        -Title "COMPUTER MANAGEMENT" `
        -Subtitle "Resumo do computador"

    Write-Host "  COMPUTADOR" -ForegroundColor DarkCyan
    Write-Host "  Hostname    : $($Summary.Hostname)" -ForegroundColor White
    Write-Host ""

    Write-Host "  STATUS" -ForegroundColor DarkCyan

    $statusColor = Get-V2StatusColor -Status ([string]$Summary.Status)

    Write-Host `
        "  $($Summary.Status)" `
        -ForegroundColor $statusColor

    Write-Host ""

    Write-Host "  ACTIVE DIRECTORY" -ForegroundColor DarkCyan

    if ($Summary.ADFound) {
        Write-Host "  Encontrado   : Sim" -ForegroundColor Green
    }
    else {
        Write-Host "  Encontrado   : Não" -ForegroundColor Yellow
    }

    Write-Host ""

    Write-Host "  CONECTIVIDADE" -ForegroundColor DarkCyan

    if ($Summary.Reachable) {
        Write-Host "  Acessível    : Sim" -ForegroundColor Green
    }
    else {
        Write-Host "  Acessível    : Não" -ForegroundColor Red
    }

    Write-Host ""

    Write-Host "  SISTEMA OPERACIONAL" -ForegroundColor DarkCyan
    Write-Host "  $($Summary.OperatingSystem)" -ForegroundColor White
    Write-Host ""

    Write-Host "  HARDWARE" -ForegroundColor DarkCyan
    Write-Host "  Modelo       : $($Summary.Model)"
    Write-Host "  Processador  : $($Summary.Processor)"
    Write-Host "  Memória      : $($Summary.MemoryGB) GB"
    Write-Host ""

    Write-Host "  BITLOCKER" -ForegroundColor DarkCyan

    $bitLockerColor = Get-V2BitLockerColor `
        -Status ([string]$Summary.BitLockerStatus)

    Write-Host `
        "  $($Summary.BitLockerStatus)" `
        -ForegroundColor $bitLockerColor

    Write-Host ""

    Write-Host "  DIAGNÓSTICO" -ForegroundColor DarkCyan

    if ($Summary.ErrorCount -eq 0) {
        Write-Host "  Erros        : 0" -ForegroundColor Green
    }
    else {
        Write-Host `
            "  Erros        : $($Summary.ErrorCount)" `
            -ForegroundColor Yellow
    }

    if ($Summary.SimulationMode) {
        Write-Host ""
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. Atualizar consulta" -ForegroundColor White
    Write-Host "  2. Ver detalhes" -ForegroundColor White
    Write-Host "  0. Voltar" -ForegroundColor Red
    Write-Host ""
}

function Show-V2ComputerDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Summary
    )

    Write-V2Header `
        -Title "COMPUTER MANAGEMENT" `
        -Subtitle "Detalhes da consulta"

    Write-Host "  DETALHES" -ForegroundColor DarkCyan
    Write-Host ""

    $properties = @(
        "Hostname",
        "Status",
        "ADFound",
        "Reachable",
        "OperatingSystem",
        "Model",
        "MemoryGB",
        "Processor",
        "BitLockerStatus",
        "ErrorCount",
        "SimulationMode"
    )

    foreach ($property in $properties) {

        $propertyValue = $Summary.PSObject.Properties[$property]

        if ($null -ne $propertyValue) {

            $value = $propertyValue.Value

            if ($null -eq $value) {
                $value = "<null>"
            }

            Write-Host `
                ("  {0,-18}: {1}" -f $property, $value)
        }
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    Pause-V2
}

function Start-V2ComputerManagement {
    [CmdletBinding()]
    param()

    $managementPath = Join-Path `
        $PSScriptRoot `
        "..\Core\Computer\Management\Computer-Management.psm1"

    if (-not (Test-Path -LiteralPath $managementPath)) {
        throw "Computer Management não encontrado: $managementPath"
    }

    Import-Module `
        $managementPath `
        -Force `
        -ErrorAction Stop

    $hostname = Read-Host "  Hostname"

    if ([string]::IsNullOrWhiteSpace($hostname)) {

        Write-Host ""
        Write-Host "  Hostname não informado." -ForegroundColor Red

        Pause-V2
        return
    }

    $hostname = $hostname.Trim()

    do {

        try {

            $summary = Get-ComputerManagementSummary `
                -Hostname $hostname

            if ($null -eq $summary) {

                Write-V2Header `
                    -Title "COMPUTER MANAGEMENT" `
                    -Subtitle "Resultado da consulta"

                Write-Host `
                    "  Não foi possível obter informações do computador." `
                    -ForegroundColor Red

                Pause-V2
                return
            }

            Show-V2ComputerSummary -Summary $summary

            $option = Read-Host "  Selecione uma opção"

            switch ($option) {

                "1" {
                    # Atualiza a consulta usando o mesmo hostname.
                }

                "2" {
                    Show-V2ComputerDetails -Summary $summary
                }

                "0" {
                    return
                }

                default {
                    Write-Host ""
                    Write-Host "  Opção inválida." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }

        }
        catch {

            Write-V2Header `
                -Title "COMPUTER MANAGEMENT" `
                -Subtitle "Erro"

            Write-Host `
                "  Erro ao consultar computador:" `
                -ForegroundColor Red

            Write-Host ""
            Write-Host `
                "  $($_.Exception.Message)" `
                -ForegroundColor Red

            Pause-V2

            return
        }

    } while ($true)
}

function Show-V2MainMenu {
    [CmdletBinding()]
    param()

    Write-V2Header `
        -Title "IT INFRASTRUCTURE TOOL" `
        -Subtitle "Automação e administração de infraestrutura Microsoft"

    Write-Host "  1.  Users" -ForegroundColor White
    Write-Host "  2.  Accounts" -ForegroundColor White
    Write-Host "  3.  Groups" -ForegroundColor White
    Write-Host "  4.  Computers" -ForegroundColor Green
    Write-Host "  5.  Policies" -ForegroundColor White
    Write-Host "  6.  Reports" -ForegroundColor White
    Write-Host "  7.  Settings" -ForegroundColor White
    Write-Host ""
    Write-Host "  0.  Exit" -ForegroundColor Red
    Write-Host ""
}

function Start-V2Interface {
    [CmdletBinding()]
    param()

    do {

        Show-V2MainMenu

        $option = Read-Host "  Selecione uma opção"

        switch ($option) {

            "1" {
                Show-V2DevelopmentMessage `
                    -ModuleName "USERS"
            }

            "2" {
                Show-V2DevelopmentMessage `
                    -ModuleName "ACCOUNTS"
            }

            "3" {
                Show-V2DevelopmentMessage `
                    -ModuleName "GROUPS"
            }

            "4" {
                Write-V2Header `
                    -Title "COMPUTER MANAGEMENT" `
                    -Subtitle "Consulta de inventário e status do computador"

                Write-Host "  Digite o hostname do computador." -ForegroundColor Gray
                Write-Host ""

                Start-V2ComputerManagement
            }

            "5" {
                Show-V2DevelopmentMessage `
                    -ModuleName "POLICIES"
            }

            "6" {
                Show-V2DevelopmentMessage `
                    -ModuleName "REPORTS"
            }

            "7" {
                Show-V2DevelopmentMessage `
                    -ModuleName "SETTINGS"
            }

            "0" {
                Clear-Host

                Write-Host ""
                Write-Host `
                    "  POWER SHELL AUTOMATION V2 encerrado." `
                    -ForegroundColor Cyan
                Write-Host ""
            }

            default {
                Write-Host ""
                Write-Host `
                    "  Opção inválida." `
                    -ForegroundColor Red

                Start-Sleep -Seconds 1
            }
        }

    } while ($option -ne "0")
}

Export-ModuleMember -Function @(
    "Write-V2Header",
    "Pause-V2",
    "Show-V2DevelopmentMessage",
    "Get-V2StatusColor",
    "Get-V2BitLockerColor",
    "Show-V2ComputerSummary",
    "Show-V2ComputerDetails",
    "Start-V2ComputerManagement",
    "Show-V2MainMenu",
    "Start-V2Interface"
)