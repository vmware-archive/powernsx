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

#Exercises all security tag cmdlets functionality

#Setup

$Cluster = "Mgmt01"

$testVMName1 = "STapp01"
$testVMName2 = "STapp02"

$testSTName1 = "testST1"
$testSTName2 = "testST2"

$testST1 = Get-NsxSecurityTag $testSTName1
$testST2 = Get-NsxSecurityTag $testSTName2

$vm1 = new-vm -name $testVMName1 -ResourcePool ( Get-Cluster $Cluster | Get-ResourcePool Resources)
$vm2 = new-vm -name $testVMName2 -ResourcePool ( Get-Cluster $Cluster | Get-ResourcePool Resources)

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
$vm1 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Added"
Get-NsxSecurityTag $testSTName1 | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $vm1
$vm1 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Removed"
$vm1 | Get-NsxSecurityTagAssignment | Remove-NsxSecurityTagAssignment -confirm:$false
$vm1 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`n--- End Test 1 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 2 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to a single virtual machine"

write-host "`nSecurity Tags before"
$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Added"
$vm2 | New-NsxSecurityTagAssignment -ApplyTag -SecurityTag $TestST2 
$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Removed"
$TestSt2 | Get-NsxSecurityTagAssignment | Remove-NsxSecurityTagAssignment -confirm:$false
$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`n--- End Test 2 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 3 ---"
write-host -foregroundcolor Green "`nAdd and remove a multiple security tags to a single virtual machine"

write-host "`nSecurity Tags before"
$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Added"
$vm2 | New-NsxSecurityTagAssignment -ApplyTag -SecurityTag ( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } )
$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Removed"
( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } ) | Get-NsxSecurityTagAssignment | Remove-NsxSecurityTagAssignment -confirm:$false
$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`n--- End Test 3 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 4 ---"
write-host -foregroundcolor Green "`nAdd and remove a multiple security tags to a single virtual machine"

write-host "`nSecurity Tags before"
$vm1 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Added"
( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } ) | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $vm1
$vm1 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Removed"
$vm1 | Get-NsxSecurityTagAssignment | Remove-NsxSecurityTagAssignment -confirm:$false
$vm1 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`n--- End Test 4 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 5 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to multiple virtual machines"

write-host "`nSecurity Tags before"
$vm1,$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Added"
$vm1,$vm2 | New-NsxSecurityTagAssignment -ApplyTag -SecurityTag ( Get-NsxSecurityTag $testSTName2 )
$vm1,$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Removed"
Get-NsxSecurityTag $testSTName2  | Get-NsxSecurityTagAssignment | Remove-NsxSecurityTagAssignment -confirm:$false
$vm1,$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`n--- End Test 5 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 6 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to multiple virtual machines"

write-host "`nSecurity Tags before"
$vm1,$vm2  | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Added"
Get-NsxSecurityTag $testSTName2  | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $vm1,$vm2 
$vm1,$vm2 | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`nSecurity Tags Removed"
$vm1,$vm2  | Get-NsxSecurityTagAssignment | Remove-NsxSecurityTagAssignment -confirm:$false
$vm1,$vm2  | Get-NsxSecurityTagAssignment | select { $_.SecurityTag.name} , VirtualMachine

write-host "`n--- End Test 6 ---"
#


#Cleanup
Get-NsxSecurityTag $testSTName1 | Remove-NsxSecurityTag -confirm:$false
Get-NsxSecurityTag $testSTName2 | Remove-NsxSecurityTag -confirm:$false
$vm1 | remove-vm -Confirm:$false -DeletePermanently
$vm2 | remove-vm -Confirm:$false -DeletePermanently