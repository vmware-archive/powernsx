

# Contributing to powernsx

Thank you for your interest in PowerNSX.  You can contribute in any of the following ways:

  * Download and use it.  "Star" the repository if you like it.
  * Report bugs if you find them.
  * Suggest feature additions or useability enhancements.
  * Review pending issues and contribute through code or documentation.


## Getting Started

  * Install PowerNSX as per installation instructions.

## Contribution Flow

- Fork the PowerNSX repository
- Create a topic branch in your fork from where you want to base your work
- Make commits of your changes
- Make sure your commit messages are in the proper format (see below)
- Push your changes to the topic branch in your fork of the repository
- Submit a pull request

Example:

``` shell
git clone git@github.com:vmware/powernsx.git
git checkout -b my-new-feature powernsx/master
git commit -a
git push $USER my-new-feature
```

### Staying In Sync With Upstream

When your branch gets out of sync with the powernsx/master branch, use the following to update:

``` shell
git checkout my-new-feature
git fetch -a
git rebase powernsx/master
git push --force-with-lease $USER my-new-feature
```

### Updating pull requests

If your PR needs changes based on code review, you'll most likely want to squash these changes into
existing commits.

If your pull request contains a single commit or your changes are related to the most recent commit, you can simply
amend the commit.

``` shell
git add .
git commit --amend
git push --force-with-lease $USER my-new-feature
```

If you need to squash changes into an earlier commit, you can use:

``` shell
git add .
git commit --fixup <commit>
git rebase -i --autosquash powernsx/master
git push --force-with-lease $USER my-new-feature
```

Be sure to add a comment to the PR indicating your new changes are ready to review, as GitHub does not generate a
notification when you git push.

### Code Style

 * Ensure PowerShell Comment based help is included with any additional cmdlets/parameters.  See existing code, or https://technet.microsoft.com/en-us/magazine/hh500719.aspx for example
 * For significant functionality (especially for update/set/remove cmdlets), please created appropriate tests.  Testing in PowerNSX is still sub optimal, but plans to improve by moving to Pester
 * When accepting object parameters that are generic object types (pscustomobject or XML - especially pipeline parameters) write appropriate validate-scripts to validate that input objects are whats expected.  When using typed objects, validate using at least type.
 * Try to optimise the pipeline usage.  Any set/update/remove cmldet that is expected to accept pipeline input should implement begin{} process{} end {}.


### Formatting Commit Messages

We (will be) follow (ing) the conventions on [How to Write a Git Commit Message](http://chris.beams.io/posts/git-commit/).

Be sure to include any related GitHub issue references in the commit message.  See
[GFM syntax](https://guides.github.com/features/mastering-markdown/#GitHub-flavored-markdown) for referencing issues
and commits.

## Reporting Bugs and Creating Issues

When opening a new issue, try to roughly follow the commit message format conventions above.

## Repository Structure

The PowerNSX Module and Installer are in the root directory.  

The 'bootstrap' line (the PoSH oneliner that will install the _latest commit of the current branch_) is contained within InstallBootstrapper.ps1

There is a directory for Tests (for the moment, these are not really automatable or consumable by anyone other than the maintainers, but any effort toward converting these toward Pester style tests would be greatly appreciated)

There is a directory for Examples - this is for self contained examples that consume PowerNSX and related functionailty (like PowerCLI).  If you have a fully functional example script that demonstrates a particular caability of PowerNSX, feel free to add it here.