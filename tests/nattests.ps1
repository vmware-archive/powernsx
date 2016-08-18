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

#Creates a test ESG, configures NAT and creates and removes some NAT rules.


$cl = get-cluster mgmt01
$ds = get-datastore MgmtData

#Create one
$name = "nattest"
$ls1_name = "nattest_LS1"
$ls2_name = "nattest_LS2"

$Ip1 = "1.1.1.1"
$ip2 = "2.2.2.2"

$ls1 = get-nsxtransportzone | new-nsxlogicalswitch $ls1_name
$ls2 = get-nsxtransportzone | new-nsxlogicalswitch $ls2_name

$vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $ls1 -PrimaryAddress $ip1 -SubnetPrefixLength 24
$vnic1 = New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $ls2 -PrimaryAddress $ip2 -SubnetPrefixLength 24

New-NsxEdge -Name $name -Interface $vnic0,$vnic1 -Cluster $cl -Datastore $ds -password "VMware1!VMware1!"

get-nsxedge $name | get-nsxedgenat | set-nsxedgenat -enabled -confirm:$false
$rule1 = get-nsxedge $name | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action dnat -Protocol tcp -Description "testing dnat from powernsx" -LoggingEnabled -Enabled -OriginalPort 1234 -TranslatedPort 1234
$rule2 = get-nsxedge $name | get-nsxedgenat | new-nsxedgenatrule -Vnic 1 -OriginalAddress 2.3.4.5 -TranslatedAddress 1.2.3.4 -action snat -Description "testing snat from powernsx" -LoggingEnabled -Enabled
$rule3 = get-nsxedge $name | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action dnat -Protocol icmp -Description "testing icmp nat from powernsx" -LoggingEnabled -Enabled -icmptype any


$rule1 | remove-nsxedgenatrule -confirm:$false
get-nsxedge $name | get-nsxedgenat | get-nsxedgenatrule | remove-nsxedgenatrule -confirm:$false

get-nsxedge $name | remove-nsxedge -confirm:$false
start-sleep 10

$ls1 | remove-nsxlogicalswitch -confirm:$false
$ls2 | remove-nsxlogicalswitch -confirm:$false

