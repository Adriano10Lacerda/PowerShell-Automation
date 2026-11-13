Set-StrictMode -Version Latest

# Deliberately blocked interface for handle-relative file operations.
# The native implementation is not enabled until its Windows ABI, reparse
# handling, volume/FileId checks, and disposition-by-handle behavior have been
# independently compiled and tested. No path-based fallback is permitted.

function Stop-ConfinedWorkspaceHandlesBlocked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [object]$Target
    )

    $record = [System.Management.Automation.ErrorRecord]::new(
        [System.Security.SecurityException]::new(
            "BLOCKED: $Operation is unavailable until the handle-relative implementation is reviewed and validated."),
        'ConfinedWorkspaceHandles.NativeImplementationUnavailable',
        [System.Management.Automation.ErrorCategory]::SecurityError,
        $Target
    )
    $PSCmdlet.ThrowTerminatingError($record)
}

function Open-ConfinedWorkspaceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Lease,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Purpose,
        [Parameter(Mandatory)][string]$Path
    )

    # Validate the lease first. In the current build this always fails closed
    # because no trusted provider or lease-verification adapter is configured.
    Assert-ConfinedWorkspaceLease -Lease $Lease -Purpose $Purpose
    Stop-ConfinedWorkspaceHandlesBlocked -Operation 'Open-ConfinedWorkspaceFile' -Target $Path
}

function New-ConfinedWorkspaceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Lease,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Purpose,
        [Parameter(Mandatory)][string]$Path
    )

    Assert-ConfinedWorkspaceLease -Lease $Lease -Purpose $Purpose
    Stop-ConfinedWorkspaceHandlesBlocked -Operation 'New-ConfinedWorkspaceFile' -Target $Path
}

function Read-ConfinedWorkspaceFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Handle)

    Stop-ConfinedWorkspaceHandlesBlocked -Operation 'Read-ConfinedWorkspaceFile' -Target $Handle
}

function Write-ConfinedWorkspaceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Handle,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    Stop-ConfinedWorkspaceHandlesBlocked -Operation 'Write-ConfinedWorkspaceFile' -Target $Handle
}

function Remove-ConfinedWorkspaceFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Handle)

    # Never call File.Delete or any path-based fallback here.
    Stop-ConfinedWorkspaceHandlesBlocked -Operation 'Remove-ConfinedWorkspaceFile' -Target $Handle
}

function Close-ConfinedWorkspaceFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Handle)

    # No handles are issued by this blocked module, so it cannot own a valid
    # disposable wrapper to close. Do not invoke Dispose on caller-controlled
    # objects or mistake a PSCustomObject for an authorized handle.
    Stop-ConfinedWorkspaceHandlesBlocked -Operation 'Close-ConfinedWorkspaceFile' -Target $Handle
}

Export-ModuleMember -Function @(
    'Open-ConfinedWorkspaceFile',
    'New-ConfinedWorkspaceFile',
    'Read-ConfinedWorkspaceFile',
    'Write-ConfinedWorkspaceFile',
    'Remove-ConfinedWorkspaceFile',
    'Close-ConfinedWorkspaceFile'
)
