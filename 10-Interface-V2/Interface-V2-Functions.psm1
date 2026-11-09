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

function Request-V2OneTimeAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Read', 'Write')] [string]$Kind,
        [Parameter(Mandatory)] [string]$Target
    )
    $phrase = if ($Kind -eq 'Read') { 'AUTORIZAR LEITURA' } else { 'AUTORIZAR ALTERAÇÃO' }
    $response = Read-Host "Para autorizar somente esta operação ($Kind) em '$Target', digite '$phrase'"
    return ($response -ceq $phrase)
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


function Resolve-V2ComputerSummaryState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSCustomObject]$Summary)

    $modeMessage = $null
    if ($Summary.Mode -eq "Simulation" -or ($Summary.IsSimulated -and -not $Summary.Preview)) {
        $modeMessage = "Dados demonstrativos fictícios; nenhuma consulta foi realizada."
    }
    elseif ($Summary.Mode -eq "Preview" -or $Summary.Preview) {
        $modeMessage = "Pré-visualização; nenhuma consulta foi realizada e nenhum inventário é apresentado."
    }

    $collectionMessage = $null
    if ($Summary.CollectionStatus -eq "Partial") {
        $collectionMessage = "Coleta parcial; alguns dados ou consultas falharam."
    }
    elseif ($Summary.CollectionStatus -eq "Error" -or $Summary.Status -eq "Error") {
        $collectionMessage = "A coleta falhou; os estados desconhecidos não representam ausência ou desconexão."
    }

    $adMessage = switch ([string]$Summary.ADQueryStatus) {
        "Found" { if ($Summary.ADFound -eq $true) { "Sim" } else { "Estado inconsistente" } }
        "NotFound" { "Não" }
        "NotQueried" { "Não consultado" }
        "Error" { "Erro na consulta" }
        default { if ($Summary.IsSimulated -or $Summary.Preview) { "Não consultado" } else { "Estado desconhecido" } }
    }
    $connectivityMessage = switch ([string]$Summary.ConnectivityStatus) {
        "Responded" { "Sim" }
        "NoResponse" { "Sem resposta confirmada" }
        "NotQueried" { "Não consultado" }
        "Error" { "Erro na consulta" }
        default { if ($Summary.IsSimulated -or $Summary.Preview) { "Não consultado" } else { "Estado desconhecido" } }
    }

    [PSCustomObject]@{
        ModeMessage = $modeMessage
        CollectionMessage = $collectionMessage
        ADMessage = $adMessage
        ConnectivityMessage = $connectivityMessage
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

    $displayState = Resolve-V2ComputerSummaryState -Summary $Summary

    $statusColor = Get-V2StatusColor `
        -Status ([string]$Summary.Status)

    Write-Host `
        "  $($Summary.Status)" `
        -ForegroundColor $statusColor

    if ($displayState.ModeMessage) { Write-Host "  $($displayState.ModeMessage)" -ForegroundColor Yellow }
    if ($displayState.CollectionMessage) { Write-Host "  $($displayState.CollectionMessage)" -ForegroundColor Yellow }

    Write-Host ""

    Write-Host "  ACTIVE DIRECTORY" -ForegroundColor DarkCyan

    $adColor = if ($displayState.ADMessage -eq "Sim") { "Green" } elseif ($displayState.ADMessage -eq "Erro na consulta") { "Red" } else { "Yellow" }
    Write-Host "  Encontrado   : $($displayState.ADMessage)" -ForegroundColor $adColor

    Write-Host ""

    Write-Host "  CONECTIVIDADE" -ForegroundColor DarkCyan

    $connectivityColor = if ($displayState.ConnectivityMessage -eq "Sim") { "Green" } elseif ($displayState.ConnectivityMessage -in @("Sem resposta confirmada", "Erro na consulta")) { "Red" } else { "Yellow" }
    Write-Host "  Acessível    : $($displayState.ConnectivityMessage)" -ForegroundColor $connectivityColor

    Write-Host ""

    Write-Host "  SISTEMA OPERACIONAL" -ForegroundColor DarkCyan
    if ($null -eq $Summary.OperatingSystem) { Write-Host "  Não coletado (modo sem I/O)" -ForegroundColor Gray }
    else { Write-Host "  $($Summary.OperatingSystem)" -ForegroundColor White }
    Write-Host ""

    Write-Host "  HARDWARE" -ForegroundColor DarkCyan
    Write-Host "  Modelo       : $(if ($null -eq $Summary.Model) { 'Não coletado' } else { $Summary.Model })"
    Write-Host "  Processador  : $(if ($null -eq $Summary.Processor) { 'Não coletado' } else { $Summary.Processor })"
    Write-Host "  Memória      : $(if ($null -eq $Summary.MemoryGB) { 'Não coletada' } else { "$($Summary.MemoryGB) GB" })"
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
        "SimulationMode",
        "Preview",
        "Mode",
        "Cancelled",
        "IsSimulated",
        "Success",
        "CollectionStatus",
        "ADQueryStatus",
        "ConnectivityStatus",
        "QueryStatus",
        "Errors"
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

    $nextMode = "Simulation"
    do {

        try {

            $summaryArguments = @{ Hostname = $hostname }
            if ($nextMode -eq "Cancelled") {
                $summary = [PSCustomObject]@{
                    Hostname = $hostname; Status = "Cancelled"; ADFound = $null; Reachable = $null
                    OperatingSystem = $null; Model = $null; MemoryGB = $null; Processor = $null
                    BitLockerStatus = "NotCollected"; ErrorCount = 1; SimulationMode = $false
                    Preview = $true; Mode = "Preview"; Cancelled = $true; Success = $false
                    Errors = @([PSCustomObject]@{ Source = "InterfaceV2"; Message = "Coleta cancelada pelo operador; nenhuma consulta foi realizada." })
                    IsSimulated = $false
                }
            }
            else {
                if ($nextMode -eq "Real") { $summaryArguments.AllowRealOperation = $true }
                elseif ($nextMode -eq "Preview") { $summaryArguments.Preview = $true }
                else { $summaryArguments.SimulationMode = $true }
                $summary = Get-ComputerManagementSummary @summaryArguments
            }

            # A autorização vale somente para esta chamada; a próxima consulta
            # volta ao modo seguro até nova escolha e confirmação do operador.
            $nextMode = "Simulation"

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

            if ($summary.Cancelled) {
                Write-V2Header -Title "COMPUTER MANAGEMENT" -Subtitle "Coleta cancelada"
                Write-Host "  A coleta foi cancelada; nenhuma consulta foi realizada." -ForegroundColor Yellow
            }
            else {
                Show-V2ComputerSummary -Summary $summary
            }

            $option = Read-Host "  Selecione uma opção"

            switch ($option) {

                "1" {
                    Write-Host "  Próxima consulta: [S]imulação, [P]review ou [R]eal autorizada?"
                    $modeChoice = (Read-Host "  Modo [S/P/R]").Trim().ToUpperInvariant()
                    if ($modeChoice -eq "P") { $nextMode = "Preview" }
                    elseif ($modeChoice -eq "R") {
                        $confirmation = Read-Host "  Para autorizar esta coleta, digite COLETAR REAL"
                        if ($confirmation -ceq "COLETAR REAL") { $nextMode = "Real" }
                        else {
                            $nextMode = "Cancelled"
                            Write-Host "  Autorização não confirmada; nenhuma coleta real será feita." -ForegroundColor Yellow
                        }
                    }
                    else { $nextMode = "Simulation" }
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

    $allowRealRead = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Read -Target $SamAccountName)) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; return }
        $allowRealRead = $true
    }

    $preview = Get-UserUnlockPreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -AllowRealRead:$allowRealRead

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

    $allowRealWrite = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Write -Target $SamAccountName)) { Write-Host "Alteração real cancelada." -ForegroundColor Yellow; return }
        $allowRealWrite = $true
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserUnlockAccount `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute `
        -AllowRealRead:$allowRealRead `
        -AllowRealWrite:$allowRealWrite

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

    $allowRealRead = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Read -Target $SamAccountName)) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; return }
        $allowRealRead = $true
    }

    $preview = Get-UserEnablePreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -AllowRealRead:$allowRealRead

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

    $allowRealWrite = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Write -Target $SamAccountName)) { Write-Host "Alteração real cancelada." -ForegroundColor Yellow; return }
        $allowRealWrite = $true
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserEnableAccount `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute `
        -AllowRealRead:$allowRealRead `
        -AllowRealWrite:$allowRealWrite

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

    $allowRealRead = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Read -Target $SamAccountName)) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; return }
        $allowRealRead = $true
    }

    $preview = Get-UserDisablePreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -AllowRealRead:$allowRealRead

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

    $allowRealWrite = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Write -Target $SamAccountName)) { Write-Host "Alteração real cancelada." -ForegroundColor Yellow; return }
        $allowRealWrite = $true
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserDisableAccount `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute `
        -AllowRealRead:$allowRealRead `
        -AllowRealWrite:$allowRealWrite

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

    $allowRealRead = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Read -Target $SamAccountName)) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; return }
        $allowRealRead = $true
    }

    $preview = Get-UserForcePasswordChangePreview `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -AllowRealRead:$allowRealRead

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

    $allowRealWrite = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Write -Target $SamAccountName)) { Write-Host "Alteração real cancelada." -ForegroundColor Yellow; return }
        $allowRealWrite = $true
    }

    Write-Host ""
    Write-Host "  Executando ação..." -ForegroundColor Cyan

    $executionResult = Invoke-UserForcePasswordChange `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -Execute `
        -AllowRealRead:$allowRealRead `
        -AllowRealWrite:$allowRealWrite

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

        $allowRealRead = $false
        $domainController = ""
        $modeChoice = (Read-Host "Modo de consulta [S]imulação/[R]eal").Trim().ToUpperInvariant()
        if ($modeChoice -eq "R") {
            $readAuthorization = Read-Host "Para autorizar esta leitura AD, digite CONSULTAR REAL"
            if ($readAuthorization -ceq "CONSULTAR REAL") { $allowRealRead = $true }
            else { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; Pause-V2; continue }

            $domainController = (Read-Host "Informe o DomainController configurado para esta consulta").Trim()
            $controllerLabels = @($domainController.TrimEnd('.').Split('.'))
            $invalidControllerLabel = @($controllerLabels | Where-Object {
                $_.Length -lt 1 -or $_.Length -gt 63 -or $_ -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$'
            }).Count -gt 0
            if ([string]::IsNullOrWhiteSpace($domainController) -or
                $domainController.Length -gt 253 -or
                $domainController -match "[\x00-\x20]" -or
                $invalidControllerLabel) {
                Write-Host "DomainController ausente ou inválido; nenhuma consulta foi realizada." -ForegroundColor Red
                Pause-V2
                continue
            }
        }

        try {

            # ------------------------------------------------
            # Configuração V2 de consulta
            # ------------------------------------------------

            $configuration = [PSCustomObject]@{
                Domain = "BRSPO"

                DomainController = $domainController

                SimulationMode = (-not $allowRealRead)

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
                -Configuration $configuration `
                -AllowRealRead:$allowRealRead

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
# GROUP MANAGEMENT
# ============================================================

function Get-V2GroupConfiguration {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        SimulationMode = $true

        ActiveDirectory = [PSCustomObject]@{
            DomainController = ""
            TargetOU         = ""
        }

        Group = [PSCustomObject]@{
            DefaultScope       = "Global"
            DefaultCategory    = "Security"
            RequireDescription = $true
        }

        Operations = [PSCustomObject]@{
            CreateGroup = $true
            AddMember   = $true
            RemoveMember = $true
            ListMembers = $true
        }

        Simulation = [PSCustomObject]@{
            ExistingGroups = @(
                [PSCustomObject]@{
                    Name        = "TI-Suporte"
                    Description = "Grupo de suporte de TI"
                    Members     = @("maria.santos")
                }

                [PSCustomObject]@{
                    Name        = "TI-Infraestrutura"
                    Description = "Grupo da equipe de infraestrutura"
                    Members     = @("carlos.oliveira")
                }

                [PSCustomObject]@{
                    Name        = "Administradores"
                    Description = "Grupo de administradores"
                    Members     = @("joao.silva")
                }
            )

            ExistingUsers = @(
                "joao.silva"
                "maria.santos"
                "carlos.oliveira"
            )
        }
    }
}


function Show-V2GroupSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$GroupResult
    )

    Write-V2Header `
        -Title "GROUP MANAGEMENT" `
        -Subtitle "Consulta do grupo"

    $data = $GroupResult.Data

    Write-Host "  GRUPO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Nome         : $($data.Identity.Name)"
    Write-Host "  Descrição    : $($data.Description)"
    Write-Host "  Escopo       : $($data.Identity.GroupScope)"
    Write-Host "  Categoria    : $($data.Identity.GroupCategory)"
    Write-Host ""

    Write-Host "  MEMBROS" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Quantidade   : $(@($data.Members).Count)"

    if ($GroupResult.SimulationMode) {
        Write-Host ""
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. Listar membros" -ForegroundColor White
    Write-Host "  2. Adicionar membro" -ForegroundColor Green
    Write-Host "  3. Remover membro" -ForegroundColor Red
    Write-Host "  4. Nova consulta" -ForegroundColor White
    Write-Host "  0. Voltar" -ForegroundColor Red
    Write-Host ""
}


function Get-V2GroupQueryMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Result
    )

    if ($Result.Cancelled -or $Result.Status -eq "Cancelled") {
        return "Consulta cancelada; nenhum estado operacional foi confirmado."
    }

    if ($Result.SimulationMode -or $Result.QueryStatus -eq "Simulation") {
        return "Dados demonstrativos; nenhuma consulta real foi realizada."
    }

    switch ([string]$Result.QueryStatus) {
        "NotFound" { return "Grupo não encontrado; a consulta foi concluída sem resultado." }
        "Error" { return "Erro durante a consulta do grupo; o estado não foi confirmado." }
        "NotQueried" { return "Consulta não realizada; o estado do grupo é desconhecido." }
        "Found" { return "Grupo encontrado." }
        default { return "Estado do grupo desconhecido; não foi possível confirmar o resultado da consulta." }
    }
}


function Show-V2GroupMembers {
    [CmdletBinding()]
    param(
         [Parameter(Mandatory)]
         [PSCustomObject]$MembersResult,

         [Parameter(Mandatory)]
         [string]$GroupName
    )

    Write-V2Header `
        -Title "GROUP MANAGEMENT" `
        -Subtitle "Membros do grupo"

    Write-Host "  GRUPO: $GroupName" -ForegroundColor DarkCyan
    Write-Host ""

    if (-not $MembersResult.Success) {
        $queryMessage = Get-V2GroupQueryMessage -Result $MembersResult
        Write-Host "  $queryMessage" -ForegroundColor Red
        Write-Host ""
        Write-Host "  $($MembersResult.Error)" -ForegroundColor Yellow
        Pause-V2
        return
    }

    $members = @($MembersResult.Data)

    if ($members.Count -eq 0) {
        Write-Host "  Nenhum membro encontrado." -ForegroundColor Gray
    }
    else {
        $index = 1

        foreach ($member in $members) {
            Write-Host `
                ("  {0,2}. {1}" -f $index, $member.SamAccountName) `
                -ForegroundColor White

            $index++
        }
    }

    if ($MembersResult.SimulationMode) {
        Write-Host ""
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
    }

    Write-Host ""
    Pause-V2
}


function Start-V2GroupAddMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $member = Read-Host "  SamAccountName do usuário"

    if ([string]::IsNullOrWhiteSpace($member)) {
        Write-Host ""
        Write-Host "  SamAccountName não informado." -ForegroundColor Red
        Pause-V2
        return
    }

    $member = $member.Trim()

    $allowRealRead = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Read -Target "$GroupName/$member")) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; return }
        $allowRealRead = $true
    }

    Write-V2Header `
        -Title "ADICIONAR MEMBRO" `
        -Subtitle "Preview da ação"

    $preview = Get-GroupManagementPreview `
        -Action "AddMember" `
        -GroupName $GroupName `
        -SamAccountName $member `
        -Configuration $Configuration `
        -AllowRealRead:$allowRealRead

    if (-not $preview.Success) {
        Write-Host "  Não foi possível gerar o preview." -ForegroundColor Red
        Write-Host ""
        Write-Host "  $($preview.Error)" -ForegroundColor Yellow
        Pause-V2
        return
    }

    $previewData = $preview.Data

    Write-Host "  GRUPO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Grupo          : $($previewData.GroupName)"
    Write-Host "  Usuário        : $($previewData.SamAccountName)"
    Write-Host ""

    Write-Host "  AÇÃO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Estado atual   : $($previewData.CurrentState)"
    Write-Host "  Estado destino : $($previewData.TargetState)"
    Write-Host ""

    if ($preview.SimulationMode) {
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
        Write-Host ""
    }

    if (-not $previewData.CanExecute) {
        Write-Host "  Ação não disponível." -ForegroundColor Yellow
        Pause-V2
        return
    }

    $confirmation = Read-Host "  Confirma a execução? [S/N]"

    if ($confirmation.Trim().ToUpperInvariant() -ne "S") {
        Write-Host ""
        Write-Host "  Ação cancelada pelo operador." -ForegroundColor Yellow
        Pause-V2
        return
    }

    $allowRealWrite = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Write -Target "$GroupName/$member")) { Write-Host "Alteração real cancelada." -ForegroundColor Yellow; return }
        $allowRealWrite = $true
    }

    $result = Invoke-GroupAddMember `
        -GroupName $GroupName `
        -SamAccountName $member `
        -Configuration $Configuration `
        -Execute `
        -AllowRealRead:$allowRealRead `
        -AllowRealWrite:$allowRealWrite

    Write-Host ""

    if ($result.Success) {
        if ($result.Status -eq "Simulated") {
            Write-Host "  MEMBRO ADICIONADO EM SIMULAÇÃO." -ForegroundColor Yellow
        }
        else {
            Write-Host "  MEMBRO ADICIONADO COM SUCESSO." -ForegroundColor Green
        }

        if ($null -ne $result.Audit) {
            Show-V2ActionAudit -ExecutionResult $result
        }
    }
    else {
        Write-Host "  FALHA AO ADICIONAR MEMBRO." -ForegroundColor Red
        Write-Host ""
        Write-Host "  $($result.Error)" -ForegroundColor Yellow
    }

    Pause-V2
}

