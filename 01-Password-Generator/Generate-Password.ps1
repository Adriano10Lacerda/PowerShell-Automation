# ===========================================
# Enterprise Password Generator
# Author: Adriano Felix Lacerda
# ===========================================

Write-Host ""

# Solicita o prefixo
$Prefixo = Read-Host "Digite o prefixo"

# Obtém a data atual no formato DDMM
$Data = Get-Date -Format "ddMM"

# Caracteres permitidos
$Maiusculas = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$Minusculas = "abcdefghijklmnopqrstuvwxyz"
$Numeros = "0123456789"
$Especiais = "!@#$%&*"

$Caracteres = $Maiusculas + $Minusculas + $Numeros + $Especiais

# Gera um caractere especial obrigatório
$PosicaoEspecial = Get-Random -Minimum 0 -Maximum $Especiais.Length
$EspecialObrigatorio = $Especiais[$PosicaoEspecial]

# Começa a parte aleatória com o caractere especial
$ParteAleatoria = $EspecialObrigatorio

# Gera os outros 3 caracteres aleatórios
for ($i = 0; $i -lt 3; $i++)
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
Write-Host "Senha gerada: $Senha" -ForegroundColor Green

Write-Host ""=