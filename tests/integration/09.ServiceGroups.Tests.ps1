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
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:svcPrefix = "pester_svcgrp_"

        #Clean up any existing services from previous runs...
        get-nsxservicegroup | ? { $_.name -match $svcPrefix } | remove-nsxservicegroup -confirm:$false


    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxservicegroup | ? { $_.name -match $svcPrefix } | remove-nsxservicegroup -confirm:$false

        disconnect-nsxserver
    }

    Context "ServiceGroup retrieval" {
        BeforeAll {
            $script:svcGrpName = "$svcPrefix-get"
            $svcGrpDesc = "PowerNSX Pester Test get serviceGroup"
            $script:get = New-NsxServiceGroup -Name $svcGrpName -Description $svcGrpDesc

        }

        it "Can retreive a service group by name" {
            {Get-NsxServiceGroup -Name $svcGrpName} | should not throw
            $sg = Get-NsxServiceGroup -Name $svcGrpName
            $sg | should not be $null
            $sg.name | should be $svcGrpName

         }

        it "Can retreive a service group by id" {
            {Get-NsxServiceGroup -objectId $get.objectId } | should not throw
            $sg = Get-NsxServiceGroup -objectId $get.objectId
            $sg | should not be $null
            $sg.objectId | should be $get.objectId
         }


    }

    Context "Successful Service Group Creation" {

        AfterAll {
            get-nsxserviceGroup | ? { $_.name -match $svcPrefix } | remove-nsxserviceGroup -confirm:$false
        }

        it "Can create a service group" {

            $svcGrpName = "$svcPrefix-sg"
            $svcDesc = "PowerNSX Pester Test service group"
            $svcgrp = New-NsxServiceGroup -Name $svcGrpName -Description $svcDesc
            $svcgrp.Name | Should be $svcGrpName
            $svcgrp.Description | should be $svcDesc
            $get = Get-NsxServiceGroup -Name $svcGrpName
            $get.name | should be $svcgrp.name
            $get.description | should be $svcgrp.description
            $get.element.protocol | should be $svcgrp.element.protocol

        }


        it "Can create a service group and return an objectId only" {
            $svcGrpName = "$svcPrefix-objonly-1234"
            $svcDesc = "PowerNSX Pester Test objectidonly service"
            $id = New-NsxServiceGroup -Name $svcGrpName -Description $svcDesc -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^applicationgroup-\d*$"

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
}