param(
    [int]$Port = 8787
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:PublicDir = Join-Path $script:AppRoot "public"
$script:DataDir = Join-Path $script:AppRoot "data"
$script:CacheDir = Join-Path $script:AppRoot "cache"
$script:DefaultCachePath = Join-Path $script:CacheDir "pricelabs-public.json"

function Get-DateKey {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($null -eq $Value) { return $null }
    $raw = [string]$Value
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    try { return (Get-Date $raw).ToString("yyyy-MM-dd") } catch { return $null }
}

function Get-Number {
    param(
        [object]$Value,
        [double]$Fallback = 0
    )

    if ($null -eq $Value) { return $Fallback }
    try { return [double]$Value } catch { return $Fallback }
}

function Get-Boolean {
    param(
        [object]$Value,
        [bool]$Fallback = $false
    )

    if ($null -eq $Value) { return $Fallback }
    try { return [bool]$Value } catch { return $Fallback }
}

function Convert-HtmlToText {
    param([Parameter(Mandatory = $true)][string]$Html)

    $clean = $Html
    $clean = [regex]::Replace($clean, "(?is)<script[^>]*>.*?</script>", " ")
    $clean = [regex]::Replace($clean, "(?is)<style[^>]*>.*?</style>", " ")
    $clean = [regex]::Replace($clean, "(?is)<noscript[^>]*>.*?</noscript>", " ")
    $clean = [regex]::Replace($clean, "(?is)<br\s*/?>", " ")
    $clean = [regex]::Replace($clean, "(?is)</p>", " ")
    $clean = [regex]::Replace($clean, "(?is)<[^>]+>", " ")
    $clean = [System.Net.WebUtility]::HtmlDecode($clean)
    $clean = $clean -replace "\s+", " "
    return $clean.Trim()
}

function Get-HtmlTitle {
    param([Parameter(Mandatory = $true)][string]$Html)

    $titleMatch = [regex]::Match($Html, "<title>(?<title>.*?)</title>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($titleMatch.Success) {
        return ([System.Net.WebUtility]::HtmlDecode($titleMatch.Groups["title"].Value)).Trim()
    }

    $metaMatch = [regex]::Match(
        $Html,
        '<meta[^>]+property=["'']og:title["''][^>]+content=["''](?<title>.*?)["'']',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($metaMatch.Success) {
        return ([System.Net.WebUtility]::HtmlDecode($metaMatch.Groups["title"].Value)).Trim()
    }

    return "PriceLabs source"
}

function Get-KeywordSnippet {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Keywords,
        [int]$Length = 320
    )

    foreach ($keyword in $Keywords) {
        $index = $Text.IndexOf($keyword, [System.StringComparison]::OrdinalIgnoreCase)
        if ($index -ge 0) {
            $start = [Math]::Max(0, $index - 80)
            $take = [Math]::Min($Length, $Text.Length - $start)
            $snippet = $Text.Substring($start, $take).Trim()
            if ($start -gt 0) { $snippet = "... $snippet" }
            if (($start + $take) -lt $Text.Length) { $snippet = "$snippet ..." }
            return $snippet
        }
    }

    if ($Text.Length -le $Length) { return $Text }
    return "$($Text.Substring(0, $Length).Trim()) ..."
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }

    return (Get-Content $Path -Raw) | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Find-BalancedJsonBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$StartIndex
    )

    $depth = 0
    $inString = $false
    $escape = $false
    for ($i = $StartIndex; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inString) {
            if ($escape) {
                $escape = $false
            } elseif ($ch -eq '\\') {
                $escape = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
        } else {
            if ($ch -eq '"') {
                $inString = $true
            } elseif ($ch -eq '{') {
                $depth++
            } elseif ($ch -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    return $Text.Substring($StartIndex, $i - $StartIndex + 1)
                }
            }
        }
    }
    return $null
}

