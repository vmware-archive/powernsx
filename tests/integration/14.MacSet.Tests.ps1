#PowerNSX Macset Tests.
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

Describe "MacSets" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred
        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:MacSetPrefix = "pester_macset_"

        #Clean up any existing macsets from previous runs...
        get-nsxmacset | Where-Object { $_.name -match $macsetPrefix } | remove-nsxmacset -confirm:$false

        #Set flag used to determine if universal objects should be tested.
        $NsxManagerRole = Get-NsxManagerRole
        if ( ( $NsxManagerRole.role -eq "PRIMARY") -or ($NsxManagerRole.role -eq "SECONDARY") ) {
            $script:universalSyncEnabled = $true
        }
        else {
            $script:universalSyncEnabled = $false
        }

    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxmacset | Where-Object { $_.name -match $macsetPrefix } | remove-nsxmacset -confirm:$false

        disconnect-nsxserver
    }

    Context "macset retrieval" {
        BeforeAll {
            $script:macsetName = "$macsetPrefix-get"
            $macsetDesc = "PowerNSX Pester Test get macset"
            $script:macsetNameUniversal = "$macsetPrefix-get-universal"
            $macsetDescUniversal = "PowerNSX Pester Test get universal macset"
            $script:get = New-nsxmacset -Name $macsetName -Description $macsetDesc
            if ( $universalSyncEnabled ) {
                $script:getuniversal = New-nsxmacset -Name $macsetNameUniversal -Description $macsetDescUniversal -Universal
            }
        }

        it "Can retrieve a macset by name" {
            {Get-nsxmacset -Name $macsetName} | should not throw
            $macset = Get-nsxmacset -Name $macsetName
            $macset | should not be $null
            $macset.name | should be $macsetName

         }

        it "Can retrieve a macset by id" {
            {Get-nsxmacset -objectId $get.objectId } | should not throw
            $macset = Get-nsxmacset -objectId $get.objectId
            $macset | should not be $null
            $macset.objectId | should be $get.objectId
         }

         It "Can retrieve global macsets" {
            $macsets = Get-Nsxmacset
            ($macsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

         It "Can retrieve both universal and global macsets"  -skip:(-not $universalSyncEnabled ) {
            $macsets = Get-Nsxmacset
            ($macsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($macsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

         It "Can retrieve universal only macsets" -skip:(-not $universalSyncEnabled ) {
            $macsets = Get-Nsxmacset -UniversalOnly
            ($macsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($macsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
         }

         It "Can retrieve local only macsets" {
            $macsets = Get-Nsxmacset -LocalOnly
            ($macsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should be 0
            ($macsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

         It "Can retrieve universal only macsets with scopeid" -skip:(-not $universalSyncEnabled )  {
            $macsets = Get-Nsxmacset -scopeid universalroot-0
            ($macsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($macsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
         }

         It "Can retrieve local only macsets with scopeid" {
            $macsets = Get-Nsxmacset -scopeid globalroot-0
            ($macsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should be 0
            ($macsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

    }

    Context "Successful macset Creation" {

        AfterAll {
            get-nsxmacset | Where-Object { $_.name -match $macsetPrefix } | remove-nsxmacset -confirm:$false
        }

        it "Can create a macset with single address" {

            $macsetName = "$macsetPrefix-macset-create1"
            $macsetDesc = "PowerNSX Pester Test create macset"
            $macaddresses = "00:00:00:00:00:00"
            $macset = New-nsxmacset -Name $macsetName -Description $macsetDesc -MacAddresses $macaddresses
            $macset.Name | Should be $macsetName
            $macset.Description | should be $macsetDesc
            $get = Get-nsxmacset -Name $macsetName
            $get.name | should be $macset.name
            $get.description | should be $macset.description
            $get.value | should be $macset.value
            $get.inheritanceAllowed | should be "false"

        }

        it "Can create a macset and return an objectId only" {
            $macsetName = "$macsetPrefix-objonly-1234"
            $macsetDesc = "PowerNSX Pester Test objectidonly macset"
            $macaddresses = "00:00:00:00:00:00"
            $id = New-nsxmacset -Name $macsetName -Description $macsetDesc -MacAddresses $macaddresses -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^macset-\d*$"

         }

        it "Can create a macset with inheritance enabled" {

            $macsetName = "$macsetPrefix-macset-create2"
            $macsetDesc = "PowerNSX Pester Test create macset with inheritance"
            $macaddresses = "00:00:00:00:00:00"
            $macset = New-nsxmacset -Name $macsetName -Description $macsetDesc -MacAddresses $macaddresses -EnableInheritance
            $macset.Name | Should be $macsetName
            $macset.Description | should be $macsetDesc
            $get = Get-nsxmacset -Name $macsetName
            $get.name | should be $macset.name
            $get.description | should be $macset.description
            $get.value | should be $macset.value
            $get.inheritanceAllowed | should be "true"

        }

        It "Creates only a single macse when used as the first part of a pipeline (#347)" {
            New-NsxMacSet -Name "$macsetPrefix-test-347"
            $MacSet = Get-NsxMacSet "$macsetPrefix-test-347" | ForEach-Object { New-NsxMacSet -Name $_.name -Universal}
            ($MacSet | Measure-Object).count | should be 1
        }
    }

    Context "Unsuccessful macset Creation" {

        it "Fails to create a macset with invalid address" {

            $macsetName = "$macsetPrefix-macset-create1"
            $macsetDesc = "PowerNSX Pester Test create macset"
            $macaddress = "00:00:00:00:00:00:00"
            { New-nsxmacset -Name $macsetName -Description $macsetDesc -MacAddresses $macaddress } | should throw
        }
    }


    Context "macset Deletion" {

        BeforeEach {
            $macsetName = "$macsetPrefix-delete"
            $macsetDesc = "PowerNSX Pester Test delete macset"
            $script:delete = New-nsxmacset -Name $macsetName -Description $macsetDesc

        }

        it "Can delete a macset by object" {

            $delete | Remove-nsxmacset -confirm:$false
            {Get-nsxmacset -objectId $delete.objectId} | should throw
        }

    }

    Context "macset Modification - Addition" {

        #Missing cmdlets to date...

        BeforeEach {
            $macsetName = "$macsetPrefix-modify"
            $macsetDesc = "PowerNSX Pester Test modify macset"
            get-nsxmacset $macsetName | remove-nsxmacset -Confirm:$false
            $script:modify = New-nsxmacset -Name $macsetName -Description $macsetDesc

        }

        AfterEach {
            $macsetName = "$macsetPrefix-modify"
            get-nsxmacset $macsetName | remove-nsxmacset -Confirm:$false

        }

        it "Can add a new address to a mac set" -skip {
            $macaddresses = "00:00:00:00:00:00"
            $macset = $modify | Add-NsxmacsetMember -MacAddress $macaddresses
            $macset.value | should be $macaddresses
        }

        it "Fails to add a duplicate address to a MacSet" -skip {
            $macaddresses = "00:00:00:00:00:00"
            $macset = $modify | Add-NsxmacsetMember -MacAddress $macaddresses
            $macset.value | should be $macaddresses
            {$macset | Add-NsxmacsetMember -MacAddress $macaddresses} | should throw
        }

        it "Can add multiple values to a macset" -skip {
            $macaddresses1 = "00:00:00:00:00:00"
            $macaddresses2 = "11:11:11:11:11:11"
            $macset = $modify | Add-NsxmacsetMember -MacAddress $macaddresses1,$macaddresses2
            $macset.value -split "," -contains $macaddresses1 | should be $true
            $macset.value -split "," -contains $macaddresses2 | should be $true
        }
    }
    Context "macset Modification - Removal" {

        BeforeEach {
            $macsetName = "$macsetPrefix-removal"
            $macsetDesc = "PowerNSX Pester Test removal macset"
            $macaddresses = "00:00:00:00:00:00"
            $macaddresses2 = "00:00:00:00:00:00"
            get-nsxmacset $macsetName | remove-nsxmacset -Confirm:$false
            $script:remove = New-nsxmacset -Name $macsetName -Description $macsetDesc -MacAddresses $macaddresses,$macaddresses2

        }

        AfterEach {
            $macsetName = "$macsetPrefix-removal"
            get-nsxmacset $macsetName | remove-nsxmacset -Confirm:$false

        }

        it "Can remove an address from a macset" -skip {
            $macset = $remove | Remove-NsxmacsetMember -MacAddress $macaddresses
            $macset.value -split "," -contains $macaddresses | should be $false
        }

        it "Can remove multiple values from a macset" -skip {

            $macset = $remove | Remove-NsxmacsetMember -MacAddress $macaddresses1,$macaddresses2
            $macset.value -split "," -contains $macaddresses | should be $false
            $macset.value -split "," -contains $macaddresses2 | should be $false

        }


    }
}