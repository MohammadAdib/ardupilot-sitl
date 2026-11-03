<#
.SYNOPSIS
  Launch ArduPilot SITL (prebuilt Windows binaries) for copter or plane.
  On Linux use ./sitl.sh instead (same options, GNU-style: --home, --speedup, ...).

.EXAMPLE
  .\sitl.ps1 copter
  .\sitl.ps1 plane -Speedup 5
  .\sitl.ps1 copter -Instance 1 -Wipe
  .\sitl.ps1 copter -Model hexa -Home "37.4133,-121.9967,10,0"
  .\sitl.ps1 plane -Home Woodley
  .\sitl.ps1 copter -Swarm 5
  .\sitl.ps1 plane -Swarm 3 -Home Woodley -Spacing 20
#>
param(
  [Parameter(Mandatory, Position = 0)]
  [ValidateSet('copter', 'plane')]
  [string]$Vehicle,

  # SITL physics model; defaults to 'quad' for copter, 'plane' for plane.
  [string]$Model,

  # lat,lon,alt(m AMSL),heading, or a name from autotest\locations.txt (e.g. Woodley).
  # Default is ArduPilot's CMAC field (Canberra).
  [Alias('Home')]
  [string]$Location = '-35.363261,149.165230,584,353',

  [double]$Speedup = 1,

  # Each instance shifts all ports by 10*N and gets its own eeprom/logs.
  [int]$Instance = 0,

  # Launch N vehicles (instances Instance..Instance+N-1, MAVLink sysid = instance+1),
  # lined up behind -Home along its heading, -Spacing metres apart.
  [ValidateRange(1, 100)]
  [int]$Swarm = 1,

  [double]$Spacing = 10,

  # Reset parameters/eeprom to defaults.
  [switch]$Wipe,

  # Extra UDP stream for GCS apps that listen on 14550. Default: 127.0.0.1:14550+10*Instance,
  # or 127.0.0.1:14550 for every vehicle of a swarm (one GCS sees all). Set to '' to disable.
  [string]$UdpOut,

  # Hold the sim at boot until a GCS connects to the TCP port (SITL's stock behavior).
  [switch]$WaitForGcs,

  # Extra args passed straight to the SITL binary.
  [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
$inv = [cultureinfo]::InvariantCulture
$dir = Join-Path $PSScriptRoot $Vehicle
$exe = Join-Path $dir $(if ($Vehicle -eq 'copter') { 'ArduCopter.exe' } else { 'ArduPlane.exe' })
$defaults = Join-Path $dir "$Vehicle.parm"
if (-not $Model) { $Model = if ($Vehicle -eq 'copter') { 'quad' } else { 'plane' } }
if (-not $PSBoundParameters.ContainsKey('UdpOut')) {
  $UdpOut = if ($Swarm -gt 1) { '127.0.0.1:14550' } else { "127.0.0.1:$(14550 + 10 * $Instance)" }
}

# The binary only knows the locations.txt baked into its ROMFS, so resolve names
# from our own copy (like sim_vehicle.py does) and pass coordinates.
if ($Location -notmatch ',') {
  $line = Get-Content (Join-Path $PSScriptRoot 'autotest\locations.txt') |
    Where-Object { $_ -match "^\s*$([regex]::Escape($Location))\s*=" } | Select-Object -First 1
  if (-not $line) { throw "Location '$Location' not found in autotest\locations.txt" }
  $Location = ($line -split '=', 2)[1].Trim()
}

# Home of swarm member $k: $k*Spacing metres behind -Home, along its heading.
function Get-SwarmHome([int]$k) {
  if ($k -eq 0) { return $Location }
  $p = $Location -split ','
  $lat = [double]::Parse($p[0], $inv); $lon = [double]::Parse($p[1], $inv)
  $alt = if ($p.Count -gt 2) { $p[2] } else { '0' }
  $hdg = if ($p.Count -gt 3) { $p[3] } else { '0' }
  $h = [double]::Parse($hdg, $inv) * [math]::PI / 180
  $d = -$k * $Spacing
  $lat2 = $lat + $d * [math]::Cos($h) / 111319.5
  $lon2 = $lon + $d * [math]::Sin($h) / (111319.5 * [math]::Cos($lat * [math]::PI / 180))
  [string]::Format($inv, '{0:F7},{1:F7},{2},{3}', $lat2, $lon2, $alt, $hdg)
}

function Get-SitlArgs([int]$inst, [string]$loc, [int]$sysid) {
  $a = @('-M', $Model, '-O', $loc, '-s', $Speedup.ToString($inv), '-I', $inst, '--defaults', $defaults,
    '--serial0', $(if ($WaitForGcs) { 'tcp:0:wait' } else { 'tcp:0' }))
  if ($sysid) { $a += @('--sysid', $sysid) }
  if ($Wipe) { $a += '-w' }
  if ($UdpOut) { $a += @('--serial1', "udpclient:$UdpOut") }
  $a + $ExtraArgs
}

function New-RunDir([int]$inst) {
  # eeprom.bin, logs and terrain land in the working directory, so keep one per instance.
  $d = Join-Path $dir "run$inst"
  New-Item -ItemType Directory -Force $d | Out-Null
  $d
}

if ($Swarm -eq 1) {
  $runDir = New-RunDir $Instance
  $tcp = 5760 + 10 * $Instance
  Write-Host "ArduPilot SITL: $Vehicle (model $Model), instance $Instance" -ForegroundColor Cyan
  Write-Host "  Home        : $Location"
  Write-Host "  MAVLink TCP : 127.0.0.1:$tcp (SERIAL0)"
  if ($UdpOut) { Write-Host "  MAVLink UDP : sending to $UdpOut (SERIAL1)" }
  Write-Host "  Run dir     : $runDir"
  Write-Host "  Ctrl+C to stop`n"

  $sitlArgs = Get-SitlArgs $Instance $Location 0
  Push-Location $runDir
  try { & $exe @sitlArgs } finally { Pop-Location }
  return
}

# Swarm: start every vehicle in the background, logging to its run dir.
function Format-Arg([string]$s) { if ($s -match '[\s"]' -or $s -eq '') { '"' + ($s -replace '"', '\"') + '"' } else { $s } }

Write-Host "ArduPilot SITL swarm: $Swarm x $Vehicle (model $Model), $Spacing m apart along home heading" -ForegroundColor Cyan
if ($UdpOut) { Write-Host "  MAVLink UDP : all vehicles sending to $UdpOut (SERIAL1)" }
Write-Host ''
Write-Host ('  {0,-4} {1,-6} {2,-16} {3}' -f 'inst', 'sysid', 'TCP', 'home')
$procs = @()
try {
  for ($k = 0; $k -lt $Swarm; $k++) {
    $inst = $Instance + $k
    $loc = Get-SwarmHome $k
    $runDir = New-RunDir $inst
    $argLine = (Get-SitlArgs $inst $loc ($inst + 1) | ForEach-Object { Format-Arg "$_" }) -join ' '
    $p = Start-Process -FilePath $exe -ArgumentList $argLine -WorkingDirectory $runDir -NoNewWindow -PassThru `
      -RedirectStandardOutput (Join-Path $runDir 'sitl.log') -RedirectStandardError (Join-Path $runDir 'sitl.err.log')
    $procs += [pscustomobject]@{ Instance = $inst; Process = $p; Reported = $false }
    Write-Host ('  {0,-4} {1,-6} {2,-16} {3}' -f $inst, ($inst + 1), "127.0.0.1:$(5760 + 10 * $inst)", $loc)
  }
  Write-Host "`n  Logs: $Vehicle\runN\sitl.log   Ctrl+C to stop all`n"

  while ($true) {
    Start-Sleep -Seconds 1
    $alive = 0
    foreach ($e in $procs) {
      if (-not $e.Process.HasExited) { $alive++ }
      elseif (-not $e.Reported) {
        $e.Reported = $true
        Write-Host "  instance $($e.Instance) exited (code $($e.Process.ExitCode)); see $Vehicle\run$($e.Instance)\sitl.log" -ForegroundColor Yellow
      }
    }
    if ($alive -eq 0) { break }
  }
} finally {
  foreach ($e in $procs) { if (-not $e.Process.HasExited) { Stop-Process -Id $e.Process.Id -Force -ErrorAction SilentlyContinue } }
}
