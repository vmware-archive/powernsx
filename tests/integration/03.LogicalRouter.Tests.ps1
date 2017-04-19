#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Logical Routing" {

    BeforeAll{

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod, establish connection to NSX Manager and do any local variable definitions here

        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | select -first 1
        write-warning "Using cluster $cl for logical router appliance deployment"

        $script:ds = $cl | get-datastore | select -first 1
        write-warning "Using datastore $ds for logical router appliance deployment"

        $script:name = "pester_lr_lr1"
        $script:ls1_name = "pester_lr_ls1"
        $script:ls2_name = "pester_lr_ls2"
        $script:ls3_name = "pester_lr_ls3"
        $script:ls4_name = "pester_lr_ls4"
        $script:ls5_name = "pester_lr_ls5"
        $script:dgaddress = "1.1.1.254"
        $script:staticroutenet = "20.20.20.0/24"
        $script:staticroutenexthop = "1.1.1.254"
        $script:OspfAreaId = "50"
        $script:RouterId = "1.1.1.1"
        $script:LocalAS = "1234"
        $script:bgpneighbour = "1.1.1.254"
        $script:RemoteAS = "2345"
        $script:PrefixName = "pester_lr_prefix"
        $script:PrefixNetwork = "1.2.3.0/24"
        $tz = get-nsxtransportzone -LocalOnly | select -first 1
        $script:lswitches = @()
        $script:lswitches += $tz | new-nsxlogicalswitch $ls1_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls2_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls3_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls4_name
        $script:lswitches += $tz | new-nsxlogicalswitch $ls5_name

        $script:vnics = @()
        $script:vnics += New-NsxLogicalRouterInterfaceSpec -Type uplink -Name vNic0 -ConnectedTo $lswitches[0] -PrimaryAddress 1.1.1.1 -SubnetPrefixLength 24
        $script:vnics += New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic1 -ConnectedTo $lswitches[1] -PrimaryAddress 2.2.2.1 -SubnetPrefixLength 24
        $script:vnics += New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic2 -ConnectedTo $lswitches[2] -PrimaryAddress 3.3.3.1 -SubnetPrefixLength 24
    }

    it "Can create a logical router" {
        New-NsxLogicalRouter -Name $name -ManagementPortGroup $lswitches[4] -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds
        Get-NsxLogicalRouter $name | should not be $null
    }

    Context "Interfaces" {
        it "Can add a logical router lif" {
            Get-NsxLogicalRouter $name | New-NsxLogicalRouterInterface -Name Test -Type internal -ConnectedTo $lswitches[3] -PrimaryAddress 4.4.4.1 -SubnetPrefixLength 24
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface Test | should not be $null
        }

        it "Can update a logical router lif" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12 | Set-NsxLogicalRouterInterface -type internal -Name TestSet -ConnectedTo $lswitches[3] -confirm:$false
            $lif = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12
            $lif.ConnectedToName | should be $lswitches[3].Name
        }

        it "Can remove a logical router lif" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12 | Remove-NsxLogicalRouterInterface -confirm:$false
            $lif = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface -Index 12
            $lif | should be $null
        }
    }

    Context "Route Prefixes" {
        it "Can create a route prefix" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterPrefix -Name $PrefixName -Network $PrefixNetwork -confirm:$false
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterPrefix -name $PrefixName | should not be $null
        }
    }

    Context "Static Routing" {
        It "Can configure the default route" {
            $UplinkVnic = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface "vNic0"
            $UplinkVnicId = $uplinkVnic.index
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $UplinkVnicId -DefaultGatewayAddress $dgaddress -Confirm:$false
            $rtg = Get-NsxLogicalRouter $name | get-nsxlogicalrouterRouting
            $rtg.staticRouting.defaultRoute.gatewayAddress | should be $dgaddress
        }

        it "Can add a static route" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop -confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.staticRouting.staticRoutes | should not be $null
        }


        it "Can remove a static route" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | Remove-NsxLogicalRouterStaticRoute -Confirm:$false
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterStaticRoute -Network $staticroutenet -NextHop $staticroutenexthop | should be $null
        }
    }

    Context "OSPF" {

        It "Can enable OSPF and define router id" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspf -RouterId $routerId -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2" -Confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.routingGlobalConfig.routerId | should be $routerId
            $rtg.ospf.enabled | should be "true"
        }

        it "Can add an OSPF Area" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $OspfAreaId -Confirm:$false
            $area = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId $OspfAreaId
            $area | should not be $null
        }

        It "Can add an OSPF Interface" {
            $UplinkVnic = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface "vNic0"
            $UplinkVnicId = $uplinkVnic.index
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $OspfAreaId -Vnic $UplinkVnicId -confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.ospf.ospfInterfaces.ospfInterface | Where-Object { $_.vnic -eq $UplinkVnicId } | should not be $null
        }

        it "Can enable route redistribution into Ospf" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -PrefixName $PrefixName -Learner ospf -FromConnected -FromStatic -Action permit -confirm:$false
            $rule = Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -learner ospf  | ? { $_.prefixName -eq $PrefixName }
            $rule.from.connected | should be "true"
            $rule.from.static | should be "true"
        }

        it "Can remove ospf route redistribution rules" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false
            $rule = Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -learner ospf
            $rule | should be $null
        }

        it "Can retreive an empty result set of redistribution rules" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false
            $rule = Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule
            $rule | should be $null
        }

        it "Can remove an OSPF Interface" {
            $UplinkVnic = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterInterface "vNic0"
            $UplinkVnicId = $uplinkVnic.index
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfInterface -AreaId $OspfAreaId -VnicId $UplinkVnicId | Remove-NsxLogicalRouterOspfInterface -confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.ospf.ospfInterfaces.ospfInterface | Where-Object { $_.vnic -eq $UplinkVnicId } | should be $null
        }

        it "Can remove an OSPF Area" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId $OspfAreaId | Remove-NsxLogicalRouterOspfArea -confirm:$false
            $area = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId $OspfAreaId
            $area | should be $null
        }

        it "Can disable OSPF" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspf:$false -Confirm:$false -RouterId $routerId -LocalAS $LocalAS -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2"
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.ospf.enabled | should be "false"
        }
    }

    Context "BGP" {

        it "Can enable BGP" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgp -RouterId $routerId -LocalAS $LocalAS -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2" -Confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.routingGlobalConfig.routerId | should be $routerId
            $rtg.bgp.enabled | should be "true"
        }

        it "Can add a BGP Neighbour" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2" -confirm:$false
            $nbr = Get-NsxLogicalRouter $name  | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour
            $nbr.ipaddress | should be $bgpneighbour
        }

        it "Can enable route redistribution into BGP" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -PrefixName $PrefixName -Learner bgp -FromConnected -FromStatic -FromOspf -Action permit -confirm:$false
            $rule = Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -learner bgp
            $rule.from.connected | should be "true"
            $rule.from.static | should be "true"
            $rule.from.ospf | should be "true"
        }

        it "Can remove bgp route redistribution rules" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner bgp | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false
            $rule = Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -learner bgp
            $rule | should be $null
        }

        it "Can remove a BGP Neighbour" {
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | Remove-NsxLogicalRouterBgpNeighbour -confirm:$false
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs | should be $null
        }

        it "Can disable BGP" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgp:$false -Confirm:$false
            $rtg = Get-NSxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.bgp.enabled | should be "false"
        }

    }

    it "Can remove a logical router" {
        Get-NsxLogicalRouter $name | remove-nsxlogicalrouter -confirm:$false
        get-nsxlogicalrouter $name | should be $null
    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        write-warning "Cleaning up"
        if ( get-nsxlogicalrouter $name ) {
            get-nsxlogicalrouter $name | remove-nsxlogicalrouter -confirm:$false
        }
        start-sleep 5

        foreach ( $lswitch in $lswitches) {
            $lswitch | remove-nsxlogicalswitch -confirm:$false
        }
        disconnect-nsxserver
    }
}