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

### 1.0 2026-07 competitor app prompt tühja headingu accessibility märkus

Mõjutatud fail:
- `frontend_dist/index.html`

Märkus:
- `Web:S6850` Sonar märgib competitor mobile app prompt modali pealkirja, sest HTML-is on dünaamiliselt täidetav tühi heading:
  - `<h3 id="competitorAppPromptTitle"></h3>`

Miks ei parandatud:
- projektis kehtib reegel, et koodis ei tohi olla fallback-ekraanitekste ega muid "igaks juhuks" kõvakodeeritud kasutajaliidese tekste;
- selle headingu sisu täidetakse JavaScriptiga tõlgete kaudu;
- Sonari rahuldamine kõige lihtsama variandiga tähendaks siia fallback-teksti või muu staatilise ligipääsetava teksti lisamist HTML-i, mis läheks vastuollu projekti i18n- ja fallback-reeglitega;
- seetõttu on tegemist teadliku kompromissiga: funktsionaalsus on korrektne, kuid staatiline analüüs näeb algses HTML-is tühja semantilist headingut.

Staatus:
- teadlikult aktsepteeritud accessibility / staatilise analüüsi kompromiss

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

### 1.9 `javascript:S4144` kaks kinnituse-dialogi funktsiooni on sisult identsed

Mõjutatud fail:
- `frontend_dist/assets/admin-main.js`

Mõjutatud ala:
- `confirmMassStartWarning(...)`
- `confirmCheckpointInteractionWarning(...)`

Miks ei parandatud:
- Sonari märkus on sisuliselt õige maintainability tähelepanek, mitte funktsionaalne viga;
- mõlemad funktsioonid kasutavad praegu teadlikult sama väikest modal-confirm mustrit, sest teine hoiatus lisati olemasoleva mass-stardi hoiatuse kõrvale minimaalse diffiga;
- ühise helperi tegemine on mõistlik järgmine cleanup-samm, kuid selle sidumine aktiivse äriloogika muudatusega oleks suurendanud asjatult diffi ja regressiooniriski.

Staatus:
- teadlikult edasi lükatud maintainability cleanup

Millal uuesti hinnata:
- kui admin hoiatusmodaleid tuleb veel juurde;
- kui tehakse eraldi admin UI refaktor / Sonar cleanup pass.

### 1.10 `text:S8569` Gradle dependency locking puudub Android shellis

Mõjutatud fail:
- `android/build.gradle`

Märkus:
- Sonar soovib kas `gradle.lockfile` või `gradle/verification-metadata.xml` kasutust, et dependency resolution oleks täielikult ettearvatav.

Miks ei parandatud:
- sisuline parandus eeldab lockfile või verification metadata genereerimist kanonilisest Android build-keskkonnast, mitte käsitsi oletamist;
- käsitsi loodud või poolik lockfile võib buildi muuta hapraks ja tekitada raskemini diagnoositavaid CI / lokaalbuildi erinevusi;
- praeguses töövoos oli mõistlikum parandada kohe need Android hardening teemad, mis ei eelda dependency resolution protsessi ümberseadistamist.

Staatus:
- teadlikult edasi lükatud build-hardening

Millal uuesti hinnata:
- kui Android release build viiakse püsivalt CI peale;
- kui lisatakse signed release AAB/APK pipeline;
- kui võetakse kasutusele Gradle dependency locking või verification metadata ühe kontrollitud buildi pealt genereerituna.

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

### 2.0a 2026-07 `_parse_utc_datetime` timezone-hoiatus

Mõjutatud fail:
- `backend/app/main.py`

Märkus:
- Gemini tõstatas riski, et `_competition_submission_window_reason(...)` võib võrrelda timezone-aware ja timezone-naive `datetime` objekte.

Miks ei parandatud:
- praeguse koodi põhjal ei ole see leid kinnitust leidnud;
- `_parse_utc_datetime(...)` kasutab `datetime.fromisoformat(raw.replace("Z", "+00:00"))`, mis tagastab `Z`-sufiksiga sisendi korral timezone-aware UTC `datetime` objekti;
- sama fail võrdleb seda `datetime.now(timezone.utc)` väärtusega, mis on samuti timezone-aware;
- seega ei ole review käigus tuvastatud tegelikku offset-naive vs offset-aware veaolukorda.

