# Kasutaja mobiiliäpi suund

See dokument kirjeldab otsust ja kaalutlusi, kuidas viia praegune võistleja kasutajavaade mobiiliäpiks nii, et olemasolev veebilahendus jääks alles ja tulevikutee iOS-i suunas oleks avatud.

## Eesmärk

Soov on teha praegusest vanilla JS võistleja lehest mobiiliäpp, esialgu Androidile, järgmiste nõuetega:

- brauserist käivitatav kasutaja-UI peab edasi töötama;
- Androidi jaoks peab olema võimalik ehitada installitav APK/AAB;
- äpp peab suutma kaardirežiimis telefoni ekraani ärkvel hoida;
- äpp peab töötama portrait-orientatsioonis nii, et telefoni auto-rotate ei pööraks kaardivaadet;
- äppi peab saama tulevikus levitada Play Store'i kaudu;
- hiljem peab jääma realistlik võimalus teha samast lahendusest ka iOS äpp.

## Olemasolev lähtekoht

Praegune võistleja kasutajavaade on eraldi staatiline frontend:

- `frontend_dist/index.html`
- `frontend_dist/assets/competitor.css`
- `frontend_dist/assets/competitor-core.js`
- `frontend_dist/assets/competitor-map.js`
- `frontend_dist/assets/competitor-main.js`

See on oluline eelis, sest võistleja UI ei ole läbi põimunud admini ega superadmini vaadetega.

Praegune competitor UI:

- kasutab olemasolevat FastAPI `/api/*` kihti;
- kasutab brauseri geolokatsiooni;
- kasutab seadme orientatsiooni/kompassi sündmusi;
- kasutab Leafletit ja seotud kaarditeeke;
- on juba mobiilikeskne.

Järeldus: tegemist ei ole olukorraga, kus tuleks nullist native mobiiliäpp kirjutada. Mõistlikum on olemasolev competitor UI tõsta rakenduse shelli sisse.

## Vaadatud variandid

Arutelus kaaluti põhimõtteliselt nelja teed.

### 1. Jääda ainult brauserilahenduse juurde

Plussid:

- puudub lisahooldus äpile;
- üksainus kasutajavaade;
- puudub äpipoodide protsess.

Miinused:

- ekraani ärkvelhoid ei ole piisavalt kontrollitav;
- portrait-lock ei ole usaldusväärselt lahendatav tavabrauseris;
- äppi ei saa Play Store'i panna kui päris Android rakendust.

See variant ei kata esitatud nõudeid.

### 2. PWA või TWA

Plussid:

- web-first lähenemine;
- väiksem lisakeerukus kui täisnative arendus;
- võib sobida lihtsamatele sisurakendustele.

Miinused:

- seadme ekraani ärkvelhoid ja orientatsiooni kontroll on nõrgemad;
- sõltuvus brauseri käitumisest on suurem;
- kaardi- ja sensoripõhise rakenduse puhul jääb kontroll liiga õhukeseks.

See variant ei tundunud piisavalt tugev just selle projekti vajaduste jaoks.

### 3. Täiesti eraldi native või ristplatvormi ümberkirjutus

Näited: Kotlin, Swift, Flutter, React Native.

Plussid:

- maksimaalne kontroll seadmefunktsioonide üle;
- saab luua täiesti app-first kasutuskogemuse.

Miinused:

- väga suur arenduskulu;
- olemasolev competitor UI tuleks sisuliselt ümber kirjutada;
- suureneb risk, et web ja app hakkavad funktsionaalselt lahknema;
- hoolduskoormus kasvab järsult.

See ei ole praeguses etapis proportsionaalne lahendus.

### 4. Capacitor

Plussid:

- olemasolev web UI saab jääda põhikoodibaasiks;
- Android ja hiljem iOS saavad kasutada sama competitor vaadet;
- native kihis saab lisada ekraani ärkvelhoiu ja orientatsiooniluku;
- Play Store'i jaoks tekib tavaline Android projekt;
- hiljem on võimalik minna hosted mudelilt bundled mudelile.

Miinused:

- tuleb hallata väikest native kihti;
- tuleb testida WebView, õiguste ja sensorite käitumist päris seadmetel;
- iOS App Store review võib hosted-wrapperi suhtes olla tundlikum.

See osutus parimaks üldsuunaks.

## Valitud suund

Valitud suund on `Capacitor` ning arhitektuuriline lähenemine on:

- esialgu `hosted web UI + app shell`;
- aga lahendus tuleb teha algusest `bundle-ready`.

See tähendab:

- brauseris töötav `frontend_dist/index.html` jääb alles;
- Android äpp kasutab alguses sama competitor UI-d rakenduse shelli sees;
- native kiht lisab ainult neid võimekusi, mida brauser ise piisavalt hästi ei anna;
- lahendus valmistatakse ette nii, et hiljem saaks sama competitor UI viia vajadusel äpi sisse bundle'ituna kaasa;
- iOS tee hoitakse teadlikult avatuna.

