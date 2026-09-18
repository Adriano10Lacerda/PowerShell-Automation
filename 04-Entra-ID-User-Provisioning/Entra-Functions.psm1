function Test-EntraConfiguration {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    # ============================================================
    # SimulationMode
    # ============================================================

    if ($null -eq $Configuration.SimulationMode) {

        $Errors += "A configuração 'SimulationMode' não foi definida."
    }

    # ============================================================
    # TenantId
    # ============================================================

    if ($Configuration.SimulationMode -eq $false) {

        if ([string]::IsNullOrWhiteSpace($Configuration.TenantId)) {

            $Errors += "O 'TenantId' é obrigatório quando o modo de simulação está desabilitado."
        }
        elseif ($Configuration.TenantId -notmatch '^[0-9a-fA-F-]{36}$') {

            $Errors += "O 'TenantId' não possui um formato válido."
        }
    }

    # ============================================================
    # Domain
    # ============================================================

    if ($Configuration.SimulationMode -eq $false) {

        if ([string]::IsNullOrWhiteSpace($Configuration.Domain)) {

            $Errors += "O 'Domain' é obrigatório quando o modo de simulação está desabilitado."
        }
    }

    # ============================================================
    # UserPrincipalName
    # ============================================================

    if ($null -eq $Configuration.UserPrincipalName) {

        $Errors += "A seção 'UserPrincipalName' não foi definida."
    }
    else {

        if ($null -eq $Configuration.UserPrincipalName.Enabled) {

            $Errors += "A propriedade 'UserPrincipalName.Enabled' não foi definida."
        }

        if ($Configuration.UserPrincipalName.Enabled -eq $true) {

            if (
                [string]::IsNullOrWhiteSpace(
                    $Configuration.UserPrincipalName.Domain
                )
            ) {

                $Errors += "O domínio do UserPrincipalName é obrigatório quando o UPN está habilitado."
            }
        }
    }

    # ============================================================
    # Simulation
    # ============================================================

    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Configuration.Simulation) {

            $Errors += "A seção 'Simulation' não foi definida."
        }
        elseif ($null -eq $Configuration.Simulation.ExistingUserPrincipalNames) {

            $Errors += "A propriedade 'Simulation.ExistingUserPrincipalNames' não foi definida."
        }
    }

    # ============================================================
    # Resultado
    # ============================================================

    if ($Errors.Count -gt 0) {

        throw ($Errors -join "`n")
    }

    return $true
}


function ConvertTo-EntraIdentifier {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $NormalizedText = $Text.Normalize(
        [System.Text.NormalizationForm]::FormD
    )

    $StringBuilder = New-Object System.Text.StringBuilder

    foreach ($Character in $NormalizedText.ToCharArray()) {

        if (
            [Globalization.CharUnicodeInfo]::GetUnicodeCategory($Character) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark
        ) {

            [void]$StringBuilder.Append($Character)
        }
    }

    $Result = $StringBuilder.ToString()

    # Espaços para hífens
    $Result = $Result -replace '\s+', '-'

    # Remove caracteres inválidos
    $Result = $Result -replace '[^a-zA-Z0-9-]', ''

    # Remove hífens duplicados
    $Result = $Result -replace '-+', '-'

    # Remove hífens das extremidades
    $Result = $Result.Trim('-')

    return $Result.ToLower()
}


function Test-EntraUserProvisioning {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$User,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    # ============================================================
    # FirstName
    # ============================================================

    if ([string]::IsNullOrWhiteSpace($User.FirstName)) {

        $Errors += "O FirstName é obrigatório."
    }
    elseif ($User.FirstName.Length -lt 2) {

        $Errors += "O FirstName deve possuir pelo menos 2 caracteres."
    }

    # ============================================================
    # LastName
    # ============================================================

    if ([string]::IsNullOrWhiteSpace($User.LastName)) {

        $Errors += "O LastName é obrigatório."
    }
    elseif ($User.LastName.Length -lt 2) {

        $Errors += "O LastName deve possuir pelo menos 2 caracteres."
    }

    # ============================================================
    # UserPrincipalName
    # ============================================================

    if ($Configuration.UserPrincipalName.Enabled -eq $true) {

        if ([string]::IsNullOrWhiteSpace($User.UserPrincipalName)) {

            $Errors += "O UserPrincipalName é obrigatório quando o UPN está habilitado."
        }
        elseif (
            $User.UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        ) {

            $Errors += "O UserPrincipalName possui um formato inválido."
        }
    }

    # ============================================================
    # MailNickname
    # ============================================================

    if ([string]::IsNullOrWhiteSpace($User.MailNickname)) {

        $Errors += "O MailNickname é obrigatório."
    }

    # ============================================================
    # Resultado
    # ============================================================

    if ($Errors.Count -gt 0) {

        throw ($Errors -join "`n")
    }

    return $true
}


