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
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | select -first 1
        write-warning "Using cluster $cl for edge appliance deployment"
        $script:ds = $cl | get-datastore | select -first 1
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
        $script:PrefixName = "pester_e_prefix1"
        $script:ospfPrefixName = "pester_e_ospfprefix1"
        $script:bgpPrefixName = "pester_e_bgpprefix1"
        $script:PrefixNetwork = "1.2.3.0/24"
        $script:Password = "VMware1!VMware1!"
        $script:tenant = "pester_e_tenant1"
        $tz = get-nsxtransportzone -LocalOnly | select -first 1
        $script:lswitches = @()
        $script:lswitches += $tz | new-nsxlogicalswitch $ls1_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls2_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls3_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls4_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls5_name
        $script:pg1 = $cl | get-vmhost | Get-VDSwitch | Select -first 1 |  New-VDPortgroup -name $pg1_name
        $script:vnics = @()
        $script:vnics += New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $lswitches[0] -PrimaryAddress $ip1 -SubnetPrefixLength 24
        $script:vnics += New-NsxEdgeInterfaceSpec -index 2 -Type internal -Name "vNic2" -ConnectedTo $lswitches[1] -PrimaryAddress $ip2 -SubnetPrefixLength 24
        $script:vnics += New-NsxEdgeInterfaceSpec -index 3 -Type trunk -Name "vNic3" -ConnectedTo $pg1

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

    it "Can deploy a new edge" {
        #hostname is important - otherwise we default to the vm name, and _ arent supported
        $edge = New-NsxEdge -Name $name -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -Hostname "pestertest"
        $edge | should not be $null
        get-nsxedge $name | should not be $null
    }

    Context "Interfaces" {
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
            $rule = Get-NsxEdge $Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -learner ospf  | ? { $_.prefixName -eq $ospfPrefixName }
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
            $rtg | New-NsxEdgeBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs -confirm:$false
            $nbr = Get-NsxEdge $name  | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour
            $nbr.ipaddress | should be $bgpneighbour
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

        it "Can retrieve locally created IP Sets" {
        }

        it "Can add local IP Sets" {
        }

        it "Can remove local IP Sets" {
        }
    }

    it "Can remove an edge" {
        Get-NsxEdge $name | should not be $null
        Get-NsxEdge $name | remove-nsxEdge -confirm:$false
        get-nsxEdge $name | should be $null
    }
}