function Get-JsonAssignmentFromHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Html,
        [Parameter(Mandatory = $true)][string]$AssignmentKey
    )

    $pattern = [regex]::Escape($AssignmentKey) + '\s*=\s*\{'
    $match = [regex]::Match($Html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }

    $start = $Html.IndexOf('{', $match.Index)
    if ($start -lt 0) { return $null }

    $jsonText = Find-BalancedJsonBlock -Text $Html -StartIndex $start
    if (-not $jsonText) { return $null }

    try {
        return $jsonText | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-JsonLdFromHtml {
    param([Parameter(Mandatory = $true)][string]$Html)

    $pattern = '<script[^>]+type=["'']application/ld\+json["''][^>]*>(.*?)</script>'
    $match = [regex]::Match($Html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { return $null }

    $payload = $match.Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($payload)) { return $null }

    try {
        return $payload | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-ValueByPossibleKeys {
    param(
        [Parameter(Mandatory = $true)][object]$Data,
        [Parameter(Mandatory = $true)][string[]]$Keys
    )

    if ($null -eq $Data) { return $null }

    if ($Data -is [System.Collections.IDictionary]) {
        foreach ($key in $Keys) {
            if ($Data.Contains($key)) { return $Data[$key] }
        }
    } elseif ($Data -is [pscustomobject]) {
        $propNames = $Data.PSObject.Properties.Name
        foreach ($key in $Keys) {
            if ($propNames -contains $key) { return $Data.$key }
        }
    } elseif ($Data -is [System.Collections.IEnumerable] -and -not ($Data -is [string])) {
        foreach ($item in $Data) {
            $found = Get-ValueByPossibleKeys -Data $item -Keys $Keys
            if ($null -ne $found) { return $found }
        }
    }

    return $null
}

function Get-ArrayItems {
    param([object]$Data)
    if ($null -eq $Data) { return @() }
    if ($Data -is [System.Collections.IEnumerable] -and -not ($Data -is [string])) {
        return @($Data)
    }
    return @($Data)
}

function Has-PoolAmenity {
    param([Parameter(Mandatory = $true)][object]$Data)

    $amenities = Get-ValueByPossibleKeys -Data $Data -Keys @("amenities","listing_amenities","amenity_names","amenities_names")
    if ($null -eq $amenities) { return $false }

    foreach ($item in Get-ArrayItems -Data $amenities) {
        if ($item -and $item.ToString().ToLower().Contains("pool")) { return $true }
    }

    return $false
}

function Extract-AirbnbListingMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Html,
        [Parameter(Mandatory = $true)][string]$Url
    )

    $metadata = [pscustomobject]@{
        listingUrl = $Url
        source = "Airbnb"
        id = $null
        name = $null
        bedrooms = $null
        maxGuests = $null
        hasPool = $false
        rating = $null
        reviewCount = $null
        description = $null
    }

    $jsonLd = Get-JsonLdFromHtml -Html $Html
    if ($jsonLd -ne $null) {
        if (($jsonLd -is [System.Collections.IEnumerable]) -and -not ($jsonLd -is [string])) {
            $jsonLd = $jsonLd | Select-Object -First 1
        }

        if ($jsonLd -is [pscustomobject]) {
            if (-not $metadata.name) { $metadata.name = [string]$jsonLd.name }
            if (-not $metadata.description) { $metadata.description = [string]$jsonLd.description }
            $agg = Get-ValueByPossibleKeys -Data $jsonLd -Keys @("aggregateRating","aggregate_rating")
            if ($agg -ne $null) {
                if (-not $metadata.rating) { $metadata.rating = [double](Get-ValueByPossibleKeys -Data $agg -Keys @("ratingValue","rating_value")) }
                if (-not $metadata.reviewCount) { $metadata.reviewCount = [int](Get-ValueByPossibleKeys -Data $agg -Keys @("reviewCount","review_count")) }
            }
        }
    }

    $pageJson = Get-JsonAssignmentFromHtml -Html $Html -AssignmentKey "window.__INITIAL_STATE__"
    if (-not $pageJson) { $pageJson = Get-JsonAssignmentFromHtml -Html $Html -AssignmentKey "__INITIAL_STATE__" }

    if ($pageJson -ne $null) {
        if (-not $metadata.id) { $metadata.id = Get-ValueByPossibleKeys -Data $pageJson -Keys @("listing_id","listingId","id") }
        if (-not $metadata.name) { $metadata.name = Get-ValueByPossibleKeys -Data $pageJson -Keys @("name","title") }
        if (-not $metadata.description) { $metadata.description = Get-ValueByPossibleKeys -Data $pageJson -Keys @("description","summary") }
        if (-not $metadata.bedrooms) { $metadata.bedrooms = Get-ValueByPossibleKeys -Data $pageJson -Keys @("bedrooms","bedroom_count","bedroomCount") }
        if (-not $metadata.maxGuests) { $metadata.maxGuests = Get-ValueByPossibleKeys -Data $pageJson -Keys @("person_capacity","personCapacity","guests_included","max_guests","maxGuests") }
        if (-not $metadata.rating) { $metadata.rating = Get-ValueByPossibleKeys -Data $pageJson -Keys @("rating","star_rating","avg_rating") }
        if (-not $metadata.hasPool) { $metadata.hasPool = Has-PoolAmenity -Data $pageJson }
    }

    if (-not $metadata.id) {
        $match = [regex]::Match($Url, '/rooms/(?<id>\d+)')
        if ($match.Success) { $metadata.id = $match.Groups['id'].Value }
    }

    if ([string]::IsNullOrWhiteSpace([string]$metadata.name)) {
        $metadata.name = "Airbnb listing"
    }

    if ($metadata.bedrooms -ne $null) { $metadata.bedrooms = [int](Get-Number $metadata.bedrooms 0) }
    if ($metadata.maxGuests -ne $null) { $metadata.maxGuests = [int](Get-Number $metadata.maxGuests 0) }
    if ($metadata.rating -ne $null) { $metadata.rating = [double](Get-Number $metadata.rating 0) }
    if ($metadata.reviewCount -ne $null) { $metadata.reviewCount = [int](Get-Number $metadata.reviewCount 0) }

    return $metadata
}

function Scrape-AirbnbListing {
    param([Parameter(Mandatory = $true)][string]$Url)

    $headers = @{ 
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        "Accept-Language" = "en-US,en;q=0.9"
        "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
    }

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -Headers $headers
    if ($null -eq $response.Content) { throw "No content returned from $Url" }

    return Extract-AirbnbListingMetadata -Html $response.Content -Url $Url
}

function Get-DefaultOptions {
    return [pscustomobject]@{
        horizonDays     = 14
        minimumRating   = 4.7
        maxWalkMinutes  = 18
        minSimilarity   = 0.58
        strictPoolMatch = $true
    }
}

function Merge-Options {
    param([object]$Incoming)

    $defaults = Get-DefaultOptions
    if ($null -eq $Incoming) { return $defaults }

    return [pscustomobject]@{
        horizonDays     = [Math]::Max(7, [Math]::Min(30, [int](Get-Number $Incoming.horizonDays $defaults.horizonDays)))
        minimumRating   = [Math]::Max(4.0, [Math]::Min(5.0, (Get-Number $Incoming.minimumRating $defaults.minimumRating)))
        maxWalkMinutes  = [Math]::Max(5, [Math]::Min(30, [int](Get-Number $Incoming.maxWalkMinutes $defaults.maxWalkMinutes)))
        minSimilarity   = [Math]::Max(0.3, [Math]::Min(0.95, (Get-Number $Incoming.minSimilarity $defaults.minSimilarity)))
        strictPoolMatch = Get-Boolean $Incoming.strictPoolMatch $defaults.strictPoolMatch
    }
}

function Get-SampleDataset {
    return Read-JsonFile -Path (Join-Path $script:DataDir "sample-dataset.json")
}

function Get-WeightedQuantile {
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [double]$Quantile = 0.5
    )

    $validItems = @(
        $Items |
            Where-Object { $null -ne $_ -and (Get-Number $_.weight 0) -gt 0 } |
            Sort-Object { Get-Number $_.value 0 }
    )

    if ($validItems.Count -eq 0) { return $null }

    $totalWeight = ($validItems | Measure-Object -Property weight -Sum).Sum
    if ($totalWeight -le 0) { return $null }

    $target = $totalWeight * $Quantile
    $running = 0.0

    foreach ($item in $validItems) {
        $running += (Get-Number $item.weight 0)
        if ($running -ge $target) {
            return (Get-Number $item.value 0)
        }
    }

    return (Get-Number $validItems[-1].value 0)
}

