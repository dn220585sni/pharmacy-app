# Збір прикладів GetStopPriceUKod для аналізу різноманіття акцій.
#
# Flow:
#   1. GetUsersRlz                 — список фармацевтів
#   2. LoginRlz (перший успішний)  — сесія для подальших викликів
#   3. GetTopDrugs                 — топ N товарів (за дефолтом 200)
#   4. GetStopPriceUKod for each   — акції на товар
#   5. LogoutRlz                   — звільнити сесію
#   6. Запис у JSON + summary в консоль
#
# Run:
#   powershell -ExecutionPolicy Bypass -File tool\collect_stop_price.ps1
#   powershell -ExecutionPolicy Bypass -File tool\collect_stop_price.ps1 -Count 50

param(
    [int]    $Count   = 200,
    [string] $BaseUrl = 'http://10.90.77.66:57772/csp/user/Kab.Service.cls',
    [string] $OutFile = "$PSScriptRoot\stop_price_examples.json",
    [int]    $DelayMs = 100
)

$ErrorActionPreference = 'Stop'

# ───────────────────────────────────────────────────────────────────────────
# CSP cookie container — щоб тримати CSPSESSIONID/CSPWSERVERID між запитами
# (інакше можна потрапити на інший Caché-інстанс, який не знає sessionId).
# ───────────────────────────────────────────────────────────────────────────
$script:Cookies = New-Object System.Net.CookieContainer

# Win-1251 декодер (Caché може віддавати у цьому кодуванні).
$script:Win1251 = [System.Text.Encoding]::GetEncoding(1251)

