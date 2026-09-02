function Show-OSDCoreLicenseHelp {
	<#
	.SYNOPSIS
	Displays instructions for setting the Recast Core license for OSDCloud.

	.DESCRIPTION
	Provides a concise, step-by-step guide to download, install, and verify the
	Right Click Tools Community Edition license used by OSDeploy and OSDCloud.

	.PARAMETER LicensePath
	The directory path where .license2 files should be stored when not using
	a full Right Click Tools Community Edition installation.

	.EXAMPLE
	Show-OSDCoreLicenseHelp
	Displays setup steps for ProgramData\Recast Software\Licenses.

	.EXAMPLE
	Show-OSDCoreLicenseHelp -LicensePath 'D:\Licenses'
	Displays setup steps and checks a custom license directory.

	.LINK
	https://www.osdeploy.com/osdeploy-pc/community-registration

	.LINK
	https://portal.recastsoftware.com/

	.NOTES
	Author: David Segura - Recast Software
	2026-07-22 - Initial help block created
	2026-07-22 - Added OSDCloud Recast Core license setup guidance
	2026-08-26 - Updated Community License installation and verification guidance
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string]$LicensePath = (Join-Path -Path $env:ProgramData -ChildPath 'Recast Software\Licenses')
	)

	Write-Host -ForegroundColor DarkYellow "No usable .license2 license was found in $LicensePath"
	Write-Host ''
	Write-Host -ForegroundColor DarkCyan 'Recast Community License for OSD | OSDCloud | OSDeploy'
	Write-Host -ForegroundColor DarkGray 'Registration is optional, but some features require a valid Community License.'
	Write-Host -ForegroundColor DarkGray 'Follow these steps to download, install, and verify the license.'
	Write-Host ''

	Write-Host -ForegroundColor DarkYellow '1. Open the Recast Software Community Portal and create an account or sign in:'
	Write-Host '   https://portal.recastsoftware.com/'
	Write-Host ''

	Write-Host -ForegroundColor DarkYellow '2. Download the license ZIP for Right Click Tools Community Edition.'
	Write-Host '   Extract the ZIP and locate the file with the .license2 extension.'
	Write-Host ''

	Write-Host -ForegroundColor DarkYellow '3. Open PowerShell 7 as an administrator and copy the license file to:'
	Write-Host "   $LicensePath"
	Write-Host '   Keep the .license2 extension unchanged.'
	Write-Host ''
	Write-Host '   $LicenseFile = ''C:\Path\To\CommunityLicense.license2'''
	Write-Host "   New-Item -Path '$LicensePath' -ItemType Directory -Force | Out-Null"
	Write-Host "   Copy-Item -LiteralPath `$LicenseFile -Destination '$LicensePath' -Force"
	Write-Host ''

	Write-Host -ForegroundColor DarkYellow '4. Verify that OSDeploy can discover the license file:'
	Write-Host "   Get-ChildItem -Path '$LicensePath' -Filter '*.license2' -File"
	Write-Host ''
	Write-Host -ForegroundColor DarkGray 'Detailed instructions:'
	Write-Host '   https://www.osdeploy.com/osdeploy-pc/community-registration'
	Write-Host ''
}
