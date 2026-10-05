#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$modulePath = Join-Path `
    $scriptRoot `
    "Group-Management.psm1"

$configPath = Join-Path `
    (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptRoot))) `
    "06-AD-Group-Management\Group-Configuration.json"

$auditPath = Join-Path `
    (Split-Path -Parent (Split-Path -Parent $scriptRoot)) `
    "Audit\Audit-Functions.psm1"

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
Write-Host " TESTES - GROUP MANAGEMENT + AUDIT V2" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------
# ESTRUTURA
# ---------------------------------------------------------

Test-Result `
    -Name "Group-Management.psm1 existe" `
    -Condition (Test-Path -LiteralPath $modulePath)

Test-Result `
    -Name "Group-Configuration.json existe" `
    -Condition (Test-Path -LiteralPath $configPath)

Test-Result `
    -Name "Audit-Functions.psm1 existe" `
    -Condition (Test-Path -LiteralPath $auditPath)

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Group-Management.psm1 não encontrado."
}

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Group-Configuration.json não encontrado."
}

if (-not (Test-Path -LiteralPath $auditPath)) {
    throw "Audit-Functions.psm1 não encontrado."
}

Import-Module $modulePath -Force -ErrorAction Stop
Import-Module $auditPath -Force -ErrorAction Stop

$config = Get-Content `
    -LiteralPath $configPath `
    -Raw `
    -ErrorAction Stop | ConvertFrom-Json

# ---------------------------------------------------------
# CONFIGURAÇÃO
# ---------------------------------------------------------

Test-Result `
    -Name "Configuration está em SimulationMode" `
    -Condition ($config.SimulationMode -eq $true)

# ---------------------------------------------------------
# AUDIT CORE
# ---------------------------------------------------------

$audit = New-AuditRecord `
    -Action "GroupTest" `
    -SamAccountName "joao.silva" `
    -Result "Success" `
    -SimulationMode $true `
    -Changed $false

Test-Result `
    -Name "Audit Core cria registro" `
    -Condition ($audit.Success -eq $true)

Test-Result `
    -Name "Audit possui Timestamp" `
    -Condition ($null -ne $audit.Data.Timestamp)

Test-Result `
    -Name "Audit possui Action" `
    -Condition ($audit.Data.Action -eq "GroupTest")

Test-Result `
    -Name "Audit possui SamAccountName" `
    -Condition ($audit.Data.SamAccountName -eq "joao.silva")

$validation = Test-AuditRecord `
    -Record $audit.Data

Test-Result `
    -Name "Registro de Audit é validado" `
    -Condition ($validation.Success -eq $true -and $validation.Data -eq $true)

# ---------------------------------------------------------
# CONSULTA
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Consulta de TI-Suporte retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Consulta retorna SimulationMode" `
    -Condition ($result.SimulationMode -eq $true)

Test-Result `
    -Name "TI-Suporte inicia com 1 membro" `
    -Condition ($result.Data.MemberCount -eq 1)

# ---------------------------------------------------------
# PREVIEW ADD
# ---------------------------------------------------------

$result = Get-GroupManagementPreview `
    -Action "AddMember" `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "Preview de adição retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Preview exige confirmação" `
    -Condition ($result.Data.RequiresConfirm -eq $true)

# ---------------------------------------------------------
# EXECUTE ADD + AUDIT
# ---------------------------------------------------------

$result = Invoke-GroupAddMember `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config `
    -Execute

Test-Result `
    -Name "Adição simulada retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Adição informa Changed=true" `
    -Condition ($result.Changed -eq $true)

Test-Result `
    -Name "Adição permanece em SimulationMode" `
    -Condition ($result.SimulationMode -eq $true)

Test-Result `
    -Name "Adição retorna Audit" `
    -Condition ($null -ne $result.Audit)

Test-Result `
    -Name "Audit da adição possui Action AddMember" `
    -Condition ($result.Audit.Action -eq "AddMember")

Test-Result `
    -Name "Audit da adição possui usuário correto" `
    -Condition ($result.Audit.SamAccountName -eq "joao.silva")

Test-Result `
    -Name "Audit da adição possui Result Success" `
    -Condition ($result.Audit.Result -eq "Success")

Test-Result `
    -Name "Audit da adição informa SimulationMode=true" `
    -Condition ($result.Audit.SimulationMode -eq $true)

Test-Result `
    -Name "Audit da adição informa Changed=true" `
    -Condition ($result.Audit.Changed -eq $true)

$validation = Test-AuditRecord `
    -Record $result.Audit

