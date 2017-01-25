#PowerNSX example script
#Nick Bradford
#nbradford@vmware.com

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
has its own license that is located in the source code of the respective component.
#>


<#
This is a SAMPLE script that enables logging on all firewall rules in the NSX DFW.

It is intended to be an example of how to perform a certain action and may not be suitable
for all purposes.  Please read an understand its action and modify as appropriate, or ensure
its suitability for a given situation before blindly running it.

Testing is limited to a lab environment.  Please test accordingly.

#>

#Requires -Version 3.0
#Requires -Module PowerNSX

If ( -not $DefaultNsxConnection ) {
    throw "Please connect to to NSX first"
}


foreach ( $section in (Get-NsxFirewallSection | ? { $_.name -notmatch 'Default Section Layer3' })) {
    $req = Invoke-NsxWebRequest -URI "/api/4.0/firewall/globalroot-0/config/layer3sections/$($section.id)" -method get
    $content = [xml]$req.Content
    foreach ($rule in $content.section.rule) { $rule.logged = "true" }
    $AdditionalHeaders = @{"If-Match"=$req.Headers.ETag}
    $response = Invoke-NsxWebRequest -URI "/api/4.0/firewall/globalroot-0/config/layer3sections/$($section.id)" -method put -extraheader $AdditionalHeaders -body $content.section.outerxml
    if ( -not $response.StatusCode -eq 200 ) {
        throw "Failed putting section $($section.name) ($($section.id)).  $($response.StatusCode) : $($response.StatusDescription)"
    }
    else {
        write-host "Enabled logging on all rules in Section $($section.name) ($($section.id))"
    }
}