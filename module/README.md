# PowerNSX Module Manifest README.

Manifest Generation is now automated via the Publish.ps1 script as different
manifests are required for different distribution mechanisms.

## Instructions

The publish script is intended to automate whatever process is required now and
in the future to make publishing updates to PowerNSX easy.

The publish script is to be run when a new version of PowerNSX needs to be
made available.

## Contributors to PowerNSX

Individual contributors to PowerNSX should do as follows:

1) If you are not adding any new functions to PowerNSX (your commit is a bug fix
or improvement to an existing function), then there is nothing more to do.

2) If you have added functions to PowerNSX, on top of your actual edits to the
PowerNSX module itself, you must also edit the Include.ps1 file and make the
appropriate changes to the FunctionsToExport array as you would previously have
done directly in the manifest (.psd1 file) itself.

### Do NOT edit the .psd1 manifest files directly!

## Publishing process

PowerNSX maintainers will perform the following when PowerNSX is updated.

1) Once reviewing and ensuring all existing tests pass, a Pull Request will be
merged by a maintainer.

2) A maintainer executes the publish script (manually for now, but soon to be
automated as part of our CI/CD) which :
    * Reads include.ps1 and adds a build number to the version string.
    * Generates the platform specific manifests and copies the updated module to
      the platform specific folders
    * Publishes the updated module to the PowerShell gallery.
    * Push the updated module to the PowerNSX repository

## Copyright
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
has its own license that is located in the source code of the respective component.
#>

