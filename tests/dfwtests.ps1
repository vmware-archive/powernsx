#Creates a test FW Section and exercises all DFW and associated grouping construct cmdlet functionality

#Setup
$l3sectionname = "DfwTestSection"
$l2sectionname = "DfwTestSection"
$testVMName1 = "evil-vm"
$testVMName2 = "custa-vcsa"
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
$TestMac1 = "00:50:56:00:00:00"
$TestMac2 = "00:50:56:00:00:01"

$testvm1 = get-vm $testVMName1
$testvm2 = get-vm $testVMName2

$testls = Get-NsxTransportZone | New-NsxLogicalSwitch $testlsname

#Create Groupings
$TestIpSet = New-NsxIpSet -Name $testIPSetName -Description "Test IP Set" -IpAddresses $testIPs 
$TestSG1 = New-NsxSecurityGroup -Name $testSGName1 -Description "Test SG1" -IncludeMember $testVM1, $testVM2
$TestSG2 = New-NsxSecurityGroup -Name $testSGName2 -Description "Test SG2" -IncludeMember $TestIpSet
$TestService1 = New-NsxService -Name $TestServiceName1 -Protocol $TestServiceProto -port $testPort
$TestService2 = New-NsxService -Name $TestServiceName2 -Protocol $TestServiceProto -port "$testPort,$testPortRange,$testPortSet"


#Create Section
$l3section = New-NsxFirewallSection $l3sectionname
$l2section = New-NsxFirewallSection -Name $l2sectionname -layer2sections

#Create L3 rule source dest vm, service 1, applied to vm
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestRule1" -Source $testvm1 -destination $testvm1 -action allow -appliedTo $TestSG -service $testService1
#Create new L3 rule with multiple members in source/dest/applied to
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestRule2" -Source $testvm1,$testvm2 -destination $testvm1,$testvm2 -action allow -appliedTo $TestSG1,$TestSG2 -position bottom -service $testService2

#Create a FW rule with different element types...
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestRule3" -Source $testvm1,$testsg1 -destination $testvm1,$testsg1 -action allow -appliedTo $TestSG1,$TestVM1 -tag "Test MultiType"


#Create an L2 Rule...
Get-NsxFirewallSection $l2sectionname | New-NsxFirewallRule -Name "TestL2Rule1" -Source $TestMac1 -Destination $TestMac1 -action allow -appliedto $testSG1 -RuleType "layer2sections"

#Multiple members
Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "TestL2Rule2" -Source $TestMac1,$testMac2 -Destination $TestMac1,$TestMac2 -action allow -appliedto $testSG1,$TestSG2 -RuleType "layer2sections"

#Tear Down
Get-NsxFireWallSection $l3sectionname | Get-NsxFirewallRule "TestRule1" | remove-NsxFirewallRule -confirm:$False

Get-NsxFireWallSection $l2sectionname | Get-NsxFirewallRule "TestL2Rule1" | remove-NsxFirewallRule -confirm:$False

Get-NsxFireWallSection $l3sectionname | remove-nsxfirewallsection -force -confirm:$False
Get-NsxFireWallSection $l2sectionname | remove-nsxfirewallsection -force -confirm:$False
Get-NsxSecurityGroup $TestSG1 | remove-NsxSecurityGroup -confirm:$False
Get-NsxSecurityGroup $TestSG2 | remove-NsxSecurityGroup -confirm:$False
Get-NsxIPSet $TestIPSet | remove-NsxIPSet -confirm:$False
Get-NsxService $TestServiceName1 | remove-nsxservice -confirm:$False
Get-NsxService $TestServiceName2 | remove-nsxservice -confirm:$False


#Missing

#Modify IPSet
#Modify SG
