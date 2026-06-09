# Known Bugs By Sonar And Gemini

See dokument koondab siinses töövoos läbi käinud SonarQube ja Gemini leiud, mida ei ole teadlikult veel parandatud.

Eesmärk:
- hoida ühes kohas alles otsus, miks mõni leid jäi praegu lahtiseks;
- vältida sama leiu uuesti läbirääkimist järgmistes commitides;
- eristada päris parandamata tehnilist võlga valepositiivsetest või teadlikult edasi lükatud tähelepanekutest.

Ulatus:
- siia pannakse ainult need leiud, mis selles töövoos tõstatati ja mida otsustati mitte kohe parandada;
- siia ei panda juba parandatud leide;
- kui mõni siin olev punkt hiljem parandatakse, tuleb see dokument uuendada.

## 1. SonarQube teadlikult parandamata leiud

### 1.0 2026-06 overlay / results töövoo Sonar leiud

Mõjutatud failid:
- `backend/app/main.py`
- `db/oracle/ords/07_ords_handlers.sql`

Märkused:
- `python:S8410` FastAPI dependency injection võiks kasutada `Annotated[...]`
- `python:S8409` redundantne `response_model` parameeter, kui return type annotation on juba olemas
- `plsql:LiteralsNonPrintableCharactersCheck` ORDS handleri `q'~ ... ~'` literaliploki alguses

Miks ei parandatud:
- Pythoni leiud on madala mõjuga maintainability / stiilimärkused, mitte funktsionaalsed vead.
- Praegune FastAPI stiil on projektis läbivalt kasutusel ja ei tekita käitumisriski.
- PL/SQL leid käitub siin tööriista piiranguna: ORDS handler kasutab korrektset mitmerealist `q'~ ... ~'` literalit ja Sonar raporteerib selle sees newline märgi kui mitteprinditava sümboli.

Staatus:
- teadlikult aktsepteeritud madala väärtusega cleanup / valepositiiv

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

Sama hinnang kehtib ka admin UI failijaotuse järel järgmiste failide kohta:
- `frontend_dist/assets/admin-core.js`
- `frontend_dist/assets/admin-map.js`
- `frontend_dist/assets/admin-main.js`

Ka admin UI kasutab teadlikult brauseri-globaalidel põhinevat jagatud state'i, kus deklaratsioonid elavad peamiselt `admin-core.js` failis ja kasutused `admin-map.js` / `admin-main.js` failides. Sonar käsitleb neid viiteid osaliselt valepositiivsete `S2703` leidudena.

### 1.2 `javascript:S6582` optional chaining eelistus

Mõjutatud failid:
- `frontend_dist/assets/competitor-core.js`
- `frontend_dist/assets/competitor-map.js`
- `frontend_dist/assets/competitor-main.js`
- `frontend_dist/assets/admin-core.js`

Miks ei parandatud:
- tegemist on valdavalt loetavus- ja stiilisoovitusega, mitte funktsionaalse bugiga;
- olemasolev kood töötab ja muudatus ei anna praegu sisulist ärilist ega tehnilist võitu võrreldes muude prioriteetidega.

Staatus:
- teadlikult edasi lükatud cleanup

### 1.3 `javascript:S7764` eelista `globalThis` asemel `window`

Mõjutatud failid:
- `frontend_dist/assets/competitor-map.js`
- `frontend_dist/admin.html`

Miks ei parandatud:
- competitor UI töötab brauseri-keskses kontekstis;
- `admin.html` töötab samuti sihilikult brauseri-globaalide peal ja kasutab `window`-it loetava jagatud state kandjana;
- `window` kasutus neis failides on teadlik ja loetav;
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

Mõjutatud failid:
- `frontend_dist/assets/competitor-main.js`
- `frontend_dist/assets/admin-main.js`

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

### 2.0 2026-06 overlay / results töövoo Gemini märkused

Mõjutatud failid:
- `db/oracle/api/05_api_packages_stub.sql`
- `frontend_dist/results.html`

