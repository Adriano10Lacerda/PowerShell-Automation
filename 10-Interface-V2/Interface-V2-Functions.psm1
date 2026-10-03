#Requires -Version 5.1

# ============================================================
# FUNÇÕES GERAIS
# ============================================================

function Write-V2Header {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Subtitle
    )

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                 POWER SHELL AUTOMATION V2" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  $Title" -ForegroundColor Yellow

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host "  $Subtitle" -ForegroundColor Gray
    }

    Write-Host ""
}


function Pause-V2 {
    [CmdletBinding()]
    param()

    Write-Host ""
    Read-Host "Pressione ENTER para continuar"
}


function Show-V2DevelopmentMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    Write-V2Header `
        -Title $ModuleName `
        -Subtitle "Módulo V2"

    Write-Host "  Este módulo está em desenvolvimento." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  A funcionalidade será disponibilizada nas próximas" -ForegroundColor Gray
    Write-Host "  etapas da V2." -ForegroundColor Gray

    Pause-V2
}


# ============================================================
# COMPUTER - CORES
# ============================================================

function Get-V2StatusColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    switch ($Status) {
        "Online"        { return "Green" }
        "ReachableOnly" { return "Yellow" }
        "Offline"       { return "Red" }
        "Unavailable"   { return "Red" }
        default         { return "Yellow" }
    }
}


function Get-V2BitLockerColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    switch ($Status) {
        "Protected"    { return "Green" }
        "NotProtected" { return "Red" }
        "NotAvailable" { return "Yellow" }
        default        { return "Yellow" }
    }
}


function Show-V2ComputerSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Summary
    )

    Write-V2Header `
        -Title "COMPUTER MANAGEMENT" `
        -Subtitle "Resumo do computador"

    Write-Host "  COMPUTADOR" -ForegroundColor DarkCyan
    Write-Host "  Hostname    : $($Summary.Hostname)" -ForegroundColor White
    Write-Host ""

    Write-Host "  STATUS" -ForegroundColor DarkCyan

    $statusColor = Get-V2StatusColor `
        -Status ([string]$Summary.Status)

    Write-Host `
        "  $($Summary.Status)" `
        -ForegroundColor $statusColor

    Write-Host ""

    Write-Host "  ACTIVE DIRECTORY" -ForegroundColor DarkCyan

    if ($Summary.ADFound) {
        Write-Host "  Encontrado   : Sim" -ForegroundColor Green
    }
    else {
        Write-Host "  Encontrado   : Não" -ForegroundColor Yellow
    }

    Write-Host ""

    Write-Host "  CONECTIVIDADE" -ForegroundColor DarkCyan

    if ($Summary.Reachable) {
        Write-Host "  Acessível    : Sim" -ForegroundColor Green
    }
    else {
        Write-Host "  Acessível    : Não" -ForegroundColor Red
    }

    Write-Host ""

    Write-Host "  SISTEMA OPERACIONAL" -ForegroundColor DarkCyan
    Write-Host "  $($Summary.OperatingSystem)" -ForegroundColor White
    Write-Host ""

    Write-Host "  HARDWARE" -ForegroundColor DarkCyan
    Write-Host "  Modelo       : $($Summary.Model)"
    Write-Host "  Processador  : $($Summary.Processor)"
    Write-Host "  Memória      : $($Summary.MemoryGB) GB"
    Write-Host ""

    Write-Host "  BITLOCKER" -ForegroundColor DarkCyan

    $bitLockerColor = Get-V2BitLockerColor `
        -Status ([string]$Summary.BitLockerStatus)

    Write-Host `
        "  $($Summary.BitLockerStatus)" `
        -ForegroundColor $bitLockerColor

    Write-Host ""

    Write-Host "  DIAGNÓSTICO" -ForegroundColor DarkCyan

    if ($Summary.ErrorCount -eq 0) {
        Write-Host "  Erros        : 0" -ForegroundColor Green
    }
    else {
        Write-Host `
            "  Erros        : $($Summary.ErrorCount)" `
            -ForegroundColor Yellow
    }

    if ($Summary.SimulationMode) {
        Write-Host ""
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. Atualizar consulta" -ForegroundColor White
    Write-Host "  2. Ver detalhes" -ForegroundColor White
    Write-Host "  0. Voltar" -ForegroundColor Red
    Write-Host ""
}


