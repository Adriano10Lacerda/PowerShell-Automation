$ErrorActionPreference = "Stop"

# ============================================================
# CAMINHOS
# ============================================================

$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "Reporting-Functions.psm1"
$ConfigPath = Join-Path $ScriptPath "Reporting-Configuration.json"


# ============================================================
# VALIDAR ARQUIVOS
# ============================================================

if (-not (Test-Path $ModulePath)) {

    throw "O módulo 'Reporting-Functions.psm1' não foi encontrado."
}

if (-not (Test-Path $ConfigPath)) {

    throw "O arquivo 'Reporting-Configuration.json' não foi encontrado."
}


# ============================================================
# IMPORTAR MÓDULO
# ============================================================

Import-Module $ModulePath -Force


# ============================================================
# CARREGAR CONFIGURAÇÃO
# ============================================================

$Configuration = Get-Content `
    $ConfigPath `
    -Raw |
    ConvertFrom-Json


# ============================================================
# VALIDAR CONFIGURAÇÃO
# ============================================================

Test-ReportingConfiguration `
    -Configuration $Configuration |
    Out-Null


# ============================================================
# FUNÇÃO AUXILIAR
# ============================================================

function Show-Header {

    Clear-Host

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "              Reporting" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Modo de simulação: " -NoNewline
    Write-Host $Configuration.SimulationMode -ForegroundColor Yellow

    Write-Host ""
}


function Show-Sources {

    Write-Host ""
    Write-Host "Fontes configuradas:" -ForegroundColor Cyan
    Write-Host ""

    $Sources = $Configuration.Sources.PSObject.Properties

    foreach ($SourceProperty in $Sources) {

        $Source = $SourceProperty.Value

        $Status = if ($Source.Enabled -eq $true) {
            "Habilitada"
        }
        else {
            "Desabilitada"
        }

        Write-Host "$($SourceProperty.Name) : " -NoNewline
        Write-Host $Status -ForegroundColor $(if ($Source.Enabled) { "Green" } else { "DarkGray" })

        Write-Host "  Diretório : $($Source.Directory)"
        Write-Host "  Padrão    : $($Source.FilePattern)"
        Write-Host ""
    }
}


function Show-Summary {

    Write-Host ""
    Write-Host "Gerando resumo..." -ForegroundColor Yellow
    Write-Host ""

    $Dataset = New-ReportingDataset `
        -Configuration $Configuration

    Write-Host "Resumo do Reporting:" -ForegroundColor Cyan
    Write-Host ""

    $Dataset.Summary |
        Format-List
}


function Invoke-Report {

    Write-Host ""
    Write-Host "Executando Reporting..." -ForegroundColor Yellow
    Write-Host ""

    $Result = Invoke-Reporting `
        -Configuration $Configuration

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "       REPORTING EXECUTADO COM SUCESSO" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host ""

    Write-Host "Arquivos processados : " -NoNewline
    Write-Host $Result.Summary.TotalFiles -ForegroundColor Cyan

    Write-Host "Processados com sucesso : " -NoNewline
    Write-Host $Result.Summary.SuccessfulFiles -ForegroundColor Green

    Write-Host "Com falha : " -NoNewline
    Write-Host $Result.Summary.FailedFiles -ForegroundColor Red

    Write-Host ""

    Write-Host "Arquivos gerados:" -ForegroundColor Cyan
    Write-Host ""

    foreach ($File in $Result.Files) {

        Write-Host $File
    }

    Write-Host ""

    Write-Host "Diretório de saída:" -ForegroundColor Cyan
    Write-Host $Result.OutputDirectory

    Write-Host ""
}


# ============================================================
# MENU
# ============================================================

Show-Header

Write-Host "1 - Executar Reporting" -ForegroundColor White
Write-Host "2 - Ver resumo" -ForegroundColor White
Write-Host "3 - Listar fontes configuradas" -ForegroundColor White
Write-Host "4 - Listar arquivos de origem" -ForegroundColor White
Write-Host "0 - Sair" -ForegroundColor White
Write-Host ""

$Option = Read-Host "Escolha uma opção"


# ============================================================
# PROCESSAMENTO
# ============================================================

switch ($Option) {

    # --------------------------------------------------------
    # 1 - EXECUTAR REPORTING
    # --------------------------------------------------------

    "1" {

        Invoke-Report
    }


    # --------------------------------------------------------
    # 2 - VER RESUMO
    # --------------------------------------------------------

    "2" {

        Show-Summary
    }


    # --------------------------------------------------------
    # 3 - LISTAR FONTES
    # --------------------------------------------------------

    "3" {

        Show-Sources
    }


    # --------------------------------------------------------
    # 4 - LISTAR ARQUIVOS DE ORIGEM
    # --------------------------------------------------------

    "4" {

        Write-Host ""
        Write-Host "Arquivos de origem:" -ForegroundColor Cyan
        Write-Host ""

        foreach ($SourceProperty in $Configuration.Sources.PSObject.Properties) {

            $SourceName = $SourceProperty.Name
            $Source = $SourceProperty.Value

            if ($Source.Enabled -ne $true) {

                continue
            }

            Write-Host "[$SourceName]" -ForegroundColor Yellow

            $Files = @(Get-ReportingSourceFiles `
                -Source $Source)

            if ($Files.Count -eq 0) {

                Write-Host "Nenhum arquivo encontrado." -ForegroundColor DarkGray
                Write-Host ""
                continue
            }

            $Files |
                Select-Object Name, Extension, Length |
                Format-Table -AutoSize

            Write-Host ""
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