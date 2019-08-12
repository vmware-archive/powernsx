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

Describe "Edge DNS" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for clustery stuff"
        $script:ds = $cl | get-datastore | Select-Object -first 1
        write-warning "Using datastore $ds for datastorey stuff"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:dnsedge1name = "pester-dns-edge1"
        $script:dnsedge1ipuplink = "1.1.1.1"
        $script:password = "VMware1!VMware1!"
        $script:dnsuplinklsname = "pester_dns_uplink_ls"
        $script:dnsinternallsname = "pester_dns_internal_ls"

        #Create Logical Switch
        $script:dnsuplinkls = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $dnsuplinklsname
        $script:dnsinternalls = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $dnsinternallsname

        #Create Edge Interface
        $vnic0 = New-NsxEdgeInterfaceSpec -index 0 -Type uplink -Name "vNic0" -ConnectedTo $dnsuplinkls -PrimaryAddress $dnsedge1ipuplink -SubnetPrefixLength 24

        #Create Edge
        $script:dnsEdge = New-NsxEdge -Name $dnsedge1name -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -enablessh -hostname $dnsedge1name

    }

    Context "dns" {

        #Group related tests together.

        it "Can retrieve DNS Config" {
            $dns= Get-NsxEdge $dnsedge1name | Get-NsxDns
            $dns.enabled | should be false
            $dns.cacheSize | should be 16
            $dns.dnsViews.dnsView.forwarders | should be $null
            $dns.logging.enable | should be false
            $dns.logging.loglevel | should be "info"
        }

        it "Configure DNS Server" {
            #set DNS Server to 192.0.2.2
            Get-NsxEdge $dnsedge1name | Get-NsxDns | Set-NsxDns -DNSServer 192.0.2.2
            #Check the DNS Server value
            (Get-NsxEdge $dnsedge1name | Get-NsxDns).dnsViews.dnsview.forwarders.ipaddress | should be "192.0.2.2"
        }

        it "Enable DNS Server" {
            #Enabled Server
            Get-NsxEdge $dnsedge1name | Get-NsxDns | Set-NsxDns -Enabled
            #Check if the DNS Server is enable
            (Get-NsxEdge $dnsedge1name | Get-NsxDns).enabled | should be true
        }

        it "Change cacheSize" {
            #Change cacheSize to 32
            Get-NsxEdge $dnsedge1name | Get-NsxDns | Set-NsxDns -cacheSize 32
            #Check cacheSize is 32 now
            (Get-NsxEdge $dnsedge1name | Get-NsxDns).cacheSize | should be 32
        }

        it "Enable logging" {
            #Enable logging
            Get-NsxEdge $dnsedge1name | Get-NsxDns | Set-NsxDns -EnableLogging
            #Check DNS logging
            (Get-NsxEdge $dnsedge1name | Get-NsxDns).logging.enable | should be true
        }

        it "Change logging level" {
            #Change level to Debug
            Get-NsxEdge $dnsedge1name | Get-NsxDns | Set-NsxDNS -LogLevel debug
            #Check DNS Log Level
            (Get-NsxEdge $dnsedge1name | Get-NsxDns).logging.loglevel | should be "debug"
        }

        it "Configure multiple DNS Server" {
            #set DNS Server to 192.0.2.3 and 192.0.2.4
            Get-NsxEdge $dnsedge1name | Get-NsxDns | Set-NsxDns -DNSServer 192.0.2.3, 192.0.2.4
            #Check the DNS Server value
            $dns = Get-NsxEdge $dnsedge1name | Get-NsxDns
            $dns.dnsViews.dnsview.forwarders.ipaddress[0] | should be "192.0.2.3"
            $dns.dnsViews.dnsview.forwarders.ipaddress[1] | should be "192.0.2.4"
        }

        it "Remove DNS Config" {
            #Remove ALL DNS config
            Get-NsxEdge $dnsedge1name | Get-NsxDns | Remove-NsxDns -NoConfirm:$true
            #Check DNS Log Level
            $dns= Get-NsxEdge $dnsedge1name | Get-NsxDns
            $dns.enabled | should be false
            $dns.cacheSize | should be 16
            $dns.dnsViews.dnsView.forwarders | should be $null
            $dns.logging.enable | should be false
            $dns.logging.loglevel | should be "info"
        }

    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxedge $dnsedge1name | remove-nsxedge -confirm:$false
        start-sleep 5

        Get-NsxLogicalSwitch $dnsuplinklsname | Remove-NsxLogicalSwitch -Confirm:$false
        Get-NsxLogicalSwitch $dnsinternallsname | Remove-NsxLogicalSwitch -Confirm:$false

        disconnect-nsxserver
    }
}
