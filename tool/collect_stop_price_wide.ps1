# Wide collection of GetStopPriceUKod examples.
#
# Instead of GetTopDrugs (498 items) we sweep the whole directory via
# SearchByName with letter prefixes, build a union of ukods, then call
# GetStopPriceUKod for each. Output JSON keeps only entries with active
# actions (to avoid bloat) + summary statistics.
#
# NOTE: Cyrillic literals are generated from Unicode code points to keep
# this script encoding-agnostic — PS 5.1 reads .ps1 in the system code page,
# so embedding cyrillic literals in the file breaks parsing.
#
# Run:
#   powershell -ExecutionPolicy Bypass -File tool\collect_stop_price_wide.ps1
#   powershell -ExecutionPolicy Bypass -File tool\collect_stop_price_wide.ps1 -MaxUkods 2000

param(
    [string]   $BaseUrl  = 'http://10.90.77.66:57772/csp/user/Kab.Service.cls',
    [string]   $OutFile  = "$PSScriptRoot\stop_price_examples_wide.json",
    [int]      $DelayMs  = 80,
    [int]      $MaxUkods = 0,
    [string[]] $Prefixes = $null
)

# Default prefixes (cyrillic a..ya + UA-specific) via code points.
if (-not $Prefixes) {
    $base = 0x0430..0x044F | ForEach-Object { [char]$_ }     # U+0430..U+044F (rus/ua shared a..ya)
    $uaExtra = @(0x0491, 0x0454, 0x0456, 0x0457) | ForEach-Object { [char]$_ }  # UA-specific: g-stroke, ye, i, yi
    $Prefixes = @($base) + @($uaExtra)
}

$ErrorActionPreference = 'Stop'

$script:Cookies = New-Object System.Net.CookieContainer
$script:Win1251 = [System.Text.Encoding]::GetEncoding(1251)
$script:BaseUrl = $BaseUrl

function Invoke-CacheService {
    param(
        [Parameter(Mandatory)] [string] $ServiceName,
        [hashtable] $Params,
        [string]    $SessionId,
        [int]       $MaxRetries = 2
    )

    $qs = "ServiceName=$ServiceName"
    if ($Params) {
        foreach ($k in $Params.Keys) {
            $qs += "&$k=$([System.Uri]::EscapeDataString($Params[$k]))"
        }
    }
    if ($SessionId) {
        $qs += "&sessionId=$SessionId"
    }
    $uri = "$($script:BaseUrl)?$qs"

    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        $req = [System.Net.HttpWebRequest]::Create($uri)
        $req.Method           = 'GET'
        $req.CookieContainer  = $script:Cookies
        $req.Timeout          = 20000
        $req.ReadWriteTimeout = 20000

        try {
            $res = $req.GetResponse()
        } catch [System.Net.WebException] {
            $httpRes = $_.Exception.Response
            $code = $null
            if ($httpRes) { $code = [int]$httpRes.StatusCode }
            if ($code -eq 503 -and $attempt -lt $MaxRetries) {
                Start-Sleep -Milliseconds 2000
                continue
            }
            throw "HTTP error $code for $ServiceName : $($_.Exception.Message)"
        }

        try {
            $stream = $res.GetResponseStream()
            $ms     = New-Object System.IO.MemoryStream
            $stream.CopyTo($ms)
            $bytes  = $ms.ToArray()
            $ct     = $res.ContentType
        } finally {
            $res.Close()
        }

        if ($ct -and $ct.ToLower().Contains('windows-1251')) {
            $body = $script:Win1251.GetString($bytes)
        } else {
            try {
                $body = [System.Text.Encoding]::UTF8.GetString($bytes)
                if ($body.Contains([char]0xFFFD)) {
                    $body = $script:Win1251.GetString($bytes)
                }
            } catch {
                $body = $script:Win1251.GetString($bytes)
            }
        }

        $body = $body -replace '"\{"user"',  '"},{"user"'
        $body = $body -replace '\}\{"orderId"', '},{"orderId"'
        $body = $body -replace '"rules":\[\]"', '"rules":[]'

        $trimmed = $body.TrimEnd()
        if ($trimmed -and -not ($trimmed.EndsWith(']}') -or $trimmed.EndsWith('}}'))) {
            $openBrace   = 0
            $openBracket = 0
            foreach ($ch in $trimmed.ToCharArray()) {
                switch ($ch) {
                    '{' { $openBrace++ }
                    '}' { $openBrace-- }
                    '[' { $openBracket++ }
                    ']' { $openBracket-- }
                }
            }
            $suffix = ''
            for ($i = 0; $i -lt $openBracket; $i++) { $suffix += ']' }
            for ($i = 0; $i -lt $openBrace;   $i++) { $suffix += '}' }
            if ($suffix) { $body = "$trimmed$suffix" }
        }

        try {
            return ConvertFrom-Json $body
        } catch {
            throw "JSON parse error for $ServiceName : $($_.Exception.Message) -- body head: $($body.Substring(0,[Math]::Min(200,$body.Length)))"
        }
    }
}

# --- Login --------------------------------------------------------------
Write-Host "GetUsersRlz..." -NoNewline
$usersResp = Invoke-CacheService -ServiceName 'GetUsersRlz' -Params @{ rezhim = 'all' }
if ($usersResp.Status -ne 'OK') { throw "GetUsersRlz FAIL: $($usersResp.Result)" }
$users = @($usersResp.users)
Write-Host " OK ($($users.Count) users)"

