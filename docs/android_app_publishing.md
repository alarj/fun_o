# Android äpi publitseerimise juhend

See dokument koondab kokku juhendi, mida on vaja jälgida, kui `fun_o` Android bundled äpp tahetakse Google Play poodi viia.

Dokument on kirjutatud praeguse projekti seisu põhjal:

- äpi nimi on `Fun-O`
- Android package / application id on `ee.funo.competitor`
- publitseerimiseks kasutatakse bundled Android äppi
- release artefaktiks on eelistatult `AAB`
- privaatsuspoliitika lehed on:
  - `frontend_dist/content/privacy_et.html`
  - `frontend_dist/content/privacy_en.html`

## 1. Eesmärk

Google Play poodi mineku jaoks on vaja:

- toimiv signed release build
- Play Console arendajakonto
- rakenduse poeandmed
- rakenduse sisudeklaratsioonid
- testrelease
- tootmisrelease

Praeguse projekti puhul on tehniline alus suuresti olemas, kuid Play Console konto loomine ja poeprotsess tuleb teha eraldi.

## 2. Mis on projektis juba olemas

Praeguses koodibaasis on olemas järgmised olulised eeldused:

- Android shell
- bundled release buildi tugi
- release signing konfiguratsioon
- GitHub workflow release `AAB` ehitamiseks
- GitHub workflow release `APK` ehitamiseks
- äpi ikoon
- privaatsuspoliitika lehed

Olulised failid:

