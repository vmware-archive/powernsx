

# Test harness to test modifications to PowerNSX module in vscode debugger.
# 1) Make sure https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell is installed in VSCode
# 2) Modify this script to perform functions required to exercise your code.
# 3) Set any breakpoints you need in PowerNSX module
# 4) Run a normal PowerShell debug session on this script
# Note: For some reason, you have to set a breakpoint on the last line of this script for all output to be shown in the debug output window.

#Make sure the user here knows we are doing something a bit dodgy
write-warning "Debug harness .VSCodeDebug.ps1 running.  Modify this file to exec PowerNSX functions you wish to debug."

# Import the module from the current dir (presumably the one you are modifying)
import-module .\PowerNsx.psd1

# Connect to NSX server - change as appopriate.
connect-nsxserver nsx-m-01a-local -username admin -password VMware1! -viusername administrator@vsphere.local -vipassword VMware1!

# Do something there to call the PowerNSX function you are testing.
New-NsxTransportZone TZ1 -Universal -Cluster (Get-Cluster mgmt01) -ControlPlaneMode UNICAST_MODE

# We need a breakpoint here... see note above...
write-host "Finished"
write-host "You must set a breakpoint on me or you will lose output, And, I wont be seen!"