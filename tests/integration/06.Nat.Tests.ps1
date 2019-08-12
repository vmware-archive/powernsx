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

Describe "Edge NAT" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for nat edge deployment"
        $script:ds = $cl | get-datastore | Select-Object -first 1
        write-warning "Using datastore $ds for nat edge deployment"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:natedgename = "pester_nat_edge1"
        $script:natedgeIp1 = "1.1.1.1"
        $script:natedgeIp2 = "2.2.2.2"
        $script:Password = "VMware1!VMware1!"
        $script:tenant = "pester_nat_tenant1"
        $script:testls1name = "pester_nat_ls1"
        $script:testls2name = "pester_nat_ls2"

        #Logical Switch
        $script:testls1 = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $testls1name
        $script:testls2 = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $testls2name

        #Create Edge
        $vnic0 = New-NsxEdgeInterfaceSpec -index 0 -Type uplink -Name "vNic0" -ConnectedTo $testls1 -PrimaryAddress $natedgeIp1 -SubnetPrefixLength 24
        $script:natEdge = New-NsxEdge -Name $natedgename -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -hostname "pester-nat-edge1"

        $script:VersionLessThan630 = [version]$DefaultNsxConnection.Version -lt [version]"6.3.0"

    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxedge $natedgename | remove-nsxedge -confirm:$false
        start-sleep 5

        Get-NsxLogicalSwitch $testls1name | Remove-NsxLogicalSwitch -Confirm:$false
        Get-NsxLogicalSwitch $testls2name | Remove-NsxLogicalSwitch -Confirm:$false

        disconnect-nsxserver
    }

    BeforeEach {
        get-nsxedge $natedgename | get-nsxedgenat | get-nsxedgenatrule | remove-nsxedgenatrule -confirm:$false
    }

    AfterEach {
        if ( $pause ) {
            read-host "Pausing"
        }
    }

    it "Can enable NAT" {
        $nat = get-nsxedge $natedgename | get-nsxedgenat | set-nsxedgenat -enabled -confirm:$false
        $nat | should not be $null
        $nat = get-nsxedge $natedgename | get-nsxedgenat
        $nat | should not be $null
        $nat.enabled | should be "true"
    }

    it "Can create a tcp dnat rule" {
        $rule = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action dnat -Protocol tcp -Description "testing dnat from powernsx" -LoggingEnabled -Enabled -OriginalPort 1234 -TranslatedPort 1234
        $rule | should not be $null
        $rule = get-nsxedge $natedgename | get-nsxedgenat | Get-NsxEdgeNatRule
        @($rule).count | should be 1
        $rule.action | should be dnat
        $rule.vnic | should be 0
        $rule.originalAddress | should be 1.2.3.4
        $rule.translatedAddress | should be 2.3.4.5
        $rule.protocol | should be tcp
        $rule.loggingEnabled | should be true
        $rule.originalPort | should be 1234
        $rule.translatedPort | should be 1234
    }

    it "Can create an icmp dnat rule" {
        $rule = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action dnat -Protocol icmp -Description "testing icmp dnat from powernsx" -LoggingEnabled -Enabled -icmptype any
        $rule | should not be $null
        $rule = get-nsxedge $natedgename | get-nsxedgenat | Get-NsxEdgeNatRule
        @($rule).count | should be 1
        $rule.action | should be dnat
        $rule.vnic | should be 0
        $rule.originalAddress | should be 1.2.3.4
        $rule.translatedAddress | should be 2.3.4.5
        $rule.protocol | should be icmp
        $rule.icmpType | should be any
        $rule.loggingEnabled | should be true
    }

    it "Can create an snat rule" {
        $rule = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 2.3.4.5 -TranslatedAddress 1.2.3.4 -action snat -Description "testing snat from powernsx" -LoggingEnabled -Enabled
        $rule | should not be $null
        $rule = get-nsxedge $natedgename | get-nsxedgenat | Get-NsxEdgeNatRule
        @($rule).count | should be 1
        $rule.action | should be snat
        $rule.vnic | should be 0
        $rule.translatedAddress | should be 1.2.3.4
        $rule.originalAddress | should be 2.3.4.5
        $rule.loggingEnabled | should be true
    }

    it "Can remove a single nat rule" {
        $rule1 = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action snat -Description "testing remove single nat rule from powernsx" -LoggingEnabled -Enabled
        $rule2 = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action dnat -Protocol icmp -Description "testing remove single nat rule from powernsx" -LoggingEnabled -Enabled -icmptype any
        $rule1 | should not be $null
        $rule2 | should not be $null
        $rules = get-nsxedge $natedgename | get-nsxedgenat | get-nsxedgenatrule
        @($rules).count | should be 2
        $rule = get-nsxedge $natedgename | get-nsxedgenat | get-nsxedgenatrule -RuleId $rule1.ruleId
        $rule.ruleId | should be $rule1.ruleId
        $rule | remove-nsxedgenatrule -confirm:$false | should be $null
        $rules = get-nsxedge $natedgename | get-nsxedgenat | get-nsxedgenatrule
        @($rules).count | should be 1
        $rules.ruleId | should be $rule2.ruleId
    }

    it "Can remove all nat rules" {
        $rule1 = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action snat -Description "testing remove all nat rules from powernsx" -LoggingEnabled -Enabled
        $rule2 = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -Vnic 0 -OriginalAddress 1.2.3.4 -TranslatedAddress 2.3.4.5 -action dnat -Protocol icmp -Description "testing remove all nat rules from powernsx" -LoggingEnabled -Enabled -icmptype any
        $rule1 | should not be $null
        $rule2 | should not be $null
        $rules = get-nsxedge $natedgename | get-nsxedgenat | get-nsxedgenatrule
        @($rules).count | should be 2
        get-nsxedge $natedgename | get-nsxedgenat | get-nsxedgenatrule | remove-nsxedgenatrule -confirm:$false| should be $null
        get-nsxedge $natedgename | get-nsxedgenat | get-nsxedgenatrule | should be $null
    }

    it "Can create an snat rule (with snatMatchDestinationAddress and snatMatchDestinationPort) on NSX -ge 6.3.0" -Skip:$VersionLessThan630 {
        $rule = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -action snat -OriginalAddress 192.168.44.0/24 -TranslatedAddress 198.51.100.1 -protocol tcp -snatMatchDestinationAddress 192.168.23.0/24 -snatMatchDestinationPort 22
        $rule = get-nsxedge $natedgename | get-nsxedgenat | Get-NsxEdgeNatRule
        @($rule).count | should be 1
        $rule.action | should be snat
        $rule.translatedAddress | should be 198.51.100.1
        $rule.originalAddress | should be "192.168.44.0/24"
        $rule.snatMatchDestinationAddress | should be "192.168.23.0/24"
        $rule.snatMatchDestinationPort | should be "22"
    }

    it "Can create an dnat rule (with dnatMatchSourceAddress and dnatMatchSourcePort) on NSX -ge 6.3.0" -Skip:$VersionLessThan630 {
        $rule = get-nsxedge $natedgename | get-nsxedgenat | new-nsxedgenatrule -action dnat -OriginalAddress 198.51.100.1 -TranslatedAddress 192.168.23.1 -protocol tcp -dnatMatchSourceAddress 192.168.44.0/24 -dnatMatchSourcePort 1024
        $rule = get-nsxedge $natedgename | get-nsxedgenat | Get-NsxEdgeNatRule
        @($rule).count | should be 1
        $rule.action | should be dnat
        $rule.translatedAddress | should be 192.168.23.1
        $rule.originalAddress | should be "198.51.100.1"
        $rule.dnatMatchSourceAddress | should be "192.168.44.0/24"
        $rule.dnatMatchSourcePort | should be "1024"
    }
}
