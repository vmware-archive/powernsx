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

#Spins up a test DLR and exercises all DLR cmdlet functionality

#Setup
$cl = get-cluster Mgmt01
$ds = get-datastore MgmtData

$name = "testlr"
$ls1_name = "dlrtest_LS1"
$ls2_name = "dlrtest_LS2"
$ls3_name = "dlrtest_LS3"
$ls4_name = "dlrtest_LS4"
$mgt_name = "dlrtest_MGT"


$ls1 = get-nsxtransportzone | new-nsxlogicalswitch $ls1_name
$ls2 = get-nsxtransportzone | new-nsxlogicalswitch $ls2_name
$ls3 = get-nsxtransportzone | new-nsxlogicalswitch $ls3_name
$ls4 = get-nsxtransportzone | new-nsxlogicalswitch $ls4_name

$mgt = get-nsxtransportzone | new-nsxlogicalswitch $mgt_name

$vnic0 = New-NsxLogicalRouterInterfaceSpec -Type uplink -Name vNic0 -ConnectedTo $ls1 -PrimaryAddress 1.1.1.1 -SubnetPrefixLength 24
$vnic1 = New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic1 -ConnectedTo $ls2 -PrimaryAddress 2.2.2.1 -SubnetPrefixLength 24
$vnic2 = New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic2 -ConnectedTo $ls3 -PrimaryAddress 3.3.3.1 -SubnetPrefixLength 24


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


#tests
New-NsxLogicalRouter -Name $name -ManagementPortGroup $mgt -Interface $vnic0,$vnic1,$vnic2 -Cluster $cl -Datastore $ds


#Add a LR vnic 
Get-NsxLogicalRouter $name | New-NsxLogicalRouterInterface -Name Test -Type internal -ConnectedTo $ls4 -PrimaryAddress 4.4.4.1 -SubnetPrefixLength 24

#Update the LR vNic
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12 | Set-NsxLogicalRouterInterface -type internal -Name TestSet -ConnectedTo $ls4 -confirm:$false

#Remove the LR vNic
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12 | Remove-NsxLogicalRouterInterface -confirm:$false


#Static Routing
####

#Create a prefix 
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterPrefix -Name $PrefixName -Network $PrefixNetwork -confirm:$false



#configure Default route
$UplinkVnic = Get-NsxLogicalRouter $name  | Get-NsxLogicalRouterInterface "vNic0"
$UplinkVnicId = $uplinkVnic.index
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $UplinkVnicId -DefaultGatewayAddress $dgaddress -Confirm:$false

#Add a static route
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop -confirm:$false

#Enable OSPF and define router id.
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspf -RouterId $routerId -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2" -Confirm:$false

#Add an OSPF Area
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $OspfAreaId -Confirm:$false

#Add an OSPF Interface
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $OspfAreaId -Vnic $UplinkVnicId -confirm:$false

#EnableRouteRedist from static / connected into Ospf
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -PrefixName $PrefixName -Learner ospf -FromConnected -FromStatic -Action permit -confirm:$false

#Get and remove an OSPF Interface
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfInterface -AreaId $OspfAreaId -VnicId $UplinkVnicId | Remove-NsxLogicalRouterOspfInterface -confirm:$false

#Get and remove an OSPF Area
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId $OspfAreaId | Remove-NsxLogicalRouterOspfArea -confirm:$false



#BGP
###
#Enable BGP and define router id.
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspf:$false -EnableBgp -RouterId $routerId -LocalAS $LocalAS -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2" -Confirm:$false

#Add a BGP Neighbour
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2" -confirm:$false




#EnableRouteRedist from static / connected and ospf into BGP
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -PrefixName $PrefixName -Learner bgp -FromConnected -FromStatic -FromOspf -Action permit -confirm:$false

#Routing Cleanup
####

#Get and Remove Route Redist Rules
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner bgp | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false

#Get and Remove a static route
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | Remove-NsxLogicalRouterStaticRoute -Confirm:$false


#Get and remove a BGP Neighbour
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | Remove-NsxLogicalRouterBgpNeighbour -confirm:$false

#Disable BGP and OSPF
Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgp:$false -EnableOspf:$false -Confirm:$false


#Tear Down
Get-NsxLogicalRouter $name | remove-nsxlogicalrouter -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls1 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls2 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls3 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls4 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $mgt | remove-nsxlogicalswitch -confirm:$false
