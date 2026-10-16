# ArduPilot SITL (Windows, prebuilt)

Official Cygwin SITL builds from `firmware.ardupilot.org/Tools/MissionPlanner/sitl/{CopterStable,PlaneStable}`
(commit in `copter/git.txt`, `plane/git.txt`), with default params from the same commit.

```powershell
git clone https://github.com/MohammadAdib/ardupilot-sitl
cd ardupilot-sitl
# once per machine, if scripts are blocked:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

.\sitl.ps1 copter
.\sitl.ps1 plane -Home Woodley
.\sitl.ps1 copter -Instance 1 -Speedup 5 -Wipe
```

| Option | Default | |
|---|---|---|
| `-Model` | `quad` / `plane` | any SITL model, e.g. `hexa`, `octa`, `quadplane` |
| `-Home` | CMAC | `lat,lon,alt,hdg` or a name from `autotest\locations.txt` |
| `-Speedup` | 1 | |
| `-Instance N` | 0 | shifts all ports by 10*N; separate eeprom/logs in `<vehicle>\runN` |
| `-Wipe` | | reset params to defaults |
| `-WaitForGcs` | | hold boot until something connects on TCP |
| `-UdpOut` | `127.0.0.1:14550+10N` | `''` to disable |

Connect a GCS to TCP `127.0.0.1:5760` (+10N) or listen on UDP `14550` (+10N). Also TCP 5763 is SERIAL2.

Named locations are resolved by `sitl.ps1` itself: the binary only reads the `locations.txt` compiled into it.
