---
layout: default
---

# PowerNSX #
# A Powershell module for NSX for vSphere #

PowerNSX is a PowerShell module that abstracts the VMware NSX API to a set of easily used PowerShell functions.

This module is not supported by VMware, and comes with no warranties express or implied. Please test and validate its functionality before using in a production environment.

It aims to focus on exposing New, Update, Remove and Get operations for all key NSX functions as well as adding additional functionality to extend the capabilities of NSX management beyond the native UI or API.  

PowerNSX works closely with VMware PowerCLI, and PowerCLI users will feel quickly at home using PowerNSX.  Together these tools provide a comprehensive command line environment for managing your VMware NSX for vSphere environments.

PowerNSX is still a work in progress, and it is unlikely that it will ever expose 100% of the NSX API.  Feature requests are welcome via the issues tracker on the projects github page.

PowerNSX functionality covers the following key areas:

* NSX Manager setup
* Host Preparation
* Logical Switching
* Logical Routing
* NSX Edge Gateway
* Dynamic Routing
* Distributed Firewall
* Service Composer
* NSX Edge Load Balancer
* NSX Edge SSL VPN

# Is PowerNSX supported?

This module is _not supported_ by VMware, and comes with no warranties express or implied.  Please test and validate its functionality before using in a production environment.

Whist every endeavor is made to test functionality it is recommended that tools and scripts created with PowerNSX be validated and tested before using in production.

# Contribution guidelines #

Contribution and feature requests are more than welcome, please use the following methods:

  * For bugs and [issues](https://github.com/vmware/powernsx/issues), please use the [issues](https://github.com/vmware/powernsx/issues) register with details of the problem.
  * For Feature Requests, please use the [issues](https://github.com/vmware/powernsx/issues) register with details of what's required.
  * For code contribution (bug fixes, or feature request), please request fork PowerNSX, create a feature branch, then submit a pull request.


# How to use Power NSX?

Below are links on how to use and operate PowerNSX. This commands are posted so operators can become familiar with PowerNSX.

* [Installing PowerNSX](/install/)
* [Connecting to NSX and vCenter](/connect/)
* [Logical Switching](ls/)
* [Logical Routing](/dlr/)
* [Distributed Firewall](/dfw/)
* [Security Groups, Tags, and Services](sgts/)
* [NSX Edge](/esg/)
* [NSX LB](/lb/)
* [NSX Manager and Controller operations](manager/)
* [Getting help](/help/)

See [Example - 3 Tier Application](example/) for a full stack deployment

# Who do I talk to? #

{% include icon-github.html username="nmbradford" %} is the primary author of PowerNSX. He is supported colleages at VMware and the community. If you want to contribute please have a look at the [issues](https://github.com/vmware/powernsx/issues) page to see what is planned, requires triage, and to get started.

PowerNSX is an opensource project, and as such is not supported by VMware.  Please feel free reach out to the team via the [Issues](https://github.com/vmware/powernsx/issues) page.

# License #

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
