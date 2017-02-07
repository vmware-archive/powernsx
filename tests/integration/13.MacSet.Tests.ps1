#PowerNSX Test for MAC Sets
#Anthony Burke : aburke@vmware.com

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

Describe "Logical Objects" { 

    BeforeAll { 

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
       
        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:Conn = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore" -DefaultConnection:$false -VIDefaultConnection:$false
        $script:cl = get-cluster | select -first 1
        write-warning "Using cluster $cl for clustery stuff"
        $script:ds = $cl | get-datastore | select -first 1
        write-warning "Using datastore $ds for datastorey stuff"

        #Put any script scope variables you need to reference in your tests.  
        #For naming items that will be created in NSX, use a unique prefix 
        #pester_<testabbreviation>_<objecttype><uid>.  example: 

      

        # IP Sets
        $script:IpSetName1 = "pester_ip_ipset1"
        $script:IpSetSubnet1 = "192.168.0.0/24"
        $script:IpSetRange1 = "1.1.1.10-1.1.1.20"
        $script:IpSetHost1 = "1.1.1.1/32"

        # MAC Sets

        $script:MacSetName1 = "pester_mac_macset1"
        $script:MacSetMac1 = "00:00:00:00:00:00"
        $script:MacSetMac1 = "AA:00:00:00:00:AA"

        }

    Context "MAC Sets" {
        # We have to make an MAC Set inline here. Currently there is no Set-NsxMACSet. Once a Set cmdlet is made then BeforeEach should
        # be used to create an MAC Set and SET used to add "values"."
        it "Can create a MAC Set"{
            #Test base object
            $MacSet1 = New-NsxMacSet $MacSetName1
            $MacSet1 | should not be $null
            $MacSet1.type.typename | should be "MACSet"
            $MacSet1.objectTypeName | should be "MACSet"
        }

        it "Can create a MAC Set with a single MAC Address"{
            #Test base object
            $MacSet1 = New-NsxMacSet $MacSetName1 -MacAddresses "$MacSetMac1"
            $MacSet1 | should not be $null
            $MacSet1.type.typename | should be "MACSet"
            $MacSet1.objectTypeName | should be "MACSet"
            #Test object unique values
            $MacSet1 = Get-NsxMacSet $MacSetName1
            $MacSet1.value | should be "$MacSetMac1"
        }

        it "Can create a MAC Set with mutiple MAC Addresses"{
              #Test base object
            $MacSet1 = New-NsxMacSet $MacSetName1 -MacAddresses $MacSetMac1,$MacSetMac2
            $MacSet1 | should not be $null
            $MacSet1.type.typename | should be "MACSet"
            $MacSet1.objectTypeName | should be "MACSet"
            #Test object unique values
            $MacSet1 = Get-NsxMacSet $MacSetName1
            $MacSet1.value | should be "$MacSetMac1,$MacSetMac2"
        }

        it "Can create a MAC Set with a global scope"{

        }

        BeforeEach {
            #create new sections for each test.

            #$script:IpSet1 = New-NsxIpSet $IpSetName1
        }
        AfterEach {
            #tear down new sections after each test.
            # read-host "waiting"
            if ($pause) { read-host "pausing" }
            Get-NsxMacSet $MacSetName1 | Remove-NsxMacSet -Confirm:$false
        }

    }
    
    AfterAll { 
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver 
        #Remove-Variable -scope global -name "Conn"
    }