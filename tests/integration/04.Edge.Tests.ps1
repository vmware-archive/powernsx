#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Edge" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | select-object -first 1
        write-warning "Using cluster $cl for edge appliance deployment"
        $script:ds = $cl | get-datastore | select-object -first 1
        write-warning "Using datastore $ds for edge appliance deployment"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:name = "pester_e_edge1"
        $script:ls1_name = "pester_e_ls1"
        $script:ls2_name = "pester_e_ls2"
        $script:ls3_name = "pester_e_ls3"
        $script:ls4_name = "pester_e_ls4"
        $script:ls5_name = "pester_e_ls5"
        $pg1_name = "pester_e_pg1"
        $script:Ip1 = "1.1.1.1"
        $script:ip2 = "2.2.2.2"
        $script:ip3 = "3.3.3.3"
        $script:ip4 = "4.4.4.4"
        $script:ip5 = "5.5.5.5"
        $script:ip6 = "6.6.6.6"
        $script:dgaddress = "1.1.1.254"
        $script:staticroutenet = "20.20.20.0/24"
        $script:staticroutenexthop = "1.1.1.254"
        $script:OspfAreaId = "50"
        $script:RouterId = "1.1.1.1"
        $script:LocalAS = "1234"
        $script:bgpneighbour = "1.1.1.254"
        $script:RemoteAS = "2345"
        $script:bgpWeight = "10"
        $script:bgpWeight = "10"
        $script:bgpHoldDownTimer = "3"
        $script:bgpKeepAliveTimer = "1"
        $script:bgpPassword = "VMware1!"
        $script:PrefixName = "pester_e_prefix1"
        $script:ospfPrefixName = "pester_e_ospfprefix1"
        $script:bgpPrefixName = "pester_e_bgpprefix1"
        $script:PrefixNetwork = "1.2.3.0/24"
        $script:Password = "VMware1!VMware1!"
        $script:tenant = "pester_e_tenant1"
        $tz = get-nsxtransportzone -LocalOnly | select-object -first 1
        $script:lswitches = @()
        $script:lswitches += $tz | new-nsxlogicalswitch $ls1_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls2_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls3_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls4_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls5_name
        $script:pg1 = $cl | get-vmhost | Get-VDSwitch | select-object -first 1 |  New-VDPortgroup -name $pg1_name
        $script:vnics = @()
        $script:vnics += New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $lswitches[0] -PrimaryAddress $ip1 -SubnetPrefixLength 24
        $script:vnics += New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $lswitches[1] -PrimaryAddress $ip2 -SubnetPrefixLength 24
        $script:vnics += New-NsxEdgeInterfaceSpec -index 3 -Type trunk -Name "vNic3" -ConnectedTo $pg1
        $script:preexistingrulename = "pester_e_testrule1"
        $edge = New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
        $edge | get-nsxedgefirewall | new-nsxedgefirewallrule -name $preexistingrulename -action accept | out-null
        $script:scopedservice = New-NsxService -scope $edge.id -Name "pester_e_scopedservice" -Protocol "TCP" -port "1234"
        $script:VersionLessThan623 = [version]$DefaultNsxConnection.Version -lt [version]"6.2.3"
        $script:VersionLessThan630 = [version]$DefaultNsxConnection.Version -lt [version]"6.3.0"
    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        write-warning "Cleaning up"
        get-nsxedge $name | remove-nsxedge -confirm:$false

        start-sleep 5

        foreach ( $lswitch in $lswitches) {
            get-nsxlogicalswitch $lswitch.name | remove-nsxlogicalswitch -confirm:$false
        }
        get-vdportgroup $pg1_name | Remove-VDPortGroup -Confirm:$false
        disconnect-nsxserver
    }

    Context "Edge Status" {

        BeforeAll{
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
            }
        }

        It "Get Edge Status" {
            $status = Get-NsxEdge $name | Get-NsxEdgeStatus
            $status | should not be $null
            $status.systemStatus| should not be $null
            $status.edgeStatus | should not be $null
            $status.publishStatus| should not be $null
        }

        It "Get Edge Service Status" {
            $service = Get-NsxEdge $name | Get-NsxEdgeStatus
            $service | should not be $null
            $service.featureStatuses.featureStatus | should not be $null
        }

        It "Get Edge Service Firewall Status" {
            $service = Get-NsxEdge $name | Get-NsxEdgeStatus
            $service | should not be $null
            $service.featureStatuses.featureStatus | should not be $null
            ($service.featureStatuses.featureStatus | where-object { $_.service -eq 'firewall' }).status | should not be $null
        }

    }

    Context "Interfaces" {

        BeforeAll{
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
            }
        }

        it "Can add an edge vnic" {
            $nic = Get-NsxEdge $name | Get-NsxEdgeInterface -Index 4 | Set-NsxEdgeInterface -Name "vNic4" -Type internal -ConnectedTo $lswitches[3] -PrimaryAddress $ip4 -SubnetPrefixLength 24
            $nic = Get-NsxEdge $name | Get-NsxEdgeInterface -Index 4
            $nic.type | should be internal
            $nic.portGroupName | should be $lswitches[3].name
        }

        it "Can add a sub-interface of VLAN Type" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubinterface  -Name "sub1" -PrimaryAddress $ip5 -SubnetPrefixLength 24 -TunnelId 1 -Vlan 123
            $vnic | should not be $null
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface
            @($vnic).count | should be 1
        }

        it "Can add a sub-interface of Network Type" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubinterface  -Name "sub2" -PrimaryAddress $ip6 -SubnetPrefixLength 24 -TunnelId 2 -Network $lswitches[4]
            $vnic | should not be $null
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface
            @($vnic).count | should be 2

        }

        it "Can get a sub-interface by name" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface "sub1"
            @($vnic).count | should be 1
        }

        it "Can get a sub-interface by index" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11
            @($vnic).count | should be 1
        }

        it "Can remove a sub-interface" {
            $subint = Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11
            $subint | should not be $null
            $subint | Remove-NsxEdgeSubinterface -confirm:$false
            Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11 | should be $null
        }

        it "Returns an empty result set when querying for sub interfaces, and no sub-interfaces exist" {
            Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface | Remove-NsxEdgeSubinterface -confirm:$false
            $int = Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3"
            $int | should not be $null
            $int | Get-NsxEdgeSubInterface | should be $null
        }
    }

    Context "Static Routing" {

        BeforeAll{
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
            }
        }

        It "Can configure the default route" {
            Get-NsxEdge $name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayVnic 1 -DefaultGatewayAddress $dgaddress -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.staticRouting.defaultRoute.gatewayAddress | should be $dgaddress
        }

        it "Can add a static route" {
            Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop -confirm:$false
            $rtg = Get-NsxEdge $name | get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.staticRouting.staticRoutes | should not be $null
        }

        it "Can remove a static route" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | Remove-NsxEdgeStaticRoute -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | should be $null
        }
    }

    Context "Route Prefixes" {

        BeforeAll{
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
            }
        }

        it "Can create a route prefix" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | New-NsxEdgePrefix -Name $PrefixName -Network $PrefixNetwork -confirm:$false
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -name $PrefixName | should not be $null
        }

        it "Can can remove a route prefix" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgePrefix | Remove-NsxEdgePrefix -Confirm:$false
            Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -name $PrefixName | should be $null
        }
    }

    Context "OSPF" {

        BeforeAll{
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
            }
        }
        It "Can enable OSPF and define router id" {
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspf -RouterId $routerId -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.routingGlobalConfig.routerId | should be $routerId
            $rtg.ospf.enabled | should be "true"
        }

        it "Can add an OSPF Area" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | New-NsxEdgeOspfArea -AreaId $OspfAreaId -Confirm:$false
            $area = Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId $OspfAreaId
            $area | should not be $null
        }

        It "Can add an OSPF Interface" {
            $UplinkVnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic1"
            $uplinkVnic | should not be $null
            $UplinkVnicId = $uplinkVnic.index
            $ospfint = Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeOspfInterface -AreaId $OspfAreaId -Vnic $UplinkVnicId -confirm:$false
            $ospfint | should not be $null
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.ospf.ospfInterfaces.ospfInterface | Where-Object { $_.vnic -eq $UplinkVnicId } | should not be $null
        }

        it "Can enable route redistribution into Ospf" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | New-NsxEdgePrefix -Name $ospfPrefixName -Network $PrefixNetwork -confirm:$false
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -name $ospfPrefixName | should not be $null
            Get-NsxEdge $Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -PrefixName $ospfPrefixName -Learner ospf -FromConnected -FromStatic -Action permit -confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -learner ospf  | where-object { $_.prefixName -eq $ospfPrefixName }
            $rule.from.connected | should be "true"
            $rule.from.static | should be "true"
        }

        it "Can remove an OSPF Interface" {
            $UplinkVnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic1"
            $UplinkVnic | should not be $null
            $UplinkVnicId = $uplinkVnic.index
            Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface -AreaId $OspfAreaId -VnicId $UplinkVnicId | Remove-NsxEdgeOspfInterface -confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.ospfInterfaces.ospfInterface | Where-Object { $_.vnic -eq $UplinkVnicId } | should be $null
        }

        it "Can remove an OSPF Area" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeOspfArea -AreaId $OspfAreaId | Remove-NsxEdgeOspfArea -confirm:$false
            $area = Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId $OspfAreaId
            $area | should be $null
        }

        it "Can remove ospf route redistribution rules" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -learner ospf
            $rule | should be $null
        }

        it "Can disable Graceful Restart" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.ospf.gracefulRestart | should be true
            $rtg | Set-NsxEdgeOspf -GracefulRestart:$false -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.gracefulRestart | should be false
        }

        it "Can enable Default Originate" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.ospf.defaultOriginate | should be false
            $rtg | Set-NsxEdgeOspf -DefaultOriginate -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.defaultOriginate | should be true
        }

        it "Can disable OSPF" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.ospf.enabled | should be "true"
            $rtg | Set-NsxEdgeRouting -EnableOspf:$false -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.enabled | should be "false"
        }
    }

    Context "BGP" {

        BeforeAll{
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
            }
        }

        it "Can enable BGP" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Set-NsxEdgeRouting -EnableBgp -RouterId $routerId -LocalAS $LocalAS -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.routingGlobalConfig.routerId | should be $routerId
            $rtg.bgp.enabled | should be "true"
        }

        it "Can add a BGP Neighbour" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | New-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs -Weight $bgpWeight -KeepAliveTimer $bgpKeepAliveTimer -HoldDownTimer $bgpHoldDownTimer -Password $bgpPassword -confirm:$false
            $nbr = Get-NsxEdge $name  | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour
            $nbr.ipaddress | should be $bgpneighbour
            $nbr.remoteAS | should be $RemoteAs
            $nbr.weight | should be $bgpWeight
            $nbr.keepAliveTimer | should be $bgpKeepAliveTimer
            $nbr.holdDownTimer | should be $bgpHoldDownTimer
            ($nbr | Get-Member -MemberType Properties -Name password).count | should be 1
        }

        it "Can enable route redistribution into BGP" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | New-NsxEdgePrefix -Name $bgpPrefixName -Network $PrefixNetwork -confirm:$false
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -name $bgpPrefixName | should not be $null
            Get-NsxEdge $Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -PrefixName $bgpPrefixName -Learner bgp -FromConnected -FromStatic -FromOspf -Action permit -confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -learner bgp
            $rule.from.connected | should be "true"
            $rule.from.static | should be "true"
            $rule.from.ospf | should be "true"
        }

        it "Can remove bgp route redistribution rules" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeRedistributionRule -Learner bgp | Remove-NsxEdgeRedistributionRule -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -learner bgp
            $rule | should be $null
        }

        it "Can retreive an empty result set of redistribution rules" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeRedistributionRule | Remove-NsxEdgeRedistributionRule -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule
            $rule | should be $null
        }

        it "Can remove a BGP Neighbour" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | Remove-NsxEdgeBgpNeighbour -confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Get-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | should be $null
        }

        it "Can disable Graceful Restart" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.bgp.gracefulRestart | should be true
            $rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.bgp.gracefulRestart | should be false
        }

        it "Can enable Default Originate" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.bgp.defaultOriginate | should be false
            $rtg | Set-NsxEdgeBgp -DefaultOriginate -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.bgp.defaultOriginate | should be true
        }

        it "Can disable BGP" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg | Set-NsxEdgeRouting -EnableBgp:$false -Confirm:$false
            $rtg = Get-NSxEdge $name | Get-NsxEdgeRouting
            $rtg | should not be $null
            $rtg.bgp.enabled | should be "false"
        }
    }

    Context "Grouping Objects" {

        BeforeAll{
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
            }
        }

        it "Can retrieve locally created IP Sets" {
        }

        it "Can add local IP Sets" {
        }

        it "Can remove local IP Sets" {
        }
    }

    Context "Edge Firewall" {

        it "Can retrieve edge firewall rules" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | Get-NsxEdgeFirewallRule $preexistingrulename
            $rule | should not be $null
            $rule.name | should be $preexistingrulename
        }

        It "Can add a simple edge firewall rule" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule1" -comment "testrule1" -action accept
            $rule | should not be $null
            $rule.name | should be "testrule1"
            $rule.description | should be "testrule1"
        }

        It "Can add an edge firewall rule with service by existing nsx service object" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule2" -comment "testrule2" -service $scopedservice -action accept
            $rule | should not be $null
            $rule.application.applicationId -contains $scopedservice.objectid | should be $true
        }

        It "Can add an edge firewall rule with service by protocol and port" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule3" -comment "testrule3" -service tcp/4321 -action accept
            $rule | should not be $null
            $rule.application.service.protocol -contains "tcp" | should be $true
            $rule.application.service.port -contains "4321" | should be $true
        }

        It "Can add an edge firewall rule with service by protocol only" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule4" -comment "testrule4" -service tcp -action accept
            $rule | should not be $null
            $rule.application.service.protocol -contains "tcp" | should be $true
            # $rule.application.service.port -contains "any" | should be $true
        }

        It "Can remove an edge firewall rule" {
            $removerulename = "test_removerule1"
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name $removerulename -comment $removerulename -service tcp -action accept
            $rule | should not be $null
            { $rule | Remove-NsxEdgeFirewallRule -NoConfirm } | should not throw
            $getrule = Get-NsxEdge $name | Get-NsxEdgeFirewall | Get-NsxEdgeFirewallRule -name $removerulename
            $getrule | should be $null
        }

        It "Can add an edge firewall rule with logging enabled" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule5" -comment "testrule5" -enablelogging -action accept
            $rule | should not be $null
            $rule.loggingEnabled | should be "true"
        }

        It "Can add an edge firewall rule with multiple source members" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule6" -comment "testrule6" -source "1.2.3.4","4.3.2.1" -action accept
            $rule | should not be $null
            $rule.source.ipaddress -contains "1.2.3.4" | should be "true"
            $rule.source.ipaddress -contains "4.3.2.1" | should be "true"
        }

        It "Can add an edge firewall rule with multiple destination members" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule7" -comment "testrule7" -destination "1.2.3.4","4.3.2.1" -action accept
            $rule | should not be $null
            $rule.destination.ipaddress -contains "1.2.3.4" | should be "true"
            $rule.destination.ipaddress -contains "4.3.2.1" | should be "true"
        }

        It "Can add an edge firewall rule with negated sources" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule8" -comment "testrule8" -source "1.2.3.4" -negateSource -action accept
            $rule | should not be $null
            $rule.source.ipaddress -contains "1.2.3.4" | should be "true"
            $rule.source.exclude | should be "true"
        }

        It "Can add an edge firewall rule with negated destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule8" -comment "testrule8" -destination "1.2.3.4" -negateDestination -action accept
            $rule | should not be $null
            $rule.destination.ipaddress -contains "1.2.3.4" | should be "true"
            $rule.destination.exclude | should be "true"
        }

        It "Can add an edge firewall rule with specific nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule9" -comment "testrule9" -sourceVnic 0 -action accept
            $rule | should not be $null
            $rule.source.vnicGroupId -contains "vnic-index-0" | should be "true"
        }

        It "Can add an edge firewall rule with internal nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule10" -comment "testrule10" -sourceVnic internal -action accept
            $rule | should not be $null
            $rule.source.vnicGroupId -contains "internal" | should be "true"
        }

        It "Can add an edge firewall rule with external nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule11" -comment "testrule11" -sourceVnic external -action accept
            $rule | should not be $null
            $rule.source.vnicGroupId -contains "external" | should be "true"
        }

        It "Can add an edge firewall rule with vse nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule12" -comment "testrule12" -sourceVnic vse -action accept
            $rule | should not be $null
            $rule.source.vnicGroupId -contains "vse" | should be "true"
        }

        It "Can add an edge firewall rule with specific nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule13" -comment "testrule13" -destinationVnic 1 -action accept
            $rule | should not be $null
            $rule.destination.vnicGroupId -contains "vnic-index-1" | should be "true"
        }

        It "Can add an edge firewall rule with internal nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule14" -comment "testrule14" -destinationVnic internal -action accept
            $rule | should not be $null
            $rule.destination.vnicGroupId -contains "internal" | should be "true"
        }

        It "Can add an edge firewall rule with external nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule15" -comment "testrule15" -destinationVnic external -action accept
            $rule | should not be $null
            $rule.destination.vnicGroupId -contains "external" | should be "true"
        }

        It "Can add an edge firewall rule with vse nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule16" -comment "testrule16" -destinationVnic vse -action accept
            $rule | should not be $null
            $rule.destination.vnicGroupId -contains "vse" | should be "true"
        }

        It "Can add an edge firewall rule above an existing rule" {
            $existingrule = Get-NsxEdge $name | Get-NsxEdgeFirewall | Get-NsxEdgeFirewallRule $preexistingrulename
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule17" -comment "testrule17" -aboveRuleId $existingRule.id -action accept
            $rule | should not be $null
            $fw = Get-NsxEdge $name | Get-NsxEdgeFirewall
            ($fw.firewallRules.firewallRule | where-object { $_.ruleType -eq 'user' } | select-object -first 1).id | should be $rule.id
        }

        It "Can add an edge firewall rule with deny action" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule18" -comment "testrule18" -action deny
            $rule | should not be $null
            $rule.action | should be "deny"
        }

        It "Can add an edge firewall rule with reject action" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule19" -comment "testrule19" -action reject
            $rule | should not be $null
            $rule.action | should be "reject"
        }

        It "Can modifiy an edge firewall rule" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -name "testrule20" -comment "testrule20" -action accept
            $rule | should not be $null
            $rule.enabled | should be "true"
            $rule.loggingEnabled | should be "false"
            $rule.action | should be "accept"
            $rule.name | should be "testrule20"
            $rule.description | should be "testrule20"
            $rule = $rule | Set-NsxEdgeFirewallRule -name "testrule21" -comment "testrule21" -loggingEnabled $true -enabled $false -action deny
            $rule | should not be $null
            $rule.enabled | should be "false"
            $rule.loggingEnabled | should be "true"
            $rule.action | should be "deny"
            $rule.name | should be "testrule21"
            $rule.description | should be "testrule21"
        }

        It "Can disable the edge firewall" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -Enabled:$false -NoConfirm
            $config.enabled | should be "false"
        }

        It "Can set edge default rule action" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -DefaultRuleAction "accept" -NoConfirm
            $config.defaultPolicy.action | should be "accept"

        }

        It "Can disable edge default rule logging" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -DefaultRuleLoggingEnabled:$false -NoConfirm
            $config.defaultPolicy.loggingEnabled | should be "false"
        }

        It "Can set edge globalConfig option tcpPickOngoingConnections" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpPickOngoingConnections -NoConfirm
            $config.globalConfig.tcpPickOngoingConnections | should be "true"
        }

        It "Can set edge globalConfig option tcpAllowOutOfWindowPackets" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpAllowOutOfWindowPackets -NoConfirm
            $config.globalConfig.tcpAllowOutOfWindowPackets | should be "true"
        }

        It "Can set edge globalConfig option tcpSendResetForClosedVsePorts" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpSendResetForClosedVsePorts:$false -NoConfirm
            $config.globalConfig.tcpSendResetForClosedVsePorts | should be "false"
        }

        It "Can set edge globalConfig option dropInvalidTraffic" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -dropInvalidTraffic:$false -NoConfirm
            $config.globalConfig.dropInvalidTraffic | should be "false"
        }

        It "Can set edge globalConfig option logInvalidTraffic" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -logInvalidTraffic -NoConfirm
            $config.globalConfig.logInvalidTraffic | should be "true"
        }

        It "Can set edge globalConfig option tcpTimeoutOpen" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpTimeoutOpen 40 -NoConfirm
            $config.globalConfig.tcpTimeoutOpen | should be "40"
        }

        It "Can set edge globalConfig option tcpTimeoutEstablished" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpTimeoutEstablished 45200 -NoConfirm
            $config.globalConfig.tcpTimeoutEstablished | should be "45200"
        }

        It "Can set edge globalConfig option tcpTimeoutClose" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpTimeoutClose 40 -NoConfirm
            $config.globalConfig.tcpTimeoutClose | should be "40"
        }

        It "Can set edge globalConfig option udpTimeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -udpTimeout 70 -NoConfirm
            $config.globalConfig.udpTimeout | should be "70"
        }

        It "Can set edge globalConfig option icmpTimeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -icmpTimeout 20 -NoConfirm
            $config.globalConfig.icmpTimeout | should be "20"
        }

        It "Can set edge globalConfig option icmp6Timeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -icmp6Timeout 20 -NoConfirm
            $config.globalConfig.icmp6Timeout | should be "20"
        }

        It "Can set edge globalConfig option ipGenericTimeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -ipGenericTimeout 130 -NoConfirm
            $config.globalConfig.ipGenericTimeout | should be "130"
        }

        It "Can set edge globalConfig option enableSynFloodProtection on NSX -ge 6.2.3" -Skip:$VersionLessThan623 {
            $config =  Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -enableSynFloodProtection -NoConfirm
            $config.globalConfig.enableSynFloodProtection | should be "true"
        }

        It "Can set edge globalConfig option logIcmpErrors on NSX -ge 6.3.0" -Skip:$VersionLessThan630 {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -logIcmpErrors -NoConfirm
            $config.globalConfig.logIcmpErrors | should be "true"
        }

        It "Can set edge globalConfig option dropIcmpReplays on NSX -ge 6.3.0" -Skip:$VersionLessThan630 {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -dropIcmpReplays -NoConfirm
            $config.globalConfig.dropIcmpReplays | should be "true"
        }

        It "Throws a warning when setting edge globalConfig option enableSynFloodProtection on NSX -lt 6.2.3" -Skip:(-not $VersionLessThan623) {
            (( Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -enableSynFloodProtection -NoConfirm ) 3>&1) -match "The option enableSynFloodProtection requires at least NSX version 6.2.3" | should be $true
        }

        It "Throws a warning when setting edge globalConfig option logIcmpErrors on NSX -lt 6.3.0" -Skip:(-not $VersionLessThan630) {
            (( Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -logIcmpErrors -NoConfirm ) 3>&1) -match "The option logIcmpErrors requires at least NSX version 6.3.0" | should be $true
        }

        It "Throws a warning when setting edge globalConfig option dropIcmpReplays on NSX -lt 6.3.0" -Skip:(-not $VersionLessThan630) {
            (( Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -dropIcmpReplays -NoConfirm ) 3>&1) -match "The option dropIcmpReplays requires at least NSX version 6.3.0" | should be $true
        }
    }

    Context "SSH" {

        it "Can disable SSH" {
            $edge = Get-NsxEdge $name
            #When deploy pstester ESG, the SSH is enabled
            $edge.cliSettings.remoteAccess | should be "true"
            Get-NsxEdge $name | Disable-NsxEdgeSsh -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | should be "false"
        }

        it "Can enable SSH" {
            Get-NsxEdge $name | Enable-NsxEdgeSsh
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | should be "true"
        }
    }

    Context "CliSettings" {

        it "Can retrieve cliSettings" {
            $edge =  Get-NsxEdge $name
            $edge.cliSettings | should not be $null
            #By default it is admin
            $edge.cliSettings.userName | should be "admin"
            #By default it is 99999
            $edge.cliSettings.passwordExpiry | should be "99999"
        }

        it "Can disable SSH" {
            $edge = Get-NsxEdge $name
            Get-NsxEdge $name | Set-NsxEdge -remoteAccess:$false -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | should be "false"
        }

        it "Can enable SSH" {
            Get-NsxEdge $name | Set-NsxEdge -remoteAccess:$true -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | should be "true"
        }

        it "Change (SSH) username (and Password)" {
            #it is mandatory to change username (and Password) on the same time (bug or feature ?)
            Get-NsxEdge $name | Set-NsxEdge -userName powernsxviasetnsxedge -Password "Vmware1!Vmware1!" -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.userName | should be "powernsxviasetnsxedge"
            #It is impossible to check if the password is modified...
        }

        it "Change Password Expiry" {
            Get-NsxEdge $name | Set-NsxEdge -passwordExpiry 4242 -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.passwordExpiry | should be "4242"
        }

        it "Change sshLoginBannerText" {
            Get-NsxEdge $name | Set-NsxEdge -sshLoginBannerText "Secured by Set-NsxEdge" -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.sshLoginBannerText | should be "Secured by Set-NsxEdge"
        }
    }

    Context "Misc" {

        it "Can enable firewall via Set-NsxEdge" {
            $edge = Get-NsxEdge $name
            $edge | should not be $null
            $edge.features.firewall.enabled | should be "false"
            $edge.features.firewall.enabled = "true"
            $edge | Set-NsxEdge -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.features.firewall.enabled | should be "true"
        }

        it "Can remove an edge" {
            Get-NsxEdge $name | should not be $null
            Get-NsxEdge $name | remove-nsxEdge -confirm:$false
            get-nsxEdge $name | should be $null
        }
    }
}