Märkused:
- overlay olemasolu kontroll kasutab mõnes kohas `sysdate`, samal ajal kui mujal kasutatakse eksplitsiitset UTC normaliseerimist
- tulemuste lehe automaatvärskendus ei aktiveeru ise hiljem, kui leht avati enne võistluse algust

Miks ei parandatud:
- Oracle pilveandmebaasi keskkonnas on süsteemi eeldus, et DB serveri aeg on UTC; selles projektis on see teadlik arhitektuurne alusreegel, mitte juhuslik sõltuvus. Seetõttu ei käsitleta `sysdate` kasutust siin reaalse bugina.
- Tulemuste lehe “avatud enne starti” käitumine kuulutati teadlikuks ärireegliks: automaatvärskendus hinnatakse lehe avamisel ning kui võistlus polnud siis veel alanud, peab kasutaja hilisemaks automaatvärskenduseks lehe käsitsi refreshima.

Staatus:
- teadlikult aktsepteeritud keskkonnaspetsiifiline eeldus / ärireegel

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

## 2a. Gemini backlog / UX täpsustused

### 2a.1 Competitor map popupi üldsõnaline teade `Küsimusi ei ole..`

Mõjutatud fail:
- `frontend_dist/assets/competitor-map.js`

Miks ei parandatud kohe:
- praegune popupi loogika eristab ainult kahte olekut: vastamise nupp või üldine “küsimusi ei ole” teade;
- tehniliselt ei ole see funktsionaalne viga, sest küsimuse avamise lõplik kontroll toimub endiselt alles nupu vajutusel;
- samas on Gemini tähelepanek sisuliselt õige: kasutajale võib olla eksitav näidata sama teksti nii juhul, kui KP-l tõesti küsimust ei ole, kui ka juhul, kui küsimus on olemas, kuid tingimused (kaugus, GPS, järjekord, START/FINISH reeglid) ei ole täidetud;
- täpsemaks paranduseks tuleks boolean-tagastuse asemel viia popupi eelotsus staatusekoodidele (`TOO_FAR`, `NO_GPS`, `WRONG_SEQUENCE`, `START_REQUIRED`, `NO_QUESTION` jne) ja lisada vastavad tõlked.

Staatus:
- teadlikult edasi lükatud UX-parandus / backlog

Millal uuesti hinnata:
- kui tehakse järgmine competitor map popupi UX täpsustamise ring;
- kui soovitakse vähendada kasutajate segadust olukorras, kus küsimus on olemas, aga pole veel vastatav.

### 2a.2 Admin info-modali HTML struktuurikontrolli valepositiivid toorete `<` / `>` märkide korral

Mõjutatud fail:
- `frontend_dist/assets/admin-core.js`

Mõjutatud ala:
- `hasValidInfoHtmlStructure(...)`
- admin väljapõhiste info-modalite HTML guard enne DOMPurify sanitiseerimist

Miks ei parandatud kohe:
- praegune guard on teadlikult kitsas ja selle põhieesmärk on piirata vigase help-HTML mõju ainult konkreetse modali sisse;
- see eesmärk on saavutatud: katkine või valesti pesastatud HTML ei tohi enam lõhkuda tervet lehte;
- samas võib regex-põhine kontroll anda valepositiivse vea, kui tõlkes kasutatakse toorest `<` või `>` märki tekstisisuna, näiteks koodinäites või matemaatilistes võrdlustes;
- sellisel juhul kuvatakse sama modali sees turvaline fallback (hoiatus + escaped toortekst), kuigi sisu ise ei pruugi olla sisuliselt vigane;
- kiirparandust ei tehtud, sest see kipuks muutuma uueks regex-lapiks; sisuline parandus tuleks teha eraldi, kui otsustatakse guard asendada parseripõhisema loogikaga.

Staatus:
- teadlikult edasi lükatud UX-parandus / teadaolev piirang

Praegune workaround:
- tõlgetes tuleb kasutada tekstisiseste nurksulgude asemel HTML olemeid `&lt;` ja `&gt;`

