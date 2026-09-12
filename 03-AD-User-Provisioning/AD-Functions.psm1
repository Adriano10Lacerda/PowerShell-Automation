function Test-ADConfiguration {
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    if ([string]::IsNullOrWhiteSpace($Configuration.Domain)) {
        $Errors += "O campo 'Domain' não pode estar vazio."
    }

    if (-not [string]::IsNullOrWhiteSpace($Configuration.DomainController)) {
        Write-Verbose "Domain Controller configurado: $($Configuration.DomainController)"
    }

    if (-not [string]::IsNullOrWhiteSpace($Configuration.TargetOU)) {
        Write-Verbose "OU configurada: $($Configuration.TargetOU)"
    }

    if ($Errors.Count -gt 0) {
        throw ($Errors -join "`n")
    }

    return $true
}


function Test-ADUserExists {
    param (
        [Parameter(Mandatory)]
        [string]$SamAccountName
    )

    try {
        $User = Get-ADUser -Identity $SamAccountName -ErrorAction Stop

        if ($null -ne $User) {
            return $true
        }

        return $false
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        return $false
    }
    catch {
        throw "Não foi possível consultar o Active Directory para verificar o usuário '$SamAccountName'. Detalhes: $($_.Exception.Message)"
    }
}


function Test-ADUserProvisioning {
    param (
        [Parameter(Mandatory)]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [string]$LastName,

        [Parameter(Mandatory)]
        [string]$SamAccountName
    )

    $Errors = @()

    if ([string]::IsNullOrWhiteSpace($FirstName)) {
        $Errors += "O primeiro nome não pode estar vazio."
    }

    if ([string]::IsNullOrWhiteSpace($LastName)) {
        $Errors += "O sobrenome não pode estar vazio."
    }

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        $Errors += "O SamAccountName não pode estar vazio."
    }

    if ($SamAccountName.Length -gt 20) {
        $Errors += "O SamAccountName não pode possuir mais de 20 caracteres."
    }

    if ($SamAccountName -notmatch '^[a-zA-Z0-9._-]+$') {
        $Errors += "O SamAccountName contém caracteres inválidos. Use apenas letras, números, ponto, hífen ou underline."
    }

    if ($Errors.Count -gt 0) {
        throw ($Errors -join "`n")
    }

    return $true
}


Export-ModuleMember -Function Test-ADConfiguration, Test-ADUserExists, Test-ADUserProvisioning
