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
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefMgrCred -ViWarningAction "Ignore"
        # $script:cl = get-cluster | select -first 1
        # write-warning "Using cluster $cl for clustery stuff"
        # $script:ds = $cl | get-datastore | select -first 1
        # write-warning "Using datastore $ds for datastorey stuff"
        $script:SpNamePrefix = "pester_secpol_"

        # These Service Defintions and Service profiles have to be precreated manually in for the associated tests to be run.
        # We know how to create the service defintion, but not sure on the service profile.
        $script:pester_sd_ni_name = "pester_sd_ni"  
        $script:pester_sd_gi_name = "pester_sd_gi"  
        $script:nisd = Get-NsxServiceDefinition -Name $pester_sd_ni_name
        $script:nisp = $nisd | Get-NsxServiceProfile
        $script:gisd = Get-NsxServiceDefinition -Name $pester_sd_gi_name
        $script:gisp = $gisd | Get-NsxServiceProfile
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
            $SD = Get-NsxServiceDefinition | select -first 1
            $getSD = Get-NsxServiceDefinition -objectId $SD.objectID
            $getSD | should not be $null
            ($getSD | measure).count | should be 1
            $getSD.objectId | should be $sd.objectId
        }   

        it "Can retreive a service definition by Name" {
            
            #The default definitions should always exist, so we just get them.
            $SD = Get-NsxServiceDefinition | select -first 1
            $NameSd = Get-NsxServiceDefinition -Name $SD.Name
            $NameSD | should not be $null
            ($NameSD | measure).count | should be 1
            $NameSD.Name | should be $SD.Name 
        }   

        it "Can retreive a service profile by service definition (on pipeline)" -skip:( -not $EnableNiTests) {
            
            #The default definitions should always exist, so we just get them.
            $SDP = Get-NsxServiceDefinition  $pester_sd_ni_name | Get-NsxServiceProfile
            ($SDP | measure).count | should be 1
            $SDP | should not be $null
            
        }   

        it "Can retreive a service profile by name" -skip:( -not $EnableNiTests) {
            
            $SDP = Get-NsxServiceDefinition  $pester_sd_ni_name | Get-NsxServiceProfile
            $GetSDP = Get-NsxServiceProfile -Name $SDP.Name
            $GetSDP | should not be $null
            ($GetSDP | measure).count | should be 1
            $SDP.Name| should be $SDP.Name
        }

        it "Can retreive a service profile by id" -skip:( -not $EnableNiTests) {
            
            $SDP = Get-NsxServiceDefinition  $pester_sd_ni_name | Get-NsxServiceProfile
            $GetSDP = Get-NsxServiceProfile -ObjectId $SDP.objectID
            $GetSDP | should not be $null
            ($GetSDP | measure).count | should be 1
            $SDP.objectId | should be $SDP.objectID
        }
    }
    
    Context "Spec Definition" {

        BeforeAll { 
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

        AfterAll { 
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
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

        it "Can create a security policy network introspection spec with servicegroup" -skip:( -not $EnableNiTests) {
            $svcgrp = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp1")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svcgrp -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.applications.applicationgroup.objectId | should be $svcgrp.objectId
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec with multiple servicegroups" -skip:( -not $EnableNiTests) {
            $svcgrp1 = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp2")
            $svcgrp2 = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp3")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svcgrp1,$svcgrp2 -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.applications.applicationgroup.objectId -contains $svcgrp1.objectId | should be $true
            $spec.applications.applicationgroup.objectId -contains $svcgrp2.objectId | should be $true
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

        it "Can create a security policy network introspection spec with both services and servicegroups" -skip:( -not $EnableNiTests) {
            $svc1 = New-NsxService -Name ($SpNamePrefix + "nisvc3")
            $svcgrp1 = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp4")
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -Service $svc1,$svcgrp2 -ServiceProfile $nisp
            $spec.class | should be "trafficSteeringSecurityAction"
            $spec.redirect | should be "true"
            $spec.isEnabled | should be "true"
            $spec.applications.application.objectId -contains $svc1.objectId | should be $true
            $spec.applications.applicationgroup.objectId -contains $svcgrp2.objectId | should be $true
            $spec.serviceProfile.objectId | should be $nisp.objectID
        }

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
        
        BeforeAll { 
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
        }
        AfterAll { 
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
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
            ($pol.actionsByCategory | ? { $_.category -eq 'firewall'}).action.name -contains $spec.Name | should be $true
        }

        It "Can create a security policy with multiple firewall rules" { 
            $spec1 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec1") -Description "Pester Spec 1"
            $spec2 = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec2") -Description "Pester Spec 2"
            $polName = ($SpNamePrefix + "policy2")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -FirewallRuleSpec $spec1,$spec2
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | ? { $_.category -eq 'firewall'}).action.name -contains $spec1.Name | should be $true
            ($pol.actionsByCategory | ? { $_.category -eq 'firewall'}).action.name -contains $spec2.Name | should be $true
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
            ($pol.actionsByCategory | ? { $_.category -eq 'endpoint'}).action.name -contains $spec.Name | should be $true
        }

        It "Can create a security policy with multiple guest introspection rules." { 
            $spec1 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec1") -Description "Pester Spec 1" -ServiceType Antivirus
            $spec2 = New-NsxSecurityPolicyGuestIntrospectionSpec -Name ($SpNamePrefix + "spec2") -Description "Pester Spec 2" -ServiceType FileIntegrityMonitoring
            $polName = ($SpNamePrefix + "policy6")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -GuestIntrospectionSpec $spec1,$spec2
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | ? { $_.category -eq 'endpoint'}).action.name -contains $spec1.Name | should be $true
            ($pol.actionsByCategory | ? { $_.category -eq 'endpoint'}).action.name -contains $spec2.Name | should be $true
        }

        It "Can create a security policy with a network introspection rule."  -skip:( -not $EnableNiTests){ 
            $spec = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp
            $polName = ($SpNamePrefix + "policy7")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -NetworkIntrospectionSpec $spec
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | ? { $_.category -eq 'traffic_steering'}).action.name -contains $spec.Name | should be $true
        }

        It "Can create a security policy with multiple network introspection rules." -skip:( -not $EnableNiTests) { 
            $spec1 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp
            $spec2 = New-NsxSecurityPolicyNetworkIntrospectionSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1" -ServiceProfile $nisp -source any
            $polName = ($SpNamePrefix + "policy8")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -NetworkIntrospectionSpec $spec1,$spec2
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | ? { $_.category -eq 'traffic_steering'}).action.name -contains $spec1.Name | should be $true
            ($pol.actionsByCategory | ? { $_.category -eq 'traffic_steering'}).action.name -contains $spec2.Name | should be $true
        }


    }

    Context "Security Policy Assignment" { 
        BeforeAll { 
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
        }
        AfterAll { 
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
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

    Context "Security Policy Firewall Rules" {
        BeforeAll {
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

        AfterAll {
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
            Get-NsxServiceGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxServiceGroup -Confirm:$false
        }

        It "Add a service object to a firewall rule within a security policy" {
            $svc1 = New-NsxService -Name ($SpNamePrefix + "nisvc11") -port 21 -protocol TCP
            $svc2 = New-NsxService -Name ($SpNamePrefix + "nisvc12") -port 22 -protocol TCP

            $ruleName = ($SpFwNamePrefix + "rule1")
            $rulespec = New-NsxSecurityPolicyFirewallRuleSpec -Name $ruleName -Direction 'outbound' -Service $svc1 -Action 'allow' -EnableLogging
            $polName = ($SpNamePrefix + "hash2")
            New-NsxSecurityPolicy $polName -FirewallRuleSpec $rulespec

            Add-NsxServiceToSPFwRule -SecurityPolicy (Get-NsxSecurityPolicy $polName) -Service $svc2 -ExecutionOrder 1
            $rule = Get-NsxApplicableFwRule -SecurityPolicy (Get-NsxSecurityPolicy $polName)
            $services = $rule.applications.application
            $services.Length | should be 2

            $index = 0
            Foreach ($service in $services) {
                $index = $index + 1
                $service.name | should be ($SpNamePrefix + "nisvc1" + $index)
                $service.element.applicationProtocol | should be "TCP"
                $service.element.value | should be ("2" + $index)
            }
        }

        It "Remove a service object from a firewall rule within a security policy" {
            # Dependent on prior test.
            $polName = ($SpNamePrefix + "hash2")
            $pol = Get-NsxSecurityPolicy $polName

            $svc2 = Get-NsxService ($SpNamePrefix + "nisvc12")

            Remove-NsxServiceFromSPFwRule -SecurityPolicy $pol -Service $svc2 -ExecutionOrder 1
            $rule = Get-NsxApplicableFwRule -SecurityPolicy (Get-NsxSecurityPolicy $polName)
            $services = $rule.applications.application
            # $services will only have a length if there is more than one entry.
            $services.Length | should be $null

            $services.name | should be ($SpNamePrefix + "nisvc11")
            $services.element.applicationProtocol | should be "TCP"
            $services.element.value | should be 21
        }

        It "Add a service group object to a firewall rule within a security policy" {
            # Dependent on prior two tests.
            $polName = ($SpNamePrefix + "hash2")
            $pol = Get-NsxSecurityPolicy $polName

            $svc1 = Get-NsxService ($SpNamePrefix + "nisvc11")
            $svc2 = Get-NsxService ($SpNamePrefix + "nisvc12")
            $svcgrp = New-NsxServiceGroup -Name ($SpNamePrefix + "nisvcgrp1")
            $svcgrp | Add-NsxServiceGroupMember $svc1,$svc2

            Add-NsxServiceToSPFwRule -SecurityPolicy $pol -Service $svcgrp -ExecutionOrder 1
            $rule = Get-NsxApplicableFwRule -SecurityPolicy (Get-NsxSecurityPolicy $polName)
            $servicegroups = $rule.applications.applicationGroup

            $servicegroups.name | should be ($SpNamePrefix + "nisvcgrp1")
        }

        It "Remove a service group object from a firewall rule within a security policy" {
            # Dependent on prior test.
            $polName = ($SpNamePrefix + "hash2")
            $pol = Get-NsxSecurityPolicy $polName

            $svcgrp = Get-NsxServiceGroup ($SpNamePrefix + "nisvcgrp1")

            Remove-NsxServiceFromSPFwRule -SecurityPolicy $pol -Service $svcgrp -ExecutionOrder 1
            $rule = Get-NsxApplicableFwRule -SecurityPolicy (Get-NsxSecurityPolicy $polName)
            $servicegroups = $rule.applications.applicationGroup
            # $services will only have a length if there is more than one entry.
            $servicegroups | should be $null
        }
    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver
    }
}