Staatus:
- teadlikult aktsepteeritud valepositiiv / ülevaatuse väärjäreldus

### 2.0b 2026-07 protsessipõhise in-memory cache tähelepanek

Mõjutatud fail:
- `backend/app/main.py`

Märkus:
- Gemini juhtis tähelepanu sellele, et globaalsed in-memory cache struktuurid (nt `open_checkpoints_last_response`) on protsessipõhised ega jagune automaatselt mitme worker-protsessi vahel.

Miks ei parandatud:
- tähelepanek on arhitektuuriliselt õige, kuid see ei ole praeguse töövoo funktsionaalne viga ega regressioon;
- olemasolev cache on teadlikult lokaalne protsessisisene optimeering;
- selle ümbertegemine jagatud cache lahenduseks oleks eraldi arhitektuurne muudatus, mitte sihitud veaparandus.

Staatus:
- teadlikult aktsepteeritud arhitektuuriline piirang, mitte aktiivne bug

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

### 2.2 Raja arvutuse queue-package commit-piirid ja `AUTONOMOUS_TRANSACTION` arutelu

Mõjutatud fail:
- `db/oracle/api/05_api_packages_stub.sql`

Mõjutatud ala:
- `pkg_competition_routes.request_route_recalc`
- `pkg_competition_routes.calculate_route_now`
- `pkg_competition_routes.process_pending_routes`

Miks ei parandatud:
- Gemini tähelepanek üldise PL/SQL best practice vaates on arusaadav, kuid nende entrypointide roll ei ole tavaline ärilise põhioperatsiooni alamprotseduur, vaid queue/control-plane loogika;
- siin on teadlik nõue, et `PENDING`, `PROCESSING`, `READY` ja `FAILED` staatused muutuksid teistele sessioonidele nähtavaks kohe, mitte alles mõne välise kutsuja suurema transaktsiooni lõpus;
- just see nähtavus väldib topeltkäivitusi ja võimaldab scheduleril ning admin UI-l näha protsessi tegelikku seisu;
- kogu protseduuri viimine `AUTONOMOUS_TRANSACTION` alla ei oleks siin parem vaikimisi lahendus, sest see lahutaks route-state'i liiga jõuliselt kutsuja transaktsioonist ja muudaks veaolukordade põhjuse-tagajärje ahela raskemini jälgitavaks;
- praegune commit-piir on seega teadlik arhitektuurne kompromiss, mitte juhuslik transaktsiooniviga.

Staatus:
- teadlikult dokumenteeritud tradeoff, mitte praeguse töövoo bugfixi kandidaat

Millal uuesti hinnata:
- kui neid protseduure hakatakse kasutama üldotstarbeliste alamprotseduuridena mõne suurema transaktsiooni sees;
- kui route queue viiakse tulevikus eraldi tööjärjekorra või teenusepõhise orkestreerimise peale.

Parandatud Gemini leiud, mida siia ei käsitleta avatud punktidena:
- `sanitizeTermsHtml` home-brew sanitizer -> asendatud DOMPurifyga
- `deviceorientation` + `deviceorientationabsolute` dubleeritud listener -> korrigeeritud ühe aktiivse allika peale
- `watchPosition` tühi veacallback -> asendatud kaardisisese GPS signaali kadumise UX-iga
- Capacitori geolocation shim `watchPosition` / `clearWatch` võidusooks -> parandatud nii, et tühistamine jääb kehtima ka siis, kui native watch ID saabub asünkroonselt
- Android instrumented testide paketinimi `com.getcapacitor.app` -> parandatud projektipõhiseks `ee.funo.competitor`
- Capacitori `webContentsDebuggingEnabled` toodangu jaoks -> viidud build-režiimipõhiseks (`release => false`)

## 2a. Gemini backlog / UX täpsustused

### 2a.0 2026-06 Android hosted app järelmärkused

Mõjutatud failid / kihid:
- `backend/app/main.py`
- `db/oracle/api/05_api_packages_stub.sql`
- Android/Capacitor build ja release protsess
- arendusdokumentatsioon

