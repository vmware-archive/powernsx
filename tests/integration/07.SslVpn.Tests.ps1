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

Describe "sslvpn" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for sslvpn edge deployment"
        $script:ds = $cl | get-datastore | Select-Object -first 1
        write-warning "Using datastore $ds for sslvpn edge deployment"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:ssledgename = "pester_ssl_edge1"
        $script:ssledgeIp1 = "1.1.1.1"
        $script:ssledgeIp2 = "2.2.2.2"
        $script:Password = "VMware1!VMware1!"
        $script:tenant = "pester_ssl_tenant1"
        $script:testls1name = "pester_ssl_ls1"
        $script:testls2name = "pester_ssl_ls2"
        $script:ippoolrange = "10.0.0.10-10.0.0.254"
        $script:primarydns = "8.8.8.8"
        $script:secondarydns = "8.8.4.4"
        $script:dnssuffix = "corp.local"
        $script:winsserver = "1.2.3.4"
        $script:gateway = "10.0.0.1"
        $script:netmask = "255.255.255.0"
        $script:notificationString =  "PowerNSX Pester Test"
        $script:forcedTimeout = "180"
        $script:sessionIdleTimeout = "30"
        $script:loglevel = "debug"
        $script:serverPort = "443"

        #Logical Switch
        $script:testls1 = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $testls1name
        $script:testls2 = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $testls2name

        #Create Edge
        $vnic0 = New-NsxEdgeInterfaceSpec -index 0 -Type uplink -Name "vNic0" -ConnectedTo $testls1 -PrimaryAddress $ssledgeIp1 -SubnetPrefixLength 24
        $script:sslEdge = New-NsxEdge -Name $ssledgename -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -hostname "pester-ssl-edge1"

    }

    Context "sslvpn" {


        it "Can configure sslvpn" {

            get-nsxedge $ssledgename | Get-NsxSslVpn | Set-NsxSslVpn -EnableCompression `
                -ForceVirtualKeyboard -RandomizeVirtualkeys -preventMultipleLogon `
                -ClientNotification $notificationstring -EnablePublicUrlAccess `
                -ForcedTimeout $forcedTimeout -SessionIdleTimeout $sessionIdleTimeout -ClientAutoReconnect -ClientUpgradeNotification `
                -EnableLogging -LogLevel $loglevel -Enable_AES128_SHA -ServerAddress $sslEdgeIp1 -ServerPort $serverport -Confirm:$false
            $sslvpn = get-nsxedge $ssledgename | Get-NsxSslVpn
            $sslvpn | should not be $null
            $sslvpn.enabled | should be "false"
            $sslvpn.advancedConfig.enableCompression | should be "true"
            $sslvpn.advancedConfig.forceVirtualKeyboard | should be "true"
            $sslvpn.advancedConfig.randomizeVirtualkeys | should be "true"
            $sslvpn.advancedConfig.preventMultipleLogon | should be "true"
            $sslvpn.advancedConfig.ClientNotification | should be $notificationstring
            $sslvpn.advancedConfig.timeout.forcedTimeout | should be $forcedTimeout
            $sslvpn.advancedConfig.timeout.sessionIdleTimeout | should be $sessionIdleTimeout
            $sslvpn.clientConfiguration.autoReconnect | should be "true"
            $sslvpn.clientConfiguration.upgradeNotification | should be "true"
            $sslvpn.logging.enable | should be "true"
            $sslvpn.logging.loglevel | should be $loglevel
        }

        it "Can create an ippool" {
            get-nsxedge $ssledgename | get-nsxsslvpn | New-NsxSslVpnIpPool -IpRange `
                $ippoolrange -Netmask $netmask -Gateway $gateway -PrimaryDnsServer `
                $primarydns -SecondaryDnsServer $secondarydns -DnsSuffix $dnssuffix -WinsServer $winsserver
        }

        it "Can configure the default authentication server" {
            $authserver = Get-NsxEdge $ssledgename | Get-NsxSslVpn | New-NsxSslVpnAuthServer
            $authserver | should not be $null
        }

        it "Can enable sslvpn" {
            $sslvpn = get-nsxedge $ssledgename | Get-NsxSslVpn | Set-NsxSslVpn -Enabled -confirm:$false
            $sslvpn | should not be $null
            $sslvpn = get-nsxedge $ssledgename | Get-NsxSslVpn
            $sslvpn | should not be $null
            $sslvpn.enabled | should be "true"
        }

        it "Can disable sslvpn" {
            get-nsxedge $ssledgename | Get-NsxSslVpn | Set-NsxSslVpn -Enabled:$false -Confirm:$false
            $sslvpn = get-nsxedge $ssledgename | Get-NsxSslVpn
            $sslvpn.enabled | should be "false"
        }

        it "Can remove sslvpn" {
            get-nsxedge $ssledgename | Get-NsxSslVpn | Remove-NsxSslVpn -NoConfirm:$true
            $sslvpn = get-nsxedge $ssledgename | Get-NsxSslVpn
            $sslvpn | should not be $null
            $sslvpn.enabled | should be "false"
            $sslvpn.serverSettings | should be $null

        }
    }


    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        if ($pause) { read-host "pausing" }

        get-nsxedge $ssledgename | remove-nsxedge -confirm:$false
        start-sleep 5

        Get-NsxLogicalSwitch $testls1name | Remove-NsxLogicalSwitch -Confirm:$false
        Get-NsxLogicalSwitch $testls2name | Remove-NsxLogicalSwitch -Confirm:$false

        disconnect-nsxserver
    }
}
