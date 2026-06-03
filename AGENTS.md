# Projekti tööreeglid

## 1. Charset ja failivorming

- Kõik kood, konfiguratsioon ja dokumentatsioon peavad olema UTF-8 kodeeringus.
- Uute failide loomisel ja olemasolevate failide muutmisel tuleb säilitada UTF-8.
- Kui failis esineb kodeeringuprobleem, tuleb see käsitleda veana ja parandada juurpõhjus, mitte peita sümptomit.

## 2. Enne muudatusi loe läbi allikad

- Enne sisuliste muudatuste kavandamist loe läbi kõik dokumendid, mis puudutavad muudetavat ala.
- Kui ülesanne puudutab arhitektuuri, andmemudelit, asukohaloogikat, liitumisreegleid, deployd, koormust või ORDS/FastAPI integratsiooni, kasuta allolevaid viiteid esmase tõeallikana.
- Kui dokumentatsiooni ja koodi vahel on vastuolu, ära eelda vaikimisi, et dokumentatsioon on õige. Tuvasta vastuolu, kirjelda seda detailselt ja küsi üle.
- Tegutse edasi ainult siis kui oled saanud kinnituse.
- Kui töö käigus tekib kahtlus, ära oleta vaid peatu ning küsi üle

## 3. Tööpõhimõtted

- Ärireeglid peavad elama võimalikult tsentraalselt ja järjekindlalt; väldi reeglite dubleerimist eri kihtides.
- Muudatused peavad olema minimaalsed, sihitud ja kooskõlas olemasoleva arhitektuuriga.
- Ära muuda kõrvalisi faile ega paranda mitteseotud probleeme.
- Kõrge mõjuga otsuste puhul eelista juurpõhjuse parandamist, mitte lokaalseid ümberkäike.

## 4. Vea käsitlemise juhis

- Vea või regressiooni korral uuri esmalt juurpõhjust.
- Uuri kogu ahelat, mitte vaid vea esinemise kohta
- Ära piirdu ainult sümptomit eemaldava parandusega, kui juurpõhjus jääb alles.
- Tee veast, selle põhjustest ja võimalikest parandusvariantidest kokkuvõte ning küsi nõusolek parandamiseks.
- Vastuses või töö kokkuvõttes kirjelda võimalusel lühidalt:
  1. mis oli juurpõhjus;
  2. miks viga tekkis;
  3. kuidas tehtud parandus selle kõrvaldab;
  4. milline jääkrisk või eeldus alles jääb.
- Kui loogiline koht on olemas, lisa või uuenda test, mis kinnitab parandust.

## 5. Mittefunktsionaalsed ootused

