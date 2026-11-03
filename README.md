# ArduPilot SITL (prebuilt, Windows + Linux)

Run ArduPilot Copter or Plane SITL without building anything: clone, run one script, connect a GCS.

- **Windows**: `sitl.ps1` runs the bundled official Cygwin SITL builds from
  `firmware.ardupilot.org/Tools/MissionPlanner/sitl/{CopterStable,PlaneStable}`
  (commit in `copter/git.txt`, `plane/git.txt`).
- **Linux**: `sitl.sh` downloads the official Linux SITL build from
  `firmware.ardupilot.org/{Copter,Plane}/stable/SITL_x86_64_linux_gnu` (or `SITL_arm_linux_gnueabihf`)
  into `copter/` / `plane/` on first run (commit saved to `<vehicle>/git-linux.txt`). Needs `curl` or `wget`.
- **Raspberry Pi 5 / 64-bit ARM Linux**: there is no official prebuilt, so `sitl.sh` builds the binary from
  ArduPilot source on first run, at the same commit as the Windows binaries (one-time, roughly 15-60 min
  depending on the board). Needs `sudo apt install git python3 python3-venv g++ make`.

Both scripts use the same default params (`copter/copter.parm`, `plane/plane.parm`), ports and run directories.

## Windows (PowerShell)

```powershell
git clone https://github.com/MohammadAdib/ardupilot-sitl
cd ardupilot-sitl
# once per machine, if scripts are blocked:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

.\sitl.ps1 copter
.\sitl.ps1 plane -Home Woodley
.\sitl.ps1 copter -Instance 1 -Speedup 5 -Wipe
.\sitl.ps1 copter -Swarm 5
```

## Linux (bash)

```bash
git clone https://github.com/MohammadAdib/ardupilot-sitl
cd ardupilot-sitl

./sitl.sh copter
./sitl.sh plane --home Woodley
./sitl.sh copter --instance 1 --speedup 5 --wipe
./sitl.sh copter --swarm 5
```

## Options

| Windows | Linux | Default | |
|---|---|---|---|
| `-Model` | `--model` | `quad` / `plane` | any SITL model, e.g. `hexa`, `octa`, `quadplane` |
| `-Home` | `--home` | CMAC | `lat,lon,alt,hdg` or a name from `autotest/locations.txt` |
| `-Speedup` | `--speedup` | 1 | |
| `-Instance N` | `--instance N` | 0 | shifts all ports by 10*N; separate eeprom/logs in `<vehicle>/runN` |
| `-Swarm N` | `--swarm N` | 1 | launch N vehicles at once (see [Swarms](#swarms)) |
| `-Spacing M` | `--spacing M` | 10 | metres between swarm vehicles |
| `-Wipe` | `--wipe` | | reset params to defaults |
| `-WaitForGcs` | `--wait-for-gcs` | | hold boot until something connects on TCP |
| `-UdpOut` | `--udp-out` | `127.0.0.1:14550+10N` (swarm: `127.0.0.1:14550` for all) | `''` to disable |
| `-ExtraArgs a,b` | `-- a b` | | passed straight to the SITL binary |
| | `--bin PATH` | downloaded binary | use your own build, e.g. `ardupilot/build/sitl/bin/arducopter` |
| | `--update` | | re-download the Linux binary |
| | `--build` | | build the Linux binary from source (automatic on aarch64) |

## Swarms

`-Swarm N` / `--swarm N` starts N vehicles from one command:

- instances `I .. I+N-1` (`I` = `-Instance`, default 0), each with its own ports, eeprom and `<vehicle>/runN`
- MAVLink system ID = instance + 1, so a GCS shows them as separate vehicles
- vehicle 0 at `-Home`, the rest lined up behind it along the home heading, `-Spacing` (10 m) apart,
  all facing the home heading (on a runway location like `Woodley`, planes line up on the runway)
- all vehicles send MAVLink to UDP `127.0.0.1:14550`, so one GCS (QGroundControl, Mission Planner) sees the
  whole swarm; vehicle N is also on TCP `5760+10N`
- output goes to `<vehicle>/runN/sitl.log`; Ctrl+C stops every vehicle

```bash
./sitl.sh plane --swarm 3 --home Woodley --spacing 20
```

Running several separate `--instance N` launches by hand also works, but they all share sysid 1 and spawn on
the same spot unless you pass `-- --sysid N` and different `--home` values.

## Connecting

Connect a GCS to TCP `127.0.0.1:5760` (+10N) or listen on UDP `14550` (+10N). TCP 5763 (+10N) is SERIAL2.

Named locations are resolved by the scripts themselves: the binary only reads the `locations.txt` compiled into it.

## Notes

- The Linux "stable" build may be a different commit from the bundled Windows build; check `git.txt` against `git-linux.txt`.
- The source build lives in `.build/ardupilot`; if it is interrupted, rerun the same command to resume.
- `sitl.sh` also accepts the `sitl.ps1` spellings (`-Home`, `-Speedup`, `-WaitForGcs`, ...).
- Inside WSL, use `sitl.sh` (native Linux build); from Windows itself, use `sitl.ps1`.
