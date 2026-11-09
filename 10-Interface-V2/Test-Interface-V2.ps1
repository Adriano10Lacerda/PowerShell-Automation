#Requires -Version 5.1

<#
.SYNOPSIS
    Testes da Interface Central V2.

.DESCRIPTION
    Valida a estrutura, funções e integrações
    da Interface V2.

    Integrações atuais:
    - Computer Management
    - User Management
    - User Account Actions
        - Unlock
        - Enable
        - Disable
        - Force Password Change

.NOTES
    V2 - Interface Central
#>

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$global:PSModuleAutoLoadingPreference = 'None'
Write-Output 'HARNESS_START:INTERFACE_V2_V1'

if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) {
    throw "ActiveDirectory já está carregado neste processo; o teste da Interface não continuará."
}

$script:Passed = 0
$script:Failed = 0

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success
    )

    if ($Success) {
        Write-Host "PASSOU: $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "FALHOU: $Name" -ForegroundColor Red
        $script:Failed++
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        TESTES - INTERFACE V2" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$functionsPath = Join-Path `
    $PSScriptRoot `
    "Interface-V2-Functions.psm1"

$launcherPath = Join-Path `
    $PSScriptRoot `
    "Interface-V2.ps1"

$computerManagementPath = Join-Path `
    $PSScriptRoot `
    "..\Core\Computer\Management\Computer-Management.psm1"

$userManagementPath = Join-Path `
    $PSScriptRoot `
    "..\Core\User\Management\User-Management.psm1"

$userActionsPath = Join-Path `
    $PSScriptRoot `
    "..\Core\User\Actions\User-Account-Actions.psm1"


# ============================================================
# TESTES DE ARQUIVOS
# ============================================================

Write-TestResult `
    "Interface-V2-Functions.psm1 existe" `
    (Test-Path -LiteralPath $functionsPath)

Write-TestResult `
    "Interface-V2.ps1 existe" `
    (Test-Path -LiteralPath $launcherPath)

Write-TestResult `
    "Computer-Management.psm1 existe" `
    (Test-Path -LiteralPath $computerManagementPath)

Write-TestResult `
    "User-Management.psm1 existe" `
    (Test-Path -LiteralPath $userManagementPath)

Write-TestResult `
    "User-Account-Actions.psm1 existe" `
    (Test-Path -LiteralPath $userActionsPath)


# ============================================================
# IMPORTAÇÃO
# ============================================================

$moduleImported = $false

try {
    Import-Module `
        $functionsPath `
        -Force `
        -ErrorAction Stop

    $interfaceModules = @(Get-Module | Where-Object { $_.Path -eq [System.IO.Path]::GetFullPath($functionsPath) })
    if ($interfaceModules.Count -ne 1) { throw "Esperada uma instância Interface V2; encontradas $($interfaceModules.Count)." }
    $interfaceModule = $interfaceModules[0]
    $entryPointModule = & $interfaceModule { (Get-Command Start-V2UserManagement -CommandType Function -ErrorAction Stop).Module }
    if ($entryPointModule -ne $interfaceModule) { throw 'A função pública não resolve para a instância Interface V2 esperada.' }
    $moduleImported = $true
}
catch {
    $moduleImported = $false
}

Write-TestResult `
    "Interface V2 importa sem erro" `
    $moduleImported


# ============================================================
# FUNÇÕES
# ============================================================

