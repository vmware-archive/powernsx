## PowerNSX Sample Script
## Author: Dale Coghlan
## version 1.0
## Feb 2018

########################################
# 1 - Connect to your NSX Manager
# 2 - Run the script and it will find the security groups which have dynamic
#     criteria that are configured with "security tag" & "equals" and add them
#     to the log file
#       ./Convert2EntityBelongsTo.ps1
# 3 - If your happy with what it wants to change, run the script with the
#     -DoTheNeedful parameter
#       ./Convert2EntityBelongsTo.ps1 -DoTheNeedful
# 4 - Sit back, have a drink, and if your like me, go and ride a vert on my blades.


<#
Copyright © 2018 VMware, Inc. All Rights Reserved.

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
Often when NSX Security Groups are configured and some dynamic criteria rules
are created, it has been observed that security tag "equals" is often
configured. This is not an optimal configuration, and should be converted to use
entity_belongs_to. This script will automate the process.

If there is only a single dynamic criteria identified in the criteria set, that
is configured with "Security Tag" & "Equals to", the script will remove the
dynamic criteria/set and add the security tag directly as a statically included
member of the security group.

If there are multiple criteria in a criteria set where it find at least 1 of
them is configured with "Security Tag" & "Equals to", the script will do an
in-place conversion to "Entity" & "Belongs to".

If there is no corresponding security tag found that matches what is in the
dynamic criteria, then the script will leave it alone, but a message will be
displayed on the screen as well as captured in the logfile.

A couple of parameter switches have been included to create some sample NSX
Security Tags and NSX Security Groups with dynamic criteria specified so that
you can use these to see how the script functions.

./Convert2EntityBelongsTo.ps1 -TrashTestEnvironment -CreateTestEnvironment

The above will cleanup any previous test tags and groups, and then create them
again. You can use these parameter switches independantly of each other if you
so desire.

This is intended to be an example of how to perform a certain action and may not
be suitable for all purposes. Please read an understand its action and modify
as appropriate, or ensure its suitability for a given situation before blindly
running it.

Testing is limited to a lab environment.  Please test accordingly.

#>