function Test-EntraUserExists {

    param (
        [Parameter(Mandatory = $true)]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    # ============================================================
    # Simulation Mode
    # ============================================================

    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Configuration.Simulation) {

            return $false
        }

        if (
            $Configuration.Simulation.ExistingUserPrincipalNames -contains
            $UserPrincipalName
        ) {

            return $true
        }

        return $false
    }

    # ============================================================
    # Verificar módulo
    # ============================================================

    if (-not (Get-Command Get-MgUser -ErrorAction SilentlyContinue)) {

        throw @"
O comando 'Get-MgUser' não está disponível.

Instale o módulo Microsoft.Graph.Users antes de continuar.
"@
    }

    # ============================================================
    # Consultar usuário
    # ============================================================

    try {

        $User = Get-MgUser `
            -UserId $UserPrincipalName `
            -ErrorAction Stop

        return ($null -ne $User)
    }
    catch {

        $Message = $_.Exception.Message

        if (
            $Message -match "Resource .* does not exist" -or
            $Message -match "does not exist" -or
            $Message -match "Request_ResourceNotFound"
        ) {

            return $false
        }

        throw @"
Não foi possível verificar se o usuário '$UserPrincipalName' existe.

Detalhes: $Message
"@
    }
}


function Test-EntraTenantConnection {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    # ============================================================
    # Verificar Microsoft Graph
    # ============================================================

    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {

        throw @"
O comando 'Get-MgContext' não está disponível.

Instale o Microsoft Graph PowerShell SDK.
"@
    }

    # ============================================================
    # Obter contexto
    # ============================================================

    $Context = Get-MgContext

    if ($null -eq $Context) {

        throw @"
Nenhuma sessão Microsoft Graph está autenticada.

Execute Connect-MgGraph antes de utilizar o modo real.
"@
    }

    # ============================================================
    # Validar TenantId
    # ============================================================

    if ([string]::IsNullOrWhiteSpace($Context.TenantId)) {

        throw @"
A sessão Microsoft Graph não possui TenantId.

Conecte-se explicitamente ao tenant Microsoft Entra ID.
"@
    }

    if (
        -not [string]::IsNullOrWhiteSpace($Configuration.TenantId) -and
        $Context.TenantId -ne $Configuration.TenantId
    ) {

        throw @"
O tenant autenticado não corresponde ao TenantId configurado.

Tenant autenticado : $($Context.TenantId)
Tenant configurado  : $($Configuration.TenantId)
"@
    }

    return [PSCustomObject]@{
        Connected = $true
        TenantId  = $Context.TenantId
        Account   = $Context.Account
        AuthType  = $Context.AuthType
        Scopes    = $Context.Scopes
        Message   = "Sessão Microsoft Graph validada com sucesso."
    }
}


