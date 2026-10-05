#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$functionsPath = Join-Path $scriptRoot "Group-Functions.psm1"

$configPath = Join-Path `
    (Split-Path -Parent (Split-Path -Parent $scriptRoot)) `
    "06-AD-Group-Management\Group-Configuration.json"

$testsPassed = 0
$testsFailed = 0

function Test-Result {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "[PASSOU] $Name" -ForegroundColor Green
        $script:testsPassed++
    }
    else {
        Write-Host "[FALHOU] $Name" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       TESTES - GROUP CORE V2" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------
# TESTE 1 - Arquivo do módulo
# ---------------------------------------------------------

Test-Result `
    -Name "Group-Functions.psm1 existe" `
    -Condition (Test-Path -LiteralPath $functionsPath)

# ---------------------------------------------------------
# TESTE 2 - Arquivo de configuração
# ---------------------------------------------------------

Test-Result `
    -Name "Group-Configuration.json existe" `
    -Condition (Test-Path -LiteralPath $configPath)

if (-not (Test-Path -LiteralPath $functionsPath)) {
    throw "Group-Functions.psm1 não encontrado."
}

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Group-Configuration.json não encontrado."
}

# ---------------------------------------------------------
# Importação
# ---------------------------------------------------------

Import-Module $functionsPath -Force -ErrorAction Stop

$config = Get-Content `
    -LiteralPath $configPath `
    -Raw `
    -ErrorAction Stop | ConvertFrom-Json

# ---------------------------------------------------------
# TESTE 3 - SimulationMode
# ---------------------------------------------------------

Test-Result `
    -Name "Configuration está em SimulationMode" `
    -Condition ([bool]$config.SimulationMode -eq $true)

# ---------------------------------------------------------
# TESTE 4 - Grupo TI-Suporte
# ---------------------------------------------------------

$result = Get-GroupADInfo `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Get-GroupADInfo retorna sucesso para TI-Suporte" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 5 - SimulationMode no resultado
# ---------------------------------------------------------

Test-Result `
    -Name "Get-GroupADInfo informa SimulationMode" `
    -Condition ($result.SimulationMode -eq $true)

# ---------------------------------------------------------
# TESTE 6 - Nome
# ---------------------------------------------------------

Test-Result `
    -Name "Nome do grupo é TI-Suporte" `
    -Condition ($result.Data.Identity.Name -eq "TI-Suporte")

# ---------------------------------------------------------
# TESTE 7 - Description
# ---------------------------------------------------------

Test-Result `
    -Name "Descrição do grupo foi carregada" `
    -Condition ($result.Data.Description -eq "Grupo de suporte de TI")

# ---------------------------------------------------------
# TESTE 8 - Scope
# ---------------------------------------------------------

Test-Result `
    -Name "Scope padrão é Global" `
    -Condition ($result.Data.Identity.GroupScope -eq "Global")

# ---------------------------------------------------------
# TESTE 9 - Category
# ---------------------------------------------------------

Test-Result `
    -Name "Category padrão é Security" `
    -Condition ($result.Data.Identity.GroupCategory -eq "Security")

# ---------------------------------------------------------
# TESTE 10 - Exists
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Suporte existe" `
    -Condition ($result.Data.Exists -eq $true)

# ---------------------------------------------------------
# TESTE 11 - MemberCount
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Suporte possui 1 membro" `
    -Condition ($result.Data.MemberCount -eq 1)

# ---------------------------------------------------------
# TESTE 12 - Membros
# ---------------------------------------------------------

$result = Get-GroupMembers `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Get-GroupMembers retorna sucesso" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 13 - Quantidade
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Suporte possui 1 membro na consulta" `
    -Condition (@($result.Data).Count -eq 1)

# ---------------------------------------------------------
# TESTE 14 - Maria Santos
# ---------------------------------------------------------

Test-Result `
    -Name "maria.santos está em TI-Suporte" `
    -Condition ($result.Data[0].SamAccountName -eq "maria.santos")

# ---------------------------------------------------------
# TESTE 15 - ObjectClass
# ---------------------------------------------------------

Test-Result `
    -Name "Membro possui ObjectClass user" `
    -Condition ($result.Data[0].ObjectClass -eq "user")

# ---------------------------------------------------------
# TESTE 16 - Membership verdadeiro
# ---------------------------------------------------------

