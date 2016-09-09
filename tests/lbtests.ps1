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


##Spins up a test ESG and exercises all LB cmdlet functionality

$cl = get-cluster mgmt01
$ds = get-datastore MgmtData

#Create one
$name = "lbtest"
$ls1_name = "esgtest_LS1"
$ls2_name = "esgtest_LS2"


$Ip1 = "1.1.1.1"
$ip2 = "2.2.2.2"
$ip3 = "3.3.3.3"
$ip4 = "4.4.4.4"

$script = "acl vmware_page url_beg /vmware redirect location https://www.vmware.com/ if vmware_page"

$ls1 = get-nsxtransportzone | new-nsxlogicalswitch $ls1_name
$ls2 = get-nsxtransportzone | new-nsxlogicalswitch $ls2_name


$vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $ls1 -PrimaryAddress $ip1 -SubnetPrefixLength 24
$vnic1 = New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $ls2 -PrimaryAddress $ip2 -SubnetPrefixLength 24


New-NsxEdge -Name $name -Interface $vnic0,$vnic1 -Cluster $cl -Datastore $ds -password "VMware1!VMware1!"

#enable LB
get-NsxEdge $name | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled -EnableAcceleration
$monitor = get-NsxEdge $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor default_http_monitor 
$AppProfile = get-NsxEdge $name | Get-NsxLoadBalancer |New-NsxLoadBalancerApplicationProfile -Name HTTP -Type HTTP -insertXForwardedFor

#Web Pool
$WebMember1 = New-NsxLoadBalancerMemberSpec -name Web01 -IpAddress 192.168.200.11 -Port 80
$WebMember2 = New-NsxLoadBalancerMemberSpec -name Web02 -IpAddress 192.168.200.12 -Port 80
$WebPool = get-NsxEdge $name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -Name WebPool -Description "WebServer Pool" -Transparent:$false -Algorithm round-robin -Monitor $monitor -MemberSpec $WebMember1,$WebMember2

#WebVIP
$WebVip = get-NsxEdge $name | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -Name WebVip -Description testdesc -IpAddress $ip1 -Protocol http -Port 80 -ApplicationProfile $AppProfile -DefaultPool $WebPool -AccelerationEnabled

#New Application Rule
get-NsxEdge $name | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationRule -name Test -script $script

#Get Application Rule 
get-NsxEdge $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationRule -name Test


#Remove Vip
get-NsxEdge $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVip WebVip| Remove-nsxLoadbalancerVip -confirm:$false

#Remove Pool
get-NsxEdge $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool WebPool | remove-nsxLoadbalancerPool -confirm:$false

#Create empty pool
$webPool = get-NsxEdge $name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -Name WebPool -Description "WebServer Pool" -Transparent:$false -Algorithm round-robin -Monitor $monitor
#Add Member
$WebPool = $WebPool | Add-NsxLoadBalancerPoolMember -Name Web01 -IpAddress 192.168.200.11 -port 80
$WebPool = $WebPool | Add-NsxLoadBalancerPoolMember -Name Web02 -IpAddress 192.168.200.12 -port 80

#Get stats
$stats = Get-NsxEdge $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerStats 

#Remove Poolmember
$WebPool = $Webpool | Get-NsxLoadBalancerPoolMember Web01 | remove-nsxLoadbalancerPoolMember -confirm:$false
$WebPool = $Webpool | Get-NsxLoadBalancerPoolMember Web02 | remove-nsxLoadbalancerPoolMember -confirm:$false

#remove monitor
#Still to do.

#remove appprofile
#Still to do.

#Remove LB ViP
get-NsxEdge $name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVip WebVip | remove-nsxLoadbalancerVip -confirm:$false




#Clean up
get-NsxEdge  $name | remove-NsxEdge -confirm:$false
start-sleep 10
get-nsxtransportzone | get-nsxlogicalswitch $ls1_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls2_name | remove-nsxlogicalswitch -confirm:$false





 
