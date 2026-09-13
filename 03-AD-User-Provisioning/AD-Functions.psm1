# ============================================
# AD Functions
# ============================================

# ============================================
# Validar configuração do Active Directory
# ============================================

function Test-ADConfiguration {
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    # ========================================
    # Domain
    # ========================================

    if ([string]::IsNullOrWhiteSpace($Configuration.Domain)) {
        $Errors += "O campo 'Domain' não pode estar vazio."
    }

    # ========================================
    # Domain Controller
    # ========================================

    if (-not [string]::IsNullOrWhiteSpace($Configuration.DomainController)) {
        Write-Verbose "Domain Controller configurado: $($Configuration.DomainController)"
    }

    # ========================================
    # Target OU
    # ========================================

    if (-not [string]::IsNullOrWhiteSpace($Configuration.TargetOU)) {
        Write-Verbose "OU configurada: $($Configuration.TargetOU)"
    }

    # ========================================
    # SamAccountName
    # ========================================

    if ($null -eq $Configuration.SamAccountName) {
        $Errors += "A seção 'SamAccountName' não foi configurada."
    }
    else {

        if ($null -eq $Configuration.SamAccountName.Enabled) {
            $Errors += "O campo 'SamAccountName.Enabled' não foi configurado."
        }

        if ($null -eq $Configuration.SamAccountName.MaxLength) {
            $Errors += "O campo 'SamAccountName.MaxLength' não foi configurado."
        }
        elseif ([int]$Configuration.SamAccountName.MaxLength -le 0) {
            $Errors += "O valor 'SamAccountName.MaxLength' deve ser maior que zero."
        }

        if ($null -eq $Configuration.SamAccountName.RemoveAccents) {
            $Errors += "O campo 'SamAccountName.RemoveAccents' não foi configurado."
        }
    }

    # ========================================
    # Duplicate Handling
    # ========================================

    if ($null -eq $Configuration.DuplicateHandling) {
        $Errors += "A seção 'DuplicateHandling' não foi configurada."
    }
    else {

        if ($null -eq $Configuration.DuplicateHandling.Enabled) {
            $Errors += "O campo 'DuplicateHandling.Enabled' não foi configurado."
        }

        if ([string]::IsNullOrWhiteSpace(
            [string]$Configuration.DuplicateHandling.Strategy
        )) {
            $Errors += "O campo 'DuplicateHandling.Strategy' não pode estar vazio."
        }
        elseif ($Configuration.DuplicateHandling.Strategy -notin @("Increment")) {
            $Errors += "A estratégia de duplicidade '$($Configuration.DuplicateHandling.Strategy)' não é suportada."
        }
    }

    # ========================================
    # Long Name Policy
    # ========================================

    if ($null -eq $Configuration.LongNamePolicy) {
        $Errors += "A seção 'LongNamePolicy' não foi configurada."
    }
    else {

        if ($null -eq $Configuration.LongNamePolicy.Enabled) {
            $Errors += "O campo 'LongNamePolicy.Enabled' não foi configurado."
        }

        if ([string]::IsNullOrWhiteSpace(
            [string]$Configuration.LongNamePolicy.Strategy
        )) {
            $Errors += "O campo 'LongNamePolicy.Strategy' não pode estar vazio."
        }
        elseif ($Configuration.LongNamePolicy.Strategy -notin @(
            "Manual",
            "Truncate"
        )) {
            $Errors += "A estratégia de nome longo '$($Configuration.LongNamePolicy.Strategy)' não é suportada."
        }
    }

        # ========================================
    # User Validation
    # ========================================

    if ($null -eq $Configuration.UserValidation) {

        $Errors += "A seção 'UserValidation' não foi configurada."
    }
    else {

        # FirstName

        if ($null -eq $Configuration.UserValidation.FirstName) {

            $Errors += "A seção 'UserValidation.FirstName' não foi configurada."
        }
        else {

            if ($null -eq $Configuration.UserValidation.FirstName.MinLength) {

                $Errors += "O campo 'UserValidation.FirstName.MinLength' não foi configurado."
            }
            elseif ([int]$Configuration.UserValidation.FirstName.MinLength -le 0) {

                $Errors += "O valor 'UserValidation.FirstName.MinLength' deve ser maior que zero."
            }
        }

        # LastName

        if ($null -eq $Configuration.UserValidation.LastName) {

            $Errors += "A seção 'UserValidation.LastName' não foi configurada."
        }
        else {

            if ($null -eq $Configuration.UserValidation.LastName.MinLength) {

                $Errors += "O campo 'UserValidation.LastName.MinLength' não foi configurado."
            }
            elseif ([int]$Configuration.UserValidation.LastName.MinLength -le 0) {

                $Errors += "O valor 'UserValidation.LastName.MinLength' deve ser maior que zero."
            }
        }
    }

    # ========================================
    # Simulation
    # ========================================

    if ($Configuration.OfflineSimulation -eq $true) {

        if ($null -eq $Configuration.Simulation) {
            $Errors += "A seção 'Simulation' deve ser configurada quando 'OfflineSimulation' está habilitado."
        }
        else {

            if ($null -eq $Configuration.Simulation.ExistingSamAccountNames) {
                $Errors += "O campo 'Simulation.ExistingSamAccountNames' não foi configurado."
            }
        }
    }

    # ========================================
    # User Types
    # ========================================

    if ($null -eq $Configuration.UserTypes) {

        $Errors += "A seção 'UserTypes' não foi configurada."
    }
    else {

        $UserTypeProperties = @(
            $Configuration.UserTypes.PSObject.Properties
        )

        if ($UserTypeProperties.Count -eq 0) {

            $Errors += "A seção 'UserTypes' deve possuir pelo menos um tipo de usuário."
        }
        else {

            foreach ($UserTypeProperty in $UserTypeProperties) {

                $UserTypeName = $UserTypeProperty.Name
                $UserTypeConfiguration = $UserTypeProperty.Value

                if ($null -eq $UserTypeConfiguration) {
                    $Errors += "A configuração do tipo de usuário '$UserTypeName' está vazia."
                    continue
                }

                if ([string]::IsNullOrWhiteSpace(
                    [string]$UserTypeConfiguration.Description
                )) {
                    $Errors += "O campo 'Description' do tipo '$UserTypeName' não pode estar vazio."
                }

                if ([string]::IsNullOrWhiteSpace(
                    [string]$UserTypeConfiguration.Format
                )) {
                    $Errors += "O campo 'Format' do tipo '$UserTypeName' não pode estar vazio."
                }
                elseif ($UserTypeConfiguration.Format -notin @(
                    "FirstName.LastName",
                    "LastName.FirstName",
                    "FirstNameLastName",
                    "LastNameFirstName",
                    "FirstInitial.LastName"
                )) {
                    $Errors += "O formato '$($UserTypeConfiguration.Format)' do tipo '$UserTypeName' não é suportado."
                }

                if ($null -eq $UserTypeConfiguration.Suffix) {
                    $Errors += "O campo 'Suffix' do tipo '$UserTypeName' não foi configurado."
                }
            }
        }
    }

    # ========================================
    # Resultado
    # ========================================

    if ($Errors.Count -gt 0) {

        throw (
            "A configuração do Active Directory contém erros:" +
            "`n" +
            ($Errors | ForEach-Object { "- $_" } | Out-String).TrimEnd()
        )
    }

    return $true
}