function Invoke-CacheService {
    param(
        [Parameter(Mandatory)] [string] $ServiceName,
        [hashtable] $Params,
        [string]    $SessionId
    )

    $qs = "ServiceName=$ServiceName"
    if ($Params) {
        foreach ($k in $Params.Keys) {
            $qs += "&$k=$($Params[$k])"
        }
    }
    if ($SessionId) {
        $qs += "&sessionId=$SessionId"
    }
    $uri = "${BaseUrl}?${qs}"

    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method            = 'GET'
    $req.CookieContainer   = $script:Cookies
    $req.Timeout           = 15000
    $req.ReadWriteTimeout  = 15000

    try {
        $res = $req.GetResponse()
    } catch [System.Net.WebException] {
        throw "HTTP error for $ServiceName : $($_.Exception.Message)"
    }

    try {
        $stream = $res.GetResponseStream()
        $ms     = New-Object System.IO.MemoryStream
        $stream.CopyTo($ms)
        $bytes  = $ms.ToArray()
    } finally {
        $res.Close()
    }

    # Декодування: Content-Type → win-1251 інакше UTF-8 з фолбеком.
    $ct = $res.ContentType
    if ($ct -and $ct.ToLower().Contains('windows-1251')) {
        $body = $script:Win1251.GetString($bytes)
    } else {
        try {
            $body = [System.Text.Encoding]::UTF8.GetString($bytes)
            # Якщо є replacement char — мабуть це win-1251.
            if ($body.Contains([char]0xFFFD)) {
                $body = $script:Win1251.GetString($bytes)
            }
        } catch {
            $body = $script:Win1251.GetString($bytes)
        }
    }

    # JSON-фікси Caché (повторюють cache_api_client.dart).
    $body = $body -replace '"\{"user"',  '"},{"user"'
    $body = $body -replace '\}\{"orderId"', '},{"orderId"'
    $body = $body -replace '"rules":\[\]"', '"rules":[]'

    # Балансування відсутніх ] / }.
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

# ───────────────────────────────────────────────────────────────────────────
# 1. GetUsersRlz
# ───────────────────────────────────────────────────────────────────────────
Write-Host "GetUsersRlz..." -NoNewline
$usersResp = Invoke-CacheService -ServiceName 'GetUsersRlz' -Params @{ rezhim = 'all' }
if ($usersResp.Status -ne 'OK') {
    throw "GetUsersRlz FAIL: $($usersResp.Result)"
}
$users = @($usersResp.users)
Write-Host " OK ($($users.Count) users)"

if ($users.Count -eq 0) {
    throw "No users returned"
}

# ───────────────────────────────────────────────────────────────────────────
# 2. LoginRlz — перший успішний
# ───────────────────────────────────────────────────────────────────────────
$sessionId  = $null
$loginUser  = $null
foreach ($u in $users) {
    Write-Host "LoginRlz user=$($u.user)..." -NoNewline
    $loginResp = Invoke-CacheService -ServiceName 'LoginRlz' -Params @{
        user = $u.user
        pswd = $u.pswd
    }
    if ($loginResp.Status -eq 'OK' -and $loginResp.sessionId) {
        $sessionId = $loginResp.sessionId
        $loginUser = $u.user
        Write-Host " OK (sessionId=$sessionId)"
        break
    } else {
        Write-Host " skip ($($loginResp.Result))"
    }
}

if (-not $sessionId) {
    throw "Не вдалося залогінитись жодним користувачем"
}

# ───────────────────────────────────────────────────────────────────────────
# 3. GetTopDrugs
# ───────────────────────────────────────────────────────────────────────────
Write-Host "GetTopDrugs..." -NoNewline
$topResp = Invoke-CacheService -ServiceName 'GetTopDrugs' -SessionId $sessionId
if ($topResp.Status -ne 'OK') {
    Invoke-CacheService -ServiceName 'LogoutRlz' -SessionId $sessionId | Out-Null
    throw "GetTopDrugs FAIL: $($topResp.Result)"
}

$itemsRaw = $null
foreach ($key in 'items','Items','drugs','Drugs') {
    if ($topResp.PSObject.Properties[$key]) {
        $itemsRaw = $topResp.$key
        break
    }
}
if (-not $itemsRaw) {
    Invoke-CacheService -ServiceName 'LogoutRlz' -SessionId $sessionId | Out-Null
    throw "GetTopDrugs: no items array. Keys: $($topResp.PSObject.Properties.Name -join ',')"
}

$items = @($itemsRaw) | Where-Object { $_.ukod -and $_.ukod -ne '' }
Write-Host " OK ($($items.Count) drugs with ukod)"

$takeCount = [Math]::Min($Count, $items.Count)
$selection = $items | Select-Object -First $takeCount
Write-Host "Збираю GetStopPriceUKod для $takeCount товарів..."

# ───────────────────────────────────────────────────────────────────────────
# 4. GetStopPriceUKod foreach
# ───────────────────────────────────────────────────────────────────────────
$examples       = @()
$withActions    = 0
$totalActions   = 0
$uniqueIds      = @{}
$uniquePravilo  = @{}

$i = 0
foreach ($it in $selection) {
    $i++
    $ukod = "$($it.ukod)"
    $name = "$($it.name)"

    try {
        $stop = Invoke-CacheService -ServiceName 'GetStopPriceUKod' `
                                    -Params @{ ukod = $ukod } `
                                    -SessionId $sessionId
    } catch {
        Write-Host "  [$i/$takeCount] ukod=$ukod EXC: $($_.Exception.Message)"
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
    }

    $examples += [PSCustomObject]@{
        ukod         = $ukod
        name         = $name
        actionsCount = $actions.Count
        raw          = $stop
    }

    if (($i % 10) -eq 0 -or $i -eq $takeCount) {
        Write-Host "  [$i/$takeCount] withActions=$withActions, uniqIds=$($uniqueIds.Count), uniqPravilo=$($uniquePravilo.Count)"
    }

    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

# ───────────────────────────────────────────────────────────────────────────
# 5. LogoutRlz
# ───────────────────────────────────────────────────────────────────────────
Write-Host "LogoutRlz..." -NoNewline
try {
    $logoutResp = Invoke-CacheService -ServiceName 'LogoutRlz' -SessionId $sessionId
    Write-Host " $($logoutResp.Result)"
} catch {
    Write-Host " EXC: $($_.Exception.Message)"
}

# ───────────────────────────────────────────────────────────────────────────
# 6. Запис у JSON + summary
# ───────────────────────────────────────────────────────────────────────────
$output = [PSCustomObject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    source      = [PSCustomObject]@{
        baseUrl       = $BaseUrl
        loginUser     = $loginUser
        topDrugsTotal = $items.Count
        sampleSize    = $takeCount
    }
    summary     = [PSCustomObject]@{
        withActions          = $withActions
        withoutActions       = $takeCount - $withActions
        totalActionsObserved = $totalActions
        uniqueActionIds      = $uniqueIds.Keys.Count
        uniquePraviloStrings = $uniquePravilo.Keys.Count
    }
    examples    = $examples
}

$output | ConvertTo-Json -Depth 12 | Out-File -FilePath $OutFile -Encoding utf8

Write-Host ""
Write-Host "═══ Summary ═══"
Write-Host "Sample size:           $takeCount"
Write-Host "With actions:          $withActions"
Write-Host "Without actions:       $($takeCount - $withActions)"
Write-Host "Total actions:         $totalActions"
Write-Host "Unique action ids:     $($uniqueIds.Count)"
Write-Host "Unique pravilo strs:   $($uniquePravilo.Count)"
Write-Host "Saved to:              $OutFile"
