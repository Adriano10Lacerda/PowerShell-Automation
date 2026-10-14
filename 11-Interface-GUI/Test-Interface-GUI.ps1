#Requires -Version 5.1

<#
.SYNOPSIS
    Testes estruturais da Interface GUI.

.DESCRIPTION
    Valida a existência, a sintaxe, os componentes principais,
    as proteções de simulação e os eventos dos botões.
    Não abre a interface nem executa operações reais no AD ou GPO.
#>

$ErrorActionPreference = "Stop"

$script:TestsPassed = 0
$script:TestsFailed = 0

$guiPath = Join-Path $PSScriptRoot "Interface-GUI.ps1"

function Invoke-GuiTest {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Test
    )

    try {
        & $Test
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:TestsPassed++
    }
    catch {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow
        $script:TestsFailed++
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       TESTES ESTRUTURAIS - GUI" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Invoke-GuiTest "Arquivo Interface-GUI.ps1 existe" {
    if (-not (Test-Path -LiteralPath $guiPath -PathType Leaf)) {
        throw "Interface-GUI.ps1 não encontrado."
    }
}

if (Test-Path -LiteralPath $guiPath -PathType Leaf) {
    $source = Get-Content -LiteralPath $guiPath -Raw

    Invoke-GuiTest "Sintaxe PowerShell válida" {
        $tokens = $null
        $parseErrors = $null

        [System.Management.Automation.Language.Parser]::ParseFile(
            $guiPath,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null

        if ($parseErrors.Count -gt 0) {
            throw (($parseErrors | ForEach-Object {
                $_.Message
            }) -join "; ")
        }
    }

    Invoke-GuiTest "Janela WPF definida em XAML" {
        if ($source -notmatch '(?s)\[xml\]\s*\$xamlXml\s*=\s*@"') {
            throw "Bloco XAML não encontrado."
        }
        if ($source -notmatch 'x:Name="btnHome"') {
            throw "Botão btnHome não encontrado no XAML."
        }
    }

    Invoke-GuiTest "Modo de simulação validado para AD" {
        if ($source -notmatch '(?s)GuiADConfig\.SimulationMode\s*-ne\s*\$true') {
            throw "Proteção SimulationMode do AD não encontrada."
        }
    }

    Invoke-GuiTest "Modo de simulação validado para GPO" {
        if ($source -notmatch '(?s)GuiGpoConfig\.SimulationMode\s*-ne\s*\$true') {
            throw "Proteção SimulationMode de GPO não encontrada."
        }
    }

    Invoke-GuiTest "Função de ações AD presente" {
        if ($source -notmatch 'function\s+Invoke-GuiADAction') {
            throw "Invoke-GuiADAction não encontrada."
        }
    }

    Invoke-GuiTest "Função de ações GPO presente" {
        if ($source -notmatch 'function\s+Invoke-GuiGpoAction') {
            throw "Invoke-GuiGpoAction não encontrada."
        }
    }

    Invoke-GuiTest "Erros AD tratados" {
        if ($source -notmatch '(?s)function\s+Invoke-GuiADAction.*?catch\s*\{') {
            throw "Bloco catch da função AD não encontrado."
        }
    }

    Invoke-GuiTest "Erros GPO tratados" {
        if ($source -notmatch '(?s)function\s+Invoke-GuiGpoAction.*?catch\s*\{') {
            throw "Bloco catch da função GPO não encontrado."
        }
    }

    Invoke-GuiTest "Consulta de usuário valida entrada vazia" {
        if ($source -notmatch 'IsNullOrWhiteSpace\(\$sam\)') {
            throw "Validação de sAMAccountName vazio não encontrada."
        }
    }

    Invoke-GuiTest "Botões AD conectados às ações" {
        foreach ($button in @(
            "btnADValidate",
            "btnADConnectivity",
            "btnADUserExists"
        )) {
            if ($source -notmatch [regex]::Escape($button)) {
                throw "Referência ao botão $button não encontrada."
            }
        }
    }

    Invoke-GuiTest "Botões GPO conectados às ações" {
        foreach ($button in @(
            "btnGPOList",
            "btnGPOCheck",
            "btnGPOLinks"
        )) {
            if ($source -notmatch [regex]::Escape($button)) {
                throw "Referência ao botão $button não encontrada."
            }
        }
    }

    Invoke-GuiTest "Modo de simulação indicado visualmente" {
        if ($source -notmatch 'SIMULATION MODE') {
            throw "Indicador visual de simulação não encontrado."
        }
    }

    Invoke-GuiTest "Entra ID identificado como integração informativa" {
        if ($source -notmatch '(?s)btnEntra.*?showModuleMessage') {
            throw "Ação informativa do botão Entra ID não encontrada."
        }
    }

    Invoke-GuiTest "Botão de testes identificado como informativo" {
        if ($source -notmatch '(?s)btnTests.*?showModuleMessage') {
            throw "Ação informativa do botão de testes não encontrada."
        }
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "             RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Total de testes : $($script:TestsPassed + $script:TestsFailed)"
Write-Host "Passaram        : $script:TestsPassed" -ForegroundColor Green
Write-Host "Falharam        : $script:TestsFailed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })

if ($script:TestsFailed -gt 0) {
    Write-Host "STATUS: EXISTEM TESTES COM FALHA" -ForegroundColor Red
    exit 1
}

Write-Host "STATUS: TODOS OS TESTES ESTRUTURAIS PASSARAM" -ForegroundColor Green
