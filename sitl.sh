#!/usr/bin/env bash
# Launch ArduPilot SITL on Linux for copter or plane (counterpart of sitl.ps1).
#
#   ./sitl.sh copter
#   ./sitl.sh plane --speedup 5
#   ./sitl.sh copter --instance 1 --wipe
#   ./sitl.sh copter --model hexa --home "37.4133,-121.9967,10,0"
#   ./sitl.sh plane --home Woodley
#   ./sitl.sh copter --swarm 5
#   ./sitl.sh plane --swarm 3 --home Woodley --spacing 20
#   ./sitl.sh copter -- --some-sitl-flag value     # args after -- go to the binary
#
# sitl.ps1-style flags work too: ./sitl.sh plane -Home Woodley -Speedup 5
#
# The bundled .exe files are Windows-only, so on first run this downloads the
# official Linux SITL build from firmware.ardupilot.org into <vehicle>/. Where no
# prebuilt runs (e.g. 64-bit Raspberry Pi OS) it builds one from ArduPilot source
# at the commit in <vehicle>/git.txt. --bin PATH uses your own build instead.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 {copter|plane} [options] [-- extra SITL args]
  (sitl.ps1-style -Home, -Speedup, -WaitForGcs ... also accepted)

  --model M         SITL physics model (default: quad for copter, plane for plane)
  --home LOC        lat,lon,alt,hdg or a name from autotest/locations.txt (default: CMAC)
  --speedup N       simulation speedup (default: 1)
  --instance N      shifts all ports by 10*N; separate eeprom/logs in <vehicle>/runN (default: 0)
  --swarm N         launch N vehicles (instances N0..N0+N-1, sysid = instance+1), lined up
                    ahead of --home along its heading
  --spacing M       metres between swarm vehicles (default: 10)
  --wipe            reset parameters/eeprom to defaults
  --udp-out ADDR    extra MAVLink UDP stream (default: 127.0.0.1:14550+10N, or
                    127.0.0.1:14550 for every swarm vehicle; '' to disable)
  --wait-for-gcs    hold boot until a GCS connects on TCP
  --bin PATH        use this SITL binary instead of the downloaded one
  --update          re-download the Linux binary
  --build           build the binary from ArduPilot source (automatic if no prebuilt exists)
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
swarm=1
spacing=10
wipe=0
wait_gcs=0
udp_out=
udp_out_set=0
bin=
update=0
build=0
extra=()

need() { [[ $# -ge 2 ]] || die "$1 needs a value"; }
while [[ $# -gt 0 ]]; do
  [[ "$1" == -- ]] && { shift; extra=("$@"); break; }
  [[ "$1" == -* ]] || { usage >&2; die "unexpected argument: $1"; }
  # Accept both GNU style (--wait-for-gcs) and sitl.ps1 style (-WaitForGcs), any case.
  key="${1,,}"; key="${key#-}"; key="${key#-}"; key="${key//[-_]/}"
  case "$key" in
    model)             need "$@"; model="$2"; shift 2 ;;
    home|location)     need "$@"; location="$2"; shift 2 ;;
    speedup)           need "$@"; speedup="$2"; shift 2 ;;
    instance)          need "$@"; instance="$2"; shift 2 ;;
    swarm)             need "$@"; swarm="$2"; shift 2 ;;
    spacing)           need "$@"; spacing="$2"; shift 2 ;;
    udpout)            need "$@"; udp_out="$2"; udp_out_set=1; shift 2 ;;
    bin)               need "$@"; bin="$2"; shift 2 ;;
    wipe)              wipe=1; shift ;;
    waitforgcs)        wait_gcs=1; shift ;;
    update)            update=1; shift ;;
    build)             build=1; shift ;;
    h|help|\?)         usage; exit 0 ;;
    *)                 usage >&2; die "unknown option: $1" ;;
  esac
done