## Miks valiti hosted-first, kuid bundle-ready mudel

Hosted-first mudel valiti, sest see vähendab esimeses etapis hoolduskoormust.

Peamised põhjused:

- sama kasutajavaate muudatus jõuab kohe nii veebisse kui äppi;
- iga väikese UI muudatuse jaoks ei pea uut Android buildi ja levitust tegema;
- competitor UI muutub praegu tõenäoliselt veel edasi;
- olemasolev Leafleti-põhine kaardiloogika saab jääda samaks;
- APK/AAB tegemiseks on vaja ainult õhukest Android ümbrist, mitte uut UI-d.

Bundle-ready nõue lisati kohe alguses, sest:

- hiljem võib iOS App Store review nõuda tugevamat äpi-identiteeti kui lihtsalt hosted wrapper;
- sama konkurendi UI peab vajadusel töötama ka lokaalselt äppi kaasa pandud varana;
- varajane ettevalmistus on odavam kui hilisem ümbertegemine.

## Hosted web UI + app shell

Selles mudelis:

- Capacitori Android äpp avab competitor UI;
- competitor UI jääb serverist hostituks;
- backend ja API arhitektuur jäävad samaks;
- web ja äpp kasutavad sama kasutajavaate koodi.

### Hosted mudeli eelised

- väikseim lisaarendus;
- üks competitor UI koodibaas;
- kiireim tee Android äpini;
- kasutajavaate parandused jõuavad kohe kõikjale;
- Leaflet ja olemasolev JS loogika jäävad suuresti puutumata.

### Hosted mudeli puudused

- äpp sõltub serveri kättesaadavusest ja võrgust;
- serverist serveeritud vigane frontend mõjutab kohe ka äppi;
- iOS App Store review jaoks võib hosted wrapper olla riskantsem kui bundled variant;
- API ja WebView erisused tuleb siiski hoolikalt läbi testida.

## Bundled web UI

Selles mudelis:

- competitor HTML/CSS/JS pannakse äpi sisse kaasa;
- äpp serveerib UI lokaalselt;
- backend jääb alles API teenindamiseks.

### Bundled mudeli eelised

- äpp on rohkem versioneeritud koos oma release'iga;
- iOS review risk võib olla väiksem kui hosted wrapperi puhul;
- sobib paremini tulevaseks app-first või osaliselt offline suunaks.

### Bundled mudeli puudused

- iga UI muudatus võib tähendada uut äpiversiooni;
- release-protsess läheb raskemaks;
- competitor UI peab olema teadlikum API baas-URL-ist ja lokaalse/hostitud režiimi erinevusest;
- hoolduskoormus kasvab võrreldes hosted variandiga.

## Hosted -> Bundled üleminek

Hosted-first ei ole tupiktee.

Kui competitor UI tehakse kohe bundle-ready põhimõttel, siis on hiljem võimalik:

- jätta brauseri `index.html` edasi tööle;
- hoida Androidi äppi samast competitor UI-st;
- muuta Android või iOS rakendus vajadusel bundled mudelile;
- teha seda ilma competitor kasutajavaadet nullist ümber kirjutamata.

Ülemineku eelduseks on, et competitor UI ei sõltu jäigalt ainult ühest käivitusviisist.

## Native võimekused, mida äpis on vaja

Praeguse arutelu põhjal on kriitilised kaks võimekust.

### 1. Ekraani ärkvelhoid kaardirežiimis

Nõue:

- kui kasutaja on kaardirežiimis, ei tohi telefon ekraani välja lülitada.

Põhimõte:

- seda ei pea hoidma aktiivsena kogu äpis;
- kõige mõistlikum on siduda see ainult kaardivaatega, et vältida põhjendamatut aku kulu.

### 2. Portrait-orientatsiooni sund

Nõue:

- telefoni auto-rotate ei tohi kaarti pöörata;
- äpp peab jääma portrait-orientatsiooni.

Põhimõte:

- see tuleks kehtestada rakenduse tasemel native kihis;
- competitor kaardiloogika ei pea ise seadme ekraani pöörde vastu võitlema.

## Leaflet ja kaart

Praeguse competitor rakenduse kõige keerukam osa on Leafleti-põhine kaardivaade.

Praegune otsus on:

- Leafleti kaart jääb samal kujul alles;
- seda ei plaanita esimeses etapis asendada native kaardikomponendiga;
- olemasolev `competitor-map.js` loogika jääb põhiliseks ka äpis.

Mida tuleb siiski kontrollida:

- Android WebView geolokatsiooni load;
- kompassi ja orientatsioonisündmuste käitumine päris seadmetel;
- viewporti ja täisekraanitunnetuse detailid WebView sees;
- kaardivaatel ekraani ärkvelhoiu sidumine.

