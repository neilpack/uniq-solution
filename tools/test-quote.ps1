<#
.SYNOPSIS
  Regression tests for tools/quote.ps1. Run after any change to data/pricing.json or the engine.
  powershell -ExecutionPolicy Bypass -File tools/test-quote.ps1
#>
$ErrorActionPreference = "Stop"
$engine = Join-Path $PSScriptRoot "quote.ps1"
$script:fail = 0; $script:pass = 0

function Q([string[]]$argList) {
  $json = & powershell -NoProfile -ExecutionPolicy Bypass -File $engine @argList
  return ($json -join "`n") | ConvertFrom-Json
}
function Check([string]$name, $actual, $expected) {
  if ("$actual" -eq "$expected") { $script:pass++; Write-Host "  PASS  $name = $expected" -ForegroundColor Green }
  else { $script:fail++; Write-Host "  FAIL  $name : expected '$expected' got '$actual'" -ForegroundColor Red }
}

Write-Host "20k 8oz 2c PMS, need Apr 15 (USA partner)"
$r = Q @("-Size", "8", "-Qty", "20000", "-Colors", "2", "-Pms", "-NeedBy", "2027-04-15")
Check "path" $r.recommended_path "usa"
Check "total" $r.recommended.total 2600
Check "shipping" $r.recommended.shipping 0
Check "deadline" $r.recommended.deadline_status "on track"
Check "over 5k" $r.flags.value_over_5k $false

Write-Host "3k 12oz full color, need Mar 27 (in-house)"
$r = Q @("-Size", "12", "-Qty", "3000", "-Colors", "full", "-NeedBy", "2027-03-27")
Check "path" $r.recommended_path "inhouse"
Check "total" $r.recommended.total 875
Check "deadline" $r.recommended.deadline_status "tight"

Write-Host "150k 16oz 2c PMS (overseas vs USA)"
$r = Q @("-Size", "16", "-Qty", "150000", "-Colors", "2", "-Pms")
Check "path" $r.recommended_path "overseas"
Check "total" $r.recommended.total 10900
Check "usa total" (($r.options | Where-Object { $_.path -eq "usa" }).total) 16650
Check "over 5k" $r.flags.value_over_5k $true

Write-Host "60k 8oz 3c, need Apr 5"
$r = Q @("-Size", "8", "-Qty", "60000", "-Colors", "3", "-NeedBy", "2027-04-05")
Check "path" $r.recommended_path "usa"
Check "total" $r.recommended.total 6390
Check "rush total" $r.rush_option.total 7281
Check "overseas deadline" (($r.options | Where-Object { $_.path -eq "overseas" }).deadline_status) "misses"
Check "rush needed" $r.flags.rush_needed $true

Write-Host "12k 8oz 1c"
$r = Q @("-Size", "8", "-Qty", "12000", "-Colors", "1")
Check "total" $r.recommended.total 1625
Check "shipping" $r.recommended.shipping 95

Write-Host "30k 8oz 2c"
$r = Q @("-Size", "8", "-Qty", "30000", "-Colors", "2")
Check "total" $r.recommended.total 3240

Write-Host "50k 8oz 2c unchanged USA reorder, need Apr 15"
$r = Q @("-Size", "8", "-Qty", "50000", "-Colors", "2", "-ReorderPath", "usa", "-NeedBy", "2027-04-15")
Check "path" $r.recommended_path "usa"
Check "setup" $r.recommended.setup 0
Check "total" $r.recommended.total 4450
Check "over 5k" $r.flags.value_over_5k $false

Write-Host "5k 16oz 1c (not offered as asked)"
$r = Q @("-Size", "16", "-Qty", "5000", "-Colors", "1")
Check "no path" $r.flags.no_path_as_asked $true
Check "alt in-house 12oz" (($r.alternatives | Where-Object { $_.path -eq "inhouse" }).total) 1395
Check "alt usa 10k 16oz" (($r.alternatives | Where-Object { $_.path -eq "usa" }).total) 1665

Write-Host "2k 8oz full color"
$r = Q @("-Size", "8", "-Qty", "2000", "-Colors", "full")
Check "total" $r.recommended.total 535

Write-Host "30k 12oz 1c to Canada"
$r = Q @("-Size", "12", "-Qty", "30000", "-Colors", "1", "-Destination", "outside")
Check "subtotal" $r.recommended.subtotal 3450
Check "outside flag" $r.flags.outside_lower48 $true

Write-Host ""
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