- Hoia API, andmemudeli ja ärireeglite käitumine eri rollide ja klientide jaoks järjekindel.
- ORDS kasutaja ei oma baasis õigust otse tabelite poole pöörduda, seda ei tohi eeldada
- Väldi lahendusi, mis suurendavad põhjendamatult ORDS-i või andmebaasi koormust. 
- ORDS päringute arv FastAPIst on kriitiline ja süsteemi tuvastatud pudelikael. 
- väldi ORDS tasemel mammutteenuseid -- iga teenus peab tagastama vaid vajaliku ja võimalikult minimaalse arvu andmeid
- Arvesta, et aja- ja kuupäevaloogikas on autoriteetne mudel UTC andmebaasis ja lokaalne aeg kasutajaliideses.
- Arvesta soft-delete nähtavusreeglitega: kustutatud kirjed ei tohi tavavoogudes lekkida v.a. juhendites nimetatud erandid.
- Arvesta i18n reeglitega: kasutajaliidese tekstid peavad tulema tõlgetest, mitte olema kõvakodeeritud. 
- koodis ei tohi olla ühtegi ekraaniteksti, ka n.ö. fallback väärtused ei ole lubatud. Fallbackina kasutatakse labelit ennast, see toov puuduvad tekstid kiiresti esile
- koodis olevad tekstilabelid peavad olema unikaalsed, nende taaskasutus erinevates kohtades ei ole lubatud. 
- See tähendab seda, et kui näiteks erinevates kohtades on tabel, milles veerg võistluse nimi, siis peab igas tabelis olema erinev label selle veeru nime koha peal. Kui on mitu OK nuppu, siis kõigil neil on erinev label. See annab võimaluse vajadusel muuta ekraanitekste sõltumatult.
- dropdowni väärtuste labelite jaoks on reegel: dropdowni label.väärtuse tunnus (näiteks admin.competition.type.label, admin.competition.type.r ja admin.competition.type.s moodustavad dropdowni, kus .label on selle pealkiri ja .s ja .r on väärtused)
- Tõlgete fallback reeglid on dokumentatsioonis, neist tuleb alati lähtuda.
- Uued tõlked lisa alati lühida ja konkreetse SQL INSERT lause kujul (esimene rida: insert into <field list>, teine rida values <väärtuste list>). 
- Arvesta, et kui tabelil on PK veerg, siis tuleb see INSERT lauses väärtustada õige sequence nextval väärtusega
- SQL koodis ei tohi samasisulisi konstante, protseduure ja funktsioone korrata -- kui on vaja, siis tuleb protseduur või funktsioon teha globaalselt kättesaadavaks.
- koodis eelista korduvate väärtuste puhul võimalusel eeldefineeritud konstante
- stylesheet on assets/app.css failis. Seda kasutavad results, admin ja superadmin lehed. Stiile tuleb jagada, mitte igale lehele sama sisuga uus stiil defineerida.
- admin "Näita kaardil" vaates ja KP lisamise/muutmise kaardil ei tohi KP erisümbolite joonistamine sõltuda Leafleti projektsioonist enne vaate paigaseadmist. Väldi lahendusi, mis kasutavad `latLngToLayerPoint` või `layerPointToLatLng` enne `setView` või `fitBounds` lõppemist; START ja FINISH tüüpi tähised tuleb teha vaate-agnostilise `divIcon`/SVG lahendusega, vastasel juhul tekib viga "Set map center and zoom first."
- index.html (kasutaja UI) ei kasuta assets/app.css stylesheeti!

## 6. Dokumentatsiooni ja tõeallikate register

### Juur-README ja sellest otse viidatud dokumendid

- `README.md`
- `docs/system_architecture.md`
- `docs/erd.md`
- `docs/location_rules.md`
- `docs/competitor_join_rules.md`
- `backend/README.md`
- `docs/deploy/https-letsencrypt.md`
- `testing/load/README.md`

### Eelnevates dokumentides viidatud täiendavad allikad

- `docker-compose.yml`
- `nginx/default.conf`
- `backend/app/main.py`
- `backend/app/map_layers.json`
- `frontend_dist/index.html`
- `db/oracle/ords/07_ords_handlers.sql`
- `db/oracle/api/05_api_packages_stub.sql`

## 7. Millal mida kindlasti lugeda

- Kui muudad autentimist, sessioone, API vastuseid, cache'i, i18n-i või kaardikihte, loe `backend/README.md`.
- Kui muudad arhitektuuri, komponentide vastutusi või teenuste vahelist piiri, loe `docs/system_architecture.md`.
- Kui muudad andmestruktuure või DB-poolseid reegleid, loe `docs/erd.md`.
- Kui muudad geolokatsiooni, checkpointi avatavust, kauguse arvutust või kaardi käitumist, loe `docs/location_rules.md` ja `backend/README.md`.
- Kui muudad liitumist, osalust, koode või tingimustega nõustumist, loe `docs/competitor_join_rules.md` ja `backend/README.md`.
- Kui muudad deployd, reverse proxyt või HTTPS seadistust, loe `docs/deploy/https-letsencrypt.md`, `docker-compose.yml` ja `nginx/default.conf`.
- Kui muudad jõudlust, koormust või ORDS-i pudelikaelu puudutavat loogikat, loe `testing/load/README.md`, `README.md` ja `backend/README.md`.

## 8. Väljundi ootused

- Kui töö sisaldab vea parandust, too kokkuvõttes eraldi välja juurpõhjus ja paranduse loogika.
- Kui töö tugineb oletusele, nimeta oletus selgelt ning küsi enne muudatuse tegemist luba.
- Kui avastad dokumentatsiooni ja tegeliku käitumise lahknevuse, maini see kokkuvõttes välja ja küsi täiendavaid juhtnööre.
