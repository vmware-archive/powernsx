# PowerNSX #

## About ##
PowerNSX is a PowerShell module that abstracts the VMware NSX API to a set of easily used PowerShell functions.

This module is _not supported_ by VMware, and comes with no warranties express or implied.  Please test and validate its functionality before using in a production environment.

It aims to focus on exposing New, Update, Remove and Get operations for all key NSX functions as well as adding additional functionality to extend the capabilities of NSX management beyond the native UI or API.  

It is unlikely that it will ever expose 100% of the NSX API, but feature requests are welcomed if you find a particular function you require to be lacking.

PowerNSX is currently a work in progress and is not yet feature complete. 

## Setup ##

PowerNSX requires PowerShell v3 or above, and requires PowerCLI (Recommend v6 and above) for full functionality.

The recommended method of using it is from within a PowerCLI session in conjunction with a PowerCLI connection established to the vCenter server that is registered to NSX.

To import the module and connect to vCenter and NSX, do the following:

* An execution policy allowing unsigned modules to be loaded is required (Required for PowerCLI as well).
* If you downloaded the module (as opposed to copy text and paste to a new file), you first have to 'unblock' it.  Locate the file, get properties and click 'Unblock'.  
* Start PowerCLI
* If you haven't already, set at least a RemoteSigned execution policy - Set-ExecutionPolicy RemoteSigned.  This only needs to be done once and you probably already did it for PowerCLI to work.
* import-module <path to PowerNSX.psm1>
* connect-viserver <vcenter hostname or ip> 
* connect-nsxserver <nsx manager hostname or ip>
* get-command -module PowerNSX  # List all functions exposed by PowerNSX.  These behave for the most part like native cmdlets and are pipeline aware
* get-help <PowerNSX function>  # all functions have basic documentation explaining the function and use.

### Contribution guidelines ###

* Feature requests are more than welcome, just dont get your hopes up.
* Patches are welcome for bugs/new functionality.

### Who do I talk to? ###

* Im just one guy but feel free to contact me at nbradford@vmware.com.