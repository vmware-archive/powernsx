
$cluster = "Mgmt01"
$testvm = "miscapp01"
$testlsname = "TestLs1"

$vm1 = new-vm -name $testVMName1 -ResourcePool ( Get-Cluster $Cluster | Get-ResourcePool Resources)

Get-Cluster $cluster | Get-NsxClusterStatus


#SecurityPolicy - still rudimentary, no new/modify cmdlets...cant test remove...
Get-NsxSecurityPolicy


$testsg = New-NsxSecurityGroup -Name Testing -IncludeMember (Get-vm $testvm)
$testsg | Get-NsxSecurityGroupEffectiveMembers
get-vm $testvm | Where-NsxVMUsed
$testsg | remove-nsxsecuritygroup -confirm:$false

$LS = Get-NsxTransportZone | New-NsxLogicalSwitch $testlsname
$LS | Get-nsxbackingPortGroup
$LS | Get-NsxBackingDVSwitch
$LS | Remove-NsxLogicalSwitch -confirm:$false