Märkused, mida ei parandatud selles töövoos:
- Hosted appi cookie/session käitumise audit juhul, kui tulevikus UI ja API originid lahknevad
- Kontrollpunkti läbimise salvestuse idempotentsuse eraldi kinnitamine PL/SQL/ORDS kihis dubleerpäringute vastu
- `ACCESS_BACKGROUND_LOCATION` / foreground-service tee tulevikuks, kui kunagi tekib nõue jälgida asukohta ka taustal või ekraani kustumisel
- Android build keskkonna piirang ARM64 Ubuntu hostil; build tuleb teha x86_64 runneris või muul toetatud hostil
- Arendaja setup dokumentatsiooni täiendamine Java/Android SDK/GitHub Actions praktiliste sammudega

Miks ei parandatud kohe:
- need punktid on kas süsteemitaseme auditid, tulevikunõuded või build-keskkonna piirangud, mitte vahetud koodivead selles commitis;
- hosted Android shell sai funktsionaalselt tööle ilma neid alasid lahti tegemata;
- osa neist nõuab arhitektuurilist või infrastruktuurilist otsust, mitte ainult lokaalse faili muutmist.

Staatus:
- teadlikult edasi lükatud audit / release-hardening / dokumentatsiooni backlog

Millal uuesti hinnata:
- enne iOS või bundled tee päris realiseerimist;
- enne release AAB laiema kasutuselevõtu või Play Store submissioni finaliseerimist;
- kui UI ja API originid tulevikus lahknevad.

### ~~2a.1 Competitor map popupi üldsõnaline teade `Küsimusi ei ole..`~~

Mõjutatud fail:
- `frontend_dist/assets/competitor-map.js`

Miks ei parandatud kohe:
- ~~praegune popupi loogika eristab ainult kahte olekut: vastamise nupp või üldine “küsimusi ei ole” teade;~~
- ~~tehniliselt ei ole see funktsionaalne viga, sest küsimuse avamise lõplik kontroll toimub endiselt alles nupu vajutusel;~~
- ~~samas on Gemini tähelepanek sisuliselt õige: kasutajale võib olla eksitav näidata sama teksti nii juhul, kui KP-l tõesti küsimust ei ole, kui ka juhul, kui küsimus on olemas, kuid tingimused (kaugus, GPS, järjekord, START/FINISH reeglid) ei ole täidetud;~~
- ~~täpsemaks paranduseks tuleks boolean-tagastuse asemel viia popupi eelotsus staatusekoodidele (`TOO_FAR`, `NO_GPS`, `WRONG_SEQUENCE`, `START_REQUIRED`, `NO_QUESTION` jne) ja lisada vastavad tõlked.~~

Staatus:
- tehtud 2026-06-12, backlogist eemaldatud

Millal uuesti hinnata:
- ainult siis, kui popupi põhjusetekste soovitakse veel lühemaks või detailsemaks muuta.

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

### 2a.6 Access code genereerimise race condition `generate_unique_access_code(...)` kasutamisel

Mõjutatud failid:
- `db/oracle/api/05_api_packages_stub.sql`
- `db/oracle/schema/11_access_code_global_unique.sql`

Mõjutatud ala:
- `generate_unique_access_code`
- korraldaja-/võistlejakoodide loomise insert-vood

Miks ei parandatud kohe:
- praegune andmemudel kaitseb terviklust, sest `competition_access_codes(code)` peal on globaalne unikaalsusindeks;
- see tähendab, et duplikaatkood ei pääse tabelisse isegi siis, kui kaks paralleelset sessiooni näevad sama koodi korraks “vabana”;
- samas jääb alles töökindluse/concurrency risk: praegune loogika kasutab enne inserti `select count(*)` kontrolli ning suure koormuse või samaaegse loomise korral võib insert saada `dup_val_on_index`;
- korrektne tugevam lahendus oleks retry-loop `dup_val_on_index` käsitlusega nendes voogudes, kus uut access code'i luuakse.

Staatus:
- teadlikult edasi lükatud töökindluse / concurrency parandus / backlog

Millal uuesti hinnata:
- kui access-code loomise koormus kasvab;
- kui tekib päris `dup_val_on_index` viga tootmises või testides;
- järgmises DB töökindluse paranduspassis.

### 2a.8 Admin onboarding "liitu koodiga" rea mobiilioverflow kitsastel ekraanidel