[[ "$instance" =~ ^[0-9]+$ ]] || die "--instance must be a non-negative integer"
[[ "$swarm" =~ ^[0-9]+$ ]] && (( swarm >= 1 && swarm <= 100 )) || die "--swarm must be 1..100"
[[ "$spacing" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--spacing must be a number of metres"
if [[ $udp_out_set -eq 0 ]]; then
  if (( swarm > 1 )); then udp_out=127.0.0.1:14550; else udp_out="127.0.0.1:$((14550 + 10 * instance))"; fi
fi

dir="$root/$vehicle"
defaults="$dir/$vehicle.parm"

download() {
  local plat="$1" url
  url="https://firmware.ardupilot.org/$fw_dir/stable/$plat"
  echo "Downloading $url/$bin_name ..."
  if command -v curl >/dev/null; then
    fetch() { curl -fL --progress-bar -o "$2" "$1"; }
  elif command -v wget >/dev/null; then
    fetch() { wget -q --show-progress -O "$2" "$1"; }
  else
    echo "need curl or wget to download the SITL binary" >&2; return 1
  fi
  fetch "$url/$bin_name" "$bin.tmp" || { rm -f "$bin.tmp"; return 1; }
  fetch "$url/git-version.txt" "$dir/git-linux.txt" 2>/dev/null || rm -f "$dir/git-linux.txt"
  chmod +x "$bin.tmp"
  mv "$bin.tmp" "$bin"
}

# Build from source at the same commit as the bundled Windows binaries
# (for platforms with no official prebuilt, e.g. 64-bit Raspberry Pi OS).
build_from_source() {
  local src="$root/.build/ardupilot" commit jobs
  commit="$(awk '/^commit /{print $2; exit}' "$dir/git.txt")"
  for t in git python3 g++ make; do
    command -v "$t" >/dev/null || die "building needs '$t' (sudo apt install git python3 python3-venv g++ make)"
  done
  echo "No prebuilt SITL for $(uname -m): building $bin_name from ArduPilot source at ${commit:0:10}."
  echo "This is a one-time step and can take 30-60+ minutes on a Raspberry Pi."
  if [[ ! -d "$src/.git" ]]; then
    mkdir -p "$src"
    git -C "$src" init -q
    git -C "$src" remote add origin https://github.com/ArduPilot/ardupilot
  fi
  if [[ "$(git -C "$src" rev-parse -q --verify HEAD 2>/dev/null)" != "$commit" ]]; then
    git -C "$src" fetch --depth 1 origin "$commit"
    git -C "$src" checkout -q --force FETCH_HEAD
  fi
  git -C "$src" submodule update --init --recursive --depth 1
  if [[ ! -x "$src/.venv/bin/python" ]]; then
    python3 -m venv "$src/.venv" || die "python3 -m venv failed (sudo apt install python3-venv)"
    "$src/.venv/bin/pip" install -q --upgrade pip setuptools wheel
    "$src/.venv/bin/pip" install -q empy==3.3.4 pexpect future lxml dronecan
  fi
  # ~1 GB RAM per compile job; keep low-memory Pis from swapping to death.
  jobs=$(nproc)
  local mem_gb=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
  (( mem_gb >= 1 && mem_gb < jobs )) && jobs=$mem_gb
  (( jobs < 1 )) && jobs=1
  (
    cd "$src"
    export PATH="$src/.venv/bin:$PATH"
    python waf configure --board sitl
    python waf "$vehicle" -j "$jobs"
  ) || die "build failed (source in $src; rerun to resume)"
  cp "$src/build/sitl/bin/$bin_name" "$bin.tmp"
  chmod +x "$bin.tmp"
  mv "$bin.tmp" "$bin"
  { echo "built from source"; cat "$dir/git.txt"; } > "$dir/git-linux.txt"
}

# Get a Linux SITL binary if we don't have one yet.
if [[ -z "$bin" ]]; then
  bin="$dir/$bin_name"
  if [[ $update -eq 1 || $build -eq 1 || ! -x "$bin" ]]; then
    case "$(uname -m)" in
      x86_64|amd64)  plats=(SITL_x86_64_linux_gnu) ;;
      armv7l|armv6l) plats=(SITL_arm_linux_gnueabihf) ;;
      # 64-bit ARM (e.g. Raspberry Pi 5): no official build, and the armhf one
      # needs 32-bit libs and breaks on 16K-page kernels, so build from source.
      *)             plats=() ;;
    esac
    ok=0
    if [[ $build -eq 0 ]]; then
      for p in ${plats[@]+"${plats[@]}"}; do download "$p" && { ok=1; break; }; done
    fi
    [[ $ok -eq 1 ]] || build_from_source
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

