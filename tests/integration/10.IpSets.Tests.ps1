#PowerNSX IPSet Tests.
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

Describe "IPSets" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred
        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:IpSetPrefix = "pester_ipset_"

        #Clean up any existing ipsets from previous runs...
        get-nsxipset | Where-Object { $_.name -match $IpSetPrefix } | remove-nsxipset -confirm:$false


    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxipset | Where-Object { $_.name -match $IpSetPrefix } | remove-nsxipset -confirm:$false

        disconnect-nsxserver
    }

    Context "IpSet retrieval" {
        BeforeAll {
            $script:ipsetName = "$IpSetPrefix-get"
            $ipSetDesc = "PowerNSX Pester Test get ipset"
            $script:ipsetNameUniversal = "$IpSetPrefix-get-universal"
            $ipSetDescUniversal = "PowerNSX Pester Test get universal ipset"
            $script:get = New-nsxipset -Name $ipsetName -Description $ipSetDesc
            $script:getuniversal = New-nsxipset -Name $ipsetNameUniversal -Description $ipSetDescUniversal -Universal
        }

        it "Can retrieve an ipset by name" {
            {Get-nsxipset -Name $ipsetName} | should not throw
            $ipset = Get-nsxipset -Name $ipsetName
            $ipset | should not be $null
            $ipset.name | should be $ipsetName
         }

        it "Can retrieve an ipset by id" {
            {Get-nsxipset -objectId $get.objectId } | should not throw
            $ipset = Get-nsxipset -objectId $get.objectId
            $ipset | should not be $null
            $ipset.objectId | should be $get.objectId
         }

         It "Can retrieve both universal and global IpSets" {
            $ipsets = Get-NsxIpSet
            ($ipsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($ipsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

         It "Can retrieve universal only IpSets" {
            $ipsets = Get-NsxIpSet -UniversalOnly
            ($ipsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($ipsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
         }

         It "Can retrieve local only IpSets" {
            $ipsets = Get-NsxIpSet -LocalOnly
            ($ipsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should be 0
            ($ipsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

         it "Can retrieve IpSets from scopeid of globalroot-0" {
            $ipsets = Get-NsxIpSet -scopeId globalroot-0
            ($ipsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should be 0
            ($ipsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should begreaterthan 0
         }

         it "Can retrieve IpSets from scopeid of universalroot-0" {
            $ipsets = Get-NsxIpSet -scopeId universalroot-0
            ($ipsets | Where-Object { $_.isUniversal -eq 'True'} | Measure-Object).count | should begreaterthan 0
            ($ipsets | Where-Object { $_.isUniversal -eq 'False'} | Measure-Object).count | should be 0
         }

    }

    Context "Successful IpSet Creation (Legacy)" {

        AfterAll {
            get-nsxipset | Where-Object { $_.name -match $IpSetPrefix } | remove-nsxipset -confirm:$false
        }

        it "Can create an ipset with single address" {

            $ipsetName = "$IpSetPrefix-ipset-create1"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddresses $ipaddresses
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "false"
        }

        it "Can create an ipset with range" {

            $ipsetName = "$IpSetPrefix-ipset-create2"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4-2.3.4.5"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddresses $ipaddresses
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "false"
        }

        it "Can create an ipset with CIDR" {

            $ipsetName = "$IpSetPrefix-ipset-create3"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.0/24"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddresses $ipaddresses
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "false"
        }


        it "Can create an ipset with multiple entries" {

            $ipsetName = "$IpSetPrefix-ipset-create4"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddress1 = "1.2.3.4"
            $ipaddress2 = "1.2.3.4-2.3.4.5"
            $ipaddress3 = "1.2.3.0/24"
            $ipaddresses = @($ipaddress1,$ipaddress2,$ipaddress3)
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddresses ($ipaddresses -join ",")
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value -split "," -contains $ipAddress1 | should be $true
            $get.value -split "," -contains $ipAddress2 | should be $true
            $get.value -split "," -contains $ipAddress3 | should be $true
            $get.inheritanceAllowed | should be "false"
        }

        it "Can create an ipset with inheritance enabled" {

            $ipsetName = "$IpSetPrefix-ipset-create5"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddresses $ipaddresses -EnableInheritance
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "true"
        }

        it "Can create an ipset and return an objectId only" {
            $ipsetName = "$IpSetPrefix-objonly-1234"
            $ipsetDesc = "PowerNSX Pester Test objectidonly ipset"
            $ipaddresses = "1.2.3.4"
            $id = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddresses $ipaddresses -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^ipset-\d*$"
        }
    }

    Context "Unsuccessful IpSet Creation (Legacy)" {

        it "Fails to create an ipset with invalid address" {

            $ipsetName = "$IpSetPrefix-ipset-create1"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4.5"
            { New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddresses $ipaddresses } | should throw
        }
    }

    Context "Successful IpSet Creation" {

        AfterAll {
            get-nsxipset | Where-Object { $_.name -match $IpSetPrefix } | remove-nsxipset -confirm:$false
        }

        it "Can create an ipset with single address" {

            $ipsetName = "$IpSetPrefix-ipset-create1"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddresses
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "false"
        }

        it "Can create an ipset with range" {

            $ipsetName = "$IpSetPrefix-ipset-create2"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4-2.3.4.5"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddresses
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "false"
        }

        it "Can create an ipset with CIDR" {

            $ipsetName = "$IpSetPrefix-ipset-create3"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.0/24"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddresses
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "false"
        }

        it "Can create an ipset with multiple entries" {

            $ipsetName = "$IpSetPrefix-ipset-create4"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddress1 = "1.2.3.4"
            $ipaddress2 = "1.2.3.4-2.3.4.5"
            $ipaddress3 = "1.2.3.0/24"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddress1,$ipaddress2,$ipaddress3
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value -split "," -contains $ipAddress1 | should be $true
            $get.value -split "," -contains $ipAddress2 | should be $true
            $get.value -split "," -contains $ipAddress3 | should be $true
            $get.inheritanceAllowed | should be "false"
        }

        it "Can create an ipset with inheritance enabled" {

            $ipsetName = "$IpSetPrefix-ipset-create5"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4"
            $ipset = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddresses -EnableInheritance
            $ipset.Name | Should be $ipsetName
            $ipset.Description | should be $ipsetDesc
            $get = Get-nsxipset -Name $ipsetName
            $get.name | should be $ipset.name
            $get.description | should be $ipset.description
            $get.value | should be $ipset.value
            $get.inheritanceAllowed | should be "true"
        }

        it "Can create an ipset and return an objectId only" {
            $ipsetName = "$IpSetPrefix-objonly-1234"
            $ipsetDesc = "PowerNSX Pester Test objectidonly ipset"
            $ipaddresses = "1.2.3.4"
            $id = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddresses -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^ipset-\d*$"
        }

        It "Creates only a single ipset when used as the first part of a pipeline (#347)" {
            New-NsxIpSet -Name "$IpSetPrefix-test-347"
            $IpSet = Get-NsxIpSet "$IpSetPrefix-test-347" | ForEach-Object { New-NsxIpSet -Name $_.name -Universal}
            ($IpSet | Measure-Object).count | should be 1
        }
    }

    Context "Unsuccessful IpSet Creation" {

        it "Fails to create an ipset with invalid address" {

            $ipsetName = "$IpSetPrefix-ipset-create1"
            $ipsetDesc = "PowerNSX Pester Test create ipset"
            $ipaddresses = "1.2.3.4.5"
            { New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddresses } | should throw
        }
    }


    Context "IpSet Deletion" {

        BeforeEach {
            $ipsetName = "$IpSetPrefix-delete"
            $ipsetDesc = "PowerNSX Pester Test delete IpSet"
            $script:delete = New-nsxipset -Name $ipsetName -Description $ipsetDesc

        }

        it "Can delete an ipset by object" {

            $delete | Remove-nsxipset -confirm:$false
            {Get-nsxipset -objectId $delete.objectId} | should throw
        }

    }

    Context "IpSet Modification - Addition" {

        BeforeEach {
            $ipsetName = "$IpSetPrefix-modify"
            $ipsetDesc = "PowerNSX Pester Test modify IpSet"
            get-nsxipset $ipsetName | remove-nsxipset -Confirm:$false
            $script:modify = New-nsxipset -Name $ipsetName -Description $ipsetDesc

        }

        AfterEach {
            $ipsetName = "$IpSetPrefix-modify"
            get-nsxipset $ipsetName | remove-nsxipset -Confirm:$false

        }

        it "Can add a new address to an ip set" {
            $IpAddress = "1.2.3.4"
            $ipset = $modify | Add-NsxIpSetMember -IpAddress $IpAddress
            $ipset.value | should be $IpAddress
        }

        it "Fails to add a duplicate address to an ip set" {
            $IpAddress = "1.2.3.4"
            $ipset = $modify | Add-NsxIpSetMember -IpAddress $IpAddress
            $ipset.value | should be $IpAddress
            {$ipset | Add-NsxIpSetMember -IpAddress $IpAddress} | should not throw
        }

        it "Can add a new range to an ip set" {
            $IpAddress = "1.2.3.4-2.3.4.5"
            $ipset = $modify | Add-NsxIpSetMember -IpAddress $IpAddress
            $ipset.value | should be $IpAddress
        }

        it "Can add a new cidr to an ip set" {
            $IpAddress = "1.2.3.0/24"
            $ipset = $modify | Add-NsxIpSetMember -IpAddress $IpAddress
            $ipset.value | should be $IpAddress
        }

        it "Can add multiple values to an ip set" {
            $IpAddress1 = "1.2.3.4"
            $IpAddress2 = "4.3.2.1"
            $ipset = $modify | Add-NsxIpSetMember -IpAddress $IpAddress1,$ipaddress2
            $ipset.value -split "," -contains $ipAddress1 | should be $true
            $ipset.value -split "," -contains $ipAddress2 | should be $true
        }

       it "Can detect adding a value to an ip set that already exists" {
            $IpAddress1 = "1.2.3.4"
            $IpAddress2 = "4.3.2.1"
            $IpAddress3 = "5.6.7.8"
            $IpAddress4 = "9.8.7.6"
            $ipset = $modify | Add-NsxIpSetMember -IpAddress $IpAddress1,$ipaddress2
            $ipset1 = $ipset | Add-NsxIpSetMember -IpAddress $IpAddress3,$ipaddress2,$IpAddress4
            $ipset1.value -split "," -contains $ipAddress1 | should be $true
            $ipset1.value -split "," -contains $ipAddress2 | should be $true
            $ipset1.value -split "," -contains $IpAddress3 | should be $true
            $ipset1.value -split "," -contains $IpAddress4 | should be $true
        }

    }
    Context "IpSet Modification - Removal" {

        BeforeEach {
            $ipsetName = "$IpSetPrefix-removal"
            $ipsetDesc = "PowerNSX Pester Test removal IpSet"
            $ipaddress = "1.2.3.4"
            $iprange = "1.2.3.4-2.3.4.5"
            $cidr = "1.2.3.0/24"
            $hostCidr = "1.2.3.4/32"
            $dummyIpAddress = "9.9.9.9"
            get-nsxipset $ipsetName | remove-nsxipset -Confirm:$false
            $script:remove = New-nsxipset -Name $ipsetName -Description $ipsetDesc -IPAddress $ipaddress,$iprange,$cidr,$hostCidr

        }

        AfterEach {
            $ipsetName = "$IpSetPrefix-removal"
            get-nsxipset $ipsetName | remove-nsxipset -Confirm:$false

        }

        it "Can remove an address from an ip set" {
            $ipset = $remove | Remove-NsxIpSetMember -IpAddress $IpAddress
            $ipset.value -split "," -contains $ipaddress | should be $false
            $ipset.value -split "," -contains $iprange | should be $true
            $ipset.value -split "," -contains $cidr | should be $true
            $ipset.value -split "," -contains $hostCidr | should be $false
        }

        it "Can remove a range from an ip set" {
            $ipset = $remove | Remove-NsxIpSetMember -IpAddress $iprange
            $ipset.value -split "," -contains $iprange | should be $false
            $ipset.value -split "," -contains $ipaddress | should be $true
            $ipset.value -split "," -contains $cidr | should be $true
            $ipset.value -split "," -contains $hostCidr | should be $true
        }

        it "Can remove a cidr from an ip set" {
            $ipset = $remove | Remove-NsxIpSetMember -IpAddress $cidr
            $ipset.value -split "," -contains $cidr | should be $false
            $ipset.value -split "," -contains $ipaddress | should be $true
            $ipset.value -split "," -contains $iprange | should be $true
            $ipset.value -split "," -contains $hostCidr | should be $true
        }

        it "Display a warning when when an ip set does not contain an address to be removed" {
            $ipset = $remove | Remove-NsxIpSetMember -IpAddress $dummyIpAddress -WarningVariable warning
            $warning | Should Match ": $dummyIpAddress is not a member of IPSet"
            $ipset | Should be $null
            $validate = get-nsxipset $ipsetName
            $validate.value -split "," -contains $ipaddress | should be $true
            $validate.value -split "," -contains $hostCidr | should be $true
            $validate.value -split "," -contains $cidr | should be $true
            $validate.value -split "," -contains $iprange | should be $true
        }

        it "Display a warning when when an ip set does not contain any memebers" {
            # Cleanup the existing IP Set as we need to create one with no
            # IP addresses specified.
            get-nsxipset $ipsetName | remove-nsxipset -Confirm:$false
            $script:remove = New-nsxipset -Name $ipsetName -Description $ipsetDesc
            $remove | Should not be $null
            $remove | Remove-NsxIpSetMember -IpAddress $dummyIpAddress -WarningVariable warning
            $warning | Should match ": No members found"
        }

        it "Fail to remove all addresses from an ip set" {
            { $remove | Remove-NsxIpSetMember -IpAddress $ipaddress,$hostCidr,$cidr,$iprange } | should throw
        }

        it "Can remove multiple values from an ip set" {

            $ipset = $remove | Remove-NsxIpSetMember -IpAddress $ipaddress,$iprange
            $ipset.value -split "," -contains $ipaddress | should be $false
            $ipset.value -split "," -contains $iprange | should be $false
            $ipset.value -split "," -contains $cidr | should be $true
            $ipset.value -split "," -contains $hostCidr | should be $false
        }

        it "Can remove a host cidr when a matching non cidr address is specified" {
            $ipset = $remove | Remove-NsxIpSetMember -IpAddress $ipaddress
            $ipset.value -split "," -contains $ipaddress | should be $false
            $ipset.value -split "," -contains $hostCidr | should be $false
            $ipset.value -split "," -contains $cidr | should be $true
            $ipset.value -split "," -contains $iprange | should be $true
        }

        it "Can remove a non cidr host address when a matching host cidr address is specified" {
            $ipset = $remove | Remove-NsxIpSetMember -IpAddress $hostCidr
            $ipset.value -split "," -contains $ipaddress | should be $false
            $ipset.value -split "," -contains $hostCidr | should be $false
            $ipset.value -split "," -contains $cidr | should be $true
            $ipset.value -split "," -contains $iprange | should be $true
        }

    }
}
