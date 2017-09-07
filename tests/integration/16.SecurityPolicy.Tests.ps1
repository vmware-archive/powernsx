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

Describe "Security Policies" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefMgrCred -ViWarningAction "Ignore"
        # $script:cl = get-cluster | select -first 1
        # write-warning "Using cluster $cl for clustery stuff"
        # $script:ds = $cl | get-datastore | select -first 1
        # write-warning "Using datastore $ds for datastorey stuff"


    }

    Context "Policy retrieval" {

        it "Can retreive a security policy" {
            
            #The system policies should always exist, so we just get them.
            $AllPolicy = Get-NsxSecurityPolicy -IncludeHidden
            $AllPolicy | should not be $null
            $FirstPolicy = $AllPolicy | Select-Object -First 1
            $FirstPolicy.objectId | should match "policy-\d*" 
        }

        it "Can retreive the highest precendence number in use" { 
            Get-NsxSecurityPolicyHighestUsedPrecendence | should match "\d*"
            #System policies make the lowest posible value for a default system 3300
            Get-NsxSecurityPolicyHighestUsedPrecendence | should begreaterthan 3299
        }
        
    }

    Context "Something else interesting" {
        ...
    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver
    }
}
