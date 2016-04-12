#Exercises all security tag cmdlets functionality

#Setup
$testVMName1 = "app01"
$testVMName2 = "app02"

$testSTName1 = "testST1"
$testSTName2 = "testST2"

$testST1 = Get-NsxSecurityTag $testSTName1
$testST2 = Get-NsxSecurityTag $testSTName2

if ( -not $testST1) {
    $testST1 = New-NsxSecurityTag $testSTName1
}

if ( -not $testST2) {
    $testST2 = New-NsxSecurityTag $testSTName2
}

$csvFileName = "sectagexport.csv"

# Test Cases
write-host -foregroundcolor Green "--- Start Test 1 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to a single virtual machine"

write-host "`nSecurity Tags before"
Get-VM $testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-NsxSecurityTag $testSTName1 | New-NsxSecurityTagAssignment -vm (Get-VM $testVMName1)
Get-VM $testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-VM $testVMName1 | Remove-NsxSecurityTagAssignment -tag (Get-NsxSecurityTag $testSTName1) -confirm:$false
Get-VM $testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 1 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 2 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to a single virtual machine"

write-host "`nSecurity Tags before"
Get-VM $testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-VM $testVMName2 | New-NsxSecurityTagAssignment -tag (Get-NsxSecurityTag $testSTName2) 
Get-VM $testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-NsxSecurityTag $testSTName2 | Remove-NsxSecurityTagAssignment -vm (Get-VM $testVMName2) -confirm:$false
Get-VM $testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 2 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 3 ---"
write-host -foregroundcolor Green "`nAdd and remove a multiple security tags to a single virtual machine"

write-host "`nSecurity Tags before"
Get-VM $testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-VM $testVMName2 | New-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } )
Get-VM $testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } ) | Remove-NsxSecurityTagAssignment -vm (Get-VM $testVMName2) -confirm:$false
Get-VM $testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 3 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 4 ---"
write-host -foregroundcolor Green "`nAdd and remove a multiple security tags to a single virtual machine"

write-host "`nSecurity Tags before"
Get-VM $testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } ) | New-NsxSecurityTagAssignment -vm (Get-VM $testVMName1)
Get-VM $testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-VM $testVMName1 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag | ? { $_.name -like "*testst*" } )  -confirm:$false
Get-VM $testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 4 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 5 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to multiple virtual machines"

write-host "`nSecurity Tags before"
Get-VM $testVMName2,$testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-VM $testVMName2,$testVMName1 | New-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 )
Get-VM $testVMName2,$testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-NsxSecurityTag $testSTName2  | Remove-NsxSecurityTagAssignment -vm (Get-VM $testVMName2,$testVMName1) -confirm:$false
Get-VM $testVMName2,$testVMName1 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 5 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 6 ---"
write-host -foregroundcolor Green "`nAdd and remove a single security tag to multiple virtual machines"

write-host "`nSecurity Tags before"
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-NsxSecurityTag $testSTName2  | New-NsxSecurityTagAssignment -vm (Get-VM $testVMName1,$testVMName2)
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-VM $testVMName1,$testVMName2 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 ) -confirm:$false
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 6 ---"
#
#
#
write-host -foregroundcolor Green "`n`n`n--- Start Test 7 ---"
write-host -foregroundcolor Green "`Testing NSX Security Tag Assignment export"

write-host "`nSecurity Tags before"
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Added"
Get-NsxSecurityTag $testSTName2  | New-NsxSecurityTagAssignment -vm (Get-VM $testVMName1,$testVMName2)
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nExporting csv file"
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | export-csv -path $csvFileName

write-host "`nSecurity Tags Removed"
Get-VM $testVMName1,$testVMName2 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 ) -confirm:$false
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nImporting security tag assignment from csv file"
New-NsxSecurityTagAssignment -csv -path $csvFileName

write-host "`nSecurity Tags imported"
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`nSecurity Tags Removed"
Get-VM $testVMName1,$testVMName2 | Remove-NsxSecurityTagAssignment -tag ( Get-NsxSecurityTag $testSTName2 ) -confirm:$false
Get-VM $testVMName1,$testVMName2 | Get-NsxSecurityTagAssignment | select name,securitytagname

write-host "`n--- End Test 7 ---"

#Cleanup
Get-NsxSecurityTag $testSTName1 | Remove-NsxSecurityTag -confirm:$false
Get-NsxSecurityTag $testSTName2 | Remove-NsxSecurityTag -confirm:$false