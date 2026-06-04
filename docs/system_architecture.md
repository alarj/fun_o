# SĆ¼steemi arhitektuur (seisuga tĆ¤nane kood)

See dokument kirjeldab ainult neid arhitektuuriosi, mis on repo olemasoleva koodi ja dokumentidega tĆµendatavad.

Allikad:
- `backend/README.md`
- `docs/erd.md`
- `docs/location_rules.md`
- `docs/competitor_join_rules.md`
- `docker-compose.yml`
- `nginx/default.conf`

## 1) Andmebaas

Mida teeb:
- Hoidab pĆµhiandmeid: kasutajad, rollid, vĆµistlused, osalused, kontrollpunktid, kĆ¼simused, valikud/Ćµiged vastused, tulemused, audit.
- Hoiab liitumise, kĆ¼simuste ja tulemuste jaoks vajalikke Ć¤rireeglitega seotud vĆ¤lju (sh ajaraamid, staatused, asukohareeglid, tingimuste versioonid).
- Kasutab pehme kustutamise mudelit (`start_date`, `end_date`) enamikus Ć¤ritabelites; `submissions` tabel on dokumentatsiooni jĆ¤rgi erand.

- Ć„rireeglid ja andmekonsistents on tsentraalselt DB-s (FK-d, kontrollid, aktiivse kirje mĆµiste).
- Audit ja soft-delete vĆµimaldavad ajaloolist jĆ¤lgitavust.
- Ajalised ja staatusekontrollid toetavad vĆµistluse elutsĆ¼klit (DRAFT/INACTIVE/ACTIVE + ajavahemik).

Tehnoloogia:
- Oracle Autonomous Database
- SQL + PL/SQL
- Andmemudel kirjeldatud ERD-s

Viited:
- `docs/erd.md`
- `docs/location_rules.md`
- `docs/competitor_join_rules.md`

## 2) ORDS kui baasi liides

Mida teeb:
- Avaldab DB funktsioonid HTTP endpointidena.
- FastAPI kutsed lĆ¤hevad ORDS endpointidesse, mitte otse DB draiveriga SQL-i tĆ¤itma.
- Tagastab JSON vastuseid, mida backend ootab kindlas formaadis.

Miks nii on tehtud:
- DB Ć¤riloogika jĆ¤Ć¤b DB pakettidesse; ORDS toimib standardse REST-kihina.
- Backendile tekib stabiilne HTTP-leping (`/auth/google/upsert`, `/competitions/register`, `/submissions`, jne).
- Errorite kaardistus on vĆµimalik teha Ć¼htselt backendi tasemel ORA-koodide pĆµhjal.

Tehnoloogia:
- Oracle REST Data Services (ORDS)
- ORDS moodulid/handlerid
- ORDS endpointide lepingud on kirjeldatud backend README-s

Viited:
- `backend/README.md`
- `db/oracle/ords/07_ords_handlers.sql`

## 3) FastAPI (veebiliidese backend)

Mida teeb:
- Pakub frontendile `/api/*` endpointid.
- Verifitseerib Google id_token'i (README jĆ¤rgi tokeninfo MVP lĆ¤henemine).
- Vahendab pĆ¤ringud ORDS-i ning kaardistab vead rakenduse veakoodideks.
- Haldab sessioonikĆ¼psist (`funo_session` vaikimisi) ja kasutaja sidumist pĆ¤ringutega.
- Laeb i18n tĆµlked mĆ¤llu ning pakub reload endpointi.
- Pakub ka kaardikihtide konfiguratsiooni endpointi (`/api/map-layers`) README kirjelduse jĆ¤rgi.

Miks nii on tehtud:
- Frontend ei pea teadma ORDS/Oracle detaili.
- Autentimine, sessioon ja veakĆ¤sitlus on Ć¼hes kontrollitavas kihis.
- Ćhtne API leping lihtsustab frontend arendust.

Tehnoloogia:
- Python + FastAPI
- `httpx` vĆ¤liskutseteks (ORDS, Google)
- `.env` pĆµhine konfiguratsioon

Viited:
- `backend/README.md`
- `backend/app/main.py`

## 4) Frontend

Mida teeb:
- Kuvab kasutajaliidest, mida nginx serveerib kataloogist `frontend_dist`.
- Tarbib backendi `/api/*` endpointe.
- Kasutab backendi antud andmeid vĆµistluste, KP-de, kĆ¼simuste, tulemuste ja i18n kuvamiseks.
- `results.html` vĆµistleja modal kasutab `participant-submissions` andmeid, sh iga rea `delta_from_prev_seconds` ning kokkuvĆµtte vĆ¤ljasid `total_elapsed_seconds` / `total_distance_m`.
- Kaardifunktsionaalsuse puhul lĆ¤htub backendi map-layer konfiguratsioonist (README kirjeldus).

