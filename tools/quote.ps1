<#
.SYNOPSIS
  UNIQ Supply custom cup quote engine. Does every price calculation, so the AI never does the math.

.DESCRIPTION
  Reads data/pricing.json, checks every production path (in-house digital, USA partner, overseas),
  and returns JSON with the math, totals, shipping, ship window, deadline status, escalation flags,
  and a ready-to-paste quote_text block.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/quote.ps1 -Size 8 -Qty 20000 -Colors 2 -Pms -NeedBy 2027-04-15
  powershell -ExecutionPolicy Bypass -File tools/quote.ps1 -Size 12 -Qty 3000 -Colors full
  powershell -ExecutionPolicy Bypass -File tools/quote.ps1 -Size 8 -Qty 50000 -Colors 2 -ReorderPath usa
  powershell -ExecutionPolicy Bypass -File tools/quote.ps1 -Size 12 -Qty 30000 -Colors 1 -Destination outside

.PARAMETER Colors
  Number of ink colors in the logo (1-4), or "full" for full color / gradients / photos.
.PARAMETER Pms
  The customer needs an exact Pantone (PMS) match. In-house digital can't guarantee that.
.PARAMETER ReorderPath
  "usa" or "overseas" when this is an unchanged reorder of a design already printed on that path (no setup fee).
.PARAMETER Destination
  lower48 (default), outside (AK, HI, Canada, PR, international), or unknown (priced as lower 48 and noted).
.PARAMETER NeedBy
  The customer's in-hand date (yyyy-MM-dd), if they gave one.
.PARAMETER ProofDays
  Business days from Today until we assume the customer approves the proof (default 1).
.PARAMETER TransitBufferDays
  Business days to keep between the ship date and NeedBy for transit (default 5). The KB has no transit times.
#>
param(
  [Parameter(Mandatory = $true)][int]$Size,
  [Parameter(Mandatory = $true)][int]$Qty,
  [string]$Colors = "1",
  [switch]$Pms,
  [string]$ReorderPath = "",
  [ValidateSet("lower48", "outside", "unknown")][string]$Destination = "lower48",
  [string]$NeedBy = "",
  [string]$Today = "",
  [int]$ProofDays = 1,
  [int]$TransitBufferDays = 5,
  [string]$PricingFile = ""
)

$ErrorActionPreference = "Stop"
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
$inv = [System.Globalization.CultureInfo]::InvariantCulture

if (-not $PricingFile) { $PricingFile = Join-Path $PSScriptRoot "..\data\pricing.json" }
$P = Get-Content -Raw -Encoding UTF8 $PricingFile | ConvertFrom-Json

# ---------- helpers ----------
function D($x) { return [decimal]::Parse(([string]$x), $inv) }
function Money([decimal]$v) { return '$' + $v.ToString("#,##0.00", $inv) }
function Price([decimal]$v) { return '$' + $v.ToString("0.00#", $inv) }
function QtyFmt([int]$v) { return $v.ToString("#,##0", $inv) }
function DateFmt([datetime]$d) { return $d.ToString("ddd MMM d", $inv) }
function Add-BusinessDays([datetime]$d, [int]$n) {
  $r = $d
  while ($n -gt 0) {
    $r = $r.AddDays(1)
    if ($r.DayOfWeek -ne 'Saturday' -and $r.DayOfWeek -ne 'Sunday') { $n-- }
  }
  return $r
}
function Get-Tier($path, [int]$q) {
  foreach ($t in $path.tiers) {
    $max = $t.max
    if ($q -ge $t.min -and ($null -eq $max -or $q -le $max)) { return $t }
  }
  return $null
}

# ---------- inputs ----------
if (-not $Today) { $Today = $P.today }
$todayDate = [datetime]::ParseExact($Today, "yyyy-MM-dd", $inv)
$proofDate = Add-BusinessDays $todayDate $ProofDays
$needDate = $null
if ($NeedBy) { $needDate = [datetime]::ParseExact($NeedBy, "yyyy-MM-dd", $inv) }

$isFull = ($Colors -match '^(full|fullcolor|cmyk)$')
$colorCount = 0
if (-not $isFull) { $colorCount = [int]$Colors }
$colorLabel = "full color"
if (-not $isFull) {
  $plural = "s"; if ($colorCount -eq 1) { $plural = "" }
  $colorLabel = "$colorCount color$plural"
}
if ($Pms) { $colorLabel += " (PMS match)" }

$freeThreshold = D $P.shipping.free_freight_threshold
$flatRate = D $P.shipping.flat_rate_under_threshold

