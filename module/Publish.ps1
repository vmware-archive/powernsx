<#
PowerNSX Publishing Script
Nick Bradford
nbradford@vmware.com
07/2017

Because of the variety of ways of distributing and supporting both Core and
Desktop PowerShell as well as supportong both script based and PowerShell
gallery based installation with the same module, we need to have flexibility
in the way the manifest is built for various platforms.  This is pretty much
to do just with properly expressing the PowerCLI dependancies that PowerNSX has.

On top of that, the process of publishing updates to PowerShell Gallery and
PowerNSX versioning is now handled by it.

The intent is to have this script called by CI/CD when updates are PRs are
merged to PowerNSX.

See PowerNSX.psd1.README.md for instructions on this process and the
requirements for maintaining manifests now.

Maintainers are the only ones that should edit this script.

Copyright © 2015 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more details.

You should have received a copy of the General Public License version 2 along with this program.
If not, see https://www.gnu.org/licenses/gpl-2.0.html.

Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.
#>

# Requires -Version 3.0


param (
    [Parameter (Mandatory=$true)]
    #Required build number that is appended to the version (maj.min) string from include.ps1 to form the full version number.
    [int]$BuildNumber,
    [Parameter (Mandatory=$true)]
    #Required API key to upload to PowershellGallery.
    [string]$NugetAPIKey
)
##########################
##########################
# This script :
#   do sources include.ps1 and adds a build number to the version string from there.
#   Generates the platform specific manifests in the appropriate directories.
#   Copies the updated Manifests and module to the dist/ folder
#   Publishes the updated module to the PowerShell gallery
##########################

# Dot Source Include.ps1.  This file includes developer configurable variables
# such as FunctionsToExport and Version
. ./Include.ps1

#Append the build number on the version string
$ModuleVersion = $ModuleVersion + '.' + $BuildNumber.tostring().trim()

if ( -not ($ModuleVersion -as [version])) { throw "$ModuleVersion is not a valid version.  Check version and build number and try again."}
$Common.Add("ModuleVersion", $ModuleVersion)

#Get current working directory - required for writeAllLines method later.
$pwd = split-path $MyInvocation.MyCommand.Path

# The path the Installation script uses on Desktop
$DesktopPath = "$pwd/platform/desktop"
# The path the Installation script uses on Core
$CorePath = "$pwd/platform/core"
# The path this script uses for the Gallery distro upload
$GalleryPath = "$pwd/platform/gallery"

copy-item -Path "./PowerNSX.psm1" "$DesktopPath/PowerNSX/"
copy-item -Path "./PowerNSX.psm1" "$CorePath/PowerNSX/"
copy-item -Path "./PowerNSX.psm1" "$GalleryPath/PowerNSX/"

New-ModuleManifest -Path "$DesktopPath/PowerNSX/PowerNSX.psd1" -RequiredModules $DesktopRequiredModules -PowerShellVersion '3.0' @Common
#Convert to UTF8NoBOM
$content = Get-Content "$DesktopPath/PowerNSX/PowerNSX.psd1"
[System.IO.File]::WriteAllLines("$DesktopPath/PowerNSX/PowerNSX.psd1", $content)

New-ModuleManifest -Path "$CorePath/PowerNSX/PowerNSX.psd1" -RequiredModules $CoreRequiredModules -PowerShellVersion '3.0' @Common
#Convert to UTF8NoBOM
$content = Get-Content "$CorePath/PowerNSX/PowerNSX.psd1"
[System.IO.File]::WriteAllLines("$CorePath/PowerNSX/PowerNSX.psd1", $content)

New-ModuleManifest -Path "$GalleryPath/PowerNSX/PowerNSX.psd1" -RequiredModules $GalleryRequiredModules -PowerShellVersion '3.0' @Common
#Convert to UTF8NoBOM
$content = Get-Content "$GalleryPath/PowerNSX/PowerNSX.psd1"
[System.IO.File]::WriteAllLines("$GalleryPath/PowerNSX/PowerNSX.psd1", $content)

#Generate Help Doc
if ( Get-Module powernsx ) { remove-module powernsx }
Import-Module ./platform/desktop/PowerNSX/PowerNSX.psd1
../psDoc/src/psDoc.ps1 -moduleName PowerNSX -template ..\psDoc\src\out-html-template.ps1 -outputDir ..\doc\

Publish-Module -NuGetApiKey $NugetAPIKey -Path "$GalleryPath/PowerNSX"

write-host -ForegroundColor Yellow "Version $ModuleVersion is now published to the Powershell Gallery.  You MUST now push these updates back to the git repository."