# fun_o

`fun_o` on mobiilisõbralik veebisüsteem orienteerumisvõistluste korraldamiseks ja läbiviimiseks, kus kontrollpunktides (KP) vastatakse küsimustele ning punktiarvestus on automaatne. 
- Võistlusi saab luua nii mobiilis kuvatava kaardiga kui ka kaardita. Kaardirežiimis on võimalik kuvada võistleja asukohta ning lubada küsimustele vastata ainult kindlas piirkonnas viibides. 
- Võistluste korraldamisel saab kasutada erinevaid avalikest allikatest pärit kaarte, nii Eesti-keskseid kaarte (nt Maa-ameti kaardid) kui laiema katvusega kaarte (nt OpenStreetMap, Mapy.cz jms.). 
- Korraldaja saab võistlusele lisada ka oma georeferentseeritud kaardi, mida kasutatakse võistluspõhise overlayna toetatud aluskaardi peal.
- Sama rakendust saab kasutada ka klassikaliste viktoriinide ja muude teadmismängude läbiviimiseks.

## Projekti taust

- Tegemist on hobiprojektiga, mis on loodud muu hulgas AI-arendusvahendite tundmaõppimiseks.
- Kogu kood ja dokumentatsioon on loodud AI abil; inimese roll on olnud ärivajaduste kirjeldamine, otsuste valideerimine ja tulemuse suunamine.
- Peamine kasutatud vahend: OpenAI Codex ([https://openai.com/codex/](https://openai.com/codex/)). Käesoleva töö põhiline mudelivariant oli GPT-5 perekonda kuuluv Codex 5.3.

## Miks see süsteem loodi

Aastaid tagasi sai töökaaslastele seminaride ja suvepäevade raames analoogseid (kuid oluliselt piiratumaid) võistlusi korraldatud Google Sheets + Forms abil. See toimis väiksemas mahus, kuid oli mõnevõrra ebamugav kuna:

- uue võistluse loomine eeldas kas uute Google Sheets tabelite loomist või olemasolevatest tabelitest seniste tulemuste kustutamist;
- võimalik oli kasutada ainult "süsteemiväliseid" (trükitud) kaarte;
- mitut võistlust ei saanud korraga ette valmistada ja ajalugu säilitada;
- KP küsimuste vastuste haldamine oli ajamahukas ja piiratud võimalustega;
- küsimused tuli trükkida võistleja kaardile;
- võistleja pidi ise iga kord Google Formsist otsima kontrollpunkti numbri ning sisestama vastuse;
- võistleja ei saanud tagasisidet oma vastuse korrektsusest ja teenitud punktidest;
- ühtset liitumis-, osalus- ja punktiarvestuse reeglite haldamist ei olnud;
- tulemuste arvutamine ja kuvamine toimus keerulise erinevatest Google Sheets tabelitest ja graafikutest koosneva süsteemi abil;
- oli palju käsitööd võistluse ettevalmistamisel (s.h. tuli leida võimalus trükkida kaardid) ning tulemuste koostamisel.

`fun_o` üritab neid kitsaskohti kõrvaldada viies võistluse ja selle korraldamise ühte veebis olevasse süsteemi: liitumine, küsimused, vastused, punktid, tabelid ja statistika. Jah, orienteerumine mobiilis oleva kaardiga on midagi muud kui orienteerumine paberil oleva suure kaardiga kuid see süsteem ei välista ka välise (paber)kaardi kasutamist -- mobiil on siis vaid abivahend raja läbimise märgete tegemiseks.

Tegemist ei ole mingi uue ideega -- analoogilisi rakendusi on palju ning neid kasutatakse erinevate korraldajate poolt igapäevaselt. 

## Äriline väärtus ja funktsionaalsus

Süsteem loob väärtust kolmes rollis.

### Võistleja väärtus

- lihtne liitumine koodi alusel (sobib nii individuaal- kui tiimiformaadile);
- töötab telefonibrauseris (Android/iOS) ilma eraldi äppi paigaldamata;
- KP vastamine nii teksti kui valikvastustega;
- kohene tulemus iga vastuse järel: kas vastus oli õige ja mitu punkti saadi;
- toetab nii `R` (vaba järjekord) kui `S` (etteantud järjekord) võistlusi ning `START`/`FINISH` erikontrollpunkte;
- võistluse ajal nähtav enda progress, punktid ja läbitud KP-d.

### Korraldaja väärtus

- võistluse, KP-de, küsimuste, vastuste ja koodide haldus ühest kohast;
- võimalus lisada võistlusele oma georeferentseeritud kaart overlayna ning kasutada seda admini kaardivaadetes pärast taustatöötluse valmimist;
- jooksev leaderboard ning detailne vaade vastustele/KP-de läbimisele;
- võistluse lõpus automaatne tulemuste tabel (punktid + ajakriteerium);
- vähem käsitsi arvutamist, vähem inimlikke vigu, parem läbipaistvus osalejatele.

### Organisatsiooni väärtus

- korduvkasutatav platvorm mitme eri võistluse jaoks;
- ajalooliste andmete säilitamine analüütikaks ja järgmiste ürituste parendamiseks;
- paindlik tee edasi asukohapõhiste ja kaardipõhiste võistlusmudelite suunas.

## Lühike lahenduse kirjeldus

Lahendus on veebipõhine mitmekihiline süsteem:

- frontendid rollipõhiselt: võistleja, admin, superadmin, tulemuste vaade;
- FastAPI backend ühtse API, sessiooni, valideerimise ja cache’iga;
- Oracle andmemudel + ORDS REST-kiht, kus paiknevad andmete ja reeglite kesksemad kontrollid;
- kaardikiht avalikest kaardiallikatest (nt Maa-ameti kaardid, OpenStreetMap, Mapy.cz), mida saab kasutada võistluse loogika osana või taustakaardina;
- võistluspõhised oma kaardid, mis salvestatakse eraldi failistorage'isse, töödeldakse taustas tile'ideks ning kuvatakse adminis overlayna aluskaardi peal;
- Docker Compose’iga käivitatav tervik (nginx + backend + testiprofiil).

Võistleja UI (`frontend_dist/index.html`) kasutab eraldi staatilisi asset-faile:
- stiilid: `frontend_dist/assets/competitor.css`
- üldine UI/API/i18n loogika: `frontend_dist/assets/competitor-core.js`
- kaardi, suuna ja kaardikihtide loogika: `frontend_dist/assets/competitor-map.js`
- bootstrap, modalid ja sündmuste sidumine: `frontend_dist/assets/competitor-main.js`
- võistluse tingimuste rich HTML sanitiseeritakse brauseris DOMPurify abil enne renderdamist

Admin UI (`frontend_dist/admin.html`) kasutab samuti eraldi staatilisi asset-faile:
- üldine UI/API/i18n loogika: `frontend_dist/assets/admin-core.js`
- admini kaartide ja kaardikihtide loogika: `frontend_dist/assets/admin-map.js`
- admini workflow'd, dialoogid, renderdus ja bootstrap: `frontend_dist/assets/admin-main.js`

See arhitektuur toetab eesmärki hoida ärireeglid stabiilsena, vähendada UI-poolset “nutikust” ning tagada, et sama reegel kehtib kõigile klientidele ühtemoodi.

## Tehniline arhitektuur (viited)

Tehnilised detailid on kirjeldatud olemasolevates dokumentides:

- süsteemiarhitektuur: [docs/system_architecture.md](docs/system_architecture.md)
- andmemudel (ERD): [docs/erd.md](docs/erd.md)
- asukohaloogika reeglid: [docs/location_rules.md](docs/location_rules.md)
- liitumise ja osaluse reeglid: [docs/competitor_join_rules.md](docs/competitor_join_rules.md)
- teadlikult parandamata Sonar/Gemini leiud: [docs/known_bugs_by_sonar_and_gemini.md](docs/known_bugs_by_sonar_and_gemini.md)
- backendi API/integreerimisdetailid: [backend/README.md](backend/README.md)
  - sisaldab ka eraldi jaotist geograafilise kauguse arvutusest (KP avatavus + `total_distance_m`)
- juurutus (HTTPS): [docs/deploy/https-letsencrypt.md](docs/deploy/https-letsencrypt.md)
- koormustestid: [testing/load/README.md](testing/load/README.md)

## Teostuse suund võrreldes algse ideega

Algne visioon oli teha mobiilirakendus orienteerumisvõistlustele. Teostus on kujunenud teadlikult mobiilisõbralikuks veebirakenduseks, mis:

- katab juba täna KP-põhise küsimusmängu, punktiarvestuse, rollid ja tulemused;
- jätab andme- ja reeglikihi Oracle/ORDS kaudu hästi eraldatuks;
- loob aluse järgmisteks sammudeks (nt geokoordinaatide tugevam sidumine, automaatne KP pakkumine asukoha järgi, liikumistrajektooride visualiseerimine).

## Kokkuvõte

`fun_o` on praktiline üleminek “excelipõhisest mängujuhtimisest” skaleeritava võistlusplatvormi suunas. Süsteem vähendab korraldusriski, parandab osalejakogemust ja annab korraldajale reaalajas juhtimisvaate koos kontrollitava andmeajaloo ning selge tehnilise laiendatavusega.

Süsteem võimaldab kiirelt ja lihtsalt sisustada seminarida ja suvepäevade puhkepause, viies osalejad laua tagant õue liikuma.

Loodud süsteem võib olla kasulik ka koolide õppetöös -- ülesandeid saab õpilane lahendada "harjumuspärases keskkonnas" (mobiilis) kuid ülesanded saab luua viisil, et lahendamiseks ei piisa vaid ekraani kerimisest. Ülesande nägemiseks tuleb minna kindlasse kohta, st. esmalt peab liikuma ja alles seejärel saab anda vastuseid.

## Arenguvõimalus (PWA vs wrapper vs native, frontend raamistikud)

Praegune arhitektuur (vanilla JS frontend + FastAPI + ORDS) on üles ehitatud nii, et äriloogika on backendis ja frontend on peamiselt esitluskiht. See tähendab, et sama API-d saab kasutada ka tulevikus mobiilirakenduse jaoks ilma suurt backendi ümbertegemist nõudmata.

Mobiilisuuna valik:
- **PWA (olemasoleva webi jätk)**: kõige väiksem risk ja kulu, kiireim areng.
- **Lightweight wrapper app (WebView/Capacitor)**: sobib, kui on vaja äpipoodides kohalolu, säilitades suure osa olemasolevast frontendist.
- **Native app**: suurim investeering; mõistlik siis, kui on selge vajadus native-võimekuste järele (nt tugev offline, background geolocation, push-teavitused, väga sujuv kaardikogemus).

Frontend-tehnoloogia valik:
- Vanilla JS -> Angular/React/Vue migratsioon on sisuliselt **frontendi rewrite**.
- **React** on kõige praktilisem, kui eesmärk on hiljem liikuda ka Android/iOS äpiks (React Native/Expo tee).
- **Angular** sobib hästi enterprise webi jaoks, kuid mobile tee on üldiselt vähem loomulik kui React Native suund.
- Leaflet jääb **webis** hästi kasutatavaks; native-äpis kasutatakse tavaliselt natiivseid kaardikomponente.

Soovituslik järjekord:
1. Tugevdada olemasolevat PWA/webi.
2. Vajadusel lisada lightweight wrapper äpp.
3. Native äppi minna alles siis, kui äriline vajadus on tõendatud.

## Võimalik jõudluse parandamise suund: ORDS vahekihi vähendamine või eemaldamine

Tänases keskkonnas (Oracle Always Free) on ORDS kasutusel jagatud ja piiratud ressursiga teenusena, mis võib kujuneda pudelikaelaks. Projekti koormustestide tulemused viitavad, et koormuse all tekib piirang eeskätt ORDS kihis, samal ajal kui andmebaasi protsessori- ja IO-koormus ei olnud märkimisväärne ([testing/load/README.md](testing/load/README.md)).

Seetõttu on üheks võimalikuks jõudluse tõstmise variandiks FastAPI ühendamine Oracle andmebaasiga otse (ilma ORDS vahenduseta), säilitades võimalusel äriloogika jätkuvalt DB pakettides/protseduurides. See võib vähendada ORDS-ist tulenevat latentsust ja läbilaskevõime piiranguid.

Oluline on arvestada, et tegemist on keskmise kuni suure arhitektuurimuudatusega:
- FastAPI ORDS-kutsete (`httpx`) asendamine otse DB-draiveri (`python-oracledb`) kasutusega.
- ORDS JSON-lepingu (`items`, `access_granted` jms) asendamine uue andmekaardistusega API vastustesse.
- Vea-, timeouti-, retry- ja connection pooli halduse suurem vastutus FastAPI kihis.

Praktiliselt sobib see etapiviisiliseks teostuseks: esmalt POC/benchmark kõige koormatumatel endpointidel, seejärel otsus, kas migratsiooni laiendada.

Praktiline vahevariant on teha esmalt "targeted bypass" ainult kõige kuumemale päringule (näiteks KP läheduse kontroll), kus FastAPI kutsub otse ühte konkreetset PL/SQL package/procedure API-t. Sellisel juhul saab säilitada turvapõhimõtte:
- FastAPI DB-kasutajale ei anta otseseid õigusi andmetabelitele.
- Antakse ainult vajalik `EXECUTE` õigus konkreetsele package/procedure'ile.
- Ärireeglid ja andmepäringud jäävad jätkuvalt DB kihis hallatavaks.

