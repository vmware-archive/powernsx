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

Describe "Edge IPsec" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefMgrCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | select -first 1
        write-warning "Using cluster $cl for clustery stuff"
        $script:ds = $cl | get-datastore | select -first 1
        write-warning "Using datastore $ds for datastorey stuff"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:ipsecedge1name = "pester-ipsec-edge1"
        $script:ipsecedge1ipuplink = "1.1.1.1"
        $script:password = "VMware1!VMware1!"
        $script:ipsecuplinklsname = "pester_ipsec_uplink_ls"
        $script:ipsecinternallsname = "pester_ipsec_internal_ls"

        #Create Logical Switch
        $script:ipsecuplinkls = Get-NsxTransportZone -LocalOnly | select -first 1 | New-NsxLogicalSwitch $ipsecuplinklsname
        $script:ipsecinternalls = Get-NsxTransportZone -LocalOnly | select -first 1 | New-NsxLogicalSwitch $ipsecinternallsname

        #Create Edge Interface
        $vnic0 = New-NsxEdgeInterfaceSpec -index 0 -Type uplink -Name "vNic0" -ConnectedTo $ipsecuplinkls -PrimaryAddress $ipsecedge1ipuplink -SubnetPrefixLength 24

        #Create Edge
        $script:sslEdge = New-NsxEdge -Name $ipsecedge1name -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -enablessh -hostname $ipsecedge1name

    }

    Context "ipsec" {

        #Group related tests together.

        it "Can retrieve IPsec Config" {
            $ipsec = Get-NsxEdge $ipsecedge1name | Get-NsxIPsec
            $ipsec.enabled | should be false
            $ipsec.global | should not be $null
            $ipsec.logging.enable | should be true
            $ipsec.logging.loglevel | should be "warning"
        }

#        it "Enable IPsec Server" {
#            #Enabled Server
#            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Set-NsxIPsec -Enabled
#            #Check if the ipsec Server is enable
#            (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec).enabled | should be true
#        }

        it "Disabled logging" {
            #Disable logging
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Set-NsxIPsec -EnableLogging:$false
            #Check ipsec logging
            (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec).logging.enable | should be false
        }

        it "Change logging level" {
            #Change level to Debug
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Set-NsxIPsec -LogLevel debug
            #Check ipsec Log Level
            (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec).logging.loglevel | should be "debug"
        }

        it "Remove IPsec Config" {
            #Remove ALL IPsec config
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Remove-NsxIPsec -NoConfirm:$true
            #Check IPsec Log Level
            $ipsec = Get-NsxEdge $ipsecedge1name | Get-NsxIPsec
            $ipsec.enabled | should be false
            $ipsec.global | should not be $null
            $ipsec.logging.enable | should be true
            $ipsec.logging.loglevel | should be "warning"
        }

    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxedge $ipsecedge1name | remove-nsxedge -confirm:$false
        start-sleep 5

        Get-NsxLogicalSwitch $ipsecuplinklsname | Remove-NsxLogicalSwitch -Confirm:$false
        Get-NsxLogicalSwitch $ipsecinternallsname | Remove-NsxLogicalSwitch -Confirm:$false

        disconnect-nsxserver
    }
}