function Get-DeadlineStatus([datetime]$earliest, [datetime]$latest) {
  if ($null -eq $script:needDate) { return "none" }
  $safeShip = $script:needDate
  for ($i = 0; $i -lt $script:TransitBufferDays; $i++) {
    do { $safeShip = $safeShip.AddDays(-1) } while ($safeShip.DayOfWeek -eq 'Saturday' -or $safeShip.DayOfWeek -eq 'Sunday')
  }
  if ($latest -le $safeShip) { return "on track" }
  if ($earliest -le $script:needDate) { return "tight" }
  return "misses"
}

function Build-Option([string]$key, [int]$sz, [int]$q, [bool]$rush = $false) {
  $path = $P.paths.$key
  $o = [ordered]@{
    path = $key; name = $path.name; rush = $rush; size_oz = $sz; qty = $q
    eligible = $true; reasons = @()
  }
  $reasons = New-Object System.Collections.ArrayList

  if (-not ($path.sizes -contains $sz)) { [void]$reasons.Add("$($path.name) does not offer $sz oz (sizes: $(($path.sizes -join ', ')) oz)") }
  if ($q -lt $path.min_qty) { [void]$reasons.Add("$($path.name) minimum is $(QtyFmt $path.min_qty) cups") }
  if ($null -ne $path.max_qty -and $q -gt $path.max_qty) { [void]$reasons.Add("$($path.name) maximum is $(QtyFmt $path.max_qty) cups") }
  if (($q % $path.multiple) -ne 0) { [void]$reasons.Add("quantity must be a multiple of $(QtyFmt $path.multiple)") }
  if ($key -eq "usa") {
    if ($isFull) { [void]$reasons.Add("USA partner prints spot colors only (max $($path.max_colors)); full color, gradients, or photos need in-house digital or overseas") }
    elseif ($colorCount -gt $path.max_colors) { [void]$reasons.Add("USA partner maximum is $($path.max_colors) ink colors") }
  }
  if ($key -eq "inhouse" -and $Pms) { [void]$reasons.Add("customer needs an exact Pantone match; in-house digital is close match only, no PMS guarantee") }

  if ($reasons.Count -gt 0) { $o.eligible = $false; $o.reasons = @($reasons); return [pscustomobject]$o }

  $tier = Get-Tier $path $q
  $base = D ($tier.prices.([string]$sz))
  $lines = New-Object System.Collections.ArrayList
  $per = $base
  $extraColors = 0
  if ($key -eq "usa") { $extraColors = [Math]::Max(0, $colorCount - [int]$path.included_colors) }
  if ($extraColors -gt 0) {
    $extraPer = (D $path.extra_color_per_cup) * $extraColors
    $per = $base + $extraPer
    $cups = $per * $q
    $extraEach = '$' + (D $path.extra_color_per_cup).ToString("0.000", $inv)
    [void]$lines.Add("Cups: $(QtyFmt $q) x $(Price $per) ($(Price $base) base + $extraEach x $extraColors color(s) beyond the 2 included) = $(Money $cups)")
  } else {
    $cups = $per * $q
    [void]$lines.Add("Cups: $(QtyFmt $q) x $(Price $per) = $(Money $cups)")
  }

  $rushAdd = [decimal]0
  if ($rush) {
    $rushAdd = [Math]::Round($cups * (D $path.rush.cup_cost_surcharge), 2)
    [void]$lines.Add("Rush surcharge: $(Money $cups) x 15% = $(Money $rushAdd) (cup cost only; rush must be confirmed by the owner)")
  }

  $setup = [decimal]0
  $isReorder = ($ReorderPath -eq $key)
  switch ($path.setup.type) {
    "none" { [void]$lines.Add("Setup: none for in-house digital = `$0.00") }
    "per_color" {
      if ($isReorder) { [void]$lines.Add("Setup: waived (unchanged reorder, plates on file) = `$0.00") }
      else {
        $setup = (D $path.setup.amount) * $colorCount
        [void]$lines.Add("Setup (plates): $colorCount color(s) x $(Money (D $path.setup.amount)) = $(Money $setup)")
      }
    }
    "flat" {
      if ($isReorder) { [void]$lines.Add("Setup: waived (unchanged reorder of same design) = `$0.00") }
      else {
        $setup = D $path.setup.amount
        [void]$lines.Add("Setup: flat $(Money $setup) per design")
      }
    }
  }

  $subtotal = $cups + $rushAdd + $setup
  [void]$lines.Add("Subtotal: $(Money $subtotal)")
  $shipping = $null
  $total = $null
  if ($Destination -eq "outside") {
    [void]$lines.Add("Freight: outside the lower 48, no standard rate. The owner will quote freight (and any duties)")
    [void]$lines.Add("TOTAL: $(Money $subtotal) + freight TBD")
  } else {
    if ($subtotal -ge $freeThreshold) {
      $shipping = [decimal]0
      [void]$lines.Add("Freight: FREE (lower 48, subtotal is $(Money $freeThreshold) or more)")
    } else {
      $shipping = $flatRate
      [void]$lines.Add("Freight: $(Money $flatRate) flat (subtotal under $(Money $freeThreshold))")
    }
    $total = $subtotal + $shipping
    [void]$lines.Add("TOTAL: $(Money $total)")
  }

  # Lead time / ship window
  if ($rush) {
    $earliest = $proofDate.AddDays(7 * [int]$path.rush.weeks); $latest = $earliest
    $leadText = "$($path.rush.weeks)-week rush after proof approval (only if the owner confirms)"
  } elseif ($path.lead.unit -eq "business_days") {
    $earliest = Add-BusinessDays $proofDate ([int]$path.lead.min)
    $latest = Add-BusinessDays $proofDate ([int]$path.lead.max)
    $leadText = "$($path.lead.min)-$($path.lead.max) business days after proof approval"
  } else {
    $earliest = $proofDate.AddDays(7 * [int]$path.lead.min)
    $latest = $proofDate.AddDays(7 * [int]$path.lead.max)
    $leadText = "$($path.lead.min)-$($path.lead.max) weeks after proof approval"
    if ($path.lead.note) { $leadText += " ($($path.lead.note.TrimEnd('.').ToLower()))" }
  }
  $status = Get-DeadlineStatus $earliest $latest
  $windowText = "ships approx $(DateFmt $earliest)"
  if ($latest -ne $earliest) { $windowText += " - $(DateFmt $latest)" }
  $windowText += " if the proof is approved by $(DateFmt $proofDate) (transit time not included)"
  [void]$lines.Add("Lead time: $leadText; $windowText")
  if ($status -ne "none") { [void]$lines.Add("Need-by $(DateFmt $needDate): $status") }
  if ($path.color_note) { [void]$lines.Add("Color: $($path.color_note)") }

  $o.per_cup = [double]$per
  $o.tier = if ($null -eq $tier.max) { "$(QtyFmt $tier.min)+" } else { "$(QtyFmt $tier.min)-$(QtyFmt $tier.max)" }
  $o.cups = [double]$cups
  $o.rush_surcharge = [double]$rushAdd
  $o.setup = [double]$setup
  $o.subtotal = [double]$subtotal
  $o.shipping = if ($null -eq $shipping) { $null } else { [double]$shipping }
  $o.total = if ($null -eq $total) { $null } else { [double]$total }
  $o.order_value = [double]$(if ($null -eq $total) { $subtotal } else { $total })
  $o.lead = $leadText
  $o.ships_earliest = $earliest.ToString("yyyy-MM-dd")
  $o.ships_latest = $latest.ToString("yyyy-MM-dd")
  $o.deadline_status = $status
  $o.lines = @($lines)
  return [pscustomobject]$o
}

