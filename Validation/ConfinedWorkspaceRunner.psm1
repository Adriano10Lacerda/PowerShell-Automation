Set-StrictMode -Version Latest

# This module is an interface boundary, not a provisioner. A caller-supplied
# path, file identity, environment variable, or ordinary PowerShell object is
# not proof that a trusted disposable-platform provider created the workspace.
# No provider trust key or platform attestation is provisioned in this build.
$script:TrustedProviderSpkiBase64 = ''
$script:TrustedProviderId = ''

function New-ConfinedWorkspaceBlockedError {
    param(
        [Parameter(Mandatory)][string]$ErrorId,
        [Parameter(Mandatory)][string]$Message,
        [object]$Target
    )

    $exception = [System.Security.SecurityException]::new("BLOCKED: $Message")
    [System.Management.Automation.ErrorRecord]::new(
        $exception,
        $ErrorId,
        [System.Management.Automation.ErrorCategory]::SecurityError,
        $Target
    )
}

function Assert-ConfinedWorkspaceProviderReady {
    [CmdletBinding()]
    if ([string]::IsNullOrWhiteSpace($script:TrustedProviderId) -or
        [string]::IsNullOrWhiteSpace($script:TrustedProviderSpkiBase64)) {
        $record = New-ConfinedWorkspaceBlockedError -ErrorId 'ConfinedWorkspaceRunner.ProviderUnavailable' -Message 'Não há provider confiável de plataforma descartável configurado; nenhuma raiz pode ser emitida ou aceita.' -Target $null
        $PSCmdlet.ThrowTerminatingError($record)
    }

    # Deliberately no implicit provider discovery, TEMP fallback, environment
    # variable, or caller-controlled callback. The reviewed provider adapter
    # and its pinned key must be implemented in a later, separately reviewed
    # change before this module can return a lease.
    $record = New-ConfinedWorkspaceBlockedError -ErrorId 'ConfinedWorkspaceRunner.ProviderAdapterMissing' -Message 'O pin existe, mas o adapter autenticado do provider ainda não foi implementado.' -Target $null
    $PSCmdlet.ThrowTerminatingError($record)
}

function Get-ConfinedWorkspaceLease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Configuration')]
        [string]$Purpose,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Root,

        [Parameter(Mandatory)]
        [ValidatePattern('\A[0-9A-F]{8}:[0-9A-F]{16}\z')]
        [string]$Identity
    )

    # Root and Identity are correlation inputs only. They never authorize
    # provisioning or acceptance on their own.
    Assert-ConfinedWorkspaceProviderReady
}

function Assert-ConfinedWorkspaceLease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Lease,

        [Parameter(Mandatory)]
        [ValidateSet('Configuration')]
        [string]$Purpose
    )

    # A forged PSCustomObject must not be accepted as a lease. The missing
    # provider trust anchor blocks before any Root/Identity values are used.
    Assert-ConfinedWorkspaceProviderReady

    # Future adapter contract, reachable only after provider authentication:
    # Root, Identity, LeaseId, OwnerSid, Purpose, Status, ExpiresUtc,
    # ProviderId, and detached Signature over canonical lease bytes.
    # Validation must then call Assert-ConfinedWorkspace from the shared
    # validator and compare the current process SID with the provisioned
    # dedicated execution SID. It must not create, repair, or clean the root.
    $record = New-ConfinedWorkspaceBlockedError -ErrorId 'ConfinedWorkspaceRunner.LeaseRejected' -Message 'Lease não autenticada; a fronteira permanece bloqueada.' -Target $Lease
    $PSCmdlet.ThrowTerminatingError($record)
}

Export-ModuleMember -Function Get-ConfinedWorkspaceLease, Assert-ConfinedWorkspaceLease
