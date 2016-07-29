##Spins up a test ESG and exercises all cert cmdlet functionality

$cl = get-cluster mgmt01
$ds = get-datastore MgmtData

#Create one
$name = "esgtest"
$ls1_name = "vpntest_LS1"
$ls2_name = "vpntest_LS2"

$Ip1 = "1.1.1.1"
$ip2 = "2.2.2.2"

$ls1 = get-nsxtransportzone | new-nsxlogicalswitch $ls1_name
$ls2 = get-nsxtransportzone | new-nsxlogicalswitch $ls2_name

$vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $ls1 -PrimaryAddress $ip1 -SubnetPrefixLength 24
$vnic1 = New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $ls2 -PrimaryAddress $ip2 -SubnetPrefixLength 24

New-NsxEdge -Name $name -Interface $vnic0,$vnic1 -Cluster $cl -Datastore $ds -password "VMware1!VMware1!"

get-nsxedge $name | Get-NsxSslVpn | Set-NsxSslVpn -EnableCompression `
    -ForceVirtualKeyboard -RandomizeVirtualkeys -preventMultipleLogon `
    -ClientNotification "Testing Notification from PowerNSX" -EnablePublicUrlAccess `
    -ForcedTimeout 123 -SessionIdleTimeout 12 -ClientAutoReconnect -ClientUpgradeNotification `
    -EnableLogging -LogLevel debug -Confirm:$false

get-nsxedge $name | get-nsxsslvpn | New-NsxSslVpnIpPool -IpRange `
    10.0.0.10-10.0.0.254 -Netmask 255.255.255.0 -Gateway 10.0.0.1 -PrimaryDnsServer `
    8.8.8.8 -SecondaryDnsServer 8.8.4.4 -DnsSuffix test.copr -WinsServer 1.2.3.4


#General Clean up
get-NsxEdge  $name | remove-NsxEdge -confirm:$false
start-sleep 10
get-nsxtransportzone | get-nsxlogicalswitch $ls1_name | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls2_name | remove-nsxlogicalswitch -confirm:$false



