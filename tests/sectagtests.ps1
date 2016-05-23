#Exercises all security tag cmdlets functionality

#Setup

$Cluster = Mgmt01

$testVMName1 = "STapp01"
$testVMName2 = "STapp02"

$testSTName1 = "testST1"
$testSTName2 = "testST2"

$TestVm1 = $vm1
$TestVm2 = $vm2

$testST1 = Get-NsxSecurityTag $testSTName1
$testST2 = Get-NsxSecurityTag $testSTName2

If ( -not $TestVM1 ) { 
    $vm1 = new-vm -name $testVMName1 -ResourcePool ( Get-Cluster $Cluster | Get-ResourcePool Resources)
}

If ( -not $TestVM2 ) { 
    $vm2 = new-vm -name $testVMName2 -ResourcePool ( Get-Cluster $Cluster | Get-ResourcePool Resources)
}

if ( -not $testST1) {
    $testST1 = New-NsxSecurityTag $testSTName1
}

if ( -not $testST2) {
    $testST2 = New-NsxSecurityTag $testSTName2
}

# Test Cases
write-host -foregroundcolor Green "--- Start Test 1 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to a single virtual machine"

write-host "`nSecurity Tags before"
$vm1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-NsxSecurityTag $testSTName1 | New-NsxSecurityTagAssignment -vm ($vm1)
$vm1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
$vm1 | Remove-NsxSecurityTagAssignment -tag (Get-NsxSecurityTag $testSTName1) -confirm:$false
$vm1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 1 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 2 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to a single virtual machine"

write-host "`nSecurity Tags before"
$vm2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
$vm2 | New-NsxSecurityTagAssignment -tag (Get-NsxSecurityTag $testSTName2) 
$vm2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-NsxSecurityTag $testSTName2 | Remove-NsxSecurityTagAssignment -vm ($vm2) -confirm:$false
$vm2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 2 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 3 ---"
write-host -foregroundcolor Green "`nAdd and remove a multiple security tags to a single virtual machine"

write-host "`nSecurity Tags before"
$vm2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
$vm2 | New-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } )
$vm2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } ) | Remove-NsxSecurityTagAssignment -vm ($vm2) -confirm:$false
$vm2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 3 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 4 ---"
write-host -foregroundcolor Green "`nAdd and remove a multiple security tags to a single virtual machine"

write-host "`nSecurity Tags before"
$vm1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } ) | New-NsxSecurityTagAssignment -vm ($vm1)
$vm1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
$vm1 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } )  -confirm:$false
$vm1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 4 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 5 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to multiple virtual machines"

write-host "`nSecurity Tags before"
$vm2,$testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
$vm2,$testVMName1 | New-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 )
$vm2,$testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-NsxSecurityTag $testSTName2  | Remove-NsxSecurityTagAssignment -vm ($vm2,$testVMName1) -confirm:$false
$vm2,$testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 5 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 6 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to multiple virtual machines"

write-host "`nSecurity Tags before"
$vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-NsxSecurityTag $testSTName2  | New-NsxSecurityTagAssignment -vm ($vm1,$testVMName2)
$vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
$vm1,$testVMName2 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 ) -confirm:$false
$vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 6 ---"
#
#
#
# write-host -foregroundcolor Green "`n`n`n--- Start Test 7 ---"
# write-host -foregroundcolor Green "`Testing NSX Security Tag Assignment export"

# write-host "`nSecurity Tags before"
# $vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

# write-host "`nSecurity Tags Added"
# Get-NsxSecurityTag $testSTName2  | New-NsxSecurityTagAssignment -vm ($vm1,$testVMName2)
# $vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

# write-host "`nExporting csv file"
# $vm1,$testVMName2 | Get-NsxSecurityTagAssignment | export-csv -path $csvFileName

# write-host "`nSecurity Tags Removed"
# $vm1,$testVMName2 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 ) -confirm:$false
# $vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

# write-host "`nImporting security tag assignment from csv file"
# New-NsxSecurityTagAssignment -csv -path $csvFileName

# write-host "`nSecurity Tags imported"
# $vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

# write-host "`nSecurity Tags Removed"
# $vm1,$testVMName2 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 ) -confirm:$false
# $vm1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

# write-host "`n--- End Test 7 ---"

#Cleanup
Get-NsxSecurityTag $testSTName1 | Remove-NsxSecurityTag -confirm:$false
Get-NsxSecurityTag $testSTName2 | Remove-NsxSecurityTag -confirm:$false
$vm1 | remove-vm -Confirm:$false -DeletePermanently
$vm2 | remove-vm -Confirm:$false -DeletePermanently