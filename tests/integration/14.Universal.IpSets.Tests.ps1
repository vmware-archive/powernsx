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
If ( -not $PNSXTestNSXManager ) { 
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
} 

Describe "Universal Object Support" { 

    BeforeAll { 

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
       
        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore"
        # $script:Conn = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore" -DefaultConnection:$false -VIDefaultConnection:$false
        # $script:cl = get-cluster | select -first 1
        # write-warning "Using cluster $cl for clustery stuff"
        # $script:ds = $cl | get-datastore | select -first 1
        # write-warning "Using datastore $ds for datastorey stuff"

        #Put any script scope variables you need to reference in your tests.  
        #For naming items that will be created in NSX, use a unique prefix 
        #pester_<testabbreviation>_<objecttype><uid>.  example: 
        $script:mynsxthing = "pester_lt_thing1"
        $script:name_prefix = "pester_universal_stuffs."

        $script:testIPSetName = $script:name_prefix + "ipset1"
        $script:testIPSetName2 = $script:name_prefix + "ipset2"
        $script:testIPs = "1.1.1.1,2.2.2.2"
        $script:testIPs2 = "1.1.1.0/24"

        #Clean up any existing ipsets from previous runs...
        #get-nsxipset | ? { $_.name -match $IpSetPrefix } | remove-nsxipset -confirm:$false

    }

    Context "NSX Manager" { 

        #Group related tests together.

        it "Can get current NSX Manager role" { 

            # This cmdlet hasn't been committed yet
            # $current = Get-NsxManagerRole

            # Test we actually get a valid response
            # Get-NsxManagerRole | should not be $null

        }

        it "Can set NSX Manager role" {
            # This cmdlet hasn't been committed yet
            # $current = Get-NsxManagerRole

            # $config = Set-NsxManagerRole -Role set-as-primary
            # $config | should not be $null
            # $config.role | should be "Primary"
        }
    }

    Context "Universal IpSet retrieval" {

        it "Can retreive an universal ipset by name" {

         }

        it "Can retreive an universal ipset by id" {

         }
    }

    Context "Successful universal IpSet Creation" {

        it "Can create an universal ipset with single address" {

        }

        it "Can create an universal ipset with range" {

        }

        it "Can create an universal ipset with CIDR" {

        }

        it "Can create an universal ipset and return an objectId only" {

         }
    }

    Context "Unsuccessful universal IpSet Creation" {

        it "Fails to create an universal ipset with invalid address" {

        }
    }


    Context "universal IpSet Deletion" {

        it "Can delete an universal ipset by object" {

        }

    }
    AfterAll { 
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver 
        Remove-Variable -scope global -name "conn"
    }
}