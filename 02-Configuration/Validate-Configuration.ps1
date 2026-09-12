# ===========================================
# Enterprise Configuration Validator
# Author: Adriano Felix Lacerda
# ===========================================

Write-Host ""

# Caminho do módulo de configuração
$CaminhoModulo = Join-Path $PSScriptRoot "Configuration.psm1"

# Verifica se o módulo existe
if (-not (Test-Path $CaminhoModulo))
{
    Write-Host "Erro: Configuration.psm1 nao encontrado." -ForegroundColor Red
    exit
}

# Carrega o módulo
Import-Module $CaminhoModulo -Force

# Caminho do arquivo de configuração
$CaminhoConfig = Join-Path $PSScriptRoot "config.json"

# Tenta carregar e validar a configuração
try
{
    $Config = Get-Configuration -ConfigurationPath $CaminhoConfig
}
catch
{
    Write-Host "Configuracao invalida." -ForegroundColor Red
    Write-Host ""

    $Erros = $_.Exception.Message -split " \| "

    foreach ($Erro in $Erros)
    {
        Write-Host "- $Erro" -ForegroundColor Red
    }

    Write-Host ""
    exit
}

# Resultado da validação
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "   Enterprise Configuration Validator  " -ForegroundColor Green
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuracao valida." -ForegroundColor Green
Write-Host ""
Write-Host "Prefixo: $($Config.Prefixo)" -ForegroundColor Yellow
Write-Host "Quantidade: $($Config.QuantidadeCaracteres)" -ForegroundColor Yellow
Write-Host "Formato da data: $($Config.FormatoData)" -ForegroundColor Yellow
Write-Host "Caracteres especiais: $($Config.CaracteresEspeciais)" -ForegroundColor Yellow

Write-Host ""