# ============================================
# Verificar existência de usuário no AD
# ============================================

function Test-ADUserExists {
    param (
        [Parameter(Mandatory)]
        [string]$SamAccountName
    )

    try {

        $User = Get-ADUser `
            -Identity $SamAccountName `
            -ErrorAction Stop

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


# ============================================
# Validar dados do usuário
# ============================================

function Test-ADUserProvisioning {
    param (
        [Parameter(Mandatory)]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [string]$LastName,

        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    # ========================================
    # Primeiro nome
    # ========================================

    if ([string]::IsNullOrWhiteSpace($FirstName)) {

        $Errors += "O primeiro nome não pode estar vazio."
    }
    else {

        $FirstNameMinLength = [int]$Configuration.UserValidation.FirstName.MinLength

        if ($FirstName.Trim().Length -lt $FirstNameMinLength) {

            $Errors += "O primeiro nome deve possuir pelo menos $FirstNameMinLength caracteres."
        }
    }

    # ========================================
    # Sobrenome
    # ========================================

    if ([string]::IsNullOrWhiteSpace($LastName)) {

        $Errors += "O sobrenome não pode estar vazio."
    }
    else {

        $LastNameMinLength = [int]$Configuration.UserValidation.LastName.MinLength

        if ($LastName.Trim().Length -lt $LastNameMinLength) {

            $Errors += "O sobrenome deve possuir pelo menos $LastNameMinLength caracteres."
        }
    }

    # ========================================
    # SamAccountName
    # ========================================

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {

        $Errors += "O SamAccountName não pode estar vazio."
    }
    else {

        $MaxLength = [int]$Configuration.SamAccountName.MaxLength

        if ($MaxLength -le 0) {

            $Errors += "O valor 'SamAccountName.MaxLength' deve ser maior que zero."
        }

        if ($SamAccountName.Length -gt $MaxLength) {

            $Errors += "O SamAccountName não pode possuir mais de $MaxLength caracteres."
        }

        if ($SamAccountName -notmatch '^[a-zA-Z0-9._-]+$') {

            $Errors += "O SamAccountName contém caracteres inválidos. Use apenas letras, números, ponto, hífen ou underline."
        }
    }

    # ========================================
    # Resultado
    # ========================================

    if ($Errors.Count -gt 0) {

        throw ($Errors -join "`n")
    }

    return $true
}


# ============================================
# Gerar SamAccountName
# ============================================

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

        if (
            $Configuration.LongNamePolicy.Enabled -and
            $Configuration.LongNamePolicy.Strategy -eq "Manual"
        ) {
            throw "O SamAccountName gerado '$BaseSamAccountName$Suffix' ultrapassa o limite configurado de $MaxLength caracteres. É necessário informar manualmente um SamAccountName válido."
        }

        $BaseSamAccountName = $BaseSamAccountName.Substring(
            0,
            $AvailableLength
        )
    }

    return "$BaseSamAccountName$Suffix"
}


# ============================================
# Gerar SamAccountName único
# ============================================

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

    # Verifica se o nome original está disponível.
    if ($ExistingSamAccountNames -notcontains $SamAccountName) {

        if ($Configuration.OfflineSimulation) {
            return $SamAccountName
        }

        try {

            $User = Get-ADUser `
                -Identity $SamAccountName `
                -ErrorAction Stop

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

    # Nome original ocupado.
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

        # Simulação offline.
        if ($Configuration.OfflineSimulation) {

            if ($ExistingSamAccountNames -notcontains $Candidate) {
                return $Candidate
            }

            $Counter++
            continue
        }

        # Active Directory real.
        try {

            $User = Get-ADUser `
                -Identity $Candidate `
                -ErrorAction Stop

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


# ============================================
# Exportar funções
# ============================================

Export-ModuleMember -Function `
    Test-ADConfiguration, `
    Test-ADUserExists, `
    Test-ADUserProvisioning, `
    Get-ADSamAccountName, `
    Get-UniqueADSamAccountName