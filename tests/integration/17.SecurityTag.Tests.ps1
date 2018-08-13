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
        Import-Module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"

        ## get some items for testing
        Write-Verbose -Verbose "Getting some SecurityTags and VMs for testing"
        $arrAllSecurityTags = Get-NsxSecurityTag
        ## get a security tag that has an assignment
        $script:SecurityTagWithAssignment = $arrAllSecurityTags | Where-Object {$_.vmCount -gt 0} | Select-Object -First 1
        ## get a security tag that has _no_ assignment
        $script:SecurityTagWithoutAssignment = $arrAllSecurityTags | Where-Object {$_.vmCount -eq 0} | Select-Object -First 1
        ## get a VM that has a security tag assigned
        $script:VMWithSecurityTagAssignment = ($script:SecurityTagWithAssignment | Get-NsxSecurityTagAssignment | Select-Object -First 1).VirtualMachine
        ## get a VM that has _no_ security tag assigned
        $script:VMWithoutSecurityTagAssignment = Get-VM | Where-Object {-not ($_ | Get-NsxSecurityTagAssignment)} | Select-Object -First 1
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
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        if ($pause) {Read-Host "pausing" }
        Disconnect-NsxServer
    } ## end AfterAll
} ## end Describe
