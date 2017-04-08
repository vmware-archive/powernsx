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
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred
        $script:cl = get-cluster | select -first 1
        write-warning "Using cluster $cl for edge appliance deployment"
        $script:ds = $cl | get-datastore | select -first 1
        write-warning "Using datastore $ds for edge appliance deployment"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:sgPrefix = "pester_secgrp"

        #Clean up any existing SGs from previous runs...
        get-nsxsecuritygroup | ? { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false


    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxsecuritygroup | ? { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false

        disconnect-nsxserver
    }

    Context "SecurityGroup retrieval" {
        BeforeAll {
            $script:secGrpName = "$sgPrefix-get"
            $SecGrpDesc = "PowerNSX Pester Test get SecurityGroup"
            $script:get = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc

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


    }

    Context "Successful SecurityGroup Creation" {

        AfterAll {
            get-nsxsecuritygroup | ? { $_.name -match $sgPrefix } | remove-nsxsecuritygroup -confirm:$false
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


            #Removal of any previously created...
            Get-NsxMacSet $MemberMacSetName1 | Remove-NsxMacSet -confirm:$false
            Get-NsxMacSet $MemberMacSetName2 | Remove-NsxMacSet -confirm:$false

            Get-NsxSecurityTag $MemberSTName1 | Remove-NsxSecurityTag -Confirm:$false
            Get-NsxSecurityTag $MemberSTName2 | Remove-NsxSecurityTag -Confirm:$false

            Get-Datacenter $MemberDCName1 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false
            Get-Datacenter $MemberDCName2 -ErrorAction SilentlyContinue | Remove-Datacenter -Confirm:$false

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

            $script:MemberLS1 = Get-NsxTransportZone -LocalOnly | select -first 1 | New-NsxLogicalSwitch $MemberLSName1
            $script:MemberLS2 = Get-NsxTransportZone -LocalOnly | select -first 1 | New-NsxLogicalSwitch $MemberLSName2

            $script:MemberVM1 = new-vm -name $MemberVMName1 @vmsplat
            $script:MemberVM2 = new-vm -name $MemberVMName2 @vmsplat
            $MemberVM1 | Connect-NsxLogicalSwitch -LogicalSwitch $MemberLS1
            $MemberVM2 | Connect-NsxLogicalSwitch -LogicalSwitch $MemberLS2

            $script:MemberIpSet1 = New-NsxIpSet -Name $MemberIpSetName1 -Description $MemberIpSetDesc1 -IpAddresses $testIPs
            $script:MemberIpSet2 = New-NsxIpSet -Name $MemberIpSetName2 -Description $MemberIpSetDesc2 -IpAddresses $testIPs

            $script:MemberResPool1 = Get-cluster | select -First 1 | New-ResourcePool -Name $MemberResPoolName1
            $script:MemberResPool2 = Get-cluster | select -First 1 | New-ResourcePool -Name $MemberResPoolName2

            $script:MemberVdPortGroup1 = Get-VDSwitch | Select -first 1 | New-VDPortgroup -Name $MemberVdPortGroupName1
            $script:MemberVdPortGroup2 = Get-VDSwitch | Select -first 1 | New-VDPortgroup -Name $MemberVdPortGroupName2

            $script:MemberDC1 = get-folder Datacenters | New-Datacenter -Name $MemberDcName1
            $script:MemberDC2 = get-folder Datacenters | New-Datacenter -Name $MemberDcName2

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
            get-nsxsecuritygroup | ? { $_.name -match "$sgPrefix-mod" } | remove-nsxsecuritygroup -confirm:$false
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

        it "Can add an ResourcePool member by object" {
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

        it "Can add an DVPortGRoup member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberVdPortGroup1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberVdPortGroupName1
            $get.member.objectId | should be $MemberVdPortGroup1.ExtensionData.MoRef.Value

        }

        it "Can add an DVPortGRoup member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberVdPortGroup1.ExtensionData.MoRef.Value
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberVdPortGroupName1
            $get.member.objectId | should be $MemberVdPortGroup1.ExtensionData.MoRef.Value

        }

        it "Can add an Datacenter member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberDc1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberDcName1
            $get.member.objectId | should be $MemberDc1.ExtensionData.MoRef.Value

        }

        it "Can add an Datacenter member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberDc1.ExtensionData.MoRef.Value
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberDcName1
            $get.member.objectId | should be $MemberDc1.ExtensionData.MoRef.Value

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

        it "Can add an SecurityTag member by id" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberST1.objectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberSTName1
            $get.member.objectId | should be $MemberST1.objectId

        }

        it "Can add an MACSet member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberMacSet1
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberMacSetName1
            $get.member.objectId | should be $MemberMacSet1.objectId

        }

        it "Can add an MACSet member by object" {
            Add-NsxSecurityGroupMember -SecurityGroup $SecGrp.objectId -Member $MemberMacSet1.objectId
            $get = Get-nsxsecuritygroup -Name $secGrpName
            $get.name | should be $secGrp.name
            $get.description | should be $secGrp.description

            $get.member | should beoftype System.xml.xmlelement
            $get.member.name | should be $MemberMacSetName1
            $get.member.objectId | should be $MemberMacSet1.objectId

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
}