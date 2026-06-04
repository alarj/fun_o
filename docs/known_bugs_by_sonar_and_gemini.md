# Known Bugs By Sonar And Gemini

See dokument koondab siinses töölõimes läbi käinud SonarQube ja Gemini leiud, mida ei ole teadlikult veel parandatud.

Eesmärk:
- hoida ühes kohas alles otsus, miks mõni leid jäi praegu lahtiseks;
- vältida sama leiu uuesti läbiarutamist järgmistes commitides;
- eristada päris parandamata tehnilist võlga valepositiivsetest või teadlikult edasi lükatud tähelepanekutest.

Ulatus:
- siia pannakse ainult need leiud, mis selles töövoos tõstatati ja mida otsustati mitte kohe parandada;
- siia ei panda juba parandatud leide;
- kui mõni siin olev punkt hiljem parandatakse, tuleb see dokument uuendada.

## 1. SonarQube teadlikult parandamata leiud

### 1.1 `javascript:S2703` competitor UI failide vahel jagatud globaalse state kohta

Mõjutatud failid:
- `frontend_dist/assets/competitor-core.js`
- `frontend_dist/assets/competitor-map.js`
- `frontend_dist/assets/competitor-main.js`

Näited:
- `myResultsSortDir`
- `myResultsSortKey`
- `myResultsItems`
- `geoWatchId`
- `mapViewPersistenceEnabled`
- `allowedMapLayers`
- `compMapOpenedOnce`
- `mapDebugGpsHeading`
- `mapDebugGpsSpeed`

Miks ei parandatud:
- competitor UI refaktor jagas varasema ühe suure `index.html` skripti mitmeks staatiliseks failiks;
- jagatud state on teadlikult deklareeritud `competitor-core.js` failis ja kasutusel teistes failides;
- `index.html` laeb failid õiges järjekorras:
  1. `competitor-core.js`
  2. `competitor-map.js`
  3. `competitor-main.js`
- Sonar analüüsib neid faile liiga isoleeritult ja käsitleb osa täiesti korrektseid viiteid nagu puuduvaid deklaratsioone.

Staatus:
- teadlikult aktsepteeritud valepositiiv / tööriista piirang

Millal uuesti hinnata:
- kui competitor UI viiakse ES module või React-põhiseks;
- kui tekib soov teha eraldi "Sonar cleanup" pass ainult maintainability jaoks.

### 1.2 `javascript:S6582` optional chaining eelistus

Mõjutatud failid:
- `frontend_dist/assets/competitor-core.js`
- `frontend_dist/assets/competitor-map.js`
- `frontend_dist/assets/competitor-main.js`

Miks ei parandatud:
- tegemist on valdavalt loetavus- ja stiilisoovitusega, mitte funktsionaalse bugiga;
- olemasolev kood töötab ja muudatus ei anna praegu sisulist ärilist ega tehnilist võitu võrreldes muude prioriteetidega.

Staatus:
- teadlikult edasi lükatud cleanup

### 1.3 `javascript:S7764` eelista `globalThis` asemel `window`

Mõjutatud fail:
- `frontend_dist/assets/competitor-map.js`

Miks ei parandatud:
- competitor UI töötab brauseri-keskses kontekstis;
- `window` kasutus on selles failis teadlik ja loetav;
- tegemist on madala mõjuga konventsioonisoovitusega.

Staatus:
- teadlikult edasi lükatud cleanup

### 1.4 `javascript:S7735` negated condition

Mõjutatud failid:
- `frontend_dist/assets/competitor-main.js`
- `frontend_dist/assets/competitor-map.js`

Miks ei parandatud:
- tegemist on loetavushinnanguga, mitte bugiga;
- olemasolevad tingimused ei olnud piisavalt probleemsed, et õigustada lisadiffi enne äriloogika järgmisi muudatusi.

Staatus:
- teadlikult edasi lükatud cleanup

### 1.5 `javascript:S7761` eelista `.dataset` üle `getAttribute(...)`

Mõjutatud fail:
- `frontend_dist/assets/competitor-main.js`

Miks ei parandatud:
- tegemist on API eelistuse, mitte vea või regressiooniga;
- olemasolev käitumine oli korrektne ja funktsionaalselt piisav.

Staatus:
- teadlikult edasi lükatud cleanup

