<#
Copyright © 2015 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more details.

You should have received a copy of the General Public License version 2 along with this program.
If not, see https://www.gnu.org/licenses/gpl-2.0.html.

The full text of the General Public License 2.0 is provided in the COPYING file.
Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.”
#>

#Excercises all created Service Group command

$svgname = "Test-SVG"
$svcname = "Test-SVC"
$svcport = "443"

$svg = New-NsxServiceGroup $svgname
$svc = New-NsxService $svcname -protocol "TCP" -port $svcport

$svg = $svg | Add-NsxServiceGroupMember $svc

$svg | Get-NsxServiceGroupMember

$svg | Remove-NsxServiceGroup -confirm:$false


