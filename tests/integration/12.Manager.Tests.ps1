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
        $script:adminConnection = Connect-NsxServer -NsxServer $DefaultNsxConnection.Server -Credential $PNSXTestDefMgrCred -DefaultConnection:$false


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
            $ver_gt_630_universalSyncEnabled = $true
        }
        else {
            $ver_gt_630_universalSyncEnabled = $false
        }
    }

    Context "Basic Connect" {

        #Connect-NsxServer tests
        it "Can connect directly to NSX server using admin account - legacy mode" {
            $NSXManager = $DefaultNsxConnection.Server
            $DirectConn = Connect-NsxServer -NsxServer $NSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore" -DefaultConnection:$false
            $DirectConn | should not be $null
            $DirectConn.Version | should not be $null
            $DirectConn.BuildNumber | should not be $null
            $DirectConn.ViConnection | should not be $null
        }

        it "Can connect directly to NSX server using Ent_Admin SSO account" {
            $NSXManager = $DefaultNsxConnection.Server
            $DirectConn = Connect-NsxServer -NsxServer $NSXManager -Credential $PNSXTestDefViCred -ViWarningAction "Ignore" -DefaultConnection:$false
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
            $GetTimeConfig = Get-NsxManagerTimeSettings -connection $adminConnection
            $GetTimeConfig.NtpServer | should be $null
        }

        it "Can configure NTP servers" {
            $TimeConfig = Set-NsxManagerTimeSettings -NtpServer $NTPServer1, $NTPServer2 -connection $adminConnection
            $TimeConfig.ntpserver | should not be $null
            $GetTimeConfig = Get-NsxManagerTimeSettings -connection $adminConnection
            $GetTimeConfig.ntpserver.string -contains $NTPServer1 | should be $true
            $GetTimeConfig.ntpserver.string -contains $NTPServer2 | should be $true
        }

        it "Can configure timezone configuration" {
            $TimeConfig = Set-NsxManagerTimeSettings -TimeZone $TimeZone -connection $adminConnection
            $TimeConfig.timezone | should be $Timezone
            $GetTimeConfig = Get-NsxManagerTimeSettings -connection $adminConnection
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

    Context "Syslog" {

        it "can configure syslog server configuration" {
        }

        it "Can retrieve current syslog server configuration" {
        }

        it "Can delete current syslog server configuration" {
        }

    }

    Context "Universal Sync" {

        BeforeAll {
            if ( $universalSyncEnabled ) {
                $script:universalPrefix = "pester_universal"
                $script:universalTz = Get-NsxTransportZone | ? {$_.isUniversal -eq 'true' | Select -First 1}
                $script:universalLs = $universalTz | New-NsxLogicalSwitch -Name $universalPrefix-LS1
                $script:universalSg = New-NsxSecurityGroup -Name $universalPrefix-SecurityGroup -universal
                $script:universalIpSet = New-NsxIpSet -Name $universalPrefix-IPSet -universal
                $script:universalMacSet = New-NsxMacSet -Name $universalPrefix-MACSet -universal
                $script:universalSvc = New-NsxService -Name $universalPrefix-Service -Protocol TCP -Port 80 -universal
                $script:universalSvcGrp = New-NsxServiceGroup -Name $universalPrefix-ServiceGroup -universal

                if ( $ver_gt_630 ) {
                    $script:universalSt = New-NsxSecurityTag -Name $universalPrefix-SecurityTag -universal
                }

            }
        }

        AfterAll {
            Get-NsxLogicalSwitch | ? { $_.name -match $universalPrefix } | Remove-NsxLogicalSwitch -confirm:$false
            Get-NsxSecurityGroup | ? { $_.name -match $universalPrefix } | Remove-NsxSecurityGroup -confirm:$false
            Get-NsxIpSet | ? { $_.name -match $universalPrefix } | Remove-NsxIpSet -confirm:$false
            Get-NsxMacSet | ? { $_.name -match $universalPrefix } | Remove-NsxMacSet -confirm:$false
            Get-NsxService | ? { $_.name -match $universalPrefix } | Remove-NsxService -confirm:$false
            Get-NsxServiceGroup | ? { $_.name -match $universalPrefix } | Remove-NsxServiceGroup -confirm:$false

            if ( $ver_gt_630 ) {
                Get-NsxSecurityTag | ? { $_.name -match $universalPrefix } | Remove-NsxSecurityTag -confirm:$false
            }

        }

        it "Can retrieve Universal Sync status" -skip:(-not $universalSyncEnabled ) {
            {Get-NsxUniversalSyncStatus} | should not throw
            $status = Get-NsxUniversalSyncStatus
            $status | should not be $null
            $status.lastClusterSyncTime | should BeGreaterThan 0
        }

        it "Can retrieve Universal Sync status of a universal transport zone" -skip:(-not $universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType VdnScope -objectId $universalTz.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType VdnScope -objectId $universalTz.objectId
            $status | should not be $null
            $status.objectId | should be $universalTz.objectId
        }

        it "Can retrieve Universal Sync status of a universal logical switch" -skip:(-not $universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType VirtualWire -objectId $universalLs.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType VirtualWire -objectId $universalLs.objectId
            $status | should not be $null
            $status.objectId | should be $universalLs.objectId
        }

        it "Can retrieve Universal Sync status of a universal Security Group" -skip:(-not $universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType SecurityGroup -objectId $universalSg.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType SecurityGroup -objectId $universalSg.objectId
            $status | should not be $null
            $status.objectId | should be $universalSg.objectId
        }

        it "Can retrieve Universal Sync status of a universal IP Set" -skip:(-not $universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType IPSet -objectId $universalIpSet.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType IPSet -objectId $universalIpSet.objectId
            $status | should not be $null
            $status.objectId | should be $universalIpSet.objectId
        }

        it "Can retrieve Universal Sync status of a universal MAC Set" -skip:(-not $universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType MACSet -objectId $universalMacSet.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType MACSet -objectId $universalMacSet.objectId
            $status | should not be $null
            $status.objectId | should be $universalMacSet.objectId
        }

        it "Can retrieve Universal Sync status of a universal Security Tag" -skip:( -not $ver_gt_630_universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType SecurityTag -objectId $universalSt.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType SecurityTag -objectId $universalSt.objectId
            $status | should not be $null
            $status.objectId | should be $universalSt.objectId
        }

        it "Can retrieve Universal Sync status of a universal Service" -skip:(-not $universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType Application -objectId $universalSvc.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType Application -objectId $universalSvc.objectId
            $status | should not be $null
            $status.objectId | should be $universalSvc.objectId
        }

        it "Can retrieve Universal Sync status of a universal Service Group" -skip:(-not $universalSyncEnabled ) {
            { Get-NsxUniversalSyncStatus -objectType ApplicationGroup -objectId $universalSvcGrp.objectId } | should not throw
            $status = Get-NsxUniversalSyncStatus -objectType ApplicationGroup -objectId $universalSvcGrp.objectId
            $status | should not be $null
            $status.objectId | should be $universalSvcGrp.objectId
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