function Test-EntraUserPostProvisioning {

    param (
        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ExpectedUser
    )

    # ============================================================
    # Verificar comando
    # ============================================================

    if (-not (Get-Command Get-MgUser -ErrorAction SilentlyContinue)) {

        throw @"
O comando 'Get-MgUser' não está disponível.

Instale o módulo Microsoft.Graph.Users antes de continuar.
"@
    }

    # ============================================================
    # Consultar usuário criado
    # ============================================================

    try {

        $CreatedUser = Get-MgUser `
            -UserId $UserId `
            -Property Id,DisplayName,UserPrincipalName `
            -ErrorAction Stop
    }
    catch {

        throw @"
O usuário foi criado, mas não foi possível realizar a pós-validação.

ID: $UserId

Detalhes: $($_.Exception.Message)
"@
    }

    # ============================================================
    # Validar ID
    # ============================================================

    if ([string]::IsNullOrWhiteSpace($CreatedUser.Id)) {

        throw "A pós-validação falhou: o usuário retornado não possui Id."
    }

    if ($CreatedUser.Id -ne $UserId) {

        throw @"
A pós-validação falhou: o Id retornado pelo Microsoft Graph
não corresponde ao Id informado após a criação.

Id esperado : $UserId
Id retornado : $($CreatedUser.Id)
"@
    }

    # ============================================================
    # Validar DisplayName
    # ============================================================

    if ($CreatedUser.DisplayName -ne $ExpectedUser.DisplayName) {

        throw @"
A pós-validação falhou: o DisplayName não corresponde ao esperado.

Esperado : $($ExpectedUser.DisplayName)
Retornado: $($CreatedUser.DisplayName)
"@
    }

    # ============================================================
    # Validar UserPrincipalName
    # ============================================================

    if (
        $CreatedUser.UserPrincipalName.ToLower() -ne
        $ExpectedUser.UserPrincipalName.ToLower()
    ) {

        throw @"
A pós-validação falhou: o UserPrincipalName não corresponde ao esperado.

Esperado : $($ExpectedUser.UserPrincipalName)
Retornado: $($CreatedUser.UserPrincipalName)
"@
    }

    # ============================================================
    # Resultado
    # ============================================================

    return [PSCustomObject]@{
        Success           = $true
        Id                = $CreatedUser.Id
        DisplayName       = $CreatedUser.DisplayName
        UserPrincipalName = $CreatedUser.UserPrincipalName
        Message           = "Pós-validação do usuário concluída com sucesso."
    }
}


function New-EntraUserProvision {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$User,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    # ============================================================
    # Validar dados
    # ============================================================

    $null = Test-EntraUserProvisioning `
        -User $User `
        -Configuration $Configuration

    # ============================================================
    # Verificar duplicidade
    # ============================================================

    if (
        Test-EntraUserExists `
            -UserPrincipalName $User.UserPrincipalName `
            -Configuration $Configuration
    ) {

        throw "O usuário '$($User.UserPrincipalName)' já existe no Entra ID."
    }

    # ============================================================
    # Simulation Mode
    # ============================================================

    if ($Configuration.SimulationMode -eq $true) {

        return [PSCustomObject]@{
            Success             = $true
            Simulation          = $true
            PostValidation      = $false
            UserPrincipalName   = $User.UserPrincipalName
            DisplayName         = $User.DisplayName
            MailNickname        = $User.MailNickname
            AccountEnabled      = $User.AccountEnabled
            Message             = "Usuário preparado para criação no Entra ID. Nenhuma alteração real foi realizada."
        }
    }

    # ============================================================
    # Validar sessão Graph
    # ============================================================

    $null = Test-EntraTenantConnection `
        -Configuration $Configuration

    # ============================================================
    # Solicitar senha
    # ============================================================

    Write-Host ""
    Write-Host "A senha inicial do usuário será solicitada." -ForegroundColor Yellow
    Write-Host "A senha não será armazenada pelo módulo." -ForegroundColor Yellow
    Write-Host ""

    $Password = Read-Host "Senha inicial" -AsSecureString

    if ($null -eq $Password) {

        throw "A senha inicial não foi informada."
    }

    # ============================================================
    # Converter SecureString temporariamente
    # ============================================================

    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)

    try {

        $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)

        if ([string]::IsNullOrWhiteSpace($PlainPassword)) {

            throw "A senha inicial não pode estar vazia."
        }

        # ========================================================
        # Corpo da requisição Microsoft Graph
        # ========================================================

        $Parameters = @{
            accountEnabled    = $true
            displayName       = $User.DisplayName
            mailNickname      = $User.MailNickname
            userPrincipalName = $User.UserPrincipalName

            passwordProfile = @{
                forceChangePasswordNextSignIn = $true
                password                      = $PlainPassword
            }
        }

        Write-Host ""
        Write-Host "Criando usuário no Microsoft Entra ID..." -ForegroundColor Cyan

        # ========================================================
        # Criar usuário
        # ========================================================

        $CreatedUser = New-MgUser `
            -BodyParameter $Parameters `
            -ErrorAction Stop

        if ($null -eq $CreatedUser) {

            throw "O Microsoft Graph não retornou o usuário criado."
        }

        if ([string]::IsNullOrWhiteSpace($CreatedUser.Id)) {

            throw "O Microsoft Graph não retornou o Id do usuário criado."
        }

        # ========================================================
        # Pós-validação
        # ========================================================

        Write-Host ""
        Write-Host "Executando pós-validação no Microsoft Graph..." -ForegroundColor Cyan

        $PostValidation = Test-EntraUserPostProvisioning `
            -UserId $CreatedUser.Id `
            -ExpectedUser $User

        # ========================================================
        # Resultado final
        # ========================================================

        return [PSCustomObject]@{
            Success           = $true
            Simulation        = $false
            PostValidation    = $PostValidation.Success
            Id                = $PostValidation.Id
            DisplayName       = $PostValidation.DisplayName
            UserPrincipalName = $PostValidation.UserPrincipalName
            MailNickname      = $User.MailNickname
            AccountEnabled    = $User.AccountEnabled
            Message           = "Usuário criado e validado com sucesso no Microsoft Entra ID."
        }
    }
    catch {

        throw @"
Não foi possível concluir o provisionamento do usuário '$($User.UserPrincipalName)' no Microsoft Entra ID.

Detalhes: $($_.Exception.Message)
"@
    }
    finally {

        if ($BSTR -ne [IntPtr]::Zero) {

            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }

        $PlainPassword = $null
        $Password = $null
    }
}


Export-ModuleMember -Function `
    Test-EntraConfiguration, `
    Test-EntraUserProvisioning, `
    Test-EntraUserExists, `
    New-EntraUserProvision, `
    Test-EntraTenantConnection, `
    Test-EntraUserPostProvisioning, `
    ConvertTo-EntraIdentifier