function Show-V2ComputerDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Summary
    )

    Write-V2Header `
        -Title "COMPUTER MANAGEMENT" `
        -Subtitle "Detalhes da consulta"

    Write-Host "  DETALHES" -ForegroundColor DarkCyan
    Write-Host ""

    $properties = @(
        "Hostname",
        "Status",
        "ADFound",
        "Reachable",
        "OperatingSystem",
        "Model",
        "MemoryGB",
        "Processor",
        "BitLockerStatus",
        "ErrorCount",
        "SimulationMode"
    )

    foreach ($property in $properties) {

        $propertyValue = $Summary.PSObject.Properties[$property]

        if ($null -ne $propertyValue) {

            $value = $propertyValue.Value

            if ($null -eq $value) {
                $value = "<null>"
            }

            Write-Host `
                ("  {0,-18}: {1}" -f $property, $value)
        }
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    Pause-V2
}


function Start-V2ComputerManagement {
    [CmdletBinding()]
    param()

    $managementPath = Join-Path `
        $PSScriptRoot `
        "..\Core\Computer\Management\Computer-Management.psm1"

    if (-not (Test-Path -LiteralPath $managementPath)) {
        throw "Computer Management não encontrado: $managementPath"
    }

    Import-Module `
        $managementPath `
        -Force `
        -ErrorAction Stop

    $hostname = Read-Host "  Hostname"

    if ([string]::IsNullOrWhiteSpace($hostname)) {

        Write-Host ""
        Write-Host "  Hostname não informado." -ForegroundColor Red

        Pause-V2
        return
    }

    $hostname = $hostname.Trim()

    do {

        try {

            $summary = Get-ComputerManagementSummary `
                -Hostname $hostname

            if ($null -eq $summary) {

                Write-V2Header `
                    -Title "COMPUTER MANAGEMENT" `
                    -Subtitle "Resultado da consulta"

                Write-Host `
                    "  Não foi possível obter informações do computador." `
                    -ForegroundColor Red

                Pause-V2
                return
            }

            Show-V2ComputerSummary -Summary $summary

            $option = Read-Host "  Selecione uma opção"

            switch ($option) {

                "1" {
                }

                "2" {
                    Show-V2ComputerDetails `
                        -Summary $summary
                }

                "0" {
                    return
                }

                default {
                    Write-Host ""
                    Write-Host "  Opção inválida." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }

        }
        catch {

            Write-V2Header `
                -Title "COMPUTER MANAGEMENT" `
                -Subtitle "Erro"

            Write-Host `
                "  Erro ao consultar computador:" `
                -ForegroundColor Red

            Write-Host ""

            Write-Host `
                "  $($_.Exception.Message)" `
                -ForegroundColor Red

            Pause-V2

            return
        }

    } while ($true)
}


# ============================================================
# USER MANAGEMENT
# ============================================================

function Show-V2UserSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Summary
    )

    Write-V2Header `
        -Title "USER MANAGEMENT" `
        -Subtitle "Resumo do usuário"

    Write-Host "  IDENTIDADE" -ForegroundColor DarkCyan

    Write-Host `
        "  SamAccountName : $($Summary.SamAccountName)" `
        -ForegroundColor White

    Write-Host `
        "  UPN            : $($Summary.UserPrincipalName)" `
        -ForegroundColor White

    Write-Host ""

    Write-Host "  USUÁRIO" -ForegroundColor DarkCyan

    Write-Host `
        "  Nome           : $($Summary.DisplayName)" `
        -ForegroundColor White

    Write-Host `
        "  E-mail         : $($Summary.Mail)" `
        -ForegroundColor White

    Write-Host ""

    Write-Host "  STATUS DA CONTA" -ForegroundColor DarkCyan

    $statusColor = "Yellow"

    switch ([string]$Summary.Status) {
        "Active"          { $statusColor = "Green" }
        "Disabled"        { $statusColor = "Red" }
        "LockedOut"       { $statusColor = "Red" }
        "PasswordExpired" { $statusColor = "Yellow" }
    }

    Write-Host `
        "  Status          : $($Summary.Status)" `
        -ForegroundColor $statusColor

    Write-Host `
        "  Enabled         : $($Summary.Enabled)" `
        -ForegroundColor White

    Write-Host `
        "  LockedOut       : $($Summary.LockedOut)" `
        -ForegroundColor White

    Write-Host `
        "  PasswordExpired : $($Summary.PasswordExpired)" `
        -ForegroundColor White

    Write-Host ""

    Write-Host "  ORGANIZAÇÃO" -ForegroundColor DarkCyan

    Write-Host `
        "  Departamento    : $($Summary.Department)" `
        -ForegroundColor White

    Write-Host `
        "  Cargo           : $($Summary.Title)" `
        -ForegroundColor White

    Write-Host ""

    Write-Host "  ATIVIDADE" -ForegroundColor DarkCyan

    Write-Host `
        "  Último logon    : $($Summary.LastLogonDate)" `
        -ForegroundColor White

    if ($Summary.SimulationMode) {
        Write-Host ""
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. Ver detalhes" -ForegroundColor White
    Write-Host "  2. Desbloquear conta" -ForegroundColor Yellow
    Write-Host "  3. Ativar conta" -ForegroundColor Green
    Write-Host "  4. Desativar conta" -ForegroundColor Red
    Write-Host "  5. Forçar troca de senha no próximo logon" -ForegroundColor Yellow
    Write-Host "  6. Nova consulta" -ForegroundColor White
    Write-Host "  0. Voltar" -ForegroundColor Red
    Write-Host ""
}


