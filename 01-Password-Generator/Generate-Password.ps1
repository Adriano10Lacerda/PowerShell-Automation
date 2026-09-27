# ===========================================
# Enterprise Password Generator
# Author: Adriano Felix Lacerda
# ===========================================

Write-Host ""

# Localiza o módulo de configuração
$CaminhoModulo = Join-Path $PSScriptRoot "..\02-Configuration\Configuration.psm1"

# Verifica se o módulo existe
if (-not (Test-Path $CaminhoModulo))
{
    Write-Host ""
    Write-Host "Erro: Configuration.psm1 nao encontrado." -ForegroundColor Red
    exit
}

# Carrega o módulo de configuração
Import-Module $CaminhoModulo -Force

# Localiza o arquivo de configuração
$CaminhoConfig = Join-Path $PSScriptRoot "..\02-Configuration\config.json"

# Carrega e valida a configuração
try
{
    $Config = Get-Configuration -ConfigurationPath $CaminhoConfig
}
catch
{
    Write-Host ""
    Write-Host "Erro: Configuracao invalida." -ForegroundColor Red
    Write-Host ""

    $Erros = $_.Exception.Message -split " \| "

    foreach ($Erro in $Erros)
    {
        Write-Host "- $Erro" -ForegroundColor Red
    }

    Write-Host ""
    exit
}



# Carrega o módulo de funções do gerador
$CaminhoFuncoes = Join-Path $PSScriptRoot "Password-Functions.psm1"

if (-not (Test-Path $CaminhoFuncoes)) {
    throw "Erro: Password-Functions.psm1 nao encontrado."
}

Import-Module $CaminhoFuncoes -Force


# Obtém valores da configuração
$Prefixo = $Config.Prefixo
$QuantidadeCaracteres = $Config.QuantidadeCaracteres
$FormatoData = $Config.FormatoData
$Especiais = $Config.CaracteresEspeciais

# Obtém a data conforme configuração
$Data = Get-Date -Format $FormatoData

# Gera a senha usando o módulo de funções
$Senha = New-SecurePassword `
    -Prefixo $Prefixo `
    -Data $Data `
    -QuantidadeCaracteres $QuantidadeCaracteres `
    -CaracteresEspeciais $Especiais

# Exibe o resultado
Write-Host ""

Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "    Enterprise Password Generator  " -ForegroundColor Green
Write-Host "------------------------------------" -ForegroundColor Cyan

Write-Host ""

Write-Host "Prefixo: $Prefixo" -ForegroundColor Yellow
Write-Host "Data: $Data" -ForegroundColor Yellow
Write-Host "Caracteres aleatorios: $QuantidadeCaracteres" -ForegroundColor Yellow
Write-Host "Senha gerada: $Senha" -ForegroundColor Green

Write-Host ""