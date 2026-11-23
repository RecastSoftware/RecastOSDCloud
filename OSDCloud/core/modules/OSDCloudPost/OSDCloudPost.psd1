@{
    RootModule           = 'OSDCloudPost.psm1'
    ModuleVersion        = '26.11.23'
    GUID                 = '16d3b337-81d9-44a9-9e7f-f5aedffb7cc9'
    Author               = 'David Segura'
    CompanyName          = 'Recast Software'
    Copyright            = '(c) 2026 Recast Software. All rights reserved.'
    Description          = 'Standalone OSDCloud post-deployment runtime for the Windows Setup PreOOBE technician window and SetupComplete scripts.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop')
    FunctionsToExport    = @('Invoke-OSDCloudPreOOBE', 'Invoke-OSDCloudSetupComplete')
    AliasesToExport      = @('OSDCloudPreOOBE')
    CmdletsToExport      = @()
    VariablesToExport    = @()
}
