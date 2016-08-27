
# PowerNSX #

## About ##
PowerNSX is a PowerShell module that abstracts the VMware NSX API to a set of easily used PowerShell functions.

This module is _not supported_ by VMware, and comes with no warranties express or implied.  Please test and validate its functionality before using in a production environment.

It aims to focus on exposing New, Update, Remove and Get operations for all key NSX functions as well as adding additional functionality to extend the capabilities of NSX management beyond the native UI or API.  

It is unlikely that it will ever expose 100% of the NSX API, but feature requests are welcomed if you find a particular function you require to be lacking.

PowerNSX remains a work in progress and is not yet feature complete. 

## Installing PowerNSX 

Installing PowerNSX is as simple as running the below onliner in a PowerCLI Window.  This will execute the PowerNSX installation script which will guide you through the installation.

```
$Branch="v2";$url="https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSXInstaller.ps1"; try { $wc = new-object Net.WebClient;$scr = try { $wc.DownloadString($url)} catch { if ( $_.exception.innerexception -match "(407)") { $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"; $wc.DownloadString($url) } else { throw $_ }}; $scr | iex } catch { throw $_ }
```

See the [Wiki](https://github.com/vmware/powernsx/wiki) for further Setup and Usage instructions.

## Contribution guidelines ##

Contribution and feature requests are more than welcome, please use the following methods:

  * For bugs and issues, please use the issues register with details of the problem.
  * For Feature Requests and bug reports, please use the issues register with details of what's required.
  * To contribute code, create a fork, make your changes and submit a pull request.
 
## Who do I talk to? ##

PowerNSX is a community supported project with support from various individuals at VMware. The right place to go to seek support if you have questions or problems using PowerNSX is the issues page. This includes known issues, usability questions, feature requests, bugs or related conversation.

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
