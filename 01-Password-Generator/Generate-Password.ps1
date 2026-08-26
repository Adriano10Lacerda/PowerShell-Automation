
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

$Caracteres = "ABCDEF"

$Senha = ""

for ($i =0; $i -lt 5; $i++)
{
    $Posicao = Get-Random -Minimum 0 -Maximum $Caracteres.Length
    $Senha += $Caracteres[$Posicao]
}

Write-Host "Senha: $Senha"