function Get-Median {
    param([Parameter(Mandatory = $true)][double[]]$Values)

    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }

    if (($sorted.Count % 2) -eq 1) {
        return $sorted[[int]($sorted.Count / 2)]
    }

    $upperIndex = [int]($sorted.Count / 2)
    $lowerIndex = $upperIndex - 1
    return ($sorted[$lowerIndex] + $sorted[$upperIndex]) / 2
}

function Get-ListingSimilarity {
    param(
        [Parameter(Mandatory = $true)]$Subject,
        [Parameter(Mandatory = $true)]$Comparable,
        [Parameter(Mandatory = $true)]$Options
    )

    $bedroomDelta = [Math]::Abs((Get-Number $Subject.bedrooms 0) - (Get-Number $Comparable.bedrooms 0))
    $guestDelta = [Math]::Abs((Get-Number $Subject.maxGuests 0) - (Get-Number $Comparable.maxGuests 0))
    $distanceDelta = [Math]::Abs((Get-Number $Subject.walkMinutesToBeach 0) - (Get-Number $Comparable.walkMinutesToBeach 0))

    $bedroomScore = [Math]::Max(0.0, 1.0 - ($bedroomDelta / 3.0))
    $guestScore = [Math]::Max(0.0, 1.0 - ($guestDelta / 6.0))
    $distanceScore = [Math]::Max(0.0, 1.0 - ($distanceDelta / 20.0))
    $ratingScore = [Math]::Max(0.55, (Get-Number $Comparable.rating 4.5) / 5.0)

    if ($Options.strictPoolMatch) {
        $poolScore = if ((Get-Boolean $Subject.hasPool $false) -eq (Get-Boolean $Comparable.hasPool $false)) { 1.0 } else { 0.0 }
    } else {
        $poolScore = if ((Get-Boolean $Subject.hasPool $false) -eq (Get-Boolean $Comparable.hasPool $false)) { 1.0 } else { 0.7 }
    }

    $similarity =
        ($bedroomScore * 0.30) +
        ($guestScore * 0.18) +
        ($poolScore * 0.20) +
        ($distanceScore * 0.14) +
        ($ratingScore * 0.18)

    return [Math]::Round($similarity, 3)
}