function Show-V2UserDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$User
    )

    Write-V2Header `
        -Title "USER MANAGEMENT" `
        -Subtitle "Detalhes do usuário"

    Write-Host "  DETALHES" -ForegroundColor DarkCyan
    Write-Host ""

    $sections = @(
        @{
            Name = "IDENTITY"
            Properties = @(
                "SamAccountName",
                "UserPrincipalName",
                "DistinguishedName",
                "ObjectGuid"
            )
            Source = "Identity"
        },
        @{
            Name = "PERSONAL"
            Properties = @(
                "Name",
                "GivenName",
                "Surname",
                "DisplayName",
                "Mail"
            )
            Source = "Personal"
        },
        @{
            Name = "ORGANIZATION"
            Properties = @(
                "Department",
                "Title",
                "Company",
                "Manager"
            )
            Source = "Organization"
        },
        @{
            Name = "ACCOUNT"
            Properties = @(
                "Enabled",
                "LockedOut",
                "PasswordExpired",
                "PasswordNeverExpires",
                "PasswordNotRequired",
                "AccountExpirationDate"
            )
            Source = "Account"
        },
        @{
            Name = "ACTIVITY"
            Properties = @(
                "LastLogonDate",
                "Created",
                "Modified"
            )
            Source = "Activity"
        }
    )

    foreach ($section in $sections) {

        $sourceObject = $User.($section.Source)

        if ($null -eq $sourceObject) {
            continue
        }

        Write-Host "  $($section.Name)" -ForegroundColor DarkCyan
        Write-Host ""

        foreach ($property in $section.Properties) {

            $propertyValue = $sourceObject.PSObject.Properties[$property]

            if ($null -ne $propertyValue) {

                $value = $propertyValue.Value

                if ($null -eq $value) {
                    $value = "<null>"
                }

                Write-Host `
                    ("  {0,-24}: {1}" -f $property, $value)
            }
        }

        Write-Host ""
    }

    Write-Host "  GROUPS" -ForegroundColor DarkCyan

    if ($null -eq $User.Groups -or @($User.Groups).Count -eq 0) {
        Write-Host "  Nenhum grupo disponível." -ForegroundColor Gray
    }
    else {
        foreach ($group in @($User.Groups)) {
            Write-Host "  - $group"
        }
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    Pause-V2
}


# ============================================================
# USER ACCOUNT ACTIONS - HELPERS
# ============================================================

function Show-V2ActionAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ExecutionResult
    )

    if ($null -eq $ExecutionResult.Audit) {
        return
    }

    Write-Host ""
    Write-Host "  AUDITORIA" -ForegroundColor DarkCyan
    Write-Host ""

    $auditRecord = $ExecutionResult.Audit

    Write-Host `
        "  Ação       : $($auditRecord.Action)" `
        -ForegroundColor White

    Write-Host `
        "  Resultado  : $($auditRecord.Result)" `
        -ForegroundColor White

    Write-Host `
        "  Simulação  : $($auditRecord.SimulationMode)" `
        -ForegroundColor White

    Write-Host `
        "  Alterado   : $($auditRecord.Changed)" `
        -ForegroundColor White

    Write-Host `
        "  Operador   : $($auditRecord.Operator)" `
        -ForegroundColor White

    Write-Host `
        "  Data/Hora  : $($auditRecord.Timestamp)" `
        -ForegroundColor White
}


function Show-V2ExecutionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ExecutionResult,

        [Parameter(Mandatory)]
        [string]$SuccessMessage,

        [Parameter(Mandatory)]
        [string]$SimulationMessage,

        [Parameter(Mandatory)]
        [string]$NoChangeMessage
    )

    Write-Host ""

    if (-not $ExecutionResult.Success) {

        Write-Host `
            "  FALHA NA EXECUÇÃO" `
            -ForegroundColor Red

        Write-Host ""

        Write-Host `
            "  $($ExecutionResult.Error)" `
            -ForegroundColor Yellow

        Pause-V2
        return $false
    }

    switch ($ExecutionResult.Status) {

        "Simulated" {
            Write-Host `
                "  $SimulationMessage" `
                -ForegroundColor Yellow

            Write-Host ""
            Write-Host `
                "  Nenhuma alteração foi realizada no Active Directory." `
                -ForegroundColor Yellow
        }

        "Executed" {
            Write-Host `
                "  $SuccessMessage" `
                -ForegroundColor Green

            Write-Host ""
            Write-Host `
                "  Alteração realizada no Active Directory." `
                -ForegroundColor Green
        }

        "NoChange" {
            Write-Host `
                "  $NoChangeMessage" `
                -ForegroundColor Yellow
        }

        default {
            Write-Host `
                "  Resultado: $($ExecutionResult.Status)" `
                -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  RESULTADO DA AÇÃO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Status     : $($ExecutionResult.Status)"
    Write-Host "  Executado  : $($ExecutionResult.Executed)"
    Write-Host "  Alterado   : $($ExecutionResult.Changed)"

    Show-V2ActionAudit -ExecutionResult $ExecutionResult

    Pause-V2
    return $true
}


# ============================================================
# USER ACCOUNT ACTIONS - UNLOCK
# ============================================================

function Start-V2UserUnlockAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $actionsPath = Join-Path `
        $PSScriptRoot `
        "..\Core\User\Actions\User-Account-Actions.psm1"

    if (-not (Test-Path -LiteralPath $actionsPath)) {
        throw "User Account Actions não encontrado: $actionsPath"
    }

    Import-Module `
        $actionsPath `
        -Force `
        -ErrorAction Stop

    Write-V2Header `
        -Title "DESBLOQUEAR CONTA" `
        -Subtitle "Preview da ação"

    $preview = Get-UserUnlockPreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration

    if (-not $preview.Success) {

        Write-Host `
            "  Não foi possível gerar o preview." `
            -ForegroundColor Red

        Write-Host ""

        Write-Host `
            "  $($preview.Error)" `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "  USUÁRIO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  SamAccountName : $($preview.SamAccountName)"
    Write-Host ""

    Write-Host "  AÇÃO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Descrição      : $($preview.Preview.Description)"
    Write-Host "  Estado atual   : $($preview.Preview.CurrentState)"
    Write-Host "  Estado destino : $($preview.Preview.TargetState)"
    Write-Host ""

    if ($preview.SimulationMode) {
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
        Write-Host ""
    }

    if (-not $preview.CanExecute) {

        Write-Host `
            "  Nenhuma alteração necessária." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $confirmation = Read-Host "  Confirma a execução? [S/N]"

    if ($confirmation.Trim().ToUpperInvariant() -ne "S") {

        Write-Host ""
        Write-Host `
            "  Ação cancelada pelo operador." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserUnlockAccount `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute

    Show-V2ExecutionResult `
        -ExecutionResult $executionResult `
        -SuccessMessage "CONTA DESBLOQUEADA COM SUCESSO" `
        -SimulationMessage "DESBLOQUEIO SIMULADO COM SUCESSO" `
        -NoChangeMessage "NENHUMA ALTERAÇÃO NECESSÁRIA"
}


# ============================================================
# USER ACCOUNT ACTIONS - ENABLE
# ============================================================

function Start-V2UserEnableAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $actionsPath = Join-Path `
        $PSScriptRoot `
        "..\Core\User\Actions\User-Account-Actions.psm1"

    if (-not (Test-Path -LiteralPath $actionsPath)) {
        throw "User Account Actions não encontrado: $actionsPath"
    }

    Import-Module `
        $actionsPath `
        -Force `
        -ErrorAction Stop

    Write-V2Header `
        -Title "ATIVAR CONTA" `
        -Subtitle "Preview da ação"

    $preview = Get-UserEnablePreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration

    if (-not $preview.Success) {

        Write-Host `
            "  Não foi possível gerar o preview." `
            -ForegroundColor Red

        Write-Host ""

        Write-Host `
            "  $($preview.Error)" `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "  USUÁRIO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  SamAccountName : $($preview.SamAccountName)"
    Write-Host ""

    Write-Host "  AÇÃO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Descrição      : $($preview.Preview.Description)"
    Write-Host "  Estado atual   : $($preview.Preview.CurrentState)"
    Write-Host "  Estado destino : $($preview.Preview.TargetState)"
    Write-Host ""

    if ($preview.SimulationMode) {
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
        Write-Host ""
    }

    if (-not $preview.CanExecute) {

        Write-Host `
            "  Nenhuma alteração necessária." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $confirmation = Read-Host "  Confirma a execução? [S/N]"

    if ($confirmation.Trim().ToUpperInvariant() -ne "S") {

        Write-Host ""
        Write-Host `
            "  Ação cancelada pelo operador." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserEnableAccount `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute

    Show-V2ExecutionResult `
        -ExecutionResult $executionResult `
        -SuccessMessage "CONTA ATIVADA COM SUCESSO" `
        -SimulationMessage "ATIVAÇÃO SIMULADA COM SUCESSO" `
        -NoChangeMessage "A CONTA JÁ ESTÁ ATIVA"
}


# ============================================================
# USER ACCOUNT ACTIONS - DISABLE
# ============================================================

function Start-V2UserDisableAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $actionsPath = Join-Path `
        $PSScriptRoot `
        "..\Core\User\Actions\User-Account-Actions.psm1"

    if (-not (Test-Path -LiteralPath $actionsPath)) {
        throw "User Account Actions não encontrado: $actionsPath"
    }

    Import-Module `
        $actionsPath `
        -Force `
        -ErrorAction Stop

    Write-V2Header `
        -Title "DESATIVAR CONTA" `
        -Subtitle "Preview da ação"

    $preview = Get-UserDisablePreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration

    if (-not $preview.Success) {

        Write-Host `
            "  Não foi possível gerar o preview." `
            -ForegroundColor Red

        Write-Host ""

        Write-Host `
            "  $($preview.Error)" `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "  USUÁRIO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  SamAccountName : $($preview.SamAccountName)"
    Write-Host ""

    Write-Host "  AÇÃO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Descrição      : $($preview.Preview.Description)"
    Write-Host "  Estado atual   : $($preview.Preview.CurrentState)"
    Write-Host "  Estado destino : $($preview.Preview.TargetState)"
    Write-Host ""

    if ($preview.SimulationMode) {
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
        Write-Host ""
    }

    if (-not $preview.CanExecute) {

        Write-Host `
            "  Nenhuma alteração necessária." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $confirmation = Read-Host "  Confirma a execução? [S/N]"

    if ($confirmation.Trim().ToUpperInvariant() -ne "S") {

        Write-Host ""
        Write-Host `
            "  Ação cancelada pelo operador." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserDisableAccount `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute

    Show-V2ExecutionResult `
        -ExecutionResult $executionResult `
        -SuccessMessage "CONTA DESATIVADA COM SUCESSO" `
        -SimulationMessage "DESATIVAÇÃO SIMULADA COM SUCESSO" `
        -NoChangeMessage "A CONTA JÁ ESTÁ DESATIVADA"
}


# ============================================================
# USER ACCOUNT ACTIONS - FORCE PASSWORD CHANGE
# ============================================================

function Start-V2UserForcePasswordChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $actionsPath = Join-Path `
        $PSScriptRoot `
        "..\Core\User\Actions\User-Account-Actions.psm1"

    if (-not (Test-Path -LiteralPath $actionsPath)) {
        throw "User Account Actions não encontrado: $actionsPath"
    }

    Import-Module `
        $actionsPath `
        -Force `
        -ErrorAction Stop

    Write-V2Header `
        -Title "FORÇAR TROCA DE SENHA" `
        -Subtitle "Preview da ação"

    $preview = Get-UserForcePasswordChangePreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration

    if (-not $preview.Success) {

        Write-Host `
            "  Não foi possível gerar o preview." `
            -ForegroundColor Red

        Write-Host ""

        Write-Host `
            "  $($preview.Error)" `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "  USUÁRIO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  SamAccountName : $($preview.SamAccountName)"
    Write-Host ""

    Write-Host "  AÇÃO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Descrição      : $($preview.Preview.Description)"
    Write-Host "  Estado atual   : $($preview.Preview.CurrentState)"
    Write-Host "  Estado destino : $($preview.Preview.TargetState)"
    Write-Host ""

    if ($preview.SimulationMode) {
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
        Write-Host ""
    }

    if (-not $preview.CanExecute) {

        Write-Host `
            "  Nenhuma alteração necessária." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $confirmation = Read-Host "  Confirma a execução? [S/N]"

    if ($confirmation.Trim().ToUpperInvariant() -ne "S") {

        Write-Host ""
        Write-Host `
            "  Ação cancelada pelo operador." `
            -ForegroundColor Yellow

        Pause-V2
        return
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserForcePasswordChange `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute

    Show-V2ExecutionResult `
        -ExecutionResult $executionResult `
        -SuccessMessage "TROCA DE SENHA OBRIGATÓRIA CONFIGURADA COM SUCESSO" `
        -SimulationMessage "TROCA DE SENHA SIMULADA COM SUCESSO" `
        -NoChangeMessage "A TROCA DE SENHA JÁ ESTÁ CONFIGURADA"
}


# ============================================================
# USER MANAGEMENT - LOOP PRINCIPAL
# ============================================================

function Start-V2UserManagement {
    [CmdletBinding()]
    param()

    $managementPath = Join-Path `
        $PSScriptRoot `
        "..\Core\User\Management\User-Management.psm1"

    if (-not (Test-Path -LiteralPath $managementPath)) {
        throw "User Management não encontrado: $managementPath"
    }

    Import-Module `
        $managementPath `
        -Force `
        -ErrorAction Stop

    do {

        Write-V2Header `
            -Title "USER MANAGEMENT" `
            -Subtitle "Consulta de usuários do Active Directory"

        Write-Host "  Digite o SamAccountName do usuário." -ForegroundColor Gray
        Write-Host ""

        $samAccountName = Read-Host "  SamAccountName"

        if ([string]::IsNullOrWhiteSpace($samAccountName)) {

            Write-Host ""
            Write-Host "  SamAccountName não informado." -ForegroundColor Red

            Pause-V2
            return
        }

        $samAccountName = $samAccountName.Trim()

        try {

            # ------------------------------------------------
            # Configuração V2 de consulta
            # ------------------------------------------------

            $configuration = [PSCustomObject]@{
                Domain = "BRSPO"

                DomainController = ""

                SimulationMode = $true

                UserPrincipalName = [PSCustomObject]@{
                    Enabled = $true
                    Domain  = "example.local"
                }

                Simulation = [PSCustomObject]@{
                    ExistingSamAccountNames = @(
                        "silva.maria.ext",
                        "silva.maria2.ext",
                        "silva.maria3.ext"
                    )

                    LockedSamAccountNames = @(
                        "silva.maria.ext"
                    )

                    DisabledSamAccountNames = @(
                        "silva.maria3.ext"
                    )

                    PasswordChangeAtLogonSamAccountNames = @()
                }
            }

            # ------------------------------------------------
            # User Management
            # ------------------------------------------------

            $managementResult = Get-UserManagement `
                -SamAccountName $samAccountName `
                -Configuration $configuration

            if (-not $managementResult.Success) {

                Write-V2Header `
                    -Title "USER MANAGEMENT" `
                    -Subtitle "Resultado da consulta"

                Write-Host `
                    "  Usuário não encontrado ou consulta não concluída." `
                    -ForegroundColor Red

                Write-Host ""

                foreach ($errorMessage in @($managementResult.Errors)) {
                    Write-Host `
                        "  $errorMessage" `
                        -ForegroundColor Yellow
                }

                Pause-V2
                continue
            }

            # ------------------------------------------------
            # Menu do usuário
            # ------------------------------------------------

            do {

                Show-V2UserSummary `
                    -Summary $managementResult.Summary

                $option = Read-Host "  Selecione uma opção"

                switch ($option) {

                    "1" {
                        Show-V2UserDetails `
                            -User $managementResult.Data
                    }

                    "2" {
                        Start-V2UserUnlockAccount `
                            -SamAccountName $samAccountName `
                            -Configuration $configuration
                    }

                    "3" {
                        Start-V2UserEnableAccount `
                            -SamAccountName $samAccountName `
                            -Configuration $configuration
                    }

                    "4" {
                        Start-V2UserDisableAccount `
                            -SamAccountName $samAccountName `
                            -Configuration $configuration
                    }

                    "5" {
                        Start-V2UserForcePasswordChange `
                            -SamAccountName $samAccountName `
                            -Configuration $configuration
                    }

                    "6" {
                        break
                    }

                    "0" {
                        return
                    }

                    default {
                        Write-Host ""
                        Write-Host "  Opção inválida." -ForegroundColor Red
                        Start-Sleep -Seconds 1
                    }
                }

            } while ($true)

        }
        catch {

            Write-V2Header `
                -Title "USER MANAGEMENT" `
                -Subtitle "Erro"

            Write-Host `
                "  Erro ao consultar usuário:" `
                -ForegroundColor Red

            Write-Host ""

            Write-Host `
                "  $($_.Exception.Message)" `
                -ForegroundColor Red

            Pause-V2
            return
        }

    } while ($true)
}


# ============================================================
# MENU PRINCIPAL
# ============================================================

function Show-V2MainMenu {
    [CmdletBinding()]
    param()

    Write-V2Header `
        -Title "IT INFRASTRUCTURE TOOL" `
        -Subtitle "Automação e administração de infraestrutura Microsoft"

    Write-Host "  1.  Users" -ForegroundColor Green
    Write-Host "  2.  Accounts" -ForegroundColor White
    Write-Host "  3.  Groups" -ForegroundColor White
    Write-Host "  4.  Computers" -ForegroundColor Green
    Write-Host "  5.  Policies" -ForegroundColor White
    Write-Host "  6.  Reports" -ForegroundColor White
    Write-Host "  7.  Settings" -ForegroundColor White
    Write-Host ""
    Write-Host "  0.  Exit" -ForegroundColor Red
    Write-Host ""
}


function Start-V2Interface {
    [CmdletBinding()]
    param()

    do {

        Show-V2MainMenu

        $option = Read-Host "  Selecione uma opção"

        switch ($option) {

            "1" {
                Start-V2UserManagement
            }

            "2" {
                Show-V2DevelopmentMessage `
                    -ModuleName "ACCOUNTS"
            }

            "3" {
                Show-V2DevelopmentMessage `
                    -ModuleName "GROUPS"
            }

            "4" {
                Write-V2Header `
                    -Title "COMPUTER MANAGEMENT" `
                    -Subtitle "Consulta de inventário e status do computador"

                Write-Host "  Digite o hostname do computador." -ForegroundColor Gray
                Write-Host ""

                Start-V2ComputerManagement
            }

            "5" {
                Show-V2DevelopmentMessage `
                    -ModuleName "POLICIES"
            }

            "6" {
                Show-V2DevelopmentMessage `
                    -ModuleName "REPORTS"
            }

            "7" {
                Show-V2DevelopmentMessage `
                    -ModuleName "SETTINGS"
            }

            "0" {
                Clear-Host

                Write-Host ""
                Write-Host `
                    "  POWER SHELL AUTOMATION V2 encerrado." `
                    -ForegroundColor Cyan
                Write-Host ""
            }

            default {
                Write-Host ""
                Write-Host `
                    "  Opção inválida." `
                    -ForegroundColor Red

                Start-Sleep -Seconds 1
            }
        }

    } while ($option -ne "0")
}


# ============================================================
# EXPORTAÇÃO
# ============================================================

Export-ModuleMember -Function @(
    "Write-V2Header",
    "Pause-V2",
    "Show-V2DevelopmentMessage",
    "Get-V2StatusColor",
    "Get-V2BitLockerColor",
    "Show-V2ComputerSummary",
    "Show-V2ComputerDetails",
    "Start-V2ComputerManagement",
    "Show-V2UserSummary",
    "Show-V2UserDetails",
    "Start-V2UserUnlockAccount",
    "Start-V2UserEnableAccount",
    "Start-V2UserDisableAccount",
    "Start-V2UserForcePasswordChange",
    "Start-V2UserManagement",
    "Show-V2MainMenu",
    "Start-V2Interface"
)