Miks nii on tehtud:
- Staatilise frontendi serveerimine nginx-ist on lihtne ja odav.
- Frontend jĆ¤Ć¤b Ćµhukeseks kliendiks; Ć¤riloogika ja turvakontroll on backend/DB kihis.
- Demostaadiumis vĆµib sama konfiguratsioon sisaldada nii kontrollitud kui katsetatavaid vĆ¤liseid kaardikihte,
  et eri riikide taustakaarte saaks reaalseadmetes kiiresti vĆµrrelda ilma eraldi deploy-ringideta.

Tehnoloogia:
- HTML
- Vanilla JavaScript (vĆµistleja UI loogika on jaotatud staatilisteks asset-failideks)
- CSS
- Leaflet (`leaflet`), `proj4`, `proj4leaflet` kaardifunktsioonide jaoks
- DOMPurify vĆµistluse tingimuste HTML turvaliseks sanitiseerimiseks enne renderdamist
- HTTP API kaudu suhtlus FastAPI-ga

Viited:
- `frontend_dist/index.html`
- `frontend_dist/assets/competitor.css`
- `frontend_dist/assets/competitor-core.js`
- `frontend_dist/assets/competitor-map.js`
- `frontend_dist/assets/competitor-main.js`
- `backend/README.md`

## 5) VĆ¤lised ressursid

Mida teeb:
- Google OAuth / tokeninfo: kasutaja identiteedi kontroll backendi autentimisvoos.
- Kaardipakkujad: Mapy.cz ja MapTiler vĆµtmed/URL-id map layerite jaoks (README jĆ¤rgi).
- Oracle Cloud ORDS URL: backendi ORDS baas-URL.

Miks nii on tehtud:
- Identiteedi kontroll delegeeritakse Google'ile.
- Kaardikihtide jaoks kasutatakse valmis teenuseid, mitte oma tile-serverit.
- ORDS kaudu vĆ¤lditakse otse DB Ć¼henduse avamist frontendile.

Tehnoloogia:
- Google tokeninfo
- Map provider API vĆµtmed (`MAPYCZ_API_KEY`, `MAPTILER_API_KEY`)
- ORDS public URL

Viited:
- `backend/README.md`
- `docs/location_rules.md`

## 6) Dockerdamine (konteineriarhitektuur)

Mida teeb:
- KĆ¤ivitab rakenduse komponendid konteinerites.
- Seob frontend serveerimise ja API reverse proxy nginx-i kaudu.
- VĆµimaldab eraldi testimise konteinerit (`testing`) profiili alusel.

Miks nii on tehtud:
- Ćhtne kĆ¤ivitusviis eri keskkondades.
- Lihtsam sĆµltuvuste haldus (nginx/FastAPI/locust eraldi konteinerites).
- VĆµrgutus ja sĆµltuvused (`depends_on`, eraldi `funo_net`) on deklareeritud.

Tehnoloogia:
- Docker Compose (`version: "3.9"`)

Konteinerid ja rollid:
- `funo_nginx` (`nginx:1.27-alpine`)
  - Serveerib staatilist frontendit (`./frontend_dist`).
  - Kasutab `nginx/default.conf` konfiguratsiooni.
  - On avalik sisenemispunkt (`80`, `443`).
  - Mountib TLS sertifikaadid (`/etc/letsencrypt`) read-only.
- `funo_fastapi` (build `./backend/Dockerfile`)
  - KĆ¤itab FastAPI backendi.
  - Loeb keskkonnamuutujad `.env` failist.
  - Avab konteinerivĆµrgus pordi `8000` (`expose`).
- `funo_testing` (`locustio/locust:2.29.1`, profile `testing`)
  - Koormustestide konteiner.
  - Mountib testiskriptid kaustast `./testing/load`.
  - KĆ¤ivitub ainult siis, kui Compose profile `testing` on sisse lĆ¼litatud.

Viited:
- `docker-compose.yml`
- `nginx/default.conf`

## Kihtide koosmĆµju (koodist tuletatud)

1. Nginx vĆµtab vastu veebipĆ¤ringud ja serveerib frontendit ning proxydab API FastAPI-le.
2. Frontend kutsub FastAPI `/api/*` endpointid.
3. FastAPI valideerib autentimise/sessiooni ja kutsub ORDS endpointid.
4. ORDS handlerid kĆ¤ivitavad DB pakette vĆµi pĆ¤ringuid.
5. DB tagastab tulemuse, mis liigub ORDS -> FastAPI -> frontend.
