#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Logical Routing" {

    BeforeAll{

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod, establish connection to NSX Manager and do any local variable definitions here

        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for logical router appliance deployment"

        $script:ds = $cl | get-datastore | Select-Object -first 1
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
        $script:bgpWeight = "10"
        $script:bgpWeight = "10"
        $script:bgpHoldDownTimer = "3"
        $script:bgpKeepAliveTimer = "1"
        $script:bgpPassword = "VMware1!"
        $script:PrefixName = "pester_lr_prefix"
        $script:PrefixNetwork = "1.2.3.0/24"
        $script:TenantName = "pester_tenant"
        $tz = get-nsxtransportzone -LocalOnly | Select-Object -first 1
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

        $script:uname1 = "pester_ulr1_lr1"
        $script:uls1_name1 = "pester_ulr1_uls1"
        $script:uls2_name1 = "pester_ulr1_uls2"
        $script:uls3_name1 = "pester_ulr1_uls3"
        $script:uls4_name1 = "pester_ulr1_uls4"
        $script:uls5_name1 = "pester_ulr1_uls5"
        $utz = get-nsxtransportzone -UniversalOnly | Select-Object -first 1
        $script:ulswitches1 = @()
        $script:ulswitches1 += $utz | new-nsxlogicalswitch $uls1_name1
        $script:ulswitches1 += $utz | new-nsxlogicalswitch $uls2_name1
        $script:ulswitches1 += $utz | new-nsxlogicalswitch $uls3_name1
        $script:ulswitches1 += $utz | new-nsxlogicalswitch $uls4_name1
        $script:ulswitches1 += $utz | new-nsxlogicalswitch $uls5_name1
        $script:uvnics1 = @()
        $script:uvnics1 += New-NsxLogicalRouterInterfaceSpec -Type uplink -Name vNic0 -ConnectedTo $ulswitches1[0] -PrimaryAddress 1.1.1.1 -SubnetPrefixLength 24
        $script:uvnics1 += New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic1 -ConnectedTo $ulswitches1[1] -PrimaryAddress 2.2.2.1 -SubnetPrefixLength 24
        $script:uvnics1 += New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic2 -ConnectedTo $ulswitches1[2] -PrimaryAddress 3.3.3.1 -SubnetPrefixLength 24

        $script:uname2 = "pester_ulr2_lr1"
        $script:uls1_name2 = "pester_ulr2_uls1"
        $script:uls2_name2 = "pester_ulr2_uls2"
        $script:uls3_name2 = "pester_ulr2_uls3"
        $script:uls4_name2 = "pester_ulr2_uls4"
        $script:uls5_name2 = "pester_ulr2_uls5"
        $utz = get-nsxtransportzone -UniversalOnly | Select-Object -first 1
        $script:ulswitches2 = @()
        $script:ulswitches2 += $utz | new-nsxlogicalswitch $uls1_name2
        $script:ulswitches2 += $utz | new-nsxlogicalswitch $uls2_name2
        $script:ulswitches2 += $utz | new-nsxlogicalswitch $uls3_name2
        $script:ulswitches2 += $utz | new-nsxlogicalswitch $uls4_name2
        $script:ulswitches2 += $utz | new-nsxlogicalswitch $uls5_name2
        $script:uvnics2 = @()
        $script:uvnics2 += New-NsxLogicalRouterInterfaceSpec -Type uplink -Name vNic0 -ConnectedTo $ulswitches2[0] -PrimaryAddress 1.1.1.1 -SubnetPrefixLength 24
        $script:uvnics2 += New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic1 -ConnectedTo $ulswitches2[1] -PrimaryAddress 2.2.2.1 -SubnetPrefixLength 24
        $script:uvnics2 += New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic2 -ConnectedTo $ulswitches2[2] -PrimaryAddress 3.3.3.1 -SubnetPrefixLength 24

        #bridging setup
        $script:bridgeportgroup1 = Get-VDSwitch | Select-Object -First 1 | New-VDPortgroup -VlanId 1234 -Name "pester_bridge_pg1"
        $script:bridgels1 = $tz | New-NsxLogicalSwitch -Name "pester_bridge_ls1"
        $script:bridgeportgroup2 = Get-VDSwitch | Select-Object -First 1 | New-VDPortgroup -VlanId 1235 -Name "pester_bridge_pg2"
        $script:bridgels2 = $tz | New-NsxLogicalSwitch -Name "pester_bridge_ls2"

        if ($script:DefaultNsxConnection.version -ge [version]"6.3.0") {
            # This flag is used  as some functions deprecated in NSX 6.3.0 or higher.
            $script:NSX630OrLaterVersion = $True
        }
        else {
            $script:NSX630OrLaterVersion = $False
        }

    }

    it "Can create a logical router" {
        New-NsxLogicalRouter -Tenant $TenantName -Name $name -ManagementPortGroup $lswitches[4] -Interface $vnics[0],$vnics[1],$vnics[2] -Cluster $cl -Datastore $ds
        $lr = Get-NsxLogicalRouter $name
        $lr | should not be $null
        $lr.tenant | should be $TenantName
    }

    it "Can create a universal logical router with Local Egress enabled" {
        $udlr1 = New-NsxLogicalRouter -Name $uname1 -ManagementPortGroup $ulswitches1[4] -Interface $uvnics1[0],$uvnics1[1],$uvnics1[2] -Cluster $cl -Datastore $ds -Universal -EnableLocalEgress
        $udlr1 | should not be $null
        $udlr1.isUniversal | should be "true"
        $udlr1.localEgressEnabled | should be "true"
    }

    it "Can create a universal logical router with Local Egress disabled" {
        $udlr2 = New-NsxLogicalRouter -Name $uname2 -ManagementPortGroup $ulswitches2[4] -Interface $uvnics2[0],$uvnics2[1],$uvnics2[2] -Cluster $cl -Datastore $ds -Universal
        $udlr2 | should not be $null
        $udlr2.isUniversal | should be "true"
        $udlr2.localEgressEnabled | should be "false"
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

    Context "Bridging"  {

        AfterEach{
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | Get-NsxLogicalRouterBridge | Remove-NSxLogicalRouterBridge -Confirm:$false
        }

        It "Can enable bridge configuration for a logical router" {
            $bridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | Set-NsxLogicalRouterBridging -enabled -confirm:$false
            $bridge | should not be $null
            $Bridge.enabled | should be "true"
        }

        It "Can create a bridge instance" {
            $bridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge -Name "pester_bridge_1" -PortGroup $BridgePortGroup1 -LogicalSwitch $bridgels1
            $bridge | should not be $null
            $Bridge.Name| should be "pester_bridge_1"
        }

        It "Can retrieve a bridge instance by name" {
            $null = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge -Name "pester_bridge_1" -PortGroup $BridgePortGroup1 -LogicalSwitch $bridgels1
            $bridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge -Name "pester_bridge_2" -PortGroup $BridgePortGroup2 -LogicalSwitch $bridgels2
            $bridge | should not be $null
            $GetBridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | Get-NsxLogicalRouterBridge -Name "pester_bridge_2"
            ($GetBridge | Measure-Object).count | should be 1
            $GetBridge.Name| should be "pester_bridge_2"
        }

        It "Can retrieve a bridge instance by id" {
            $null = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge -Name "pester_bridge_1" -PortGroup $BridgePortGroup1 -LogicalSwitch $bridgels1
            $bridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge -Name "pester_bridge_2" -PortGroup $BridgePortGroup2 -LogicalSwitch $bridgels2
            $bridge | should not be $null
            $GetBridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | Get-NsxLogicalRouterBridge -bridgeId $bridge.bridgeId
            ($GetBridge | Measure-Object).count | should be 1
            $GetBridge.bridgeId| should be $bridge.bridgeId
        }

        It "Can remove a bridge instance" {
            $firstbridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge -Name "pester_bridge_1" -PortGroup $BridgePortGroup1 -LogicalSwitch $bridgels1
            $bridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge -Name "pester_bridge_2" -PortGroup $BridgePortGroup2 -LogicalSwitch $bridgels2
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | Get-NsxLogicalRouterBridge -bridgeId $bridge.bridgeId | Remove-NsxLogicalRouterBridge -Confirm:$false
            $bridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | Get-NsxLogicalRouterBridge
            ($bridge | Measure-Object).count | should be 1
            $bridge.bridgeId| should be $firstbridge.bridgeId
        }

        It "Can disable bridge configuration for a logical router" {
            $bridge = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterBridging | Set-NsxLogicalRouterBridging -enabled:$false -confirm:$false
            $bridge | should not be $null
            $Bridge.enabled | should be "false"
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
            $rule = Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -learner ospf  | Where-Object { $_.prefixName -eq $PrefixName }
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

        it "Can disable Graceful Restart" {
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg | should not be $null
            $rtg.ospf.gracefulRestart | should be true
            $rtg | Set-NsxLogicalRouterOspf -GracefulRestart:$false -confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.ospf.gracefulRestart | should be false
        }

        it "Cannot enable Default Originate in NSX 6.3.0 or later" -Skip:( -not $NSX630OrLaterVersion) {
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg | should not be $null
            {$rtg | Set-NsxLogicalRouterOspf -DefaultOriginate -confirm:$false} | should throw "Setting defaultOriginate on a logical router is not supported NSX 6.3.0 or later."
        }

        it "Can enable Default Originate in earlier version than 6.3.0" -Skip:$($NSX630OrLaterVersion) {
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg | should not be $null
            $rtg.ospf.defaultOriginate | should be false
            $rtg | Set-NsxLogicalRouterOspf -DefaultOriginate -confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.ospf.defaultOriginate | should be true
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
            Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $bgpneighbour -RemoteAS $RemoteAs -ForwardingAddress "1.1.1.1" -ProtocolAddress "1.1.1.2" -Weight $bgpWeight -KeepAliveTimer $bgpKeepAliveTimer -HoldDownTimer $bgpHoldDownTimer -Password $bgpPassword -confirm:$false
            $nbr = Get-NsxLogicalRouter $name  | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour
            $nbr.ipaddress | should be $bgpneighbour
            $nbr.remoteAS | should be $RemoteAs
            $nbr.forwardingAddress | should be "1.1.1.1"
            $nbr.protocolAddress | should be "1.1.1.2"
            $nbr.weight | should be $bgpWeight
            $nbr.keepAliveTimer | should be $bgpKeepAliveTimer
            $nbr.holdDownTimer | should be $bgpHoldDownTimer
            ($nbr | Get-Member -MemberType Properties -Name password).count | should be 1
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

        it "Can disable Graceful Restart" {
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg | should not be $null
            $rtg.bgp.gracefulRestart | should be true
            $rtg | Set-NsxLogicalRouterBgp -GracefulRestart:$false -confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.bgp.gracefulRestart | should be false
        }

        it "Cannot enable Default Originate in NSX 6.3.0 or later" -Skip:(-not $NSX630OrLaterVersion) {
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg | should not be $null
            {$rtg | Set-NsxLogicalRouterBgp -DefaultOriginate -confirm:$false} | should throw "Setting defaultOriginate on a logical router is not supported NSX 6.3.0 or later."
        }

        it "Can enable Default Originate in earlier version than 6.3.0" -Skip:$NSX630OrLaterVersion {
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg | should not be $null
            $rtg.bgp.defaultOriginate | should be false
            $rtg | Set-NsxLogicalRouterBgp -DefaultOriginate -confirm:$false
            $rtg = Get-NsxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.bgp.defaultOriginate | should be true
        }

        it "Can disable BGP" {
            Get-NsxLogicalRouter $Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgp:$false -Confirm:$false
            $rtg = Get-NSxLogicalRouter $name | Get-NsxLogicalRouterRouting
            $rtg.bgp.enabled | should be "false"
        }

    }

    it "Can disable firewall by Set-NsxLogicalRouter" {
        $lr = Get-NsxLogicalRouter $name
        $lr | should not be $null
        $lr.features.firewall.enabled | should be "true"
        $lr.features.firewall.enabled = "false"
        $lr | Set-NsxLogicalRouter -confirm:$false
        $lr = Get-NsxLogicalRouter $name
        $lr.features.firewall.enabled | should be "false"
    }

    it "Can remove a logical router" {
        Get-NsxLogicalRouter $name | remove-nsxlogicalrouter -confirm:$false
        get-nsxlogicalrouter $name | should be $null
    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        write-warning "Cleaning up distributed logical router"
        if ( get-nsxlogicalrouter $name ) {
            get-nsxlogicalrouter $name | remove-nsxlogicalrouter -confirm:$false
        }
        start-sleep 5

        foreach ( $lswitch in $lswitches) {
            $lswitch | remove-nsxlogicalswitch -confirm:$false
        }

        write-warning "Cleaning up universal distributed logical router 1"
        if ( get-nsxlogicalrouter $uname1 ) {
            get-nsxlogicalrouter $uname1 | remove-nsxlogicalrouter -confirm:$false
        }
        start-sleep 5

        foreach ( $ulswitch1 in $ulswitches1) {
            $ulswitch1 | remove-nsxlogicalswitch -confirm:$false
        }

        write-warning "Cleaning up universal distributed logical router 2"
        if ( get-nsxlogicalrouter $uname2 ) {
            get-nsxlogicalrouter $uname2 | remove-nsxlogicalrouter -confirm:$false
        }
        start-sleep 5

        foreach ( $ulswitch2 in $ulswitches2) {
            $ulswitch2 | remove-nsxlogicalswitch -confirm:$false
        }

        $bridgels1 | Remove-NSxLogicalSwitch -Confirm:$false
        $bridgels2 | Remove-NSxLogicalSwitch -Confirm:$false
        Get-vdPortGroup pester* | Remove-VDPortGroup -Confirm:$false

        disconnect-nsxserver
    }
}