function Get-NormalizedDataset {
    param([Parameter(Mandatory = $true)]$Dataset)

    $meta = if ($null -eq $Dataset.meta) { [pscustomobject]@{} } else { $Dataset.meta }
    $subject = $Dataset.subjectListing
    if ($null -eq $subject) { throw "Dataset is missing subjectListing." }

    $normalizedRates = @()
    foreach ($rate in @($Dataset.pricelabsRates)) {
        $dateKey = Get-DateKey $rate.date
        if ($null -eq $dateKey) { continue }

        $normalizedRates += [pscustomobject]@{
            date    = $dateKey
            price   = Get-Number $rate.price 0
            minStay = [int](Get-Number $rate.minStay 1)
        }
    }
    if ($normalizedRates.Count -eq 0) { throw "Dataset has no usable PriceLabs rates." }

    $normalizedComparables = @()
    foreach ($comp in @($Dataset.comparables)) {
        $dailyRates = @()
        foreach ($daily in @($comp.dailyRates)) {
            $dateKey = Get-DateKey $daily.date
            if ($null -eq $dateKey) { continue }

            $dailyRates += [pscustomobject]@{
                date      = $dateKey
                price     = Get-Number $daily.price 0
                available = Get-Boolean $daily.available $true
            }
        }

        $normalizedComparables += [pscustomobject]@{
            id                 = [string]$comp.id
            name               = [string]$comp.name
            source             = [string]$comp.source
            bedrooms           = [int](Get-Number $comp.bedrooms 0)
            maxGuests          = [int](Get-Number $comp.maxGuests 0)
            hasPool            = Get-Boolean $comp.hasPool $false
            walkMinutesToBeach = [int](Get-Number $comp.walkMinutesToBeach 0)
            rating             = Get-Number $comp.rating 4.5
            dailyRates         = $dailyRates
        }
    }

    return [pscustomobject]@{
        meta = [pscustomobject]@{
            currency           = if ([string]::IsNullOrWhiteSpace([string]$meta.currency)) { "INR" } else { [string]$meta.currency }
            microMarket        = [string]$meta.microMarket
            sourceContext      = [string]$meta.sourceContext
            sampleType         = [string]$meta.sampleType
            sharedConversation = [string]$meta.sharedConversation
        }
        subjectListing = [pscustomobject]@{
            name               = [string]$subject.name
            bedrooms           = [int](Get-Number $subject.bedrooms 0)
            maxGuests          = [int](Get-Number $subject.maxGuests 0)
            hasPool            = Get-Boolean $subject.hasPool $false
            walkMinutesToBeach = [int](Get-Number $subject.walkMinutesToBeach 0)
            rating             = Get-Number $subject.rating 4.8
            market             = [string]$subject.market
            notes              = @($subject.notes)
        }
        auditAssumptions = @($Dataset.auditAssumptions)
        pricelabsRates   = @($normalizedRates | Sort-Object date)
        comparables      = @($normalizedComparables)
    }
}

