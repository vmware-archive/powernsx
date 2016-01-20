#Spins up a test DLR and exercises all DLR cmdlet functionality

#Setup
$cl = get-cluster mgmt01
$ds = get-datastore Data

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

#tests
New-NsxLogicalRouter -Name $name -ManagementPortGroup $mgt -Interface $vnic0,$vnic1,$vnic2 -Cluster $cl -Datastore $ds


#Add a LR vnic 
Get-NsxLogicalRouter $name | New-NsxLogicalRouterInterface -Name Test -Type internal -ConnectedTo $ls4 -PrimaryAddress 4.4.4.1 -SubnetPrefixLength 24

#Update the LR vNic
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12 | Set-NsxLogicalRouterInterface -type internal -Name TestSet -ConnectedTo $ls4 -confirm:$false

#Remove the LR vNic
Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12 | Remove-NsxLogicalRouterInterface -confirm:$false


#Tear Down
Get-NsxLogicalRouter $name | remove-nsxlogicalrouter -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls1 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls2 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls3 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $ls4 | remove-nsxlogicalswitch -confirm:$false
get-nsxtransportzone | get-nsxlogicalswitch $mgt | remove-nsxlogicalswitch -confirm:$false
