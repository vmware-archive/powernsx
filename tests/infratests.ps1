
$Name
$mgrIP = "192.168.100.189"
$DS = "Data"
$Cluster = "mgmt01"
$Folder = "CustA"
$PG = "Pri_Services"
$pwd = "VMware1!VMware1!"
$name = "testmanager"
$mask = "255.255.255.0"
$gw = "192.168.100.1"
$dns = "192.168.100.10"
$dnsdomain = "corp.local"
$ntp = "192.168.100.10"
$ovf = "C:\Users\Administrator\Downloads\VMware-NSX-Manager-6.2.0-2986609.ova"
$syslogip = "1.2.3.4"
$ssoServer = ""
$ssousername = "administrator@vsphere.local"
$ssopassword = "VMware1!"
$vcenterserver = $ssoServer
$vcusername= $ssousername
$vcpassword = $ssopassword



$mgrVM = New-NSXManager -NsxManagerOVF $ovf `
    -Name $Name -ClusterName $cluster -ManagementPortGroupName $PG -DatastoreName $DS -FolderName $folder `
    -CliPassword $pwd -CliEnablePassword $pwd -Hostname $name -IpAddress $mgrIp `
    -Netmask $mask -Gateway $gw -DnsServer $dns -DnsDomain $dnsdomain -NtpServer $ntp -EnableSsh

$mgrVm | set-vm -memoryGb 8 -confirm:$false | start-vm

#this enough?
start-sleep 60

#Initial Connection
$Connection = Connect-NsxServer -Server $mgrIp -username "admin" -Password $pwd -DisableVIAutoConnect -DefaultConnection:$false
Set-NsxManager -syslogserver $syslogip -connection $connection
#Set-NSxManager -ssoserver $ssoServer -ssousername $ssousername -ssopassword $ssopassword -connection $connection
#Set-NsxManager -vcenterusername $vcusername -vcenterpassword $vcpassword -vcenterserver $vcserver -connection $connection


read-host "Waiting for you to do something guv..."

$mgrVM | stop-vm -kill -confirm:$false
start-sleep 10
$mgrVM | remove-vm -DeletePermanently -confirm:$false
