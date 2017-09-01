## PowerNSX Sampe Script
## Author: Dale Coghlan
## version 1.0
## August 2017

########################################
# 1 - Connect to your NSX Manager
# 2 - Run the script and provide the path to the file containing the ruleids
#       ./BulkDeleteFwRules.ps1 ruleid.txt
# 3 - If the file contains ruleids that can be removed from the DFW, it will go
#     ahead and remove them, and save a copy of the config before any changes,
#     and also the config that is uploaded to the NSX Manager for future
#     reference.
# 4 - Sit back, have a drink, and reflect on what you just did and how long it
#     would have taken you to do manually.


<#
Copyright © 2017 VMware, Inc. All Rights Reserved.

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
This is a SAMPLE script that will bulk remove individual firewall rules from the
DFW based on a list of rule IDs provided in a text file.

It is intended to be an example of how to perform a certain action and may not
be suitable for all purposes.  Please read an understand its action and modify
as appropriate, or ensure its suitability for a given situation before blindly
running it.

Testing is limited to a lab environment.  Please test accordingly.

#>

# Supply the path to the file containing the list of rule IDs that are required
# to be deleted. The script expects a the file contain a single rule ID per line
$file = $args[0]

# Test to make sure the file path provided actually exists
if (-Not (Test-Path -Path $file) ) {
    throw "The file containing the rules to delete does not exist"
}

$f = Get-Content -Path $file

# Make sure we have a connection to NSX Manager
If ( -not $DefaultNsxConnection ) {
    throw "Please connect to to NSX first"
}

# Go and grab the current firewall configuration
$URI = "/api/4.0/firewall/globalroot-0/config"
$response = invoke-nsxrestmethod -method "get" -uri $URI

# Here we clone the xml response so that we have a copy of the xml that we can
# modify and use to send back to the NSX Manager with the rules removed from it
$modifiedxml = $response.CloneNode($true)

$generationNumber = $modifiedxml.firewallConfiguration.generationNumber
$modified = $false

# Lets loop through the rule ids in the file and find them in the XML. If we
# find them, we remove the node and set the modified flag to $true
foreach ($id in $f ) {
    $node = Invoke-XPathQuery -QueryMethod SelectSingleNode -Node $modifiedxml -Query "firewallConfiguration/*/section/rule[@id=`"$id`"]"
    if ($node) {
        $node.parentnode.removechild($node) | out-null
        $modified = $true
    }
}

# If we managed to remove some xml then lets go ahead and save the original xml
# and the modified xml, just so we can see whats changed. We could have just
# saved the individual nodes that were being removed, but this does not give you
# the context of where abouts in the rule base the rules were located.
if ($modified) {
    if (! (Test-Path -Path "$generationNumber-original.xml")) {
        $response.firewallconfiguration | Export-NsxObject -FilePath "$generationNumber-original.xml"
    }

    if (! (Test-Path -Path "$generationNumber-modified.xml")) {
        $modifiedxml.firewallconfiguration | Export-NsxObject -FilePath "$generationNumber-modified.xml"
    }

    $IfMatchHeader = @{"If-Match"=$generationNumber}
    invoke-nsxwebrequest -method "put" -uri $URI -body $modifiedxml.outerXml -extraheader $IfMatchHeader | out-null
}

