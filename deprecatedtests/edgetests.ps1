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

##Spins up a test ESG and exercises all edge cmdlet functionality

$cl = get-cluster mgmt01
$ds = get-datastore MgmtData

#Create one
$name = "esgtest"
$ls1_name = "esgtest_LS1"
$ls2_name = "esgtest_LS2"
$ls3_name = "esgtest_LS3"
$ls4_name = "esgtest_LS4"
$ls5_name = "esgtest_LS5"

$pg1_name = "testesgtrunk"


$Ip1 = "1.1.1.1"
$ip2 = "2.2.2.2"
$ip3 = "3.3.3.3"
$ip4 = "4.4.4.4"
$ip5 = "5.5.5.5"
$ip6 = "6.6.6.6"

$vdswitch_name = "Mgt_Trans_Vds"

$dgaddress = "1.1.1.254"
$staticroutenet = "20.20.20.0/24"
$staticroutenexthop = "1.1.1.254"

$OspfAreaId = "50"
$RouterId = "1.1.1.1"
$LocalAS = "1234"

$bgpneighbour = "1.1.1.254"
$RemoteAS = "2345"

$PrefixName = "TestPrefix"
$PrefixNetwork = "1.2.3.0/24"

$Password = "VMware1!VMware1!"
$tenant = "testtenant"

$ls1 = get-nsxtransportzone | new-nsxlogicalswitch $ls1_name
$ls2 = get-nsxtransportzone | new-nsxlogicalswitch $ls2_name
$ls3 = get-nsxtransportzone | new-nsxlogicalswitch $ls3_name
$ls4 = get-nsxtransportzone | new-nsxlogicalswitch $ls4_name
$ls5 = get-nsxtransportzone | new-nsxlogicalswitch $ls5_name
$pg1 = Get-VDSwitch $vdswitch_name |  New-VDPortgroup -name $pg1_name



$vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $ls1 -PrimaryAddress $ip1 -SubnetPrefixLength 24
$vnic1 = New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $ls2 -PrimaryAddress $ip2 -SubnetPrefixLength 24
$vnic2 = New-NsxEdgeInterfaceSpec -index 3 -Type trunk -Name "vNic3" -ConnectedTo $pg1

New-NsxEdge -Name $name -Interface $vnic0,$vnic1,$vnic2 -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh


#Add a vnic 
Get-NsxEdge $name | Get-NsxEdgeInterface -Index 4 | Set-NsxEdgeInterface -Name "vNic4" -Type internal -ConnectedTo $ls4 -PrimaryAddress $ip4 -SubnetPrefixLength 24

#Add a subint of VLAN and Network Type
Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubinterface  -Name "sub1" -PrimaryAddress $ip5 -SubnetPrefixLength 24 -TunnelId 1 -Vlan 123
Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubinterface  -Name "sub2" -PrimaryAddress $ip6 -SubnetPrefixLength 24 -TunnelId 2 -Network $ls5

#Get and Remove a subint by name
Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface "sub1" | Remove-NsxEdgeSubinterface -confirm:$false 

#Get and Remove a subint by index
Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11 | Remove-NsxEdgeSubinterface -confirm:$false


#Get and remove a vNic by name and index
Get-NsxEdge $name | Get-NsxEdgeInterface -index 3 | Clear-NsxEdgeInterface -confirm:$false
Get-NsxEdge $name | Get-NsxEdgeInterface "vNic4" | Clear-NsxEdgeInterface -confirm:$false

#Static Routing
####

#configure Default route
Get-NsxEdge $name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayVnic 1 -DefaultGatewayAddress $dgaddress -Confirm:$false

#Add a static route
Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop -confirm:$false

#Enable OSPF and define router id.
Get-NsxEdge $Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspf -RouterId $routerId -Confirm:$false

#Add an OSPF Area
Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeOspfArea -AreaId $OspfAreaId -Confirm:$false

#Add an OSPF Interface
Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeOspfInterface -AreaId $OspfAreaId -Vnic 1 -confirm:$false


#BGP
###
#Enable BGP and define router id.
Get-NsxEdge $Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgp -RouterId $routerId -LocalAS $LocalAS -Confirm:$false

#Add a BGP Neighbour
Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs -confirm:$false



#Route redistribution
###
#Create a prefix 
Get-NsxEdge $Name | Get-NsxEdgeRouting | New-NsxEdgePrefix -Name $PrefixName -Network $PrefixNetwork -confirm:$false

#EnableRouteRedist from static / connected into Ospf
Get-NsxEdge $Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -PrefixName $PrefixName -Learner ospf -FromConnected -FromStatic -Action permit -confirm:$false

#EnableRouteRedist from static / connected and ospf into BGP
Get-NsxEdge $Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -PrefixName $PrefixName -Learner bgp -FromConnected -FromStatic -FromOspf -Action permit -confirm:$false

read-host "Enter to cleanup..."

#Routing Cleanup
####

#Get and Remove Route Redist Rules
Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false
Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner bgp | Remove-NsxEdgeRedistributionRule -Confirm:$false

#Get and Remove a static route
Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | Remove-NsxEdgeStaticRoute -Confirm:$false

#Get and remove an OSPF Interface
Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface -AreaId $OspfAreaId -VnicId 1 | Remove-NsxEdgeOspfInterface -confirm:$false

#Get and remove an OSPF Area
Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId $OspfAreaId | Remove-NsxEdgeOspfArea -confirm:$false


#Get and remove a BGP Neighbour
Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | Remove-NsxEdgeBgpNeighbour -confirm:$false

#Disable BGP and OSPF
Get-NsxEdge $Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgp:$false -EnableOspf:$false -Confirm:$false


#General Clean up
get-NsxEdge  $name | remove-NsxEdge -confirm:$false
start-sleep 10
get-nsxtransportzone | get-nsxlogicalswitch $ls1_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls2_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls3_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls4_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls5_name | remove-nsxlogicalswitch -confirm:$false
get-vdportgroup $pg1_name | remove-vdportgroup -confirm:$false



 