# ---------- evaluate all paths ----------
$options = @()
foreach ($k in @("inhouse", "usa", "overseas")) { $options += , (Build-Option $k $Size $Qty) }
$eligible = @($options | Where-Object { $_.eligible })
$ineligible = @($options | Where-Object { -not $_.eligible })

$rushOpt = $null
$usaStd = $eligible | Where-Object { $_.path -eq "usa" }
if ($usaStd -and $needDate -and $usaStd.deadline_status -ne "on track") {
  $rushOpt = Build-Option "usa" $Size $Qty $true
}

# Recommended: cheapest standard option that is on track, else tight, else cheapest overall
$recommended = $null
foreach ($want in @("on track", "none", "tight")) {
  $c = @($eligible | Where-Object { $_.deadline_status -eq $want } | Sort-Object order_value)
  if ($c.Count -gt 0) { $recommended = $c[0]; break }
}
if (-not $recommended -and $eligible.Count -gt 0) { $recommended = @($eligible | Sort-Object order_value)[0] }

# Alternatives when nothing fits as asked
$alternatives = @()
if ($eligible.Count -eq 0) {
  $cands = @()
  $roundUp = [int]([Math]::Ceiling($Qty / 1000.0) * 1000)
  $roundDown = [int]([Math]::Floor($Qty / 1000.0) * 1000)
  foreach ($k in @("inhouse", "usa", "overseas")) {
    $path = $P.paths.$k
    $altSize = $Size
    $sizeNote = "same size"
    if (-not ($path.sizes -contains $Size)) {
      $altSize = [int](@($path.sizes | Sort-Object { [Math]::Abs($_ - $Size) })[0])
      $sizeNote = "nearest size $($path.name) offers ($altSize oz)"
    }
    $qs = @()
    if ($roundUp -lt $path.min_qty) { $qs += , @([int]$path.min_qty, "quantity raised to the $($path.name) minimum of $(QtyFmt $path.min_qty)") }
    else {
      if ($roundUp -ne $Qty) { $qs += , @($roundUp, "rounded up to $(QtyFmt $roundUp) (orders are in multiples of 1,000)") }
      else { $qs += , @($Qty, "") }
      if ($roundDown -ne $Qty -and $roundDown -ge $path.min_qty) { $qs += , @($roundDown, "rounded down to $(QtyFmt $roundDown) (orders are in multiples of 1,000)") }
    }
    foreach ($qq in $qs) {
      if ($null -ne $path.max_qty -and $qq[0] -gt $path.max_qty) { continue }
      $why = (@($sizeNote, $qq[1]) | Where-Object { $_ }) -join ", "
      $cands += , @($k, $altSize, $qq[0], $why)
    }
  }
  foreach ($c in $cands) {
    $alt = Build-Option $c[0] $c[1] $c[2]
    if ($alt.eligible -and ($alt.qty -le 2 * $Qty -or $alt.size_oz -ne $Size)) { $alt | Add-Member -NotePropertyName why -NotePropertyValue $c[3]; $alternatives += , $alt }
  }
  $alternatives = @($alternatives | Sort-Object order_value)
}

