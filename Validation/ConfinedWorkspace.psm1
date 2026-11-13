Set-StrictMode -Version Latest

# The trusted provisioner creates and owns the lease. This module validates it
# without creating a directory, granting permissions, or selecting a fallback.
function Initialize-ConfinedWorkspaceNative {
    if ('PowerShellAutomation.ConfinedWorkspaceNative' -as [type]) { return }
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace PowerShellAutomation {
    public static class ConfinedWorkspaceNative {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileInfo {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string path, uint access, uint share,
            IntPtr security, uint creation, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle,
            StringBuilder path, uint length, uint flags);

        public static SafeFileHandle Open(string path) {
            // READ_ATTRIBUTES, share read/write, OPEN_EXISTING,
            // BACKUP_SEMANTICS | OPEN_REPARSE_POINT. Do not share deletion.
            var handle = CreateFileW(path, 0x80, 3, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
            if (handle.IsInvalid) {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error);
            }
            return handle;
        }

        public static string Identity(SafeFileHandle handle) {
            FileInfo info;
            if (!GetFileInformationByHandle(handle, out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if ((info.Attributes & 0x400) != 0 ||
                ((info.Attributes & 0x10) == 0 && info.Links != 1))
                throw new InvalidOperationException("Reparse points and multiply linked files are prohibited.");
            return info.Volume.ToString("X8") + ":" +
                info.IndexHigh.ToString("X8") + info.IndexLow.ToString("X8");
        }

        public static bool IsVolumeRoot(SafeFileHandle handle) {
            var path = new StringBuilder(128);
            uint length = GetFinalPathNameByHandleW(handle, path, (uint)path.Capacity, 1);
            if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            // With VOLUME_NAME_GUID a real volume root has no component after the GUID.
            return length < path.Capacity && System.Text.RegularExpressions.Regex.IsMatch(
                path.ToString(), @"^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\$");
        }
    }
}
'@
}

function Get-ConfinedCanonicalPath {
    param([string]$Path)

    if ($Path -cnotmatch '\A[A-Z]:\\' -or $Path.Substring(2) -match '[\x00-\x1f/:*?"<>|]') {
        throw 'BLOCKED: Expected an absolute local drive path.'
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath -cne $Path -or ($Path.Length -gt 3 -and $Path.EndsWith('\'))) {
        throw 'BLOCKED: The path is not canonical.'
    }
    if ($Path.Length -gt 3) {
        foreach ($segment in $Path.Substring(3).Split('\')) {
            if ($segment -match '[. ]$|~|\A(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[0-9¹²³]|LPT[0-9¹²³])(?:\.|$)') {
                throw 'BLOCKED: Unsupported path component.'
            }
        }
    }
    return $fullPath
}

function Get-ConfinedObjectIdentity {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Handle')][Microsoft.Win32.SafeHandles.SafeFileHandle]$Handle
    )

    try {
        Initialize-ConfinedWorkspaceNative
        if ($PSCmdlet.ParameterSetName -eq 'Handle') {
            return [PowerShellAutomation.ConfinedWorkspaceNative]::Identity($Handle)
        }
        $pathToOpen = Get-ConfinedCanonicalPath $Path
        $opened = [PowerShellAutomation.ConfinedWorkspaceNative]::Open($pathToOpen)
        try { return [PowerShellAutomation.ConfinedWorkspaceNative]::Identity($opened) }
        finally { $opened.Dispose() }
    } catch {
        throw "BLOCKED: Object identity unavailable. $($_.Exception.Message)"
    }
}

function Assert-ConfinedDirectoryAccess {
    param([string]$Path, [string]$OperatorSid, [switch]$Workspace)

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $sections = [Security.AccessControl.AccessControlSections]::Owner -bor
        [Security.AccessControl.AccessControlSections]::Access
    $sd = [Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorSddlForm($sections))
    $trusted = @($OperatorSid, 'S-1-5-18')
    if (!$Workspace) {
        # SYSTEM, local Administrators and TrustedInstaller are trusted OS principals.
        $trusted += 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    }
    if ($null -eq $sd.DiscretionaryAcl -or $sd.Owner.Value -cnotin $trusted) {
        throw 'BLOCKED: Directory owner or DACL is untrusted.'
    }
    if ($Workspace -and (!$acl.AreAccessRulesProtected -or $sd.Owner.Value -cne $OperatorSid -or
            $sd.DiscretionaryAcl.Count -ne 2)) {
        throw 'BLOCKED: Workspace DACL is not private and protected.'
    }
    $principals = @()
    foreach ($ace in $sd.DiscretionaryAcl) {
        if ($ace -isnot [Security.AccessControl.CommonAce] -or $ace.IsCallback -or
                $ace.AceType -cnotin @('AccessAllowed', 'AccessDenied')) {
            throw 'BLOCKED: Unsupported directory ACE.'
        }
        $sid = $ace.SecurityIdentifier.Value
        if ($Workspace) {
            # Exactly two explicit full-control ACEs, inheritable by all fixtures.
            if ($ace.AceType -ne [Security.AccessControl.AceType]::AccessAllowed -or
                    [int]$ace.AceFlags -ne 3 -or $sid -cnotin $trusted -or $ace.AccessMask -ne 0x1F01FF) {
                throw 'BLOCKED: Workspace grants unexpected access.'
            }
            $principals += $sid
        } elseif ($ace.AceType -eq [Security.AccessControl.AceType]::AccessAllowed -and
                !(($ace.AceFlags -band [Security.AccessControl.AceFlags]::InheritOnly)) -and
                $sid -cnotin $trusted -and ($ace.AccessMask -band 0x500D0156)) {
            # FILE_ADD_FILE/FILE_ADD_SUBDIRECTORY, DELETE_CHILD/DELETE,
            # WRITE_DAC/WRITE_OWNER, WRITE_ATTRIBUTES/WRITE_EA,
            # GENERIC_WRITE/GENERIC_ALL let a principal change or replace the path.
            throw 'BLOCKED: Directory or its existing children can be replaced by an untrusted principal.'
        }
    }
    if ($Workspace -and ($OperatorSid -cnotin $principals -or 'S-1-5-18' -cnotin $principals)) {
        throw 'BLOCKED: Workspace principals do not match the lease policy.'
    }
}

function Assert-ConfinedWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Identity
    )

    try {
        $canonical = Get-ConfinedCanonicalPath $Root
        if ($canonical.Length -le 3 -or $Identity -cnotmatch '\A[0-9A-F]{8}:[0-9A-F]{16}\z') {
            throw 'BLOCKED: A dedicated workspace and its provisioned identity are required.'
        }
        $current = $canonical.Substring(0, 3)
        $drive = [IO.DriveInfo]::new($current)
        if ($drive.DriveType -ne [IO.DriveType]::Fixed -or $drive.DriveFormat -cne 'NTFS') {
            throw 'BLOCKED: The workspace must be on a fixed NTFS volume.'
        }
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Initialize-ConfinedWorkspaceNative
        $volume = [PowerShellAutomation.ConfinedWorkspaceNative]::Open($current)
        try {
            if (![PowerShellAutomation.ConfinedWorkspaceNative]::IsVolumeRoot($volume)) {
                throw 'BLOCKED: Drive aliases are not supported.'
            }
            $null = [PowerShellAutomation.ConfinedWorkspaceNative]::Identity($volume)
            Assert-ConfinedDirectoryAccess $current $sid
        } finally { $volume.Dispose() }

        foreach ($segment in $canonical.Substring(3).Split('\')) {
            $current = [IO.Path]::Combine($current, $segment)
            if (!([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::Directory)) {
                throw 'BLOCKED: Workspace ancestor is not a directory.'
            }
            $observed = Get-ConfinedObjectIdentity -Path $current
            $isWorkspace = $current -ceq $canonical
            Assert-ConfinedDirectoryAccess $current $sid -Workspace:$isWorkspace
            if ($isWorkspace -and $observed -cne $Identity) {
                throw 'BLOCKED: Workspace identity does not match the provisioned lease.'
            }
        }
    } catch {
        if ($_.Exception.Message.StartsWith('BLOCKED:', [StringComparison]::Ordinal)) { throw }
        throw "BLOCKED: Workspace proof unavailable. $($_.Exception.Message)"
    }
}

function Resolve-ConfinedWorkspacePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$Path
    )

    Assert-ConfinedWorkspace -Root $Root -Identity $Identity
    $canonical = Get-ConfinedCanonicalPath $Path
    $prefix = $Root + '\'
    if (!$canonical.StartsWith($prefix, [StringComparison]::Ordinal)) {
        throw 'BLOCKED: The path is outside the approved workspace.'
    }
    $current = $Root
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    try {
        foreach ($segment in $canonical.Substring($prefix.Length).Split('\')) {
            $current = [IO.Path]::Combine($current, $segment)
            try { $attributes = [IO.File]::GetAttributes($current) }
            catch [IO.FileNotFoundException] {
                if ($current -ceq $canonical) { return $canonical }
                throw
            }
            $null = Get-ConfinedObjectIdentity -Path $current
            if ($attributes -band [IO.FileAttributes]::Directory) {
                Assert-ConfinedDirectoryAccess $current $sid
            } elseif ($current -cne $canonical) {
                throw 'BLOCKED: Intermediate component is not a directory.'
            }
        }
    } catch {
        if ($_.Exception.Message.StartsWith('BLOCKED:', [StringComparison]::Ordinal)) { throw }
        throw "BLOCKED: Path proof unavailable. $($_.Exception.Message)"
    }
    return $canonical
}

Export-ModuleMember -Function Assert-ConfinedWorkspace, Resolve-ConfinedWorkspacePath, Get-ConfinedObjectIdentity