function Invoke-PriceAudit {
    param(
        [Parameter(Mandatory = $true)]$Dataset,
        [Parameter(Mandatory = $true)]$Options
    )

    $normalized = Get-NormalizedDataset -Dataset $Dataset
    $mergedOptions = Merge-Options -Incoming $Options
    $subject = $normalized.subjectListing
    $priceLabsWindow = @($normalized.pricelabsRates | Sort-Object date | Select-Object -First $mergedOptions.horizonDays)
    $windowDateKeys = @($priceLabsWindow | ForEach-Object { $_.date })

    $compSummaries = @()
    foreach ($comp in @($normalized.comparables)) {
        if ((Get-Number $comp.rating 0) -lt $mergedOptions.minimumRating) { continue }
        if ((Get-Number $comp.walkMinutesToBeach 999) -gt $mergedOptions.maxWalkMinutes) { continue }
        if ($mergedOptions.strictPoolMatch -and ((Get-Boolean $comp.hasPool $false) -ne (Get-Boolean $subject.hasPool $false))) { continue }

        $similarity = Get-ListingSimilarity -Subject $subject -Comparable $comp -Options $mergedOptions
        if ($similarity -lt $mergedOptions.minSimilarity) { continue }

        $rateMap = @{}
        foreach ($daily in @($comp.dailyRates)) {
            $rateMap[$daily.date] = $daily
        }

        $availablePrices = @()
        $unavailableCount = 0
        $coveredCount = 0
        foreach ($dateKey in $windowDateKeys) {
            if ($rateMap.ContainsKey($dateKey)) {
                $coveredCount += 1
                $entry = $rateMap[$dateKey]
                if (Get-Boolean $entry.available $true) {
                    $availablePrices += (Get-Number $entry.price 0)
                } else {
                    $unavailableCount += 1
                }
            }
        }

        $coverageRatio = if ($windowDateKeys.Count -gt 0) { $coveredCount / $windowDateKeys.Count } else { 0 }
        $occupancyProxy = if ($coveredCount -gt 0) { $unavailableCount / $coveredCount } else { 0 }
        $medianAdr = if ($availablePrices.Count -gt 0) { Get-Median -Values $availablePrices } else { $null }

        $compSummaries += [pscustomobject]@{
            id                 = $comp.id
            name               = $comp.name
            source             = $comp.source
            bedrooms           = $comp.bedrooms
            maxGuests          = $comp.maxGuests
            hasPool            = $comp.hasPool
            walkMinutesToBeach = $comp.walkMinutesToBeach
            rating             = $comp.rating
            similarity         = $similarity
            coverageRatio      = [Math]::Round($coverageRatio, 3)
            occupancyProxy     = [Math]::Round($occupancyProxy, 3)
            medianAdr          = if ($null -ne $medianAdr) { [Math]::Round($medianAdr, 0) } else { $null }
            rateMap            = $rateMap
        }
    }

    $dailyRows = @()
    foreach ($priceLabsRate in $priceLabsWindow) {
        $candidates = @()
        $coverageCount = 0
        $unavailableCount = 0

        foreach ($compSummary in $compSummaries) {
            if (-not $compSummary.rateMap.ContainsKey($priceLabsRate.date)) { continue }
            $coverageCount += 1
            $entry = $compSummary.rateMap[$priceLabsRate.date]
            if (-not (Get-Boolean $entry.available $true)) {
                $unavailableCount += 1
                continue
            }

            $weight = [Math]::Round([Math]::Max(0.05, ($compSummary.similarity * (0.7 + ((Get-Number $compSummary.rating 4.5) / 10.0)))), 3)
            $candidates += [pscustomobject]@{
                name   = $compSummary.name
                value  = Get-Number $entry.price 0
                weight = $weight
            }
        }

        $marketMedian = Get-WeightedQuantile -Items $candidates -Quantile 0.5
        $marketLow = Get-WeightedQuantile -Items $candidates -Quantile 0.25
        $marketHigh = Get-WeightedQuantile -Items $candidates -Quantile 0.75
        $priceLabsPrice = Get-Number $priceLabsRate.price 0

        if ($null -ne $marketMedian -and $marketMedian -gt 0) {
            $gapAmount = $marketMedian - $priceLabsPrice
            $gapPercent = ($gapAmount / $marketMedian) * 100
            $priceIndex = $priceLabsPrice / $marketMedian
        } else {
            $gapAmount = $null
            $gapPercent = $null
            $priceIndex = $null
        }

        $averageSimilarity = if ($candidates.Count -gt 0) {
            ((
                $compSummaries |
                    Where-Object { $null -ne $_.rateMap[$priceLabsRate.date] -and (Get-Boolean $_.rateMap[$priceLabsRate.date].available $true) }
            ) | Measure-Object -Property similarity -Average).Average
        } else { 0 }

        $confidence = if ($candidates.Count -eq 0) {
            0
        } else {
            [Math]::Min(1.0, (($candidates.Count / 5.0) * ((Get-Number $averageSimilarity 0) + 0.35)))
        }

        $action = "Need more data"
        if ($null -ne $gapPercent) {
            if ($gapPercent -ge 8) {
                $action = "Raise"
            } elseif ($gapPercent -le -8) {
                $action = "Lower"
            } else {
                $action = "Hold"
            }
        }

        $dailyRows += [pscustomobject]@{
            date                 = $priceLabsRate.date
            priceLabs            = [Math]::Round($priceLabsPrice, 0)
            marketMedian         = if ($null -ne $marketMedian) { [Math]::Round($marketMedian, 0) } else { $null }
            marketLow            = if ($null -ne $marketLow) { [Math]::Round($marketLow, 0) } else { $null }
            marketHigh           = if ($null -ne $marketHigh) { [Math]::Round($marketHigh, 0) } else { $null }
            priceIndex           = if ($null -ne $priceIndex) { [Math]::Round($priceIndex, 3) } else { $null }
            gapAmount            = if ($null -ne $gapAmount) { [Math]::Round($gapAmount, 0) } else { $null }
            gapPercent           = if ($null -ne $gapPercent) { [Math]::Round($gapPercent, 1) } else { $null }
            availableCompCount   = $candidates.Count
            marketOccupancyProxy = if ($coverageCount -gt 0) { [Math]::Round(($unavailableCount / $coverageCount) * 100, 1) } else { 0 }
            confidence           = [Math]::Round($confidence * 100, 1)
            action               = $action
        }
    }

    $validDailyRows = @($dailyRows | Where-Object { $null -ne $_.marketMedian })
    $priceLabsValues = @($validDailyRows | ForEach-Object { [double]$_.priceLabs })
    $marketValues = @($validDailyRows | ForEach-Object { [double]$_.marketMedian })

    $medianPriceLabs = if ($priceLabsValues.Count -gt 0) { Get-Median -Values $priceLabsValues } else { $null }
    $medianMarket = if ($marketValues.Count -gt 0) { Get-Median -Values $marketValues } else { $null }

    if ($null -ne $medianPriceLabs -and $null -ne $medianMarket -and $medianMarket -gt 0) {
        $medianIndex = $medianPriceLabs / $medianMarket
        $medianGapPercent = (($medianMarket - $medianPriceLabs) / $medianMarket) * 100
    } else {
        $medianIndex = $null
        $medianGapPercent = $null
    }

    $underpricedDays = @($validDailyRows | Where-Object { $null -ne $_.gapPercent -and $_.gapPercent -ge 8 }).Count
    $overpricedDays = @($validDailyRows | Where-Object { $null -ne $_.gapPercent -and $_.gapPercent -le -8 }).Count
    $holdDays = @($validDailyRows | Where-Object { $_.action -eq "Hold" }).Count

    $opportunityUplift = (
        $validDailyRows |
            ForEach-Object { if ($null -ne $_.gapAmount -and $_.gapAmount -gt 0) { [double]$_.gapAmount } else { 0 } } |
            Measure-Object -Sum
    ).Sum

    $riskDownside = (
        $validDailyRows |
            ForEach-Object { if ($null -ne $_.gapAmount -and $_.gapAmount -lt 0) { [Math]::Abs([double]$_.gapAmount) } else { 0 } } |
            Measure-Object -Sum
    ).Sum

    $averageConfidence = if ($validDailyRows.Count -gt 0) {
        [Math]::Round((($validDailyRows | Measure-Object -Property confidence -Average).Average), 1)
    } else { 0 }

    $marketOccupancy = if ($validDailyRows.Count -gt 0) {
        [Math]::Round((($validDailyRows | Measure-Object -Property marketOccupancyProxy -Average).Average), 1)
    } else { 0 }

    $auditStatus = "Need more market data"
    $headline = "The comparison set is too thin to judge PriceLabs confidently."
    if ($null -ne $medianGapPercent) {
        if ($medianGapPercent -ge 8) {
            $auditStatus = "Likely underpriced"
            $headline = "PriceLabs is running below the weighted market benchmark for this micro-market."
        } elseif ($medianGapPercent -le -8) {
            $auditStatus = "Likely overpriced"
            $headline = "PriceLabs is running above the weighted market benchmark for this micro-market."
        } else {
            $auditStatus = "Within market band"
            $headline = "PriceLabs is landing inside the market band most days."
        }
    }

    $insights = @()
    if ($null -ne $medianGapPercent) {
        $insights += "PriceLabs is $(("{0:N1}" -f $medianGapPercent))% below the weighted market median across the next $($validDailyRows.Count) nights."
    }
    $insights += "$underpricedDays day(s) look underpriced, $holdDays day(s) sit inside the band, and $overpricedDays day(s) look overpriced."
    $insights += "Observed comp-set occupancy proxy is $marketOccupancy% for the active date window."
    $insights += "Average audit confidence is $averageConfidence% based on rating, distance-to-beach, pool match, and bedroom/guest similarity."

    return [pscustomobject]@{
        status = $auditStatus
        headline = $headline
        summary = [pscustomobject]@{
            medianPriceLabs      = if ($null -ne $medianPriceLabs) { [Math]::Round($medianPriceLabs, 0) } else { $null }
            medianMarket         = if ($null -ne $medianMarket) { [Math]::Round($medianMarket, 0) } else { $null }
            medianGapPercent     = if ($null -ne $medianGapPercent) { [Math]::Round($medianGapPercent, 1) } else { $null }
            priceIndex           = if ($null -ne $medianIndex) { [Math]::Round($medianIndex, 3) } else { $null }
            underpricedDays      = $underpricedDays
            holdDays             = $holdDays
            overpricedDays       = $overpricedDays
            opportunityUplift    = [Math]::Round((Get-Number $opportunityUplift 0), 0)
            downsideRisk         = [Math]::Round((Get-Number $riskDownside 0), 0)
            marketOccupancyProxy = $marketOccupancy
            averageConfidence    = $averageConfidence
        }
        dailyComparison = $dailyRows
        comparableSummary = @($compSummaries | Sort-Object similarity -Descending | ForEach-Object {
            [pscustomobject]@{
                id                 = $_.id
                name               = $_.name
                source             = $_.source
                similarity         = [Math]::Round($_.similarity * 100, 1)
                rating             = $_.rating
                medianAdr          = $_.medianAdr
                occupancyProxy     = [Math]::Round($_.occupancyProxy * 100, 1)
                coverageRatio      = [Math]::Round($_.coverageRatio * 100, 1)
                hasPool            = $_.hasPool
                bedrooms           = $_.bedrooms
                maxGuests          = $_.maxGuests
                walkMinutesToBeach = $_.walkMinutesToBeach
            }
        })
        insights = $insights
        optionsUsed = $mergedOptions
    }
}

