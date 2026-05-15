# Load Test (UI emulator)

See kaust sisaldab Locust-põhist koormustesti, mis emuleerib võistleja mobiili-UI käitumist ilma brauserita.

## Mida test teeb

Iga virtuaalkasutaja teeb:

1. `POST /api/dev/login`
2. `POST /api/competitions/register` (võistleja koodiga)
3. `GET /api/competitor/competitions`
4. Kaardi laadimine stardis: `GET /api/competitor/map-checkpoints`
5. Võistluse jooksul hulga `open-checkpoints` päringuid:
- `near` päringud (KP lähedal) + vastuse saatmine (`POST /api/submissions`)
- `far` päringud (KP-dest eemal), et simuleerida "ei leitud sobivat KP-d"

Loogika:
- KP läbimine on iga kasutaja jaoks juhuslikus järjekorras.
- Kasutajate lõpetamise aeg on `n ± jitter%`.
- Stardipauk: kaardi laadimine üritatakse teha esimese 5 sek jooksul pärast kasutaja starti.

## Eeldused

- Backend töötab (soovitavalt `APP_ENV=dev`).
- `LOAD_ACCESS_CODE` peab viitama aktiivsele võistleja koodile.
- Kui kasutad HTTPS domeeni (soovitus), määra host `https://fun-o.eu`.

## Kiire käivitus (kohalik Python)

PowerShell (Windows):

```powershell
cd C:\Users\Alar\Documents\development\fun_o
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install locust

$env:LOAD_ACCESS_CODE = "SIIN_VOISTLEJA_KOOD"
$env:LOAD_COMPETITION_ID = "22"
$env:LOAD_KP_COUNT = "50"
$env:LOAD_DURATION_MIN = "60"
$env:LOAD_FINISH_JITTER_PCT = "15"
$env:LOAD_FAR_REQUEST_MULTIPLIER = "4"
$env:LOAD_MAP_BURST_SECONDS = "5"

locust -f testing\load\locustfile.py --host https://fun-o.eu --users 200 --spawn-rate 40 --run-time 70m --headless --only-summary
```

## Kiire käivitus (Docker, soovitatud)

`docker-compose.yml` sisaldab eraldi `testing` teenust (Locust).

```powershell
cd C:\Users\Alar\Documents\development\fun_o

$env:LOAD_ACCESS_CODE = "SIIN_VOISTLEJA_KOOD"
$env:LOAD_COMPETITION_ID = "22"
$env:LOAD_KP_COUNT = "50"
$env:LOAD_DURATION_MIN = "60"
$env:LOAD_FINISH_JITTER_PCT = "15"
$env:LOAD_FAR_REQUEST_MULTIPLIER = "4"
$env:LOAD_MAP_BURST_SECONDS = "5"

docker compose --profile testing run --rm `
  -e LOAD_ACCESS_CODE `
  -e LOAD_COMPETITION_ID `
  -e LOAD_KP_COUNT `
  -e LOAD_DURATION_MIN `
  -e LOAD_FINISH_JITTER_PCT `
  -e LOAD_FAR_REQUEST_MULTIPLIER `
  -e LOAD_MAP_BURST_SECONDS `
  testing `
  -f /mnt/locust/locustfile.py `
  --host https://fun-o.eu `
  --users 200 `
  --spawn-rate 40 `
  --run-time 70m `
  --headless `
  --only-summary
```

## Soovitatud parameetrid sinu testiks

- `--users 200`
- `--spawn-rate 40` (ca 5 sekundiga üles)
- `LOAD_KP_COUNT=50`
- `LOAD_FAR_REQUEST_MULTIPLIER=4`
  - kokku 5x KP päringuid per kasutaja (`50 near + 200 far`)
- `LOAD_DURATION_MIN=60`
- `LOAD_FINISH_JITTER_PCT=15`
- `--run-time 70m` (et kõik kasutajad jõuaks lõpetada)

## Tähtsad märkused

- Kui testid `http://localhost`, siis tootmis-HTTPS redirect võib segada. Kasuta pigem päris hosti `https://fun-o.eu`.
- Docker variandis on `fun-o.eu` compose-võrgus aliasena olemas.
- Sea kõik `LOAD_*` keskkonnamuutujad samas shellis, kust käivitad `docker compose ... run testing`.
- Kontrolli enne jooksu:
  - `echo $LOAD_COMPETITION_ID` (Linux) / `$env:LOAD_COMPETITION_ID` (PowerShell) ei tohi olla tühi ega `0`.
  - `echo $LOAD_ACCESS_CODE` (Linux) / `$env:LOAD_ACCESS_CODE` (PowerShell) ei tohi olla tühi.
- Test kasutab dev loginit ja e-poste kujul `T001@funo.local` ... `T200@funo.local` (muudetav `LOAD_USER_PREFIX` ja `LOAD_USER_COUNT` envidega).
- TEXT küsimuste korral saadetakse juhuslik vastus `OK` või `NOK`.
- SINGLE_CHOICE küsimustes valitakse juhuslik vastusevariant.

## Tulemuste vaatamine

Kui jooksutad `--headless`, näed kokkuvõtet terminalis.
Soovi korral võid lisada:

```powershell
--csv testing\load\results\run1
```

siis saad CSV failid p95/p99 analüüsiks.

## Testvõistluse loomise SQL

Valmis skript:

`testing/sql/01_create_loadtest_competition.sql`

See skript loob:
- 1 asukohapõhise testvõistluse (`use_location='Y'`, `radius_m=20`)
- 50 KP-d (keskpunkt `59.439685, 24.730787`, juhuslik hajuvus 3km raadiuses)
- igale KP-le TEXT küsimus `Kuidas läheb?`, õige vastus `OK`, punktid `1`
- 200 kasutajat `T001..T200` ja seob nad võistluse osalejateks
