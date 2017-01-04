
# PowerNSX #

## About ##
PowerNSX is a PowerShell module that abstracts the VMware NSX API to a set of easily used PowerShell functions.

This module is _not supported_ by VMware, and comes with no warranties express or implied.  Please test and validate its functionality before using in a production environment.

It aims to focus on exposing New, Update, Remove and Get operations for all key NSX functions as well as adding additional functionality to extend the capabilities of NSX management beyond the native UI or API.  

PowerNSX is still a work in progress, and it is unlikely that it will ever expose 100% of the NSX API. Feature requests are welcome via the issues tracker on the projects GitHub page.

PowerNSX now has experimental PowerShell Core support available in the master (development) branch. Note that not all PowerNSX functions have been tested, and there are known issues (Remember, PowerShell Core and PowerCLI Core are both pre-release products as well.). See PowerNSX Core for details.

## Installing PowerNSX 

Installing PowerNSX is as simple as running the below onliner in a PowerCLI Window.  This will execute the PowerNSX installation script which will guide you through the installation of the latest stable release of PowerNSX.

```
$Branch="v2";$url="https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSXInstaller.ps1"; try { $wc = new-object Net.WebClient;$scr = try { $wc.DownloadString($url)} catch { if ( $_.exception.innerexception -match "(407)") { $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"; $wc.DownloadString($url) } else { throw $_ }}; $scr | iex } catch { throw $_ }
```

The development version of PowerNSX can be installed using the Update-PowerNsx cmdlet of v2 or via the following oneliner.  
_NOTE:  Live development occurs against this branch and should not be relied upon to be fully functional at all times.  You have been warned!_
```
Update-PowerNsx master
```
or 
```
$Branch="master";$url="https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSXInstaller.ps1"; try { $wc = new-object Net.WebClient;$scr = try { $wc.DownloadString($url)} catch { if ( $_.exception.innerexception -match "(407)") { $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"; $wc.DownloadString($url) } else { throw $_ }}; $scr | iex } catch { throw $_ }
```

The development version of PowerNSX can now be installed on PowerShell Core via the following oneliner.  
_NOTE:  PowerShell Core support is still experimental._
```
$pp = $ProgressPreference;$global:ProgressPreference = "silentlycontinue"; $Branch="master";$url="https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSXInstaller.ps1"; try { try { $response = Invoke-WebRequest -uri $url; $scr = $response.content } catch { if ( $_.exception.innerexception -match "(407)") { $credentials = Get-Credential -Message "Proxy Authentication Required"; $response = Invoke-WebRequest -uri $url -proxyCredential $credentials; $scr = $response.content } else { throw $_ }}; $scr | iex } catch { throw $_ };$global:ProgressPreference = $pp
```

See [Installing PowerNSX](https://github.com/vmware/powernsx/wiki/Installing-PowerNSX) for detailed Installation instructions.

## Using PowerNSX

Refer to the project [website](https://powernsx.github.io/) for detailed PowerNSX usage information.

## Contribution guidelines ##

Contribution and feature requests are more than welcome, please use the following methods:

  * For bugs and issues, please use the issues register with details of the problem.
  * For Feature Requests and bug reports, please use the issues register with details of what's required.
  * For code contribution (bug fixes, or feature requests), please fork PowerNSX, create a feature branch to do your development, and submit a pull request when your work is complete.
 
## Who do I talk to? ##

PowerNSX is a community based projected headed by some VMware staff. If you want to contribute please have a look at the issues page to see what is planned, requires triage, and to get started.

PowerNSX is an OpenSource project, and as such is not supported by VMware. Please feel free reach out to the team via the Issues page.

## Blog

Want to know what is new with PowerNSX? The team occasionally blogs [here](https://powernsx.github.io/blog/). Also, team member Anthony Burkes blog, where he posts a lot of useful usage information cant be found [here](http://networkinferno.net/tag/powernsx).

## Support

This module is opensource, and as such is _not supported by VMware_, and comes with no warranties express or implied. Please test and validate its functionality before using in a production environment.

Whist every endeavour is made to test functionality it is recommended that tools and scripts created with PowerNSX be validated and tested before using in production.

## License ##

PowerNSX is licensed under GPL v2

Copyright © 2015 VMware, Inc. All Rights Reserved.

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