Järeldus:

- suurimat rakenduse keerukust ei plaanita praegu ümber kirjutada;
- see on üks peamisi põhjuseid, miks Capacitori tee on atraktiivne.

## Live Updates

Arutelus kerkis üles ka küsimus, kas kasutada Capacitori ökosüsteemi live update tüüpi lahendusi.

Kokkuvõte:

- sellised lahendused on olemas HTML/CSS/JS tüüpi web-asset'ite uuendamiseks;
- need ei lahenda native muudatusi;
- hosted mudelis on nende väärtus väike, sest hosted UI muutub niigi serveri deployga;
- bundled mudelis võivad need hiljem olla kasulikud piiratud ulatuses.

Praegune otsus:

- esimest lahendust ei ehitata live updates peale;
- live updates ei ole esimeses etapis arhitektuuri keskne eeldus;
- seda võib hiljem hinnata eraldi, kui bundled suund muutub aktuaalseks.

## Android build väljund

APK/AAB ei teki `frontend_dist` kataloogi.

Kui projektile lisandub Capacitori Android alamprojekt, siis build väljund tekib tavaliselt siia:

- `android/app/build/outputs/apk/...`
- `android/app/build/outputs/bundle/...`

Näited:

- `android/app/build/outputs/apk/debug/app-debug.apk`
- `android/app/build/outputs/bundle/release/app-release.aab`

`frontend_dist` jääb endiselt competitor web UI staatiliste failide asukohaks.

## Oodatav hooldusmudel

Kui arhitektuur tehakse õigesti, siis ei teki eraldi kolme kasutajavaate koodibaasi stiilis:

- web UI
- Android UI
- iOS UI

Soovitud mudel on:

- üks competitor kasutajavaate koodibaas;
- õhuke Android shell;
- hiljem vajadusel õhuke iOS shell.

See tähendab, et enamik kasutajavaate muudatusi tehakse ühes kohas.

Eraldi native kihis jäävad vaid need teemad, mis on seadme- või platvormispetsiifilised:

- wake lock;
- orientatsioonilukk;
- õiguste tekstid ja load;
- äpi ikoonid, splashid ja store-spetsiifiline meta;
- võimalikud WebView või sensorite erisused.

## Riskid ja tähelepanekud

### 1. Hosted wrapper iOS-is

Apple võib suhtuda hosted-wrapper tüüpi rakendustesse ettevaatlikumalt kui Play Store.

Järeldus:

- iOS-i puhul ei tohi strateegia eeldada, et hosted variant kindlasti kinnitatakse;
- bundle-ready ettevalmistus on oluline kaitse tulevikuks.

### 2. Sensorid ja load

Geolokatsioon ja orientatsioon võivad Androidi ja iOS-i seadmetes käituda erinevalt.

Järeldus:

- enne lõplike arhitektuuriliste järelduste tegemist tuleb testida päris seadmetel.

### 3. Võrgusõltuvus

Hosted mudel sõltub serverist ja võrguühendusest.

Järeldus:

- kui hiljem muutub oluliseks app-first või offline suund, tuleb bundled lahendus uuesti lauale.

### 4. Leafleti keerukus

Kaardivaade on competitor rakenduse kõige delikaatsem osa.

Järeldus:

- esimene mobiiliäpi iteratsioon peaks vältima kaardikihi tarbetut ümbertegemist;
- muudatused peavad jääma ümbrise, õiguste ja seadmevõimekuste tasemele.

## Praegune otsus kokkuvõtlikult

Praeguse arutelu põhjal on valitud suund järgmine:

- competitor web UI jääb alles ja peab edasi töötama brauseris;
- esialgu tehakse Androidi äpp Capacitori abil;
- esimene äpivariant on hosted web UI + app shell;
- lahendus tehakse kohe bundle-ready põhimõttel;
- Leafleti kaardiloogika jääb esimeses etapis samaks;
- live updates ei ole esialgse lahenduse keskne osa;
- hiljem saab hinnata bundled mudelit, eriti kui iOS App Store suund muutub oluliseks.

## Järgmised sammud

Kui hakatakse tehnilist lahendust tegema, siis järgmised loogilised sammud on:

1. täpsustada competitor UI käivitusmudel nii, et see toetaks nii brauserit kui app-shelli;
2. määrata, kuidas competitor frontend saab kätte API baas-URL-i eri režiimides;
3. lisada Androidi Capacitori shell;
4. siduda kaardivaatega ekraani ärkvelhoid;
5. kehtestada äpile portrait-orientatsioon;
6. testida geolokatsiooni, kompassi ja Leafleti kaarti päris Android seadmes;
7. alles pärast stabiliseerumist otsustada, kas iOS suunas minna hosted või bundled lähenemisega.
