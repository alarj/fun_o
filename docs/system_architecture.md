# Süsteemi arhitektuur (seisuga tänane kood)

See dokument kirjeldab ainult neid arhitektuuriosi, mis on repo olemasoleva koodi ja dokumentidega tõendatavad.

Allikad:
- `backend/README.md`
- `docs/erd.md`
- `docs/location_rules.md`
- `docs/competitor_join_rules.md`
- `docker-compose.yml`
- `nginx/default.conf`

## 1) Andmebaas

Mida teeb:
- Hoidab põhiandmeid: kasutajad, rollid, võistlused, osalused, kontrollpunktid, küsimused, valikud/õiged vastused, tulemused, audit.
- Hoiab ka raja pikkuse snapshotte ja taustaarvutuse seadistusi (`competition_routes`, `app_settings`).
- Hoiab liitumise, küsimuste ja tulemuste jaoks vajalikke ärireeglitega seotud välju (sh ajaraamid, staatused, asukohareeglid, tingimuste versioonid).
- Kasutab pehme kustutamise mudelit (`start_date`, `end_date`) enamikus äritabelites; `submissions` tabel on dokumentatsiooni järgi erand.

- Ärireeglid ja andmekonsistents on tsentraalselt DB-s (FK-d, kontrollid, aktiivse kirje mõiste).
- Audit ja soft-delete võimaldavad ajaloolist jälgitavust.
- Ajalised ja staatusekontrollid toetavad võistluse elutsüklit (DRAFT/INACTIVE/ACTIVE + ajavahemik).
- DB-s toimub ka raja linnulennulise pikkuse arvutus ning selle tulemuse salvestamine koos sisend-hashiga.

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
- FastAPI kutsed lähevad ORDS endpointidesse, mitte otse DB draiveriga SQL-i täitma.
- Tagastab JSON vastuseid, mida backend ootab kindlas formaadis.

Miks nii on tehtud:
- DB äriloogika jääb DB pakettidesse; ORDS toimib standardse REST-kihina.
- Backendile tekib stabiilne HTTP-leping (`/auth/google/upsert`, `/competitions/register`, `/submissions`, jne).
- Errorite kaardistus on võimalik teha ühtselt backendi tasemel ORA-koodide põhjal.
- Sama kiht avaldab ka raja snapshoti lugemise ning arvutuse tellimise endpointid (`/admin/competitions/route*`).

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
- Verifitseerib Google id_token'i (README järgi tokeninfo MVP lähenemine).
- Vahendab päringud ORDS-i ning kaardistab vead rakenduse veakoodideks.
- Haldab sessiooniküpsist (`funo_session` vaikimisi) ja kasutaja sidumist päringutega.
- Kontrollib competitor liitumisvoos enne ORDS `join-preview` / `join-complete` kutseid reCAPTCHA-d ning väljastab lühiajalise serveri-signeeritud `join_proof` tõendi.
- Laeb i18n tõlked mällu ning pakub reload endpointi.
- Pakub ka kaardikihtide konfiguratsiooni endpointi (`/api/map-layers`) README kirjelduse järgi.
- Haldab võistluspõhiste oma kaartide uploadi, metadata salvestust, taustatöötluse käivitamist ning valmis tile'ide serveerimist admin vaadetele.
- Kontrollib võistleja vaates, kas salvestatud raja snapshot on endiselt kehtiv, võrreldes ORDS-ist saadud `current_source_hash` väärtust FastAPI enda arvutatud hashiga.

Miks nii on tehtud:
- Frontend ei pea teadma ORDS/Oracle detaili.
- Autentimine, sessioon ja veakäsitlus on ühes kontrollitavas kihis.
- Anti-bot kontroll jääb samuti FastAPI kihti, et ORDS-i ei koormataks bottide preview/join päringutega ning DB äriloogika ei sõltuks Google captcha integratsioonist.
- Ühtne API leping lihtsustab frontend arendust.
- Suured võistluspõhised kaardifailid saab töödelda taustas tile'ideks ilma ORDS-i või brauserit ühe suure rasteri renderdamisega koormamata.
- Raja pikkust ei arvutata frontendis ega igal lugemisel uuesti, vaid FastAPI kasutab DB-s salvestatud snapshoti ainult siis, kui hash kinnitab selle värskuse.

Tehnoloogia:
- Python + FastAPI
- `httpx` väliskutseteks (ORDS, Google)
- `.env` põhine konfiguratsioon

Viited:
- `backend/README.md`
- `backend/app/main.py`

## 4) Frontend

Mida teeb:
- Kuvab kasutajaliidest, mida nginx serveerib kataloogist `frontend_dist`.
- Tarbib backendi `/api/*` endpointe.
- Kasutab backendi antud andmeid võistluste, KP-de, küsimuste, tulemuste ja i18n kuvamiseks.
- Competitor liitumisvoos kasutab vajadusel Google reCAPTCHA v3 ja ainult madala skoori korral v2 fallback challenge'it.
- `results.html` võistleja modal kasutab `participant-submissions` andmeid, sh iga rea `delta_from_prev_seconds` ning kokkuvõtte väljasid `total_elapsed_seconds` / `total_distance_m`.
- `results.html` automaatvärskendus töötab ainult lehe avamisel aktiivseks loetud võistlusel, mille `starts_at <= now` ja mille `ends_at` on kas tulevikus või `NULL`, ning peatub hiljemalt 1 tunni möödumisel lehe avamisest.
- Kaardifunktsionaalsuse puhul lähtub backendi map-layer konfiguratsioonist (README kirjeldus).
- Admin UI saab võistlusele lisatud oma kaardi korral dünaamilise kaardivaliku `* {display_name}`, kuid alles siis, kui overlay töötlusstaatus on `READY`.
- Competitor UI saab samal põhimõttel dünaamilise kaardivaliku `* {display_name}`, mida renderdatakse EPK peale tavalise tile-overlay kihina.

