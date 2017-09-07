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

    Context "Firewall Spec Definition" {

        AfterAll { 
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
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
    }

    Context "Security Policy Creation" {
        
        AfterAll { 
            Get-NsxSecurityGroup | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxSecurityPolicy | ? { $_.name -match $spNamePrefix } | Remove-NsxSecurityPolicy -Confirm:$false
            Get-NsxService | ? { $_.name -match $spNamePrefix } | Remove-NsxService -Confirm:$false
        }

        It "Can create a security policy with single firewall rule" { 
            $spec = New-NsxSecurityPolicyFirewallRuleSpec -Name ($SpNamePrefix + "spec") -Description "Pester Spec 1"
            $polName = ($SpNamePrefix + "policy1")
            $pol = New-NsxSecurityPolicy -Name $polName -Description "Pester Policy" -FirewallRuleSpec $spec
            $pol.Name | should be $polName
            $pol.Description | should be "Pester Policy"
            ($pol.actionsByCategory | ? { $_.category -eq 'firewall'}).action.name -contains $spec.Name | should be $true
        }

        It "Can create a security policy with multiple firewall rule" { 
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


    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver
    }
}