### 1.6 `javascript:S3776` liiga kõrge kognitiivne keerukus

Mõjutatud fail:
- `frontend_dist/assets/competitor-map.js`

Mõjutatud ala:
- suur kaartide renderdus / kaardi avamise loogika

Miks ei parandatud:
- kaartide refaktoris oli eesmärk esmalt viia inline JS eraldi failidesse ilma ärikäitumist laiali lõhkumata;
- Sonari märkus on sisuliselt õige maintainability tähelepanek, kuid mitte värske funktsionaalne viga;
- funktsiooni väiksemateks tükkideks lõhkumine on mõistlik teha eraldi refaktorina, mitte koos aktiivsete äriloogika muudatustega.

Staatus:
- päris tehniline võlg, kuid teadlikult edasi lükatud

### 1.7 `javascript:S4158` kahtlus, et `mapRings` saab selles harus olla tühi

Mõjutatud fail:
- `frontend_dist/assets/competitor-core.js`

Miks ei parandatud:
- leid vajab eraldi rahulikku kontrolli;
- esmase käsitsi ülevaatuse järgi ei paistnud see olevat kohene regressioon, vaid pigem staatilise analüüsi kahtlus;
- tööfookus oli kaardi refaktor, i18n, DOMPurify ja GPS/heading UX.

Staatus:
- ülevaatamist vajav, kuid mitte kinnitatud bug

### 1.8 `javascript:S7748` "Don't use a zero fraction in the number"

Mõjutatud fail:
- `frontend_dist/assets/competitor-core.js`

Miks ei parandatud:
- puhas vormistus- / stiilimärkus;
- puudub sisuline mõju käitumisele.

Staatus:
- teadlikult ignoreeritud madala väärtusega cleanup

## 2. Gemini teadlikult parandamata leiud

### 2.1 DB päringutes `normalize_checkpoint_type(...)` funktsiooni kasutamine WHERE tingimuses

Mõjutatud fail:
- `db/oracle/api/05_api_packages_stub.sql`

Näited:
- `pkg_common.get_next_ordered_checkpoint_id(...)`
- mitmed `START` / `FINISH` / `NORMAL` kontrollid competitor ja submission flow's

Miks ei parandatud:
- tähelepanek on sisuliselt õige: tabeli tulba mähkimine funktsiooniga võib pärssida indeksi otsest kasutamist, kui vastavat function-based index'it ei ole;
- samas pole see praegu kinnitatud funktsionaalne viga, vaid potentsiaalne jõudlusrisk;
- sama normaliseerimisreegel (`NULL -> NORMAL`, supported values uppercased) elab juba läbivalt DB äriloogikas ning selle asendamine vajab eraldi sihitud ülevaatust, et mitte muuta semantikat ainult ühes või kahes päringus;
- kuna ORDS on niigi süsteemi tuntud pudelikael, on mõistlik seda teemat hinnata koos tegelike päringuplaanide ja indeksitega, mitte oletuslikult ainult kooditasemel.

Staatus:
- teadlikult edasi lükatud jõudluse optimeerimine

Millal uuesti hinnata:
- kui competitor flow päringud muutuvad mõõdetavalt kuumaks;
- kui tehakse eraldi DB/ORDS jõudluse paranduspass;
- kui otsustatakse lisada function-based index või asendada normaliseerimisfunktsioon eksplitsiitse tingimusloogikaga.

Parandatud Gemini leiud, mida siia ei käsitleta avatud punktidena:
- `sanitizeTermsHtml` home-brew sanitizer -> asendatud DOMPurifyga
- `deviceorientation` + `deviceorientationabsolute` dubleeritud listener -> korrigeeritud ühe aktiivse allika peale
- `watchPosition` tühi veacallback -> asendatud kaardisisese GPS signaali kadumise UX-iga

## 3. Kuidas seda dokumenti kasutada

- Kui Sonar või Gemini raporteerib järgmistes commitides uuesti sama leidu, kontrolli esmalt siit, kas tegemist on juba teadlikult aktsepteeritud punktiga.
- Kui leid on siin kirjas ja olukord pole muutunud, ei pea sama otsust uuesti nullist läbi vaidlema.
- Kui arhitektuur või koodistruktuur muutub nii, et siin toodud põhjendus enam ei kehti, tuleb see dokument uuendada või punkt eemaldada.