Miks nii on tehtud:
- Staatilise frontendi serveerimine nginx-ist on lihtne ja odav.
- Frontend jääb õhukeseks kliendiks; äriloogika ja turvakontroll on backend/DB kihis.
- Demostaadiumis võib sama konfiguratsioon sisaldada nii kontrollitud kui katsetatavaid väliseid kaardikihte,
  et eri riikide taustakaarte saaks reaalseadmetes kiiresti võrrelda ilma eraldi deploy-ringideta.
- Võistluspõhise overlay elutsükkel on frontendile lihtne: UI näitab source-kaardi metaandmeid ja töötlusolekut, kuid kasutab overlayd kaardil alles siis, kui backend on tile'id valmis loonud.
- Võistleja vaates on oma kaart, kasutaja asukoht ja follow-režiim üksteisest lahutatud: overlay valik määrab ainult aktiivse kaardikihikomplekti, follow määrab ainult kaardi keskpunkti liikumise.

Tehnoloogia:
- HTML
- Vanilla JavaScript (võistleja UI loogika on jaotatud staatilisteks asset-failideks)
- CSS
- Leaflet (`leaflet`), `proj4`, `proj4leaflet` kaardifunktsioonide jaoks
- DOMPurify võistluse tingimuste HTML ning admin UI kontekstitundlike info-modalite piiratud HTML turvaliseks sanitiseerimiseks enne renderdamist
- HTTP API kaudu suhtlus FastAPI-ga

Viited:
- `frontend_dist/index.html`
- `frontend_dist/assets/competitor.css`
- `frontend_dist/assets/competitor-core.js`
- `frontend_dist/assets/competitor-map.js`
- `frontend_dist/assets/competitor-main.js`
- `frontend_dist/admin.html`
- `frontend_dist/assets/admin-core.js`
- `frontend_dist/assets/admin-map.js`
- `frontend_dist/assets/admin-main.js`
- `backend/README.md`

## 5) Välised ressursid

Mida teeb:
- Google OAuth / tokeninfo: kasutaja identiteedi kontroll backendi autentimisvoos.
- Kaardipakkujad: Mapy.cz ja MapTiler võtmed/URL-id map layerite jaoks (README järgi).
- Oracle Cloud ORDS URL: backendi ORDS baas-URL.
- Kohalik failistorage võistluspõhiste oma kaartide source-failide ja tile-püramiidide jaoks.

Miks nii on tehtud:
- Identiteedi kontroll delegeeritakse Google'ile.
- Kaardikihtide jaoks kasutatakse valmis teenuseid, mitte oma tile-serverit.
- ORDS kaudu välditakse otse DB ühenduse avamist frontendile.
- Võistluspõhiste oma kaartide puhul kasutatakse rakenduse hallatud lokaalset storage'it, sest suured rasterfailid ei sobi ORDS-i kaudu edasi-tagasi vahendamiseks.

Tehnoloogia:
- Google tokeninfo
- Map provider API võtmed (`MAPYCZ_API_KEY`, `MAPTILER_API_KEY`)
- ORDS public URL

Viited:
- `backend/README.md`
- `docs/location_rules.md`

## 6) Dockerdamine (konteineriarhitektuur)

Mida teeb:
- Käivitab rakenduse komponendid konteinerites.
- Seob frontend serveerimise ja API reverse proxy nginx-i kaudu.
- Võimaldab eraldi testimise konteinerit (`testing`) profiili alusel.

Miks nii on tehtud:
- Ühtne käivitusviis eri keskkondades.
- Lihtsam sõltuvuste haldus (nginx/FastAPI/locust eraldi konteinerites).
- Võrgutus ja sõltuvused (`depends_on`, eraldi `funo_net`) on deklareeritud.

Tehnoloogia:
- Docker Compose (`version: "3.9"`)

Konteinerid ja rollid:
- `funo_nginx` (`nginx:1.27-alpine`)
  - Serveerib staatilist frontendit (`./frontend_dist`).
  - Kasutab `nginx/default.conf` konfiguratsiooni.
  - On avalik sisenemispunkt (`80`, `443`).
  - Mountib TLS sertifikaadid (`/etc/letsencrypt`) read-only.
- `funo_fastapi` (build `./backend/Dockerfile`)
  - Käitab FastAPI backendi.
  - Loeb keskkonnamuutujad `.env` failist.
  - Avab konteinerivõrgus pordi `8000` (`expose`).
- `funo_testing` (`locustio/locust:2.29.1`, profile `testing`)
  - Koormustestide konteiner.
  - Mountib testiskriptid kaustast `./testing/load`.
  - Käivitub ainult siis, kui Compose profile `testing` on sisse lülitatud.

Viited:
- `docker-compose.yml`
- `nginx/default.conf`

## Kihtide koosmõju (koodist tuletatud)

1. Nginx võtab vastu veebipäringud ja serveerib frontendit ning proxydab API FastAPI-le.
2. Frontend kutsub FastAPI `/api/*` endpointid.
3. FastAPI valideerib autentimise/sessiooni ja kutsub ORDS endpointid.
4. ORDS handlerid käivitavad DB pakette või päringuid.
5. DB tagastab tulemuse, mis liigub ORDS -> FastAPI -> frontend.
