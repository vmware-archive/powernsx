#PowerNSX Manager cmdlet tests.
#Nick Bradford : nbradford@vmware.com

#########################
#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "NSXManager" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred
        $script:adminConnection = Connect-NsxServer -NsxServer $DefaultNsxConnection.Server -Credential $PNSXTestDefMgrCred


        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:NTPServer1 = "1.1.1.1"
        $script:NTPServer2 = "2.2.2.2"
        $Script:TimeZone = "Australia/Melbourne"

        #SSO account used to test different level permissions.  MUST BE PRECREATED with at least vsphere R/O rights. (because there is no SSO API to do this automatically. GGGGGGGRRRRRRRRRRR)
        $Script:TestSSOAccount = "powernsx_test@vsphere.local"
        $Script:TestSSOPassword = "VMware1!"

        #This can fail if non-admin account is used.
        #Try to preserve existing state...
        # $Script:PreExistingConfig = Get-NsxManagerTimeSettings

        #Test if required test SSO account exists in VC
        try {
            $dummyconn = Connect-VIServer $PNSXTestVC -NotDefault -username $TestSSOAccount -Password $TestSSOPassword -ErrorAction Stop
            $Global:SkipSSOTests = $false
        }
        catch {
            write-warning "Unable to authenticate to vCenter using test SSO account.  Please precreate $TestSSOAccount and grant at least R/O vCenter Inventory permissions.  SSO credential tests will be skipped."
            $Global:SkipSSOTests = $True
        }

        $role = Get-NsxUserRole $PNSXTestDefViCred.Username
        if ( $role.role -eq 'super_user') {
            $Script:IsSuperUser = $true
        }
        else {
            write-warning "Skipping tests requiring super_user (admin) credentials."
            $Script:IsSuperUser = $false
        }
    }

    Context "Basic Connect" {

        #Connect-NsxServer tests
        it "Can connect directly to NSX server using admin account - legacy mode" {
            $NSXManager = $DefaultNsxConnection.Server
            $DirectConn = Connect-NsxServer -NsxServer $NSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore"
            $DirectConn | should not be $null
            $DirectConn.Version | should not be $null
            $DirectConn.BuildNumber | should not be $null
            $DirectConn.ViConnection | should not be $null
        }

        it "Can connect directly to NSX server using Ent_Admin SSO account" {
            $NSXManager = $DefaultNsxConnection.Server
            $DirectConn = Connect-NsxServer -NsxServer $NSXManager -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
            $DirectConn | should not be $null
            $DirectConn.Version | should be $null
            $DirectConn.BuildNumber | should be $null
        }

    }

    Context "Restricted Role Connect" {

        BeforeEach {
            #ensure the NSX user account is removed.
            try {
                $result = Invoke-NsxRestMethod -method delete -uri "/api/2.0/services/usermgmt/role/$TestSSOAccount"
            }
            catch {
                #Do nothing
            }
        }

        It "Can connect using vCenter using Auditor SSO account" {

            #Create auditor role xml
            $xmlDoc = New-Object System.Xml.XmlDocument
            $ace = $xmlDoc.CreateElement("accessControlEntry")
            $xmlDoc.AppendChild($ace) | out-null

            $roleElem = $xmlDoc.CreateElement("role")
            $roleNode = $xmlDoc.CreateTextNode("auditor")
            $ace.AppendChild($roleElem) | out-null
            $roleElem.AppendChild($roleNode) | out-null

            $resourceElem = $xmlDoc.CreateElement("resource")
            $resourceIdElem = $xmlDoc.CreateElement("resourceId")
            $resourceNode = $xmlDoc.CreateTextNode("globalroot-0")
            $ace.AppendChild($resourceElem) | out-null
            $resourceElem.AppendChild($resourceIdElem) | out-null
            $resourceIdElem.AppendChild($resourceNode) | out-null

            #make test user auditor
            $result = Invoke-NsxRestMethod -method post -uri "/api/2.0/services/usermgmt/role/$TestSSOAccount" -body $ace.outerxml -connection $adminConnection

            $testconn = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred -DefaultConnection:$false

            $testConn | should not be $null
            $testConn.version | should not be $null
            $testConn.BuildNumber | should not be $null
            $testConn.VIConnection | should not be $null

        }

    }

    Context "Time" {

        #Group related tests together.

        it "Can get existing time configuration" {

            $TimeConfig = Get-NsxManagerTimeSettings -connection $adminConnection
            $TimeConfig.datetime | should not be $null

            #Not 100% on this, but I think tz always exists, and defaults to UTC.
            $TimeConfig.timezone | should not be $null

        }

        it "Can clear existing NTP configuration" {
            $TimeConfig = Clear-NsxManagerTimeSettings -connection $adminConnection
            $TimeConfig | should be $null
            $GetTimeConfig = Get-NsxManagerTimeSettings
            $GetTimeConfig.NtpServer | should be $null
        }

        it "Can configure NTP servers" {
            $TimeConfig = Set-NsxManagerTimeSettings -NtpServer $NTPServer1, $NTPServer2 -connection $adminConnection
            $TimeConfig.ntpserver | should not be $null
            $GetTimeConfig = Get-NsxManagerTimeSettings
            $GetTimeConfig.ntpserver.string -contains $NTPServer1 | should be $true
            $GetTimeConfig.ntpserver.string -contains $NTPServer2 | should be $true
        }

        it "Can configure timezone configuration" {
            $TimeConfig = Set-NsxManagerTimeSettings -TimeZone $TimeZone -connection $adminConnection
            $TimeConfig.timezone | should be $Timezone
            $GetTimeConfig = Get-NsxManagerTimeSettings
            $TimeConfig.timezone | should be $Timezone
        }
    }

    Context "Certificate" {

        #Group related tests together.

        it "Can get configured SSL Certificates" {
            $certificates = Get-NsxManagerCertificate -connection $adminConnection
            $( $certificates | measure ).count | should BeGreaterThan 0
            $certificates | should not be $null
        }
    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        # This can fail if a non-admin account is used.
        # if ($PreExistingConfig.ntpserver.string) {
        #     Clear-NsxManagerTimeSettings
        #     Set-NsxManagerTimeSettings -NtpServer $PreExistingConfig.ntpserver.string
        # }
        # try {
        #     #this can fail depending on credentials
        #     Set-NsxManagerTimeSettings -TimeZone $PreExistingConfig.timezone
        # }
        # catch {
        #     #do nothing
        # }
        disconnect-nsxserver
    }
}