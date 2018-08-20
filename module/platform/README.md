# PowerNSX Distribution folder

## Notes for developers/maintainters

DO NOT edit the module files or manifests within the platform folder.
The platform/ folder is automatically populated by the publish script which is run
when PowerNSX updates are accepted by a maintainer.

The modules in the platform/ directory are overwritten by this process and are
the ones used by the installation script and uploaded to the PowerShell Gallery.

## Notes for users

If you are performing a manual installation of PowerNSX, download the appropriate
module files for your platform (Desktop or Core) from this directory and place
them in a path within $PSModulePath.

No edits to the module files within this directory files will be accepted in any PR.
