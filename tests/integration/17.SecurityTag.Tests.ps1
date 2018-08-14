#PowerNSX Test template.
#Nick Bradford : nbradford@vmware.com

#Because PowerNSX is an API consumption tool, its test framework is limited to
#exercising cmdlet functionality against a functional NSX and vSphere API
#If you disagree with this approach - feel free to start writing mocks for all
#potential API reponses... :)

#In the meantime, the test format is not as elegant as normal TDD, but Ive made some effort to get close to this.
#Each functional area in NSX should have a separate test file.

#Try to group related tests in contexts.  Especially ones that rely on configuration done in previous tests
#Try to make tests as standalone as possible, but generally round trips to the API are expensive, so bear in mind
#the time spent recreating configuration created in previous tests just for the sake of keeping test isolation.

#Try to put all non test related setup and tear down in the BeforeAll and AfterAll sections.  ]
#If a failure in here occurs, the Describe block is not executed.

#########################
#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe -Name "SecurityTagAssignment" -Tag "Get" -Fixture {
    BeforeAll {
        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        Write-Verbose -Verbose "Performing setup tasks for SecurityTag tests"
        Import-Module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"

        ## GUID to use as suffix for some temporary vSphere/NSX objects, so as to prevent any naming conflict with existing objects
        $strSuffixGuid = [System.Guid]::NewGuid().Guid.Replace("-","")
        Write-Verbose -Verbose "Using following GUID as suffix on temporary objects' names for ensuring unique object naming: '$strSuffixGuid'"

        ## get some spot in which to create a couple of empty VMs, for use in tests (checking for SecurityTag assignments, for example)
        $script:oVMHostToUse = Get-VMHost -State Connected | Get-Random
        Write-Verbose -Verbose "Using VMHost '$oVMHostToUse' for temporary VM creation"
        ## get the datastore mounted on this VMHost as readWrite (where .ExtensionData.Host.Key is this VMHost's ID, and where .ExtensionData.Host.MountInfo.AccessMode is "readWrite") and with the most FreespaceGB, on which to create some test VMs
        $script:oDStoreToUse = $oVMHostToUse | Get-Datastore | Where-Object {$_.ExtensionData.Host | Where-Object {$_.Key -eq $oVMHostToUse.Id -and ($_.MountInfo.AccessMode -eq "readWrite")}} | Sort-Object -Property FreespaceGB -Descending | Select-Object -First 1
        Write-Verbose -Verbose "Using datastore '$oDStoreToUse' for temporary VM creation"
        ## hashtable of objects that the tests will create; hashtable will then be used as the colleciton of objects to delete at clean-up time
        $script:hshTemporaryItemsToDelete = @{NsxSecurityTag = @(); VM = @()}

        ## get some items for testing
        Write-Verbose -Verbose "Getting some SecurityTags and VMs for testing (making some Tags/VMs in the process)"
        $script:hshTemporaryItemsToDelete["NsxSecurityTag"] = 0..1 | Foreach-Object {New-NsxSecurityTag -Name "pesterTestTag${_}_toDelete-$strSuffixGuid" -Description "test Tag for Pester testing"}
        $script:hshTemporaryItemsToDelete["VM"] = 0..1 | Foreach-Object {New-VM -Name "pesterTestVM${_}_toDelete-$strSuffixGuid" -Description "test VM for Pester testing" -VMHost $oVMHostToUse -Datastore $oDStoreToUse}

        ## make a security tag assignment
        New-NsxSecurityTagAssignment -VirtualMachine $hshTemporaryItemsToDelete["VM"][0] -ApplyToVm -SecurityTag $hshTemporaryItemsToDelete["NsxSecurityTag"][0]
        ## a security tag that has an assignment
        $script:SecurityTagWithAssignment = $hshTemporaryItemsToDelete["NsxSecurityTag"][0]
        ## a security tag that has _no_ assignment
        $script:SecurityTagWithoutAssignment = $hshTemporaryItemsToDelete["NsxSecurityTag"][1]
        ## a VM that has a security tag assigned
        $script:VMWithSecurityTagAssignment = $hshTemporaryItemsToDelete["VM"][0]
        ## a VM that has _no_ security tag assigned
        $script:VMWithoutSecurityTagAssignment = $hshTemporaryItemsToDelete["VM"][1]
    } ## end BeforeAll

    Context -Name "Get-NSXSecurityTagAssignment (by SecurityTag)" -Fixture {
        It -Name "Gets security tag assignment by security tag" -Test {
            $bGetsSecurityTagAssignmentBySecurityTag = $null -ne ($script:SecurityTagWithAssignment | Get-NSXSecurityTagAssignment)
            $bGetsSecurityTagAssignmentBySecurityTag | Should Be $true
        } ## end it

        It -Name "Gets `$null when getting security tag assignment by security tag that has no assignments" -Test {
            $bGetsNullForSecurityTagAssignmentBySecurityTagWithNoAssignment = $null -eq ($script:SecurityTagWithoutAssignment | Get-NSXSecurityTagAssignment)
            $bGetsNullForSecurityTagAssignmentBySecurityTagWithNoAssignment | Should Be $true
        } ## end it
    } ## end context

    Context -Name "Get-NSXSecurityTagAssignment (by VirtualMachine)" -Fixture {
        It -Name "Gets security tag assignment by VM" -Test {
            $bGetsSecurityTagAssignmentByVirtualMachine = $null -ne ($script:VMWithSecurityTagAssignment | Get-NSXSecurityTagAssignment)
            $bGetsSecurityTagAssignmentByVirtualMachine | Should Be $true
        } ## end it

        It -Name "Gets `$null when getting security tag assignment by VM that has no assignments" -Test {
            $bGetsNullForSecurityTagAssignmentByVMWithNoAssignment = $null -eq ($script:VMWithoutSecurityTagAssignment | Get-NSXSecurityTagAssignment)
            $bGetsNullForSecurityTagAssignmentByVMWithNoAssignment | Should Be $true
        } ## end it
    } ## end context

    AfterAll {
        # AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        # Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        # We kill the connection to NSX Manager here.

        if ($pause) {Read-Host "pausing" }
        ## remove the temporary, test SecurityTags
        $hshTemporaryItemsToDelete["NsxSecurityTag"] | Foreach-Object {Remove-NsxSecurityTag -SecurityTag $_ -Confirm:$false -Verbose}
        ## remove the temporary, test VMs (first make sure that there are some to remove)
        if (($hshTemporaryItemsToDelete["VM"] | Measure-Object).Count -gt 0) {Remove-VM -VM $hshTemporaryItemsToDelete["VM"] -DeletePermanently -Confirm:$false -Verbose}

        Disconnect-NsxServer
    } ## end AfterAll
} ## end Describe
