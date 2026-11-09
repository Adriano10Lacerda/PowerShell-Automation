#Requires -Version 5.1
Set-StrictMode -Version Latest

function New-AdminAuthorizationFixture {
    [CmdletBinding()]
    param([string]$Operation = '', [switch]$Read, [switch]$Write, [switch]$Valid = $true)
    [pscustomobject]@{
        AllowRealRead = [bool]$Read; AllowRealWrite = [bool]$Write
        WriteAuthorizationValid = [bool]$Valid; AuthorizationOperation = $Operation
    }
}

function New-AdminUserFixture {
    [CmdletBinding()]
    param([string]$SamAccountName = 'fixture.user', [ValidateSet('Found','NotFound','Error')][string]$QueryStatus = 'Found', [string]$State = 'LockedOut')
    [pscustomobject]@{
        SamAccountName = $SamAccountName; Name = 'Synthetic User'; QueryStatus = $QueryStatus; State = $State
        Enabled = ($State -ne 'Disabled'); LockedOut = ($State -eq 'LockedOut'); PasswordChangeAtLogon = $false
        Error = if ($QueryStatus -eq 'Error') { 'Synthetic user query error.' } else { $null }
    }
}

function New-AdminGroupFixture {
    [CmdletBinding()]
    param([string]$GroupName = 'fixture.group', [ValidateSet('Found','NotFound','Error')][string]$QueryStatus = 'Found', [string[]]$Members = @('fixture.member'))
    [pscustomobject]@{ GroupName = $GroupName; QueryStatus = $QueryStatus; Members = @($Members); Error = if ($QueryStatus -eq 'Error') { 'Synthetic group query error.' } else { $null } }
}

function New-AdminOperationFixture {
    [CmdletBinding()]
    param([ValidateSet('Found','NotFound','Error')][string]$QueryStatus = 'Found', [switch]$MutationFails, [switch]$AuditFails)
    [pscustomobject]@{
        QueryStatus = $QueryStatus
        MutationFails = [bool]$MutationFails
        AuditFails = [bool]$AuditFails
        Error = if ($QueryStatus -eq 'Error') { 'Synthetic directory query error.' } else { $null }
        CreatedUtc = [DateTime]::UtcNow
    }
}

function New-AdminScenarioFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Operation, [Parameter(Mandatory)][string]$ScenarioName)
    [pscustomobject]@{
        Operation = $Operation; ScenarioName = $ScenarioName
        ScenarioId = [guid]::NewGuid().ToString('N')
        ADModuleAvailable = $true
        DomainQueryStatus = 'Found'
        User = New-AdminUserFixture
        Group = New-AdminGroupFixture
        Authorization = New-AdminAuthorizationFixture -Operation $Operation
        OperationResult = New-AdminOperationFixture
    }
}

Export-ModuleMember -Function @('New-AdminAuthorizationFixture','New-AdminUserFixture','New-AdminGroupFixture','New-AdminOperationFixture','New-AdminScenarioFixture')
