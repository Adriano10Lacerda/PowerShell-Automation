# ===========================================
# Enterprise Password Generator
# Author: Adriano Felix Lacerda
# ===========================================

Write-Host ""

# Solicita o prefixo
$Prefixo = Read-Host "Digite o prefixo"

# Valida o prefixo
if ([string]::IsNullOrWhiteSpace($Prefixo))
{
    Write-Host ""
    Write-Host "Erro: O prefixo nao pode ficar vazio." -ForegroundColor Red
    exit
}

# Solicita a quantidade de caracteres aleatórios
[int]$QuantidadeCaracteres = Read-Host "Digite a quantidade de caracteres aleatorios"

# Valida a quantidade
if ($QuantidadeCaracteres -lt 4)
{
    Write-Host ""
    Write-Host "Erro: A quantidade deve ser no minimo 4 caracteres." -ForegroundColor Red
    exit
}

# Obtém a data atual no formato DDMM
$Data = Get-Date -Format "ddMM"

# Grupos de caracteres
$Maiusculas = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$Minusculas = "abcdefghijklmnopqrstuvwxyz"
$Numeros = "0123456789"
$Especiais = "!@#$%&*"

# Seleciona um caractere de cada grupo
$Obrigatorios = @(
    $Maiusculas[(Get-Random -Minimum 0 -Maximum $Maiusculas.Length)]
    $Minusculas[(Get-Random -Minimum 0 -Maximum $Minusculas.Length)]
    $Numeros[(Get-Random -Minimum 0 -Maximum $Numeros.Length)]
    $Especiais[(Get-Random -Minimum 0 -Maximum $Especiais.Length)]
)

# Embaralha os caracteres obrigatórios
$Obrigatorios = $Obrigatorios | Sort-Object { Get-Random }

# Junta todos os grupos
$Caracteres = $Maiusculas + $Minusculas + $Numeros + $Especiais

# Começa a parte aleatória
$ParteAleatoria = $Obrigatorios -join ""

# Gera os caracteres restantes
for ($i = 4; $i -lt $QuantidadeCaracteres; $i++)
{
    $Posicao = Get-Random -Minimum 0 -Maximum $Caracteres.Length
    $ParteAleatoria += $Caracteres[$Posicao]
}

# Monta a senha final
$Senha = $Prefixo + $Data + $ParteAleatoria

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