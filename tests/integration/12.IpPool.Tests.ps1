#PowerNSX Test for IpPools
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


        # IP Pools

        $script:IpPoolName1 = "pester_pool_ippool1"
        $script:IpPoolGateway1 = "192.168.103.1"
        $script:IpPoolSubnetPrefix1 = "24"
        $script:DnsServer1 = "10.100.10.100"
        $script:DnsServer2 = "100.10.100.10"
        $script:DnsSuffix1 = "powernsx.pester.test"
        $script:StartAddress1 = "192.168.103.100"
        $script:EndAddress1 = "192.168.103.110"

    }
    
    AfterAll { 
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver 
        #Remove-Variable -scope global -name "Conn"
    }




  Context "Create IP Pools"{

        it "Can create an IP Pool with IP configuration"{
            #Create Object
            $IpPool1 = New-NsxIpPool -name $IpPoolName1 -gateway $IpPoolGateway1 -StartAddress $StartAddress1 -EndAddress $EndAddress1 -SubnetPrefixLength $IpPoolSubnetPrefix1 
            #Object creation test
            $IpPool1 | should not be $null
            #Base object tests
            $IpPool1.objectTypeName | should be "IpAddressPool"
            $IpPool1.type.typeName | should be "IpAddressPool"
            #Mandatory Object fields
            $IpPool1.name | should be $IpPoolName1
            $IpPool1.gateway | should be $IpPoolGateway1
            $IpPool1.prefixLength | should be $IpPoolSubnetPrefix1
            $IpPool1.ipRanges.ipRangeDto.startAddress | should be $StartAddress1
            $IpPool1.ipRanges.ipRangeDto.endAddress | should be $EndAddress1
            $IpPool1.totalAddressCount | should not be 0
            $IpPool1.subnetId | should not be $null

        }

        it "Can create an IP Pool with IP and DNS configuration"{
            $IpPool1 = New-NsxIpPool -name $IpPoolName1 -gateway $IpPoolGateway1 -StartAddress $StartAddress1 -EndAddress $EndAddress1 -SubnetPrefixLength $IpPoolSubnetPrefix1  
            #Object creation test
            $IpPool1 | should not be $null
            #Base object tests
            $IpPool1.objectTypeName | should be "IpAddressPool"
            $IpPool1.type.typeName | should be "IpAddressPool"
            #Mandatory Object fields
            $IpPool1.name | should be $IpPoolName1
            $IpPool1.gateway | should be $IpPoolGateway1
            $IpPool1.prefixLength | should be $IpPoolSubnetPrefix1
            $IpPool1.ipRanges.ipRangeDto.startAddress | should be $StartAddress1
            $IpPool1.ipRanges.ipRangeDto.endAddress | should be $EndAddress1
            $IpPool1.totalAddressCount | should not be 0
            $IpPool1.subnetId | should not be $null
            #Additional Object fields
            $IpPool1.dnsSuffix | should be $DnsSuffix1
            $ipPool1.dnsServer1 | should be $DnsServer1
            $ipPool1.dnsServer2 | should be $DnsServer2

        }
        
        
        
        BeforeEach {
            #create new sections for each test.

            #$script:IpSet1 = New-NsxIpSet $IpSetName1
        }
        AfterEach {
            #tear down new sections after each test.
            # read-host "waiting"
            if ($pause) { read-host "pausing" }
            Get-NsxIpPool $IpPoolName1 | Remove-NsxIpPool -Confirm:$false
        }
    }

    Context "Update IP Pools" {
        # To be determined
    }

    # Context "Security Groups" { 

    #     #Group related tests together.

    #     it "Can create a Security Group" { 

    #         #do something and then make an assertion about what it should be
    #         $SecurityGroup1 = New-NsxSecurityGroup $SecurityGroup1Name

    #         #remember to get from api rather than use returned val - this test successful creation, not just return
    #         Get-NsxSecurityGroup $SecurityGroup1Name | should not be $null

    #         #can make multiple assertions to improve test value.
    #         $SecurityGroup1.name | should be "$SecurityGroup1Name"
    #     }

    #     it "Can create a security group and " {
    #         ...
    #     }
    # }

    
}