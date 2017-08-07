## NSX LB AutoScale
## Author: Dimitri Desmidt
## version 1.0
## August 2017

###
# This PowerShell script offers Auto Scaling of your application.
# Your application is running on servers ($VM_PrefixName + $VM_Clone_PrefixName)
# When those servers are heavily loaded ($CPU_Max or $RAM_Max) and are less than $VM_Max
#   The script deploys one new VM from vCenter template  ($VM_Template)
#   and adds that new VM in NSX LB Pool ($Edge_Name, $LB_Pool_Name)
# When those servers are lightly loaded ($CPU_Min or $RAM_Min) and more than $VM_Min,
#   The script removes one VM from NSX LB Pool ($Edge_Name, $LB_Pool_Name)
#   and removes that VM from vCenter
#
# Go to section "Define Variables for NSX LB AutoScale script" and enter your environment settings
#
# Enhancement TODO
# Drain Option: "Clone_VM drained from the pool" + "pause" + "delete"
###

# To allow the launch of that script in Windows Tasks "powershell.exe -file C:\NSXLBAustoScale-v1.0.ps1"
add-pssnapin VMware.VimAutomation.Core


<#
Copyright © 2017 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more details.

You should have received a copy of the General Public License version 2 along with this program.
If not, see https://www.gnu.org/licenses/gpl-2.0.html.

The full text of the General Public License 2.0 is provided in the COPYING file.
Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.”
#>


###
# Define Variables for NSX LB AutoScale script
###
# vCenter IP / User / Password
$vCenter_IP = "192.168.10.4"
$vCenter_User = "administrator@vsphere.local"
$vCenter_Pwd = "VMware1!"
# vCenter Cluster where new Clone_VM will be deployed
$Cluster_Compute_Name = "Cluster-CompA"

# NSX_Mgr IP / User / Password
$NSX_IP = "192.168.10.5"
$NSX_User = "admin"
$NSX_Pwd = "vmware"

# Name of the VM template to clone + Prefix Name of the VM Names of LB Pool + Name of Clone VM
$VM_Template = "Web-Template"
$VM_PrefixName = "Web0"
$VM_Clone_PrefixName = "Web_Clone"

# LB information
# How many pool members Minimum / Maximum
$VM_Min = 2
$VM_Max = 3
# Edge Name / Pool Name
$Edge_Name = "LB1"
$Edge_VIP = "VIP1"
$LB_Pool_Name = "NSXLBAutoScale-Pool"
$LB_Pool_Port = 80
# CPU_Max, RAM_Max, CPU_Min, RAM_Min that will trigger AutoScale (create VM / delete VM)
$CPU_Max = 80
$RAM_Max = 80
$CPU_Min = 20
$RAM_Min = 20
# When load decrease, do you want to drain connections before deleting Pool Member and for how long in minute (only available for L4-VIP).
$VM_Drain = $false
$VM_Drain_Timer = 1

# File to write the log output
$Output_File = "C:\NSXLBAutoScale.log"
  # Note: To "tail -f" in PowerShell "Get-Content .\NSXLBAutoScale.log -Wait"


###
# Do Not modify below this line! :)
###
# Set variables
$allvms = @()
$clone_vm = $false
$vm_not_hot = 0

# Connect to vCenter + NSX
Connect-NsxServer -Server $NSX_IP -Username $NSX_User -Password $NSX_Pwd -VIUserName $vCenter_User -VIPassword $vCenter_Pwd -ViWarningAction "Ignore"

# Print the date in the file
"##############################################" >> $Output_File
Get-Date >> $Output_File

# Get all Pool_VMs powered on
$vms_base = Get-Vm -Name "$VM_PrefixName*" |Where-object {$_.powerstate -eq "PoweredOn"}
$vms_clone = Get-Vm -Name "$VM_Clone_PrefixName*" |Where-object {$_.powerstate -eq "PoweredOn"}
$vms_total = $vms_base + $vms_clone
# Count all Pool_VMs powered on
$number_vms = ($vms_total | Measure-Object).count


# For each Pool_VM powered on, check its CPU + RAM
foreach($vm in $vms_total) {
  $vmstat = "" | Select VmName, CPUAvg, MemAvg
  $vmstat.VmName = $vm.name
  
  $statcpu = Get-Stat -Entity ($vm) -IntervalMins 1 -MaxSamples 5 -stat cpu.usage.average
  $statmem = Get-Stat -Entity ($vm) -IntervalMins 1 -MaxSamples 5 -stat mem.usage.average

  $cpu = $statcpu | Measure-Object -Property value -Average
  $mem = $statmem | Measure-Object -Property value -Average

  $vmstat.CPUAvg = $cpu.Average
  $vmstat.MemAvg = $mem.Average

# If CPU or RAM above $CPU_Max/$RAM_Max, ask to create a new Pool_VM
  if (($vmstat.CPUAvg -gt $CPU_Max) -or ($vmstat.MemAvg -gt $RAM_Max)) {
    $clone_vm = $true
  }
# If CPU and RAM below $CPU_Min/$RAM_Min, ask to create a new Pool_VM
  if (($vmstat.CPUAvg -lt $CPU_Min) -and ($vmstat.MemAvg -lt $RAM_Min)) {
    $vm_not_hot += 1
  }
$allvms += $vmstat
}
write-host -foregroundcolor "Green" "List of Pool_VM Servers: $($allvms | Format-Table | Out-String)"
"List of Pool_VM Servers: $($allvms | Format-Table | Out-String)" >> $Output_File 
  