Mõjutatud fail:
- `frontend_dist/assets/app.css`

Mõjutatud ala:
- `.no-org-join-row`
- sama rea `label`, `input` ja `button` laiuse/flex reeglid

Miks ei parandatud kohe:
- praegune paigutus kasutab `flex-wrap: nowrap` koos fikseeritud sisendlaiusega `20ch` ja nupu `min-width: 140px`;
- väga kitsastel mobiiliekraanidel võib see põhjustada horisontaalse ülevoolu või ebamugava kokkusurumise;
- tegemist on UX/responsiivsuse probleemiga admin onboarding vaates, mitte andmekao või äriloogika veaga;
- käesoleva töö fookus oli kasutaja UI help-modal ja sellega otseselt seotud parandused.

Staatus:
- teadlikult edasi lükatud mobiili-UX parandus / backlog

Millal uuesti hinnata:
- kui tehakse järgmine admin onboarding UX pass;
- kui tuleb päris seadmetest tagasiside kitsaste ekraanide horisontaalse kerimise kohta.

### ~~2a.7 Admin session refresh middleware käivitub ka `/api/health` päringul~~

Mõjutatud fail:
- `backend/app/main.py`

Mõjutatud ala:
- `admin_session_refresh_middleware`
- `GET /api/health`

Miks ei parandatud kohe:
- ~~praegune middleware filtreerib õigesti välja staatilised failid ja töötab sessiooniloogika mõttes korrektselt;~~
- ~~samas jääb `/api/health` endiselt `/api/` filtri alla ning võib monitooringu või load balanceri tihedate health-checkide korral teha tarbetut refresh-cookie taastamise tööd;~~
- punkt on nüüd parandatud: refresh-cookie taastamise middleware käivitub ainult `/api/admin/*`, `/api/superadmin/*` ja `/api/auth/session` otspunktidel.

Staatus:
- tehtud 2026-06-11, backlogist eemaldatud

Millal uuesti hinnata:
- ainult siis, kui admin-session refresh scope tulevikus uuesti laieneb.

### 2a.9 Locust JSONL request-logimise blokeeriv faili-I/O võib moonutada koormustesti enda mõõtmisi

Mõjutatud fail:
- `testing/load/locustfile.py`

Mõjutatud ala:
- `_append_jsonl(...)`
- request/response detailrea kirjutamine koormustesti ajal

Miks ei parandatud kohe:
- praegune test logib teadlikult iga päringu detailse JSONL reana, et hilisem analüüs oleks võimalikult täielik;
- samas avatakse ja suletakse logifail iga kirje jaoks uuesti ning kasutatakse standardset blokeerivat faili-I/O-d;
- suure koormuse all võib see tekitada täiendavat CPU ja ketta survet Locusti konteineris ning mõjutada mõõdetavaid response time näitajaid;
- tähelepanek puudutab eelkõige testitööriista enda mõõtmistäpsust, mitte rakenduse äriloogika korrektsust;
- käesoleva töö fookus oli ORDS/FastAPI päris pudelikaelte leidmine ja kõrvaldamine, mitte Locusti logimissüsteemi refaktor.

Staatus:
- teadlikult edasi lükatud testitööriista täpsuse / jõudluse parandus

Millal uuesti hinnata:
- enne järgmisi väga suure koormusega võrdlusteste, kus response time täpsus muutub otsustuskriteeriumiks;
- kui detailse JSONL logi maht kasvab nii suureks, et testigeneraatori enda koormus hakkab tulemusi nähtavalt mõjutama.

### 2a.10 `map_checkpoints` payload kloonimine kasutab madalat koopiat ja võib muutuda riskiks rikkalikuma cache-payloadi korral

Mõjutatud fail:
- `backend/app/main.py`

Mõjutatud ala:
- `_clone_map_checkpoint_payload(...)`

