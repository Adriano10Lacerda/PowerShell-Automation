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

Export-ModuleMember -Function Test-EntraConfiguration

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
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
        throw "O módulo Microsoft.Graph.Users não está instalado."
    }

    try {
        $User = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop
        return ($null -ne $User)
    }
    catch {
        if ($_.Exception.Message -match "Resource .* does not exist" -or
            $_.Exception.Message -match "does not exist") {
            return $false
        }

        throw
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
    Test-EntraUserProvisioning -User $User -Configuration $Configuration

    # Verificação de usuário existente
    if (Test-EntraUserExists -UserPrincipalName $User.UserPrincipalName -Configuration $Configuration) {
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
            JobTitle            = $User.JobTitle
            Department          = $User.Department
            AccountEnabled      = $User.AccountEnabled
            Message             = "Usuário preparado para criação no Entra ID. Nenhuma alteração real foi realizada."
        }
    }

    # Modo real será implementado posteriormente
    throw "O modo real de provisionamento ainda não foi implementado."
}

Export-ModuleMember -Function Test-EntraConfiguration, Test-EntraUserProvisioning, Test-EntraUserExists, New-EntraUserProvision