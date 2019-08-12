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
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for clustery stuff"
        $script:ds = $cl | get-datastore | Select-Object -first 1
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
        $script:ipsecuplinkls = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $ipsecuplinklsname
        $script:ipsecinternalls = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $ipsecinternallsname

        #Create Edge Interface
        $vnic0 = New-NsxEdgeInterfaceSpec -index 0 -Type uplink -Name "vNic0" -ConnectedTo $ipsecuplinkls -PrimaryAddress $ipsecedge1ipuplink -SubnetPrefixLength 24

        #Create Edge
        $script:ipsecEdge = New-NsxEdge -Name $ipsecedge1name -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -enablessh -hostname $ipsecedge1name

    }

    Context "ipsec" {

        #Group related tests together.

        it "Get IPsec stats" {
            (Get-NsxEdge ipsecedge1name | Get-NsxIPsecStats).timestamp | should not be null
        }

        it "Can retrieve IPsec Config" {
            $ipsec = Get-NsxEdge $ipsecedge1name | Get-NsxIPsec
            $ipsec.enabled | should be false
            $ipsec.global | should not be $null
            $ipsec.logging.enable | should be true
            $ipsec.logging.loglevel | should be "warning"
        }

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

        it "Add First IPsec Site (with PSK)" {
            #Add Ipsec with default settings
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Add-NsxIPsecSite -localID localid1 -localIP 1.1.1.1 -localSubnet 192.0.2.0/24 -peerId peerid1 -peerIP 2.2.2.2 -peerSubnet 198.51.100.0/24 -psk VMware1!
            #Check IPsec site config
            $ipsec = (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec)
            $ipsecSite1 = $ipsec.sites.site | Where-Object {$_.localid -eq "localid1"}
            $ipsecSite1 | Should not be $null
            $ipsecSite1.localid | should be "localid1"
            $ipsecSite1.localip | should be "1.1.1.1"
            $ipsecSite1.localSubnets.subnet -contains "192.0.2.0/24" | should be true
            $ipsecSite1.peerid | should be "peerid1"
            $ipsecSite1.peerip | should be "2.2.2.2"
            $ipsecSite1.peerSubnets.subnet -contains "198.51.100.0/24" | should be true
        }

        it "Enable IPsec Server" {
            #Enabled Server
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Set-NsxIPsec -Enabled
            #Check if the ipsec Server is enable
            (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec).enabled | should be true
        }

        it "Add Second IPsec Site (with PSK and disable pfs but use dh2 and encryption AES256)" {
            #Add second IPsec
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Add-NsxIPsecSite -localID localid2 -localIP 1.1.1.1 -localSubnet 192.0.2.0/24 -peerId peerid2 -peerIP 3.3.3.3 -peerSubnet 203.0.113.0/24 -psk VMware1! -enablepfs:$false -dhgroup dh2 -encryptionAlgorithm AES256
            #Check IPsec (second) site config
            $ipsec = (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec)
            $ipsecSite2 = $ipsec.sites.site | Where-Object {$_.localid -eq "localid2"}
            $ipsecSite2 | Should not be $null
            $ipsecSite2.localid | should be "localid2"
            $ipsecSite2.localip | should be "1.1.1.1"
            $ipsecSite2.localSubnets.subnet -contains "192.0.2.0/24" | should be true
            $ipsecSite2.peerid | should be "peerid2"
            $ipsecSite2.peerip | should be "3.3.3.3"
            $ipsecSite2.peerSubnets.subnet -contains "203.0.113.0/24" | should be true
            $ipsecSite2.enablePfs | should be "false"
            $ipsecSite2.dhgroup | should be "dh2"
            $ipsecSite2.encryptionAlgorithm | should be "AES256"
        }

        it "Config global IPsec settings" {
            #Specify a serviceCertificate
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Set-NsxIPsec -serviceCertificate certificate-1
            #Check if serviceCertificate it is set
            (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec).global.serviceCertificate | should be "certificate-1"
        }

        it "Add Third IPsec Site (with certificate)" {
            #Add third IPsec
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Add-NsxIPsecSite -localID localid3 -localIP 1.1.1.1 -localSubnet 192.0.2.0/24 -peerId cn=peerid -peerIP 4.4.4.4 -peerSubnet 192.168.44.0/24 -authenticationMode x.509
            #Check IPsec (third) site config
            $ipsec = (Get-NsxEdge $ipsecedge1name | Get-NsxIPsec)
            $ipsecSite3 = $ipsec.sites.site | Where-Object {$_.localid -eq "localid3"}
            $ipsecSite3 | Should not be $null
            $ipsecSite3.localid | should be "localid3"
            $ipsecSite3.localip | should be "1.1.1.1"
            $ipsecSite3.localSubnets.subnet -contains "192.0.2.0/24" | should be true
            $ipsecSite3.peerid | should be "cn=peerid"
            $ipsecSite3.peerip | should be "4.4.4.4"
            $ipsecSite3.peerSubnets.subnet -contains "192.168.44.0/24" | should be true
            $ipsecSite3.enablePfs | should be "true"
            $ipsecSite3.dhgroup | should be "dh14"
            $ipsecSite3.authenticationMode | should be "x.509"
        }

        it "Remove IPsec Config" {
            #Remove ALL IPsec config
            Get-NsxEdge $ipsecedge1name | Get-NsxIPsec | Remove-NsxIPsec -NoConfirm:$true
            #Check if there is no longer configuration
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