Miks ei parandatud kohe:
- praegune kloonimisloogika kopeerib ülemise taseme sõnastikud ja `items` listi elemendid, kuid ei tee täielikku sügavat koopiat kõigist võimalikest siseobjektidest;
- tänases voos ei ole see kinnitatud funktsionaalne viga ning praegune cache kasutus ei ole näidanud sellest tulenevat regressiooni;
- samas võib risk kasvada, kui cache-payload muutub rikkalikumaks ja sisaldab rohkem nested struktuure, mida hakatakse hiljem lokaalselt uuendama või muteerima;
- viimane Gemini review tõi sama riski eraldi välja ja selle sisuga võib nõustuda: kui mõni tulevane kooditee muudab vastuses olevat nested objekti kohapeal, võib shallow-copy tõttu muutuda ka globaalne cache-entry ning halvimal juhul lekkida muutus teiste kasutajate vastustesse;
- kuna aktiivne fookus oli ORDS koormuse vähendamisel ja request-flow pudelikaelte leidmisel, ei tehtud siin eraldi `deepcopy` refaktorit ilma kinnitatud vajaduseta.

Staatus:
- teadlikult edasi lükatud ettevaatus-/töökindluse parandus

Millal uuesti hinnata:
- kui `map-checkpoints` või muu competitor cache hakkab sisaldama rikkalikumat küsimuse payloadi;
- kui FastAPI hakkab cache-payloadis rohkem nested välju kohapeal uuendama;
- kui tehakse järgmine sihitud cache-hardening pass, võib `_clone_map_checkpoint_payload(...)` ja seotud clone-helperid viia `copy.deepcopy(...)` peale;
- kui ilmneb päris sümptom, mis viitab jagatud mutable state lekkimisele kasutajate vahel.

### 2a.11 `participant_checkpoint_state_cache` võib bootstrap-faasis teha sama kasutaja kohta paralleelseid ORDS päringuid

Mõjutatud fail:
- `backend/app/main.py`

Mõjutatud ala:
- `_get_participant_checkpoint_state(...)`

Miks ei parandatud kohe:
- staatilise competition-scope payloadi jaoks on olemas `inflight` koondamine, kuid participant-state cache kasutab praegu ainult tavalist cache-miss -> ORDS laadimist;
- funktsionaalselt on voog korrektne ja senised parandused keskendusid kinnitatud süsteemivigadele ning ORDS koormuse suurematele allikatele;
- sama kasutaja paralleelne bootstrap-koormus on pigem optimeerimise, mitte ärilise korrektsuse teema;
- selle lisamine muudaks concurrency-käitumist ning väärib eraldi sihitud muudatust koos mõõtmisega.

Staatus:
- teadlikult edasi lükatud optimeerimine / hardening

Millal uuesti hinnata:
- kui logidest ilmneb sama `competition_id:user_id` kohta dubleeruvaid `competitor/checkpoint-state` ORDS päringuid bootstrap-faasis;
- enne järgmisi suuremaid koormusteste, kus soovime participant-state ORDS päringuid veel kitsamaks tõmmata;
- kui ORDS koormus on pärast suuremate pudelikaelte eemaldamist endiselt märkimisväärne just participant-state harus.

### 2a.12 `1 x 400` mass-stardi bootstrapis jääb ORDS-i esimene metadata-laine kitsaskohaks

Mõjutatud failid:
- `backend/app/main.py`
- `testing/load/README.md`

Mõjutatud ala:
- `POST /api/dev/login`
- `GET /api/competitor/competitions`
- `GET /api/competitor/map-checkpoints [ords]`

Miks ei parandatud kohe:
- `R9` jooks näitas, et võistlusaegne põhivoog on nüüd puhas ka `1 x 400` mass-stardi korral:
  - `GET /api/competitor/open-checkpoints [fastapi]` -> `20000` päringut, `0` viga
  - `POST /api/competitor/checkpoint-access [fastapi]` -> `100171` päringut, `0` viga
  - `POST /api/submissions` -> `20000` päringut, `0` viga
- alles jäänud vead olid ainult esimeses bootstrapi laines, kokku `61` tk:
  - `18` × `POST /api/dev/login` `429`
  - `13` × `GET /api/competitor/competitions` `429`
  - `30` × `GET /api/competitor/map-checkpoints [ords]` `429`
- kõik need vead jäid esimesse `0-10 min` ajakorvi ega rikkunud jooksu lõpptulemust: kõik `400` kasutajat lõpetasid ja tegid kokku `20000` KP märget;
- see on seega päris ORDS bootstrapi optimeerimiskoht, kuid mitte enam süsteemi korrektsuse ega töövõime blokk.