[CmdletBinding(DefaultParameterSetName="StandardExecution")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments","")]

param (

    [Parameter (Mandatory=$False, ParameterSetName="StandardExecution")]
        #Set this switch to modify the NSX Configuration. By default will only report what will change
        [switch]$DoTheNeedful=$false,
    [Parameter (Mandatory=$False, ParameterSetName="TestLab")]
        # Used to setup a small test set of tags and groups
        [switch]$CreateTestEnvironment=$false,
    [Parameter (Mandatory=$False, ParameterSetName="TestLab")]
        # Used to trash the test tags and groups
        [switch]$TrashTestEnvironment=$false

)

################################################################################
# Setup and Teardown some test groups if required
################################################################################
if ( $PSCmdlet.ParameterSetName -eq "TestLab") {

    if ($TrashTestEnvironment) {
        Get-NsxSecurityGroup | Where-Object {$_.name -match "EntityTestGroup_"} | Remove-NsxSecurityGroup -confirm:$False
        Get-NsxSecurityTag | Where-Object {$_.name -match "EntityTagTest"} | Remove-NsxSecurityTag -confirm:$False
    }

    if ($CreateTestEnvironment) {
        1..9 | ForEach-Object {New-NsxSecurityTag -Name EntityTagTest_00$_ | out-null}
        $st = Get-NsxSecurityTag | Where-Object {$_.name -match "EntityTagTest"}

        $criteria0 = New-NsxDynamicCriteriaSpec -Key SecurityTag -Value dummyNonExistentTag -Condition equals
        0..8 | ForEach-Object { New-Variable -Name criteria$($_ + 1) -value (New-NsxDynamicCriteriaSpec -Key SecurityTag -Value ($st[$_].name) -Condition equals)}

        $group1 = New-NsxSecurityGroup -Name EntityTestGroup_001
        $group2 = New-NsxSecurityGroup -Name EntityTestGroup_002
        $group3 = New-NsxSecurityGroup -Name EntityTestGroup_003
        $group4 = New-NsxSecurityGroup -Name EntityTestGroup_004

        Get-NsxSecurityGroup -objectId $group1.objectid | Add-NsxDynamicMemberSet -SetOperator OR -CriteriaOperator ALL -DynamicCriteriaSpec $criteria1,$criteria2
        Get-NsxSecurityGroup -objectId $group1.objectid | Add-NsxDynamicMemberSet -SetOperator OR -CriteriaOperator ALL -DynamicCriteriaSpec $criteria3,$criteria0,$criteria4
        Get-NsxSecurityGroup -objectId $group2.objectid | Add-NsxDynamicMemberSet -SetOperator OR -CriteriaOperator ALL -DynamicCriteriaSpec $criteria3,$criteria5
        Get-NsxSecurityGroup -objectId $group3.objectid | Add-NsxDynamicMemberSet -SetOperator OR -CriteriaOperator ALL -DynamicCriteriaSpec $criteria6,$criteria7,$criteria8,$criteria9
        Get-NsxSecurityGroup -objectId $group4.objectid | Add-NsxDynamicMemberSet -SetOperator OR -CriteriaOperator ALL -DynamicCriteriaSpec $criteria5
    }

    exit
}

################################################################################
# The fun starts here
################################################################################

# This is to determine dynamic path separators
$pathSeparator = [IO.Path]::DirectorySeparatorChar
# Generate date time string for debug log file name
$dtstring = get-date -format "yyyy_MM_dd_HH_mm_ss"
# Name and location of the debug log file. This will place it in the directory
# where this script is run from and will work cross-platform
$DebugLogFile = ".$($pathSeparator)debuglogfile-$dtstring.log"
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

# Retrieve the configuration of ALL the security groups. We do this manually,
# rather than via Get-NsxSecurityGroup as we want the result in a single XML
# document as we can do some funky stuff with XPATH if we need to.
write-log -level host -msg "Retrieving local NSX Security Groups"
$URI = "/api/2.0/services/securitygroup/scope/globalroot-0"
[system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

if ( ! (Invoke-XPathQuery -QueryMethod SelectSingleNode -Node $response -Query 'descendant::list/securitygroup') ) {
    Throw "No security groups were returned."
}

# Save a copy of the security group config prior to any changes being made
write-log -level verbose -msg "$($response | format-xml)"

# Search for any instances where securitytag equals is configured
write-log -level host -msg "Searching for Security Groups with 'Security Tag' & 'Equals' configured in dynamic criteria"
$query = "//dynamicCriteria[key='VM.SECURITY_TAG' and criteria='=']"
$output = Invoke-XpathQuery -QueryMethod SelectNodes -Node $response -query $query

# Create a hash table that allows us to store the security groups that are identified via the query above
$securityGroupsAffected = @{}

if ($output) {
    $foundInstances = ($output| Measure-Object).count
    write-log -level host -msg "Instances where 'Security Tag' & 'equals' is configured : $($foundInstances)" -ForegroundColor green
    write-log -level host -msg "Adding Security Group names to logfile."

    # Go through each criteria which matches the query and add the security group
    # to the hashtable of affected security groups
    foreach ($criteriaFound in $output) {
        # Get the parent security group
        $parentNode = Invoke-XPathQuery -QueryMethod SelectSingleNode -Node $criteriaFound -query "ancestor::securitygroup"
        if ( ! ($securityGroupsAffected.ContainsKey($parentNode.name)) ) {
            write-log -level verbose -msg "Adding to hashtable (securityGroupsAffected) : $($parentNode.name)($($parentNode.objectId))"
            $securityGroupsAffected.Add($parentNode.name,$parentNode)
        }
    }

    if ($DoTheNeedful) {
        # Retrieve a list of all the Security Tags. We really just need the
        # Names and ObjectIds, hence we are just using the applicable members API
        write-log -level host -msg "Retrieving local NSX Security Tags"
        $secTagCache = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag

        # Go through each security group that is identified, and grab the latest
        # config for it. Why not just use the one we already have? Good question.
        # In environments where there is large amounts of security tags,churn
        # or updates to security groups done automatically, we run into an issue
        # where we could be working on a group with a old revision number and
        # NSX doesn't like it if we submit changes with an old revision number.
        foreach ($key in $securityGroupsAffected.KEYS.GetEnumerator()) {
            write-log -level host -msg "Retrieving latest Security Group configuration : $($key)($($securityGroupsAffected[$key].objectId))" -ForegroundColor cyan
            $sg = Get-NsxSecurityGroup -objectid $securityGroupsAffected[$key].objectId

            # Again lets search within this specific security group for the offending criteria
            $sgQueryOutput = Invoke-XpathQuery -QueryMethod SelectNodes -Node $sg -query $query
            $sgModified = $False

            # Now we've found some, lets swap them to use entity belong to
            foreach ($dynamicCriteriaIdentified in $sgQueryOutput) {
                # Identify if this is the only criteria defined in the set?
                $dynamicCriteriaInSetCount = (($dynamicCriteriaIdentified.parentNode).dynamicCriteria | Measure-Object).count
                write-log -level verbose -msg "Criteria set : Criteria count = $($dynamicCriteriaInSetCount)"

                # Lookup the corresponding tag objectid
                $secTag = $secTagCache | Where-Object {$_.name -eq $dynamicCriteriaIdentified.value.trim()}

                # If we don't find a corresponding match with a configured security tag,
                # we just flag it here and move on. When we do find a matching security
                # tag configured in the system, we manipulate the XML and mark the group
                # as modified. We keep doing this for all instances found in the security
                # group, and then at the end, if the gorup is marked as modified, we
                # update it via the API.
                if ( ! ($secTag) ) {
                    write-log -level host -msg "Criteria Skipped - Exact match NOT found for Security Tag : $($dynamicCriteriaIdentified.value)" -ForegroundColor red
                } else {
                    write-log -level host -msg "Found exact match for Security Tag : $($dynamicCriteriaIdentified.value)($($secTag.objectid))" -ForegroundColor green

                    # If there is more than 1 criteria in the set, just do an in place
                    # conversion to entity belongs to, otherwise remove the dynamic
                    # criteria and add the security tag as a static include.
                    if ($dynamicCriteriaInSetCount -gt 1) {
                        write-log -level verbose -msg "Multiple criteria exists in parentNode. Performing conversion to Entity Belongs To"
                        write-log -level verbose -msg "----- BEFORE -----"
                        write-log -level verbose -msg ($dynamicCriteriaIdentified | format-xml)
                        $dynamicCriteriaIdentified.key = "ENTITY"
                        $dynamicCriteriaIdentified.criteria = "belongs_to"
                        $dynamicCriteriaIdentified.value = $secTag.objectid
                        write-log -level verbose -msg "----- AFTER -----"
                        write-log -level verbose -msg ($dynamicCriteriaIdentified | format-xml)
                        $sgModified = $True
                    } else {
                        write-log -level verbose -msg "Single criteria in parent node found. Criteria will be deleted and added as a statically included member."
                        $null = $memberxml = $sg.OwnerDocument.CreateElement("member")
                        $null = $sg.AppendChild($memberxml)
                        Add-XmlElement -xmlRoot $memberxml -xmlElementName "objectId" -xmlElementText $secTag.objectid

                        $dynamicCriteriaIdentified.parentNode.parentNode.RemoveChild($dynamicCriteriaIdentified.parentNode) | out-null

                        $sgModified = $True
                    }
                }
            }
            if ($sgModified) {
                write-log -level host -msg "Updating Security Group : $($sg.name)($($sg.objectid))" -ForegroundColor green
                write-log -level verbose -msg ($sg.outerXml | format-xml)
                $sgUpdateURI = "/api/2.0/services/securitygroup/bulk/$($sg.objectid)"
                $update = Invoke-NsxRestMethod -method PUT -uri $sgUpdateURI -body $sg.outerXml
            }
        }
    }

}

[timespan]$ts = (get-date) - $StartTime
write-log -ForegroundColor magenta -msg "Script complete in $($ts -f "HH:mm:ss")"
write-log -ForegroundColor magenta -msg "Debug log saved to $DebugLogFile"
