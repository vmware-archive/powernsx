#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Edge" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        Import-Module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = Get-Cluster | Select-Object -First 1
        Write-Warning "Using cluster $cl for edge appliance deployment"
        $script:ds = $cl | Get-Datastore | Select-Object -First 1
        Write-Warning "Using datastore $ds for edge appliance deployment"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:name = "pester_e_edge1"
        $script:fipsName = "fips-$($script:name)"
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
        $tz = Get-NsxTransportZone -LocalOnly | Select-Object -First 1
        $script:lswitches = @()
        $script:lswitches += $tz | New-NsxLogicalSwitch $ls1_name
        $script:lswitches += $tz | New-NsxLogicalSwitch $ls2_name
        $script:lswitches += $tz | New-NsxLogicalSwitch $ls3_name
        $script:lswitches += $tz | New-NsxLogicalSwitch $ls4_name
        $script:lswitches += $tz | New-NsxLogicalSwitch $ls5_name
        $script:pg1 = $cl | Get-VMHost | Get-VDSwitch | Select-Object -First 1 | New-VDPortgroup -Name $pg1_name
        $script:vnics = @()
        $script:vnics += New-NsxEdgeInterfaceSpec -Index 1 -Type uplink -Name "vNic1" -ConnectedTo $lswitches[0] -PrimaryAddress $ip1 -SubnetPrefixLength 24
        $script:vnics += New-NsxEdgeInterfaceSpec -Index 2 -Type internal -Name "vNic2" -ConnectedTo $lswitches[1] -PrimaryAddress $ip2 -SubnetPrefixLength 24
        $script:vnics += New-NsxEdgeInterfaceSpec -Index 3 -Type trunk -Name "vNic3" -ConnectedTo $pg1
        $script:preexistingrulename = "pester_e_testrule1"
        $edge = New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
        $edge | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name $preexistingrulename -Action accept | Out-Null
        $script:scopedservice = New-NsxService -scope $edge.id -Name "pester_e_scopedservice" -Protocol "TCP" -port "1234"
        $script:VersionLessThan623 = [version]$DefaultNsxConnection.Version -lt [version]"6.2.3"
        $script:VersionLessThan630 = [version]$DefaultNsxConnection.Version -lt [version]"6.3.0"
    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        Write-Warning "Cleaning up"
        Get-NsxEdge $name | Remove-NsxEdge -Confirm:$false
        Get-NsxEdge $fipsName | Remove-NsxEdge -Confirm:$false

        Start-Sleep 5

        foreach ( $lswitch in $lswitches) {
            Get-NsxLogicalSwitch $lswitch.name | Remove-NsxLogicalSwitch -Confirm:$false
        }
        Get-VDPortgroup $pg1_name | Remove-VDPortGroup -Confirm:$false
        Disconnect-NsxServer
    }

    Context "Edge Status" {

        BeforeAll {
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
            }
        }

        It "Get Edge Status" {
            $status = Get-NsxEdge $name | Get-NsxEdgeStatus
            $status | Should not be $null
            $status.systemStatus | Should not be $null
            $status.edgeStatus | Should not be $null
            $status.publishStatus | Should not be $null
        }

        It "Get Edge Service Status" {
            $service = Get-NsxEdge $name | Get-NsxEdgeStatus
            $service | Should not be $null
            $service.featureStatuses.featureStatus | Should not be $null
        }

        It "Get Edge Service Firewall Status" {
            $service = Get-NsxEdge $name | Get-NsxEdgeStatus
            $service | Should not be $null
            $service.featureStatuses.featureStatus | Should not be $null
            ($service.featureStatuses.featureStatus | Where-Object { $_.service -eq 'firewall' }).status | Should not be $null
        }

    }

    Context "Interfaces" {

        BeforeAll {
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
            }
        }

        It "Can add an edge vnic" {
            $nic = Get-NsxEdge $name | Get-NsxEdgeInterface -Index 4 | Set-NsxEdgeInterface -Name "vNic4" -Type internal -ConnectedTo $lswitches[3] -PrimaryAddress $ip4 -SubnetPrefixLength 24
            $nic = Get-NsxEdge $name | Get-NsxEdgeInterface -Index 4
            $nic.type | Should be internal
            $nic.portGroupName | Should be $lswitches[3].name
        }

        It "Can add a sub-interface of VLAN Type" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubInterface -Name "sub1" -PrimaryAddress $ip5 -SubnetPrefixLength 24 -TunnelId 1 -VLAN 123
            $vnic | Should not be $null
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface
            @($vnic).count | Should be 1
        }

        It "Can add a sub-interface of Network Type" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | New-NsxEdgeSubInterface -Name "sub2" -PrimaryAddress $ip6 -SubnetPrefixLength 24 -TunnelId 2 -Network $lswitches[4]
            $vnic | Should not be $null
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface
            @($vnic).count | Should be 2

        }

        It "Can get a sub-interface by name" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" | Get-NsxEdgeSubInterface "sub1"
            @($vnic).count | Should be 1
        }

        It "Can get a sub-interface by index" {
            $vnic = Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11
            @($vnic).count | Should be 1
        }

        It "Can remove a sub-interface" {
            $subint = Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11
            $subint | Should not be $null
            $subint | Remove-NsxEdgeSubInterface -Confirm:$false
            Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface -Index 11 | Should be $null
        }

        It "Returns an empty result set when querying for sub interfaces, and no sub-interfaces exist" {
            Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3" | Get-NsxEdgeSubInterface | Remove-NsxEdgeSubInterface -Confirm:$false
            $int = Get-NsxEdge $name | Get-NsxEdgeInterface "Vnic3"
            $int | Should not be $null
            $int | Get-NsxEdgeSubInterface | Should be $null
        }
    }

    Context "Static Routing" {

        BeforeAll {
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
            }
        }

        It "Can configure the default route" {
            Get-NsxEdge $name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayVnic 1 -DefaultGatewayAddress $dgaddress -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.staticRouting.defaultRoute.gatewayAddress | Should be $dgaddress
        }

        It "Can add a static route" {
            Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.staticRouting.staticRoutes | Should not be $null
        }

        It "Can remove a static route" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | Remove-NsxEdgeStaticRoute -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | Should be $null
        }
    }

    Context "Route Prefixes" {

        BeforeAll {
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
            }
        }

        It "Can create a route prefix" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | New-NsxEdgePrefix -Name $PrefixName -Network $PrefixNetwork -Confirm:$false
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Name $PrefixName | Should not be $null
        }

        It "Can can remove a route prefix" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgePrefix | Remove-NsxEdgePrefix -Confirm:$false
            Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Name $PrefixName | Should be $null
        }
    }

    Context "OSPF" {

        BeforeAll {
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
            }
        }
        It "Can enable OSPF and define router id" {
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspf -RouterId $routerId -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.routingGlobalConfig.routerId | Should be $routerId
            $rtg.ospf.enabled | Should be "true"
        }

        It "Can add an OSPF Area" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | New-NsxEdgeOspfArea -AreaId $OspfAreaId -Confirm:$false
            $area = Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId $OspfAreaId
            $area | Should not be $null
        }

        It "Can add an OSPF Interface" {
            $UplinkVnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic1"
            $uplinkVnic | Should not be $null
            $UplinkVnicId = $uplinkVnic.index
            $ospfint = Get-NsxEdge $name | Get-NsxEdgeRouting | New-NsxEdgeOspfInterface -AreaId $OspfAreaId -Vnic $UplinkVnicId -Confirm:$false
            $ospfint | Should not be $null
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.ospf.ospfInterfaces.ospfInterface | Where-Object { $_.vnic -eq $UplinkVnicId } | Should not be $null
        }

        It "Can enable route redistribution into Ospf" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | New-NsxEdgePrefix -Name $ospfPrefixName -Network $PrefixNetwork -Confirm:$false
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Name $ospfPrefixName | Should not be $null
            Get-NsxEdge $Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -PrefixName $ospfPrefixName -Learner ospf -FromConnected -FromStatic -Action permit -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Where-Object { $_.prefixName -eq $ospfPrefixName }
            $rule.from.connected | Should be "true"
            $rule.from.static | Should be "true"
        }

        It "Can remove an OSPF Interface" {
            $UplinkVnic = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic1"
            $UplinkVnic | Should not be $null
            $UplinkVnicId = $uplinkVnic.index
            Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface -AreaId $OspfAreaId -vNicId $UplinkVnicId | Remove-NsxEdgeOspfInterface -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.ospfInterfaces.ospfInterface | Where-Object { $_.vnic -eq $UplinkVnicId } | Should be $null
        }

        It "Can remove an OSPF Area" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeOspfArea -AreaId $OspfAreaId | Remove-NsxEdgeOspfArea -Confirm:$false
            $area = Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId $OspfAreaId
            $area | Should be $null
        }

        It "Can remove ospf route redistribution rules" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf
            $rule | Should be $null
        }

        It "Can disable Graceful Restart" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.ospf.gracefulRestart | Should be true
            $rtg | Set-NsxEdgeOspf -GracefulRestart:$false -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.gracefulRestart | Should be false
        }

        It "Can enable Default Originate" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.ospf.defaultOriginate | Should be false
            $rtg | Set-NsxEdgeOspf -DefaultOriginate -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.defaultOriginate | Should be true
        }

        It "Can disable OSPF" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.ospf.enabled | Should be "true"
            $rtg | Set-NsxEdgeRouting -EnableOspf:$false -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.ospf.enabled | Should be "false"
        }
    }

    Context "BGP" {

        BeforeAll {
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
            }
        }

        It "Can enable BGP" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Set-NsxEdgeRouting -EnableBgp -RouterId $routerId -LocalAS $LocalAS -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.routingGlobalConfig.routerId | Should be $routerId
            $rtg.bgp.enabled | Should be "true"
        }

        It "Can add a BGP Neighbour" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | New-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs -Weight $bgpWeight -KeepAliveTimer $bgpKeepAliveTimer -HoldDownTimer $bgpHoldDownTimer -Password $bgpPassword -Confirm:$false
            $nbr = Get-NsxEdge $name | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour
            $nbr.ipaddress | Should be $bgpneighbour
            $nbr.remoteAS | Should be $RemoteAs
            $nbr.weight | Should be $bgpWeight
            $nbr.keepAliveTimer | Should be $bgpKeepAliveTimer
            $nbr.holdDownTimer | Should be $bgpHoldDownTimer
            ($nbr | Get-Member -MemberType Properties -Name password).count | Should be 1
        }

        It "Can enable route redistribution into BGP" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | New-NsxEdgePrefix -Name $bgpPrefixName -Network $PrefixNetwork -Confirm:$false
            Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Name $bgpPrefixName | Should not be $null
            Get-NsxEdge $Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -PrefixName $bgpPrefixName -Learner bgp -FromConnected -FromStatic -FromOspf -Action permit -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner bgp
            $rule.from.connected | Should be "true"
            $rule.from.static | Should be "true"
            $rule.from.ospf | Should be "true"
        }

        It "Can remove bgp route redistribution rules" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeRedistributionRule -Learner bgp | Remove-NsxEdgeRedistributionRule -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner bgp
            $rule | Should be $null
        }

        It "Can retreive an empty result set of redistribution rules" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeRedistributionRule | Remove-NsxEdgeRedistributionRule -Confirm:$false
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule
            $rule | Should be $null
        }

        It "Can remove a BGP Neighbour" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | Remove-NsxEdgeBgpNeighbour -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Get-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | Should be $null
        }

        It "Can disable Graceful Restart" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.bgp.gracefulRestart | Should be true
            $rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.bgp.gracefulRestart | Should be false
        }

        It "Can enable Default Originate" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.bgp.defaultOriginate | Should be false
            $rtg | Set-NsxEdgeBgp -DefaultOriginate -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg.bgp.defaultOriginate | Should be true
        }

        It "Can disable BGP" {
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg | Set-NsxEdgeRouting -EnableBgp:$false -Confirm:$false
            $rtg = Get-NsxEdge $name | Get-NsxEdgeRouting
            $rtg | Should not be $null
            $rtg.bgp.enabled | Should be "false"
        }
    }

    Context "Grouping Objects" {

        BeforeAll {
            if ( -not ( Get-NsxEdge $name ) ) {
                New-NsxEdge -Name $name -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "pestertest"
            }
        }

        It "Can retrieve locally created IP Sets" {
        }

        It "Can add local IP Sets" {
        }

        It "Can remove local IP Sets" {
        }
    }

    Context "Edge Firewall" {

        It "Can retrieve edge firewall rules" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | Get-NsxEdgeFirewallRule $preexistingrulename
            $rule | Should not be $null
            $rule.name | Should be $preexistingrulename
        }

        It "Can add a simple edge firewall rule" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule1" -Comment "testrule1" -Action accept
            $rule | Should not be $null
            $rule.name | Should be "testrule1"
            $rule.description | Should be "testrule1"
        }

        It "Can add an edge firewall rule with service by existing nsx service object" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule2" -Comment "testrule2" -Service $scopedservice -Action accept
            $rule | Should not be $null
            $rule.application.applicationId -contains $scopedservice.objectid | Should be $true
        }

        It "Can add an edge firewall rule with service by protocol and port" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule3" -Comment "testrule3" -Service tcp/4321 -Action accept
            $rule | Should not be $null
            $rule.application.service.protocol -contains "tcp" | Should be $true
            $rule.application.service.port -contains "4321" | Should be $true
        }

        It "Can add an edge firewall rule with service by protocol only" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule4" -Comment "testrule4" -Service tcp -Action accept
            $rule | Should not be $null
            $rule.application.service.protocol -contains "tcp" | Should be $true
            # $rule.application.service.port -contains "any" | should be $true
        }

        It "Can remove an edge firewall rule" {
            $removerulename = "test_removerule1"
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name $removerulename -Comment $removerulename -Service tcp -Action accept
            $rule | Should not be $null
            { $rule | Remove-NsxEdgeFirewallRule -NoConfirm } | Should not throw
            $getrule = Get-NsxEdge $name | Get-NsxEdgeFirewall | Get-NsxEdgeFirewallRule -Name $removerulename
            $getrule | Should be $null
        }

        It "Can add an edge firewall rule with logging enabled" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule5" -Comment "testrule5" -EnableLogging -Action accept
            $rule | Should not be $null
            $rule.loggingEnabled | Should be "true"
        }

        It "Can add an edge firewall rule with multiple source members" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule6" -Comment "testrule6" -Source "1.2.3.4", "4.3.2.1" -Action accept
            $rule | Should not be $null
            $rule.source.ipaddress -contains "1.2.3.4" | Should be "true"
            $rule.source.ipaddress -contains "4.3.2.1" | Should be "true"
        }

        It "Can add an edge firewall rule with multiple destination members" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule7" -Comment "testrule7" -Destination "1.2.3.4", "4.3.2.1" -Action accept
            $rule | Should not be $null
            $rule.destination.ipaddress -contains "1.2.3.4" | Should be "true"
            $rule.destination.ipaddress -contains "4.3.2.1" | Should be "true"
        }

        It "Can add an edge firewall rule with negated sources" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule8" -Comment "testrule8" -Source "1.2.3.4" -NegateSource -Action accept
            $rule | Should not be $null
            $rule.source.ipaddress -contains "1.2.3.4" | Should be "true"
            $rule.source.exclude | Should be "true"
        }

        It "Can add an edge firewall rule with negated destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule8" -Comment "testrule8" -Destination "1.2.3.4" -NegateDestination -Action accept
            $rule | Should not be $null
            $rule.destination.ipaddress -contains "1.2.3.4" | Should be "true"
            $rule.destination.exclude | Should be "true"
        }

        It "Can add an edge firewall rule with specific nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule9" -Comment "testrule9" -SourceVnic 0 -Action accept
            $rule | Should not be $null
            $rule.source.vnicGroupId -contains "vnic-index-0" | Should be "true"
        }

        It "Can add an edge firewall rule with internal nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule10" -Comment "testrule10" -SourceVnic internal -Action accept
            $rule | Should not be $null
            $rule.source.vnicGroupId -contains "internal" | Should be "true"
        }

        It "Can add an edge firewall rule with external nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule11" -Comment "testrule11" -SourceVnic external -Action accept
            $rule | Should not be $null
            $rule.source.vnicGroupId -contains "external" | Should be "true"
        }

        It "Can add an edge firewall rule with vse nic source" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule12" -Comment "testrule12" -SourceVnic vse -Action accept
            $rule | Should not be $null
            $rule.source.vnicGroupId -contains "vse" | Should be "true"
        }

        It "Can add an edge firewall rule with specific nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule13" -Comment "testrule13" -DestinationVnic 1 -Action accept
            $rule | Should not be $null
            $rule.destination.vnicGroupId -contains "vnic-index-1" | Should be "true"
        }

        It "Can add an edge firewall rule with internal nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule14" -Comment "testrule14" -DestinationVnic internal -Action accept
            $rule | Should not be $null
            $rule.destination.vnicGroupId -contains "internal" | Should be "true"
        }

        It "Can add an edge firewall rule with external nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule15" -Comment "testrule15" -DestinationVnic external -Action accept
            $rule | Should not be $null
            $rule.destination.vnicGroupId -contains "external" | Should be "true"
        }

        It "Can add an edge firewall rule with vse nic destination" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule16" -Comment "testrule16" -DestinationVnic vse -Action accept
            $rule | Should not be $null
            $rule.destination.vnicGroupId -contains "vse" | Should be "true"
        }

        It "Can add an edge firewall rule above an existing rule" {
            $existingrule = Get-NsxEdge $name | Get-NsxEdgeFirewall | Get-NsxEdgeFirewallRule $preexistingrulename
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule17" -Comment "testrule17" -AboveRuleId $existingRule.id -Action accept
            $rule | Should not be $null
            $fw = Get-NsxEdge $name | Get-NsxEdgeFirewall
            ($fw.firewallRules.firewallRule | Where-Object { $_.ruleType -eq 'user' } | Select-Object -First 1).id | Should be $rule.id
        }

        It "Can add an edge firewall rule with deny action" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule18" -Comment "testrule18" -Action deny
            $rule | Should not be $null
            $rule.action | Should be "deny"
        }

        It "Can add an edge firewall rule with reject action" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule19" -Comment "testrule19" -Action reject
            $rule | Should not be $null
            $rule.action | Should be "reject"
        }

        It "Can modifiy an edge firewall rule" {
            $rule = Get-NsxEdge $name | Get-NsxEdgeFirewall | New-NsxEdgeFirewallRule -Name "testrule20" -Comment "testrule20" -Action accept
            $rule | Should not be $null
            $rule.enabled | Should be "true"
            $rule.loggingEnabled | Should be "false"
            $rule.action | Should be "accept"
            $rule.name | Should be "testrule20"
            $rule.description | Should be "testrule20"
            $rule = $rule | Set-NsxEdgeFirewallRule -Name "testrule21" -comment "testrule21" -loggingEnabled $true -enabled $false -action deny
            $rule | Should not be $null
            $rule.enabled | Should be "false"
            $rule.loggingEnabled | Should be "true"
            $rule.action | Should be "deny"
            $rule.name | Should be "testrule21"
            $rule.description | Should be "testrule21"
        }

        It "Can disable the edge firewall" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -Enabled:$false -NoConfirm
            $config.enabled | Should be "false"
        }

        It "Can set edge default rule action" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -DefaultRuleAction "accept" -NoConfirm
            $config.defaultPolicy.action | Should be "accept"

        }

        It "Can disable edge default rule logging" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -DefaultRuleLoggingEnabled:$false -NoConfirm
            $config.defaultPolicy.loggingEnabled | Should be "false"
        }

        It "Can set edge globalConfig option tcpPickOngoingConnections" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpPickOngoingConnections -NoConfirm
            $config.globalConfig.tcpPickOngoingConnections | Should be "true"
        }

        It "Can set edge globalConfig option tcpAllowOutOfWindowPackets" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpAllowOutOfWindowPackets -NoConfirm
            $config.globalConfig.tcpAllowOutOfWindowPackets | Should be "true"
        }

        It "Can set edge globalConfig option tcpSendResetForClosedVsePorts" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpSendResetForClosedVsePorts:$false -NoConfirm
            $config.globalConfig.tcpSendResetForClosedVsePorts | Should be "false"
        }

        It "Can set edge globalConfig option dropInvalidTraffic" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -dropInvalidTraffic:$false -NoConfirm
            $config.globalConfig.dropInvalidTraffic | Should be "false"
        }

        It "Can set edge globalConfig option logInvalidTraffic" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -logInvalidTraffic -NoConfirm
            $config.globalConfig.logInvalidTraffic | Should be "true"
        }

        It "Can set edge globalConfig option tcpTimeoutOpen" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpTimeoutOpen 40 -NoConfirm
            $config.globalConfig.tcpTimeoutOpen | Should be "40"
        }

        It "Can set edge globalConfig option tcpTimeoutEstablished" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpTimeoutEstablished 45200 -NoConfirm
            $config.globalConfig.tcpTimeoutEstablished | Should be "45200"
        }

        It "Can set edge globalConfig option tcpTimeoutClose" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -tcpTimeoutClose 40 -NoConfirm
            $config.globalConfig.tcpTimeoutClose | Should be "40"
        }

        It "Can set edge globalConfig option udpTimeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -udpTimeout 70 -NoConfirm
            $config.globalConfig.udpTimeout | Should be "70"
        }

        It "Can set edge globalConfig option icmpTimeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -icmpTimeout 20 -NoConfirm
            $config.globalConfig.icmpTimeout | Should be "20"
        }

        It "Can set edge globalConfig option icmp6Timeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -icmp6Timeout 20 -NoConfirm
            $config.globalConfig.icmp6Timeout | Should be "20"
        }

        It "Can set edge globalConfig option ipGenericTimeout" {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -ipGenericTimeout 130 -NoConfirm
            $config.globalConfig.ipGenericTimeout | Should be "130"
        }

        It "Can set edge globalConfig option enableSynFloodProtection on NSX -ge 6.2.3" -Skip:$VersionLessThan623 {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -enableSynFloodProtection -NoConfirm
            $config.globalConfig.enableSynFloodProtection | Should be "true"
        }

        It "Can set edge globalConfig option logIcmpErrors on NSX -ge 6.3.0" -Skip:$VersionLessThan630 {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -logIcmpErrors -NoConfirm
            $config.globalConfig.logIcmpErrors | Should be "true"
        }

        It "Can set edge globalConfig option dropIcmpReplays on NSX -ge 6.3.0" -Skip:$VersionLessThan630 {
            $config = Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -dropIcmpReplays -NoConfirm
            $config.globalConfig.dropIcmpReplays | Should be "true"
        }

        It "Throws a warning when setting edge globalConfig option enableSynFloodProtection on NSX -lt 6.2.3" -Skip:(-not $VersionLessThan623) {
            (( Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -enableSynFloodProtection -NoConfirm ) 3>&1) -match "The option enableSynFloodProtection requires at least NSX version 6.2.3" | Should be $true
        }

        It "Throws a warning when setting edge globalConfig option logIcmpErrors on NSX -lt 6.3.0" -Skip:(-not $VersionLessThan630) {
            (( Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -logIcmpErrors -NoConfirm ) 3>&1) -match "The option logIcmpErrors requires at least NSX version 6.3.0" | Should be $true
        }

        It "Throws a warning when setting edge globalConfig option dropIcmpReplays on NSX -lt 6.3.0" -Skip:(-not $VersionLessThan630) {
            (( Get-NsxEdge $name | Get-NsxEdgeFirewall | Set-NsxEdgeFirewall -dropIcmpReplays -NoConfirm ) 3>&1) -match "The option dropIcmpReplays requires at least NSX version 6.3.0" | Should be $true
        }
    }

    Context "SSH" {

        It "Can disable SSH" {
            $edge = Get-NsxEdge $name
            #When deploy pstester ESG, the SSH is enabled
            $edge.cliSettings.remoteAccess | Should be "true"
            Get-NsxEdge $name | Disable-NsxEdgeSsh -Confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | Should be "false"
        }

        It "Can enable SSH" {
            Get-NsxEdge $name | Enable-NsxEdgeSsh
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | Should be "true"
        }
    }

    Context "CliSettings" {

        It "Can retrieve cliSettings" {
            $edge = Get-NsxEdge $name
            $edge.cliSettings | Should not be $null
            #By default it is admin
            $edge.cliSettings.userName | Should be "admin"
            #By default it is 99999
            $edge.cliSettings.passwordExpiry | Should be "99999"
        }

        It "Can disable SSH" {
            $edge = Get-NsxEdge $name
            Get-NsxEdge $name | Set-NsxEdge -remoteAccess:$false -Confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | Should be "false"
        }

        It "Can enable SSH" {
            Get-NsxEdge $name | Set-NsxEdge -remoteAccess:$true -Confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.remoteAccess | Should be "true"
        }

        It "Change (SSH) username (and Password)" {
            #it is mandatory to change username (and Password) on the same time (bug or feature ?)
            Get-NsxEdge $name | Set-NsxEdge -userName powernsxviasetnsxedge -Password "Vmware1!Vmware1!" -Confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.userName | Should be "powernsxviasetnsxedge"
            #It is impossible to check if the password is modified...
        }

        It "Change Password Expiry" {
            Get-NsxEdge $name | Set-NsxEdge -passwordExpiry 4242 -Confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.passwordExpiry | Should be "4242"
        }

        It "Change sshLoginBannerText" {
            Get-NsxEdge $name | Set-NsxEdge -sshLoginBannerText "Secured by Set-NsxEdge" -Confirm:$false
            $edge = Get-NsxEdge $name
            $edge.cliSettings.sshLoginBannerText | Should be "Secured by Set-NsxEdge"
        }
    }

    Context "Misc" {

        It "Can enable firewall via Set-NsxEdge" {
            $edge = Get-NsxEdge $name
            $edge | Should not be $null
            $edge.features.firewall.enabled | Should be "false"
            $edge.features.firewall.enabled = "true"
            $edge | Set-NsxEdge -Confirm:$false
            $edge = Get-NsxEdge $name
            $edge.features.firewall.enabled | Should be "true"
        }

        It "Can remove an edge" {
            Get-NsxEdge $name | Should not be $null
            Get-NsxEdge $name | Remove-NsxEdge -Confirm:$false
            Get-NsxEdge $name | Should be $null
        }
    }

    Context "FIPS" {

        It "Edge deployed by default with FIPS mode disabled" {
            $edge = Get-NsxEdge $name
            $edge | Should not be $null
            $edge.enableFips | Should be "false"
        }

        It "Can enable FIPS mode on an already deployed Edge" {
            $edge = Get-NsxEdge $name
            $edge | Should not be $null
            $edge.enableFips | Should be "false"
            $edge | Enable-NsxEdgeFips -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.enableFips | Should be "true"
        }

        It "Can disable FIPS mode on an already deployed Edge" {
            $edge = Get-NsxEdge $name
            $edge | Should not be $null
            $edge.enableFips | Should be "true"
            $edge | Enable-NsxEdgeFips -confirm:$false
            $edge = Get-NsxEdge $name
            $edge.enableFips | Should be "false"
        }

        It "Can deploy an edge with FIPS mode enabled" {
            { $edge = New-NsxEdge -Name $fipsName -Interface $vnics[0], $vnics[1], $vnics[2] -Cluster $cl -Datastore $ds -Password $password -Tenant $tenant -EnableSSH -Hostname "fips-pestertest" } | Should not throw
            $edge = Get-NsxEdge $fipsName
            $edge | Should not be $null
            $edge.enableFips | Should be "true"
        }
    }
}