# Home of swarm member $1: $1*spacing metres ahead of --home, along its heading.
swarm_home() {
  [[ $1 -eq 0 ]] && { echo "$location"; return; }
  awk -v loc="$location" -v d="$1" -v sp="$spacing" 'BEGIN {
    n = split(loc, p, ","); alt = (n > 2) ? p[3] : 0; hdg = (n > 3) ? p[4] : 0
    pi = atan2(0, -1); h = hdg * pi / 180; d *= sp
    lat = p[1] + d * cos(h) / 111319.5
    lon = p[2] + d * sin(h) / (111319.5 * cos(p[1] * pi / 180))
    printf "%.7f,%.7f,%s,%s\n", lat, lon, alt, hdg
  }'
}

# Sets args=() for instance $1 at home $2, with MAVLink sysid $3 (0 = leave as is).
sitl_args() {
  local serial0=tcp:0
  [[ $wait_gcs -eq 1 ]] && serial0=tcp:0:wait
  args=(-M "$model" -O "$2" -s "$speedup" -I "$1" --defaults "$defaults" --serial0 "$serial0")
  [[ $3 -ne 0 ]] && args+=(--sysid "$3")
  [[ $wipe -eq 1 ]] && args+=(-w)
  [[ -n "$udp_out" ]] && args+=(--serial1 "udpclient:$udp_out")
  args+=(${extra[@]+"${extra[@]}"})
}

# eeprom.bin, logs and terrain land in the working directory, so keep one per instance.
run_dir_for() { run_dir="$dir/run$1"; mkdir -p "$run_dir"; }

if (( swarm == 1 )); then
  sitl_args "$instance" "$location" 0
  run_dir_for "$instance"
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
fi

# Swarm: start every vehicle in the background, logging to its run dir.
pids=()
insts=()
stop_all() {
  trap - INT TERM EXIT
  for pid in ${pids[@]+"${pids[@]}"}; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap 'stop_all; exit 130' INT TERM
trap stop_all EXIT

printf '\033[36mArduPilot SITL swarm: %s x %s (model %s), %s m apart along home heading\033[0m\n' \
  "$swarm" "$vehicle" "$model" "$spacing"
[[ -n "$udp_out" ]] && echo "  MAVLink UDP : all vehicles sending to $udp_out (SERIAL1)"
echo
printf '  %-4s %-6s %-16s %s\n' inst sysid TCP home
for (( k = 0; k < swarm; k++ )); do
  inst=$((instance + k))
  home="$(swarm_home "$k")"
  sitl_args "$inst" "$home" $((inst + 1))
  run_dir_for "$inst"
  ( cd "$run_dir" && exec "$bin" "${args[@]}" ) > "$run_dir/sitl.log" 2>&1 < /dev/null &
  pids+=($!)
  insts+=("$inst")
  printf '  %-4s %-6s %-16s %s\n' "$inst" $((inst + 1)) "127.0.0.1:$((5760 + 10 * inst))" "$home"
done
echo
echo "  Logs: $vehicle/runN/sitl.log   Ctrl+C to stop all"
echo

declare -A reported=()
while :; do
  sleep 1
  alive=0
  for i in "${!pids[@]}"; do
    if kill -0 "${pids[$i]}" 2>/dev/null; then
      alive=$((alive + 1))
    elif [[ -z "${reported[$i]:-}" ]]; then
      reported[$i]=1
      printf '\033[33m  instance %s exited; see %s\033[0m\n' "${insts[$i]}" "$dir/run${insts[$i]}/sitl.log"
    fi
  done
  (( alive > 0 )) || break
done
