<#
PowerNSX Module Manifest generation script.
Nick Bradford
nbradford@vmware.com
07/2017


This script is only required for developers working on PowerNSX that wish to
generate a manifest file to facilicate loading the PowerNSX module to test changes
etc.
Simply run to generate the manifest.

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

$wd = split-path $MyInvocation.MyCommand.Path
#Bring in the module generation variables
. $wd/Include.ps1

#Pre PoSH 5 new-modmanifest barfs if the following exists...We dont need it for dev work....
$common.Remove("ProjectURI")

#Create the manifest
if ( $PSVersionTable.PSEdition -eq "Core" ) {
    New-ModuleManifest -Path "$wd/PowerNSX.psd1" -RequiredModules $CoreRequiredModules -PowerShellVersion '3.0' @Common
}
else {
    New-ModuleManifest -Path "$wd/PowerNSX.psd1" -RequiredModules $DesktopRequiredModules -PowerShellVersion '3.0' @Common
}