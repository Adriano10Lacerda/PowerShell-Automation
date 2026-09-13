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

function Get-ADSamAccountName {
    param (
        [Parameter(Mandatory)]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [string]$LastName,

        [Parameter(Mandatory)]
        [string]$UserType,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    if (-not $Configuration.SamAccountName.Enabled) {
        throw "A geração automática do SamAccountName está desabilitada na configuração."
    }

    if (-not $Configuration.UserTypes.$UserType) {
        throw "O tipo de usuário '$UserType' não está configurado."
    }

    $UserPolicy = $Configuration.UserTypes.$UserType

    $FirstNameClean = $FirstName.Trim()
    $LastNameClean = $LastName.Trim()

    # Usa somente o último sobrenome informado.
    $LastNameParts = $LastNameClean -split '\s+'
    $LastNameClean = $LastNameParts[-1]

    # Remove acentos quando configurado.
    if ($Configuration.SamAccountName.RemoveAccents) {
        $FirstNameClean = $FirstNameClean.Normalize(
            [Text.NormalizationForm]::FormD
        ) -replace '\p{Mn}', ''

        $LastNameClean = $LastNameClean.Normalize(
            [Text.NormalizationForm]::FormD
        ) -replace '\p{Mn}', ''
    }

    # Converte para minúsculas e remove caracteres inválidos.
    $FirstNameClean = $FirstNameClean.ToLower() -replace '[^a-z0-9]', ''
    $LastNameClean = $LastNameClean.ToLower() -replace '[^a-z0-9]', ''

    if ([string]::IsNullOrWhiteSpace($FirstNameClean)) {
        throw "Não foi possível gerar o SamAccountName: primeiro nome inválido."
    }

    if ([string]::IsNullOrWhiteSpace($LastNameClean)) {
        throw "Não foi possível gerar o SamAccountName: sobrenome inválido."
    }

    switch ($UserPolicy.Format) {

        "FirstName.LastName" {
            $BaseSamAccountName = "$FirstNameClean.$LastNameClean"
        }

        "LastName.FirstName" {
            $BaseSamAccountName = "$LastNameClean.$FirstNameClean"
        }

        "FirstNameLastName" {
            $BaseSamAccountName = "$FirstNameClean$LastNameClean"
        }

        "LastNameFirstName" {
            $BaseSamAccountName = "$LastNameClean$FirstNameClean"
        }

        "FirstInitial.LastName" {
            $BaseSamAccountName = "$($FirstNameClean.Substring(0,1)).$LastNameClean"
        }

        default {
            throw "Formato de SamAccountName '$($UserPolicy.Format)' não é suportado."
        }
    }

    $Suffix = [string]$UserPolicy.Suffix
    $MaxLength = [int]$Configuration.SamAccountName.MaxLength

    if ($Suffix.Length -ge $MaxLength) {
        throw "O sufixo '$Suffix' não pode ser utilizado porque excede o limite configurado de $MaxLength caracteres."
    }

    $AvailableLength = $MaxLength - $Suffix.Length

    if ($BaseSamAccountName.Length -gt $AvailableLength) {
        $BaseSamAccountName = $BaseSamAccountName.Substring(
            0,
            $AvailableLength
        )
    }

    return "$BaseSamAccountName$Suffix"
}

function Get-UniqueADSamAccountName {
    param (
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [string[]]$ExistingSamAccountNames = @()
    )

    if (-not $Configuration.DuplicateHandling.Enabled) {
        return $SamAccountName
    }

    if ($Configuration.DuplicateHandling.Strategy -ne "Increment") {
        throw "Estratégia de duplicidade '$($Configuration.DuplicateHandling.Strategy)' não é suportada."
    }

    $MaxLength = [int]$Configuration.SamAccountName.MaxLength

    if ($SamAccountName.Length -gt $MaxLength) {
        throw "O SamAccountName '$SamAccountName' já excede o limite configurado de $MaxLength caracteres."
    }

    # Identifica o sufixo configurado.
    $Suffix = ""

    foreach ($UserTypeProperty in $Configuration.UserTypes.PSObject.Properties) {

        $ConfiguredSuffix = [string]$UserTypeProperty.Value.Suffix

        if (
            -not [string]::IsNullOrWhiteSpace($ConfiguredSuffix) -and
            $SamAccountName.EndsWith($ConfiguredSuffix)
        ) {
            $Suffix = $ConfiguredSuffix
            break
        }
    }

    # Se houver sufixo, separa a base do sufixo.
    if ([string]::IsNullOrEmpty($Suffix)) {
        $BaseName = $SamAccountName
    }
    else {
        $BaseName = $SamAccountName.Substring(
            0,
            $SamAccountName.Length - $Suffix.Length
        )
    }

    # Primeiro verifica se o nome original está disponível.
    if ($ExistingSamAccountNames -notcontains $SamAccountName) {

        if ($Configuration.OfflineSimulation) {
            return $SamAccountName
        }

        try {
            $User = Get-ADUser -Identity $SamAccountName -ErrorAction Stop

            if ($null -eq $User) {
                return $SamAccountName
            }
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            return $SamAccountName
        }
        catch {
            throw "Não foi possível verificar a disponibilidade do SamAccountName '$SamAccountName'. Detalhes: $($_.Exception.Message)"
        }
    }

    # Nome original ocupado. Começa a procurar pelo próximo número.
    $Counter = 2

    while ($true) {

        $CounterText = [string]$Counter

        $AvailableBaseLength =
            $MaxLength -
            $Suffix.Length -
            $CounterText.Length

        if ($AvailableBaseLength -le 0) {
            throw "Não foi possível gerar um SamAccountName único dentro do limite de $MaxLength caracteres."
        }

        $AdjustedBaseName = $BaseName

        if ($AdjustedBaseName.Length -gt $AvailableBaseLength) {
            $AdjustedBaseName = $AdjustedBaseName.Substring(
                0,
                $AvailableBaseLength
            )
        }

        $Candidate = "$AdjustedBaseName$CounterText$Suffix"

        Write-Verbose "Verificando disponibilidade: $Candidate"

        # Simulação offline utilizando lista fornecida para teste.
        if ($Configuration.OfflineSimulation) {

            if ($ExistingSamAccountNames -notcontains $Candidate) {
                return $Candidate
            }

            $Counter++
            continue
        }

        # Consulta ao Active Directory real.
        try {
            $User = Get-ADUser -Identity $Candidate -ErrorAction Stop

            if ($null -eq $User) {
                return $Candidate
            }

            $Counter++
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            return $Candidate
        }
        catch {
            throw "Não foi possível verificar a disponibilidade do SamAccountName '$Candidate'. Detalhes: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Test-ADConfiguration, Test-ADUserExists, Test-ADUserProvisioning, Get-ADSamAccountName, Get-UniqueADSamAccountName
