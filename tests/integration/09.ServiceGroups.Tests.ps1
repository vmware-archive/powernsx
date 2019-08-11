#PowerNSX ServiceGroup Tests.
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

Describe "ServiceGroups" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:svcPrefix = "pester_svcgrp_"

        #Clean up any existing services from previous runs...
        get-nsxservicegroup | Where-Object { $_.name -match $svcPrefix } | remove-nsxservicegroup -confirm:$false
        get-nsxservicegroup -scopeid universalroot-0 | Where-Object { $_.name -match $svcPrefix } | remove-nsxservicegroup -confirm:$false

        #Set flag used to determine if universal objects should be tested.
        $NsxManagerRole = Get-NsxManagerRole
        if ( ( $NsxManagerRole.role -eq "PRIMARY") -or ($NsxManagerRole.role -eq "SECONDARY") ) {
            $universalSyncEnabled = $true
        }
        else {
            $universalSyncEnabled = $false
        }

    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxservicegroup | Where-Object { $_.name -match $svcPrefix } | remove-nsxservicegroup -confirm:$false
        get-nsxservicegroup -scopeid universalroot-0 | Where-Object { $_.name -match $svcPrefix } | remove-nsxservicegroup -confirm:$false

        disconnect-nsxserver
    }

    Context "Local ServiceGroup retrieval" {
        BeforeAll {
            $script:svcGrpName = "$svcPrefix-get"
            $svcGrpDesc = "PowerNSX Pester Test get serviceGroup"
            $script:getLocal = New-NsxServiceGroup -Name $svcGrpName -Description $svcGrpDesc

        }

         It "Can retrieve all local ServiceGroups" {
            {Get-NsxServiceGroup -localonly} | should not throw
            $sg = Get-NsxServiceGroup -localonly
            $sg | should not be $null
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

         It "Can retrieve both local and universal ServiceGroup" {
            {Get-NsxServiceGroup} | should not throw
            $sg = Get-NsxServiceGroup
            $sg | should not be $null
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

        it "Can retreive a group by name" {
            {Get-NsxServiceGroup -Name $svcGrpName} | should not throw
            $sg = Get-NsxServiceGroup -Name $svcGrpName
            $sg | should not be $null
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
            $sg.name | should be $svcGrpName
         }

        it "Can retreive a local service group by name with scopeid" {
            {Get-NsxServiceGroup -Name $svcGrpName -scopeid globalroot-0} | should not throw
            $sg = Get-NsxServiceGroup -Name $svcGrpName -scopeid globalroot-0
            $sg | should not be $null
            $sg.name | should be $svcGrpName
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 1
         }

        it "Can retreive a local service group by id" {
            {Get-NsxServiceGroup -objectId $getLocal.objectId } | should not throw
            $sg = Get-NsxServiceGroup -objectId $getLocal.objectId
            $sg | should not be $null
            $sg.objectId | should be $getLocal.objectId
         }


    }

    Context "Universal ServiceGroup retrieval" {
        BeforeAll {
            $script:svcGrpName = "$svcPrefix-universal-get"
            $svcGrpDesc = "PowerNSX Pester Test get universal serviceGroup"
            $script:getLocal = New-NsxServiceGroup -Name $svcGrpName -Description $svcGrpDesc
            if ( $universalSyncEnabled ) {
                $script:getUniversal = New-NsxServiceGroup -Name $svcGrpName -Description $svcGrpDesc -universal
            }
        }

         It "Can retrieve all universal ServiceGroups" -skip:(-not $universalSyncEnabled ) {
            {Get-NsxServiceGroup -universalonly} | should not throw
            $sg = Get-NsxServiceGroup -universalonly
            $sg | should not be $null
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
            ($sg | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
         }

         It "Can retrieve both local and universal ServiceGroup" -skip:(-not $universalSyncEnabled ) {
            {Get-NsxServiceGroup} | should not throw
            $sg = Get-NsxServiceGroup
            $sg | should not be $null
            ($sg | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

        it "Can retreive all service groups by name" -skip:(-not $universalSyncEnabled ) {
            {Get-NsxServiceGroup -Name $svcGrpName} | should not throw
            $sg = Get-NsxServiceGroup -Name $svcGrpName
            $sg | should not be $null
            ($sg | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

        it "Can retreive a universal service group by name with scopeid" -skip:(-not $universalSyncEnabled ) {
            {Get-NsxServiceGroup -scopeid universalroot-0 -Name $svcGrpName} | should not throw
            $sg = Get-NsxServiceGroup -scopeid universalroot-0 -Name $svcGrpName
            $sg | should not be $null
            $sg.name | should be $svcGrpName
            ($sg | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
            ($sg | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should be 1
         }

        it "Can retreive a universal service group by id" -skip:(-not $universalSyncEnabled ) {
            {Get-NsxServiceGroup -objectId $getUniversal.objectId } | should not throw
            $sg = Get-NsxServiceGroup -objectId $getUniversal.objectId
            $sg | should not be $null
            $sg.objectId | should be $getUniversal.objectId
         }


    }

    Context "Successful Local Service Group Creation" {

        AfterAll {
            get-nsxserviceGroup | Where-Object { $_.name -match $svcPrefix } | remove-nsxserviceGroup -confirm:$false
        }

        it "Can create a service group" {

            $svcGrpName = "$svcPrefix-sg1"
            $svcDesc = "PowerNSX Pester Test service group"
            $svcgrp = New-NsxServiceGroup -Name $svcGrpName -Description $svcDesc
            $svcgrp.Name | Should be $svcGrpName
            $svcgrp.Description | should be $svcDesc
            $get = Get-NsxServiceGroup -Name $svcGrpName
            $get.name | should be $svcgrp.name
            $get.description | should be $svcgrp.description
            $get.inheritanceAllowed | should be "false"

        }

        it "Can create a service group with inheritance" {

            $svcGrpName = "$svcPrefix-sg2"
            $svcDesc = "PowerNSX Pester Test service group with inheritance"
            $svcgrp = New-NsxServiceGroup -Name $svcGrpName -Description $svcDesc -EnableInheritance
            $svcgrp.Name | Should be $svcGrpName
            $svcgrp.Description | should be $svcDesc
            $get = Get-NsxServiceGroup -Name $svcGrpName
            $get.name | should be $svcgrp.name
            $get.description | should be $svcgrp.description
            $get.inheritanceAllowed | should be "true"

        }


        it "Can create a service group and return an objectId only" {
            $svcGrpName = "$svcPrefix-objonly-1234"
            $svcDesc = "PowerNSX Pester Test objectidonly service"
            $id = New-NsxServiceGroup -Name $svcGrpName -Description $svcDesc -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^applicationgroup-\d*$"

        }

        It "Creates only a single servicegroup when used as the first part of a pipeline (#347)" {
            New-NsxServiceGroup -Name "$SvcPrefix-test-347"
            $SvcGrp = Get-NsxServiceGroup "$SvcPrefix-test-347" | ForEach-Object { New-NsxServiceGroup -Name $_.name -Universal}
            ($SvcGrp | Measure-Object).count | should be 1
        }

    }

    Context "Successful Universal Service Group Creation" {

        AfterAll {
            get-nsxserviceGroup -scopeid universalroot-0 | Where-Object { $_.name -match $svcPrefix } | remove-nsxserviceGroup -confirm:$false
        }

        it "Can create a universal service group" {

            $svcGrpName = "$svcPrefix-universal-sg"
            $svcDesc = "PowerNSX Pester Test universal service group"
            $svcgrp = New-NsxServiceGroup -Name $svcGrpName -Description $svcDesc -universal
            $svcgrp.Name | Should be $svcGrpName
            $svcgrp.Description | should be $svcDesc
            $get = Get-NsxServiceGroup -scopeid universalroot-0 -Name $svcGrpName
            $get.name | should be $svcgrp.name
            $get.description | should be $svcgrp.description
            $get.inheritanceAllowed | should be "false"

        }

    }


    Context "Service Group Deletion" {

        BeforeEach {
            $svcGrpName = "$svcPrefix-delete"
            $svcDesc = "PowerNSX Pester Test delete service group"
            $script:delete = New-NsxServiceGroup -Name $svcGrpName -Description $svcDesc

        }

        it "Can delete a servicegroup by object" {

            $delete | Remove-NsxServiceGroup -confirm:$false
            {Get-NsxServiceGroup -objectId $delete.objectId} | should throw
        }

    }

    Context "Applicable Members" {

        BeforeAll {
            #Service Group
            $svcgrpName1 = "$svcPrefix-testgroup-1"
            $UsvcgrpName1 = "$svcPrefix-testgroup-1-Universal"

            #Service
            $svcName1 = "$svcPrefix-testservice-1"
            $UsvcName1 = "$svcPrefix-testservice-1-Universal"

            # Remove any previosuly created ones
            Get-NsxServiceGroup | Where-Object { $_.name -match $svcPrefix } | Remove-NsxServiceGroup -Confirm:$false
            Get-NsxService | Where-Object { $_.name -match $svcPrefix } | Remove-NsxService -Confirm:$false

            # Create stuff
            $script:MemberSvcGrp1 = New-NsxServiceGroup -Name $svcgrpName1
            $script:UMemberSvcGrp1 = New-NsxServiceGroup -Name $UsvcgrpName1 -universal

            $script:MemberSvc1 = New-NsxService -Name $svcName1 -Protocol TCP -Port 80
            $script:UMemberSvc1 = New-NsxService -Name $UsvcName1 -Protocol TCP -Port 80 -Universal
        }

        AfterAll {
            Get-NsxServiceGroup | Where-Object { $_.name -match $svcPrefix } | Remove-NsxServiceGroup -Confirm:$false
            Get-NsxService | Where-Object { $_.name -match $svcPrefix } | Remove-NsxService -Confirm:$false
        }

        it "Can retrieve local Service Group Service applicable members" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $svcName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Application"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Service Group Service applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $svcName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Application"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Service Group service group applicable members" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $svcgrpName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ApplicationGroup"
            $item.isUniversal | should be "false"
        }

        it "Can retrieve local Service Group service group applicable members specifying scopeid globalroot-0" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers -scopeId GlobalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers -scopeId GlobalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $svcgrpName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ApplicationGroup"
            $item.isUniversal | should be "false"
        }

# Universal Applicable Members
        it "Can retrieve universal Service Group Service applicable members" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers -Universal } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers -Universal
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UsvcName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Application"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Service Group Service applicable members specifying scopeid universalroot-0" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers -scopeId universalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers -scopeId universalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UsvcName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "Application"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Service Group service group applicable members" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers -Universal } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers -Universal
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UsvcgrpName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ApplicationGroup"
            $item.isUniversal | should be "true"
        }

        it "Can retrieve universal Service Group service group applicable members specifying scopeid universalroot-0" {
            { Get-NsxApplicableMember -ServiceGroupApplicableMembers  -scopeId universalRoot-0 } | should not throw
            $results = Get-NsxApplicableMember -ServiceGroupApplicableMembers -scopeId universalRoot-0
            $results | should not be $null
            $item = $results | Where-Object {$_.name -eq $UsvcgrpName1}
            $item | should not be $null
            @($item | Measure-Object).count | should be 1
            $item.objectTypeName | should be "ApplicationGroup"
            $item.isUniversal | should be "true"
        }
    }
}