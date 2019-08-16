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

Describe "SecurityPolicy" {

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
        $script:SpNamePrefix = "pester_secpol_"

        # These Service Defintions and Service profiles have to be precreated manually in for the associated tests to be run.
        # We know how to create the service defintion, but not sure on the service profile.
        $script:pester_sd_ni_name = "pester_sd_ni"
        $script:pester_sd_gi_name = "pester_sd_gi"
        $script:nisd = Get-NsxServiceDefinition -Name $pester_sd_ni_name
        $script:nisp = $nisd | Get-NsxServiceProfile
        $script:gisd = Get-NsxServiceDefinition -Name $pester_sd_gi_name
        $script:gisp = $gisd | Get-NsxServiceProfile
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
        $script:testVMName1 = "pester_vm_1"
        $script:testvm1 = new-vm -name $testVMName1 @vmsplat

        if ( $nisd -and $nisp -and ( $nisd.functionalities.functionality.type -eq "FIREWALL") `
            -and ( $nisd.implementations.implementation.type -eq "HOST_BASED_VNIC") `
            -and ( $nisd.transports.transport.type -eq "VMXNET3") ) {
            $script:EnableNiTests = $true
        }
        else {
            write-warning "Disabled Network Introspection tests due to missing precreated service definition.  Create a service definition called pester_sd_ni with Host Based VNIC mechanism, the Firewall service category enabled, at least one service profile and with a VMXNET3 transport to enable these tests."
        }

        if ( $gisd -and $gisp -and ( $gisd.functionalities.functionality.type -eq "FIM") `
            -and ( $gisd.implementations.implementation.type -eq "HOST_BASED_ENDPOINT") ) {
            $script:EnableGiTests = $true
        }
        else {
            write-warning "Disabled Guest Introspection tests due to missing precreated service definition.  Create a service definition called pester_sd_gi with Host Based Guest Introspection mechanism, at least one service profile and the File Integrity Monitoring category enabled to enable these tests."
        }

        #There are a few tests that fail regularly but seem to work when run interactively.
        #They appear related to slowness of NSX in cleaning up firewall rules on policy deletion
        #causing deletion of related groups to fail.  We will disable them for now.
        $script:EnableDodgyTests = $false
        if ( $EnableDodgyTests) {
            write-warning "Disabled tests that fail because of group deletion failure immediately after removal of security policies applied to them."
        }
    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        get-vm $testVMName1 -ErrorAction Ignore | remove-vm -Confirm:$false -DeletePermanently
        write-host -ForegroundColor Green "Completed cleanup tasks for Sec Pol tests"

    }

    Context "Policy Retrieval" {

        it "Can retreive a security policy" {
            #The system policies should always exist, so we just get them.
            $AllPolicy = Get-NsxSecurityPolicy -IncludeHidden
            $AllPolicy | should not be $null
            $FirstPolicy = $AllPolicy | Select-Object -First 1
            $FirstPolicy.objectId | should match "policy-\d+"
        }

        it "Can retreive the highest precedence number in use" {
            $currprecedence = Get-NsxSecurityPolicyHighestUsedPrecedence
            $currprecedence.Precedence | should match "\d+"
            #System policies make the lowest posible value for a default system 3300
            $currprecedence.Precedence | should begreaterthan 3299
        }
    }

    Context "Service Definition and Profile Retrieval" {

        it "Can retreive a service definition" {
            #The default definitions should always exist, so we just get them.
            $SD = Get-NsxServiceDefinition
            $SD | should not be $null
            $FirstSD = $SD | Select-Object -First 1
            $FirstSD.objectId | should match "service-\d+"
            $FirstSD.type.typename | should be "Service"
        }

        it "Can retreive a service definition by Id" {
            #The default definitions should always exist
            $SD = Get-NsxServiceDefinition | Select-Object -first 1
            $getSD = Get-NsxServiceDefinition -objectId $SD.objectID
            $getSD | should not be $null
            ($getSD | Measure-Object).count | should be 1
            $getSD.objectId | should be $sd.objectId
        }

        it "Can retreive a service definition by Name" {
            #The default definitions should always exist, so we just get them.
            $SD = Get-NsxServiceDefinition | Select-Object -first 1
            $NameSd = Get-NsxServiceDefinition -Name $SD.Name
            $NameSD | should not be $null
            ($NameSD | Measure-Object).count | should be 1
            $NameSD.Name | should be $SD.Name
        }

        it "Can retrieve a service profile by service definition (on pipeline)" -skip:( -not $EnableNiTests) {
            #The default definitions should always exist, so we just get them.
            $SDP = Get-NsxServiceDefinition  $pester_sd_ni_name | Get-NsxServiceProfile
            ($SDP | Measure-Object).count | should be 1
            $SDP | should not be $null
        }

        it "Can retreive a service profile by name" -skip:( -not $EnableNiTests) {
            $SDP = Get-NsxServiceDefinition  $pester_sd_ni_name | Get-NsxServiceProfile
            $GetSDP = Get-NsxServiceProfile -Name $SDP.Name
            $GetSDP | should not be $null
            ($GetSDP | Measure-Object).count | should be 1
            $SDP.Name| should be $SDP.Name
        }

        it "Can retreive a service profile by id" -skip:( -not $EnableNiTests) {
            $SDP = Get-NsxServiceDefinition  $pester_sd_ni_name | Get-NsxServiceProfile
            $GetSDP = Get-NsxServiceProfile -ObjectId $SDP.objectID
            $GetSDP | should not be $null
            ($GetSDP | Measure-Object).count | should be 1
            $SDP.objectId | should be $SDP.objectID
        }
    }

    Context "Security Policy Applicable Actions" {
        BeforeEach {

        }

        AfterEach {
            Get-NsxSecurityPolicy | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            while ( $grps | Get-NsxApplicableSecurityAction ) {
                #Wait for api to catch up
                start-sleep -Seconds 1
                $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            }
            $grps | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

            It "Can get actions applicable to a VM" -skip:( -not $EnableDodgyTests) {
            $polName = ($SpNamePrefix + "policy1")
            $grpName = ($SpNamePrefix + "grp1")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1"
            $sp = new-nsxsecuritypolicy -Name $polname -FirewallRuleSpec $spec
            $sg = new-nsxsecuritygroup -name $grpname -IncludeMember $testvm1
            $sp | New-NsxSecurityPolicyAssignment -SecurityGroup $sg
            #We have to sleep as it takes time for NSX to do the needful
            start-sleep -Seconds 5
            $actions = $testvm1 | Get-NsxApplicableSecurityAction
            ($actions | Measure-Object).count | should be 1
            $actions.category | should be "firewall"
            $actions.securitypolicy.objectid | should be $sp.objectid
        }
            it "Can get actions applicable to a SecurityGroup" -skip:( -not $EnableDodgyTests) {
            $polName = ($SpNamePrefix + "policy1")
            $grpName = ($SpNamePrefix + "grp1")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1"
            $sp = new-nsxsecuritypolicy -Name $polname -FirewallRuleSpec $spec
            $sg = new-nsxsecuritygroup -name $grpname
            $sp | New-NsxSecurityPolicyAssignment -SecurityGroup $sg
            #We have to sleep as it takes time for NSX to do the needful
            start-sleep -Seconds 5
            $actions = $sg | Get-NsxApplicableSecurityAction
            ($actions | Measure-Object).count | should be 1
            $actions.category | should be "firewall"
            $actions.securitypolicy.objectid | should be $sp.objectid
        }
            it "Can get actions applicable to a SecurityPolicy" -skip:( -not $EnableDodgyTests) {
            $polName = ($SpNamePrefix + "policy1")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1"
            $sp = new-nsxsecuritypolicy -Name $polname -FirewallRuleSpec $spec
            #We have to sleep as it takes time for NSX to do the needful
            start-sleep -Seconds 5
            $actions = $sp | Get-NsxApplicableSecurityAction
            ($actions | Measure-Object).count | should be 1
            $actions.category | should be "firewall"
            $actions.securitypolicy.objectid | should be $sp.objectid
        }
    }

    Context "Spec Definition" {
        BeforeEach {
        }

        AfterEach {
            # Get-NsxSecurityPolicy | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            # $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            # while ( $grps | Get-NsxApplicableSecurityAction ) {
            #     #Wait for api to catch up
            #     start-sleep -Seconds 1
            #     $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            # }
            # $grps | Remove-NsxSecurityGroup -Confirm:$false
            # Get-NsxService | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            # Get-NsxServiceGroup | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

        it "Can create a security policy firewall spec - intra - mode1 (Source/Dest w/PSG based)" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -direction Intra
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "intra"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
        }

        it "Can create a security policy firewall spec - intra - mode2 (Direction based)" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1"
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "intra"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
        }

        it "Can create a security policy firewall spec source ANY - mode1 (Source/Dest w/PSG based)" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source Any
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "inbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
        }

        it "Can create a security policy firewall spec source ANY - mode2 (Direction based)" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Direction inbound
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "inbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
        }

        it "Can create a security policy firewall spec dest ANY - mode1 (Source/Dest w/PSG based)" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Destination Any
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "outbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
        }

        it "Can create a security policy firewall spec dest ANY - mode2 (Direction based)" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Direction outbound
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "outbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
        }

        it "Can create a security policy firewall spec source security group - mode1 (Source/Dest w/PSG based)" {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg1")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source $sg
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "inbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
        }

        it "Can create a security policy firewall spec source security group - mode2 (Direction based)" {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg2")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -direction inbound -SecurityGroup $sg
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "inbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
        }

        it "Can create a security policy firewall spec destination security group - mode1 (Source/Dest w/PSG based)" {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg3")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Destination $sg
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "outbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
        }

        it "Can create a security policy firewall spec destination security group - mode2 (Direction based)" {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg4")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -direction outbound -SecurityGroup $sg
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "outbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
        }

        it "Can create a security policy firewall spec source multiple security group - mode1 (Source/Dest w/PSG based)" {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg5")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg6")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source $sg1,$sg2
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "inbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
        }

        it "Can create a security policy firewall spec source multiple security group - mode2 (Direction based)" {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg7")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg8")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source $sg1,$sg2
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "inbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
        }

        it "Can create a security policy firewall spec destination multiple security group - mode1 (Source/Dest w/PSG based)" {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg9")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg10")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -destination $sg1,$sg2
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "outbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
        }

        it "Can create a security policy firewall spec destination multiple security group - mode2 (Direction based)" {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg11")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "sg12")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Direction outbound -SecurityGroup $sg1,$sg2
            $spec.class | should be "firewallSecurityAction"
            $spec.direction | should be "outbound"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
        }

        it "Can create a security policy firewall spec with service" {
            $svc = New-NsxService -Name ($SpNamePrefix + "svc1") -port 22 -protocol TCP
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svc
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.applications.application.objectId | should be $svc.objectId
        }

        it "Can create a security policy firewall spec with multiple services" {
            $svc1 = New-NsxService -Name ($SpNamePrefix + "svc2") -port 22 -protocol TCP
            $svc2 = New-NsxService -Name ($SpNamePrefix + "svc3") -port 22 -protocol TCP
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svc1,$svc2
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.applications.application.objectId -contains $svc1.objectId | should be $true
            $spec.applications.application.objectId -contains $svc2.objectId | should be $true
        }

        it "Can create a security policy firewall spec with servicegroup" {
            $svcgrp = New-NsxServiceGroup -Name ($SpNamePrefix + "svcgrp")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svcgrp
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.applications.applicationgroup.objectId | should be $svcgrp.objectId
        }

        it "Can create a security policy firewall spec with multiple servicegroups" {
            $svcgrp1 = New-NsxServiceGroup -Name ($SpNamePrefix + "svcgrp1")
            $svcgrp2 = New-NsxServiceGroup -Name ($SpNamePrefix + "svcgrp2")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svcgrp1,$svcgrp2
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.applications.applicationgroup.objectId -contains $svcgrp1.objectId | should be $true
            $spec.applications.applicationgroup.objectId -contains $svcgrp2.objectId | should be $true
        }

        it "Can create a security policy firewall spec with both service and servicegroups" {
            $svc1 = New-NsxService -Name ($SpNamePrefix + "svc4") -port 22 -protocol TCP
            $svcgrp3 = New-NsxServiceGroup -Name ($SpNamePrefix + "svcgrp3")
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svc1,$svcgrp3
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "true"
            $spec.applications.application.objectId -contains $svc1.objectId | should be $true
            $spec.applications.applicationgroup.objectId -contains $svcgrp3.objectId | should be $true
        }

        it "Can create a disabled security policy firewall spec" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Disabled
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "allow"
            $spec.isEnabled | should be "false"
        }

        it "Can create a blocking security policy firewall spec" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -action Block
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "block"
        }

        it "Can create a reject security policy firewall spec" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -action reject
            $spec.class | should be "firewallSecurityAction"
            $spec.action | should be "reject"
        }

        It "Can create an AV Guest Introspection Spec" {
            $spec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceType ANTIVIRUS
            $spec.class | should be "endpointSecurityAction"
            $spec.actiontype | should be "ANTI_VIRUS"
        }

        It "Can create a FIM Guest Introspection Spec" {
            $spec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceType FileIntegrityMonitoring
            $spec.class | should be "endpointSecurityAction"
            $spec.actiontype | should be "FIM"
        }

        It "Can create a vulnerability management Guest Introspection Spec" {
            $spec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceType VulnerabilityManagement
            $spec.class | should be "endpointSecurityAction"
            $spec.actiontype | should be "VULNERABILITY_MGMT"
        }

        It "Can create a service / service profile based Guest Introspection Spec" -skip:( -not $EnableGiTests) {
            $spec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -serviceDefinition $gisd -ServiceProfile $gisp
            $spec.class | should be "endpointSecurityAction"
            $spec.ServiceId | should be $gisd.objectid
            $spec.serviceProfile.objectId | should be $gisp.objectId
        }

        ############

        it "Can create a security policy network introspection spec - intra - mode1 (Source/Dest w/PSG based)" -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -direction Intra -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "intra"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec - intra - mode2 (Direction based)"  -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "intra"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec source ANY - mode1 (Source/Dest w/PSG based)"  -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source Any -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "inbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec source ANY - mode2 (Direction based)" -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Direction inbound -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "inbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec dest ANY - mode1 (Source/Dest w/PSG based)" -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Destination Any -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "outbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec dest ANY - mode2 (Direction based)" -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Direction outbound -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "outbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup | should be $null
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec source security group - mode1 (Source/Dest w/PSG based)" -skip:( -not $EnableNiTests) {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg1")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source $sg -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "inbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec source security group - mode2 (Direction based)"  -skip:( -not $EnableNiTests) {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg2")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -direction inbound -SecurityGroup $sg -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "inbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec destination security group - mode1 (Source/Dest w/PSG based)" -skip:( -not $EnableNiTests) {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg3")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Destination $sg -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "outbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec destination security group - mode2 (Direction based)" -skip:( -not $EnableNiTests) {
            $sg = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg4")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -direction outbound -SecurityGroup $sg -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "outbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId | should be $sg.objectId
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec source multiple security group - mode1 (Source/Dest w/PSG based)" -skip:( -not $EnableNiTests) {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg5")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg6")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source $sg1,$sg2 -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "inbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec source multiple security group - mode2 (Direction based)" -skip:( -not $EnableNiTests) {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg7")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg8")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Source $sg1,$sg2 -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "inbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec destination multiple security group - mode1 (Source/Dest w/PSG based)" -skip:( -not $EnableNiTests) {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg9")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg10")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -destination $sg1,$sg2 -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "outbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec destination multiple security group - mode2 (Direction based)" -skip:( -not $EnableNiTests) {
            $sg1 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg11")
            $sg2 = New-NsxSecurityGroup -Name ($SpNamePrefix + "nisg12")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Direction outbound -SecurityGroup $sg1,$sg2 -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.direction | should be "outbound"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.secondarySecurityGroup.objectId -contains $sg1.objectId | should be $true
            $spec.secondarySecurityGroup.objectId -contains $sg2.objectId | should be $true
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec with service" -skip:( -not $EnableNiTests) {
            $svc = New-NsxService -Name ($SpNamePrefix + "nisvc1") -port 22 -protocol TCP
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svc -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.applications.application.objectId | should be $svc.objectId
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec with multiple services" -skip:( -not $EnableNiTests) {
            $svc1 = New-NsxService -Name ($SpNamePrefix + "nisvc2") -port 22 -protocol TCP
            $svc2 = New-NsxService -Name ($SpNamePrefix + "nisvc3") -port 22 -protocol TCP
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svc1,$svc2 -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.applications.application.objectId -contains $svc1.objectId | should be $true
            $spec.applications.application.objectId -contains $svc2.objectId | should be $true
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        #To Do - fix the following tests.

        # it "Can create a security policy network introspection spec with servicegroup" -skip:( -not $EnableNiTests) {
        #     $svcgrp = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp1")
        #     $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svcgrp -ServiceProfile $nisp
        #     $spec.class | should be "trafficSteeringSecurityAction"
        #     $spec.redirect | should be "true"
        #     $spec.isEnabled | should be "true"
        #     $spec.applications.applicationgroup.objectId | should be $svcgrp.objectId
        #     $spec.serviceProfile.objectId | should be $nisp.objectID
        # }

        # it "Can create a security policy network introspection spec with multiple servicegroups" -skip:( -not $EnableNiTests) {
        #     $svcgrp1 = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp2")
        #     $svcgrp2 = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp3")
        #     $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svcgrp1,$svcgrp2 -ServiceProfile $nisp
        #     $spec.class | should be "trafficSteeringSecurityAction"
        #     $spec.redirect | should be "true"
        #     $spec.isEnabled | should be "true"
        #     $spec.applications.applicationgroup.objectId -contains $svcgrp1.objectId | should be $true
        #     $spec.applications.applicationgroup.objectId -contains $svcgrp2.objectId | should be $true
        #     $spec.serviceProfile.objectId | should be $nisp.objectID
        # }

        # it "Can create a security policy network introspection spec with both services and servicegroups" -skip:( -not $EnableNiTests) {
        #     $svc1 = New-NsxService -Name ($SpNamePrefix + "nisvc3")
        #     $svcgrp1 = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp4")
        #     $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svc1,$svcgrp2 -ServiceProfile $nisp
        #     $spec.class | should be "trafficSteeringSecurityAction"
        #     $spec.redirect | should be "true"
        #     $spec.isEnabled | should be "true"
        #     $spec.applications.application.objectId -contains $svc1.objectId | should be $true
        #     $spec.applications.applicationgroup.objectId -contains $svcgrp2.objectId | should be $true
        #     $spec.serviceProfile.objectId | should be $nisp.objectID
        # }

        it "Can create a disabled security policy network introspection spec" -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Disabled -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "false"
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec with redirection disabled" -skip:( -not $EnableNiTests) {
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp -DisableRedirection
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.redirect | should be "false"
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

    }

    Context "Security Policy Creation" {

        BeforeEach {
        }

        AfterEach {
            Get-NsxSecurityPolicy | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxService | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

        It "Can create an empty security policy"  {
            $polName = ($SpNamePrefix + "policy0")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy"
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
        }

        It "Can create a security policy with single firewall rule" {
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1"
            $polName = ($SpNamePrefix + "policy1")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -FirewallRuleSpec $spec
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'firewall'}).action.name -contains $spec.Name | should be $true
        }

        It "Can create a security policy with multiple firewall rules" {
            $spec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec1") -Description "Pester Spec 1"
            $spec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec2") -Description "Pester Spec 2"
            $polName = ($SpNamePrefix + "policy2")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -FirewallRuleSpec $spec1,$spec2
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'firewall'}).action.name -contains $spec1.Name | should be $true
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'firewall'}).action.name -contains $spec2.Name | should be $true
        }

        It "Can create a security policy with correct default precedence" {
            $currprecedence = Get-NsxSecurityPolicyHighestUsedPrecedence
            $polName = ($SpNamePrefix + "policy3")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy"
            $pol.precedence | should be ($currprecedence.precedence + 1000)
        }

        It "Can create a security policy with nondefault precedence" {
            $currprecedence = Get-NsxSecurityPolicyHighestUsedPrecedence
            $newprecedence = $currprecedence.precedence + 2000
            $polName = ($SpNamePrefix + "policy4")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -precedence $newprecedence
            $pol.precedence | should be $newprecedence
        }

        It "Can create a security policy with a guest introspection rule." {
            $spec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceType ANTIVIRUS
            $polName = ($SpNamePrefix + "policy5")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -GuestIntrospectionSpec $spec
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'endpoint'}).action.name -contains $spec.Name | should be $true
        }

        It "Can create a security policy with multiple guest introspection rules." {
            $spec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec1") -Description "Pester Spec 1" -ServiceType Antivirus
            $spec2 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec2") -Description "Pester Spec 2" -ServiceType FileIntegrityMonitoring
            $polName = ($SpNamePrefix + "policy6")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -GuestIntrospectionSpec $spec1,$spec2
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'endpoint'}).action.name -contains $spec1.Name | should be $true
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'endpoint'}).action.name -contains $spec2.Name | should be $true
        }

        It "Can create a security policy with a network introspection rule."  -skip:( -not $EnableNiTests){
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp
            $polName = ($SpNamePrefix + "policy7")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -NetworkIntrospectionSpec $spec
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'traffic_steering'}).action.name -contains $spec.Name | should be $true
        }

        It "Can create a security policy with multiple network introspection rules." -skip:( -not $EnableNiTests) {
            $spec1 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp
            $spec2 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp -source any
            $polName = ($SpNamePrefix + "policy8")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -NetworkIntrospectionSpec $spec1,$spec2
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'traffic_steering'}).action.name -contains $spec1.Name | should be $true
            ($pol.actionsByCategory | Where-Object { $_.category -eq 'traffic_steering'}).action.name -contains $spec2.Name | should be $true
        }


    }

    Context "Security Policy Assignment" {
        BeforeEach {
        }

        AfterEach {
            Get-NsxSecurityPolicy | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            while ( $grps | Get-NsxApplicableSecurityAction ) {
                #Wait for api to catch up
                start-sleep -Seconds 1
                $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            }
            $grps | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

        It "Can assign a policy to a Security Group" {
            $polName = ($SpNamePrefix + "policy1")
            $grpName = ($SpNamePrefix + "grp1")
            $sp = new-nsxsecuritypolicy -Name $polname
            $sg = new-nsxsecuritygroup -name $grpname
            $newsp = $sp | New-NsxSecurityPolicyAssignment -SecurityGroup $sg
            $newsp.securityGroupBinding.objectId | should be $sg.objectID
        }

        It "Can remove a policy assignment from a Security Group" {
            $polName = ($SpNamePrefix + "policy2")
            $grpName = ($SpNamePrefix + "grp2")
            $sp = new-nsxsecuritypolicy -Name $polname
            $sg = new-nsxsecuritygroup -name $grpname
            $newsp = $sp | New-NsxSecurityPolicyAssignment -SecurityGroup $sg
            $newsp.securityGroupBinding.objectId | should be $sg.objectID
            $newnewsp = $newsp | Remove-NsxSecurityPolicyAssignment -SecurityGroup $sg
            ($newnewsp | get-member -membertype property -Name securityGroupBinding) | should be $null
        }

    }

    Context "Policy Removal" {
        it "Can remove a policy" {
             $sp = new-nsxsecuritypolicy -Name $spNamePrefix
             $sp | should not be $null
             $sp | remove-nsxsecuritypolicy -confirm:$false
             {get-nsxsecuritypolicy -objectId $sp.objectId} | should throw
        }
    }

    Context "Policy Modification" {
        BeforeEach {
            $script:sp = new-nsxsecuritypolicy -Name $spNamePrefix
            $script:spmodname = "$($spNamePrefix)_testmod"
            $script:inheritspname = "$($spNamePrefix)_inherited"
            $script:inheritsp = new-nsxsecuritypolicy -Name $inheritspname
        }
        AfterEach {
            Get-nsxsecuritypolicy  | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
        }

        it "Can set an existing policy name" {
            $newsp = $sp | Set-NsxSecurityPolicy -Name $spmodname -NoConfirm
            $newsp.name | should be $spmodname
        }

        it "Can set an existing policy description" {
            $newsp = $sp | Set-NsxSecurityPolicy -Description $spmodname -NoConfirm
            $newsp.description | should be $spmodname
        }

        It "Can configure policy inheritance" {
            $newsp = $inheritsp | Set-NsxSecurityPolicy -inheritpolicy $sp -NoConfirm
            $newsp.parent.objectId | should be $sp.objectId
        }

        It "Can disable policy inheritance" {
            $newsp = $inheritsp | Set-NsxSecurityPolicy -inheritpolicy $sp -NoConfirm
            $newsp.parent.objectId | should be $sp.objectId
            $newnewsp = $newsp | set-nsxsecuritypolicy -disableinheritance -NoConfirm
            $newnewsp.parent | should be $null
        }

        It "Can configure policy weight" {
            $newsp = $sp | Set-NsxSecurityPolicy -weight 100000 -NoConfirm
            $newsp.precedence | should be 100000
        }
    }

    Context "Rule Retrieval" {
        BeforeEach {

        }
        AfterEach {
            Get-nsxsecuritypolicy  | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
        }

        it "Can retrieve a policy rule of all three types" -skip:( -not $EnableNiTests ) {
            $fwspec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $gispec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec2") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $nispec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec3") -Description "Pester NI Spec 1" -Source Any -ServiceProfile $nisp
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec -GuestIntrospectionSpec $gispec -NetworkIntrospectionSpec $nispec
            $sp | get-nsxsecuritypolicyrule
            ($sp | get-nsxsecuritypolicyrule).class -contains "firewallSecurityAction" | should be $true
            ($sp | get-nsxsecuritypolicyrule).class -contains "endpointSecurityAction" | should be $true
            ($sp | get-nsxsecuritypolicyrule).class -contains "trafficSteeringSecurityAction" | should be $true
        }

        it "Can retrieve a policy rule of firewall type" {
            $fwspec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $gispec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec2") -Description "Pester GI Spec 1" -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec -GuestIntrospectionSpec $gispec
            $rules = $sp | get-nsxsecuritypolicyrule -ruletype firewall
            $rules.class -contains "firewallSecurityAction" | should be $true
            $rules.class -contains "endpointSecurityAction" | should be $false
        }

        it "Can retrieve a policy rule of guest introspection type" {
            $fwspec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $gispec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec2") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec -GuestIntrospectionSpec $gispec
            $rules = $sp | get-nsxsecuritypolicyrule -ruletype guest
            $rules.class -contains "firewallSecurityAction" | should be $false
            $rules.class -contains "endpointSecurityAction" | should be $true
        }

        it "Can retrieve a policy rule of network introspection type" -skip:( -not $EnableNiTests) {
            $fwspec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $gispec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec2") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $nispec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec3") -Description "Pester NI Spec 1" -Source Any -ServiceProfile $nisp
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec -GuestIntrospectionSpec $gispec -NetworkIntrospectionSpec $nispec
            $rules = $sp | get-nsxsecuritypolicyrule -ruletype network
            $rules.class -contains "firewallSecurityAction" | should be $false
            $rules.class -contains "endpointSecurityAction" | should be $false
            $rules.class -contains "trafficSteeringSecurityAction" | should be $true
        }
    }

    Context "Rule Addition" {
        BeforeEach {

        }

        AfterEach {
            Get-nsxsecuritypolicy  | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
        }

        it "Can add a firewall rule to an existing policy" {
            $fwspec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix
            $newsp = $sp | Add-NsxSecurityPolicyRule -FirewallRuleSpec $fwspec
            $fwrules = $newsp.actionsByCategory.action | Where-Object { $_.class -eq 'firewallSecurityAction'}
            $fwrules.name -contains $fwspec.name | should be $true
        }

        it "Can add a guest introspection rule to an existing policy" {
            $gispec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec2") -Description "Pester GI Spec 1" -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix
            $newsp = $sp | Add-NsxSecurityPolicyRule -GuestIntrospectionSpec $gispec
            $girules = $newsp.actionsByCategory.action | Where-Object { $_.class -eq 'endpointSecurityAction'}
            $girules.name -contains $gispec.name | should be $true
        }

        it "Can add a network introspection rule to an existing policy" -skip:( -not $EnableNiTests ){
            $nispec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec3") -Description "Pester NI Spec 1" -Source Any -ServiceProfile $nisp
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix
            $newsp = $sp | Add-NsxSecurityPolicyRule -NetworkIntrospectionSpec $nispec
            $nirules = $newsp.actionsByCategory.action | Where-Object { $_.class -eq 'trafficSteeringSecurityAction'}
            $nirules.name -contains $nispec.name | should be $true
        }

        it "Can add all three types of rule to an existing policy" -skip:( -not $EnableNiTests ) {
            $fwspec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $gispec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec2") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $nispec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec3") -Description "Pester NI Spec 1" -Source Any -ServiceProfile $nisp
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix
            $newsp = $sp | Add-NsxSecurityPolicyRule -FirewallRuleSpec $fwspec -GuestIntrospectionSpec $gispec -NetworkIntrospectionSpec $nispec
            $rules = $newsp.actionsByCategory.action
            $rules.name -contains $fwspec.name | should be $true
            $rules.name -contains $gispec.name | should be $true
            $rules.name -contains $nispec.name | should be $true
        }
    }

    Context "Rule Removal" {

        BeforeAll {

        }
        AfterAll {
            Get-nsxsecuritypolicy  | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
        }

        it "Can remove a rule from an existing security policy" {
            $fwspec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $gispec = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec2") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec -GuestIntrospectionSpec $gispec
            $rules = $sp | Get-NsxSecurityPolicyRule
            $rule = $rules | Select-Object -first 1
            $rule | remove-nsxsecuritypolicyrule -NoConfirm
            $rules = get-nsxsecuritypolicy -objectId $sp.objectId | Get-NsxSecurityPolicyRule
            $rules.name -contains $rule.name | should be $false
        }

    }

    Context "Rule Move" {

        BeforeEach {
            }
        AfterEach {
            Get-nsxsecuritypolicy  | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
        }

        it "Can move a firewall rule to the top" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rules = $sp | Get-NsxSecurityPolicyrule -ruletype firewall
            $bottomrule = $rules | sort-object -Property executionorder | Select-Object -last 1
            $newrule = $bottomrule | move-nsxsecuritypolicyrule -Destination Top -NoConfirm
            $newrule.executionOrder | should be 1
        }

        it "Can move a firewall rule to the bottom" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rules = $sp | Get-NsxSecurityPolicyrule -ruletype firewall
            $toprule = $rules | sort-object -Property executionorder | Select-Object -first 1
            $newrule = $toprule | move-nsxsecuritypolicyrule -Destination Bottom -NoConfirm
            $lastrule = $rules | Sort-Object -Property executionOrder | Select-Object -Last 1
            $newrule.executionorder | should be $lastrule.executionorder

        }

        it "Can move a firewall rule to the a specific position" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rules = $sp | Get-NsxSecurityPolicyrule -ruletype firewall
            $toprule = $rules | sort-object -Property executionorder | Select-Object -first 1
            $newrule = $toprule | move-nsxsecuritypolicyrule -Destination 3 -NoConfirm
            $newrule.executionorder | should be "3"
        }
    }

    Context "Rule Modification" {
        BeforeEach {

        }
        AfterEach {
            Get-nsxsecuritypolicy  | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
        }

        it "Can modify the name of an existing firewall rule" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS

            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -First 1
            $newrule = $rule | set-nsxsecuritypolicyfirewallrule -Name ($spnameprefix + "test") -NoConfirm
            $newrule.name | should be ($spnameprefix + "test")
        }

        it "Can modify the description of an existing firewall rule" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -First 1
            $newrule = $rule | set-nsxsecuritypolicyfirewallrule -description ($spnameprefix + "test") -NoConfirm
            $newrule.description | should be ($spnameprefix + "test")
        }

        it "Can modify the action of an existing firewall rule" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -First 1
            $newrule = $rule | set-nsxsecuritypolicyfirewallrule -action block -NoConfirm
            $newrule.action | should be "block"
        }

        it "Can modify the logging config of an existing firewall rule" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -First 1
            $newrule = $rule | set-nsxsecuritypolicyfirewallrule -loggingEnabled $true -NoConfirm
            $newrule.logged | should be "true"
        }

        it "Can disable and enable an existing firewall rule" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -First 1
            $newrule = $rule | set-nsxsecuritypolicyfirewallrule -enabled $false -NoConfirm
            $newrule.isEnabled | should be "false"
            $newnewrule = $newrule | set-nsxsecuritypolicyfirewallrule -enabled $true -NoConfirm
            $newnewrule.isEnabled | should be "true"
        }

        it "Can change the direction of a rule" {
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source Any
            $fwspec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec2") -Description "Pester FW Spec 2" -Source Any
            $fwspec3 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec3") -Description "Pester FW Spec 3" -Source Any
            $gispec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "gispec1") -Description "Pester GI Spec 1"  -ServiceType ANTIVIRUS
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1, $fwspec2, $fwspec3 -GuestIntrospectionSpec $gispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -First 1
            $newrule = $rule | set-nsxsecuritypolicyfirewallrule -direction outbound -NoConfirm
            $newrule.direction | should be "outbound"
            $newnewrule = $newrule | set-nsxsecuritypolicyfirewallrule -direction intra -NoConfirm
            $newnewrule.direction | should be "intra"
            $newnewnewrule = $newnewrule | set-nsxsecuritypolicyfirewallrule -direction inbound -NoConfirm
            $newnewnewrule.direction | should be "inbound"
        }
    }

    Context "Rule Group Modification" {
        BeforeEach {
        }

        AfterEach {
            Get-NsxSecurityPolicy | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            while ( $grps | Get-NsxApplicableSecurityAction ) {
                #Wait for api to catch up
                start-sleep -Seconds 1
                $grps = Get-NsxSecurityGroup | Where-Object { $_.name -match $spNamePrefix }
            }
            $grps | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

        it "Can add a group to a security policy firewall rule" -skip:( -not $EnableDodgyTests) {
            $grp1 = new-nsxsecuritygroup -name ($SPNamePrefix + "grp1")
            $grp2 = new-nsxsecuritygroup -name ($SPNamePrefix + "grp2")
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source $grp1
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall| Select-Object -first 1
            $newrule = $rule | add-nsxsecuritypolicyrulegroup -securitygroup $grp2 -NoConfirm
            $newrule.secondarySecurityGroup.objectId -contains $grp2.objectId | should be $true
        }

            it "Can remove a group from a security policy firewall rule" -skip:( -not $EnableDodgyTests) {
            $grp1 = new-nsxsecuritygroup -name ($SPNamePrefix + "grp1")
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source $grp1
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -first 1
            $newrule = $rule | remove-nsxsecuritypolicyrulegroup -securitygroup $grp1 -Noconfirm -NoConfirmOnLastGroupRemoval
            $newrule.secondarySecurityGroup.objectId -contains $grp1.objectId | should be $false
        }

        it "Can add a group to a security policy network introspection rule" -skip:( -not ($EnableNiTests -and $EnableDodgyTests )) {
            $grp1 = new-nsxsecuritygroup -name ($SPNamePrefix + "grp1")
            $grp2 = new-nsxsecuritygroup -name ($SPNamePrefix + "grp2")
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source $grp1
            $nispec1 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec1") -Description "Pester NI Spec 1" -Source $grp1 -ServiceProfile $nisp
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1 -NetworkIntrospectionSpec $nispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype network | Select-Object -first 1
            $newrule = $rule | add-nsxsecuritypolicyrulegroup -securitygroup $grp2 -NoConfirm
            $newrule.secondarySecurityGroup.objectId -contains $grp2.objectId | should be $true
        }

        it "Can remove a group from a security policy network introspection rule" -skip:( -not ($EnableNiTests -and $EnableDodgyTests ))  {
            $grp1 = new-nsxsecuritygroup -name ($SPNamePrefix + "grp1")
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source $grp1
            $nispec1 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec1") -Description "Pester NI Spec 1" -Source $grp1 -ServiceProfile $nisp
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1 -NetworkIntrospectionSpec $nispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype network | Select-Object -first 1
            $newrule = $rule | remove-nsxsecuritypolicyrulegroup -securitygroup $grp1 -Noconfirm -NoConfirmOnLastGroupRemoval
            $newrule.secondarySecurityGroup.objectId -contains $grp1.objectId | should be $false
        }
    }

    Context "Rule Service Modification" {

        BeforeEach {

        }
        AfterEach {
            Get-nsxsecuritypolicy  | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            try {
                Get-NsxService | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxService -confirm:$false
            }
            Catch {
                Write-Verbose "Caught error when cleaning up services."
                Write-Verbose "$_"
                Write-Verbose "Going to sleep for 10 secs to wait for NSX Manager to do its thing."
                sleep 10
                Get-NsxService | Where-Object { $_.name -match $spNamePrefix } | Remove-NsxService -confirm:$false
            }
        }

        it "Can add a service to a security policy firewall rule" {
            $svc1 = new-nsxservice -name ($SPNamePrefix + "svc1") -Protocol TCP -port 80
            $svc2 = new-nsxservice -name ($SPNamePrefix + "svc2") -Protocol TCP -port 80
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source any -service $svc1
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall| Select-Object -first 1
            $newrule = $rule | add-nsxsecuritypolicyruleservice -service $svc2 -NoConfirm
            $newrule.applications.application.objectid -contains $svc2.objectId | should be $true
        }

        it "Can remove a service from a security policy firewall rule" {
            $svc1 = new-nsxservice -name ($SPNamePrefix + "svc1") -Protocol TCP -port 80
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source any -service $svc1
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype firewall | Select-Object -first 1
            $newrule = $rule | remove-nsxsecuritypolicyruleservice -service $svc1 -Noconfirm -NoConfirmOnLastServiceRemoval
            $newrule.applications.application.objectid -contains $svc1.objectId | should be $false
        }

        it "Can add a service to a security policy network introspection rule" -skip:( -not $EnableNiTests ) {
            $svc1 = new-nsxservice -name ($SPNamePrefix + "svc1") -Protocol TCP -port 80
            $svc2 = new-nsxservice -name ($SPNamePrefix + "svc2") -Protocol TCP -port 80
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source any -service $svc1
            $nispec1 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec1") -Description "Pester NI Spec 1" -Source any -ServiceProfile $nisp -service $svc1
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1 -NetworkIntrospectionSpec $nispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype network| Select-Object -first 1
            $newrule = $rule | add-nsxsecuritypolicyruleservice -service $svc2 -NoConfirm
            $newrule.applications.application.objectid -contains $svc2.objectId | should be $true
        }

        it "Can remove a service from a security policy network introspection rule" -skip:( -not $EnableNiTests ) {
            $svc1 = new-nsxservice -name ($SPNamePrefix + "svc1") -Protocol TCP -port 80
            $fwspec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "fwspec1") -Description "Pester FW Spec 1" -Source any -service $svc1
            $nispec1 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "nispec1") -Description "Pester NI Spec 1" -Source any -ServiceProfile $nisp -service $svc1
            $sp = new-nsxsecuritypolicy -Name $spNamePrefix -FirewallRuleSpec $fwspec1 -NetworkIntrospectionSpec $nispec1
            $rule = $sp | get-nsxsecuritypolicyrule -ruletype network | Select-Object -first 1
            $newrule = $rule | remove-nsxsecuritypolicyruleservice -service $svc1 -Noconfirm -NoConfirmOnLastServiceRemoval
            $newrule.applications.application.objectid -contains $svc1.objectId | should be $false
        }
    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver
    }
}