$expectedFunctions = @(
    "Write-V2Header",
    "Pause-V2",
    "Show-V2DevelopmentMessage",
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

foreach ($functionName in $expectedFunctions) {

    $command = Get-Command `
        $functionName `
        -ErrorAction SilentlyContinue

    Write-TestResult `
        "Função '$functionName' disponível" `
        ($null -ne $command)
}


# ============================================================
# CONTEÚDO DO LAUNCHER
# ============================================================

$launcherContent = ""

try {
    $launcherContent = Get-Content `
        -LiteralPath $launcherPath `
        -Raw `
        -ErrorAction Stop
}
catch {
    $launcherContent = ""
}

Write-TestResult `
    "Launcher referencia Interface-V2-Functions.psm1" `
    ($launcherContent -match "Interface-V2-Functions\.psm1")

Write-TestResult `
    "Launcher chama Start-V2Interface" `
    ($launcherContent -match "Start-V2Interface")


# ============================================================
# CONTEÚDO DO MÓDULO
# ============================================================

$moduleContent = ""

try {
    $moduleContent = Get-Content `
        -LiteralPath $functionsPath `
        -Raw `
        -ErrorAction Stop
}
catch {
    $moduleContent = ""
}


# ============================================================
# MENU PRINCIPAL
# ============================================================

Write-TestResult `
    "Menu contém Users" `
    ($moduleContent -match "Users")

Write-TestResult `
    "Menu contém Accounts" `
    ($moduleContent -match "Accounts")

Write-TestResult `
    "Menu contém Groups" `
    ($moduleContent -match "Groups")

Write-TestResult `
    "Menu contém Computers" `
    ($moduleContent -match "Computers")

Write-TestResult `
    "Menu contém Policies" `
    ($moduleContent -match "Policies")

Write-TestResult `
    "Menu contém Reports" `
    ($moduleContent -match "Reports")

Write-TestResult `
    "Menu contém Settings" `
    ($moduleContent -match "Settings")

Write-TestResult `
    "Menu contém Exit" `
    ($moduleContent -match "Exit")


# ============================================================
# COMPUTER MANAGEMENT
# ============================================================

Write-TestResult `
    "Computer Management é integrado" `
    ($moduleContent -match "Computer-Management\.psm1")

Write-TestResult `
    "Get-ComputerManagementSummary é utilizado" `
    ($moduleContent -match "Get-ComputerManagementSummary")

Write-TestResult `
    "Hostname é solicitado ao operador" `
    ($moduleContent -match 'Read-Host "  Hostname"')

Write-TestResult `
    "Modo simulação de computador é apresentado" `
    ($moduleContent -match "SimulationMode")

Write-TestResult `
    "Erros da consulta de computador são tratados" `
    ($moduleContent -match "ErrorCount")

Write-TestResult `
    "Consulta inicial do Computer Management inicia em SimulationMode" `
    ($moduleContent -match '\$nextMode\s*=\s*"Simulation"')

Write-TestResult `
    "Coleta real exige confirmação digitada por execução" `
    ($moduleContent -match 'COLETAR REAL' -and $moduleContent -match '\$confirmation\s+-ceq\s+"COLETAR REAL"')

Write-TestResult `
    "Recusa na Interface cria retorno Success falso e Cancelled verdadeiro" `
    ($moduleContent -match '(?s)if \(\$nextMode -eq "Cancelled"\).*?Status = "Cancelled".*?Cancelled = \$true; Success = \$false')

Write-TestResult `
    "Autorização real é limpa após uma consulta" `
    ($moduleContent -match '(?s)autorização vale somente para esta chamada.*?\$nextMode\s*=\s*"Simulation"')

# Exercita o fluxo real da função com todos os pontos de entrada externos
# substituídos dentro do escopo do módulo. Nenhum módulo/host/rede é acessado.
$interfaceRuntimeSafe = $false
$interfaceCapturedCalls = @()
if ($null -ne $interfaceModule) {
    try {
        $interfaceCapturedCalls = & $interfaceModule {
            $script:V2TestInputQueue = @("PC-FIXTURE", "1", "P", "1", "R", "COLETAR REAL", "1", "S", "0")
            $script:V2TestCapturedCalls = @()
            $script:V2TestHeaders = @()
            Set-Item Function:\script:Test-Path { $true } -Force
            Set-Item Function:\script:Import-Module { } -Force
            Set-Item Function:\script:Read-Host {
                param([string]$Prompt)
                $answer = $script:V2TestInputQueue[0]
                $script:V2TestInputQueue = @($script:V2TestInputQueue | Select-Object -Skip 1)
                return $answer
            } -Force
            Set-Item Function:\script:Write-V2Header {
                param([string]$Title, [string]$Subtitle)
                $script:V2TestHeaders += $Subtitle
            } -Force
            Set-Item Function:\script:Pause-V2 { } -Force
            Set-Item Function:\script:Show-V2ComputerSummary { } -Force
            Set-Item Function:\script:Show-V2ComputerDetails { } -Force
            Set-Item Function:\script:Start-Sleep { } -Force
            Set-Item Function:\script:Get-ComputerManagementSummary {
                [CmdletBinding()]
                param([string]$Hostname, [switch]$SimulationMode, [switch]$Preview, [switch]$AllowRealOperation)
                $script:V2TestCapturedCalls += @(@{
                    Hostname = $Hostname
                    SimulationMode = [bool]$SimulationMode
                    Preview = [bool]$Preview
                    AllowRealOperation = [bool]$AllowRealOperation
                })
                [PSCustomObject]@{
                    Hostname = $Hostname; Status = "Simulated"; ADFound = $null; Reachable = $null
                    OperatingSystem = $null; Model = $null; MemoryGB = $null; Processor = $null
                    BitLockerStatus = "NotCollected"; ErrorCount = 0; SimulationMode = [bool]$SimulationMode
                    Preview = [bool]$Preview; Mode = if ($AllowRealOperation) { "Real" } elseif ($Preview) { "Preview" } else { "Simulation" }
                    Cancelled = $false; Success = $true; IsSimulated = [bool]$SimulationMode
                }
            } -Force
            Start-V2ComputerManagement
            return ,$script:V2TestCapturedCalls
        }
        $interfaceRuntimeSafe = $true
    }
    catch {
        $interfaceRuntimeSafe = $false
    }
}

Write-TestResult "Harness da Interface executou somente com stubs" $interfaceRuntimeSafe
Write-TestResult "Interface encaminhou a consulta inicial como SimulationMode" ($interfaceCapturedCalls.Count -ge 4 -and $interfaceCapturedCalls[0].SimulationMode -and -not $interfaceCapturedCalls[0].AllowRealOperation)
Write-TestResult "Interface encaminhou Preview sem autorização real" ($interfaceCapturedCalls.Count -ge 4 -and $interfaceCapturedCalls[1].Preview -and -not $interfaceCapturedCalls[1].AllowRealOperation)
Write-TestResult "Interface encaminhou autorização real somente após escolha e confirmação" ($interfaceCapturedCalls.Count -ge 4 -and $interfaceCapturedCalls[2].AllowRealOperation -and -not $interfaceCapturedCalls[1].AllowRealOperation)
Write-TestResult "Interface voltou à simulação após consulta real" ($interfaceCapturedCalls.Count -ge 4 -and $interfaceCapturedCalls[3].SimulationMode -and -not $interfaceCapturedCalls[3].AllowRealOperation)

$declinedAuthorizationCalls = @()
$declinedAuthorizationPresentedCancellation = $false
if ($interfaceRuntimeSafe) {
    $declinedRun = & $interfaceModule {
        $script:V2TestInputQueue = @("PC-FIXTURE", "1", "R", "NAO", "1", "S", "0")
        $script:V2TestCapturedCalls = @()
        $script:V2TestHeaders = @()
        Start-V2ComputerManagement
        [PSCustomObject]@{ Calls = @($script:V2TestCapturedCalls); Headers = @($script:V2TestHeaders) }
    }
    $declinedAuthorizationCalls = @($declinedRun.Calls)
    $declinedAuthorizationPresentedCancellation = $declinedRun.Headers -contains "Coleta cancelada"
}
Write-TestResult "Recusa de autorização real é apresentada como cancelamento" $declinedAuthorizationPresentedCancellation
Write-TestResult "Recusa de autorização não chama Management/Core naquela consulta" ($declinedAuthorizationCalls.Count -eq 2 -and @($declinedAuthorizationCalls | Where-Object { $_.AllowRealOperation -or $_.Preview }).Count -eq 0)

# Verify the real pure state formatter used by the UI. It has no I/O boundary.
$computerDisplayCases = @{}
if ($null -ne $interfaceModule) {
    $computerDisplayCases = & $interfaceModule {
        $base = @{
            Hostname="PC-FIXTURE"; Status="Preview"; ADFound=$null; Reachable=$null
            OperatingSystem=$null; Model=$null; MemoryGB=$null; Processor=$null
            BitLockerStatus="NotCollected"; ErrorCount=0; SimulationMode=$false
            Preview=$true; Mode="Preview"; Cancelled=$false; IsSimulated=$false
            CollectionStatus="Preview"; ADQueryStatus="NotQueried"; ConnectivityStatus="NotQueried"
        }
        $makeDisplayCase = {
            param([hashtable]$Changes)
            $values = @{}
            foreach ($key in $base.Keys) { $values[$key] = $base[$key] }
            foreach ($key in $Changes.Keys) { $values[$key] = $Changes[$key] }
            return [PSCustomObject]$values
        }
        $cases = @{
            Preview = [PSCustomObject]$base
            Simulation = (& $makeDisplayCase @{ Status="Simulated"; SimulationMode=$true; Preview=$false; Mode="Simulation"; IsSimulated=$true; CollectionStatus="Simulation" })
            Found = (& $makeDisplayCase @{ Status="Online"; Preview=$false; Mode="Real"; CollectionStatus="Complete"; ADQueryStatus="Found"; ADFound=$true; ConnectivityStatus="Responded"; Reachable=$true })
            NotFound = (& $makeDisplayCase @{ Status="Unavailable"; Preview=$false; Mode="Real"; CollectionStatus="Complete"; ADQueryStatus="NotFound"; ADFound=$false; ConnectivityStatus="NoResponse"; Reachable=$false })
            ErrorPartial = (& $makeDisplayCase @{ Status="Unknown"; Preview=$false; Mode="Real"; CollectionStatus="Partial"; ErrorCount=1; ADQueryStatus="Error"; ConnectivityStatus="Error" })
            Unknown = (& $makeDisplayCase @{ Status="Unknown"; Preview=$false; Mode="Real"; CollectionStatus="Complete"; ADQueryStatus="UnexpectedState"; ConnectivityStatus="UnexpectedState"; ADFound=$false; Reachable=$false })
        }
        $output = @{}
        foreach ($name in $cases.Keys) { $output[$name] = Resolve-V2ComputerSummaryState -Summary $cases[$name] }
        return $output
    }
}
Write-TestResult "Preview é pré-visualização sem mensagem de simulação" ($computerDisplayCases.Preview.ModeMessage -match "Pré-visualização")
Write-TestResult "Simulation identifica claramente dados fictícios" ($computerDisplayCases.Simulation.ModeMessage -match "Dados demonstrativos fictícios")
Write-TestResult "Found exige estado explícito e resposta confirmada" ($computerDisplayCases.Found.ADMessage -eq "Sim" -and $computerDisplayCases.Found.ConnectivityMessage -eq "Sim")
Write-TestResult "NotFound só é apresentado após estado explícito" ($computerDisplayCases.NotFound.ADMessage -eq "Não" -and $computerDisplayCases.NotFound.ConnectivityMessage -eq "Sem resposta confirmada")
Write-TestResult "Erro de AD e coleta parcial são diferenciados" ($computerDisplayCases.ErrorPartial.ADMessage -eq "Erro na consulta" -and $computerDisplayCases.ErrorPartial.CollectionMessage -match "Coleta parcial")
Write-TestResult "Estado desconhecido não usa boolean false como NotFound ou offline" ($computerDisplayCases.Unknown.ADMessage -eq "Estado desconhecido" -and $computerDisplayCases.Unknown.ConnectivityMessage -eq "Estado desconhecido")


# ============================================================
# USER MANAGEMENT
# ============================================================

Write-TestResult `
    "User Management é integrado" `
    ($moduleContent -match "User-Management\.psm1")

Write-TestResult `
    "Get-UserManagement é utilizado" `
    ($moduleContent -match "Get-UserManagement")

Write-TestResult `
    "SamAccountName é solicitado ao operador" `
    ($moduleContent -match 'Read-Host "  SamAccountName"')

Write-TestResult `
    "Resumo de usuário é apresentado" `
    ($moduleContent -match "Show-V2UserSummary")

Write-TestResult `
    "Detalhes de usuário são apresentados" `
    ($moduleContent -match "Show-V2UserDetails")

Write-TestResult `
    "Modo simulação de usuário é apresentado" `
    ($moduleContent -match "MODO SIMULAÇÃO: ATIVO")

Write-TestResult `
    "Erros da consulta de usuário são tratados" `
    ($moduleContent -match "Usuário não encontrado")


# ============================================================
# USER ACCOUNT ACTIONS - INTEGRAÇÃO
# ============================================================

Write-TestResult `
    "User Account Actions é integrado" `
    ($moduleContent -match "User-Account-Actions\.psm1")


# ============================================================
# UNLOCK
# ============================================================

Write-TestResult `
    "Start-V2UserUnlockAccount existe" `
    ($moduleContent -match "function Start-V2UserUnlockAccount")

Write-TestResult `
    "Get-UserUnlockPreview é utilizado" `
    ($moduleContent -match "Get-UserUnlockPreview")

Write-TestResult `
    "Invoke-UserUnlockAccount é utilizado" `
    ($moduleContent -match "Invoke-UserUnlockAccount")

Write-TestResult `
    "Ação de desbloqueio exige confirmação" `
    ($moduleContent -match 'Confirma a execução\? \[S/N\]')

Write-TestResult `
    "Execução usa -Execute" `
    ($moduleContent -match "Invoke-UserUnlockAccount[\s\S]*-Execute")

Write-TestResult `
    "Modo simulação de desbloqueio é apresentado" `
    ($moduleContent -match "DESBLOQUEIO SIMULADO COM SUCESSO")

Write-TestResult `
    "Execução real apresenta resultado" `
    ($moduleContent -match "CONTA DESBLOQUEADA COM SUCESSO")

Write-TestResult `
    "Cancelamento da ação é tratado" `
    ($moduleContent -match "Ação cancelada pelo operador")

Write-TestResult `
    "Estado LockedOut é apresentado no preview" `
    ($moduleContent -match "CurrentState")

Write-TestResult `
    "Estado Unlocked é apresentado no preview" `
    ($moduleContent -match "TargetState")

Write-TestResult `
    "Menu do usuário contém desbloqueio" `
    ($moduleContent -match "2\. Desbloquear conta")


# ============================================================
# ENABLE
# ============================================================

Write-TestResult `
    "Start-V2UserEnableAccount existe" `
    ($moduleContent -match "function Start-V2UserEnableAccount")

Write-TestResult `
    "Get-UserEnablePreview é utilizado" `
    ($moduleContent -match "Get-UserEnablePreview")

Write-TestResult `
    "Invoke-UserEnableAccount é utilizado" `
    ($moduleContent -match "Invoke-UserEnableAccount")

Write-TestResult `
    "Mensagem de ativação simulada existe" `
    ($moduleContent -match "ATIVAÇÃO SIMULADA COM SUCESSO")

Write-TestResult `
    "Mensagem de ativação real existe" `
    ($moduleContent -match "CONTA ATIVADA COM SUCESSO")

Write-TestResult `
    "Menu contém ativação de conta" `
    ($moduleContent -match "3\. Ativar conta")


# ============================================================
# DISABLE
# ============================================================

Write-TestResult `
    "Start-V2UserDisableAccount existe" `
    ($moduleContent -match "function Start-V2UserDisableAccount")

Write-TestResult `
    "Get-UserDisablePreview é utilizado" `
    ($moduleContent -match "Get-UserDisablePreview")

Write-TestResult `
    "Invoke-UserDisableAccount é utilizado" `
    ($moduleContent -match "Invoke-UserDisableAccount")

Write-TestResult `
    "Mensagem de desativação simulada existe" `
    ($moduleContent -match "DESATIVAÇÃO SIMULADA COM SUCESSO")

Write-TestResult `
    "Mensagem de desativação real existe" `
    ($moduleContent -match "CONTA DESATIVADA COM SUCESSO")

Write-TestResult `
    "Menu contém desativação de conta" `
    ($moduleContent -match "4\. Desativar conta")


# ============================================================
# FORCE PASSWORD CHANGE
# ============================================================

Write-TestResult `
    "Start-V2UserForcePasswordChange existe" `
    ($moduleContent -match "function Start-V2UserForcePasswordChange")

Write-TestResult `
    "Get-UserForcePasswordChangePreview é utilizado" `
    ($moduleContent -match "Get-UserForcePasswordChangePreview")

Write-TestResult `
    "Invoke-UserForcePasswordChange é utilizado" `
    ($moduleContent -match "Invoke-UserForcePasswordChange")

Write-TestResult `
    "Mensagem de troca de senha simulada existe" `
    ($moduleContent -match "TROCA DE SENHA SIMULADA COM SUCESSO")

Write-TestResult `
    "Mensagem de troca de senha real existe" `
    ($moduleContent -match "TROCA DE SENHA OBRIGATÓRIA CONFIGURADA COM SUCESSO")

Write-TestResult `
    "Menu contém força de troca de senha" `
    ($moduleContent -match "5\. Forçar troca de senha no próximo logon")


# ============================================================
# MENU DO USUÁRIO
# ============================================================

Write-TestResult `
    "Menu contém nova consulta" `
    ($moduleContent -match "6\. Nova consulta")

Write-TestResult `
    "Menu do usuário mantém opção Voltar" `
    ($moduleContent -match "0\. Voltar")

Write-TestResult `
    "Simulation possui DisabledSamAccountNames" `
    ($moduleContent -match "DisabledSamAccountNames")

Write-TestResult `
    "Simulation possui PasswordChangeAtLogonSamAccountNames" `
    ($moduleContent -match "PasswordChangeAtLogonSamAccountNames")


# ============================================================
# POLICIES - GPO MANAGEMENT
# ============================================================

Write-TestResult `
    "Start-V2PolicyManagement existe" `
    ($moduleContent -match 'function Start-V2PolicyManagement')

Write-TestResult `
    "Policies importa o módulo GPO" `
    ($moduleContent -match '07-GPO-Management.*GPO-Functions\.psm1')

Write-TestResult `
    "Policies carrega a configuração GPO" `
    ($moduleContent -match 'GPO-Configuration\.json')

Write-TestResult `
    "Policies bloqueia operação sem SimulationMode" `
    ($moduleContent -match 'SimulationMode -ne \$true')

Write-TestResult `
    "Policies oferece listagem de GPOs" `
    ($moduleContent -match '"ListGPOs"')

Write-TestResult `
    "Policies oferece consulta de GPO" `
    ($moduleContent -match '"CheckGPO"')

Write-TestResult `
    "Policies oferece consulta de vínculos" `
    ($moduleContent -match '"ListLinks"')

Write-TestResult `
    "Policies oferece criação simulada" `
    ($moduleContent -match '"CreateGPO"')

Write-TestResult `
    "Opção 5 chama Start-V2PolicyManagement" `
    ($moduleContent -match '"5"\s*\{\s*Start-V2PolicyManagement')

Write-TestResult `
    "Start-V2PolicyManagement está exportada" `
    ($moduleContent -match '"Start-V2PolicyManagement",')

# ============================================================
# ============================================================
# GROUP MANAGEMENT - INTERFACE V2
# ============================================================

Write-TestResult `
    "Start-V2GroupManagement existe" `
    ($moduleContent -match 'function Start-V2GroupManagement')

Write-TestResult `
    "Group Management referencia o módulo Core" `
    ($moduleContent -match '\.\.\\Core\\Group\\Management\\Group-Management\.psm1')

Write-TestResult `
    "Group Management verifica a existência do módulo Core" `
    ($moduleContent -match 'Group Management não encontrado')

Write-TestResult `
    "Group Management importa o módulo Core" `
    ($moduleContent -match 'Import-Module')

Write-TestResult `
    "Group Management carrega a configuração" `
    ($moduleContent -match 'Get-V2GroupConfiguration')

Write-TestResult `
    "Group Management consulta grupos" `
    ($moduleContent -match 'Get-GroupManagement\s+`')

Write-TestResult `
    "Group Management consulta membros" `
    ($moduleContent -match 'Get-GroupManagementMembers\s+`')

Write-TestResult `
    "Inclusão utiliza preview" `
    ($moduleContent -match 'Get-GroupManagementPreview\s+`(?s).*?-Action "AddMember"')

Write-TestResult `
    "Remoção utiliza preview" `
    ($moduleContent -match 'Get-GroupManagementPreview\s+`(?s).*?-Action "RemoveMember"')

Write-TestResult `
    "Inclusão chama Invoke-GroupAddMember" `
    ($moduleContent -match 'Invoke-GroupAddMember\s+`')

Write-TestResult `
    "Remoção chama Invoke-GroupRemoveMember" `
    ($moduleContent -match 'Invoke-GroupRemoveMember\s+`')

Write-TestResult `
    "Inclusão utiliza confirmação" `
    ($moduleContent -match '(?s)function Start-V2GroupAddMember.*?Read-Host.*?Invoke-GroupAddMember')

Write-TestResult `
    "Remoção utiliza confirmação" `
    ($moduleContent -match '(?s)function Start-V2GroupRemoveMember.*?Read-Host.*?Invoke-GroupRemoveMember')

Write-TestResult `
    "Inclusão utiliza -Execute" `
    ($moduleContent -match '(?s)Invoke-GroupAddMember\s+`.*?-Execute')

Write-TestResult `
    "Remoção utiliza -Execute" `
    ($moduleContent -match '(?s)Invoke-GroupRemoveMember\s+`.*?-Execute')

Write-TestResult `
    "Consulta do grupo é atualizada após ações" `
    ($moduleContent -match '(?s)Start-V2GroupManagement.*?Start-V2GroupAddMember.*?Get-GroupManagement.*?Start-V2GroupRemoveMember.*?Get-GroupManagement')

Write-TestResult `
    "Opção 3 do menu chama Start-V2GroupManagement" `
    ($moduleContent -match '"3"\s*\{\s*Start-V2GroupManagement')

Write-TestResult `
    "Start-V2GroupManagement está exportada" `
    ($moduleContent -match '"Start-V2GroupManagement",')
# PADRÃO DE SEGURANÇA
# ============================================================

Write-TestResult `
    "Interface não contém senha em texto" `
    ($moduleContent -notmatch '(?i)\bpassword\s*[:=]\s*["''][^"'']+["'']')

Write-TestResult `
    "Interface não contém Credential em configuração" `
    ($moduleContent -notmatch '(?i)\bCredential\s*[:=]')


# ============================================================
$authorizationContract = & $interfaceModule {
    $script:AuthorizationQueue = @('AUTORIZAR LEITURA', 'AUTORIZAR ALTERAÇÃO', 'NAO')
    Set-Item Function:\script:Read-Host {
        param([string]$Prompt)
        $answer = $script:AuthorizationQueue[0]
        $script:AuthorizationQueue = @($script:AuthorizationQueue | Select-Object -Skip 1)
        return $answer
    } -Force
    [PSCustomObject]@{
        ReadAccepted = Request-V2OneTimeAuthorization -Kind Read -Target 'fixture'
        WriteAccepted = Request-V2OneTimeAuthorization -Kind Write -Target 'fixture'
        DeclineAccepted = Request-V2OneTimeAuthorization -Kind Write -Target 'fixture'
    }
}
Write-TestResult "Interface exige frases distintas para leitura e escrita" ($authorizationContract.ReadAccepted -and $authorizationContract.WriteAccepted)
Write-TestResult "Autorização recusada não é reutilizada" (-not $authorizationContract.DeclineAccepted)
Write-TestResult "Interface encaminha AllowRealRead e AllowRealWrite explicitamente" ($moduleContent -match '-AllowRealRead' -and $moduleContent -match '-AllowRealWrite')
Write-TestResult "Interface não usa AllowRealOperation como autorização de escrita User/Group" ($moduleContent -notmatch 'Invoke-User(?:Unlock|Enable|Disable|ForcePasswordChange)Account\s+`(?s:.*?)AllowRealOperation' -and $moduleContent -notmatch 'Invoke-Group(?:Add|Remove)Member\s+`(?s:.*?)AllowRealOperation')

$userAuthorizationFlow = & $interfaceModule {
    $script:InputQueue = @('AUTORIZAR LEITURA','S','AUTORIZAR ALTERAÇÃO')
    $script:Captured = @{}
    Set-Item Function:\script:Read-Host { param([string]$Prompt); $v=$script:InputQueue[0]; $script:InputQueue=@($script:InputQueue | Select-Object -Skip 1); $v } -Force
    Set-Item Function:\script:Pause-V2 { } -Force
    Set-Item Function:\script:Test-Path { $true } -Force
    Set-Item Function:\script:Import-Module { } -Force
    Set-Item Function:\script:Write-V2Header { } -Force
    Set-Item Function:\script:Get-UserUnlockPreview { param([string]$SamAccountName,[PSCustomObject]$Configuration,[switch]$AllowRealRead); $script:Captured.PreviewRead=[bool]$AllowRealRead; [PSCustomObject]@{Success=$true;SamAccountName=$SamAccountName;SimulationMode=$false;CanExecute=$true;Preview=[PSCustomObject]@{Description='fixture';CurrentState='Locked';TargetState='Unlocked'}} } -Force
    Set-Item Function:\script:Invoke-UserUnlockAccount { param([string]$SamAccountName,[PSCustomObject]$Configuration,[switch]$Execute,[switch]$AllowRealRead,[switch]$AllowRealWrite); $script:Captured.InvokeRead=[bool]$AllowRealRead; $script:Captured.InvokeWrite=[bool]$AllowRealWrite; [PSCustomObject]@{Success=$true;Status='Executed';Executed=$true;Changed=$true;Audit=$null} } -Force
    Set-Item Function:\script:Show-V2ExecutionResult { } -Force
    Start-V2UserUnlockAccount -SamAccountName 'fixture.user' -Configuration ([PSCustomObject]@{SimulationMode=$false})
    return $script:Captured
}
Write-TestResult "User Interface encaminha autorizações separadas de uma operação" ($userAuthorizationFlow.PreviewRead -and $userAuthorizationFlow.InvokeRead -and $userAuthorizationFlow.InvokeWrite)

$userDeclinedWriteFlow = & $interfaceModule {
    $script:InputQueue = @('AUTORIZAR LEITURA','S','NO')
    $script:Captured = @{ Invoked=$false }
    Set-Item Function:\script:Read-Host { param([string]$Prompt); $v=$script:InputQueue[0]; $script:InputQueue=@($script:InputQueue | Select-Object -Skip 1); $v } -Force
    Set-Item Function:\script:Invoke-UserUnlockAccount { $script:Captured.Invoked=$true } -Force
    Start-V2UserUnlockAccount -SamAccountName 'fixture.user' -Configuration ([PSCustomObject]@{SimulationMode=$false})
    return $script:Captured
}
Write-TestResult "Recusa User write impede chamada e não reutiliza autorização" (-not $userDeclinedWriteFlow.Invoked)

$groupAuthorizationFlow = & $interfaceModule {
    $script:InputQueue = @('fixture.user','AUTORIZAR LEITURA','S','AUTORIZAR ALTERAÇÃO')
    $script:Captured = @{}
    Set-Item Function:\script:Read-Host { param([string]$Prompt); $v=$script:InputQueue[0]; $script:InputQueue=@($script:InputQueue | Select-Object -Skip 1); $v } -Force
    Set-Item Function:\script:Pause-V2 { } -Force
    Set-Item Function:\script:Write-V2Header { } -Force
    Set-Item Function:\script:Get-GroupManagementPreview { param([string]$Action,[string]$GroupName,[string]$SamAccountName,[object]$Configuration,[switch]$AllowRealRead); $script:Captured.PreviewRead=[bool]$AllowRealRead; [PSCustomObject]@{Success=$true;SimulationMode=$false;Data=[PSCustomObject]@{GroupName=$GroupName;SamAccountName=$SamAccountName;CurrentState='NotMember';TargetState='Member';CanExecute=$true}} } -Force
    Set-Item Function:\script:Invoke-GroupAddMember { param([string]$GroupName,[string]$SamAccountName,[object]$Configuration,[switch]$Execute,[switch]$AllowRealRead,[switch]$AllowRealWrite); $script:Captured.InvokeRead=[bool]$AllowRealRead; $script:Captured.InvokeWrite=[bool]$AllowRealWrite; [PSCustomObject]@{Success=$true;Status='Simulated';Data=$null} } -Force
    Start-V2GroupAddMember -GroupName 'fixture.group' -Configuration ([PSCustomObject]@{SimulationMode=$false})
    return $script:Captured
}
Write-TestResult "Group Interface encaminha leitura e escrita em chamadas distintas" ($groupAuthorizationFlow.PreviewRead -and $groupAuthorizationFlow.InvokeRead -and $groupAuthorizationFlow.InvokeWrite)

$groupQueryMessages = & $interfaceModule {
    @{
        NotFound = Get-V2GroupQueryMessage -Result ([PSCustomObject]@{ QueryStatus = 'NotFound'; SimulationMode = $false })
        Error = Get-V2GroupQueryMessage -Result ([PSCustomObject]@{ QueryStatus = 'Error'; SimulationMode = $false })
        NotQueried = Get-V2GroupQueryMessage -Result ([PSCustomObject]@{ QueryStatus = 'NotQueried'; SimulationMode = $false })
        Simulation = Get-V2GroupQueryMessage -Result ([PSCustomObject]@{ QueryStatus = 'Simulation'; SimulationMode = $true })
        Cancelled = Get-V2GroupQueryMessage -Result ([PSCustomObject]@{ Status = 'Cancelled'; Cancelled = $true; SimulationMode = $false })
    }
}
Write-TestResult "Group distingue NotFound de erro, consulta ausente, simulação e cancelamento" (
    $groupQueryMessages.NotFound -match 'consulta foi concluída' -and
    $groupQueryMessages.Error -match 'Erro durante a consulta' -and
    $groupQueryMessages.NotQueried -match 'Consulta não realizada' -and
    $groupQueryMessages.Simulation -match 'Dados demonstrativos' -and
    $groupQueryMessages.Cancelled -match 'cancelada'
)

$userManagementControllerFlow = & $interfaceModule {
    $script:V2ControllerInputQueue = @('fixture.user', 'R', 'CONSULTAR REAL', 'dc.fixture.invalid', '')
    $script:V2ControllerCaptured = @()
    Set-Item Function:\script:Test-Path { $true } -Force
    Set-Item Function:\script:Import-Module { } -Force
    Set-Item Function:\script:Read-Host {
        param([string]$Prompt)
        $answer = $script:V2ControllerInputQueue[0]
        $script:V2ControllerInputQueue = @($script:V2ControllerInputQueue | Select-Object -Skip 1)
        return $answer
    } -Force
    Set-Item Function:\script:Pause-V2 { } -Force
    Set-Item Function:\script:Write-V2Header { } -Force
    Set-Item Function:\script:Get-UserManagement {
        param([string]$SamAccountName, [PSCustomObject]$Configuration, [switch]$AllowRealRead)
        $script:V2ControllerCaptured += [PSCustomObject]@{
            DomainController = $Configuration.DomainController
            SimulationMode = $Configuration.SimulationMode
            AllowRealRead = [bool]$AllowRealRead
        }
        [PSCustomObject]@{ Success = $false; Errors = @('Fixture stops before display') }
    } -Force
    Start-V2UserManagement
    return ,$script:V2ControllerCaptured
}
Write-TestResult "User Management encaminha DomainController explícito e validado" (
    $userManagementControllerFlow.Count -eq 1 -and
    $userManagementControllerFlow[0].DomainController -eq 'dc.fixture.invalid' -and
    -not $userManagementControllerFlow[0].SimulationMode -and
    $userManagementControllerFlow[0].AllowRealRead
)

$emptyControllerCalls = & $interfaceModule {
    $script:V2ControllerInputQueue = @('fixture.user', 'R', 'CONSULTAR REAL', '   ', '')
    $script:V2ControllerCallCount = 0
    Set-Item Function:\script:Read-Host {
        param([string]$Prompt)
        $answer = $script:V2ControllerInputQueue[0]
        $script:V2ControllerInputQueue = @($script:V2ControllerInputQueue | Select-Object -Skip 1)
        return $answer
    } -Force
    Set-Item Function:\script:Get-UserManagement { $script:V2ControllerCallCount++; throw 'Management must not be called for an empty controller.' } -Force
    Start-V2UserManagement
    return $script:V2ControllerCallCount
}
Write-TestResult "DomainController vazio impede chamada ao User Management" ($emptyControllerCalls -eq 0)

# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RESULTADO DOS TESTES" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $($script:Passed + $script:Failed)"
Write-Host "PASS  : $script:Passed" -ForegroundColor Green
Write-Host "FAIL  : $script:Failed" -ForegroundColor $(if ($script:Failed -eq 0) { "Green" } else { "Red" })

Write-Host ""

if ($script:Failed -eq 0) {
    Write-Host "INTERFACE V2: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    Write-Output 'HARNESS_PASS:INTERFACE_V2_V1'
    exit 0
}
else {
    Write-Host "INTERFACE V2: EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}