# ---------- flags ----------
$threshold = D $P.escalation_order_value
$flags = [ordered]@{
  value_over_5k    = $false
  outside_lower48  = ($Destination -eq "outside")
  rush_needed      = $false
  deadline_at_risk = $false
  no_path_as_asked = ($eligible.Count -eq 0)
}
if ($recommended) {
  if ((D $recommended.order_value) -ge $threshold) { $flags.value_over_5k = $true }
  if ($recommended.deadline_status -eq "tight") { $flags.deadline_at_risk = $true }
  if ($recommended.deadline_status -eq "misses") { $flags.deadline_at_risk = $true; $flags.rush_needed = $true }
}
if ($rushOpt -and $recommended -and $recommended.deadline_status -ne "on track") { $flags.rush_needed = $true }

# ---------- quote text ----------
$sb = New-Object System.Text.StringBuilder
$hdr = "$(QtyFmt $Qty) x $Size oz custom cups, $colorLabel"
if ($ReorderPath) { $hdr += ", unchanged reorder" }
[void]$sb.AppendLine("REQUEST: $hdr")
function Add-OptText($label, $o) {
  [void]$script:sb.AppendLine("")
  [void]$script:sb.AppendLine("$label $($o.name)$(if ($o.rush) { ' - RUSH' } else { '' }) ($(QtyFmt $o.qty) x $($o.size_oz) oz)")
  foreach ($l in $o.lines) { [void]$script:sb.AppendLine("  $l") }
}
if ($recommended) { Add-OptText "RECOMMENDED:" $recommended }
foreach ($o in ($eligible | Where-Object { $_ -ne $recommended } | Sort-Object order_value)) { Add-OptText "ALSO AVAILABLE:" $o }
if ($rushOpt -and $rushOpt.eligible) { Add-OptText "RUSH OPTION (owner must confirm):" $rushOpt }
foreach ($o in $alternatives) { Add-OptText "ALTERNATIVE ($($o.why)):" $o }
if ($ineligible.Count -gt 0) {
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("NOT AVAILABLE AS ASKED:")
  foreach ($o in $ineligible) { [void]$sb.AppendLine("  $($o.name): $($o.reasons -join '; ')") }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Terms: estimate valid 30 days, excludes sales tax; 50% deposit to start, balance before shipping; digital proof with every order.")
if ($Destination -eq "unknown") { [void]$sb.AppendLine("Assumption: priced for delivery in the lower 48; freight changes if it ships elsewhere.") }

$result = [ordered]@{
  input            = [ordered]@{ size_oz = $Size; qty = $Qty; colors = $Colors; pms = [bool]$Pms; reorder_path = $ReorderPath; destination = $Destination; need_by = $NeedBy; today = $Today; proof_assumed = $proofDate.ToString("yyyy-MM-dd") }
  recommended_path = if ($recommended) { $recommended.path } else { $null }
  recommended      = $recommended
  options          = $eligible
  rush_option      = $rushOpt
  alternatives     = $alternatives
  not_available    = @($ineligible | ForEach-Object { [ordered]@{ path = $_.path; name = $_.name; reasons = $_.reasons } })
  flags            = $flags
  quote_text       = $sb.ToString().Replace("`r`n", "`n").TrimEnd()
}
$result | ConvertTo-Json -Depth 8
