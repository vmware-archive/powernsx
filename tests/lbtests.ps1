##Spins up a test ESG and exercises all edge cmdlet functionality

$cl = get-cluster mgmt01
$ds = get-datastore Data

#Create one
$name = "lbtest"
$ls1_name = "esgtest_LS1"
$ls2_name = "esgtest_LS2"


$Ip1 = "1.1.1.1"
$ip2 = "2.2.2.2"
$ip3 = "3.3.3.3"
$ip4 = "4.4.4.4"



$ls1 = get-nsxtransportzone | new-nsxlogicalswitch $ls1_name
$ls2 = get-nsxtransportzone | new-nsxlogicalswitch $ls2_name


$vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $ls1 -PrimaryAddress $ip1 -SubnetPrefixLength 24
$vnic1 = New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $ls2 -PrimaryAddress $ip2 -SubnetPrefixLength 24


New-NsxEdgeServicesGateway -Name $name -Interface $vnic0,$vnic1,$vnic2 -Cluster $cl -Datastore $ds -password "VMware1!VMware1!"

#enable LB
get-nsxedgeservicesgateway $name | Update-NsxEdgeServicesGateway -EnableLoadBalancing -EnableAcceleration
$monitor = get-nsxedgeservicesgateway $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor default_http_monitor 
$AppProfile = get-nsxedgeservicesgateway $name | New-NsxLoadBalancerApplicationProfile -Name HTTP -Type HTTP -insertXForwardedFor

#Web Pool
$WebMember1 = New-NsxLoadBalancerMemberSpec -name Web01 -IpAddress 192.168.200.11 -Port 80
$WebMember2 = New-NsxLoadBalancerMemberSpec -name Web02 -IpAddress 192.168.200.12 -Port 80
$WebPool = get-nsxedgeservicesgateway $name | New-NsxLoadBalancerPool -Name WebPool -Description "WebServer Pool" -Transparent:$false -Algorithm round-robin -Monitor $monitor -MemberSpec $WebMember1,$WebMember2

#WebVIP
$WebVip = get-nsxedgeservicesgateway $name | New-NsxLoadBalancerVip -Name WebVip -Description testdesc -IpAddress $ip1 -Protocol http -Port 80 -ApplicationProfile $AppProfile -DefaultPool $WebPool -AccelerationEnabled

#Remove Vip
get-nsxedgeservicesgateway $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVip WebVip| Remove-nsxLoadbalancerVip -confirm:$false

#Remove Pool
get-nsxedgeservicesgateway $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool WebPool | remove-nsxLoadbalancerPool

#Create empty pool
$webPool = get-nsxedgeservicesgateway $name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -Name WebPool -Description "WebServer Pool" -Transparent:$false -Algorithm round-robin -Monitor $monitor
#Add Member
$WebPool = $WebPool | Add-NsxLoadBalancerPoolMember -Name Web01 -IpAddress 192.168.200.11 -port 80
$WebPool = $WebPool | Add-NsxLoadBalancerPoolMember -Name Web02 -IpAddress 192.168.200.12 -port 80

#Remove Poolmember
$WebPool = $Webpool | Get-NsxLoadBalancerPoolMember Web01 | remove-nsxLoadbalancerPoolMember -confirm:$false
$WebPool = $Webpool | Get-NsxLoadBalancerPoolMember Web02 | remove-nsxLoadbalancerPoolMember -confirm:$false

#remove monitor
#Still to do.

#remove appprofile
#Still to do.

#Remove LB ViP
get-nsxedgeservicesgateway $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVip WebVip | remove-nsxLoadbalancerVip -confirm:$false




#Clean up
get-nsxedgeservicesgateway  $name | remove-nsxedgeservicesgateway -confirm:$false
start-sleep 10
get-nsxtransportzone | get-nsxlogicalswitch $ls1_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls2_name | remove-nsxlogicalswitch -confirm:$false





 