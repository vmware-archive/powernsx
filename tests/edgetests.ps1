##Spins up a test ESG and exercises all edge cmdlet functionality

$cl = get-cluster mgmt01
$ds = get-datastore Data

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

$vdswitch_name = "mgmt_transit"



$ls1 = get-nsxtransportzone | new-nsxlogicalswitch $ls1_name
$ls2 = get-nsxtransportzone | new-nsxlogicalswitch $ls2_name
$ls3 = get-nsxtransportzone | new-nsxlogicalswitch $ls3_name
$ls4 = get-nsxtransportzone | new-nsxlogicalswitch $ls4_name
$ls5 = get-nsxtransportzone | new-nsxlogicalswitch $ls5_name
$pg1 = Get-VDSwitch $vdswitch_name |  New-VDPortgroup -name $pg1_name



$vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $ls1 -PrimaryAddress $ip1 -SubnetPrefixLength 24
$vnic1 = New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $ls2 -PrimaryAddress $ip2 -SubnetPrefixLength 24
$vnic2 = New-NsxEdgeInterfaceSpec -index 3 -Type trunk -Name "vNic3" -ConnectedTo $pg1

New-NsxEdgeServicesGateway -Name $name -Interface $vnic0,$vnic1,$vnic2 -Cluster $cl -Datastore $ds -password "VMware1!VMware1!"


#Add a vnic 
Get-NsxEdgeServicesGateway $name | Get-NsxEdgeInterface -Index 4 | Set-NsxEdgeInterface -Name "vNic4" -Type internal -ConnectedTo $ls4 -PrimaryAddress $ip4 -SubnetPrefixLength 24

#Add a subint of VLAN and Network Type
Get-NsxEdgeServicesGateway $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubinterface  -Name "sub1" -PrimaryAddress $ip5 -SubnetPrefixLength 24 -TunnelId 1 -Vlan 123
Get-NsxEdgeServicesGateway $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubinterface  -Name "sub2" -PrimaryAddress $ip6 -SubnetPrefixLength 24 -TunnelId 2 -Network $ls5

#Get and Remove a subint by name
Get-NsxEdgeServicesGateway $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface "sub1" | Remove-NsxEdgeSubinterface -confirm:$false 

#Get and Remove a subint by index
Get-NsxEdgeServicesGateway $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11 | Remove-NsxEdgeSubinterface -confirm:$false


#Get and remove a vNic by name and index
Get-NsxEdgeServicesGateway $name | Get-NsxEdgeInterface -index 3 | Clear-NsxEdgeInterface -confirm:$false
Get-NsxEdgeServicesGateway $name | Get-NsxEdgeInterface "vNic4" | Clear-NsxEdgeInterface -confirm:$false


#enable LB
get-nsxedgeservicesgateway $name | Update-NsxEdgeServicesGateway -EnableLoadBalancing -EnableAcceleration
$monitor = get-nsxedgeservicesgateway $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor default_http_monitor 
$AppProfile = get-nsxedgeservicesgateway $name | New-NsxLoadBalancerApplicationProfile -Name HTTP -Type HTTP -insertXForwardedFor

#Web Vip
$WebMember1 = New-NsxLoadBalancerMemberSpec -name Web01 -IpAddress 192.168.200.11 -Port 80
$WebMember2 = New-NsxLoadBalancerMemberSpec -name Web02 -IpAddress 192.168.200.12 -Port 80
$WebPool = get-nsxedgeservicesgateway $name | New-NsxLoadBalancerPool -Name WebPool -Description "WebServer Pool" -Transparent:$false -Algorithm round-robin -Monitor $monitor -MemberSpec $WebMember1,$WebMember2
$WebVip = get-nsxedgeservicesgateway $name | New-NsxLoadBalancerVip -Name WebVip -Description testdesc -IpAddress $ip1 -Protocol http -Port 80 -ApplicationProfile $AppProfile -DefaultPool $WebPool -AccelerationEnabled

#Remove Vip
#Still to do.

#Remove Poolmember
#Still to do.

#remove monitor
#Still to do.

#remove appprofile
#Still to do.

#Add member to pool
#Still to do.

#Remove LB
#Still to do.


#Clean up
get-nsxedgeservicesgateway  $name | remove-nsxedgeservicesgateway -confirm:$false
start-sleep 10
get-nsxtransportzone | get-nsxlogicalswitch $ls1_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls2_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls3_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls4_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls5_name | remove-nsxlogicalswitch -confirm:$false
get-vdportgroup $pg1_name | remove-vdportgroup -confirm:$false



 