function Start-V2GroupRemoveMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $member = Read-Host "  SamAccountName do usuário"

    if ([string]::IsNullOrWhiteSpace($member)) {
        Write-Host ""
        Write-Host "  SamAccountName não informado." -ForegroundColor Red
        Pause-V2
        return
    }

    $member = $member.Trim()

    $allowRealRead = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Read -Target "$GroupName/$member")) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; return }
        $allowRealRead = $true
    }

    Write-V2Header `
        -Title "REMOVER MEMBRO" `
        -Subtitle "Preview da ação"

    $preview = Get-GroupManagementPreview `
        -Action "RemoveMember" `
        -GroupName $GroupName `
        -SamAccountName $member `
        -Configuration $Configuration `
        -AllowRealRead:$allowRealRead

    if (-not $preview.Success) {
        Write-Host "  Não foi possível gerar o preview." -ForegroundColor Red
        Write-Host ""
        Write-Host "  $($preview.Error)" -ForegroundColor Yellow
        Pause-V2
        return
    }

    $previewData = $preview.Data

    Write-Host "  GRUPO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Grupo          : $($previewData.GroupName)"
    Write-Host "  Usuário        : $($previewData.SamAccountName)"
    Write-Host ""

    Write-Host "  AÇÃO" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Estado atual   : $($previewData.CurrentState)"
    Write-Host "  Estado destino : $($previewData.TargetState)"
    Write-Host ""

    if ($preview.SimulationMode) {
        Write-Host "  MODO SIMULAÇÃO: ATIVO" -ForegroundColor Yellow
        Write-Host ""
    }

    if (-not $previewData.CanExecute) {
        Write-Host "  Ação não disponível." -ForegroundColor Yellow
        Pause-V2
        return
    }

    $confirmation = Read-Host "  Confirma a execução? [S/N]"

    if ($confirmation.Trim().ToUpperInvariant() -ne "S") {
        Write-Host ""
        Write-Host "  Ação cancelada pelo operador." -ForegroundColor Yellow
        Pause-V2
        return
    }

    $allowRealWrite = $false
    if (-not $Configuration.SimulationMode) {
        if (-not (Request-V2OneTimeAuthorization -Kind Write -Target "$GroupName/$member")) { Write-Host "Alteração real cancelada." -ForegroundColor Yellow; return }
        $allowRealWrite = $true
    }

    $result = Invoke-GroupRemoveMember `
        -GroupName $GroupName `
        -SamAccountName $member `
        -Configuration $Configuration `
        -Execute `
        -AllowRealRead:$allowRealRead `
        -AllowRealWrite:$allowRealWrite

    Write-Host ""

    if ($result.Success) {
        if ($result.Status -eq "Simulated") {
            Write-Host "  MEMBRO REMOVIDO EM SIMULAÇÃO." -ForegroundColor Yellow
        }
        else {
            Write-Host "  MEMBRO REMOVIDO COM SUCESSO." -ForegroundColor Green
        }

        if ($null -ne $result.Audit) {
            Show-V2ActionAudit -ExecutionResult $result
        }
    }
    else {
        Write-Host "  FALHA AO REMOVER MEMBRO." -ForegroundColor Red
        Write-Host ""
        Write-Host "  $($result.Error)" -ForegroundColor Yellow
    }

    Pause-V2
}

function Start-V2GroupManagement {
    [CmdletBinding()]
    param()

    $managementPath = Join-Path `
        $PSScriptRoot `
        "..\Core\Group\Management\Group-Management.psm1"

    if (-not (Test-Path -LiteralPath $managementPath)) {
        throw "Group Management não encontrado: $managementPath"
    }

    Import-Module `
        $managementPath `
        -Force `
        -ErrorAction Stop

    $configuration = Get-V2GroupConfiguration
    $groupModeChoice = (Read-Host "Modo padrão do fluxo [S]imulação/[R]eal sob autorização por operação").Trim().ToUpperInvariant()
    if ($groupModeChoice -eq "R") { $configuration.SimulationMode = $false }

    :GroupQueryLoop do {

        Write-V2Header `
            -Title "GROUP MANAGEMENT" `
            -Subtitle "Consulta e administração de grupos do Active Directory"

        Write-Host "  Digite o nome do grupo." -ForegroundColor Gray
        Write-Host ""

        $groupName = Read-Host "  Grupo"

        if ([string]::IsNullOrWhiteSpace($groupName)) {
            Write-Host ""
            Write-Host "  Grupo não informado." -ForegroundColor Red
            Pause-V2
            return
        }

        $groupName = $groupName.Trim()

        try {

            $allowRealRead = $false
            if (-not $configuration.SimulationMode) {
                if (-not (Request-V2OneTimeAuthorization -Kind Read -Target $groupName)) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; continue }
                $allowRealRead = $true
            }

            $groupResult = Get-GroupManagement `
                -GroupName $groupName `
                -Configuration $configuration `
                -AllowRealRead:$allowRealRead

            if (-not $groupResult.Success) {
                Write-V2Header `
                    -Title "GROUP MANAGEMENT" `
                    -Subtitle "Resultado da consulta"

                $queryMessage = Get-V2GroupQueryMessage -Result $groupResult
                Write-Host `
                    "  $queryMessage" `
                    -ForegroundColor Red

                Write-Host ""

                Write-Host `
                    "  $($groupResult.Error)" `
                    -ForegroundColor Yellow

                Pause-V2
                continue
            }


            do {

                Show-V2GroupSummary `
                    -GroupResult $groupResult

                $option = Read-Host "  Selecione uma opção"

                switch ($option) {

                    "1" {
                        $allowMembersRead = $false
                        if (-not $configuration.SimulationMode) {
                            if (-not (Request-V2OneTimeAuthorization -Kind Read -Target "$groupName membros")) { Write-Host "Leitura real cancelada." -ForegroundColor Yellow; break }
                            $allowMembersRead = $true
                        }
                        $membersResult = Get-GroupManagementMembers `
                            -GroupName $groupName `
                            -Configuration $configuration `
                            -AllowRealRead:$allowMembersRead

                        Show-V2GroupMembers `
                            -MembersResult $membersResult `
                            -GroupName $groupName
                    }

                    "2" {
                        Start-V2GroupAddMember `
                            -GroupName $groupName `
                            -Configuration $configuration

                        $allowRefreshRead = $false
                        if (-not $configuration.SimulationMode) { $allowRefreshRead = Request-V2OneTimeAuthorization -Kind Read -Target $groupName }
                        $groupResult = Get-GroupManagement `
                            -GroupName $groupName `
                            -Configuration $configuration `
                            -AllowRealRead:$allowRefreshRead
                    }

                    "3" {
                        Start-V2GroupRemoveMember `
                            -GroupName $groupName `
                            -Configuration $configuration

                        $allowRefreshRead = $false
                        if (-not $configuration.SimulationMode) { $allowRefreshRead = Request-V2OneTimeAuthorization -Kind Read -Target $groupName }
                        $groupResult = Get-GroupManagement `
                            -GroupName $groupName `
                            -Configuration $configuration `
                            -AllowRealRead:$allowRefreshRead
                    }

                    "4" {
                        continue GroupQueryLoop
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
                -Title "GROUP MANAGEMENT" `
                -Subtitle "Erro"

            Write-Host `
                "  Erro ao consultar grupo:" `
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


# ============================================================
# POLICIES - GROUP POLICY MANAGEMENT
# ============================================================

function Start-V2PolicyManagement {
    [CmdletBinding()]
    param()

    $gpoPath = Join-Path $PSScriptRoot "..\07-GPO-Management\GPO-Functions.psm1"
    $configPath = Join-Path $PSScriptRoot "..\07-GPO-Management\GPO-Configuration.json"

    if (-not (Test-Path -LiteralPath $gpoPath)) {
        throw "Módulo GPO não encontrado: $gpoPath"
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Configuração GPO não encontrada: $configPath"
    }

    $configuration = Get-Content -LiteralPath $configPath -Raw |
        ConvertFrom-Json

    if ($configuration.SimulationMode -ne $true) {
        Write-V2Header -Title "POLICIES" -Subtitle "Gerenciamento de Group Policy Objects"
        Write-Host "Operação bloqueada: SimulationMode não está ativo." -ForegroundColor Red
        Write-Host "Nenhuma operação foi executada." -ForegroundColor Yellow
        Pause-V2
        return
    }

    Import-Module $gpoPath -Force -ErrorAction Stop

    $gpoModule = Get-Module |
        Where-Object {
            $_.Path -and
            ([System.IO.Path]::GetFullPath($_.Path) -eq
             [System.IO.Path]::GetFullPath((Resolve-Path $gpoPath).Path))
        } |
        Select-Object -First 1

    if ($null -eq $gpoModule) {
        throw "Não foi possível carregar o módulo GPO."
    }

    do {
        Write-V2Header -Title "POLICIES" -Subtitle "Gerenciamento de Group Policy Objects"
        Write-Host "  1. Listar GPOs" -ForegroundColor Green
        Write-Host "  2. Consultar GPO" -ForegroundColor White
        Write-Host "  3. Consultar vínculos" -ForegroundColor White
        Write-Host "  4. Simular criação de GPO" -ForegroundColor White
        Write-Host ""
        Write-Host "  Modo de simulação: ATIVO" -ForegroundColor Yellow
        Write-Host "  0. Voltar" -ForegroundColor Red

        $option = Read-Host "  Selecione uma opção"
        $operation = $null
        $gpoName = $null
        $description = $null

        switch ($option) {
            "1" {
                $operation = "ListGPOs"
            }
            "2" {
                $gpoName = (Read-Host "  Nome da GPO").Trim()
                if ([string]::IsNullOrWhiteSpace($gpoName)) {
                    Write-Host "Nome da GPO obrigatório." -ForegroundColor Red
                    Pause-V2
                    continue
                }
                $operation = "CheckGPO"
            }
            "3" {
                $gpoName = (Read-Host "  Nome da GPO").Trim()
                if ([string]::IsNullOrWhiteSpace($gpoName)) {
                    Write-Host "Nome da GPO obrigatório." -ForegroundColor Red
                    Pause-V2
                    continue
                }
                $operation = "ListLinks"
            }
            "4" {
                $gpoName = (Read-Host "  Nome da nova GPO").Trim()
                if ([string]::IsNullOrWhiteSpace($gpoName)) {
                    Write-Host "Nome da GPO obrigatório." -ForegroundColor Red
                    Pause-V2
                    continue
                }

                $description = (Read-Host "  Descrição da GPO").Trim()
                if (
                    $configuration.GPO.RequireDescription -eq $true -and
                    [string]::IsNullOrWhiteSpace($description)
                ) {
                    Write-Host "A descrição é obrigatória." -ForegroundColor Red
                    Pause-V2
                    continue
                }

                Write-Host "A criação será somente simulada." -ForegroundColor Yellow
                $confirmation = Read-Host "Confirmar simulação? (S/N)"
                if ($confirmation -notmatch '^(S|SIM)$') {
                    Write-Host "Operação cancelada." -ForegroundColor Yellow
                    Pause-V2
                    continue
                }

                $operation = "CreateGPO"
            }
            "0" {
                break
            }
            default {
                Write-Host "Opção inválida." -ForegroundColor Red
                Pause-V2
                continue
            }
        }

        if ($operation) {
            try {
                $invokeCommand = "{0}\Invoke-GPOManagement" -f $gpoModule.Name
                $parameters = @{
                    Operation     = $operation
                    Configuration = $configuration
                    ErrorAction   = "Stop"
                }

                if (-not [string]::IsNullOrWhiteSpace($gpoName)) {
                    $parameters.GPOName = $gpoName
                }

                if ($null -ne $description) {
                    $parameters.Description = $description
                }

                $result = & $invokeCommand @parameters

                Write-Host ""
                Write-Host "Operação: $operation" -ForegroundColor Cyan
                Write-Host "SimulationMode: ATIVO" -ForegroundColor Yellow
                if ($null -ne $result) {
                    $result | Format-List * | Out-Host
                }
                else {
                    Write-Host "A operação não retornou dados." -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "Falha na operação: $($_.Exception.Message)" -ForegroundColor Red
            }

            Pause-V2
        }

    } while ($option -ne "0")
}
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
                Start-V2GroupManagement
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
                Start-V2PolicyManagement
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
    "Get-V2GroupConfiguration",
    "Show-V2GroupSummary",
    "Show-V2GroupMembers",
    "Start-V2GroupAddMember",
    "Start-V2GroupRemoveMember",
    "Start-V2GroupManagement",
    "Start-V2PolicyManagement",
    "Show-V2MainMenu",
    "Start-V2Interface"
)