Staatus:
- teadlikult edasi lükatud ORDS bootstrapi optimeerimine / backlog

Millal uuesti hinnata:
- enne järgmist suuremat kui `1 x 400` mass-stardi testi;
- kui soovime vähendada just alglaadimise `429` vigu;
- kui ORDS bootstrapi koormuse vähendamine muutub eraldi arhitektuurilise töövoo eesmärgiks.

### 2a.13 Competitor payloadide answered-state semantika peab jääma rangelt eristatud

Mõjutatud failid:
- `backend/app/main.py`
- `backend/README.md`
- `docs/location_rules.md`

Mõjutatud ala:
- `competitor/competition-content`
- `competitor/checkpoint-state`
- FastAPI helperid, mis tuletavad answered checkpoint id-sid või `is_answered` overlay seisu

Miks see on oluline:
- competitor cache- ja popupivood kasutavad mitut eri payloadi, mille answered-state semantika ei ole sama;
- `competition-content` on staatiline payload ja ei sisalda participant-specific `is_answered` välju;
- `checkpoint-state` sisaldab ainult answered checkpoint id-de loendit kujul `{"items":[{"checkpoint_id":...}, ...]}`;
- `map-checkpoints` / `open-checkpoints` vahepayloadis võib `is_answered` juba olemas olla, sest FastAPI on selle ise overlayna juurde ehitanud.

Risk:
- kui neid payloaditüüpe loetakse sama helperi või sama reegliga, võivad `START` / `FINISH` ärireeglid vaikides valeks minna;
- reaalselt juba juhtunud rikked:
  - vale `finished`, kuigi kasutaja ei olnud DB järgi lõpetanud;
  - vale `start_required`, kuigi `START` oli DB järgi läbitud.

Õige reegel:
- payloadidest, kus `is_answered` on olemas, tohib answered-state'i lugeda ainult `is_answered = 'Y'` järgi;
- `checkpoint-state` payloadist tuleb answered-state lugeda ainult `checkpoint_id` olemasolu järgi;
- neid kahte tõlgendust ei tohi ühendada ega jagada sama parseri taha ilma väga teadliku eristamiseta.

Staatus:
- püsiv arhitektuurne hoiatus / review kontrollpunkt

Millal uuesti hinnata:
- iga kord, kui muudetakse competitor cache-helper'eid, popupi ligipääsuloogikat või answered-state overlay koostamist;
- iga kord, kui tekib soov “lihtsustada” payloadi parsivaid helper'eid ühiseks üldfunktsiooniks.

### 2a.14 Competitor join access code ajatelje ebaühtlus

Mõjutatud fail:
- `db/oracle/api/05_api_packages_stub.sql`

Mõjutatud ala:
- `resolve_join_access_code(...)`

Märkus:
- sama päringu sees kasutatakse kahte erinevat ajavõrdluse alust:
  - `c.end_date` ja `comp.end_date` kontrollitakse reegliga `> sysdate`
  - `c.expires_at` kontrollitakse reegliga `> cast((systimestamp at time zone 'UTC') as timestamp)`

Mida kontrolliti:
- see ei ole praeguse dokumentatsiooni põhjal automaatselt kinnitatud bugi, sest väljad ei kanna sama semantikat:
  - `end_date` on süsteemi üldise aktiivse kirje / soft-delete reegli väli
  - `expires_at` on access code äriline aegumine
- ERD defineerib aktiivse kirje reegli kujul `end_date is null or end_date > sysdate`
- ERD järgi on `end_date` tüüpi `date`, samal ajal kui `expires_at` on tüüpi `timestamp`

Miks jäi praegu parandamata:
- selles töövoos ei ilmnenud kinnitatud regressiooni ega tõestatud valet käitumist ainult selle koodikoha põhjal;
- samas on ajamudel selles harus ebaühtlane ja väärib eraldi auditit, kui liitumiskoodide aegumise semantikat või DB/session timezone eeldusi muudetakse.

Staatus:
- dokumenteeritud auditikoht, mitte kinnitatud bugfixi kandidaat käesolevas töövoos

