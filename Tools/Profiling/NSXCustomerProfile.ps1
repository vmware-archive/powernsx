#customer NSX Environment Profiling tool
#Nick Bradford
#nbradford@vmware.com



#Copyright © 2015 VMware, Inc. All Rights Reserved.

#Permission is hereby granted, free of charge, to any person obtaining a copy of
#this software and associated documentation files (the "Software"), to deal in 
#the Software without restriction, including without limitation the rights to 
#use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
#of the Software, and to permit persons to whom the Software is furnished to do 
#so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all 
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
#SOFTWARE.

#requires -Version 3.0
#requires -Modules PowerNSX, PSScheduledJob

param (

    [Parameter (Mandatory=$false)] 
        [switch]$Interactive=$True,
    [Parameter (Mandatory=$false)]
        [switch]$Setup=$false


)


#Stuff that should be find for most Environments, but can be changed if really necessary...
$InstallPath = "$($env:ProgramData)\VMware\VMware NSX Support Utility"
$configFile = "$InstallPath\Config.json"
$PowerCLIInitScript = "$(${env:ProgramFiles(x86)})\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"
$TaskTimeOfDay = "6am"
$TaskDayOfWeek = "Sunday"


#########################################################################
# Do not modify below here.
$VMwareRecipient = "nbradford@vmware.com"

