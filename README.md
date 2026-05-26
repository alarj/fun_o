# fun_o

`fun_o` on mobiilisõbralik veebisüsteem orienteerumisvõistluste korraldamiseks ja läbiviimiseks, kus kontrollpunktides (KP) vastatakse küsimustele ning punktiarvestus tekib automaatselt. 
- Võistlusi saab luua nii mobiilis kuvatava kaardiga kui ka kaardita. Kaardirežiimis on võimalik kuvada võistleja asukohta ning lubada küsimustele vastata ainult kindlas piirkonnas viibides. 
- Võistluste korraldamisel saab kasutada erinevaid avalikest allikatest pärit kaarte, nii Eesti-keskseid kaarte (nt Maa-ameti kaardid) kui laiema katvusega kaarte (nt OpenStreetMap, Mapy.cz jms.). 
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
- võistluse ajal nähtav enda progress, punktid ja läbitud KP-d.

### Korraldaja väärtus

- võistluse, KP-de, küsimuste, vastuste ja koodide haldus ühest kohast;
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
- Docker Compose’iga käivitatav tervik (nginx + backend + testiprofiil).

See arhitektuur toetab eesmärki hoida ärireeglid stabiilsena, vähendada UI-poolset “nutikust” ning tagada, et sama reegel kehtib kõigile klientidele ühtemoodi.

## Tehniline arhitektuur (viited)

Tehnilised detailid on kirjeldatud olemasolevates dokumentides:

- süsteemiarhitektuur: [docs/system_architecture.md](docs/system_architecture.md)
- andmemudel (ERD): [docs/erd.md](docs/erd.md)
- asukohaloogika reeglid: [docs/location_rules.md](docs/location_rules.md)
- liitumise ja osaluse reeglid: [docs/competitor_join_rules.md](docs/competitor_join_rules.md)
- backendi API/integreerimisdetailid: [backend/README.md](backend/README.md)
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
