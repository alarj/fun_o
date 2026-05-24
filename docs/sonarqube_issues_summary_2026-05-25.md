# SonarQube leiud: kokkuvõte ja parandused

Kuupäev: 2026-05-25
Raporti allikas: `sonar_25_05.json`

## 1) Milliseid vigu SonarQube tuvastas (üldistus)

SonarQube leidude peamised kategooriad olid:

- `BUG` (usaldusväärsuse probleemid)
  - `NULL` võrdlused SQL-is valel kujul (nt `= NULL` / `<> NULL` tüüpi loogika risk).
  - Jõudmatu kood (unreachable code) Pythonis.
- `CODE_SMELL` (hooldatavuse probleemid)
  - Liiga suur kognitiivne keerukus (Cognitive Complexity) mõnes funktsioonis.
  - Korduvad literaalid/stringid (`S1192`) Pythonis ja SQL-is.
  - FastAPI stiili/konventsiooni tähelepanekud (nt `response_model` dubleerimine, `Annotated` soovitus).
  - SQL/PLSQL dokumenteerituse ja vormistusliku kvaliteedi märkused.

## 2) Mõju süsteemile

### Äriloogika ja töökindlus

- `NULL`-loogika vead võivad anda valesid filtreerimistulemusi või tingimusharusid.
- Jõudmatu kood võib peita katkist execution flow’d (kood näib olemas, aga ei käivitu kunagi).
- Keelevahetuse bug (täiendav äriviga) tekitas olukorra, kus küsimus/vastused ei uuenenud kohe.

### Hooldatavus ja muutuste risk

- Kõrge kognitiivne keerukus teeb funktsioonid raskesti loetavaks ja regressioonitundlikuks.
- Korduvad literaalid suurendavad copy-paste vigu ja muudatuste killustatust.
- Konventsioonide eiramine (API/typing) tekitab meeskonnas ebajärjekindla koodibaasi.

## 3) Tõenäolised tekkepõhjused

Tõenäolised juurpõhjused olid:

- Ajalooline kasv "suures failis" (eriti `backend/app/main.py`) ilma järjepideva refaktorita.
- Kiired funktsionaalsed lisandused, kus korduskasutus (konstandid/helperid) jäi teisejärguliseks.
- Piiratud automaatsed kvaliteedigate’id enne merge/deploy etappi.
- Frontendi cache/refresh loogika ei arvestanud kõiki kontekste (sh aktiivne keel).

## 4) Mida parandamiseks tehti

### Prioriteet 1 (BUG-id)

- Parandati SQL `NULL`-võrdlused korrektsesse vormi.
- Eemaldati jõudmatu Pythoni kood ning taastati katkine execution flow õigesse endpointi.

Muutunud failid:

- `backend/app/main.py`
- `db/oracle/api/05_api_packages_stub.sql`

### Prioriteet 2 (hooldatavus)

- Vähendati Pythoni funktsioonide kognitiivset keerukust:
  - tingimuspuude asendamine andmepõhise map’iga,
  - väiksemad helper-funktsioonid,
  - vastutuste selgem eristamine.
- Asendati korduvad literaalid konstanditega Pythonis.
- Asendati korduvad literaalid konstanditega SQL/ORDS skriptides (sihtkohtades, mille Sonar tõstis esile).

Muutunud failid:

- `backend/app/main.py`
- `db/oracle/api/05_api_packages_stub.sql`
- `db/oracle/ords/07_ords_handlers.sql`

### Täiendav äriparandus (väljaspool Sonar prioriteete)

- Keelevahetusel tehakse nüüd kohene küsimuse ja vastusevariantide värskendus.
- Open-checkpoints cache võti arvestab keelt, et vältida vana keele andmete näitamist.

Muutunud fail:

- `frontend_dist/index.html`

## 5) Soovitus edasiseks

- Hoida SonarQube Quality Gate "blocking" režiimis vähemalt `BUG` ja `CRITICAL` leidudele.
- Lisada CI-sse kiire kontroll:
  - Python lint + type check,
  - SQL staatiline kontroll,
  - smoke test keelevahetuse ärivoole.
- Jätkata `main.py` järkjärgulist jaotamist väiksemateks mooduliteks, et keerukus ei koguneks tagasi.
