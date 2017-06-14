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

#Creates a test FW Section and exercises all DFW and associated grouping construct cmdlet functionality

#Setup
$l3sectionname = "DfwTestL3Section"
$l2sectionname = "DfwTestL2Section"
$testVMName1 = "app01"
$testVMName2 = "app02"
$testSGName1 = "testSG1"
$testSGName2 = "testSG2"
$testIPSetName = "testIpSet"
$testIPs = "1.1.1.1,2.2.2.2"
$TestServiceName1 = "testService1"
$testServiceName2 = "testService2"
$testPort = "80"
$testPortRange = "80-88"
$testPortSet = "80,88"
$testServiceProto = "tcp"
$testlsname = "testls"
$TestMacSetName1 = "testMacSet1"
$TestMacSetName2 = "testMacSet2"
$TestMac1 = "00:50:56:00:00:00"
$TestMac2 = "00:50:56:00:00:01"

$dfwedgename = "dfwesgtest"
$dfwedgeIp1 = "1.1.1.1"

$testvm1 = get-vm $testVMName1
$testvm2 = get-vm $testVMName2
$cl = get-cluster mgmt01
$ds = get-datastore MgmtData
$Password = "VMware1!VMware1!"
$tenant = "testtenant"

$testls = Get-NsxTransportZone | New-NsxLogicalSwitch $testlsname

#Create Edge
$vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $testls -PrimaryAddress $dfwedgeIp1 -SubnetPrefixLength 24
New-NsxEdge -Name $dfwedgename -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh

#Create Groupings
$TestIpSet = New-NsxIpSet -Name $testIPSetName -Description "Test IP Set" -IpAddresses $testIPs 
$TestMacSet1 = New-NsxMacSet -Name $testMacSetName1 -Description "Test MAC Set1" -MacAddresses "$TestMac1,$TestMac2" 
$TestMacSet2 = New-NsxMacSet -Name $testMacSetName2 -Description "Test MAC Set2" -MacAddresses "$TestMac1,$TestMac2" 

$TestSG1 = New-NsxSecurityGroup -Name $testSGName1 -Description "Test SG1" -IncludeMember $testVM1, $testVM2
$TestSG2 = New-NsxSecurityGroup -Name $testSGName2 -Description "Test SG2" -IncludeMember $TestIpSet
$TestService1 = New-NsxService -Name $TestServiceName1 -Protocol $TestServiceProto -port $testPort
$TestService2 = New-NsxService -Name $TestServiceName2 -Protocol $TestServiceProto -port "$testPort,$testPortRange,$testPortSet"


#Create Section
$l3section = New-NsxFirewallSection $l3sectionname
$l2section = New-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections

#Create L3 rule source dest vm, service 1, applied to vm
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestRule1" -Source $testvm1 -destination $testvm1 -action allow -appliedTo $TestSG1 -service $testService1
#Create new L3 rule with multiple members in source/dest/applied to
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestRule2" -Source $testvm1,$testvm2 -destination $testvm1,$testvm2 -action allow -appliedTo $TestSG1,$TestSG2 -position bottom -service $testService2

#Create a FW rule with different element types...
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestRule3" -Source $testvm1,$testsg1 -destination $testvm1,$testsg1 -action allow -appliedTo $TestSG1,$TestVM1 -tag "Test MultiType"

#Create some different applied to rules...
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestRule4" -Source $testvm1,$testsg1 -destination $testvm1,$testsg1 -action allow -ApplyToDfw -ApplyToAllEdges

#Create an L2 Rule...
Get-NsxFirewallSection $l2sectionname | New-NsxFirewallRule -Name "TestL2Rule1" -Source $TestMacSet1 -Destination $TestMacSet1 -action allow -appliedto $testSG1 -RuleType "layer2sections"

#Multiple members
Get-NsxFirewallSection $l2sectionname | New-NsxFirewallRule -Name "TestL2Rule2" -Source $TestMacSet1,$TestMacSet2 -Destination $TestMacSet1,$TestMacSet2 -action allow -appliedto $testSG1,$TestSG2 -RuleType "layer2sections"

read-host "Hit any key to tear down"

#Tear Down
Get-NsxFireWallSection $l3sectionname | Get-NsxFirewallRule "TestRule1" | remove-NsxFirewallRule -confirm:$False

Get-NsxFireWallSection $l2sectionname | Get-NsxFirewallRule "TestL2Rule1" | remove-NsxFirewallRule -confirm:$False

Get-NsxFireWallSection $l3sectionname | remove-nsxfirewallsection -force -confirm:$False
Get-NsxFireWallSection $l2sectionname | remove-nsxfirewallsection -force -confirm:$False
Get-NsxSecurityGroup $TestSGName1 | remove-NsxSecurityGroup -confirm:$False
Get-NsxSecurityGroup $TestSGName2 | remove-NsxSecurityGroup -confirm:$False
Get-NsxMacSet $TestMacSetName1 | remove-nsxmacset -confirm:$false
Get-NsxMacSet $TestMacSetName2 | remove-nsxmacset -confirm:$false
Get-NsxIPSet $TestIPSetName | remove-NsxIPSet -confirm:$False
Get-NsxService $TestServiceName1 | remove-nsxservice -confirm:$False
Get-NsxService $TestServiceName2 | remove-nsxservice -confirm:$False
Get-NSxEdge $dfwedgename | remove-nsxedge -confirm:$false
start-sleep 10
Get-NsxTransportZone | get-nsxLogicalSwitch $testlsname | remove-nsxlogicalswitch -confirm:$false
#Missing

#Modify IPSet
#Modify SG
