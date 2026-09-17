function Test-EntraConfiguration {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    # SimulationMode
    if ($null -eq $Configuration.SimulationMode) {
        $Errors += "A configuração 'SimulationMode' não foi definida."
    }

    # TenantId
    if ($Configuration.SimulationMode -eq $false) {
        if ([string]::IsNullOrWhiteSpace($Configuration.TenantId)) {
            $Errors += "O 'TenantId' é obrigatório quando o modo de simulação está desabilitado."
        }
    }

    # Domain
    if ($Configuration.SimulationMode -eq $false) {
        if ([string]::IsNullOrWhiteSpace($Configuration.Domain)) {
            $Errors += "O 'Domain' é obrigatório quando o modo de simulação está desabilitado."
        }
    }

    # UserPrincipalName
    if ($null -eq $Configuration.UserPrincipalName) {
        $Errors += "A seção 'UserPrincipalName' não foi definida."
    }
    else {

        if ($null -eq $Configuration.UserPrincipalName.Enabled) {
            $Errors += "A propriedade 'UserPrincipalName.Enabled' não foi definida."
        }

        if ($Configuration.UserPrincipalName.Enabled -eq $true) {

            if ([string]::IsNullOrWhiteSpace($Configuration.UserPrincipalName.Domain)) {
                $Errors += "O domínio do UserPrincipalName é obrigatório quando o UPN está habilitado."
            }
        }
    }

    # Resultado da validação
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

        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($Character) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark) {

            [void]$StringBuilder.Append($Character)
        }
    }

    $Result = $StringBuilder.ToString()

    # Substitui espaços por hífens
    $Result = $Result -replace '\s+', '-'

    # Remove caracteres que não sejam letras, números ou hífen
    $Result = $Result -replace '[^a-zA-Z0-9-]', ''

    # Remove hífens duplicados
    $Result = $Result -replace '-+', '-'

    # Remove hífens no início e no final
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

    # FirstName
    if ([string]::IsNullOrWhiteSpace($User.FirstName)) {
        $Errors += "O FirstName é obrigatório."
    }
    else {
        if ($User.FirstName.Length -lt 2) {
            $Errors += "O FirstName deve possuir pelo menos 2 caracteres."
        }
    }

    # LastName
    if ([string]::IsNullOrWhiteSpace($User.LastName)) {
        $Errors += "O LastName é obrigatório."
    }
    else {
        if ($User.LastName.Length -lt 2) {
            $Errors += "O LastName deve possuir pelo menos 2 caracteres."
        }
    }

    # UserPrincipalName
    if ($Configuration.UserPrincipalName.Enabled -eq $true) {

        if ([string]::IsNullOrWhiteSpace($User.UserPrincipalName)) {
            $Errors += "O UserPrincipalName é obrigatório quando o UPN está habilitado."
        }
        elseif ($User.UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            $Errors += "O UserPrincipalName possui um formato inválido."
        }
    }

    # Resultado da validação
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

    # Modo de simulação
    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Configuration.Simulation) {
            return $false
        }

        if ($Configuration.Simulation.ExistingUserPrincipalNames -contains $UserPrincipalName) {
            return $true
        }

        return $false
    }

    # Modo real
    if (-not (Get-Command Get-MgUser -ErrorAction SilentlyContinue)) {
        throw "O comando 'Get-MgUser' não está disponível. Instale o Microsoft.Graph.Users e autentique-se no Microsoft Graph."
    }

    # Verificar se existe um tenant Microsoft Entra
    try {

        $Organization = Invoke-MgGraphRequest `
            -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/organization" `
            -ErrorAction Stop

        if ($null -eq $Organization.value -or $Organization.value.Count -eq 0) {
            throw "Nenhuma organização Microsoft Entra foi encontrada."
        }
    }
    catch {

        $ErrorDetails = $_ | Out-String

        if ($ErrorDetails -match "MSA accounts" -or
            $ErrorDetails -match "not supported for MSA") {

            throw "A conta autenticada é uma Microsoft Account (MSA). O provisionamento requer uma conta corporativa ou escolar em um tenant Microsoft Entra ID."
        }

        throw "Não foi possível validar o tenant Microsoft Entra ID. Detalhes: $($_.Exception.Message)"
    }

    # Consultar usuário no Microsoft Entra ID
    try {

        $User = Get-MgUser `
            -UserId $UserPrincipalName `
            -ErrorAction Stop

        if ($null -eq $User) {
            return $false
        }

        return $true
    }
    catch {

        if ($_.Exception.Message -match "Resource .* does not exist" -or
            $_.Exception.Message -match "does not exist" -or
            $_.Exception.Message -match "Request_ResourceNotFound") {

            return $false
        }

        throw "Não foi possível verificar o usuário '$UserPrincipalName'. Detalhes: $($_.Exception.Message)"
    }
}

function New-EntraUserProvision {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$User,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    # Validação dos dados
    $null = Test-EntraUserProvisioning -User $User -Configuration $Configuration

    # Verificação de usuário existente
    if (Test-EntraUserExists `
        -UserPrincipalName $User.UserPrincipalName `
        -Configuration $Configuration) {

        throw "O usuário '$($User.UserPrincipalName)' já existe no Entra ID."
    }

    # Modo de simulação
    if ($Configuration.SimulationMode -eq $true) {

        return [PSCustomObject]@{
            Success             = $true
            Simulation          = $true
            UserPrincipalName   = $User.UserPrincipalName
            DisplayName         = $User.DisplayName
            MailNickname        = $User.MailNickname
            AccountEnabled      = $User.AccountEnabled
            Message             = "Usuário preparado para criação no Entra ID. Nenhuma alteração real foi realizada."
        }
    }

    # Modo real será implementado posteriormente
    throw "O modo real de provisionamento ainda não foi implementado."
}

function Test-EntraTenantConnection {

    try {

        $Organization = Invoke-MgGraphRequest `
            -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/organization" `
            -ErrorAction Stop

        if ($null -eq $Organization.value -or $Organization.value.Count -eq 0) {
            throw "Nenhuma organização Microsoft Entra foi encontrada."
        }

        return [PSCustomObject]@{
            Connected       = $true
            TenantId        = $Organization.value[0].id
            DisplayName     = $Organization.value[0].displayName
            VerifiedDomains = $Organization.value[0].verifiedDomains
            Message         = "Conexão com o Microsoft Entra ID validada com sucesso."
        }
    }
    catch {

        $ErrorDetails = $_ | Out-String

        if ($ErrorDetails -match "MSA accounts" -or
            $ErrorDetails -match "not supported for MSA") {

            throw "A conta autenticada é uma Microsoft Account (MSA). O provisionamento deste módulo requer uma conta corporativa ou escolar em um tenant Microsoft Entra ID."
        }

        if ($_.Exception.Message -match "BadRequest") {

            throw "Não foi possível consultar a organização Microsoft Entra ID. Verifique se a conta autenticada pertence a um tenant Microsoft Entra ID corporativo ou escolar."
        }

        throw "Não foi possível validar o tenant Microsoft Entra ID. Detalhes: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Test-EntraConfiguration, Test-EntraUserProvisioning, Test-EntraUserExists, New-EntraUserProvision, Test-EntraTenantConnection, ConvertTo-EntraIdentifier