- `android/app/build.gradle`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/values/strings.xml`
- `.github/workflows/android-release-aab.yml`
- `.github/workflows/android-release-apk.yml`
- `frontend_dist/content/privacy_et.html`
- `frontend_dist/content/privacy_en.html`

## 3. Soovitatud release artefakt

Google Play jaoks tuleb kasutada `AAB` faili.

Põhjused:

- Google Play ootab uute rakenduste puhul App Bundle formaati
- Play ise teeb sellest seadmespetsiifilised paketid
- see on ametlik ja soovitatud tee

`APK` on endiselt kasulik:

- käsitsi testimiseks
- kiireks külglaadimiseks telefoni
- olukordades, kus Play Console'it ei kasutata

Reegel:

- Play Store uploadiks kasuta `AAB`
- käsitsi testimiseks kasuta vajadusel `APK`

## 4. Äpi identiteet, mida tuleb hoida stabiilsena

Play Store'i jaoks on oluline, et mõned väärtused jääksid püsivaks.

Praegused väärtused:

- äpi nimi: `Fun-O`
- application id: `ee.funo.competitor`

Neid ei tohi pärast Play Store'i publitseerimist kergekäeliselt muuta.

Eriti oluline:

- `applicationId` muutmine looks Play jaoks sisuliselt uue rakenduse
- signing key peab jääma samaks

## 5. Versioneerimine

Praegu on Android buildis versiooniloogika:

- `versionCode` vaikimisi `20500`
- `versionName` vaikimisi `2.5`

Need tulevad failist:

- `android/app/build.gradle`

Senine kokkulepe projektis:

- hoida äpi versioon joondatuna projekti release numeratsiooniga
- näiteks `2.5`, `2.5.1`, `2.6`

Soovitus:

- `versionName` on inimesele nähtav versioon
- `versionCode` peab iga järgmise Play release'iga suurenema

Praktiline reegel:

- ära lae Play Console'i üles buildi, mille `versionCode` ei ole eelmisest suurem

## 6. Signing

Play Store release peab olema signeeritud.

Projektis on selleks ette valmistatud järgmised saladused / seadistused:

- `FUNO_RELEASE_KEYSTORE_BASE64`
- `FUNO_RELEASE_STORE_PASSWORD`
- `FUNO_RELEASE_KEY_ALIAS`
- `FUNO_RELEASE_KEY_PASSWORD`

Need on vajalikud GitHub Actions release workflow jaoks.

Oluline:

- kasuta alati sama keystore't
- hoia keystore varukoopia turvalises kohas
- hoia paroolid turvalises kohas

Kui keystore kaob ja taastamisvõimalust ei ole, võib edaspidine uuendamine muutuda väga keeruliseks.

## 7. GitHub workflow'd

Praegused olulised workflow'd:

- `.github/workflows/android-release-aab.yml`
- `.github/workflows/android-release-apk.yml`

Nende mõte:

- `android-release-aab.yml` ehitab Play Store'i jaoks release bundle'i
- `android-release-apk.yml` ehitab signed release APK testimiseks

Soovituslik kasutus:

1. tee koodimuudatused valmis
2. veendu, et õige branch sisaldab viimast Android release workflow faili
3. käivita release build GitHubis
4. lae artefakt alla
5. kontrolli enne publitseerimist telefoni peal

## 8. Mida enne Play Console'i kindlasti kontrollida

Enne publitseerimist kontrolli vähemalt need punktid läbi.

### 8.1 Funktsionaalne kontroll

- äpp avaneb ilma valge tühja ekraanita
- võistlusega liitumine toimib
- reCAPTCHA toimib
- kaart avaneb
- overlay kaart avaneb
- Mapy.cz kaart avaneb
- asukohaõigused toimivad
- sinise asukohatäpi lipp muutub õigesti
- follow nupp töötab
- portrait lock töötab
- keep awake töötab kaardivaates

### 8.2 Release kontroll

- build on tehtud release workflow kaudu
- build on signed
- `versionName` on õige
- `versionCode` on eelmisest suurem
- package name on õige

### 8.3 Õiguslik ja sisuline kontroll

- privacy policy URL on avalik
- kontakt e-post on olemas
- poe kirjeldused on olemas
- screenshotid on olemas
- app icon on õige

## 9. Mida on Google Play Console'is vaja teha

## 9.1 Loo arendajakonto

Google Play Console kasutamiseks on vaja arendajakontot.

Arvestada tuleb:

- konto loomine ei pruugi olla tasuta
- Google võib küsida isikutuvastust või ettevõtte andmeid
- nõuded võivad aja jooksul muutuda

Kui arendajakontot veel ei looda, saab äppi seni jagada käsitsi `APK` kaudu.

## 9.2 Loo uus rakendus

Play Console'is tuleb luua uus app ja määrata vähemalt:

- app name: `Fun-O`
- default language
- kas tegemist on appi või mänguga
- kas rakendus on tasuta või tasuline

Soovitus:

- hoia nimi Play Console'is samana nagu rakenduses endas: `Fun-O`

## 9.3 Store listing

Täita tuleb poeandmed:

- app name
- short description
- full description
- app icon
- phone screenshotid
- feature graphic
- kategooria
- contact details
- privacy policy URL

`fun_o` puhul tuleb siin arvestada, et rakendus on:

- võistlustel kasutatav osaleja rakendus
- kaardivaatega
- kasutab asukohta

Seega peaks kirjeldus ausalt mainima vähemalt:

- võistlusega liitumist koodi alusel
- kontrollpunktide küsimusi
- kaardi kasutamist
- valikulist või reeglipõhist asukoha kasutust

## 9.4 App content

Play Console küsib lisaks mitu sisudeklaratsiooni.

Tüüpiliselt tuleb täita:

- Privacy policy
- Data safety
- App access
- Content rating
- Ads

### Privacy policy

Praegused lehed:

- eesti: `https://fun-o.eu/content/privacy_et.html`
- inglise: `https://fun-o.eu/content/privacy_en.html`

Soovitus:

- Play Console'is kasuta avalikku ja püsivat URL-i
- kui võimalik, eelista ingliskeelset varianti või veendu, et kasutatud link on sihtrühmale arusaadav

### Data safety

Praeguse rakenduse põhjal tuleb väga hoolikalt hinnata vähemalt neid andmekategooriaid:

- asukohaandmed
- kasutaja sisestatud alias
- kasutaja vabatahtlik e-post
- võistluse osalusandmed
- vastused ja tulemused
- tehnilised sessiooniandmed

Siin ei tohi oletada. Enne märkimist tuleb võrrelda Play küsimustikku tegeliku süsteemikäitumisega.

Eriti oluline:

- kui andmeid kogutakse, tuleb see ausalt deklareerida
- kui asukohaandmeid kasutatakse, tuleb see ausalt deklareerida
- kui andmeid hoitakse serveris, tuleb see arvesse võtta

Praeguse privaatsuspoliitika põhjal on oluline meeles pidada:

- andmeid töödeldakse EL-is asuvates serverites
- rakendus kasutab asukohta võistluse funktsioonide täitmiseks