Test-Result `
    -Name "Audit da adição passa na validação" `
    -Condition ($validation.Success -eq $true -and $validation.Data -eq $true)

# ---------------------------------------------------------
# PERSISTÊNCIA
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Membro adicionado permanece no inventário" `
    -Condition (
        $result.Data.MemberCount -eq 2 -and
        @($result.Data.Members | Where-Object {
            $_.SamAccountName -eq "joao.silva"
        }).Count -eq 1
    )

# ---------------------------------------------------------
# DUPLICIDADE
# ---------------------------------------------------------

$result = Get-GroupManagementPreview `
    -Action "AddMember" `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "Adição duplicada é bloqueada" `
    -Condition ($result.Success -eq $false)

# ---------------------------------------------------------
# PREVIEW REMOVE
# ---------------------------------------------------------

$result = Get-GroupManagementPreview `
    -Action "RemoveMember" `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config

Test-Result `
    -Name "Preview de remoção retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Preview de remoção exige confirmação" `
    -Condition ($result.Data.RequiresConfirm -eq $true)

# ---------------------------------------------------------
# EXECUTE REMOVE + AUDIT
# ---------------------------------------------------------

$result = Invoke-GroupRemoveMember `
    -GroupName "TI-Suporte" `
    -SamAccountName "joao.silva" `
    -Configuration $config `
    -Execute

Test-Result `
    -Name "Remoção simulada retorna sucesso" `
    -Condition ($result.Success -eq $true)

Test-Result `
    -Name "Remoção informa Changed=true" `
    -Condition ($result.Changed -eq $true)

Test-Result `
    -Name "Remoção retorna Audit" `
    -Condition ($null -ne $result.Audit)

Test-Result `
    -Name "Audit da remoção possui Action RemoveMember" `
    -Condition ($result.Audit.Action -eq "RemoveMember")

Test-Result `
    -Name "Audit da remoção possui usuário correto" `
    -Condition ($result.Audit.SamAccountName -eq "joao.silva")

Test-Result `
    -Name "Audit da remoção possui Result Success" `
    -Condition ($result.Audit.Result -eq "Success")

Test-Result `
    -Name "Audit da remoção informa SimulationMode=true" `
    -Condition ($result.Audit.SimulationMode -eq $true)

Test-Result `
    -Name "Audit da remoção informa Changed=true" `
    -Condition ($result.Audit.Changed -eq $true)

$validation = Test-AuditRecord `
    -Record $result.Audit

Test-Result `
    -Name "Audit da remoção passa na validação" `
    -Condition ($validation.Success -eq $true -and $validation.Data -eq $true)

# ---------------------------------------------------------
# PERSISTÊNCIA DA REMOÇÃO
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Suporte" `
    -Configuration $config

Test-Result `
    -Name "Membro removido não aparece mais" `
    -Condition (
        $result.Data.MemberCount -eq 1 -and
        @($result.Data.Members | Where-Object {
            $_.SamAccountName -eq "joao.silva"
        }).Count -eq 0
    )

# ---------------------------------------------------------
# PROTEÇÃO DE AUDIT
# ---------------------------------------------------------

$badRecord = [PSCustomObject]@{
    Timestamp      = Get-Date
    Operator       = "Test"
    Action         = "Invalid"
    SamAccountName = "joao.silva"
    Result         = "Failed"
    SimulationMode = $true
    Changed        = $false
    Password       = "NAO-DEVE-EXISTIR"
}

$validation = Test-AuditRecord `
    -Record $badRecord

Test-Result `
    -Name "Audit rejeita registro contendo Password" `
    -Condition ($validation.Success -eq $false)

# ---------------------------------------------------------
# OUTROS GRUPOS
# ---------------------------------------------------------

$result = Get-GroupManagement `
    -GroupName "TI-Infraestrutura" `
    -Configuration $config

Test-Result `
    -Name "TI-Infraestrutura continua íntegro" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.MemberCount -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "carlos.oliveira"
    )

$result = Get-GroupManagement `
    -GroupName "Administradores" `
    -Configuration $config

Test-Result `
    -Name "Administradores continua íntegro" `
    -Condition (
        $result.Success -eq $true -and
        $result.Data.MemberCount -eq 1 -and
        $result.Data.Members[0].SamAccountName -eq "joao.silva"
    )

# ---------------------------------------------------------
# RESULTADO
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