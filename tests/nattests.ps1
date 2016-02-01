#Creates a test ESG, configures NAT and cretes and removes som NAT rules.


$cl = get-cluster mgmt01
$ds = get-datastore Data

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