function Get-PriceLabsPublicIntel {
    param([switch]$ForceRefresh)

    $cacheTtlHours = 12
    if ((-not $ForceRefresh) -and (Test-Path $script:DefaultCachePath)) {
        $cacheAge = (Get-Date) - (Get-Item $script:DefaultCachePath).LastWriteTime
        if ($cacheAge.TotalHours -lt $cacheTtlHours) {
            return Read-JsonFile -Path $script:DefaultCachePath
        }
    }

    $sourceSpecs = @(
        [pscustomobject]@{ url = "https://hello.pricelabs.co/plans/"; label = "Pricing Plans"; keywords = @("pricing", "trial", "monthly", "listing") },
        [pscustomobject]@{ url = "https://hello.pricelabs.co/dynamic-pricing/"; label = "Dynamic Pricing"; keywords = @("dynamic pricing", "base price", "demand", "control") },
        [pscustomobject]@{ url = "https://help.pricelabs.co/portal/en/kb/articles/using-vrbo-data-for-your-dynamic-pricing"; label = "Vrbo Data Support"; keywords = @("occupancy", "market", "base price", "recommendations", "Vrbo") }
    )

    $results = @()
    $warnings = @()
    foreach ($spec in $sourceSpecs) {
        try {
            $response = Invoke-WebRequest -Uri $spec.url -UseBasicParsing -TimeoutSec 25
            $title = Get-HtmlTitle -Html $response.Content
            if ([string]::IsNullOrWhiteSpace($title)) { $title = $spec.label }
            $text = Convert-HtmlToText -Html $response.Content
            $snippet = Get-KeywordSnippet -Text $text -Keywords $spec.keywords
            $results += [pscustomobject]@{ title = $title; url = $spec.url; snippet = $snippet }
        } catch {
            $warnings += "Could not refresh $($spec.url): $($_.Exception.Message)"
        }
    }

    if ($results.Count -eq 0 -and (Test-Path $script:DefaultCachePath)) {
        return Read-JsonFile -Path $script:DefaultCachePath
    }

    $payload = [pscustomobject]@{
        fetchedAt = (Get-Date).ToString("s")
        sources = $results
        warnings = $warnings
    }

    Write-JsonFile -Path $script:DefaultCachePath -Value $payload
    return $payload
}

