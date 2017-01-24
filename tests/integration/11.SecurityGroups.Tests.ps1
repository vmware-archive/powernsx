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
If ( -not $PNSXTestNSXManager ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "SecurityGroups" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -DisableVIAutoConnect

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:sgPrefix = "pester_secgrp_"

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
            $get.element.protocol | should be $secGrp.element.protocol

        }


        it "Can create a SecurityGroup and return an objectId only" {
            $secGrpName = "$sgPrefix-objonly-1234"
            $SecGrpDesc = "PowerNSX Pester Test objectidonly SecurityGroup"
            $id = New-nsxsecuritygroup -Name $secGrpName -Description $SecGrpDesc -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^securitygroup-\d*$"

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