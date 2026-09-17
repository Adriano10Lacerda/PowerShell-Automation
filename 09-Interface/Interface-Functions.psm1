function Start-PasswordGenerator {

    $ScriptPath = Join-Path $PSScriptRoot "..\01-Password-Generator\Generate-Password.ps1"

    if (-not (Test-Path $ScriptPath)) {
        throw "Password Generator não encontrado: $ScriptPath"
    }

    & $ScriptPath
}


function Start-ADUserProvisioning {

    $ScriptPath = Join-Path $PSScriptRoot "..\03-AD-User-Provisioning\Provision-ADUser.ps1"

    if (-not (Test-Path $ScriptPath)) {
        throw "AD User Provisioning não encontrado: $ScriptPath"
    }

    & $ScriptPath
}


function Start-EntraUserProvisioning {

    $ScriptPath = Join-Path $PSScriptRoot "..\04-Entra-ID-User-Provisioning\Provision-EntraUser.ps1"

    if (-not (Test-Path $ScriptPath)) {
        throw "Entra ID User Provisioning não encontrado: $ScriptPath"
    }

    & $ScriptPath
}


function Start-ComputerInventory {

    $ScriptPath = Join-Path $PSScriptRoot "..\05-Computer-Inventory\Computer-Inventory.ps1"

    if (-not (Test-Path $ScriptPath)) {
        throw "Computer Inventory não encontrado: $ScriptPath"
    }

    & $ScriptPath
}


function Start-ADGroupManagement {

    $ScriptPath = Join-Path $PSScriptRoot "..\06-AD-Group-Management\AD-Group-Management.ps1"

    if (-not (Test-Path $ScriptPath)) {
        throw "AD Group Management não encontrado: $ScriptPath"
    }

    & $ScriptPath
}


function Start-GPOManagement {

    $ScriptPath = Join-Path $PSScriptRoot "..\07-GPO-Management\GPO-Management.ps1"

    if (-not (Test-Path $ScriptPath)) {
        throw "GPO Management não encontrado: $ScriptPath"
    }

    & $ScriptPath
}


function Start-Reporting {

    $ScriptPath = Join-Path $PSScriptRoot "..\08-Reporting\Reporting.ps1"

    if (-not (Test-Path $ScriptPath)) {
        throw "Reporting não encontrado: $ScriptPath"
    }

    & $ScriptPath
}


Export-ModuleMember -Function `
    Start-PasswordGenerator, `
    Start-ADUserProvisioning, `
    Start-EntraUserProvisioning, `
    Start-ComputerInventory, `
    Start-ADGroupManagement, `
    Start-GPOManagement, `
    Start-Reporting