# If less than $VM_Min Pool_VMs AND asked to Clone_VM, THEN Create new Clone_VM + Add to LB_Pool
if (($number_vms -lt $VM_Max) -and ($clone_vm -eq $true)) {
  # Get Pool_VM Template
  $vm_template = Get-Template -Name $VM_Template
  # vCenter Cluster where new Pool_VM will be deployed
  $cluster_compute = get-cluster $Cluster_Compute_Name
  # Create new Pool_VM
  $new_vm = "$VM_Clone_PrefixName$($number_vms-$VM_Min+1)"
  write-host -foregroundcolor "Green" "Adding new Clone_VM $new_vm..."
  "Adding new Clone_VM $new_vm..." >> $Output_File 
  $vmhost = $cluster_compute | Get-vmhost | Sort MemoryUsageGB | Select -first 1
  New-VM -Name $new_vm -Template $vm_template -vmhost $vmhost
  Start-VM -VM $new_vm
  
  # Add Clone_VM to NSX Edge LB Pool
  # Wait for the VMTools to get the IP@ of the Clone_VM
  write-host -foregroundcolor "Green" "Waiting for VMTools to get new Pool VM IP@..."
  "Waiting for VMTools to get new Pool VM IP@" >> $Output_File 
  while (!(Get-VM -Name $new_vm).guest.ipaddress) {
    Start-Sleep -s 1
  }
  write-host -foregroundcolor "Green" "Adding new Clone_VM $new_vm in NSX Edge $Edge_Name Pool $LB_Pool_Name..."
  "Adding new Clone_VM $new_vm in NSX Edge $Edge_Name Pool $LB_Pool_Name..." >> $Output_File 
  # Get the IP-v4 of the Clone_VM
  $new_vm_ip = (Get-VM -Name $new_vm).guest.ipaddress[0]
  # Add the Clone_VM in the NSX LB Pool
  $lb_pool = Get-NsxEdge $Edge_Name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -name $LB_Pool_Name
  $lb_pool = $lb_pool | Add-NsxLoadBalancerPoolMember -name $new_vm -IpAddress $new_vm_ip -Port $LB_Pool_Port
}


# If more than $VM_Min Pool_VMs AND asked to remove Pool_VM, THEN delete Pool_VM
if (($number_vms -gt $VM_Min) -and ($number_vms -eq $vm_not_hot)) {
  $remove_vm = "$VM_Clone_PrefixName$($number_vms-$VM_Min)"
  # Check if option VM_Drain enabled, and if so Drain Pool_VM for VM_Drain_Timer
  if ($VM_Drain) {
     if ((Get-NsxEdge $Edge_Name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVIP -name $Edge_VIP).accelerationEnabled) {
       # Add the code for Drain with PowerNSX supports it       
     } else {
       write-host -foregroundcolor "Green" "Did NOT move the Clone_VM $remove_vm to Drain State before removing it from pool, because the VIP is with acceleration enabled."
       "Did NOT move the Clone_VM $remove_vm to Drain State before removing it from pool, because the VIP is with acceleration enabled." >> $Output_File
     }
  }
  # Delete the Clone_VM in the NSX LB Pool
  write-host -foregroundcolor "Green" "Removing Clone_VM $remove_vm in NSX Edge $Edge_Name Pool $LB_Pool_Name..."
  "Removing Clone_VM $remove_vm in NSX Edge $Edge_Name Pool $LB_Pool_Name..." >> $Output_File 
  $lb_pool = Get-NsxEdge $Edge_Name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -name $LB_Pool_Name
  $lb_pool = $lb_pool | Get-NsxLoadBalancerPoolMember $remove_vm | remove-nsxLoadbalancerPoolMember -confirm:$false
  # Delete the Clone_VM in the NSX LB Pool
  write-host -foregroundcolor "Green" "Deleting Clone_VM $remove_vm..."
  "Deleting Clone_VM $remove_vm ..." >> $Output_File 
  Stop-VM -VM $remove_vm -Confirm:$false
  Remove-VM -VM $remove_vm -DeletePermanently -Confirm:$false
}




