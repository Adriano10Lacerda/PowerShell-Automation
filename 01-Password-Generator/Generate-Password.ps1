
# ===========================================
# Enterprise Password Generator
# Author: Adriano Felix Lacerda
# ===========================================

Write-Host ""

[int]$PasswordLength = Read-Host "Enter password Length"

Write-Host ""

Clear-Host

Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "    Enterprise Password Generator  " -ForegroundColor Green
Write-Host "------------------------------------" -ForegroundColor Cyan

Write-Host ""

Write-Host "Selected Length: $PasswordLength" -ForegroundColor Yellow

$Maiusculas = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$Minusculas = "abcdefghijklmnopqrstuvwxyz"
$Numeros = "0123456789"
$Especiais = "!@#$%&*"
$Obrigatorios = @("A", "a", "1", "!")



$Caracteres = $Maiusculas + $Minusculas + $Numeros + $Especiais


$Senha = ""

for ($i =0; $i -lt $PasswordLength; $i++)
{
    $Posicao = Get-Random -Minimum 0 -Maximum $Caracteres.Length
    $Senha += $Caracteres[$Posicao]
}

Write-Host "Senha: $Senha"

