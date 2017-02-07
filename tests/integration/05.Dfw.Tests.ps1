
#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestNSXManager ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Distributed Firewall" {


    $brokenSpecificAppliedTo = $true

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        write-host -ForegroundColor Green "Performing setup tasks for DFW tests"
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | select -first 1
        write-warning "Using cluster $cl for edge appliance deployment"
        $script:ds = $cl | get-datastore | select -first 1
        write-warning "Using datastore $ds for edge appliance deployment"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:dfwedgename = "pester_dfw_edge1"
        $script:dfwedgeIp1 = "1.1.1.1"
        $script:Password = "VMware1!VMware1!"
        $script:tenant = "pester_dfw_tenant1"
        $script:l3sectionname = "pester_dfw_l3section1"
        $script:l2sectionname = "pester_dfw_l2section1"
        $script:testVMName1 = "pester_dfw_vm1"
        $script:testVMName2 = "pester_dfw_vm2"
        $script:testSGName1 = "pester_dfw_sg1"
        $script:testSGName2 = "pester_dfw_sg2"
        $script:testIPSetName = "pester_dfw_ipset1"
        $script:testIPs = "1.1.1.1,2.2.2.2"
        $script:testServiceName1 = "pester_dfw_svc1"
        $script:testServiceName2 = "pester_dfw_svc2"
        $script:testPort = "80"
        $script:testPortRange = "80-88"
        $script:testPortSet = "80,88"
        $script:testServiceProto = "tcp"
        $script:testlsname = "pester_dfw_ls1"
        $script:TestMacSetName1 = "pester_dfw_macset1"
        $script:TestMacSetName2 = "pester_dfw_macset2"
        $script:TestMac1 = "00:50:56:00:00:00"
        $script:TestMac2 = "00:50:56:00:00:01"
        $script:cpuThreshold = "75"
        $script:cpuThreshold1 = "85"
        $script:memoryThreshold = "75"
        $script:memoryThreshold1 = "85" 
        $script:cpsThreshold = "125000"
        $script:cpsThreshold1 = "200000"
        $script:cpsDefault = "100000"
        $script:memorydefault = "100"
        $script:cpudefault = "100"
        
        
        $script:

        #Logical Switch
        $script:testls = Get-NsxTransportZone | select -first 1 | New-NsxLogicalSwitch $testlsname

        #Create Edge
        $vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $testls -PrimaryAddress $dfwedgeIp1 -SubnetPrefixLength 24
        $script:dfwEdge = New-NsxEdge -Name $dfwedgename -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -hostname "pester-dfw-edge1"

        #VMs
        $vmhost = $cl | get-vmhost | select -first 1
        $folder = get-folder -type VM -name vm
        $vmsplat = @{
            "VMHost" = $vmhost
            "Location" = $folder
            "ResourcePool" = $cl
            "Datastore" = $ds
            "DiskGB" = 1
            "DiskStorageFormat" = "Thin"
            "NumCpu" = 1
            "Floppy" = $false
            "CD" = $false
            "GuestId" = "other26xLinuxGuest"
            "MemoryMB" = 512
        }
        $script:testvm1 = new-vm -name $testVMName1 @vmsplat
        $script:testvm2 = new-vm -name $testVMName2 @vmsplat

        #Create Groupings
        $script:TestIpSet = New-NsxIpSet -Name $testIPSetName -Description "Pester dfw Test IP Set" -IpAddresses $testIPs
        $script:TestMacSet1 = New-NsxMacSet -Name $testMacSetName1 -Description "Pester dfw Test MAC Set1" -MacAddresses "$TestMac1,$TestMac2"
        $script:TestMacSet2 = New-NsxMacSet -Name $testMacSetName2 -Description "Pester dfw Test MAC Set2" -MacAddresses "$TestMac1,$TestMac2"
        $script:TestSG1 = New-NsxSecurityGroup -Name $testSGName1 -Description "Pester dfw Test SG1" -IncludeMember $testVM1, $testVM2
        $script:TestSG2 = New-NsxSecurityGroup -Name $testSGName2 -Description "Pester dfw Test SG2" -IncludeMember $TestIpSet
        $script:TestService1 = New-NsxService -Name $TestServiceName1 -Protocol $TestServiceProto -port $testPort
        $script:TestService2 = New-NsxService -Name $TestServiceName2 -Protocol $TestServiceProto -port "$testPort,$testPortRange,$testPortSet"

        write-host -ForegroundColor Green "Completed setup tasks for DFW tests"

    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        write-host -ForegroundColor Green "Performing cleanup tasks for DFW tests"
        get-vm $testVMName1 | remove-vm -Confirm:$false
        get-vm $testVMName2 | remove-vm -Confirm:$false
        get-nsxedge $dfwedgename | remove-nsxedge -confirm:$false
        start-sleep 5

        Get-NsxFirewallSection $l3sectionname | Remove-NsxFirewallSection -Confirm:$false -force:$true
        Get-NsxFirewallSection $l2sectionname -sectionType layer2sections | Remove-NsxFirewallSection -Confirm:$false -force:$true
        get-nsxlogicalswitch $testlsname | Remove-NsxLogicalSwitch -Confirm:$false
        get-nsxipset $testIPSetName  | Remove-NsxIpSet -Confirm:$false
        get-nsxmacset $TestMacSetName1 | Remove-NsxMacSet -Confirm:$false
        get-nsxmacset $TestMacSetName2 | Remove-NsxMacSet -Confirm:$false
        Get-NsxSecurityGroup $testSGName1 | Remove-NsxSecurityGroup -confirm:$false
        Get-NsxSecurityGroup $testSGName2 | Remove-NsxSecurityGroup -confirm:$false
        Get-NsxService $TestServiceName1 | Remove-NsxService -confirm:$false
        Get-NsxService $TestServiceName2 | Remove-NsxService -confirm:$false

        Set-NsxFirewallThreshold -Cpu 100 -Memory 100 -ConnectionsPerSecond 100000 | out-null

        disconnect-nsxserver
        write-host -ForegroundColor Green "Completed cleanup tasks for DFW tests"

    }

    Context "DFW Global options" {
        it "Can validate default DFW event thresholds"{
            #Unsure if this is correct "test"
            $threshold = Get-NsxFirewallThreshold
            $threshold | should not be $null
            $threshold.Cpu | should be $cpuDefault
            $threshold.Memory | should be $memoryDefault
            $threshold.ConnectionsPerSecond | should be $cpsDefault
        }
        it "Can adjust all DFW event thresholds" {
            $threshold = Set-NsxFirewallThreshold -Cpu $cputhreshold -Memory $memorythreshold -ConnectionsPerSecond $cpsThreshold
            $threshold | should not be $null
            $threshold.Cpu | should be $cputhreshold
            $threshold.Memory | should be $memorythreshold
            $threshold.ConnectionsPerSecond | should be $cpsThreshold
        }
        it "Can adjust Memory DFW event threshold" {
            $threshold = Set-NsxFirewallThreshold  -Memory $memorythreshold1
            $threshold | should not be $null
            
            $threshold.Memory | should be $memorythreshold1
        }
        it "Can adjust CPU DFW event threshold" {
            $threshold = Set-NsxFirewallThreshold -Cpu $cputhreshold1
            $threshold | should not be $null
            $threshold.Cpu | should be $cputhreshold1
        }
        it "Can adjust ConnectionsPerSecond DFW event thresholds" {
            $threshold = Set-NsxFirewallThreshold -ConnectionsPerSecond $cpsThreshold1
            $threshold | should not be $null
            $threshold.ConnectionsPerSecond | should be $cpsThreshold1
        }

        it "Can adjust Global Containers"{

        }

        it "Can adjust TCP Optimisation"{

        }
    }
     

    Context "L3 Sections" {
        it "Can create an L3 section" {
            $section = New-NsxFirewallSection $l3sectionname
            $section | should not be $null
            $section = Get-NsxFirewallSection $l3sectionname
            $section | should not be $null
            @($section).count | should be 1
            $section.name | should be $l3sectionname
        }

        it "Fails to delete an L3 section with rules in it" {
            $section = Get-NsxFirewallSection $l3sectionname
            $section | should not be $null
            $rule = $section | New-NsxFirewallRule -Name "pester_dfw_testrule1" -Action allow
            $rule | should not be $null
            $section = Get-NsxFirewallSection $l3sectionname
            { $section | Remove-NsxFirewallSection -Confirm:$false } | should Throw
        }

        it "Can delete an L3 section with rules in it when forced" {
            $section = Get-NsxFirewallSection $l3sectionname
            $section | should not be $null
            $section | Get-NsxFirewallRule | should not be $null
            { $section | Remove-NsxFirewallSection -Confirm:$false -force } | should not Throw
        }

        it "Can delete an L3 Section" {
            $section = New-NsxFirewallSection $l3sectionname
            $section | should not be $null
            @($section).count | should be 1
            $defaultNsxConnection.DebugLogging = $true
            $section | Remove-NsxFirewallSection -confirm:$false
            $defaultNsxConnection.DebugLogging = $false
            $section = Get-NsxFirewallSection $l3sectionname
            $section | should be $null
        }
    }
    Context "L2 Sections" {

        it "Can create an L2 section" {
            $section = New-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections
            $section | should not be $null
            $section = Get-NsxFirewallSection -name $l2sectionname -sectionType layer2sections
            $section | should not be $null
            @($section).count | should be 1
            $section.name | should be $l2sectionname
        }

        it "Can delete an L2 Section" {
            $section = Get-NsxFirewallSection -name $l2sectionname -sectionType layer2sections
            $section | should not be $null
            @($section).count | should be 1
            $section | Remove-NsxFirewallSection -confirm:$false
            $section = Get-NsxFirewallSection -name $l2sectionname -sectionType layer2sections
            $section | should be $null
        }

        it "Fails to delete an L2 section with rules in it" {
            $section = New-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections
            $section | should not be $null
            $rule = $section | New-NsxFirewallRule -Name "pester_dfw_testrule1" -Action allow -RuleType "layer2sections"
            $rule | should not be $null
            $section = Get-NsxFirewallSection -name $l2sectionname -sectionType layer2sections
            { $section | Remove-NsxFirewallSection -Confirm:$false } | should Throw
        }

        it "Can delete an L2 section with rules in it when forced" {
            $section = Get-NsxFirewallSection -name $l2sectionname -sectionType layer2sections
            $section | should not be $null
            $section | Get-NsxFirewallRule | should not be $null
            { $section | Remove-NsxFirewallSection -Confirm:$false -force } | should not Throw
        }
    }

    Context "L3 Rules" {

        it "Can create an l3 allow any - any rule" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
        }

        it "Can create an l3 deny any - any rule" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
        }

        it "Can create an l3 rule with an ip based source" {
        }

        it "Can create an l3 rule with an ipset based source" {
        }

        it "Can create an l3 rule with a security group based source" {
        }

        it "Can create an l3 rule with a cluster based source" {
        }

        it "Can create an l3 rule with a vmhost based source" {
        }

        it "Can create an l3 rule with a datacenter based source" {
        }

        it "Can create an l3 rule with a dvportgroup based source" {
        }

        it "Can create an l3 rule with an lswitch based source" {
        }

        it "Can create an l3 rule with a resource pool based source" {
        }

        it "Can create an l3 rule with an vapp based source" {
        }

        it "Can create an l3 rule with an vnic based source" {
        }

        it "Can create an l3 rule with an ip based destination" {
        }

        it "Can create an l3 rule with an ipset based destination" {
        }

        it "Can create an l3 rule with a security group based destination" {
        }

        it "Can create an l3 rule with a cluster based destination" {
        }

        it "Can create an l3 rule with a vmhost based destination" {
        }

        it "Can create an l3 rule with a datacenter based destination" {
        }

        it "Can create an l3 rule with a dvportgroup based destination" {
        }

        it "Can create an l3 rule with an lswitch based destination" {
        }

        it "Can create an l3 rule with a resource pool based destination" {
        }

        it "Can create an l3 rule with an vapp based destination" {
        }

        it "Can create an l3 rule with an vnic based destination" {
        }

        it "Can create an l3 rule with an ip based applied to" {
        }

        it "Can create an l3 rule with an ipset based applied to" {
        }

        it "Can create an l3 rule with a security group based applied to" {
        }

        it "Can create an l3 rule with a cluster based applied to" {
        }

        it "Can create an l3 rule with a vmhost based applied to" {
        }

        it "Can create an l3 rule with a datacenter based applied to" {
        }

        it "Can create an l3 rule with a dvportgroup based applied to" {
        }

        it "Can create an l3 rule with an lswitch based applied to" {
        }

        it "Can create an l3 rule with a resource pool based applied to" {
        }

        it "Can create an l3 rule with a vapp based applied to" {
        }

        it "Can create an l3 rule with a vnic based applied to" {
        }

        it "Can create an l3 rule with a negated source" {
        }

        it "Can create an l3 rule with a negated destination" {
        }


        it "Can create an l3 rule with vm based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.sources.source).count | should be 1
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.sources.source.name | should be $testVmName1
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with vm based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $testvm1 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            @($rule.destinations.destination).count | should be 1
            $rule.destinations.destination.name | should be $testVmName1
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with vm based applied to" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -appliedTo $testvm1
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedTo).count | should be 1
            $rule.appliedToList.appliedTo.name | should be $testVmName1
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with specific service" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -service $testService1
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 1
            $rule.services.service.name | should be $testServiceName1
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with single source, destination, applied to and service" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1 -destination $testvm2 -action allow -appliedTo $testvm1 -service $testService1
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.sources.source).count | should be 1
            @($rule.destinations.destination).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 1
            @($rule.services.service).count | should be 1
            $rule.sources.source.name | should be $testVmName1
            $rule.destinations.destination.name | should be $testVmName2
            $rule.appliedToList.appliedTo.name | should be $testVmName1
            $rule.services.service.name | should be $testService1.Name
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with multiple vm based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1,$testvm2 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should beoftype System.Xml.XmlElement
            @($rule.sources.source).count | should be 2
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $rule.sources.source.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with multiple vm based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $testvm1,$testvm2 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations | should beoftype System.Xml.XmlElement
            @($rule.destinations.destination).count | should be 2
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $rule.destinations.destination.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with multiple vm based appliedto" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -appliedTo $testvm1,$testvm2 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedTo).count | should be 2
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $rule.appliedToList.appliedTo.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with multiple services" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -service $testService1, $testService2 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 2
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedNames = ( @($testService1.name, $testService2.name) | Sort-Object)
            $rule.services.service.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l3 rule with multiple item based source, destination, applied to and service" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1,$testvm2 -destination $testvm1,$testvm2 -action allow -appliedTo $testvm1,$testvm2 -Service $TestService1, $TestService2
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should beoftype System.Xml.XmlElement
            $rule.destinations | should beoftype System.Xml.XmlElement
            $rule.appliedToList | should beoftype System.Xml.XmlElement
            @($rule.services.service).count | should be 2
            @($rule.appliedToList.appliedTo).count | should be 2
            @($rule.destinations.destination).count | should be 2
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $sortedServiceNames = ( @($TestService1.name, $TestService2.name) | Sort-Object )
            $rule.sources.source.name | sort-object | should be $sortedNames
            $rule.destinations.destination.name | sort-object | should be $sortedNames
            $rule.appliedToList.appliedTo.name  | sort-object | should be $sortedNames
            $rule.services.service.name  | sort-object | should be $sortedServiceNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an L3 rule with different element types in the source, destination and applied to fields" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1,$testsg1 -destination $testvm1,$testsg1 -action allow -appliedTo $TestSG1,$TestVM1 -tag "Test MultiType"
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should beoftype System.Xml.XmlElement
            $rule.destinations | should beoftype System.Xml.XmlElement
            $rule.appliedToList | should beoftype System.Xml.XmlElement
            $sortedNames = ( @($testvm1.name, $testsg1.name) | Sort-Object)
            $rule.sources.source.name | sort-object | should be $sortedNames
            $rule.destinations.destination.name | sort-object | should be $sortedNames
            $rule.appliedToList.appliedTo.name  | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an L3 rule with a tag" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -tag "Test Tag"
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.tag | should beexactly "Test Tag"
            $rule.name | should be "pester_dfw_rule1"
        }

        #############
        it "Can create a rule to apply to all edges plus dfw" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -ApplyToAllEdges
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.appliedToList.appliedTo).count | should not be 1
            $rule.appliedToList.appliedTo.Name -contains "ALL_EDGES" | should be $true
            $rule.appliedToList.appliedTo.Name -contains "DISTRIBUTED_FIREWALL" | should be $true
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create a rule to apply to all edges and not dfw" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -ApplyToAllEdges -ApplyToDfw:$false
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "ALL_EDGES"
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create a rule to apply to a specific edge" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -AppliedTo $dfwEdge -ApplyToDfw:$false
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be $dfwEdgeName
            $rule.appliedToList.appliedTo.Value | should be $dfwEdge.id
            $rule.appliedToList.appliedTo.Type | should be edge
            $rule.name | should be "pester_dfw_rule1"
        }

        BeforeEach {
            #create new sections for each test.

            $script:l3sec = New-NsxFirewallSection -Name $l3sectionname
        }
        AfterEach {
            #tear down new sections after each test.
            # read-host "waiting"
            if ($pause) { read-host "pausing" }
            Get-NsxFirewallSection -Name $l3sectionname | Remove-NsxFirewallSection -force -Confirm:$false
        }
    }

    Context "L2 Rules" {


        it "Can create an l2 rule with an ip based source" {
        }

        it "Can create an l2 rule with an ipset based source" {
        }

        it "Can create an l2 rule with a security group based source" {
        }

        it "Can create an l2 rule with a cluster based source" {
        }

        it "Can create an l2 rule with a vmhost based source" {
        }

        it "Can create an l2 rule with a datacenter based source" {
        }

        it "Can create an l2 rule with a dvportgroup based source" {
        }

        it "Can create an l2 rule with an lswitch based source" {
        }

        it "Can create an l2 rule with a resource pool based source" {
        }

        it "Can create an l2 rule with an vapp based source" {
        }

        it "Can create an l2 rule with an vnic based source" {
        }

        it "Can create an l2 rule with an ip based destination" {
        }

        it "Can create an l2 rule with an ipset based destination" {
        }

        it "Can create an l2 rule with a security group based destination" {
        }

        it "Can create an l2 rule with a cluster based destination" {
        }

        it "Can create an l2 rule with a vmhost based destination" {
        }

        it "Can create an l2 rule with a datacenter based destination" {
        }

        it "Can create an l2 rule with a dvportgroup based destination" {
        }

        it "Can create an l2 rule with an lswitch based destination" {
        }

        it "Can create an l2 rule with a resource pool based destination" {
        }

        it "Can create an l2 rule with an vapp based destination" {
        }

        it "Can create an l2 rule with an vnic based destination" {
        }

        it "Can create an l2 rule with an ip based applied to" {
        }

        it "Can create an l2 rule with an ipset based applied to" {
        }

        it "Can create an l2 rule with a security group based applied to" {
        }

        it "Can create an l2 rule with a cluster based applied to" {
        }

        it "Can create an l2 rule with a vmhost based applied to" {
        }

        it "Can create an l2 rule with a datacenter based applied to" {
        }

        it "Can create an l2 rule with a dvportgroup based applied to" {
        }

        it "Can create an l2 rule with an lswitch based applied to" {
        }

        it "Can create an l2 rule with a resource pool based applied to" {
        }

        it "Can create an l2 rule with a vapp based applied to" {
        }

        it "Can create an l2 rule with a vnic based applied to" {
        }

        it "Can create an l2 rule with a negated source" {
        }

        it "Can create an l2 rule with a negated destination" {
        }

        it "Can create an l2 allow any - any rule" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
        }

        it "Can create an l2 deny any - any rule" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
        }

        it "Can create an l2 rule with macset based source" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testmacset1 -action allow -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.sources.source).count | should be 1
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.sources.source.name | should be $TestMacSetName1
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with macset based destination" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $testmacset1 -action allow -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            @($rule.destinations.destination).count | should be 1
            $rule.destinations.destination.name | should be $TestMacSetName1
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with vm based applied to" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -appliedTo $TestVM1 -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedTo).count | should be 1
            $rule.appliedToList.appliedTo.name | should be $testVmName1
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with specific service" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -service $testService1 -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 1
            $rule.services.service.name | should be $testServiceName1
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with single source, destination, applied to and service" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $TestMacSet1 -destination $TestMacSet2 -action allow -appliedTo $testvm1 -service $testService1 -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.sources.source).count | should be 1
            @($rule.destinations.destination).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 1
            @($rule.services.service).count | should be 1
            $rule.sources.source.name | should be $TestMacSetName1
            $rule.destinations.destination.name | should be $TestMacSetName2
            $rule.appliedToList.appliedTo.name | should be $testVmName1
            $rule.services.service.name | should be $testService1.Name
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with multiple vm based source" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1,$testvm2 -action allow -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections| Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should beoftype System.Xml.XmlElement
            @($rule.sources.source).count | should be 2
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $rule.sources.source.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with multiple vm based destination" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $testvm1,$testvm2 -action allow -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations | should beoftype System.Xml.XmlElement
            @($rule.destinations.destination).count | should be 2
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $rule.destinations.destination.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with multiple vm based appliedto" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -appliedTo $testvm1,$testvm2 -action allow -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedTo).count | should be 2
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $rule.appliedToList.appliedTo.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with multiple services" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -service $testService1, $testService2 -action allow -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 2
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedNames = ( @($testService1.name, $testService2.name) | Sort-Object)
            $rule.services.service.name | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an l2 rule with multiple item based source, destination, applied to and service" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1,$testvm2 -destination $testvm1,$testvm2 -action allow -appliedTo $testvm1,$testvm2 -Service $TestService1, $TestService2 -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should beoftype System.Xml.XmlElement
            $rule.destinations | should beoftype System.Xml.XmlElement
            $rule.appliedToList | should beoftype System.Xml.XmlElement
            @($rule.services.service).count | should be 2
            @($rule.appliedToList.appliedTo).count | should be 2
            @($rule.destinations.destination).count | should be 2
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $sortedServiceNames = ( @($TestService1.name, $TestService2.name) | Sort-Object )
            $rule.sources.source.name | sort-object | should be $sortedNames
            $rule.destinations.destination.name | sort-object | should be $sortedNames
            $rule.appliedToList.appliedTo.name  | sort-object | should be $sortedNames
            $rule.services.service.name  | sort-object | should be $sortedServiceNames
            $rule.name | should be "pester_dfw_rule1"
        }

        #Busted - applied to bug
        it "Can create an L2 rule with different element types in the source, destination and applied to fields"  {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1,$testsg1 -destination $testvm1,$testsg1 -action allow -appliedTo $TestSG1,$TestVM1 -tag "Test MultiType" -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 2
            $rule.sources | should beoftype System.Xml.XmlElement
            $rule.destinations | should beoftype System.Xml.XmlElement
            $rule.appliedToList | should beoftype System.Xml.XmlElement
            $sortedNames = ( @($testvm1.name, $testsg1.name) | Sort-Object)
            $rule.sources.source.name | sort-object | should be $sortedNames
            $rule.destinations.destination.name | sort-object | should be $sortedNames
            $rule.appliedToList.appliedTo.name  | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
        }

        it "Can create an L2 rule with a tag" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -tag "Test Tag" -RuleType layer2sections
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1" -RuleType layer2sections
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.tag | should beexactly "Test Tag"
            $rule.name | should be "pester_dfw_rule1"
        }

        BeforeEach {
            #create new sections for each test.

            $script:l2sec = New-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections
        }
        AfterEach {
            #tear down new sections after each test.
            # read-host "waiting"
            if ($pause) { read-host "pausing" }
            Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections| Remove-NsxFirewallSection -force -Confirm:$false
        }
    }

}
