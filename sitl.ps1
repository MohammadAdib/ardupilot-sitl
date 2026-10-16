<#
.SYNOPSIS
  Launch ArduPilot SITL (prebuilt Windows binaries) for copter or plane.

.EXAMPLE
  .\sitl.ps1 copter
  .\sitl.ps1 plane -Speedup 5
  .\sitl.ps1 copter -Instance 1 -Wipe
  .\sitl.ps1 copter -Model hexa -Home "37.4133,-121.9967,10,0"
  .\sitl.ps1 plane -Home Woodley
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

  # Reset parameters/eeprom to defaults.
  [switch]$Wipe,

  # Extra UDP stream for GCS apps that listen on 14550 (+10*Instance). Set to '' to disable.
  [string]$UdpOut = "127.0.0.1:$(14550 + 10 * $Instance)",

  # Hold the sim at boot until a GCS connects to the TCP port (SITL's stock behavior).
  [switch]$WaitForGcs,

  # Extra args passed straight to the SITL binary.
  [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot $Vehicle
$exe = Join-Path $dir $(if ($Vehicle -eq 'copter') { 'ArduCopter.exe' } else { 'ArduPlane.exe' })
$defaults = Join-Path $dir "$Vehicle.parm"
if (-not $Model) { $Model = if ($Vehicle -eq 'copter') { 'quad' } else { 'plane' } }

# eeprom.bin, logs and terrain land in the working directory, so keep one per instance.
$runDir = Join-Path $dir "run$Instance"
New-Item -ItemType Directory -Force $runDir | Out-Null

# The binary only knows the locations.txt baked into its ROMFS, so resolve names
# from our own copy (like sim_vehicle.py does) and pass coordinates.
if ($Location -notmatch ',') {
  $line = Get-Content (Join-Path $PSScriptRoot 'autotest\locations.txt') |
    Where-Object { $_ -match "^\s*$([regex]::Escape($Location))\s*=" } | Select-Object -First 1
  if (-not $line) { throw "Location '$Location' not found in autotest\locations.txt" }
  $Location = ($line -split '=', 2)[1].Trim()
}

$sitlArgs = @('-M', $Model, '-O', $Location, '-s', $Speedup, '-I', $Instance, '--defaults', $defaults,
  '--serial0', $(if ($WaitForGcs) { 'tcp:0:wait' } else { 'tcp:0' }))
if ($Wipe) { $sitlArgs += '-w' }
if ($UdpOut) { $sitlArgs += @('--serial1', "udpclient:$UdpOut") }
$sitlArgs += $ExtraArgs

$tcp = 5760 + 10 * $Instance
Write-Host "ArduPilot SITL: $Vehicle (model $Model), instance $Instance" -ForegroundColor Cyan
Write-Host "  Home        : $Location"
Write-Host "  MAVLink TCP : 127.0.0.1:$tcp (SERIAL0)"
if ($UdpOut) { Write-Host "  MAVLink UDP : sending to $UdpOut (SERIAL1)" }
Write-Host "  Run dir     : $runDir"
Write-Host "  Ctrl+C to stop`n"

Push-Location $runDir
try { & $exe @sitlArgs } finally { Pop-Location }
