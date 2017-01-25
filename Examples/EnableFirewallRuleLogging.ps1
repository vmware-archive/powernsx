

foreach ( $section in (Get-NsxFirewallSection | ? { $_.name -notmatch 'Default Section Layer3' })) {
    $req = Invoke-NsxWebRequest -URI "/api/4.0/firewall/globalroot-0/config/layer3sections/$($section.id)" -method get
    $content = [xml]$req.Content
    foreach ($rule in $content.section.rule) { $rule.logged = "true" }
    $AdditionalHeaders = @{"If-Match"=$req.Headers.ETag}
    $response = Invoke-NsxWebRequest -URI "/api/4.0/firewall/globalroot-0/config/layer3sections/$($section.id)" -method put -extraheader $AdditionalHeaders -body $content.section.outerxml
    if ( -not $response.StatusCode -eq 200 ) {
        throw "Failed putting section $($section.name) ($($section.id)).  $($req.StatusCode) : $($req.StatusDescription)"
    }
    else {
        write-host "Enabled logging on all rules in Section $($section.name) ($($section.id))"
    }
}