### App access

See rakendus ei ole täiesti avalik “avatud sisu” rakendus, sest sisusse jõudmiseks on vaja:

- liituda võistlusega
- sisestada võistluse kood

Seetõttu tuleb Play review jaoks anda selge testimisjuhis.

Soovituslik info reviewerile:

- testvõistluse kood
- testkasutaja alias, mida võib kasutada
- lühike juhend:
  1. ava rakendus
  2. sisesta võistluse kood
  3. sisesta alias
  4. liitu võistlusega
  5. ava kaart

Kui review ajal vajalikud andmed puuduvad, võib Google rakenduse tagasi lükata.

### Content rating

Tuleb täita Google Play küsimustik.

Praeguse rakenduse olemuse järgi on tõenäoline, et sisu on madala riskiga, kuid tegelik hinnang tuleb anda küsimustiku järgi.

### Ads

Kui rakenduses ei ole reklaame, tuleb märkida, et reklaame ei kasutata.

## 10. Testtrackid

Soovituslik tee enne productionit:

1. `Internal testing`
2. vajadusel `Closed testing`
3. alles siis `Production`

Põhjus:

- sisuvormide vead tulevad kiiresti välja
- signing / install / uuendamise probleemid selguvad varem
- review jaoks vajalikke tekste on lihtsam enne productionit parandada

## 11. Fun-O projekti konkreetsed publish-eelsed materjalid

Enne Play Store'i minekut tuleks valmis hoida vähemalt:

- signed `AAB`
- testimiseks signed `APK`
- app icon
- telefoni screenshotid
- feature graphic
- lühikirjeldus eesti keeles
- lühikirjeldus inglise keeles
- pikk kirjeldus eesti keeles
- pikk kirjeldus inglise keeles
- privacy policy URL
- reviewer testikonto / testvõistluse juhis
- kontakt e-post, näiteks `fun-o@gmail.com`

## 12. Mis on praegu kõige mõistlikum praktiline tee

Kui Play Console kontot veel ei tehta, siis on mõistlik vahevariant:

- jätkata bundled äpi testimist
- jagada testijatele `APK` käsitsi
- hoida release `AAB` ehitamise võimekus töökorras
- täiendada aegamööda poe materjale

See vähendab survet teha Play Store samm enne, kui:

- rahaline otsus arendajakonto osas on tehtud
- review jaoks vajalikud tekstid ja pildid on valmis
- release protsess on piisavalt stabiilne

## 13. Enne päris publitseerimist tehtav viimane kontroll

Vahetult enne esimest päris Play release'i kontrolli see nimekiri uuesti läbi.

- arendajakonto on olemas
- app nimi on õige
- package name on õige
- signed `AAB` on olemas
- `versionCode` on eelmisest suurem
- privacy policy link töötab
- Data safety on sisuliselt korrektne
- App access juhis on olemas
- screenshotid ja feature graphic on olemas
- release on testitud päris telefonis
- install olemasoleva versiooni peale toimib

## 14. Ametlikud viited

Need ametlikud viited on mõistlik enne päris publitseerimist uuesti üle kontrollida, sest Google võib nõudeid muuta.

- Android Developers: [Google Play Console overview](https://developer.android.com/distribute/console)
- Android Developers: [Android App Bundle](https://developer.android.com/guide/app-bundle)
- Android Developers: [Publish your app](https://developer.android.com/studio/publish)
- Google Play Help: [Prepare and roll out a release](https://support.google.com/googleplay/android-developer/answer/9859348)
- Google Play Help: [Data safety form](https://support.google.com/googleplay/android-developer/answer/10787469)

## 15. Kokkuvõte

`fun_o` projekti tehniline Androidi release-valmidus on suurel määral olemas.

Päris publitseerimiseks on peamised järgmised sammud:

1. hoia signed `AAB` build töökorras
2. loo Play Console konto siis, kui see on äriliselt mõistlik
3. täida store listing ja app content
4. testi internal või closed trackis
5. alles siis mine productionisse

Praegu ei ole Play Store'i mineku peamine takistus mitte Android shell ise, vaid:

- arendajakonto loomine
- poe protsess
- sisudeklaratsioonide korrektne täitmine
- publitseerimismaterjalide valmisolek
