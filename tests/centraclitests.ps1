$testvm = "app01"

#Basic CCLI output
invoke-nsxcli "show cluster all"


get-vm $testvm | Get-NsxCliDfwRule
get-vm $testvm | Get-NsxCliDfwFilter
get-vm $testvm | Get-NsxCliDfwAddrSet



