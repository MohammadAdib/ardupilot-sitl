#!/usr/bin/env bash
# Launch ArduPilot SITL on Linux for copter or plane (counterpart of sitl.ps1).
#
#   ./sitl.sh copter
#   ./sitl.sh plane --speedup 5
#   ./sitl.sh copter --instance 1 --wipe
#   ./sitl.sh copter --model hexa --home "37.4133,-121.9967,10,0"
#   ./sitl.sh plane --home Woodley
#   ./sitl.sh copter -- --some-sitl-flag value     # args after -- go to the binary
#
# The bundled .exe files are Windows-only, so on first run this downloads the
# official Linux SITL build from firmware.ardupilot.org into <vehicle>/ (or use
# --bin to point at your own build, e.g. ardupilot/build/sitl/bin/arducopter).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 {copter|plane} [options] [-- extra SITL args]

  --model M         SITL physics model (default: quad for copter, plane for plane)
  --home LOC        lat,lon,alt,hdg or a name from autotest/locations.txt (default: CMAC)
  --speedup N       simulation speedup (default: 1)
  --instance N      shifts all ports by 10*N; separate eeprom/logs in <vehicle>/runN (default: 0)
  --wipe            reset parameters/eeprom to defaults
  --udp-out ADDR    extra MAVLink UDP stream (default: 127.0.0.1:14550+10N; '' to disable)
  --wait-for-gcs    hold boot until a GCS connects on TCP
  --bin PATH        use this SITL binary instead of the downloaded one
  --update          re-download the Linux binary
  -h, --help        show this help
EOF
}

die() { echo "error: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || { usage >&2; exit 1; }
case "$1" in
  copter) vehicle=copter; bin_name=arducopter; fw_dir=Copter; model=quad ;;
  plane)  vehicle=plane;  bin_name=arduplane;  fw_dir=Plane;  model=plane ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; die "vehicle must be 'copter' or 'plane'" ;;
esac
shift

location='-35.363261,149.165230,584,353'   # CMAC field (Canberra)
speedup=1
instance=0
wipe=0
wait_gcs=0
udp_out=
udp_out_set=0
bin=
update=0
extra=()

need() { [[ $# -ge 2 ]] || die "$1 needs a value"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)            need "$@"; model="$2"; shift 2 ;;
    --home|--location)  need "$@"; location="$2"; shift 2 ;;
    --speedup)          need "$@"; speedup="$2"; shift 2 ;;
    --instance)         need "$@"; instance="$2"; shift 2 ;;
    --udp-out)          need "$@"; udp_out="$2"; udp_out_set=1; shift 2 ;;
    --bin)              need "$@"; bin="$2"; shift 2 ;;
    --wipe)             wipe=1; shift ;;
    --wait-for-gcs)     wait_gcs=1; shift ;;
    --update)           update=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    --)                 shift; extra=("$@"); break ;;
    *)                  usage >&2; die "unknown option: $1" ;;
  esac
done

[[ "$instance" =~ ^[0-9]+$ ]] || die "--instance must be a non-negative integer"
[[ $udp_out_set -eq 1 ]] || udp_out="127.0.0.1:$((14550 + 10 * instance))"

dir="$root/$vehicle"
defaults="$dir/$vehicle.parm"

# Fetch the official Linux SITL binary if we don't have one yet.
if [[ -z "$bin" ]]; then
  bin="$dir/$bin_name"
  if [[ $update -eq 1 || ! -x "$bin" ]]; then
    case "$(uname -m)" in
      x86_64|amd64)  plat=SITL_x86_64_linux_gnu ;;
      armv7l|armv6l) plat=SITL_arm_linux_gnueabihf ;;
      *) die "no prebuilt Linux SITL for $(uname -m); build one (./waf configure --board sitl && ./waf $vehicle) and pass --bin" ;;
    esac
    url="https://firmware.ardupilot.org/$fw_dir/stable/$plat"
    echo "Downloading $url/$bin_name ..."
    if command -v curl >/dev/null; then
      fetch() { curl -fL --progress-bar -o "$2" "$1"; }
    elif command -v wget >/dev/null; then
      fetch() { wget -q --show-progress -O "$2" "$1"; }
    else
      die "need curl or wget to download the SITL binary"
    fi
    fetch "$url/$bin_name" "$bin.tmp" || { rm -f "$bin.tmp"; die "download failed"; }
    fetch "$url/git-version.txt" "$dir/git-linux.txt" 2>/dev/null || rm -f "$dir/git-linux.txt"
    chmod +x "$bin.tmp"
    mv "$bin.tmp" "$bin"
  fi
fi
[[ -x "$bin" ]] || die "SITL binary not found or not executable: $bin"

# The binary only knows the locations.txt baked into it, so resolve names
# from our own copy (like sim_vehicle.py does) and pass coordinates.
if [[ "$location" != *,* ]]; then
  resolved="$(awk -F= -v name="$location" '
    { key = $1; gsub(/^[ \t]+|[ \t]+$/, "", key) }
    key == name { sub(/^[^=]*=/, ""); gsub(/^[ \t]+|[ \t\r]+$/, ""); print; exit }
  ' "$root/autotest/locations.txt")"
  [[ -n "$resolved" ]] || die "location '$location' not found in autotest/locations.txt"
  location="$resolved"
fi

serial0=tcp:0
[[ $wait_gcs -eq 1 ]] && serial0=tcp:0:wait
args=(-M "$model" -O "$location" -s "$speedup" -I "$instance" --defaults "$defaults" --serial0 "$serial0")
[[ $wipe -eq 1 ]] && args+=(-w)
[[ -n "$udp_out" ]] && args+=(--serial1 "udpclient:$udp_out")
args+=(${extra[@]+"${extra[@]}"})

# eeprom.bin, logs and terrain land in the working directory, so keep one per instance.
run_dir="$dir/run$instance"
mkdir -p "$run_dir"

tcp=$((5760 + 10 * instance))
printf '\033[36mArduPilot SITL: %s (model %s), instance %s\033[0m\n' "$vehicle" "$model" "$instance"
echo "  Home        : $location"
echo "  MAVLink TCP : 127.0.0.1:$tcp (SERIAL0)"
[[ -n "$udp_out" ]] && echo "  MAVLink UDP : sending to $udp_out (SERIAL1)"
echo "  Run dir     : $run_dir"
echo "  Binary      : $bin"
echo "  Ctrl+C to stop"
echo

cd "$run_dir"
exec "$bin" "${args[@]}"
