#PowerNSX SecurityGroup Tests.
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

Describe "SecurityGroups" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for edge appliance deployment"
        $script:ds = $cl | get-datastore | Select-Object -first 1
        write-warning "Using datastore $ds for edge appliance deployment"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:sgPrefix = "pester_secgrp"

        #Clean up any existing SGs from previous runs...
        get-nsxsecuritygroup | Where-Object { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false

        #Set flag used in tests we have to tag out for 6.3.0 and above only...
        if ( [version]$DefaultNsxConnection.Version -ge [version]"6.3.0" )  {
            $ver_gt_630 = $true
        }
        else {
            $ver_gt_630 = $false
        }

        #Set flag used to determine if universal objects should be tested.
        $NsxManagerRole = Get-NsxManagerRole
        if ( ( $NsxManagerRole.role -eq "PRIMARY") -or ($NsxManagerRole.role -eq "SECONDARY") ) {
            $universalSyncEnabled = $true
        }
        else {
            $universalSyncEnabled = $false
        }

        # Set flag for greater the 6.3.0 AND universal sync enabled
        # Initial use case is for Universal Security Tags introduced in 6.3.0
        if ( ($ver_gt_630) -and ($universalSyncEnabled) ) {
            $script:ver_gt_630_universalSyncEnabled = $true
        }
        else {
            $script:ver_gt_630_universalSyncEnabled = $false
        }

        #LDAP Directory Groups - Check to see if this setup is integrated with LDAP
        $script:listDomainsUri = "/api/1.0/directory/listDomains"
        $script:domainsConfigured = Invoke-NsxRestMethod -method GET -URI $listDomainsUri
        if ($domainsConfigured.DirectoryDomains) {
            $script:directoryDomainConfigured = $True
        } else {
            $script:directoryDomainConfigured = $False
        }

        # Create test VM to test VM membership
        $script:testVMName1 = "pester_sg_vm1"
        if ( get-vm $testVMName1 -ErrorAction Ignore ) {
            remove-vm $testVMName1 -DeletePermanently -Confirm:$false
        }
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
    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxsecuritygroup | Where-Object { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false
        Get-vm | Where-Object { $_.name -eq $testVMName1 } | Remove-vm -DeletePermanently -Confirm:$false
        disconnect-nsxserver
    }

    Context "SecurityGroup retrieval" {
        BeforeAll {
            $script:secGrpName = "$sgPrefix-get"
            $SecGrpDesc = "PowerNSX Pester Test get SecurityGroup"
            $script:get = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc -IncludeMember $testvm1

        }

        it "Can retreive a SecurityGroup by name" {
            {Get-nsxsecuritygroup -Name $secGrpName} | should not throw
            $sg = Get-nsxsecuritygroup -Name $secGrpName
            $sg | should not be $null
            $sg.name | should be $secGrpName

         }

        it "Can retreive a SecurityGroup by id" {
            {Get-nsxsecuritygroup -objectId $get.objectId } | should not throw
            $sg = Get-nsxsecuritygroup -objectId $get.objectId
            $sg | should not be $null
            $sg.objectId | should be $get.objectId
         }

        it "Can retrieve only local SecurityGroups" {
            $secGrp = Get-nsxsecuritygroup -localonly
            ($secGrp | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
            ($secGrp | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should be 0
        }

        it "Can retrieve only local SecurityGroups via scopeid" {
            $secGrp = Get-nsxsecuritygroup -scopeid globalroot-0
            ($secGrp | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
            ($secGrp | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should be 0
        }

        It "Can retrieve securitygroups by virtual machine" {
            $sg = $testvm1 | Get-NsxSecurityGroup
            $sg | should not be $null
            ($sg | Measure-Object).count | should be 1
            $sg.name | should be $secGrpName
        }

    }

    Context "Successful SecurityGroup Creation" {

        AfterAll {
            get-nsxsecuritygroup | Where-Object { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false
        }

        it "Can create a SecurityGroup" {

            $secGrpName = "$sgPrefix-sg"
            $SecGrpDesc = "PowerNSX Pester Test SecurityGroup"
            $secGrp = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc
            $secGrp.Name | Should be $secGrpName
            $secGrp.Description | should be $SecGrpDesc
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

        }


        it "Can create a SecurityGroup and return an objectId only" {
            $secGrpName = "$sgPrefix-objonly-1234"
            $SecGrpDesc = "PowerNSX Pester Test objectidonly SecurityGroup"
            $id = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^securitygroup-\d*$"

        }

        It "Creates only a single securityGroup when used as the first part of a pipeline (#347)" {
            New-NsxSecurityGroup -Name "$sgPrefix-test-347"
            $sg = Get-NsxSecurityGroup "$sgPrefix-test-347" | ForEach-Object { New-NsxSecurityGroup -Name $_.name -Universal}
            ($sg | Measure-Object).count | should be 1
        }
    }

    Context "SecurityGroup Modification" {

        BeforeAll {

            #Member stuff definitions...
            #SGs
            $SecGrpMemberName1 = "$sgPrefix-member1"
            $SecGrpMemberDesc1 = "PowerNSX pester member SecurityGroup1"
            $SecGrpMemberName2 = "$sgPrefix-member2"
            $SecGrpMemberDesc2 = "PowerNSX Pester member SecurityGroup2"

            #VirtualWire
            $script:MemberLSName1 = "pester_member_ls1"
            $script:MemberLSName2 = "pester_member_ls2"

            #VMs
            $script:MemberVMName1 = "pester_member_vm1"
            $script:MemberVMName2 = "pester_member_vm2"
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

            #IPSet
            $script:testIPs = "1.1.1.1,2.2.2.2"
            $script:MemberIpSetName1 = "pester_member_ipset1"
            $script:MemberIpSetName2 = "pester_member_ipset2"
            $script:MemberIpSetDesc1 = "Pester member IP Set 1"
            $script:MemberIpSetDesc2 = "Pester member IP Set 2"

            #ResourcePool
            $Script:MemberResPoolName1 = "pester_member_respool1"
            $Script:MemberResPoolName2 = "pester_member_respool2"

            #DistributedVirtualPortgroup
            $script:MemberVdPortGroupName1 = "pester_member_vdportgroup1"
            $script:MemberVdPortGroupName2 = "pester_member_vdportgroup2"

            #Datacenter
            $script:MemberDcName1 = "pester_member_dc1"
            $script:MemberDcName2 = "pester_member_dc2"

            #Cluster
            $script:ParentDcName1 = "pester_parent_dc1"
            $script:MemberClusterName1 = "pester_member_cluster1"
            $script:MemberClusterName2 = "pester_member_cluster2"

            #SecurityTag
            $Script:MemberSTName1 = "pester_member_sectag1"
            $Script:MemberSTName2 = "pester_member_sectag2"
            $Script:MemberSTDesc1 = "Pester Member Security Tag 1"
            $Script:MemberSTDesc2 = "Pester Member Security Tag 2"

            #MACSet
            $script:MemberMacSetName1 = "pester_member_macset1"
            $script:MemberMacSetName2 = "pester_member_macset2"
            $script:MemberMac1 = "00:50:56:00:00:00"
            $script:MemberMac2 = "00:50:56:00:00:01"

            #DynamicCriteriaKeys
            $script:DynamicCriteriaKey1 = "VM.NAME"
            $script:DynamicCriteriaKey2 = "VM.GUEST_OS_FULL_NAME"
            $script:DynamicCriteriaKey3 = "VM.GUEST_HOST_NAME"
            $script:DynamicCriteriaKey4 = "VM.SECURITY_TAG"
            $script:DynamicCriteriaKey5 = "ENTITY"

            $script:DynamicCriteriaKeySubstitute = @{
                "VmName" = "VM.NAME";
                "OsName" = "VM.GUEST_OS_FULL_NAME";
                "ComputerName" = "VM.GUEST_HOST_NAME";
                "SecurityTag" = "VM.SECURITY_TAG"
            }

            #DynamicCriteriaOperators
            $script:DynamicCriteriaOperator1 = "AND"
            $script:DynamicCriteriaOperator2 = "OR"
            $script:DynamicCriteriaOperatorList = $DynamicCriteriaOperator1,$DynamicCriteriaOperator2

            #DynamicCriteriaCriteria
            $script:DynamicCriteriaCriteria1 = "contains"
            $script:DynamicCriteriaCriteria2 = "ends_with"
            $script:DynamicCriteriaCriteria3 = "starts_with"
            $script:DynamicCriteriaCriteria4 = "equals"
            $script:DynamicCriteriaCriteria5 = "notequals"
            $script:DynamicCriteriaCriteria6 = "regex"

            $script:DynamicCriteriaConditionSubstitute = @{
                "contains" = "contains";
                "ends_with" = "ends_with";
                "starts_with" = "starts_with";
                "equals" = "=";
                "notequals" = "!=";
                "regex" = "similar_to"
            }

            #DynamicCriteriaValue
            $script:DynamicCriteriaValue1 = "Test"

            #Removal of any previously created...
            Get-NsxMacSet $MemberMacSetName1 | Remove-NsxMacSet -confirm:$false
            Get-NsxMacSet $MemberMacSetName2 | Remove-NsxMacSet -confirm:$false

            Get-NsxSecurityTag $MemberSTName1 | Remove-NsxSecurityTag -Confirm:$false
            Get-NsxSecurityTag $MemberSTName2 | Remove-NsxSecurityTag -Confirm:$false

            Get-Datacenter $MemberDCName1 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false
            Get-Datacenter $MemberDCName2 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false

            Get-Cluster $MemberClusterName1 -ErrorAction SilentlyContinue | Remove-Cluster -Confirm:$false
            Get-Cluster $MemberClusterName2 -ErrorAction SilentlyContinue | Remove-Cluster -Confirm:$false
            Get-Datacenter $ParentDcName1 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false

            Get-VDPortgroup $MemberVdPortGroupName1 -ErrorAction SilentlyContinue | Remove-VDPortGroup -Confirm:$false
            Get-VDPortgroup $MemberVdPortGroupName2 -ErrorAction SilentlyContinue | Remove-VDPortGroup -Confirm:$false

            Get-ResourcePool $MemberResPoolName1 -ErrorAction SilentlyContinue | Remove-ResourcePool -Confirm:$false
            Get-ResourcePool $MemberResPoolName2 -ErrorAction SilentlyContinue | Remove-ResourcePool -Confirm:$false

            Get-NsxIpSet $MemberIPSetName1  | Remove-NsxIpSet -Confirm:$false
            Get-NsxIpSet $MemberIPSetName2  | Remove-NsxIpSet -Confirm:$false

            Get-Vm $MemberVmName1 -ErrorAction SilentlyContinue | Remove-VM -DeletePermanently -Confirm:$false
            Get-Vm $MemberVmName2 -ErrorAction SilentlyContinue | Remove-VM -DeletePermanently -Confirm:$false

            Get-NsxLogicalSwitch $MemberLSName1 | Remove-NsxLogicalSwitch -Confirm:$false
            Get-NsxLogicalSwitch $MemberLSName2 | Remove-NsxLogicalSwitch -Confirm:$false

            #Creation

            $script:MemberSG1 = New-NsxSecurityGroup -Name $SecGrpMemberName1 -Description $SecGrpMemberDesc1
            $script:MemberSG2 = New-NsxSecurityGroup -Name $SecGrpMemberName2 -Description $SecGrpMemberDesc2

            $script:MemberLS1 = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $MemberLSName1
            $script:MemberLS2 = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $MemberLSName2

            $script:MemberVM1 = new-vm -name $MemberVMName1 @vmsplat
            $script:MemberVM2 = new-vm -name $MemberVMName2 @vmsplat
            $MemberVM1 | Connect-NsxLogicalSwitch -LogicalSwitch $MemberLS1
            $MemberVM2 | Connect-NsxLogicalSwitch -LogicalSwitch $MemberLS2

            $script:MemberIpSet1 = New-NsxIpSet -Name $MemberIpSetName1 -Description $MemberIpSetDesc1 -IpAddress $testIPs
            $script:MemberIpSet2 = New-NsxIpSet -Name $MemberIpSetName2 -Description $MemberIpSetDesc2 -IpAddress $testIPs

            $script:MemberResPool1 = Get-cluster | Select-Object -First 1 | New-ResourcePool -Name $MemberResPoolName1
            $script:MemberResPool2 = Get-cluster | Select-Object -First 1 | New-ResourcePool -Name $MemberResPoolName2

            $script:MemberVdPortGroup1 = Get-VDSwitch | Select-Object -first 1 | New-VDPortgroup -Name $MemberVdPortGroupName1
            $script:MemberVdPortGroup2 = Get-VDSwitch | Select-Object -first 1 | New-VDPortgroup -Name $MemberVdPortGroupName2

            $script:MemberDC1 = get-folder Datacenters | New-Datacenter -Name $MemberDcName1
            $script:MemberDC2 = get-folder Datacenters | New-Datacenter -Name $MemberDcName2

            $script:ParentDC1 = get-folder Datacenters | New-Datacenter -Name $ParentDcName1
            $script:MemberCluster1 = New-Cluster -Name $MemberClusterName1 -Location $ParentDC1
            $script:MemberCluster2 = New-Cluster -Name $MemberClusterName2 -Location $ParentDC1

            $Script:MemberVnic1 = $MemberVM1 | Get-NetworkAdapter
            $Script:MemberVnic2 = $MemberVM2 | Get-NetworkAdapter

            $Script:MemberST1 = New-NsxSecurityTag -Name $MemberSTName1 -Description $MemberSTDesc1
            $Script:MemberST2 = New-NsxSecurityTag -Name $MemberSTName2 -Description $MemberSTDesc2

            $script:MemberMacSet1 = New-NsxMacSet -Name $MemberMacSetName1 -Description "Pester member MAC Set1" -MacAddresses "$MemberMac1,$MemberMac2"
            $script:MemberMacSet2 = New-NsxMacSet -Name $MemberMacSetName2 -Description "Pester member MAC Set2" -MacAddresses "$MemberMac1,$MemberMac2"

        }

        AfterAll {

            Get-NsxMacSet $MemberMacSetName1 | Remove-NsxMacSet -confirm:$false
            Get-NsxMacSet $MemberMacSetName2 | Remove-NsxMacSet -confirm:$false

            Get-NsxSecurityTag $MemberSTName1 | Remove-NsxSecurityTag -Confirm:$false
            Get-NsxSecurityTag $MemberSTName2 | Remove-NsxSecurityTag -Confirm:$false

            Get-Datacenter $MemberDCName1 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false
            Get-Datacenter $MemberDCName2 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false

            Get-Cluster $MemberClusterName1 -ErrorAction SilentlyContinue | Remove-Cluster -Confirm:$false
            Get-Cluster $MemberClusterName2 -ErrorAction SilentlyContinue | Remove-Cluster -Confirm:$false
            Get-Datacenter $ParentDcName1 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false

            Get-VDPortgroup $MemberVdPortGroupName1 -ErrorAction SilentlyContinue | Remove-VDPortGroup -Confirm:$false
            Get-VDPortgroup $MemberVdPortGroupName2 -ErrorAction SilentlyContinue | Remove-VDPortGroup -Confirm:$false

            Get-ResourcePool $MemberResPoolName1 -ErrorAction SilentlyContinue | Remove-ResourcePool -Confirm:$false
            Get-ResourcePool $MemberResPoolName2 -ErrorAction SilentlyContinue | Remove-ResourcePool -Confirm:$false

            Get-NsxIpSet $MemberIPSetName1  | Remove-NsxIpSet -Confirm:$false
            Get-NsxIpSet $MemberIPSetName2  | Remove-NsxIpSet -Confirm:$false

            Get-Vm $MemberVmName1 -ErrorAction SilentlyContinue | Remove-VM -DeletePermanently -Confirm:$false
            Get-Vm $MemberVmName2 -ErrorAction SilentlyContinue | Remove-VM -DeletePermanently -Confirm:$false

            Get-NsxLogicalSwitch $MemberLSName1 | Remove-NsxLogicalSwitch -Confirm:$false
            Get-NsxLogicalSwitch $MemberLSName2 | Remove-NsxLogicalSwitch -Confirm:$false

        }
        BeforeEach {
            $secGrpName = "$sgPrefix-mod"
            $SecGrpDesc = "PowerNSX Pester Test modify SecurityGroup"
            $script:SecGrp = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc
        }

        AfterEach {
            get-nsxsecuritygroup | Where-Object { $_.name -match "$sgPrefix-mod" } | remove-nsxsecuritygroup -confirm:$false
        }

        it "Can modify a SecurityGroup membership by object" {
            #Specify SG to be modified and member by object
            $SecGrp | Add-NsxSecurityGroupMember -Member $MemberSg1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            #Precludes multiple members, as they will be a collection
            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $SecGrpMemberName1
            $get.member.objectId | should be $MemberSG1.objectId

        }

         it "Can modify a SecurityGroup exclusion membership by object" {
            #Specify SG to be modified and member by object
            $SecGrp | Add-NsxSecurityGroupMember -Member $MemberSg1 -MemberIsExcluded
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            #Precludes multiple members, as they will be a collection
            $get.excludeMember | should beoftype System.xml.xmlelement
            $get.excludeMember.name | should be $SecGrpMemberName1
            $get.excludeMember.objectId | should be $MemberSG1.objectId
        }

        it "Can modify a SecurityGroup membership by id" {
            #Specify SG to be modified and member by id
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberSg1.objectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $SecGrpMemberName1
            $get.member.objectId | should be $MemberSG1.objectId

        }

        it "Can add multiple members by object" {
            $SecGrp | Add-NsxSecurityGroupMember -Member $MemberSg1, $MemberSg2
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member.count | should be 2
            $get.member.name -contains $SecGrpMemberName1 | should be $true
            $get.member.name -contains $SecGrpMemberName2 | should be $true
            $get.member.objectId -contains $MemberSG1.objectId | should be $true
            $get.member.objectId -contains $MemberSG2.objectId | should be $true

        }

        it "Can add multiple members by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberSg1.objectId, $MemberSg2.objectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member.count | should be 2
            $get.member.name -contains $SecGrpMemberName1 | should be $true
            $get.member.name -contains $SecGrpMemberName2 | should be $true
            $get.member.objectId -contains $MemberSG1.objectId | should be $true
            $get.member.objectId -contains $MemberSG2.objectId | should be $true
        }

        it "Can add a Logical Switch member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberLS1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberLSName1
            $get.member.objectId | should be $MemberLS1.objectId

        }

        it "Can add a Logical Switch member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberLS1.ObjectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberLSName1
            $get.member.objectId | should be $MemberLS1.objectId

        }

        it "Can add a VM member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberVM1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberVMName1
            $get.member.objectId | should be $MemberVM1.ExtensionData.MoRef.Value

        }

        it "Can add a VM member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberVM1.ExtensionData.MoRef.Value
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberVMName1
            $get.member.objectId | should be $MemberVM1.ExtensionData.MoRef.Value

        }

        it "Can add an IPSet member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberIpSet1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberIPSetName1
            $get.member.objectId | should be $MemberIpSet1.objectId

        }

        it "Can add an IPSet member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberIpSet1.objectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberIPSetName1
            $get.member.objectId | should be $MemberIpSet1.objectId

        }

        it "Can add a ResourcePool member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberResPool1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberResPoolName1
            $get.member.objectId | should be $MemberResPool1.ExtensionData.MoRef.Value

        }

        it "Can add an ResourcePool member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberResPool1.ExtensionData.MoRef.Value
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberResPoolName1
            $get.member.objectId | should be $MemberResPool1.ExtensionData.MoRef.Value

        }

        it "Can add a DVPortGRoup member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberVdPortGroup1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberVdPortGroupName1
            $get.member.objectId | should be $MemberVdPortGroup1.ExtensionData.MoRef.Value

        }

        it "Can add a DVPortGRoup member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberVdPortGroup1.ExtensionData.MoRef.Value
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberVdPortGroupName1
            $get.member.objectId | should be $MemberVdPortGroup1.ExtensionData.MoRef.Value

        }

        it "Can add a Datacenter member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberDc1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberDcName1
            $get.member.objectId | should be $MemberDc1.ExtensionData.MoRef.Value

        }

        it "Can add a Datacenter member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberDc1.ExtensionData.MoRef.Value
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberDcName1
            $get.member.objectId | should be $MemberDc1.ExtensionData.MoRef.Value

        }

        it "Can add a Cluster member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberCluster1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberClusterName1
            $get.member.objectId | should be $MemberCluster1.ExtensionData.MoRef.Value

        }

        it "Can add a Cluster member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberCluster1.ExtensionData.MoRef.Value
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberClusterName1
            $get.member.objectId | should be $MemberCluster1.ExtensionData.MoRef.Value

        }

        it "Can add a VNIC member by object" {
            $vmUuid = ($MemberVnic1.parent | get-view).config.instanceuuid
            $VnicId = "$vmUuid.$($MemberVnic1.id.substring($MemberVnic1.id.length-3))"

            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberVnic1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.objectId | should be $VnicId

        }

        it "Can add a VNIC member by id" {

            $vmUuid = ($MemberVnic1.parent | get-view).config.instanceuuid
            $VnicId = "$vmUuid.$($MemberVnic1.id.substring($MemberVnic1.id.length-3))"
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $VnicId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.objectId | should be $VnicId

        }

        it "Can add an SecurityTag member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberST1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberSTName1
            $get.member.objectId | should be $MemberST1.objectId

        }

        it "Can add a SecurityTag member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberST1.objectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberSTName1
            $get.member.objectId | should be $MemberST1.objectId

        }

        it "Can add a MACSet member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberMacSet1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberMacSetName1
            $get.member.objectId | should be $MemberMacSet1.objectId

        }

        it "Can add a MACSet member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberMacSet1.objectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberMacSetName1
            $get.member.objectId | should be $MemberMacSet1.objectId

        }

        it "Can add a Directory Group member by id" -skip:(-not $script:directoryDomainConfigured ) {
            $directoryGroup = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DirectoryGroup | Select-Object -First 1
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $directoryGroup.objectId
            $get = Get-nsxsecuritygroup -objectid $SecGrp.objectId
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $directoryGroup.name
            $get.member.objectId | should be $directoryGroup.objectId
        }

        it "Can add a Directory Group member by object" -skip:(-not $script:directoryDomainConfigured ) {
            $directoryGroup = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DirectoryGroup | Select-Object -First 1
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $directoryGroup
            $get = Get-nsxsecuritygroup -objectid $SecGrp.objectId
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $directoryGroup.name
            $get.member.objectId | should be $directoryGroup.objectId
        }

        foreach ( $key in $DynamicCriteriaKeySubstitute.keys ) {
            foreach ( $condition in $DynamicCriteriaConditionSubstitute.keys ) {
                it "Can create a new Dynamic Criteria Spec: $key/$condition" {
                    { New-NsxDynamicCriteriaSpec -key $key -condition $condition -value $DynamicCriteriaValue1 } | should not throw
                    $spec = New-NsxDynamicCriteriaSpec -key $key -condition $condition -value $DynamicCriteriaValue1
                    $spec | should not be $null
                    $spec.key | should be $DynamicCriteriaKeySubstitute[$key]
                    $spec.criteria | should be $DynamicCriteriaConditionSubstitute[$condition]
                    $spec.value | should be $DynamicCriteriaValue1
                }
            }
        }

        It "Can add a dynamic member set to an existing security group." {
            $val = "$sgprefix-dynamic1"
            $spec1 = New-NsxDynamicCriteriaSpec -key ComputerName -condition equals -value $val
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -DynamicCriteriaSpec $spec1
            $update = Get-NsxSecurityGroup $secGrpName
            $update.objectId | should be $secGrp.objectId
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 1
            ($update.dynamicMemberDefinition.dynamicSet.dynamicCriteria | Measure-Object).count | should be 1
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key | should be $DynamicCriteriaKeySubstitute["ComputerName"]
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria | should be $DynamicCriteriaConditionSubstitute["equals"]
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value | should be $val
        }

        It "Can add multiple dynamic criteria in a new Dynamic Member Set to an existing security group." {
            $val1 = "$sgprefix-dynamic1"
            $val2 = "$sgprefix-dynamic2"
            $spec1 = New-NsxDynamicCriteriaSpec -key ComputerName -condition equals -value $val1
            $spec2 = New-NsxDynamicCriteriaSpec -key OSName -condition ends_with -value $val2
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -DynamicCriteriaSpec $spec1,$spec2
            $update = Get-NsxSecurityGroup $secGrpName
            $update.objectId | should be $secGrp.objectId
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 1
            ($update.dynamicMemberDefinition.dynamicSet.dynamicCriteria | Measure-Object).count | should be 2
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key -contains $DynamicCriteriaKeySubstitute["ComputerName"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria -contains $DynamicCriteriaConditionSubstitute["equals"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value -contains $val1 | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key -contains $DynamicCriteriaKeySubstitute["OSName"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria -contains $DynamicCriteriaConditionSubstitute["ends_With"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value -contains $val2 | should be $true
        }

        It "Can add multiple dynamic member sets to an existing security group." {
            $val1 = "$sgprefix-dynamic1"
            $val2 = "$sgprefix-dynamic2"
            $spec1 = New-NsxDynamicCriteriaSpec -key ComputerName -condition equals -value $val1
            $spec2 = New-NsxDynamicCriteriaSpec -key OSName -condition ends_with -value $val2
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -DynamicCriteriaSpec $spec1
            $SecGrp = Get-NsxSecurityGroup $SecGrpName
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -SetOperator AND -DynamicCriteriaSpec $spec2
            $update = Get-NsxSecurityGroup $secGrpName
            $update.objectId | should be $secGrp.objectId
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 2
            ($update.dynamicMemberDefinition.dynamicSet[0].dynamicCriteria | Measure-Object).count | should be 1
            ($update.dynamicMemberDefinition.dynamicSet[1].dynamicCriteria | Measure-Object).count | should be 1
            $update.dynamicMemberDefinition.dynamicSet[0].dynamicCriteria.key | should be $DynamicCriteriaKeySubstitute["ComputerName"]
            $update.dynamicMemberDefinition.dynamicSet[0].dynamicCriteria.criteria | should be $DynamicCriteriaConditionSubstitute["equals"]
            $update.dynamicMemberDefinition.dynamicSet[0].dynamicCriteria.value | should be $val1
            $update.dynamicMemberDefinition.dynamicSet[1].dynamicCriteria.key | should be $DynamicCriteriaKeySubstitute["OSName"]
            $update.dynamicMemberDefinition.dynamicSet[1].dynamicCriteria.criteria | should be $DynamicCriteriaConditionSubstitute["ends_With"]
            $update.dynamicMemberDefinition.dynamicSet[1].dynamicCriteria.value | should be $val2
        }

        It "Can add a new dynamic criteria spec to an existing member set." {
            $val1 = "$sgprefix-dynamic1"
            $val2 = "$sgprefix-dynamic2"
            $spec1 = New-NsxDynamicCriteriaSpec -key ComputerName -condition equals -value $val1
            $spec2 = New-NsxDynamicCriteriaSpec -key OSName -condition ends_with -value $val2
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -DynamicCriteriaSpec $spec1
            Get-NsxSecurityGroup $SecGrpName | Get-NsxDynamicMemberSet -index 1 | Add-NsxDynamicCriteria -DynamicCriteriaSpec $spec2
            $update = Get-NsxSecurityGroup $secGrpName
            $update.objectId | should be $secGrp.objectId
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 1
            ($update.dynamicMemberDefinition.dynamicSet.dynamicCriteria | Measure-Object).count | should be 2
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key -contains $DynamicCriteriaKeySubstitute["ComputerName"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria -contains $DynamicCriteriaConditionSubstitute["equals"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value -contains $val1 | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key -contains $DynamicCriteriaKeySubstitute["OSName"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria -contains $DynamicCriteriaConditionSubstitute["ends_With"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value -contains $val2 | should be $true
        }

        It "Can add a new dynamic criteria to an existing member set by key/condition/val." {
            $val1 = "$sgprefix-dynamic1"
            $val2 = "$sgprefix-dynamic2"
            $spec1 = New-NsxDynamicCriteriaSpec -key ComputerName -condition equals -value $val1
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -DynamicCriteriaSpec $spec1
            Get-NsxSecurityGroup $SecGrpName | Get-NsxDynamicMemberSet -index 1 | Add-NsxDynamicCriteria -key OSName -condition ends_with -value $val2
            $update = Get-NsxSecurityGroup $secGrpName
            $update.objectId | should be $secGrp.objectId
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 1
            ($update.dynamicMemberDefinition.dynamicSet.dynamicCriteria | Measure-Object).count | should be 2
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key -contains $DynamicCriteriaKeySubstitute["ComputerName"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria -contains $DynamicCriteriaConditionSubstitute["equals"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value -contains $val1 | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key -contains $DynamicCriteriaKeySubstitute["OSName"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria -contains $DynamicCriteriaConditionSubstitute["ends_With"] | should be $true
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value -contains $val2 | should be $true
        }

        It "Can remove an existing dynamic criteria from a dynamic member set." {
            $val1 = "$sgprefix-dynamic1"
            $val2 = "$sgprefix-dynamic2"
            $spec1 = New-NsxDynamicCriteriaSpec -key ComputerName -condition equals -value $val1
            $spec2 = New-NsxDynamicCriteriaSpec -key OSName -condition ends_with -value $val2
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -DynamicCriteriaSpec $spec1,$spec2
            $secGrp = Get-NsxSecurityGroup $secGrpName
            $MemberSetToRemove = Get-NsxSecurityGroup $SecGrpName | Get-NsxDynamicMemberSet -index 1 | Get-NsxDynamicCriteria | Where-Object { (($_.key -eq 'ComputerName') -AND
            ($_.condition -eq 'equals') -AND ($_.value -eq $val1)) }
            $secGrp | Get-NsxDynamicMemberSet -index 1 | Get-NsxDynamicCriteria -index $MemberSetToRemove.index | Remove-NsxDynamicCriteria -Noconfirm
            $update = Get-NsxSecurityGroup $secGrpName
            $update.objectId | should be $secGrp.objectId
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 1
            ($update.dynamicMemberDefinition.dynamicSet.dynamicCriteria | Measure-Object).count | should be 1
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key | should be $DynamicCriteriaKeySubstitute["OSName"]
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria | should be $DynamicCriteriaConditionSubstitute["ends_With"]
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value | should be $val2
        }

        It "Can remove an existing dynamic member set from an existing security group." {
            $val1 = "$sgprefix-dynamic1"
            $val2 = "$sgprefix-dynamic2"
            $spec1 = New-NsxDynamicCriteriaSpec -key ComputerName -condition equals -value $val1
            $spec2 = New-NsxDynamicCriteriaSpec -key OSName -condition ends_with -value $val2
            $secGrp | Add-NsxDynamicMemberSet -CriteriaOperator ANY -DynamicCriteriaSpec $spec1
            Get-NsxSecurityGroup $SecGrpName | Add-NsxDynamicMemberSet -CriteriaOperator ANY -SetOperator AND -DynamicCriteriaSpec $spec2
            $update = Get-NsxSecurityGroup $secGrpName
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 2
            Get-NsxSecurityGroup $SecGrpName | Get-NsxDynamicMemberSet -index 1 | Remove-NsxDynamicMemberSet -Noconfirm
            $update = Get-NsxSecurityGroup $secGrpName
            $update.objectId | should be $secGrp.objectId
            ($update.dynamicMemberDefinition.dynamicSet | Measure-Object).count | should be 1
            ($update.dynamicMemberDefinition.dynamicSet.dynamicCriteria | Measure-Object).count | should be 1
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.key | should be $DynamicCriteriaKeySubstitute["OSName"]
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.criteria | should be $DynamicCriteriaConditionSubstitute["ends_With"]
            $update.dynamicMemberDefinition.dynamicSet.dynamicCriteria.value | should be $val2
        }
    }

    Context "SecurityGroup Deletion" {

        BeforeEach {
            $secGrpName = "$sgPrefix-delete"
            $SecGrpDesc = "PowerNSX Pester Test delete SecurityGroup"
            $script:delete = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc
        }

        it "Can delete a SecurityGroup by object" {

            $delete | Remove-nsxsecuritygroup -confirm:$false
            {Get-nsxsecuritygroup -objectId $delete.objectId} | should throw
        }

    }

    Context "Universal SecurityGroup Retrieval" {

        BeforeAll {
            New-NsxSecurityGroup -Name $sgPrefix-local-retrieval
            if ( $universalSyncEnabled ) {
                New-NsxSecurityGroup -Name $sgPrefix-universal-retrieval -universal
            }
        }

        AfterAll {
            get-nsxsecuritygroup | Where-Object { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false
        }

        it "Can retrieve both local and universal SecurityGroups" -skip:(-not $universalSyncEnabled ) {
            $secGrp = Get-nsxsecuritygroup
            ($secGrp | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($secGrp | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
        }

        it "Can retrieve only universal SecurityGroups" -skip:(-not $universalSyncEnabled ) {
            $secGrp = Get-nsxsecuritygroup -universalOnly
            ($secGrp | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($secGrp | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
        }

        it "Can retrieve only universal SecurityGroups via scopeid" -skip:(-not $universalSyncEnabled ) {
            $secGrp = Get-nsxsecuritygroup -scopeid universalroot-0
            ($secGrp | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($secGrp | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
        }

    }

    Context "Universal SecurityGroups" {

        BeforeAll {
            if ( $ver_gt_630 ) {
                $script:UST = New-NsxSecurityTag -Universal -Name $sgPrefix-sectag-universal -Description "PowerNSX Pester Test Universal SecurityTag"
            }
        }

        AfterAll {
            get-nsxsecuritygroup | Where-Object { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false
            get-nsxsecuritytag | Where-Object { $_.name -match $sgPrefix } | Remove-NsxSecurityTag -Confirm:$false
        }


        it "Can create a universal SecurityGroup" {
            $secGrpName = "$sgPrefix-sg-universal"
            $SecGrpDesc = "PowerNSX Pester Test Universal SecurityGroup"
            $secGrp = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc -Universal
            $secGrp.Name | Should be $secGrpName
            $secGrp.Description | should be $SecGrpDesc
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description
        }

        #6.3.0 and above only...
        it "Can create a universal SecurityGroup with static universal Security Tag membership (Active-Standby deployment flag)" -skip:(-not $ver_gt_630 ) {
            $secGrpName = "$sgPrefix-sg-universal-active_standby"
            $SecGrpDesc = "PowerNSX Pester Test Universal SecurityGroup with Active-Standby flag"
            $secGrp = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc -Universal -ActiveStandbyDeployment -IncludeMember $UST
            $secGrp.Name | Should be $secGrpName
            $secGrp.Description | should be $SecGrpDesc
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description
            $localMembersOnly = $get.extendedAttributes.extendedAttribute | Where-Object { $_.name -eq "localMembersOnly" }
            $localMembersOnly.value | should be "true"
            $get.member.name | should be $UST.name
        }

        #6.3.0 and above only
        it "Fails to create a universal SecurityGroup with static universal Security Tag membership when Active-Standby deployment flag is not enabled"  -skip:(-not $ver_gt_630 ) {
            $secGrpName = "$sgPrefix-sg-universal-no-active_standby"
            $SecGrpDesc = "PowerNSX Pester Test Universal SecurityGroup without Active-Standby flag"
            {New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc -Universal -IncludeMember $UST} | should throw
        }
    }

    Context "Applicable Members" {

        BeforeAll {

            #Appliceable Member stuff definitions...
            #SGs
            $SecGrpMemberName1 = "$sgPrefix-member1"
            $USecGrpMemberName1 = "$sgPrefix-member1-universal"

            #VirtualWire
            $script:MemberLSName1 = "pester_member_ls1"

            #VMs
            $script:MemberVMName1 = "pester_member_vm1"
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

            #IPSet
            $script:testIPs = "1.1.1.1,2.2.2.2"
            $script:MemberIpSetName1 = "pester_member_ipset1"
            $script:UMemberIpSetName1 = "pester_member_ipset1_universal"
            $script:MemberIpSetDesc1 = "Pester member IP Set 1"

            #ResourcePool
            $Script:MemberResPoolName1 = "pester_member_respool1"

            #DistributedVirtualPortgroup
            $script:MemberVdPortGroupName1 = "pester_member_vdportgroup1"

            #Datacenter
            $script:MemberDcName1 = "pester_member_dc1"

            #SecurityTag
            $Script:MemberSTName1 = "pester_member_sectag1"
            $Script:UMemberSTName1 = "pester_member_sectag1"
            $Script:MemberSTDesc1 = "Pester Member Security Tag 1"

            #MACSet
            $script:MemberMacSetName1 = "pester_member_macset1"
            $script:UMemberMacSetName1 = "pester_member_macset1_universal"
            $script:MemberMac1 = "00:50:56:00:00:00"


            #Removal of any previously created...
            Get-Vm $MemberVmName1 -ErrorAction SilentlyContinue | Remove-VM -DeletePermanently -Confirm:$false

            Get-NsxMacSet $MemberMacSetName1 | Remove-NsxMacSet -confirm:$false
            Get-NsxMacSet $UMemberMacSetName1 | Remove-NsxMacSet -confirm:$false

            Get-NsxSecurityTag $MemberSTName1 | Remove-NsxSecurityTag -Confirm:$false
            Get-NsxSecurityTag $UMemberSTName1 | Remove-NsxSecurityTag -Confirm:$false

            Get-Datacenter $MemberDCName1 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false

            Get-VDPortgroup $MemberVdPortGroupName1 -ErrorAction SilentlyContinue | Remove-VDPortGroup -Confirm:$false

            Get-ResourcePool $MemberResPoolName1 -ErrorAction SilentlyContinue | Remove-ResourcePool -Confirm:$false

            Get-NsxIpSet $MemberIPSetName1  | Remove-NsxIpSet -Confirm:$false
            Get-NsxIpSet $UMemberIPSetName1  | Remove-NsxIpSet -Confirm:$false

            Get-NsxLogicalSwitch $MemberLSName1 | Remove-NsxLogicalSwitch -Confirm:$false

            Get-NsxSecurityGroup $SecGrpMemberName1 | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxSecurityGroup $USecGrpMemberName1 | Remove-NsxSecurityGroup -Confirm:$false

            #Creation

            $script:MemberSG1 = New-NsxSecurityGroup -Name $SecGrpMemberName1 -Description $SecGrpMemberDesc1
            $script:UMemberSG1 = New-NsxSecurityGroup -Name $USecGrpMemberName1 -Description $SecGrpMemberDesc1 -universal

            $script:MemberLS1 = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $MemberLSName1

            $script:MemberVM1 = new-vm -name $MemberVMName1 @vmsplat
            $MemberVM1 | Connect-NsxLogicalSwitch -LogicalSwitch $MemberLS1

            $script:MemberIpSet1 = New-NsxIpSet -Name $MemberIpSetName1 -Description $MemberIpSetDesc1 -IpAddress $testIPs
            $script:UMemberIpSet1 = New-NsxIpSet -Name $UMemberIpSetName1 -Description $MemberIpSetDesc1 -IpAddress $testIPs -Universal

            $script:MemberResPool1 = Get-cluster | Select-Object -First 1 | New-ResourcePool -Name $MemberResPoolName1

            $script:MemberVdPortGroup1 = Get-VDSwitch | Select-Object -first 1 | New-VDPortgroup -Name $MemberVdPortGroupName1

            $script:MemberDC1 = get-folder Datacenters | New-Datacenter -Name $MemberDcName1

            $Script:MemberVnic1 = $MemberVM1 | Get-NetworkAdapter

            $Script:MemberST1 = New-NsxSecurityTag -Name $MemberSTName1 -Description $MemberSTDesc1

            $script:MemberMacSet1 = New-NsxMacSet -Name $MemberMacSetName1 -Description "Pester member MAC Set1" -MacAddresses "$MemberMac1"
            $script:UMemberMacSet1 = New-NsxMacSet -Name $UMemberMacSetName1 -Description "Pester member MAC Set1 Universal" -MacAddresses "$MemberMac1" -Universal

            if ( $ver_gt_630 ) {
                # $script:UST = New-NsxSecurityTag -Universal -Name $sgPrefix-sectag-universal -Description "PowerNSX Pester Test Universal SecurityTag"
                $Script:UMemberST1 = New-NsxSecurityTag -Name $UMemberSTName1 -Description $MemberSTDesc1 -universal
            }

        }

        AfterAll {
            #Removal of any previously created...
            Get-Vm $MemberVmName1 -ErrorAction SilentlyContinue | Remove-VM -DeletePermanently -Confirm:$false

            Get-NsxMacSet $MemberMacSetName1 | Remove-NsxMacSet -confirm:$false
            Get-NsxMacSet $UMemberMacSetName1 | Remove-NsxMacSet -confirm:$false

            Get-NsxSecurityTag $MemberSTName1 | Remove-NsxSecurityTag -Confirm:$false
            Get-NsxSecurityTag $UMemberSTName1 | Remove-NsxSecurityTag -Confirm:$false

            Get-Datacenter $MemberDCName1 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false

            Get-VDPortgroup $MemberVdPortGroupName1 -ErrorAction SilentlyContinue | Remove-VDPortGroup -Confirm:$false

            Get-ResourcePool $MemberResPoolName1 -ErrorAction SilentlyContinue | Remove-ResourcePool -Confirm:$false

            Get-NsxIpSet $MemberIPSetName1  | Remove-NsxIpSet -Confirm:$false
            Get-NsxIpSet $UMemberIPSetName1  | Remove-NsxIpSet -Confirm:$false

            Get-NsxLogicalSwitch $MemberLSName1 | Remove-NsxLogicalSwitch -Confirm:$false

            Get-NsxSecurityGroup $SecGrpMemberName1 | Remove-NsxSecurityGroup -Confirm:$false
            Get-NsxSecurityGroup $USecGrpMemberName1 | Remove-NsxSecurityGroup -Confirm:$false
        }

        it "Can retrieve local Security Group IPSet applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberIpSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "IPSet"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group IPSet applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberIpSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "IPSet"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group ClusterComputeResource applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ClusterComputeResource } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ClusterComputeResource
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $cl.name}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ClusterComputeResource"
        }

        it "Can retrieve local Security Group ClusterComputeResource applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ClusterComputeResource -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ClusterComputeResource -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $cl.name}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ClusterComputeResource"
        }

        it "Can retrieve local Security Group VirtualWire applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualWire } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualWire
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberLSName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "VirtualWire"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group VirtualWire applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualWire -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualWire -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberLSName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "VirtualWire"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group VirtualMachine applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualMachine } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualMachine
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberVMName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "VirtualMachine"
        }

        it "Can retrieve local Security Group VirtualMachine applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualMachine -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualMachine -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberVMName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "VirtualMachine"
        }

        it "Can retrieve local Security Group DirectoryGroup applicable members" -skip:(-not $script:directoryDomainConfigured ) {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DirectoryGroup } | should not throw
            # The test environments will be connected to a Microsoft Active Directory, which should populate all the default Active Directory Groups
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DirectoryGroup
            $results | should not be $null
        }

        it "Can retrieve local Security Group DirectoryGroup applicable members specifying scopeid globalroot-0" -skip:(-not $script:directoryDomainConfigured ) {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DirectoryGroup -scopeId GlobalRoot-0 } | should not throw
            # The test environments will be connected to a Microsoft Active Directory, which should populate all the default Active Directory Groups
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DirectoryGroup -scopeId GlobalRoot-0
            $results | should not be $null
        }

        it "Can retrieve local Security Group SecurityGroup applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $SecGrpMemberName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityGroup"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group SecurityGroup applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $SecGrpMemberName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityGroup"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group VirtualApp applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualApp } | should not throw
        }

        it "Can retrieve local Security Group VirtualApp applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType VirtualApp -scopeId GlobalRoot-0 } | should not throw
        }

        it "Can retrieve local Security Group ResourcePool applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ResourcePool } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ResourcePool
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberResPool1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ResourcePool"
        }

        it "Can retrieve local Security Group ResourcePool applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ResourcePool -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType ResourcePool -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberResPool1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ResourcePool"
        }

        it "Can retrieve local Security Group DistributedVirtualPortgroup applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DistributedVirtualPortgroup } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DistributedVirtualPortgroup
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberVdPortGroup1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "DistributedVirtualPortgroup"
        }

        it "Can retrieve local Security Group DistributedVirtualPortgroup applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DistributedVirtualPortgroup -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType DistributedVirtualPortgroup -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberVdPortGroup1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "DistributedVirtualPortgroup"
        }

        it "Can retrieve local Security Group Datacenter applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Datacenter } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Datacenter
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberDC1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Datacenter"
        }

        it "Can retrieve local Security Group Datacenter applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Datacenter -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Datacenter -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberDC1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Datacenter"
        }

        it "Can retrieve local Security Group Network applicable members" {
        }

        it "Can retrieve local Security Group Network applicable members specifying scopeid globalroot-0" {
        }

        it "Can retrieve local Security Group Vnic applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Vnic } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Vnic
            $results | should not be $null
            $item = $results | Select-Object -first 1
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Vnic"
        }

        it "Can retrieve local Security Group Vnic applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Vnic -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType Vnic -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Select-Object -first 1
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Vnic"
        }

        it "Can retrieve local Security Group SecurityTag applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberSTName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityTag"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group SecurityTag applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberSTName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityTag"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group MACSet applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberMacSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "MACSet"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Security Group MACSet applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $MemberMacSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "MACSet"
            $item.isUniversal | should be "false"
        }

        #Universal Security Group Applicable Members

        it "Can retrieve universal Security Group IPSet applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet -universal } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet -universal
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UMemberIpSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "IPSet"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Security Group IPSet applicable members specifying scopeid universalRoot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet -scopeId universalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType IPSet -scopeId universalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UMemberIpSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "IPSet"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Security Group SecurityTag applicable members" -skip:(-not $ver_gt_630_universalSyncEnabled ) {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag  -universal} | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag -universal
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UMemberSTName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityTag"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Security Group SecurityTag applicable members specifying scopeid universalRoot-0" -skip:(-not $ver_gt_630_universalSyncEnabled ){
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag -scopeId universalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityTag -scopeId universalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UMemberSTName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityTag"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Security Group MACSet applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet  -universal} | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet -universal
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UMemberMacSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "MACSet"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Security Group MACSet applicable members specifying scopeid universalRoot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet -scopeId universalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType MACSet -scopeId universalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UMemberMacSetName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "MACSet"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Security Group SecurityGroup applicable members" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup  -universal} | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup -universal
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $USecGrpMemberName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityGroup"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Security Group SecurityGroup applicable members specifying scopeid universalRoot-0" {
            { Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup -scopeId universalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -SecurityGroupApplicableMembers -MemberType SecurityGroup -scopeId universalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $USecGrpMemberName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "SecurityGroup"
            $item.isUniversal | should be "true"
        }


        #ScopeId of an Edge
        it "Can retrieve local Security Group IPSet applicable members specifying scopeid of an edge" {
        }

        it "Can retrieve local Security Group MACSet applicable members specifying scopeid of an edge" {
        }

        it "Can retrieve local Security Group SecurityGroup applicable members specifying scopeid of an edge" {
        }
    }

    Context "Security Tag Assignments" {
        BeforeAll {
            $testTemplateName = "Pester_sg_template_1"
            $script:testtemplate1 = New-Template -VM $testvm1 -Name $testTemplateName -Datastore $ds -Location $folder
        }

        AfterAll {
            Get-Template | Where-Object {$_.name -match "^pester"} | Remove-Template -confirm:$false
        }

        BeforeEach {
            $testTagName = "pester_tag_1"
            $script:testTag = New-NsxSecurityTag -Name $testTagName
        }

        AfterEach {
            Get-NsxSecurityTag | Where-Object {$_.name -match "^pester"} | Remove-NsxSecurityTag -confirm:$false
        }

        it "Can get security tag assignment from a Security Tag" {
            Get-VM $testVMName1 | New-NsxSecurityTagAssignment -ApplyTag $testTag
            $assignment = $testTag | Get-NsxSecurityTagAssignment
            $assignment | should not be $null
            ($assignment | Measure-Object).count | should be 1
            $assignment.VirtualMachine.name | should be $testVMName1
        }

        it "Can get security tag assignment from a Virtual Machine" {
            Get-VM $testVMName1 | New-NsxSecurityTagAssignment -ApplyTag $testTag
            $assignment = Get-VM $testVMName1 | Get-NsxSecurityTagAssignment
            $assignment | should not be $null
            ($assignment | Measure-Object).count | should be 1
            $assignment.VirtualMachine.name | should be $testVMName1
        }
        it "Can get security tag assignment from a Template" {
            # Now PowerNSX doesn't allow you to actually apply a security tag to
            # a virtual machine template. But if a virtual machine was converted
            # to a template and it had a tag already applied to it, then it may
            # be returned when looking up tag assignments.

            # Lets apply a tag manually to a template
            $URI = "/api/2.0/services/securitytags/tag/$($testTag.objectid)/vm/$($testtemplate1.ExtensionData.MoRef.value)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -connection $connection
            $response.StatusCode | should be 200

            $assignment = Get-Template $testtemplate1 | Get-NsxSecurityTagAssignment
            $assignment | should not be $null
            ($assignment | Measure-Object).count | should be 1
            $assignment.VirtualMachine.name | should be $testTemplateName
        }
    }
}