function new-config { 

    #Creates and populates the Config File and registers a scheduled task.

    write-host -foregroundcolor green "`n##################################################"
    write-host -ForegroundColor Green "`nVMware NSX Customer Profiling Tool Setup"

    #Storing creds and task creation rely on be able to decrypt the crypted passwords stored in the config file.  We all need to be one happy user for that...
    $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    write-warning "This setup process will store credentials securely so the Profiling script can be run non-interactively in the future.  All future use of this tool MUST be performed as $currentUser."

    If ( ( read-host "  Continue? (y/n)") -ne "y" ) { 
        throw "User Cancelled.  Rerun with -setup as desired user."
    }

    write-host

    #Confirm that user wants to create a scheduled task
    if (( Read-Host "  Create Scheduled Task to run profiling script once every week ($TaskTimeOfDay on $TaskDayOfWeek)? (y/n)") -eq "y" ) {

        if ( -not ( ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))) { 
            throw "Setup must be run as Administrator to create a scheduled task.  Rerun with -setup as an Administrator."
        }
        #Remove existing if it exists...
        Get-ScheduledJob 'VMware NSX Customer Profiling' -erroraction ignore | Unregister-ScheduledJob

        #Get credentials.  For whatever reason, the script was not executing correctly without it.  TS'ing scheduled task failures is 
        #one of the more frustrating things Ive had to do this decade...  This particular straw clutch made it work, though I suspect
        #more because of the action of decrypting passwords from file and converting to securestring objects as simple scheduled tasks
        #work fine without it...YMMV
        $CurrentUserPassword = Read-Host -AsSecureString "  Enter password for $currentUser for scheduled task credentials"
        $CreateTask = $True
    }
    else {
        $CreateTask = $False
    }

    if ( test-path $configFile ) {
        write-host 
        write-warning "Configuration file $configfile already exists.  Proceeding will overwrite existing configuration."
        if ( ( read-host "  Continue? (y/n)" ) -ne "y" ) {
            throw "Setup cancelled"
        }
    }

    #Gather connection details and test connection...
    $ConnectionTest = $false
    while ( -not $ConnectionTest )  { 

        write-host "`nConfiguring NSX and vSphere settings`n"
        $NSXManager = Read-Host "  NSX Manager IP or FQDN"
        $NSXUserName = Read-Host "  NSX Manager API username (Note:  This is not a vSphere login, and is usually just 'admin')"
        $NSXPassword = Read-Host -AsSecureString "  NSX Manager Password"
        $VIUserName = Read-Host "  vCenter Username"
        $VIPassword = Read-Host -AsSecureString "  vCenter Password"

        write-host "`n  Testing connection details..." 
        try {
            $NsxCredential = new-object -typename System.Management.Automation.PSCredential -argumentlist $NSXUsername, $NSXPassword
            $ViCredential = new-object -typename System.Management.Automation.PSCredential -argumentlist $VIUserName, $VIPassword
            $connection = Connect-NsxServer -Server $NSXManager -Credential $NsxCredential -VICred $ViCredential -Defaultconnection:$false -VIDefaultConnection:$false
            $ConnectionTest = $True
            disconnect-VIServer $connection.ViConnection -confirm:$false

        }
        catch {
            write-warning "PowerNSX connection failed. ($_)."
        }
    }

    #Gather email details and test with test-email.
    $emailTest = $false
    while ( -not $EmailTest ) {
        write-host "`nConfiguring Email settings`n"
        $Smtpserver = Read-Host "  SMTP Server (must allow unauthenticated relay, or credentials of user running script must be allowed to authenticate)"
        $From = Read-Host "  From Address"
        $To = Read-Host "  Local recipient (required)"

        write-host "`n  Sending test email..." 
        try {
            send-mailmessage -From $From -To $to -Smtpserver $Smtpserver -Subject "VMware NSX Customer Profiling Tool Test Email" -Body "Your email settings have been successfully configured." -ErrorAction Stop

            $EmailTest = $true
        }
        catch {
            write-warning "Test email failed to send ($_)."
        }
    }
    
    #Store configuration in config file.  The Password storage is secured with reversible decryption, meaning any person with access to $currentUser credentials can decrypt.
    $outobj = [pscustomobject]@{ 

        "nsxmanager" = $NSXManager;
        "nsxusername" = $NSXUserName;
        "nsxpassword" = ($NSXPassword | ConvertFrom-SecureString);
        "viusername" = $VIUserName;
        "vipassword" = ($VIPassword | ConvertFrom-SecureString);
        "smtpserver" = $smtpserver;
        "from" = $from;
        "to" = @(
            $To,
            $VMwareRecipient
        )
    }

    $outobj | ConvertTo-Json | set-content $configFile

    #Create a scheduled task if user indicated it...
    if ( $CreateTask ) {

        #Set up Scheduled Task to automate profile gathering.  Gunna comment the crap outa this, coz it took ages to get working and is not so obvious!  Im sure Ill be back here one day :|
        $TaskSuccess = $False
            while ( -not $TaskSuccess ) { 
            try {

                write-host "`nCreating Scheduled Task`n"

                #Credential seemed to be required - I suspect due to the use of convertto-securestring to import encrypted passwords from file, rather
                #than being needed to allow the task to run itself...
                $taskCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $CurrentUser, $CurrentUserPassword

                #Its all in this line...
                # 1- Command needs to be a scriptblock.  You cant create one with the normal {} otherwise variable expansion is supressed within the braces.
                # 2 - the & is PoSHes call function.  Run this Sh1t rather than treat it as a string object.
                # 3 - Need to load PowerCLI env.  Using the init script that comes with PowerCLI is required as technically this would work with PowerCLI 5.5 as well... not tested... Dont want to assume we can just #requires the modules in as 5.5 is snapin based...May work  with initscript param to register-scheduledjob
                # 4 - The actual scriptnames may contain spaces, and the quotes enclosing them need to be escaped so that they get passed to the actual command block in the resulting task.  The $ before the False needs to be escaped as well so it ends up there too.
                # 5 - It seems so simple now Im explaining it to myself... :|  Hours...
                # 6 - If you are trying to TS this crap:
                #   -  $job = Get-ScheduledJob; $job.command looks like this : & "C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"; & "C:\ProgramData\VMware\VMware NSX Support Utility\NSXCustomerProfile.ps1" -interactive:$False
                #   - $result = $job.Run() to attempt exec.
                #   - $result.ChildJobs.jobstateinfo and  $result.ChildJobs.Error are quite enlightening and cant be seen from the Tasks UI...
                $command = [ScriptBlock]::Create("& `"$PowerCLIInitScript`"; & `"$($MyInvocation.ScriptName)`" -interactive:`$False")

                #Then create it, which is easy...
                $trigger =  New-JobTrigger -Weekly -At $TaskTimeOfDay -DaysOfWeek $TaskDayOfWeek
                $job = Register-ScheduledJob -ScriptBlock $command -Trigger $trigger -Name "VMware NSX Customer Profiling" -credential $taskCred
                $TaskSuccess = $true
            }
            catch {

                #Give user option to try again...
                write-warning "Scheduled Task Creation Failed ($_)."
                if ( ( read-host "Try again? (y/n)") -ne "y" ) {
                    $TaskSuccess = $True
                }
            }
        }
    }
    else {

        Write-Warning "NSX Profile gathering will not be automatic and VMware will be sad.  Rerun this script with -setup switch to configure a scheduled task to make them happy."

    }

    write-host -ForegroundColor Green "`nSetup completed successfully.  You may rerun setup at any time by specifying the -setup switch."
}

function Get-Config {

    $inobj = Get-Content -raw $configFile | ConvertFrom-Json
    if ( -not 
        ( $inobj | Get-Member -MemberType Property -Name nsxmanager) -and
        ( $inobj | Get-Member -MemberType Property -Name smtpserver) -and
        ( $inobj | Get-Member -MemberType Property -Name from) -and
        ( $inobj | Get-Member -MemberType Property -Name to) -and
        ( $inobj | Get-Member -MemberType Property -Name nsxusername) -and
        ( $inobj | Get-Member -MemberType Property -Name nsxpassword) -and
        ( $inobj | Get-Member -MemberType Property -Name viusername) -and
        ( $inobj | Get-Member -MemberType Property -Name vipassword)
    ) { Throw "Config File content is invalid.  Rerun script with -setup switch to correct."}

    $global:NSXManager = $inobj.nsxmanager
    $global:Smtpserver = $inobj.smtpserver
    $global:From = $inobj.from
    $global:To = $inobj.to
    $global:NsxCredential = new-object -typename System.Management.Automation.PSCredential -argumentlist $inobj.nsxusername, ($inobj.nsxpassword | ConvertTo-SecureString)
    $global:ViCredential = new-object -typename System.Management.Automation.PSCredential -argumentlist $inobj.viusername, ($inobj.vipassword | ConvertTo-SecureString)

}

function get-answers {


    do {
        $custname = Read-host "Customer Name"
        $NSBUOwner = Read-host "VMware NSBU Owner (e.g. Solution Architect, TAM, SE etc.)"
        $ProdStatus = Read-host "Production Status (e.g. Prod, Limited Production, Pre Production, Non Production)"
        $PrimUseCase = Read-Host "Primary Use Case (e.g. Microsegmentation, 3rd Party Service Insertion, DC Extension, Network Virtualisation etc.)"
        $SecUseCase =  Read-Host "Secondary Use Case (e.g. Microsegmentation, 3rd Party Service Insertion, DC Extension, Network Virtualisation etc.)"
        $CMP = Read-Host "Consumption Method (e.g. None, vRealize Automation, Openstack, Cloudstack, vCloudDirector etc.)"

        write-host

        $inkey = read-host "Are you happy with these answers? (y/n)"
        while ( $inkey -notmatch "[yn]" ) {
            $inkey = read-host "Are you happy with these answers? (y/n)"
        }    
    } while ( $inkey -ne "y")


    $return = new-object psobject
    $return | add-member -membertype NoteProperty -name CustomerName -Value $custname
    $return | add-member -membertype NoteProperty -name NSBUOwner -Value $NSBUOwner
    $return | add-member -membertype NoteProperty -name ProductionStatus -Value $ProdStatus
    $return | add-member -membertype NoteProperty -name PrimaryUseCase -Value $PrimUseCase
    $return | add-member -membertype NoteProperty -name SecondaryUseCase -Value $SecUseCase
    $return | add-member -membertype NoteProperty -name ConsumptionMethod -Value $CMP

    $return
}


function new-answerfile {


    #precreates the necessary properties in the output file.
    "" | select Date, CustomerName, NSBUOwner, ProductionStatus, PrimaryUseCase, SecondaryUseCase, 
        ConsumptionMethod, TotalHosts, TotalVMs, PreparedHosts, DFWEnabledHosts, 
        VXLANEnabledHosts, NsxVms, LogicalSwitches, LogicalRouters, EdgeServiceGateways, 
        DFWRules, SecurityGroups, SecurityPolicies, ThirdPartyIntegrations, edgeL2VPNCount, edgeFirewall, edgeDns, edgeSSLVPN, edgerouting, edgeHA, 
        edgeSyslog, edgeLoadBalancer, edgeGsLB, edgeIPsec, edgeDhcp, edgeNat,
        edgeBridge, dlrFirewall, dlrrouting, dlrHA, dlrSyslog, dlrDhcp, 
        dlrBridge | export-csv -confirm:$false -force -NoTypeInformation $answerfile


}

function Get-CustomerProfile {


    write-host "`nTo provide better context around the information being gathered, some basic"
    write-host "free-form questions have to be answered first.  Responses to these will be "
    write-host "saved so future runs of this tool can be completely automatic."

    #Counter init
    $PreparedHostCount = 0
    $DFWHostCount = 0
    $VXLANHostCount = 0
    $PreparedHostVMCount = 0 
    $DFWHostVMCount = 0
    $VXLANHostVMCount = 0

    $edgeL2VPNCount = 0
    $edgeFirewall = 0
    $edgeDns = 0
    $edgeSSLVPN = 0
    $edgerouting = 0
    $edgeHA = 0
    $edgeSyslog = 0
    $edgeLoadBalancer = 0
    $edgeGsLB = 0
    $edgeIPsec = 0
    $edgeDhcp = 0
    $edgeNat = 0
    $edgeBridge = 0

    $TotalHostCount = 0 
    $TotalVMCount = 0
    $TotalLSCount = 0
    $TotalDLRCount = 0
    $TotalEdgeCount = 0
    $TotalRuleCount = 0
    $TotalSGCount = 0
    $TotalSPCount = 0

    $dlrFirewall = 0
    $dlrrouting = 0
    $dlrHA = 0
    $dlrSyslog = 0
    $dlrDhcp = 0
    $dlrBridge = 0

    if ( (-not (test-path $configFile ))){

        new-config

    }

    if (-not (test-path $answerfile )) {

        new-answerfile
        $results = get-answers

    }
    else {

        $responses = import-csv $answerfile

        if ( $Interactive ) { 
            if ( $responses ) { 

                write-host 
                write-host -foregroundColor Green "The following details were used in the previous run of this tool."
                write-host

                $responses | select -last 1 | select CustomerName, NSBUOwner, ProductionStatus, PrimaryUseCase, SecondaryUseCase, ConsumptionMethod | format-list
                $inkey = read-host "Do you want to update these answers? (y/n)"
                while ( $inkey -notmatch "[yn]" ) {
                    $inkey = read-host "Do you want to update these answers? (y/n)"
                }

                switch ( $inkey ) {

                    "y" { 
                        $results = get-answers
                        
                    }
                    default { 
                        write-host -foregroundColor Yellow "Using previous responses from $answerfile."
                        $results = $responses | select -last 1 | select CustomerName, NSBUOwner, ProductionStatus, PrimaryUseCase, SecondaryUseCase, ConsumptionMethod
                    }
                
                }
            }
            else {

                #answerfile exists but was empty?
                new-answerfile
                $results = get-answers 

            }
        }
        else {

            write-warning "Running in non interactive mode."

            if ( -not $responses ) {
                #Nothing in previous file 
                new-answerfile
                $results = "" | select CustomerName, NSBUOwner, ProductionStatus, PrimaryUseCase, SecondaryUseCase, ConsumptionMethod
                $results.CustomerName = "Run script interactively at least once to populate free form fields."
            }
            else {
                $results = $responses | select -last 1 | select CustomerName, NSBUOwner, ProductionStatus, PrimaryUseCase, SecondaryUseCase, ConsumptionMethod

            }
        }
    }


    #Lets do some stuff now
    write-host
    write-host -foregroundColor Green "Profiling environment.  Please wait."
    write-host

    #Get Date...
    $Date = 
    $results | add-member -membertype NoteProperty -Name Date -Value $(get-date).tolongdatestring()


    #Get total Host count
    write-host -nonewline " - Getting total Host count..."
    try { 
        $TotalHostCount = (get-vmhost | measure).count
        write-host -foregroundColor Green "Ok. ($TotalHostCount)"
    }
    catch {
        $TotalHostCount = -1
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name TotalHosts -Value $TotalHostCount

    #Get total VM count
    write-host -nonewline " - Getting total VM count..."
    try { 

        $TotalVMCount = (get-vm | measure ).count
        write-host -foregroundColor Green "Ok. ($TotalVMCount)"
    }
    catch {
        $TotalVMCount = -1
        write-host -foregroundColor Red "Failed.  $_"

    }
    $results | add-member -membertype NoteProperty -Name TotalVMs -Value $TotalVMCount

    



    #Get NSX resource status of each cluster.
    get-cluster | % { 
        $CurrentCluster = $_
        $ClustPreparedHostCount = 0
        $ClustPreparedHostVMCount = 0 
        $ClustDFWHostCount = 0
        $ClustDFWHostVMCount = 0
        $ClustVXLANHostCount = 0
        $ClustVXLANHostVMCount = 0
        $Prepped = $False
        $DFW = $False
        $VXLAN = $False

        write-host -nonewline " - Retreiving NSX resource status for cluster $CurrentCluster..."
        try {
            $clusterstatus = $_ | Get-NsxClusterStatus
            
            #hostprep installed property tracks if the cluster has been prepped for NSX (vib install and auto enable DFW)
            if ( ($clusterstatus | ? { $_.featureId -eq "com.vmware.vshield.vsm.nwfabric.hostPrep" }).installed -eq "true" ) {
                $ClustPreparedHostCount = ( $CurrentCluster | get-vmhost | measure).count 
                $ClustPreparedHostVMCount = ( $CurrentCluster | get-vm | measure).count
                $PreparedHostCount += $ClustPreparedHostCount
                $PreparedHostVMCount += $ClustPreparedHostVMCount
                $Prepped = $true
                
            }

            #for firewall to be active, feature must be installed and enabled. 
            if ( 
                (($clusterstatus | ? { $_.featureId -eq "com.vmware.vshield.firewall" }).installed -eq "true" ) -and 
                (($clusterstatus | ? { $_.featureId -eq "com.vmware.vshield.firewall" }).enabled -eq "true" )
            ) {
                $ClustDFWHostCount = ( $CurrentCluster | get-vmhost | measure).count 
                $ClustDFWHostVMCount = ( $CurrentCluster | get-vm | measure).count 
                $DFWHostCount += $ClustDFWHostCount
                $DFWHostVMCount += $ClustDFWHostVMCount
                $DFW = $true
            }

            #Check for VXLAN configured.
            if (             
                (($clusterstatus | ? { $_.featureId -eq "com.vmware.vshield.vsm.vxlan" }).installed -eq "true" ) -and 
                (($clusterstatus | ? { $_.featureId -eq "com.vmware.vshield.vsm.vxlan" }).enabled -eq "true" )
            ) {
                $ClustVXLANHostCount = ( $CurrentCluster | get-vmhost | measure).count 
                $ClustVXLANHostVMCount = ( $CurrentCluster | get-vm | measure).count 
                $VXLANHostCount += $ClustVXLANHostCount
                $VXLANHostVMCount += $ClustVXLANHostVMCount
                $VXLAN = $true

            }
            write-host -foregroundColor Green "Ok. (Cluster Prepared: $Prepped, DFW Enabled: $DFW, VXLAN Configured: $VXLAN)"
        }
        catch {
            write-host -foregroundColor Red "Failed: $_"
        }
    }

    $results | add-member -membertype NoteProperty -Name PreparedHosts -Value $PreparedHostCount
    $results | add-member -membertype NoteProperty -Name DFWEnabledHosts -Value $DFWHostCount
    $results | add-member -membertype NoteProperty -Name VXLANEnabledHosts -Value $VXLANHostCount
    $results | add-member -membertype NoteProperty -Name NsxVms -Value $PreparedHostVMCount
   
    #Get number of Logical Switches
    write-host -nonewline " - Getting Logical Switch count..."
    try { 
        $TotalLSCount = (get-nsxtransportzone | get-nsxlogicalswitch | measure).count
        write-host -foregroundColor Green "Ok. ($TotalLSCount)"
    }
    catch {
        $TotalLSCount = -1
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name LogicalSwitches -Value $TotalLSCount

    #Get number of DLR
    write-host -nonewline " - Getting Logical Router count..."
    try { 
        $dlrs = get-nsxLogicalRouter
        $TotalDLRCount = ($dlrs | measure).count
        write-host -foregroundColor Green "Ok. ($TotalDLRCount)"

        write-host -nonewline " - Getting DLR Services in use..."

        $dlrs | % { 

            if ( $_.features.firewall.enabled -eq 'true' ) { $dlrFirewall += 1 } 
            if ( $_.features.routing.enabled -eq 'true' ) { $dlrrouting += 1 } 
            if ( $_.features.highAvailability.enabled -eq 'true' ) { $dlrHA += 1 } 
            if ( $_.features.syslog.enabled -eq 'true' ) { $dlrSyslog += 1 } 
            if ( $_.features.dhcp.enabled -eq 'true' ) { $dlrDhcp += 1 } 
            if ( $_.features.bridges.enabled -eq 'true' ) { $dlrBridge += 1 } 

        }

        write-host -foregroundColor Green "Ok."
        write-host "   - DLR Firewall Count : $dlrFirewall"
        write-host "   - DLR Routing Count : $dlrrouting"
        write-host "   - DLR HA Count : $dlrHA"
        write-host "   - DLR Syslog Count : $dlrSyslog"
        write-host "   - DLR DHCP L2 VPN Count : $dlrDhcp"
        write-host "   - DLR Bridge Count : $dlrBridge"

    }
    catch {
        $TotalDLRCount = -1
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name LogicalRouters -Value $TotalDLRCount
    $results | add-member -membertype NoteProperty -Name dlrFirewall -Value $dlrFirewall
    $results | add-member -membertype NoteProperty -Name dlrrouting -Value $dlrrouting
    $results | add-member -membertype NoteProperty -Name dlrHA -Value $dlrHA
    $results | add-member -membertype NoteProperty -Name dlrSyslog -Value $dlrSyslog
    $results | add-member -membertype NoteProperty -Name dlrDhcp -Value $dlrDhcp
    $results | add-member -membertype NoteProperty -Name dlrBridge -Value $dlrBridge
    
    #Get number of ESG
    write-host -nonewline " - Getting Edge Service Gateway count..."
    try { 

        $edges = Get-NSxEdge
        $TotalEdgeCount = ($edges | Measure).count
        write-host -foregroundColor Green "Ok. ($TotalEdgeCount)"

        write-host -nonewline " - Getting Edge Services in use..."


        $edges | % { 

            if ( $_.features.l2Vpn.enabled -eq 'true' ) { $edgeL2VPNCount += 1 }       
            if ( $_.features.firewall.enabled -eq 'true' ) { $edgeFirewall += 1 } 
            if ( $_.features.dns.enabled -eq 'true' ) { $edgeDns += 1 } 
            if ( $_.features.sslvpnConfig.enabled -eq 'true' ) { $edgeSSLVPN += 1 } 
            if ( $_.features.routing.enabled -eq 'true' ) { $edgerouting += 1 } 
            if ( $_.features.highAvailability.enabled -eq 'true' ) { $edgeHA += 1 } 
            if ( $_.features.syslog.enabled -eq 'true' ) { $edgeSyslog += 1 } 
            if ( $_.features.loadBalancer.enabled -eq 'true' ) { $edgeLoadBalancer += 1 } 
            if ( $_.features.gslb.enabled -eq 'true' ) { $edgeGsLB += 1 } 
            if ( $_.features.ipsec.enabled -eq 'true' ) { $edgeIPsec += 1 } 
            if ( $_.features.dhcp.enabled -eq 'true' ) { $edgeDhcp += 1 } 
            if ( $_.features.nat.enabled -eq 'true' ) { $edgeNat += 1 } 
            if ( $_.features.bridges.enabled -eq 'true' ) { $edgeBridge += 1 } 

        }

        write-host -foregroundColor Green "Ok."
        write-host "   - Edge L2 VPN Count : $edgeL2VPNCount"
        write-host "   - Edge Firewall Count : $edgeFirewall"
        write-host "   - Edge DNS Count : $edgeDns"
        write-host "   - Edge SSLVPN Count : $edgeSSLVPN"
        write-host "   - Edge Routing Count : $edgerouting"
        write-host "   - Edge HA Count : $edgeHA"
        write-host "   - Edge Syslog Count : $edgeSyslog"
        write-host "   - Edge LB  Count : $edgeLoadBalancer"
        write-host "   - Edge GSLB Count : $edgeGsLB"
        write-host "   - Edge IPSec Count : $edgeIPsec"
        write-host "   - Edge DHCP Count : $edgeDhcp"
        write-host "   - Edge NAT Count : $edgeNat"
        write-host "   - Edge Bridge Count : $edgeBridge"
    }
    catch {
        $TotalEdgeCount = -1
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name EdgeServiceGateways -Value $TotalEdgeCount
    $results | add-member -membertype NoteProperty -Name edgeL2VPNCount -Value $edgeL2VPNCount
    $results | add-member -membertype NoteProperty -Name edgeFirewall -Value $edgeFirewall
    $results | add-member -membertype NoteProperty -Name edgeDns -Value $edgeDns
    $results | add-member -membertype NoteProperty -Name edgeSSLVPN -Value $edgeSSLVPN
    $results | add-member -membertype NoteProperty -Name edgerouting -Value $edgerouting
    $results | add-member -membertype NoteProperty -Name edgeHA -Value $edgeHA
    $results | add-member -membertype NoteProperty -Name edgeSyslog -Value $edgeSyslog
    $results | add-member -membertype NoteProperty -Name edgeLoadBalancer -Value $edgeLoadBalancer
    $results | add-member -membertype NoteProperty -Name edgeGsLB -Value $edgeGsLB
    $results | add-member -membertype NoteProperty -Name edgeIPsec -Value $edgeIPsec
    $results | add-member -membertype NoteProperty -Name edgeDhcp -Value $edgeDhcp
    $results | add-member -membertype NoteProperty -Name edgeNat -Value $edgeNat
    $results | add-member -membertype NoteProperty -Name edgeBridge -Value $edgeBridge


    #Get number of DFW Rules
    write-host -nonewline " - Getting DFW Rule count..."
    try { 
        $TotalRuleCount = (get-nsxfirewallsection | get-nsxfirewallrule | measure ).count
        write-host -foregroundColor Green "Ok. ($TotalRuleCount)"
    }
    catch {
        $TotalRuleCount = -1
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name DFWRules -Value $TotalRuleCount
    
    #Get number of Security Groups
    write-host -nonewline " - Getting Security Group count..."
    try { 
        $TotalSGCount = (get-nsxsecuritygroup | measure ).count
        write-host -foregroundColor Green "Ok. ($TotalSGCount)"
    }
    catch {
        $TotalSGCount = -1
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name SecurityGroups -Value $TotalSGCount
    

    #Get number of Security Policies
    write-host -nonewline " - Getting Security Policies count..."
    try { 
        $TotalSPCount = (get-NsxSecurityPolicy | measure ).count
        write-host -foregroundColor Green "Ok. ($TotalSPCount)"
    }
    catch {
        $TotalSPCount = -1
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name SecurityPolicies -Value $TotalSPCount


    #Get 3rdParty Integration in use
    write-host -nonewline " - Getting 3rd Party Integration in use..."
    try { 
        
        $Uri = "/api/2.0/si/deploy"
        $response = Invoke-NsxRestMethod -uri $uri -method "get"
        $services = $response.deployedServices.deployedService | Sort-Object -Unique -Property service-id
        $ServiceNames = ""
        foreach ( $service in $Services) {  $ServiceNames += "$($service.serviceName), " }      
        write-host -foregroundColor Green "Ok. ($ServiceNames)"
  
    }
    catch {
        write-host -foregroundColor Red "Failed.  $_"
    }
    $results | add-member -membertype NoteProperty -Name ThirdPartyIntegrations -Value $ServiceNames


    #Finished - Save results to file
    write-host 
    write-host -foregroundColor Yellow "Saving responses to $answerfile..."
    $results | export-csv $answerfile -append -noTypeInformation

    if ( $Interactive ) { 
        #Prompt to open file?
        $inkey = read-host "Do you want to (o)pen the response file or (v)iew it in Explorer? (o/v/n)"
        while ( $inkey -notmatch "[ovn]" ) {
            $inkey = read-host "Do you want to (o)pen the response file or (v)iew it in Explorer? (o/v/n)"
        }

        switch ( $inkey ) {

            "o" { 
                $answerfile | iex 
            }
            "v" { 
                "explorer $(split-path $answerfile)" | iex        
            }
        }
    }

    write-host -ForeGroundColor Green "Collection complete, sending email."

    send-mailmessage -From $From -To $to -Smtpserver $Smtpserver -Subject "VMware NSX Customer Profiling Tool Update - $($Results.CustomerName)" -Body "New profiling results for $($Results.CustomerName)" -ErrorAction Stop -attachments $answerfile


}



if ( $Setup ) {
    new-config
    
}
else {

    write-host -foregroundcolor green "`n##################################################"
    write-host -foregroundColor Green "`nVMware NSX Customer Profiling Tool"
    write-host "`nThis tool automates the process of gathering profile information"
    write-host "about an NSX customer.  It is designed to capture a basic snapshot"
    write-host "of what NSX features are configured in a given environment.  All reporting is done"
    write-host "via a CSV file that is generated by the script which is then emailed"
    write-host "to your friendly VMware NSBU representative."


    if ( -not (test-path $configFile )) {
        write-host -ForegroundColor Green "`nRunning first time setup...`n"
        new-config
    }

    try {
        Get-Config 
        write-host -ForegroundColor Green "`nConnecting to NSX Manager and vCenter Server."
        $connection = Connect-NsxServer -Server $NSXManager -Credential $NsxCredential -VICred $ViCredential
    }
    catch {
        Throw "Unable to connect to NSX.  $_"
    }

    $answerfile = "$InstallPath\CustomerProfileAnswers-$($Connection.Credential.UserName)@$($Connection.Server).csv"

    Get-CustomerProfile
    disconnect-VIServer $connection.ViConnection  -confirm:$false
    disconnect-nsxserver

}