$result = Get-GroupMembership `
    -GroupName "TI-Suporte" `
    -SamAccountName "maria.santos" `
    -Configuration $config

Test-Result `
    -Name "maria.santos é membro de TI-Suporte" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.IsMember -eq $true
    )

# ---------------------------------------------------------
# TESTE 17 - Membership falso
# ---------------------------------------------------------

$result = Get-GroupMembership `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "joao.silva não é membro de TI-Suporte" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.IsMember -eq $false
    )

# ---------------------------------------------------------
# TESTE 18 - Grupo TI-Infraestrutura
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "TI-Infraestrutura" `
    -Configuration $config

Test-Result `
    -Name "Inventário de TI-Infraestrutura retorna sucesso" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 19 - Carlos Oliveira
# ---------------------------------------------------------

Test-Result `
    -Name "TI-Infraestrutura possui carlos.oliveira" `
    -Condition (
        @($result.Data.Members).Count -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "carlos.oliveira"
    )

# ---------------------------------------------------------
# TESTE 20 - Administradores
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "Administradores" `
    -Configuration $config

Test-Result `
    -Name "Inventário de Administradores retorna sucesso" `
    -Condition ($result.Success -eq $true)

# ---------------------------------------------------------
# TESTE 21 - João Silva
# ---------------------------------------------------------

Test-Result `
    -Name "Administradores possui joao.silva" `
    -Condition (
        @($result.Data.Members).Count -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "joao.silva"
    )

# ---------------------------------------------------------
# TESTE 22 - Grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupADInfo `
    -GroupName "Grupo-Inexistente" `
    -Configuration $config

Test-Result `
    -Name "Grupo inexistente retorna falha controlada" `
    -Condition (
        $result.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($result.Error)
    )

# ---------------------------------------------------------
# TESTE 23 - Membros de grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupMembers `
    -GroupName "Grupo-Inexistente" `
    -Configuration $config

Test-Result `
    -Name "Consulta de membros de grupo inexistente falha controladamente" `
    -Condition (
        $result.Success -eq $false -and
        -not [string]::IsNullOrWhiteSpace($result.Error)
    )

# ---------------------------------------------------------
# TESTE 24 - Membership de grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupMembership `
    -GroupName "Grupo-Inexistente" `
    -SamAccountName "maria.santos" `
    -Configuration $config

Test-Result `
    -Name "Membership de grupo inexistente falha controladamente" `
    -Condition (
        $result.Success -eq $false
    )

# ---------------------------------------------------------
# TESTE 25 - Inventário de grupo inexistente
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "Grupo-Inexistente" `
    -Configuration $config

Test-Result `
    -Name "Inventário de grupo inexistente falha controladamente" `
    -Condition (
        $result.Success -eq $false
    )

# ---------------------------------------------------------
# TESTE 26 - Modelo de erro
# ---------------------------------------------------------

Test-Result `
    -Name "Resultado de erro possui campo Error" `
    -Condition (
        $null -ne $result.PSObject.Properties["Error"]
    )

# ---------------------------------------------------------
# TESTE 27 - Modelo de sucesso
# ---------------------------------------------------------

$result = Get-GroupInventory `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Resultado de sucesso possui campo Data" `
    -Condition (
        $null -ne $result.PSObject.Properties["Data"]
    )

# ---------------------------------------------------------
# TESTE 28 - Inventário consolidado
# ---------------------------------------------------------

Test-Result `
    -Name "Inventário possui Identity" `
    -Condition (
        $null -ne $result.Data.PSObject.Properties["Identity"]
    )

# ---------------------------------------------------------
# TESTE 29 - Inventário possui Members
# ---------------------------------------------------------

Test-Result `
    -Name "Inventário possui Members" `
    -Condition (
        $null -ne $result.Data.PSObject.Properties["Members"]
    )

# ---------------------------------------------------------
# TESTE 30 - Inventário possui MemberCount
# ---------------------------------------------------------

Test-Result `
    -Name "Inventário possui MemberCount" `
    -Condition (
        $result.Data.MemberCount -eq 1
    )

# ---------------------------------------------------------
# RESUMO
# ---------------------------------------------------------

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "              RESULTADO FINAL" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host "Testes aprovados : $testsPassed" -ForegroundColor Green
Write-Host "Testes falhos    : $testsFailed" -ForegroundColor Red
Write-Host "Total            : $($testsPassed + $testsFailed)"

Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}