function Read-RequestBody {
    param([Parameter(Mandatory = $true)][System.Net.HttpListenerRequest]$Request)

    if (-not $Request.HasEntityBody) { return $null }

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ([string]::IsNullOrWhiteSpace($body)) { return $null }
    return $body | ConvertFrom-Json
}

function Send-Json {
    param(
        [Parameter(Mandatory = $true)][System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$StatusCode = 200
    )

    $json = $Payload | ConvertTo-Json -Depth 100
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Send-File {
    param(
        [Parameter(Mandatory = $true)][System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $contentType = switch ($extension) {
        ".html" { "text/html; charset=utf-8" }
        ".css"  { "text/css; charset=utf-8" }
        ".js"   { "application/javascript; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".svg"  { "image/svg+xml" }
        default { "application/octet-stream" }
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $Response.StatusCode = 200
    $Response.ContentType = $contentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Send-Error {
    param(
        [Parameter(Mandatory = $true)][System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$StatusCode = 400
    )

    Send-Json -Response $Response -StatusCode $StatusCode -Payload ([pscustomobject]@{ error = $Message })
}

function Handle-ApiRequest {
    param([Parameter(Mandatory = $true)][System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath.ToLowerInvariant()

    switch ("$($request.HttpMethod) $path") {
        "GET /api/health" {
            Send-Json -Response $response -Payload ([pscustomobject]@{
                ok = $true
                port = $Port
                startedAt = (Get-Date).ToString("s")
            })
            return
        }
        "GET /api/bootstrap" {
            $dataset = Get-SampleDataset
            $analysis = Invoke-PriceAudit -Dataset $dataset -Options (Get-DefaultOptions)
            $sources = Get-PriceLabsPublicIntel
            Send-Json -Response $response -Payload ([pscustomobject]@{
                dataset = $dataset
                defaultOptions = Get-DefaultOptions
                analysis = $analysis
                publicIntel = $sources
            })
            return
        }
        "POST /api/analyze" {
            $body = Read-RequestBody -Request $request
            if ($null -eq $body -or $null -eq $body.dataset) {
                Send-Error -Response $response -Message "Request body must include a dataset payload."
                return
            }
            $analysis = Invoke-PriceAudit -Dataset $body.dataset -Options $body.options
            Send-Json -Response $response -Payload $analysis
            return
        }
        "POST /api/scrape-listing" {
            $body = Read-RequestBody -Request $request
            if ($null -eq $body -or [string]::IsNullOrWhiteSpace([string]$body.url)) {
                Send-Error -Response $response -Message "Request body must include a listing URL."
                return
            }

            try {
                $listing = Scrape-AirbnbListing -Url [string]$body.url
                Send-Json -Response $response -Payload ([pscustomobject]@{ listing = $listing })
            } catch {
                Send-Error -Response $response -Message $_.Exception.Message
            }
            return
        }

        "POST /api/refresh-sources" {
            $sources = Get-PriceLabsPublicIntel -ForceRefresh
            Send-Json -Response $response -Payload $sources
            return
        }
        default {
            Send-Error -Response $response -StatusCode 404 -Message "Unknown API route."
            return
        }
    }
}

function Handle-StaticRequest {
    param([Parameter(Mandatory = $true)][System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath

    if ($path -eq "/") { $path = "/index.html" }
    if ($path -eq "/favicon.ico") {
        $response.StatusCode = 204
        $response.OutputStream.Close()
        return
    }

    $relativePath = $path.TrimStart("/") -replace "/", [System.IO.Path]::DirectorySeparatorChar
    $fullPath = Join-Path $script:PublicDir $relativePath
    if (-not (Test-Path $fullPath -PathType Leaf)) {
        Send-Error -Response $response -StatusCode 404 -Message "Static file not found."
        return
    }

    Send-File -Response $response -Path $fullPath
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host ""
Write-Host "PriceLabs audit app is running." -ForegroundColor Cyan
Write-Host "Open http://localhost:$Port/" -ForegroundColor Cyan
Write-Host ""

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            if ($context.Request.Url.AbsolutePath.StartsWith("/api/", [System.StringComparison]::OrdinalIgnoreCase)) {
                Handle-ApiRequest -Context $context
            } else {
                Handle-StaticRequest -Context $context
            }
        } catch {
            if ($context.Response.OutputStream.CanWrite) {
                Send-Error -Response $context.Response -StatusCode 500 -Message $_.Exception.Message
            }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
