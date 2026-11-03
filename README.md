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
```

## Linux (bash)

```bash
git clone https://github.com/MohammadAdib/ardupilot-sitl
cd ardupilot-sitl

./sitl.sh copter
./sitl.sh plane --home Woodley
./sitl.sh copter --instance 1 --speedup 5 --wipe
```

## Options

| Windows | Linux | Default | |
|---|---|---|---|
| `-Model` | `--model` | `quad` / `plane` | any SITL model, e.g. `hexa`, `octa`, `quadplane` |
| `-Home` | `--home` | CMAC | `lat,lon,alt,hdg` or a name from `autotest/locations.txt` |
| `-Speedup` | `--speedup` | 1 | |
| `-Instance N` | `--instance N` | 0 | shifts all ports by 10*N; separate eeprom/logs in `<vehicle>/runN` |
| `-Wipe` | `--wipe` | | reset params to defaults |
| `-WaitForGcs` | `--wait-for-gcs` | | hold boot until something connects on TCP |
| `-UdpOut` | `--udp-out` | `127.0.0.1:14550+10N` | `''` to disable |
| `-ExtraArgs a,b` | `-- a b` | | passed straight to the SITL binary |
| | `--bin PATH` | downloaded binary | use your own build, e.g. `ardupilot/build/sitl/bin/arducopter` |
| | `--update` | | re-download the Linux binary |
| | `--build` | | build the Linux binary from source (automatic on aarch64) |

## Connecting

Connect a GCS to TCP `127.0.0.1:5760` (+10N) or listen on UDP `14550` (+10N). TCP 5763 (+10N) is SERIAL2.

Named locations are resolved by the scripts themselves: the binary only reads the `locations.txt` compiled into it.

## Notes

- The Linux "stable" build may be a different commit from the bundled Windows build; check `git.txt` against `git-linux.txt`.
- The source build lives in `.build/ardupilot`; if it is interrupted, rerun the same command to resume.
- `sitl.sh` also accepts the `sitl.ps1` spellings (`-Home`, `-Speedup`, `-WaitForGcs`, ...).
- Inside WSL, use `sitl.sh` (native Linux build); from Windows itself, use `sitl.ps1`.