$sessionId = $null
$loginUser = $null
foreach ($u in $users) {
    Write-Host "LoginRlz user=$($u.user)..." -NoNewline
    $loginResp = Invoke-CacheService -ServiceName 'LoginRlz' -Params @{ user = $u.user; pswd = $u.pswd }
    if ($loginResp.Status -eq 'OK' -and $loginResp.sessionId) {
        $sessionId = $loginResp.sessionId
        $loginUser = $u.user
        Write-Host " OK (sessionId=$sessionId)"
        break
    } else {
        Write-Host " skip ($($loginResp.Result))"
    }
}
if (-not $sessionId) { throw "Login failed for all users" }

# --- Phase 1: SearchByName over prefixes --> union of ukods --------------
$ukodMap = @{}   # ukod -> first seen name

Write-Host ""
Write-Host "=== Phase 1: SearchByName over $($Prefixes.Count) prefixes ==="
foreach ($p in $Prefixes) {
    try {
        $resp = Invoke-CacheService -ServiceName 'SearchByName' `
                                    -Params @{ name = $p } `
                                    -SessionId $sessionId
        if ($resp.Status -ne 'OK') {
            Write-Host "  prefix='$p' FAIL ($($resp.Result))"
            continue
        }
        # SearchByName quirk: server returns u-code in the 'ids' field
        # (not 'ukod'). DrugSearchItem.fromJson in dart leaves .ukod empty
        # for this endpoint and uses .ids as the lookup key.
        $items = @($resp.items)
        $newCount = 0
        foreach ($it in $items) {
            $u = $null
            foreach ($key in 'ids','ukod','UKod') {
                if ($it.PSObject.Properties[$key]) {
                    $val = "$($it.$key)"
                    if ($val) { $u = $val; break }
                }
            }
            if ($u -and -not $ukodMap.ContainsKey($u)) {
                $name = $null
                foreach ($k in 'nameukr','name','NameUkr','Name') {
                    if ($it.PSObject.Properties[$k]) {
                        $val = "$($it.$k)"
                        if ($val) { $name = $val; break }
                    }
                }
                $ukodMap[$u] = $name
                $newCount++
            }
        }
        Write-Host "  prefix='$p' items=$($items.Count) new=$newCount totalUnique=$($ukodMap.Count)"
    } catch {
        Write-Host "  prefix='$p' EXC: $($_.Exception.Message)"
    }
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

$allUkods = @($ukodMap.Keys)
if ($MaxUkods -gt 0 -and $allUkods.Count -gt $MaxUkods) {
    Write-Host "Capping sample: $MaxUkods of $($allUkods.Count)"
    $allUkods = $allUkods | Select-Object -First $MaxUkods
}

Write-Host ""
Write-Host "=== Phase 2: GetStopPriceUKod for $($allUkods.Count) ukods ==="

# --- Phase 2: GetStopPriceUKod foreach ----------------------------------
$examples       = @()
$withActions    = 0
$totalActions   = 0
$uniqueIds      = @{}
$uniquePravilo  = @{}
$errors         = 0

$i = 0
$total = $allUkods.Count
foreach ($ukod in $allUkods) {
    $i++
    $name = $ukodMap[$ukod]

    try {
        $stop = Invoke-CacheService -ServiceName 'GetStopPriceUKod' `
                                    -Params @{ ukod = $ukod } `
                                    -SessionId $sessionId
    } catch {
        $errors++
        if (($i % 50) -eq 0) {
            Write-Host "  [$i/$total] EXC ukod=$ukod : $($_.Exception.Message)"
        }
        continue
    }

    $actions = @()
    if ($stop.Actions) { $actions = @($stop.Actions) }

    if ($actions.Count -gt 0) {
        $withActions++
        $totalActions += $actions.Count
        foreach ($a in $actions) {
            if ($a.id)      { $uniqueIds[$a.id]          = $true }
            if ($a.pravilo) { $uniquePravilo[$a.pravilo] = $true }
        }
        $examples += [PSCustomObject]@{
            ukod         = $ukod
            name         = $name
            actionsCount = $actions.Count
            raw          = $stop
        }
    }

    if (($i % 100) -eq 0 -or $i -eq $total) {
        Write-Host "  [$i/$total] withActions=$withActions, uniqIds=$($uniqueIds.Count), uniqPravilo=$($uniquePravilo.Count), errors=$errors"
    }

    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

# --- Phase 3: Logout + save ---------------------------------------------
Write-Host "LogoutRlz..." -NoNewline
try {
    $logoutResp = Invoke-CacheService -ServiceName 'LogoutRlz' -SessionId $sessionId
    Write-Host " $($logoutResp.Result)"
} catch {
    Write-Host " EXC: $($_.Exception.Message)"
}

$output = [PSCustomObject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    source      = [PSCustomObject]@{
        baseUrl      = $BaseUrl
        loginUser    = $loginUser
        prefixes     = $Prefixes
        ukodsScanned = $total
    }
    summary     = [PSCustomObject]@{
        withActions          = $withActions
        withoutActions       = $total - $withActions - $errors
        errors               = $errors
        totalActionsObserved = $totalActions
        uniqueActionIds      = $uniqueIds.Keys.Count
        uniquePraviloStrings = $uniquePravilo.Keys.Count
    }
    uniqueIds       = ($uniqueIds.Keys | Sort-Object)
    uniquePraviloss = ($uniquePravilo.Keys | Sort-Object)
    examples        = $examples
}

$output | ConvertTo-Json -Depth 12 | Out-File -FilePath $OutFile -Encoding utf8

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Ukods scanned:         $total"
Write-Host "With actions:          $withActions"
Write-Host "Without actions:       $($total - $withActions - $errors)"
Write-Host "Errors:                $errors"
Write-Host "Total actions:         $totalActions"
Write-Host "Unique action ids:     $($uniqueIds.Count)"
Write-Host "Unique pravilo strs:   $($uniquePravilo.Count)"
Write-Host "Saved to:              $OutFile"
