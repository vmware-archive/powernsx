
#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "DFW" {


    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        write-host -ForegroundColor Green "Performing setup tasks for DFW tests"
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for edge appliance deployment"
        $script:ds = $cl |  get-datastore | Select-Object -first 1
        write-warning "Using datastore $ds for edge appliance deployment"
        $script:dc = Get-Datacenter | Select-Object -first 1
        write-warning "Using Datacenter $dc for object identifier"

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
        $script:testVMName3 = "pester_dfw_vm3"
        $script:testSGName1 = "pester_dfw_sg1"
        $script:testSGName2 = "pester_dfw_sg2"
        $script:testRpname = "pester_dfw_rp"
        $script:testIPSetName = "pester_dfw_ipset1"
        $script:testIPSetName2 = "pester_dfw_ipset2"
        $script:testIPs = "1.1.1.1,2.2.2.2"
        $script:testIPs2 = "1.1.1.0/24"
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
        $script:Testdvportgroupname = "pester_dfw_pg1"
        $script:vAppName = "pester_dfw_vapp"
        $script:rawService1 = "ICMP"
        $script:rawService2 = "tcp/80"
        $script:rawService3 = "udp/49152-65535"
        $script:rawService4 = "udp/53"
        $script:rawService5 = "TCP"
        $script:rawService6 = "UDP"
        $script:TestDraftName1 = "pester_draft_1"
        $script:TestDraftName2 = "pester_draft_2"
        $script:TestDraftName3 = "pester_draft_3"
        $script:TestDraftDesc1 = "pester_draft_description_1"
        $script:TestDraftDesc2 = "pester_draft_description_2"
        $script:TestDraftDesc3 = "pester_draft_description_3"
        $script:TestDraftUpdatedName = "pester_draft_updated_name"
        $script:TestDraftUpdatedDesc = "pester_draft_updated_desc"


        #Logical Switch
        $script:testls = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $testlsname

        #Create Edge

        $vnic0 = New-NsxEdgeInterfaceSpec -index 1 -Type uplink -Name "vNic1" -ConnectedTo $testls -PrimaryAddress $dfwedgeIp1 -SubnetPrefixLength 24
        $script:dfwEdge = New-NsxEdge -Name $dfwedgename -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -tenant $tenant -enablessh -hostname "pester-dfw-edge1"
        #VMs
        $vmhost = $cl | get-vmhost | Select-Object -first 1
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
        $script:testvm3 = new-vm -name $testVMName3 @vmsplat

        #Create Groupings
        $script:TestIpSet = New-NsxIpSet -Name $testIPSetName -Description "Pester dfw Test IP Set" -IpAddress $testIPs
        $script:TestIpSet2 = New-NsxIpSet -Name $testIPSetName2 -Description "Pester dfw Test IP Set2" -IpAddress $testIPs2
        $script:TestMacSet1 = New-NsxMacSet -Name $testMacSetName1 -Description "Pester dfw Test MAC Set1" -MacAddresses "$TestMac1,$TestMac2"
        $script:TestMacSet2 = New-NsxMacSet -Name $testMacSetName2 -Description "Pester dfw Test MAC Set2" -MacAddresses "$TestMac1,$TestMac2"
        $script:TestSG1 = New-NsxSecurityGroup -Name $testSGName1 -Description "Pester dfw Test SG1" -IncludeMember $testVM1, $testVM2
        $script:TestSG2 = New-NsxSecurityGroup -Name $testSGName2 -Description "Pester dfw Test SG2" -IncludeMember $TestIpSet
        $script:TestService1 = New-NsxService -Name $TestServiceName1 -Protocol $TestServiceProto -port $testPort
        $script:TestService2 = New-NsxService -Name $TestServiceName2 -Protocol $TestServiceProto -port "$testPort,$testPortRange,$testPortSet"

        $script:TestDvPortgroup = Get-VDSwitch | Select-Object -first 1 | New-VDPortgroup -name $testdvportgroupname

        #Create Resource pool

        $script:testresourcepool = Get-ResourcePool | Select-Object -first 1 | New-ResourcePool -name $testRpname -CpuExpandableReservation $true -CpuReservationMhz 0 -CpuSharesLevel low

        # Create vapp

        $script:testvapp = New-vApp -name $vAppName -location $cl

        write-host -ForegroundColor Green "Completed setup tasks for DFW tests"

    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        write-host -ForegroundColor Green "Performing cleanup tasks for DFW tests"
        get-vm $testVMName1 -ErrorAction Ignore | remove-vm -Confirm:$false -DeletePermanently
        get-vm $testVMName2 -ErrorAction Ignore | remove-vm -Confirm:$false -DeletePermanently
        get-vm $testVMName3 -ErrorAction Ignore | remove-vm -Confirm:$false -DeletePermanently
        get-nsxedge $dfwedgename | remove-nsxedge -confirm:$false
        start-sleep 5

        Get-NsxFirewallSection $l3sectionname | Remove-NsxFirewallSection -Confirm:$false -force:$true
        Get-NsxFirewallSection $l2sectionname -sectionType layer2sections | Remove-NsxFirewallSection -Confirm:$false -force:$true
        get-nsxlogicalswitch $testlsname | Remove-NsxLogicalSwitch -Confirm:$false
        get-nsxipset $testIPSetName  | Remove-NsxIpSet -Confirm:$false
        get-nsxipset $testIPSetName2  | Remove-NsxIpSet -Confirm:$false
        get-nsxmacset $TestMacSetName1 | Remove-NsxMacSet -Confirm:$false
        get-nsxmacset $TestMacSetName2 | Remove-NsxMacSet -Confirm:$false
        Get-NsxSecurityGroup $testSGName1 | Remove-NsxSecurityGroup -confirm:$false
        Get-NsxSecurityGroup $testSGName2 | Remove-NsxSecurityGroup -confirm:$false
        Get-NsxService $TestServiceName1 | Remove-NsxService -confirm:$false
        Get-NsxService $TestServiceName2 | Remove-NsxService -confirm:$false

        # Delete Port-Group

        Get-VdPortGroup $Testdvportgroupname -ErrorAction Ignore| Remove-VdPortGroup -confirm:$false
        # Delete Resource-pool
        Get-ResourcePool -name $testRpname  -ErrorAction Ignore | Remove-ResourcePool -confirm:$false
        # Delete $vAppName
        Get-vApp $vAppName  -ErrorAction Ignore | Remove-vApp -confirm:$false -DeletePermanently

        disconnect-nsxserver

        write-host -ForegroundColor Green "Completed cleanup tasks for DFW tests"

    }

    Context "Firewall Drafts" {
        AfterAll {
            Get-NsxFirewallSavedConfiguration | Where-Object {$_.name -match "^pester"} | Remove-NsxFirewallSavedConfiguration -confirm:$false
        }

        BeforeEach {
            $section = New-NsxFirewallSection "pester_drafts"
            sleep 1
            $section | New-NsxFirewallRule -Name "pester_draft_rule" -Action allow
            sleep 1
        }

        AfterEach {
            Get-NsxFirewallSection -ObjectId $section.id | Remove-NsxFirewallSection -confirm:$false -force
            sleep 1
        }

        it "Can retrieve all firewall drafts" {
            $drafts = Get-NsxFirewallSavedConfiguration
            $drafts | should not be $null
            ($drafts | Measure-Object).count | should begreaterthan 0
            $draft = $drafts | select-object -first 1
            $draft.id | should not be $null
            ($draft | Get-Member -Name description -MemberType Properties).count | should be 1
            $draft.timestamp | should not be $null
            $draft.preserve | should not be $null
            $draft.user | should not be $null
            ($draft | Get-Member -Name mode -MemberType Properties).count | should be 1
        }

        it "Can retrieve firewall drafts by name (positional)" {
            # NSX Manager allows firewall drafts are able to be configured with
            # the same name
            $drafts = Get-NsxFirewallSavedConfiguration | Select-Object -first 1
            $drafts | should not be $null
            ($drafts | Measure-Object).count | should be 1

            $draft = Get-NsxFirewallSavedConfiguration $drafts.name
            $draft.id | should be $drafts.id
            $draft.description | should be $drafts.description
            $draft.timestamp | should be $drafts.timestamp
            $draft.preserve | should be $drafts.preserve
            $draft.user | should be $drafts.user
            $draft.mode | should be $drafts.mode
            ($draft | Get-Member -Name config -MemberType Properties).count | should be 1
            $draft.config.timestamp | should not be $null
            $draft.config.contextId | should not be $null
            $draft.config.layer3Sections | should not be $null
            $draft.config.layer2Sections | should not be $null
            $draft.config.layer3RedirectSections | should not be $null
            $draft.config.generationNumber | should not be $null
        }

        it "Can retrieve firewall drafts by name (parameter)" {
            # NSX Manager allows firewall drafts are able to be configured with
            # the same name
            $drafts = Get-NsxFirewallSavedConfiguration | Select-Object -first 1
            $drafts | should not be $null
            ($drafts | Measure-Object).count | should be 1

            $draft = Get-NsxFirewallSavedConfiguration -Name $drafts.name
            $draft.id | should be $drafts.id
            $draft.description | should be $drafts.description
            $draft.timestamp | should be $drafts.timestamp
            $draft.preserve | should be $drafts.preserve
            $draft.user | should be $drafts.user
            $draft.mode | should be $drafts.mode
            ($draft | Get-Member -Name config -MemberType Properties).count | should be 1
            $draft.config.timestamp | should not be $null
            $draft.config.contextId | should not be $null
            $draft.config.layer3Sections | should not be $null
            $draft.config.layer2Sections | should not be $null
            $draft.config.layer3RedirectSections | should not be $null
            $draft.config.generationNumber | should not be $null
        }

        it "Can retrieve firewall drafts by id" {
            $drafts = Get-NsxFirewallSavedConfiguration | Select-Object -first 1
            $drafts | should not be $null
            ($drafts | Measure-Object).count | should be 1

            $draft = Get-NsxFirewallSavedConfiguration -ObjectId $drafts.id
            $draft.id | should be $drafts.id
            $draft.description | should be $drafts.description
            $draft.timestamp | should be $drafts.timestamp
            $draft.preserve | should be $drafts.preserve
            $draft.user | should be $drafts.user
            $draft.mode | should be $drafts.mode
            ($draft | Get-Member -Name config -MemberType Properties).count | should be 1
            $draft.config.timestamp | should not be $null
            $draft.config.contextId | should not be $null
            $draft.config.layer3Sections | should not be $null
            $draft.config.layer2Sections | should not be $null
            $draft.config.layer3RedirectSections | should not be $null
            $draft.config.generationNumber | should not be $null
        }

        it "Can create a userdefined firewall draft" {
            $draft = New-NsxFirewallSavedConfiguration -Name $TestDraftName1 -Description $TestDraftDesc1
            $draft | should not be $null
            $draft.id | should not be $null
            $draft.name | should be $TestDraftName1
            $draft.description | should be $TestDraftDesc1
            $draft.timestamp | should not be $null
            $draft.preserve | should be "true"
            $draft.user | should not be $null
            $draft.mode | should be "userdefined"
            ($draft | Get-Member -Name config -MemberType Properties).count | should be 1
            $draft.config.timestamp | should not be $null
            $draft.config.contextId | should not be $null
            $draft.config.layer3Sections | should not be $null
            $draft.config.layer2Sections | should not be $null
            $draft.config.layer3RedirectSections | should not be $null
            $draft.config.generationNumber | should not be $null
        }

        it "Can create a userdefined firewall draft with preserve disabled" {
            $draft = New-NsxFirewallSavedConfiguration -Name $TestDraftName2 -Description $TestDraftDesc2 -Preserve:$false
            $draft | should not be $null
            $draft.id | should not be $null
            $draft.name | should be $TestDraftName2
            $draft.description | should be $TestDraftDesc2
            $draft.timestamp | should not be $null
            $draft.preserve | should be "false"
            $draft.user | should not be $null
            $draft.mode | should be "userdefined"
            ($draft | Get-Member -Name config -MemberType Properties).count | should be 1
            $draft.config.timestamp | should not be $null
            $draft.config.contextId | should not be $null
            $draft.config.layer3Sections | should not be $null
            $draft.config.layer2Sections | should not be $null
            $draft.config.layer3RedirectSections | should not be $null
            $draft.config.generationNumber | should not be $null
        }

        it "Can modify an existing firewall draft" {
            $draft = New-NsxFirewallSavedConfiguration -Name $TestDraftName3 -Description $TestDraftDesc3
            $draft | should not be $null
            $draft.id | should not be $null
            $draft.name | should be $TestDraftName3
            $draft.description | should be $TestDraftDesc3
            $draft.timestamp | should not be $null
            $draft.preserve | should be "true"
            $draft.user | should not be $null
            $draft.mode | should be "userdefined"
            ($draft | Get-Member -Name config -MemberType Properties).count | should be 1
            $draft.config.timestamp | should not be $null
            $draft.config.contextId | should not be $null
            $draft.config.layer3Sections | should not be $null
            $draft.config.layer2Sections | should not be $null
            $draft.config.layer3RedirectSections | should not be $null
            $draft.config.generationNumber | should not be $null

            $updated = Get-NsxFirewallSavedConfiguration -ObjectId $draft.id | Set-NsxFirewallSavedConfiguration -Name $TestDraftUpdatedName -Description $TestDraftUpdatedDesc -Preserve:$false
            $updated.id | should be $draft.id
            $updated.name | should be $TestDraftUpdatedName
            $updated.description | should be $TestDraftUpdatedDesc
            $updated.timestamp | should not be $null
            $updated.preserve | should be "false"
            $updated.user | should not be $null
            $updated.mode | should be "userdefined"
            ($updated | Get-Member -Name config -MemberType Properties).count | should be 1
            $updated.config.timestamp | should not be $null
            $updated.config.contextId | should not be $null
            $updated.config.layer3Sections | should not be $null
            $updated.config.layer2Sections | should not be $null
            $updated.config.layer3RedirectSections | should not be $null
            $updated.config.generationNumber | should not be $null
        }

        it "Can remove a firewall draft" {
            $draft = New-NsxFirewallSavedConfiguration -Name "pester_draft_delete" | Select-Object -first 1
            $draft | should not be $null
            ($draft | Measure-Object).count | should be 1
            Get-NsxFirewallSavedConfiguration -ObjectId $draft.id | Remove-NsxFirewallSavedConfiguration -confirm:$false
            $deleted = Get-NsxFirewallSavedConfiguration | Where-Object { ($_.name -eq $draft.name) -AND ($_.id -eq $draft.id) }
            $deleted | should be $null
        }

    }

    Context "L3 Sections" {

        AfterAll {
            get-nsxfirewallsection | Where-Object {$_.name -match "^pester" } | remove-nsxfirewallsection -Confirm:$false -force:$true
        }

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
            $section | Remove-NsxFirewallSection -confirm:$false
            $section = Get-NsxFirewallSection $l3sectionname
            $section | should be $null
        }

        it "Can create an L3 section at top (legacy)" {
            $section = New-NsxFirewallSection $l3sectionname
            $section | should not be $null
            $section = Get-NsxFirewallSection
            $section | should not be $null
            $section[0].name | should be $l3sectionname
        }

        it "Can create an L3 section at top (insert_top)" {
            $section = New-NsxFirewallSection $l3sectionname -position top
            $section | should not be $null
            $section = Get-NsxFirewallSection
            $section | should not be $null
            $section[0].name | should be $l3sectionname
        }

        it "Can create an L3 section at bottom (insert_before_default)" {
            New-NsxFirewallSection "pester_dfw_top"
            $section = New-NsxFirewallSection $l3sectionname -position bottom
            $section | should not be $null
            $section = Get-NsxFirewallSection
            $section[-2].name  | should be $l3sectionname
        }

        it "Can insert an L3 section before a given section" {
            New-NsxFirewallSection "pester_dfw_3"
            $section2 = New-NsxFirewallSection "pester_dfw_2"
            New-NsxFirewallSection "pester_dfw_1"
            $section = New-NsxFirewallSection $l3sectionname -position before -anchorId $section2.id
            $section | should not be $null
            $section = Get-NsxFirewallSection
            $section[1].name  | should be $l3sectionname
        }

        it "Can insert an L3 section after a given section" {
            New-NsxFirewallSection "pester_dfw_3"
            $section2 = New-NsxFirewallSection "pester_dfw_2"
            New-NsxFirewallSection "pester_dfw_1"
            $section = New-NsxFirewallSection $l3sectionname -position after -anchorId $section2.id
            $section | should not be $null
            $section = Get-NsxFirewallSection
            $section[2].name  | should be $l3sectionname
        }

        it "Fails to insert an L3 section if no anchorId is supplied when using after" {
            { New-NsxFirewallSection $l3sectionname -position after } | should Throw
        }

        it "Fails to insert an L3 section if no anchorId is supplied when using before" {
            { New-NsxFirewallSection $l3sectionname -position before } | should Throw
        }

        it "Fails to insert an L3 universal section if bottom is specified as the position" {
            { New-NsxFirewallSection $l3sectionname -position bottom -universal } | should Throw
        }
    }

    Context "L2 Sections" {

        AfterAll {
            get-nsxfirewallsection -sectionType layer2sections | Where-Object {$_.name -match "^pester" } | remove-nsxfirewallsection -Confirm:$false -force:$true
        }

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
            $section | Get-NsxFirewallRule -RuleType layer2sections | should not be $null
            { $section | Remove-NsxFirewallSection -Confirm:$false -force } | should not Throw
        }

        it "Can create an L2 section at top (legacy)" {
            $section = New-NsxFirewallSection $l2sectionname -sectionType layer2sections
            $section | should not be $null
            $section = Get-NsxFirewallSection -sectionType layer2sections
            $section | should not be $null
            $section[0].name | should be $l2sectionname
        }

        it "Can create an L2 section at top (insert_top)" {
            $section = New-NsxFirewallSection $l2sectionname -position top -sectionType layer2sections
            $section | should not be $null
            $section = Get-NsxFirewallSection -sectionType layer2sections
            $section | should not be $null
            $section[0].name | should be $l2sectionname
        }

        it "Can create an L2 section at bottom (insert_before_default)" {
            New-NsxFirewallSection "pester_dfw_top" -sectionType layer2sections
            $section = New-NsxFirewallSection $l2sectionname -position bottom -sectionType layer2sections
            $section | should not be $null
            $section = Get-NsxFirewallSection -sectionType layer2sections
            $section[-2].name  | should be $l2sectionname
        }

        it "Can insert an L3 section before a given section" {
            New-NsxFirewallSection "pester_dfw_3" -sectionType layer2sections
            $section2 = New-NsxFirewallSection "pester_dfw_2" -sectionType layer2sections
            New-NsxFirewallSection "pester_dfw_1" -sectionType layer2sections
            $section = New-NsxFirewallSection $l2sectionname -position before -anchorId $section2.id -sectionType layer2sections
            $section | should not be $null
            $section = Get-NsxFirewallSection -sectionType layer2sections
            $section[1].name  | should be $l2sectionname
        }

        it "Can insert an L3 section after a given section" {
            New-NsxFirewallSection "pester_dfw_3" -sectionType layer2sections
            $section2 = New-NsxFirewallSection "pester_dfw_2" -sectionType layer2sections
            New-NsxFirewallSection "pester_dfw_1" -sectionType layer2sections
            $section = New-NsxFirewallSection $l2sectionname -position after -anchorId $section2.id -sectionType layer2sections
            $section | should not be $null
            $section = Get-NsxFirewallSection -sectionType layer2sections
            $section[2].name  | should be $l2sectionname
        }

        it "Fails to insert an L2 section if no anchorId is supplied when using after" {
            { New-NsxFirewallSection $l3sectionname -sectionType layer2sections -position after } | should Throw
        }

        it "Fails to insert an L2 section if no anchorId is supplied when using before" {
            { New-NsxFirewallSection $l3sectionname -sectionType layer2sections -position before } | should Throw
        }

        it "Fails to insert an L2 universal section if bottom is specified as the position" {
            { New-NsxFirewallSection $l3sectionname -sectionType layer2sections -position bottom -universal } | should Throw
        }
    }

    Context "Rule Filtering" {

        it "Can query for a rule by ip" {

            $rule1 = Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -Source $TestIpSet -Destination $testipset
            $rule2 = Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "pester_dfw_rule2" -action allow -Source $TestIpSet2 -Destination $testipset2

            #Test positive hits for our first matching rule by source
            $filteredrules = Get-NsxFirewallRule -Source "2.2.2.2"
            $filteredrules.sources.source.value -contains $testIpSet.objectId | should be $true
            $filteredrules.sources.source.value -contains $testIpSet2.objectId | should not be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test matching both rules by source
            $filteredrules = Get-NsxFirewallRule -Source "1.1.1.1"
            $filteredrules.sources.source.value -contains $testIpSet.objectId | should be $true
            $filteredrules.sources.source.value -contains $testIpSet2.objectId | should be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should be $true

            #Test negative query by source
            $filteredrules = Get-NsxFirewallRule -Source "3.3.3.3"
            $filteredrules.sources.source.value -contains $testIpSet.objectId | should not be $true
            $filteredrules.sources.source.value -contains $testIpSet2.objectId | should not be $true
            $filteredrules.id -contains $rule1.id | should not be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test positive hits for our first matching rule by destination
            $filteredrules = Get-NsxFirewallRule -Destination "2.2.2.2"
            $filteredrules.destinations.destination.value -contains $testIpSet.objectId | should be $true
            $filteredrules.destinations.destination.value -contains $testIpSet2.objectId | should not be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test matching both rules by destination
            $filteredrules = Get-NsxFirewallRule -Destination "1.1.1.1"
            $filteredrules.destinations.destination.value -contains $testIpSet.objectId | should be $true
            $filteredrules.destinations.destination.value -contains $testIpSet2.objectId | should be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should be $true

            #Test negative query by destination
            $filteredrules = Get-NsxFirewallRule -Destination "3.3.3.3"
            $filteredrules.destinations.destination.value -contains $testIpSet.objectId | should not be $true
            $filteredrules.destinations.destination.value -contains $testIpSet2.objectId | should not be $true
            $filteredrules.id -contains $rule1.id | should not be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test positive hits for our first matching rule by source and destination
            $filteredrules = Get-NsxFirewallRule -source "2.2.2.2" -Destination "2.2.2.2"
            $filteredrules.destinations.destination.value -contains $testIpSet.objectId | should be $true
            $filteredrules.destinations.destination.value -contains $testIpSet2.objectId | should not be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test matching both rules by source and destination
            $filteredrules = Get-NsxFirewallRule -source "1.1.1.1" -Destination "1.1.1.1"
            $filteredrules.destinations.destination.value -contains $testIpSet.objectId | should be $true
            $filteredrules.destinations.destination.value -contains $testIpSet2.objectId | should be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should be $true

            #Test negative query by source and destination
            $filteredrules = Get-NsxFirewallRule -source "3.3.3.3" -Destination "3.3.3.3"
            $filteredrules.destinations.destination.value -contains $testIpSet.objectId | should not be $true
            $filteredrules.destinations.destination.value -contains $testIpSet2.objectId | should not be $true
            $filteredrules.id -contains $rule1.id | should not be $true
            $filteredrules.id -contains $rule2.id | should not be $true

        }

        it "Can query for a rule by source vm object" {
            $rule1 = Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -Source $TestVM1 -Destination $TestVM1
            $rule2 = Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "pester_dfw_rule2" -action allow -Source $TestVM2 -Destination $TestVM2

            #Test positive hits for our first matching rule by source
            $filteredrules = Get-NsxFirewallRule -Source $TestVM1
            $filteredrules.sources.source.value -contains ($TestVM1.id -replace "virtualmachine-") | should be $true
            $filteredrules.sources.source.value -contains ($TestVM2.id -replace "virtualmachine-") | should not be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should not be $true


            #Test negative query by source
            $filteredrules = Get-NsxFirewallRule -Source $TestVM3
            $filteredrules.sources.source.value -contains ($TestVM1.id -replace "virtualmachine-") | should not be $true
            $filteredrules.sources.source.value -contains ($TestVM2.id -replace "virtualmachine-") | should not be $true
            $filteredrules.id -contains $rule1.id | should not be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test positive hits for our first matching rule by destination
            $filteredrules = Get-NsxFirewallRule -Destination $TestVM1
            $filteredrules.destinations.destination.value -contains ($TestVM1.id -replace "virtualmachine-") | should be $true
            $filteredrules.destinations.destination.value -contains ($TestVM2.id -replace "virtualmachine-") | should not be $true
            $filteredrules.id -contains $rule1.id | should be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test negative query by destination
            $filteredrules = Get-NsxFirewallRule -Destination $TestVM3
            $filteredrules.destinations.destination.value -contains ($TestVM1.id -replace "virtualmachine-") | should not be $true
            $filteredrules.destinations.destination.value -contains ($TestVM2.id -replace "virtualmachine-") | should not be $true
            $filteredrules.id -contains $rule1.id | should not be $true
            $filteredrules.id -contains $rule2.id | should not be $true

            #Test positive hits for our first matching rule by source and destination
            $filteredrules = Get-NsxFirewallRule -source $TestVM2 -Destination $TestVM2
            $filteredrules.destinations.destination.value -contains ($TestVM2.id -replace "virtualmachine-") | should be $true
            $filteredrules.destinations.destination.value -contains ($TestVM1.id -replace "virtualmachine-") | should not be $true
            $filteredrules.id -contains $rule2.id | should be $true
            $filteredrules.id -contains $rule1.id | should not be $true

            #Test negative query by source and destination
            $filteredrules = Get-NsxFirewallRule -source $TestVM3 -Destination $TestVM3
            $filteredrules.destinations.destination.value -contains ($TestVM1.id -replace "virtualmachine-") | should not be $true
            $filteredrules.destinations.destination.value -contains ($TestVM2.id -replace "virtualmachine-") | should not be $true
            $filteredrules.id -contains $rule1.id | should not be $true
            $filteredrules.id -contains $rule2.id | should not be $true

        }

        it "Can query for a rule by name" {
            $rule1 = Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -Source $TestVM1 -Destination $TestVM1

            #Test positive hits for our first matching rule by name
            $filteredrules = Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $filteredrules.name -contains "pester_dfw_rule1" | should be $true
            $filteredrules.id -contains $rule1.id | should be $true

            #Test negative hits for our first matching rule by name
            $filteredrules = Get-NsxFirewallRule -Name "fred"
            $filteredrules.name -contains "pester_dfw_rule1" | should not be $true
            $filteredrules.id -contains $rule1.id | should not be $true
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

    Context "L3 Rules" {

        it "Can create an l3 disabled allow any - any rule" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -Disabled
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
            $rule.disabled | should be "true"
        }

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
            $rule.disabled | should be "false"
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
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ip host based source" {
            $ipaddress = "1.1.1.1"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -source $ipaddress
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.type | should be "Ipv4Address"
            $rule.sources.source.value | should be $ipaddress
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ip range based source" {
            $ipaddress = "1.1.1.1-1.1.1.254"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -source $ipaddress
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.type | should be "Ipv4Address"
            $rule.sources.source.value | should be $ipaddress
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ip network based source" {
            $ipaddress = "1.1.1.1/24"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -source $ipaddress
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.type | should be "Ipv4Address"
            $rule.sources.source.value | should be $ipaddress
            $rule.destinations | should be $null
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ipset based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $TestIpSet -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$testIPSetName"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a security group based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $TestSG1 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$testSGName1"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a cluster based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $cl -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$($cl.name)"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a datacenter based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $dc -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$($dc.name)"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a dvportgroup based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $TestDvPortgroup -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$Testdvportgroupname"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"

        }

        it "Can create an l3 rule with an lswitch based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $testls -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$testlsname"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a resource pool based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $testresourcepool -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$testrpname"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an vapp based source" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $testvapp -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources.source.name | should be "$vAppName"
            $rule.destinations | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a vnic based source" {
            # Update PowerNSX to get nics fix to arrays
            $vm1vnic = Get-Vm $testVMName1 | Get-NetworkAdapter
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -source $vm1vnic -action allow
            $rule.sources.source.type | should be "Vnic"
            $rule.destinations.destination | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ip host based destination" {
            $ipaddress = "1.1.1.1"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -destination $ipaddress
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations.destination.type | should be "Ipv4Address"
            $rule.destinations.destination.value | should be $ipaddress
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ip range based destination" {
            $ipaddress = "1.1.1.1-1.1.1.254"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -destination $ipaddress
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations.destination.type | should be "Ipv4Address"
            $rule.destinations.destination.value | should be $ipaddress
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ip network based destination" {
            $ipaddress = "1.1.1.1/24"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -destination $ipaddress
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations.destination.type | should be "Ipv4Address"
            $rule.destinations.destination.value | should be $ipaddress
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an ipset based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $TestIpSet -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$testIPSetName"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a security group based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $TestSG1 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$TestSgName1"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a cluster based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $cl -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$($cl.name)"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a datacenter based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $dc -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$($dc.name)"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a dvportgroup based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $TestDvPortgroup -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$Testdvportgroupname"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an lswitch based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $testls -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$testlsname"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a resource pool based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $testresourcepool -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$testrpname"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an vapp based destination" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $testvapp -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations.destination.name | should be "$vAppName"
            $rule.sources | should be $null
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a vnic based destination" {
            $vm1vnic = Get-Vm $testVMName1 | Get-NetworkAdapter
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -destination $vm1vnic -action allow
            $rule.sources.source | should be $null
            $rule.destinations.destination.type | should be "Vnic"
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a security group based applied to" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1"  -action allow -appliedTo $testSg1
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destination | should be $null
            $rule.appliedToList.appliedTo.Name | should be $testSGName1
            #$rule.appliedToList.appliedTo.Value | should not be $null
            $rule.appliedToList.appliedTo.Type | should be "SecurityGroup"
            #$rule.appliedToList.appliedTo.isValue | should not be $null
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a cluster based applied to" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1"  -action allow -appliedTo $cl
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destination | should be $null
            $rule.appliedToList.appliedTo.Name | should be $($cl.name)
            $clid = $cl.id  -replace "ClusterComputeResource-",""
            $rule.appliedToList.appliedTo.Value | should be $clid
            $rule.appliedToList.appliedTo.Type | should be "ClusterComputeResource"
            #$rule.appliedToList.appliedTo.isValue | should not be $null
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a datacenter based applied to" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1"  -action allow -appliedTo $dc
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destination | should be $null
            $rule.appliedToList.appliedTo.Name | should be $($dc.name)
            $dcid = $dc.id  -replace "^Datacenter-",""
            $rule.appliedToList.appliedTo.Value | should be $dcid
            $rule.appliedToList.appliedTo.Type | should be "Datacenter"
            #$rule.appliedToList.appliedTo.isValue | should not be $null
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a dvportgroup based applied to" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1"  -action allow -appliedTo $testdvPortgroup
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destination | should be $null
            $rule.appliedToList.appliedTo.Name | should be $testdvportgroupname
            #$rule.appliedToList.appliedTo.Value | should not be $null
            $rule.appliedToList.appliedTo.Type | should be "DistributedVirtualPortgroup"
            #$rule.appliedToList.appliedTo.isValue | should not be $null
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with an lswitch based applied to" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1"  -action allow -appliedTo $testls
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destination | should be $null
            $rule.appliedToList.appliedTo.Name | should be $testlsname
            #$rule.appliedToList.appliedTo.Value | should not be $null
            $rule.appliedToList.appliedTo.Type | should be "VirtualWire"
            #$rule.appliedToList.appliedTo.isValue | should not be $null
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with a vapp based applied to" {
        }

        it "Can create an l3 rule with a vnic based applied to" {
            $vm1vnic = Get-Vm $testVMName1 | Get-NetworkAdapter
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -AppliedTo $vm1vnic -action allow
            $rule.sources.source | should be $null
            $rule.destinations.destination | should be $null
            $rule.appliedToList.appliedTo.Type | should be "Vnic"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with raw protocol as the service (No Port Defined)" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -service $TestServiceProto
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 1
            $rule.services.service.protocolName | should be $TestServiceProto
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with raw protocol and port as the service" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -service "$TestServiceProto/$testPort"
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 1
            $rule.services.service.protocolName | should be $TestServiceProto
            $rule.services.service.destinationPort | should be $testPort
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with raw protocol and port-range as the service" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -service "$TestServiceProto/$testPortRange"
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 1
            $rule.services.service.protocolName | should be $TestServiceProto
            $rule.services.service.destinationPort | should be $testPortRange
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple raw port/protocol combinations as the service" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -service $rawService1,$rawService2,$rawService3,$rawService4,$rawService5,$rawService6
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should be $null
            $rule.destinations | should be $null
            @($rule.services.service).count | should be 6
            @($rule.services.service | Where-Object { $_.protocolName -eq $rawService1 }).count | should Be 1
            @($rule.services.service | Where-Object { ( $_.protocolName -eq ($rawservice2 -split "/")[0] ) -and  ( $_.destinationPort -eq ($rawservice2 -split "/")[1] ) }).count | should be 1
            @($rule.services.service | Where-Object { ( $_.protocolName -eq ($rawservice3 -split "/")[0] ) -and  ( $_.destinationPort -eq ($rawservice3 -split "/")[1] ) }).count | should be 1
            @($rule.services.service | Where-Object { ( $_.protocolName -eq ($rawservice4 -split "/")[0] ) -and  ( $_.destinationPort -eq ($rawservice4 -split "/")[1] ) }).count | should be 1
            @($rule.services.service | Where-Object { ( $_.protocolName -eq $rawService5) -and ( !($_ | get-member -name destinationport -Membertype Properties ) ) }).count | should be 1
            @($rule.services.service | Where-Object { ( $_.protocolName -eq $rawService6) -and ( !($_ | get-member -name destinationport -Membertype Properties ) ) }).count | should be 1
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with single source, destination, applied to and service (object)" {
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with single source, destination, applied to and service (raw)" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1 -destination $testvm2 -action allow -appliedTo $testvm1 -service $rawservice3
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.sources.source).count | should be 1
            @($rule.destinations.destination).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 1
            @($rule.services.service).count | should be 1
            @($rule.services.service | Where-Object { ( $_.protocolName -eq ($rawservice3 -split "/")[0] ) -and  ( $_.destinationPort -eq ($rawservice3 -split "/")[1] ) }).count | should be 1
            $rule.sources.source.name | should be $testVmName1
            $rule.destinations.destination.name | should be $testVmName2
            $rule.appliedToList.appliedTo.name | should be $testVmName1
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip host based source" {
            $ipaddress1 = "1.1.1.1"
            $ipaddress2 = "2.2.2.2"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $ipaddress1,$ipaddress2 -action allow
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
            $sortedAddresses = ( @($ipaddress1, $ipaddress2) | Sort-Object)
            $rule.sources.source.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip range based source" {
            $ipaddress1 = "1.1.1.1-1.1.1.254"
            $ipaddress2 = "2.2.2.2-2.2.2.254"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $ipaddress1,$ipaddress2 -action allow
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
            $sortedAddresses = ( @($ipaddress1, $ipaddress2) | Sort-Object)
            $rule.sources.source.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip network based source" {
            $ipaddress1 = "1.1.1.0/24"
            $ipaddress2 = "2.2.0.0/16"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $ipaddress1,$ipaddress2 -action allow
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
            $sortedAddresses = ( @($ipaddress1, $ipaddress2) | Sort-Object)
            $rule.sources.source.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip host,range,network based source" {
            $ipaddress1 = "1.1.1.1"
            $ipaddress2 = "2.2.0.0/16"
            $ipaddress3 = "3.3.3.1-3.3.3.254"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $ipaddress1,$ipaddress2,$ipaddress3 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should beoftype System.Xml.XmlElement
            @($rule.sources.source).count | should be 3
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedAddresses = ( @($ipaddress1, $ipaddress2, $ipaddress3) | Sort-Object)
            $rule.sources.source.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip host based destination" {
            $ipaddress1 = "1.1.1.1"
            $ipaddress2 = "2.2.2.2"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Destination $ipaddress1,$ipaddress2 -action allow
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
            $sortedAddresses = ( @($ipaddress1, $ipaddress2) | Sort-Object)
            $rule.destinations.destination.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip range based destination" {
            $ipaddress1 = "1.1.1.1-1.1.1.254"
            $ipaddress2 = "2.2.2.2-2.2.2.254"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Destination $ipaddress1,$ipaddress2 -action allow
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
            $sortedAddresses = ( @($ipaddress1, $ipaddress2) | Sort-Object)
            $rule.destinations.destination.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip network based destination" {
            $ipaddress1 = "1.1.1.0/24"
            $ipaddress2 = "2.2.0.0/16"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Destination $ipaddress1,$ipaddress2 -action allow
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
            $sortedAddresses = ( @($ipaddress1, $ipaddress2) | Sort-Object)
            $rule.destinations.destination.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple ip host,range,network based destination" {
            $ipaddress1 = "1.1.1.1"
            $ipaddress2 = "2.2.0.0/16"
            $ipaddress3 = "3.3.3.1-3.3.3.254"
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Destination $ipaddress1,$ipaddress2,$ipaddress3 -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.destinations | should beoftype System.Xml.XmlElement
            @($rule.destinations.destination).count | should be 3
            @($rule.appliedToList.appliedto).count | should be 1
            $rule.appliedToList.appliedTo.Name | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Value | should be "DISTRIBUTED_FIREWALL"
            $rule.appliedToList.appliedTo.Type | should be "DISTRIBUTED_FIREWALL"
            $sortedAddresses = ( @($ipaddress1, $ipaddress2, $ipaddress3) | Sort-Object)
            $rule.destinations.destination.value | sort-object | should be $sortedAddresses
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple item based source, destination, applied to and service (objects)" {
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create an l3 rule with multiple item based source, destination, applied to and service (objects/raw)" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -Source $testvm1,$testvm2 -destination $testvm1,$testvm2 -action allow -appliedTo $testvm1,$testvm2 -Service $TestService1, $rawService1, $TestService2, $rawservice3
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            $rule.sources | should beoftype System.Xml.XmlElement
            $rule.destinations | should beoftype System.Xml.XmlElement
            $rule.appliedToList | should beoftype System.Xml.XmlElement
            @($rule.services.service).count | should be 4
            @($rule.services.service | Where-Object { $_.Name -eq $TestServiceName1 }).count | should be 1
            @($rule.services.service | Where-Object { $_.Name -eq $TestServiceName2 }).count | should be 1
            @($rule.services.service | Where-Object { $_.protocolName -eq $rawService1 }).count | should be 1
            @($rule.services.service | Where-Object { ( $_.protocolName -eq ($rawservice3 -split "/")[0] ) -and  ( $_.destinationPort -eq ($rawservice3 -split "/")[1] ) }).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 2
            @($rule.destinations.destination).count | should be 2
            $sortedNames = ( @($testvm1.name, $testvm2.name) | Sort-Object)
            $rule.sources.source.name | sort-object | should be $sortedNames
            $rule.destinations.destination.name | sort-object | should be $sortedNames
            $rule.appliedToList.appliedTo.name  | sort-object | should be $sortedNames
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }


        it "Can create a rule to apply to a specific edge" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -AppliedTo $dfwEdge
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 2
            $rule.appliedToList.appliedTo.Name -contains "$dfwedgename" | should be $True
            $rule.appliedToList.appliedTo.Name -contains "DISTRIBUTED_FIREWALL" | should be $True
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

         it "Can create a rule to apply to a specific edge without DFW" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -AppliedTo $dfwEdge -ApplytoDfw:$false
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            @($rule).count | should be 1
            @($rule.appliedToList.appliedTo).count | should be 1
            $rule.appliedToList.appliedTo.Name -contains "$dfwedgename" | should be $True
            $rule.appliedToList.appliedTo.Name -contains "DISTRIBUTED_FIREWALL" | should be $False
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create a rule with a servicegroup specified as service"{}

        #############
        # Positional rule inserting

        it "Can insert a rule at the top of a section (by default)" {
            $rule3 = Get-NsxFirewallSection $l3sectionname | New-NsxFirewallRule -Name "pester_dfw_rule3" -action allow
            $rule2 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule2" -action allow
            $rule1 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow
            $rule1 | should not be $null
            $rule2 | should not be $null
            $rule3 | should not be $null
            $section = Get-NsxFirewallSection -Name $l3sectionname
            $section | should not be $null
            $section.rule[0].name | should be "pester_dfw_rule1"
        }

        it "Can insert a rule at the top of a section (position top)" {
            $rule3 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule3" -action allow -position top
            $rule2 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule2" -action allow -position top
            $rule1 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -position top
            $rule1 | should not be $null
            $rule2 | should not be $null
            $rule3 | should not be $null
            $section = Get-NsxFirewallSection -Name $l3sectionname
            $section | should not be $null
            $section.rule[0].name | should be "pester_dfw_rule1"
        }

        it "Can insert a rule at the bottom of a section (position bottom)" {
            $rule3 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule3" -action allow
            $rule2 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule2" -action allow
            $ruleBottom = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_bottom" -action allow -position bottom
            $ruleBottom | should not be $null
            $rule2 | should not be $null
            $rule3 | should not be $null
            $section = Get-NsxFirewallSection -Name $l3sectionname
            $section | should not be $null
            $section.rule[2].name | should be "pester_dfw_bottom"
        }

        it "Can insert a rule before an existing rule within a section (position before)" {
            $rule5 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule5" -action allow
            $rule4 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule4" -action allow
            $rule3 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule3" -action allow
            $rule2 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule2" -action allow
            $rule1 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow
            $rule = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_inserted" -action allow -position before -anchorId $rule3.id
            $rule | should not be $null
            $rule1 | should not be $null
            $rule2 | should not be $null
            $rule3 | should not be $null
            $rule4 | should not be $null
            $rule5 | should not be $null
            $section = Get-NsxFirewallSection -Name $l3sectionname
            $section | should not be $null
            $section.rule[2].name | should be "pester_dfw_inserted"
        }

        it "Can insert a rule after an existing rule within a section (position after)" {
            $rule5 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule5" -action allow
            $rule4 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule4" -action allow
            $rule3 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule3" -action allow
            $rule2 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule2" -action allow
            $rule1 = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow
            $rule = Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_inserted" -action allow -position after -anchorId $rule3.id
            $rule | should not be $null
            $rule1 | should not be $null
            $rule2 | should not be $null
            $rule3 | should not be $null
            $rule4 | should not be $null
            $rule5 | should not be $null
            $section = Get-NsxFirewallSection -Name $l3sectionname
            $section | should not be $null
            $section.rule[3].name | should be "pester_dfw_inserted"
        }

        it "Fails to insert a new rule before another rule if anchorId is not supplied" {
            {Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_inserted" -action allow -position before} | should throw
        }

        it "Fails to insert a new rule after another rule if anchorId is not supplied" {
            {Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_inserted" -action allow -position after} | should throw
        }

        it "Fails to insert a new rule after another rule if anchorId does not exist within section" {
            {Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_inserted" -action allow -position after -anchorId 9999} | should throw
        }

        it "Fails to insert a new rule before another rule if anchorId does not exist within section" {
            {Get-NsxFirewallSection $l3sectionname  | New-NsxFirewallRule -Name "pester_dfw_inserted" -action allow -position before -anchorId 9999} | should throw
        }

        it "Fails to insert a new rule to the bottom of the default layer 3 section" {
            $section = Get-NsxFirewallSection -sectionType layer3sections | Select-Object -last 1
            {$section | New-NsxFirewallRule -Name "pester_dfw_bottom" -action allow -position bottom } | should throw
        }
        it "Fails to insert a new rule to the bottom of the default layer 2 section" {
            $section = Get-NsxFirewallSection -sectionType layer2sections | Select-Object -last 1
            {$section | New-NsxFirewallRule -Name "pester_dfw_bottom" -action allow -position bottom } | should throw
        }

        it "Can modified an l3 rule" {
            $rule = $l3sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action deny -EnableLogging
            $rule | should not be $null
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be deny
            $rule.disabled | should be "false"
            $rule.logged | should be "true"
            #There is no comment before, it will be add
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "pester_dfw_rule1" | Set-NsxFirewallRule -name "modified_pester_dfw_rule1" -action allow -disabled:$true -logged:$false -comment "My Comment"
            $rule | should not be $null
            $rule.name | should be "modified_pester_dfw_rule1"
            $rule.action | should be allow
            $rule.disabled | should be "true"
            $rule.logged | should be "false"
            $rule.notes | should be "My Comment"
            #There is already a comment, it will be replaced
            $rule = Get-NsxFirewallSection -Name $l3sectionname | Get-NsxFirewallRule -Name "modified_pester_dfw_rule1" | Set-NsxFirewallRule -comment "My Comment 2"
            $rule.notes | should be "My Comment 2"
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


    Context "L3 Rule Member Modification" {


        BeforeEach {
            #create new sections with rules in it for each test.
            $script:l3sec = New-NsxFirewallSection -Name $l3sectionname
            $script:l3modrule1 = Get-NsxFirewallSection -Name $l3sectionname | new-nsxfirewallrule -Name "pester_l3_test_modification_rule1" -source $testvm1, $testipset, $testsg1 -destination $testvm1, $testipset, $testsg1 -Action allow -Service $TestService1
            $script:l3modrule2 = Get-NsxFirewallSection -Name $l3sectionname | new-nsxfirewallrule -Name "pester_l3_test_modification_rule2" -source $testvm2, $testIpSet2,$testsg2 -destination $testvm2, $testipset2, $testsg2 -Action allow -Service $TestService2
        }
        AfterEach {
            #tear down new sections after each test.
            # read-host "waiting"
            if ($pause) { read-host "pausing" }
            Get-NsxFirewallSection -Name $l3sectionname | Remove-NsxFirewallSection -force -Confirm:$false
        }

        it "Can get a specific source member of an existing L3 rule by string" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -MemberType Source -Member $script:testVMName1
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Source' } | Measure-Object).count | should be 1
            ($member | Where-Object { $_.MemberType -eq 'Destination' } | Measure-Object).count | should be 0
            $member.Name  |should be $script:testVMName1
            $member.RuleId | should be $l3modrule1.id
        }

        it "Can get a specific destination member of an existing L3 rule by string" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -MemberType Destination -Member $script:testVMName1
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Source' } | Measure-Object).count | should be 0
            ($member | Where-Object { $_.MemberType -eq 'Destination' } | Measure-Object).count | should be 1
            $member.Name  |should be $script:testVMName1
            $member.RuleId | should be $l3modrule1.id
        }

        it "Can get a specific member in both source and destination of an existing L3 rule by string" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -Member $script:testVMName1
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id | Measure-Object}).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Source' } | Measure-Object).count | should be 1
            ($member | Where-Object { $_.MemberType -eq 'Destination' } | Measure-Object).count | should be 1
            ($member | Where-Object { $_.MemberType -eq 'Source' } ).Name  | should be $script:testVMName1
            ($member | Where-Object { $_.MemberType -eq 'Destination' } ).Name  | should be $script:testVMName1
            ($member | Where-Object { $_.MemberType -eq 'Source' }).ruleid | should be $l3modrule1.id
            ($member | Where-Object { $_.MemberType -eq 'Destination' }).RuleId | should be $l3modrule1.id        }

        it "Can get a specific source member of an existing L3 rule by object" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -MemberType Source -Member $script:testvm1
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id}  | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Source' } | Measure-Object).count | should be 1
            ($member | Where-Object { $_.MemberType -eq 'Destination' } | Measure-Object).count | should be 0
            $member.Name  |should be $script:testVMName1
            $member.RuleId | should be $l3modrule1.id
        }

        it "Can get a specific destination member of an existing L3 rule by object" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -MemberType Destination -Member $script:testVM1
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id}  | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Source' } | Measure-Object).count | should be 0
            ($member | Where-Object { $_.MemberType -eq 'Destination' } | Measure-Object).count | should be 1
            $member.Name  |should be $script:testVMName1
            $member.RuleId | should be $l3modrule1.id
        }

        it "Can get a specific member in both source and destination of an existing L3 rule by object" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -Member $script:testVM1
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id}  | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Source' } | Measure-Object).count | should be 1
            ($member | Where-Object { $_.MemberType -eq 'Destination' } | Measure-Object).count | should be 1
            ($member | Where-Object { $_.MemberType -eq 'Source' } ).Name  | should be $script:testVMName1
            ($member | Where-Object { $_.MemberType -eq 'Destination' } ).Name  | should be $script:testVMName1
            ($member | Where-Object { $_.MemberType -eq 'Source' }).RuleId | should be $l3modrule1.id
            ($member | Where-Object { $_.MemberType -eq 'Destination' }).RuleId | should be $l3modrule1.id
        }

        it "Can get all sources from an existing L3 rule" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -MemberType Source
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Destination'} | Measure-Object).count | should be 0
            $member.count -eq @($l3modrule1.Sources.Source).count | should be $true
        }

        it "Can get all destinations from an existing L3 rule" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember -MemberType Destination
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.MemberType -eq 'Source'} | Measure-Object).count | should be 0
            $member.count -eq @($l3modrule1.Destinations.Destination).count | should be $true
        }

        it "Can get all members (source/destination) from an existing L3 rule" {
            $member = $l3modrule1 | Get-NsxFirewallRuleMember
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            $member.count -eq (@($l3modrule1.Sources.Source).count + @($l3modrule1.Destinations.Destination).count) | should be $true
        }

        it "Can add a new source to an existing L3 rule" {

            $member = Get-NsxFirewallRule -ruleid $l3modrule1.id | Add-NsxFirewallRuleMember -MemberType Source -Member $script:TestVM2
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.membertype -eq 'Source' } | Measure-Object).count -eq (@($l3modrule1.Sources.Source).count + 1) | should be $true
            ($member | Where-Object { $_.membertype -eq 'Destination' } | Measure-Object).count -eq (@($l3modrule1.Destinations.Destination).count) | should be $true
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Sources.Source.Name -contains $script:TestVMName2 | should be $true
        }

        it "Can add a new destination to an existing L3 rule" {

            $member = Get-NsxFirewallRule -ruleid $l3modrule1.id | Add-NsxFirewallRuleMember -MemberType Destination -Member $script:TestVM2
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.membertype -eq 'Source' } | Measure-Object).count -eq (@($l3modrule1.Sources.Source).count) | should be $true
            ($member | Where-Object { $_.membertype -eq 'Destination' } | Measure-Object).count -eq (@($l3modrule1.Destinations.Destination).count + 1) | should be $true
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Destinations.Destination.Name -contains $script:TestVMName2 | should be $true
        }

        it "Can add multiple sources to an existing L3 rule" {
            $member = Get-NsxFirewallRule -ruleid $l3modrule1.id | Add-NsxFirewallRuleMember -MemberType Source -Member $script:TestVM2, $script:TestSG2
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.membertype -eq 'Source' } | Measure-Object).count -eq (@($l3modrule1.Sources.Source).count + 2) | should be $true
            ($member | Where-Object { $_.membertype -eq 'Destination' } | Measure-Object).count -eq (@($l3modrule1.Destinations.Destination).count) | should be $true
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Sources.Source.Name -contains $script:TestVMName2 | should be $true
            $rule.Sources.Source.Name -contains $script:TestSgName2 | should be $true
        }

        it "Can add multiple destinations to an existing L3 rule" {
            $member = Get-NsxFirewallRule -ruleid $l3modrule1.id | Add-NsxFirewallRuleMember -MemberType Destination -Member $script:TestVM2, $script:TestSG2
            ($member | Where-Object { $_.ruleid -eq $l3modrule1.id} | Measure-Object).count | should begreaterthan 0
            $member | Where-Object { $_.ruleid -ne $l3modrule1.id} | should be $null
            ($member | Where-Object { $_.membertype -eq 'Destination' } | Measure-Object).count -eq (@($l3modrule1.Destinations.Destination).count + 2) | should be $true
            ($member | Where-Object { $_.membertype -eq 'Source' } | Measure-Object).count -eq (@($l3modrule1.Sources.Source).count) | should be $true
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Destinations.Destination.Name -contains $script:TestVMName2 | should be $true
            $rule.Destinations.Destination.Name -contains $script:TestSgName2 | should be $true
        }

        it "Can remove an existing source from an existing L3 rule" {
            Get-NsxFirewallRule -ruleid $l3modrule1.id | Get-NsxFirewallRuleMember -MemberType Source -Member $script:TestVM1 | Remove-NsxFirewallRuleMember -Confirm:$false -SayHello2Heaven
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Sources.Source.Name -contains $script:TestVMName1 | should be $false
        }

        it "Can remove an existing destination from an existing L3 rule" {
            Get-NsxFirewallRule -ruleid $l3modrule1.id | Get-NsxFirewallRuleMember -MemberType Destination -Member $script:TestVM1 | Remove-NsxFirewallRuleMember -Confirm:$false -SayHello2Heaven
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Destinations.Destination.Name -contains $script:TestVMName1 | should be $false
        }

        it "Can remove multiple sources from an existing L3 rule" {
            Get-NsxFirewallRule -ruleid $l3modrule1.id | Get-NsxFirewallRuleMember -MemberType Source -Member $script:TestVM1, $script:TestSG1 | Remove-NsxFirewallRuleMember -confirm:$false -SayHello2Heaven
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Sources.Source.Name -contains $script:TestVMName1 | should be $false
            $rule.Sources.Source.Name -contains $script:TestSgName1 | should be $false
        }

        it "Can remove multiple destinations from an existing L3 rule" {
            Get-NsxFirewallRule -ruleid $l3modrule1.id | Get-NsxFirewallRuleMember -MemberType Destination -Member $script:TestVM1, $script:TestSG1 | Remove-NsxFirewallRuleMember -confirm:$false -SayHello2Heaven
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            $rule.Destinations.Destination.Name -contains $script:TestVMName1 | should be $false
            $rule.Destinations.Destination.Name -contains $script:TestSgName1 | should be $false
        }

        it "Can remove all sources from an existing L3 rule" {
            Get-NsxFirewallRule -ruleid $l3modrule1.id | Get-NsxFirewallRuleMember -MemberType Source| Remove-NsxFirewallRuleMember -confirm:$false -SayHello2Heaven
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            ($rule.Sources.Source.Name).count | should be 0
        }

        it "Can remove all destinations from an existing L3 rule" {
            Get-NsxFirewallRule -ruleid $l3modrule1.id | Get-NsxFirewallRuleMember -MemberType Destination | Remove-NsxFirewallRuleMember -confirm:$false -SayHello2Heaven
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            ($rule.Destinations.Destination.Name).count | should be 0
        }

        it "Can remove all members (source/destination) from an existing L3 rule" {
            Get-NsxFirewallRule -ruleid $l3modrule1.id | Get-NsxFirewallRuleMember | Remove-NsxFirewallRuleMember -confirm:$false -SayHello2Heaven
            $rule = Get-NsxFirewallRule -Ruleid $l3modrule1.id
            ($rule.Sources.Source.Name).count | should be 0
            ($rule.Destinations.Destination.Name).count | should be 0

        }
    }

    Context "L2 Rules" {

        it "Can create an l2 disabled rule" {
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

        it "Can create an l2 rule with a vnic based source" {
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

        it "Can create an l2 rule with a vnic based destination" {
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

        it "Can create an l2 disabled allow any - any rule" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow -RuleType layer2sections -Disabled
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
            $rule.disabled | should be "true"
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
            $rule.disabled | should be "false"
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
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

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
            $rule.action | should be allow
            $rule.disabled | should be "false"
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
            $rule.action | should be allow
            $rule.disabled | should be "false"
        }

        it "Can create and get a l2 rule without specifying ruleType" {
            $rule = $l2sec | New-NsxFirewallRule -Name "pester_dfw_rule1" -action allow
            $rule | should not be $null
            $rule = Get-NsxFirewallSection -Name $l2sectionname -sectionType layer2sections | Get-NsxFirewallRule -Name "pester_dfw_rule1"
            $rule | should not be $null
            $rule.name | should be "pester_dfw_rule1"
            $rule.action | should be allow
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

    Context "Miscellaneous"  {
        It "Can get publish status" {
            $publish = Get-NsxFirewallPublishStatus
            $publish | should not be $null
            $publish.starttime | should not be $null
            $publish.status | should not be $null
        }
    }



}