Millal uuesti hinnata:
- kui access code aegumine või liitumisreeglid muutuvad;
- kui DB/session timezone eeldused muutuvad;
- kui leitakse päris juhtum, kus `end_date` ja `expires_at` annavad vastuolulise tulemuse.

### 2a.15 FastAPI `startup` / `shutdown` event handlerite viimine `lifespan` kontekstile

Mõjutatud fail:
- `backend/app/main.py`

Mõjutatud ala:
- `@app.on_event("startup")`
- `@app.on_event("shutdown")`
- shared HTTP kliendi elutsükkel

Miks ei parandatud kohe:
- praegune käivituse/seiskamise loogika töötab funktsionaalselt korrektselt;
- käesolevas töövoos oli eesmärk parandada esmalt join-flow funktsionaalsed ja turvalisusega seotud vead minimaalse diffiga;
- `lifespan` peale üleviimine muudab rakenduse elutsükli wiring'ut korraga laiemalt kui ainult reCAPTCHA/join voog.

Staatus:
- teadlikult edasi lükatud moderniseerimine / maintainability cleanup

Millal uuesti hinnata:
- järgmises backend maintainability passis;
- kui FastAPI upgrade või muu elutsüklit puudutav muudatus niikuinii toimub.

### 2a.16 Kaardiga aktiivse võistluse map-layer nõude autoriteetne jõustamine PL/SQL / ORDS kihis

Mõjutatud failid / kihid:
- `backend/app/main.py`
- ORDS / PL/SQL admin entrypointid, mis muudavad võistluse staatust või participant map-layer ridu

Praegune seis:
- reegel `ACTIVE + use_location = 'Y' => vähemalt üks aktiivne participant map-layer` on jõustatud FastAPI BFF kihis;
- see katab tavapärase admin UI voo, kuid ei ole veel viidud autoriteetsesse DB/ORDS kihti.

Miks jäi praegu backlogi:
- käesoleva töö eesmärk oli parandada päris kasutajani jõudnud UX/andmevoo probleem minimaalse diffiga;
- PL/SQL taseme jõustamine on õige järgmine samm, kuid see puudutab laiemalt seda, milline kiht on staatusemuudatuste autoriteetne värav;
- enne DB-poolset lisamist tasub otsus teha teadlikult, et vältida sama reegli hajutamist mitmesse sõltumatusse kohta.

Staatus:
- teadlikult edasi lükatud andmetervikluse tugevdamine / backlog

Millal uuesti hinnata:
- kui järgmine töövoog puudutab admin staatusemuudatuste ORDS/PLSQL autoriteetsust;
- kui leitakse mõni tegelik bypass FastAPI-välise sisestuskanali kaudu.

### 2a.17 Admin competition meta oleku hoidmine ühes koond-state objektis

Mõjutatud fail:
- `frontend_dist/assets/admin-main.js`

Praegune seis:
- map-layer nõude frontend-valideerimine toetub väärtustele `window.__lastCompetitionStatus` ja `window.__lastCompetitionUseLocation`;
- praeguses voos laetakse need pärast edukat salvestust uuesti `loadView()` kaudu, seega kinnitatud bugi ei ole.

Miks jäi praegu backlogi:
- teema on eelkõige maintainability/refaktori küsimus, mitte kinnitatud funktsionaalne rike;
- olemasolev töövoog töötab ja käesoleva muudatuse eesmärk ei olnud admin state-halduse laiem ümberkorraldus.

Staatus:
- teadlikult edasi lükatud state-halduse puhastus / backlog

Millal uuesti hinnata:
- kui admin-vaatesse lisandub rohkem sama võistluse jooksva oleku peale toetuvat valideerimist;
- kui `window.__last...` väärtuste hulk kasvab või nende sünkroonsus muutub päriselt hapraks.

## 3. Kuidas seda dokumenti kasutada

- Kui Sonar või Gemini raporteerib järgmistes commitides uuesti sama leidu, kontrolli esmalt siit, kas tegemist on juba teadlikult aktsepteeritud punktiga.
- Kui leid on siin kirjas ja olukord pole muutunud, ei pea sama otsust uuesti nullist läbi vaidlema.
- Kui arhitektuur või koodistruktuur muutub nii, et siin toodud põhjendus enam ei kehti, tuleb see dokument uuendada või punkt eemaldada.
