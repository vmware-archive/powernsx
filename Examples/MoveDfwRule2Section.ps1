## PowerNSX Sampe Script
## Author: Dale Coghlan
## version 1.0
## April 2018

########################################
# 1 - Connect to your NSX Manager
# 2 - Run the script and provide the name of the rule you want to move, and also
#     the name of the section you want to move the rule into.

<#
Copyright © 2017 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free
Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more
details.

You should have received a copy of the General Public License version 2 along
with this program. If not, see https://www.gnu.org/licenses/gpl-2.0.html.

The full text of the General Public License 2.0 is provided in the COPYING file.
Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.
#>


<#
This is a SAMPLE script that find a DFW rule based on the name provided, and
move it into the DFW section based on the section name provided.

It is intended to be an example of how to perform a certain action and may not
be suitable for all purposes. Only basic parameters and error checking have been
implemented. Please read an understand its action and modify as appropriate, or
ensure its suitability for a given situation before blindly running it.

Testing is limited to a lab environment. Please test accordingly.

#>
param (

    [Parameter (Mandatory=$True)]
        #Name of DFW rule to find and move to specified DFW section
        [string]$ruleName,
    [Parameter (Mandatory=$True)]
        #Name of DFW Section to move specified rule to
        [string]$sectionName
)

################################################################################
# The fun starts here
################################################################################

# This is to determine dynamic path separators
$pathSeparator = [IO.Path]::DirectorySeparatorChar
# Generate date time string for debug log file name
$dtstring = get-date -format "yyyy_MM_dd_HH_mm_ss"
# Name and location of the debug log file. This will place it in the directory
# where this script is run from and will work cross-platform
$DebugFileNamePrefix = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.InvocationName)
$DebugLogFile = ".$($pathSeparator)$($DebugFileNamePrefix)_$dtstring.log"
# Take note of the start time
$StartTime = Get-Date

function Write-Log {
    param (
        [Parameter(Mandatory=$false)]
            [ValidateSet("host", "warning", "verbose")]
            [string]$level="host",
        [Parameter(Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("white", "yellow", "red", "magenta", "cyan", "green")]
            [string]$ForegroundColor="white",
        [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [object]$msg
            )

    $msgPrefix = "$(get-date -f "HH:mm:ss") : Line($($MyInvocation.ScriptLineNumber)) :"

    if ( -not ( test-path $DebugLogFile )) {
        write-host "$msgPrefix Log file not found... creating a new one"
        New-Item -Type file $DebugLogFile | out-null
        if ( test-path $DebugLogFile ) {
            write-host "$msgPrefix Logging to file $DebugLogFile"
        }
    }

    switch ($level) {
        "warning" {
            write-warning "$msgPrefix $msg"
            Add-content -path $DebugLogFile -value "$msgPrefix $msg"
        }
        "verbose" {
            write-verbose "$msgPrefix $msg"
            Add-content -path $DebugLogFile -value "$msgPrefix $msg"
        }
        default {
            write-host "$msgPrefix $msg" -ForegroundColor $ForegroundColor
            Add-content -path $DebugLogFile -value "$msgPrefix $msg"
        }
    }
}

# Make sure we have a connection to NSX Manager
If ( -not $DefaultNsxConnection ) {
    throw "Please connect to to NSX first"
}

write-log -level host -msg "Retrieving complete DFW configuration"
$uri="/api/4.0/firewall/globalroot-0/config"
$response = invoke-nsxwebrequest -URI $uri -Method GET -connection $connection
[system.xml.xmldocument]$responseXml = $response.content

#Clone the DFW configuration so modifying XML doesnt affect the source.
$_responseXml = $responseXml.CloneNode($true)

write-log -level host -msg "Searching for firewall rule with name $ruleName"
# Find the rule based on the name
$rule = $_responseXml.SelectSingleNode("//rule[name='$ruleName']")
# Find the destination section based on the name
$section = $_responseXml.SelectSingleNode("//section[@name='$($sectionName)']")

# Perform a sanity check that the rule specified doesn't already exist in the destination section
if ($rule.parentNode.name -eq $section.name) {
    write-log -level host -ForegroundColor yellow -msg "Rule '$($ruleName)' with ID '$($rule.id)' already exists in the destination section '$($section.name)' with ID '$($section.id)'"
    throw "Rule already exists in destination section"
}

# Only do the needful if both a rule is found and an appropriate section is found
if ( ($rule) -and ($section) ) {
    write-log -level host -msg "Found firewall rule with name $ruleName ($($rule.id))"
    write-log -level host -msg "Found firewall section with name $sectionName ($($section.id))"

    # Import the rule into the document and then append it to the destination section
    $ruleImport = $section.ownerDocument.ImportNode($rule, $True)
    $section.AppendChild($ruleImport) | out-null

    # Remove the original rule from the source sections
    $rule.parentNode.removeChild($rule) | out-null

    # set the proceed flag to true, as we assume that all is good up to this point.
    $proceed = $True

    # Sanity checks to verify:
    # - The rule has been moved to the desired section
    # - The rule has been removed from the original section
    $sanityCheck = $_responseXml.selectNodes("//rule[name='$ruleName']")

    # If there are no results from the xpath query, then something has gone
    # wrong and we don't want to proceed
    if (! ($sanityCheck) ) {
        $proceed = $False
    } else {
        # Iterate through the results of the xpath query, and if a section is found
        # which doesn't match the destination seciton, then do not proceed.
        foreach ($result in $sanityCheck) {
            if ( $result.parentNode.id -ne $section.id ) {
                $proceed = $False
            }
        }
    }

    if ($proceed = $True) {
        write-log -level host -ForegroundColor green -msg "Sanity checks passed."
        write-log -level host -msg "Updating DFW configuration."

        #Update the DFW configuration
        $body = $_responseXml.OuterXml
        $AdditionalHeaders = @{"If-Match"=$response.Headers.ETag}
        $URI = "/api/4.0/firewall/globalroot-0/config"
        $updateResponse = invoke-nsxwebrequest -method "put" -uri $URI -body $body -extraheader $AdditionalHeaders -connection $connection

        if ( $updateResponse | Get-Member -memberType Properties -name statusCode ) {
            if ( $updateResponse.statusCode -ne '200' ) {
                write-log -level host -ForegroundColor red -msg "Failed to update DFW configuration."
            } else {
                write-log -level host -ForegroundColor green -msg "Successfully updated DFW configuration."
            }
        }
    }
}