Millal uuesti hinnata:
- kui info-modalitesse lisatakse rohkem tehnilisi näiteid või abiinfodes hakatakse sagedamini kasutama võrdlusmärke;
- kui tehakse eraldi admin i18n / help-modalite robustsuse paranduspass.

### 2a.3 Admin participant map layer dialoogi EPK visuaalne sünk

Mõjutatud fail:
- `frontend_dist/assets/admin-main.js`

Mõjutatud ala:
- `normalizeParticipantLayerSelection(...)`
- participant map-layer checkboxide renderdus

Miks ei parandatud kohe:
- praegu lisab süsteem salvestamisel automaatselt `maaamet_pohikaart` kihi, kui administraator valib overlay-valiku;
- andmed salvestuvad õigesti ja ärireegel ei lähe katki;
- samas ei peegeldu see automaatne lisand kohe dialoogi checkboxites, mistõttu võib kasutaja näha teistsugust seisu kui see, mis lõpuks salvestatakse;
- tegemist on UX-parandusega, mitte andmekorruptsiooni või turvaveaga.

Staatus:
- teadlikult edasi lükatud UX-parandus / backlog

Millal uuesti hinnata:
- kui tehakse järgmine admin kaardivalikute UX ring;
- kui overlay-valik jõuab ka competitor UI-sse.

### 2a.4 Overlay uploadi ja tile-töötluse backend refaktor väiksemateks tükkideks

Mõjutatud fail:
- `backend/app/main.py`

Mõjutatud ala:
- overlay upload voog
- tile generation ja taustatöötluse orkestreerimine

Miks ei parandatud kohe:
- praegune lahendus on funktsionaalselt korrektne ja selle peale lisati esmalt töökindluse parandused (taastöötlus startupil, tokeni aegumine, mälusäästlikum upload);
- Sonari cognitive complexity märkus on maintainability mõttes sisuliselt õige;
- funktsioonide väiksemateks tükkideks jagamine on mõistlik teha eraldi refaktorina, et mitte segada aktiivseid äriloogika muudatusi ja deploy-voogu.

Staatus:
- päris tehniline võlg, kuid teadlikult edasi lükatud refaktor / backlog

Millal uuesti hinnata:
- kui overlay-workflow stabiliseerub;
- kui tehakse eraldi backend maintainability pass.

### 2a.5 Competitor overlay tile tokeni dünaamiline uuendamine pikkadel sessioonidel

Mõjutatud failid:
- `backend/app/main.py`
- `frontend_dist/assets/competitor-map.js`

Mõjutatud ala:
- võistleja oma kaardi tile URL token
- overlay tile-layeri vea- ja refreshiloogika

Miks ei parandatud kohe:
- praegune tokeni TTL on pikk ja vaikimisi `86400` sekundit, mis katab tüüpilise võistluse;
- funktsionaalsus töötab MVP-s korrektselt, kuid väga pika sessiooni või tulevikus lühema TTL-i korral võib võistleja overlay tile token aeguda keset võistlust;
- korrektne lahendus vajab frontendi ja backendi koostööd: tile `403` vea tuvastamist, uue signed URL/template küsimist ja olemasoleva overlay layeri sujuvat uuendamist ilma lehte värskendamata.

Staatus:
- teadlikult edasi lükatud töökindluse/UX parandus / backlog

Millal uuesti hinnata:
- kui competitor overlay workflow stabiliseerub;
- kui tokeni TTL-i soovitakse turvakaalutlustel lühendada;
- enne pikemate või mitmepäevaste võistluste laiemat kasutust.

## 3. Kuidas seda dokumenti kasutada

- Kui Sonar või Gemini raporteerib järgmistes commitides uuesti sama leidu, kontrolli esmalt siit, kas tegemist on juba teadlikult aktsepteeritud punktiga.
- Kui leid on siin kirjas ja olukord pole muutunud, ei pea sama otsust uuesti nullist läbi vaidlema.
- Kui arhitektuur või koodistruktuur muutub nii, et siin toodud põhjendus enam ei kehti, tuleb see dokument uuendada või punkt eemaldada.
