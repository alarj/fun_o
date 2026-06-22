# Asukohareeglid (location rules)

See dokument kirjeldab kokkulepitud ärireegleid, kuidas asukohaandmeid kasutatakse võistlustel, kontrollpunktidel (KP) ja võistleja vaates.

## 1. Võistluse taseme parameetrid

### 1a. Aja autoriteetsus

- Andmebaasi autoriteetne aeg on selles süsteemis UTC.
- ORDS/DB kiht võib kasutada ajalistes kontrollides Oracle serveri hetkeaega eeldusel, et see keskkond töötab UTC ajas.
- Brauser kuvab kuupäevi ja kellaaegu kasutaja lokaalses ajas.
- Vahekiht ja frontend peavad selle erinevusega arvestama nii, et ärireeglid lähtuvad DB/UTC ajateljest, kuid kasutajale näidatakse aega tema lokaalses ajas.

- `competitions.use_location` (`Y`/`N`)
  - Määrab, kas võistlus kasutab asukohaloogikat üldse.
- `competitions.radius_m` (number, meetrites)
  - Vaikimisi kauguslävi, mida kasutatakse KP-de puhul, kui KP-l eraldi raadiust pole määratud.
- `competitions.show_competitor_location` (`Y`/`N`)
  - Määrab ainult selle, kas võistleja sinist asukohamarkerit kuvatakse kaardil.
  - See ei tohi välja lülitada kaardi pööramist, `follow`-režiimi ega asukohapõhist KP avatavuse kontrolli, kui `use_location='Y'`.

## 2. Kontrollpunkti taseme parameetrid

- `checkpoints.latitude`, `checkpoints.longitude`
  - KP geokoordinaadid (WGS84).
- `checkpoints.checkpoint_type`
  - KP liik: `NORMAL`, `START`, `FINISH`.
  - Kui väärtus on `NULL`, käsitletakse seda äriloogikas kui `NORMAL`.
- `checkpoints.checkpoint_interaction`
  - KP aktiivse interaktsiooni liik: `QUESTION`, `CHECK_ONLY`, `MASS_START`.
  - `MASS_START` on lubatud ainult `START` checkpointil.
  - Raja pikkuse arvutuses kehtib küsimuse olemasolu nõue ainult siis, kui interaktsioon on `QUESTION`.
  - Kui checkpointi interaktsioon muudetakse `QUESTION`-ist mõneks muuks väärtuseks ja checkpointil on aktiivne küsimus, peab admin UI enne salvestust küsima kinnituse; ainult kinnituse järel lõpetab süsteem seotud aktiivse küsimuse (soft-delete).
- `checkpoints.radius_m` (number, meetrites, nullable)
  - KP-spetsiifiline raadius. Kui puudub, kasutatakse `competitions.radius_m`.
- `checkpoints.location_required` (`Y`/`N`)
  - Kas selle KP vastuse juures on asukoht kohustuslik.
  - Admin UI-s muudetav ainult siis, kui võistlusel `use_location='Y'`.

## 2a. START / FINISH erireeglid

- Ühel aktiivsel võistlusel võib olla maksimaalselt üks aktiivne `START` ja üks aktiivne `FINISH`.
- Soft-deleted `START`/`FINISH` kirjed arvesse ei lähe.
- `START` ja `FINISH` on tavalised küsimusega KP-d:
  - nende läbimine tekib `submissions` kaudu samamoodi nagu teistel KP-del;
  - nad võivad anda punkte tavalisel moel.
- Erand: kui `START.checkpoint_interaction = MASS_START`, siis võistleja ei vasta START checkpointi käsitsi.
  - süsteem lisab `submission_events` tabelisse tehnilise `MASS_START` sündmuse automaatselt esimese päris checkpointi tegevuse ajal;
  - selle sündmuse äriline aeg (`submitted_at`) on `competitions.mass_start_at`;
  - sündmuse tegelik salvestamise aeg läheb `evaluated_at` väljale;
  - enne `mass_start_at` aega ei tohi teisi checkpointi tegevusi lubada.
- Kui `checkpoint_interaction = CHECK_ONLY`, siis võistleja ei vasta küsimusele, vaid registreerib checkpointi läbimise ühe tegevusega.
- `START` pealkiri on alati `START`.
- `FINISH` pealkiri on alati `FINISH`.
- `START` ja `FINISH` tüüpi olemasolevat KP-d ei saa adminis muuta teiseks liigiks.
- Ka tavalist `NORMAL` KP-d ei muudeta edit-vaates `START` või `FINISH` tüübiks.
- `START.order_no = 0`.
- `FINISH.order_no = 9999`.
- See `order_no` reegel kehtib nii `R` kui `S` tüüpi võistlustel.
- Admin kasutaja ei sisesta ega muuda `START`/`FINISH` `order_no` väärtust käsitsi.
- Admini `Uus KP / Muuda KP` modalis kuvatakse `order_no` sisestusväli ainult `S` tüüpi võistlustel tavalise `NORMAL` KP jaoks.
- `R` tüüpi võistlustel ei kuvata admini `Uus KP / Muuda KP` modalis `order_no` sisestusvälja ega saadeta selle väärtust checkpointi salvestusel.

## 3. Asukohaloogika sisse/välja

- Kui `competition.use_location='N'`:
  - GPS loogikat ei rakendata.
  - KP `location_required` väärtust ignoreeritakse.
  - Admin UI-s asukohaväljad ei ole aktiivsed.
  - KP nimekirjas asukohaveergu ei kuvata.

- Kui `competition.use_location='Y'`:
  - GPS loogika on lubatud.
  - KP võib olla koordinaatidega või ilma.
  - Kui KP-l koordinaate pole, jääb käsitsi valik alati võimalikuks.

## 4. Võistleja vaate reeglid

- Kui asukoht on saadaval:
  - süsteem võib pakkuda eelisjärjekorras lähedal olevaid KP-sid.
- Kui asukohta ei saa (luba puudub/GPS viga/seade ei toeta):
  - võistleja saab KP käsitsi valida (fallback).
- Kui GPS täpsus on halb:
  - KP käsitsi valik peab jääma võimalikuks.
- Võistluse tüübid:
  - `R` tähendab vaba läbimise järjekorda, välja arvatud see, et kui aktiivne `START` eksisteerib, tuleb see läbida enne kõiki teisi KP-sid.
  - `S` tähendab etteantud läbimise järjekorda: pärast `START`i saab vastata ainult järgmisele vastamata `NORMAL` KP-le `order_no` järgi.
  - `S` tüübil ei sõltu järgmise KP avanemine sellest, kas eelmine vastus oli õige või vale; oluline on, et eelmine KP oleks vastatud.

### 4a. `index.html` keskmise ala reeglid

- `index.html` ülemine blokk (võistluse nimi, keelevahetus, uuele võistlusele liitumine) jääb samaks sõltumata võistluse liigist.
- `index.html` alumine blokk (progress + `Tulemused`) jääb samaks sõltumata võistluse liigist.
- Muutuv osa on ainult keskmine ala.
- Kui `competition.use_location='Y'`:
  - keskmises alas kuvatakse raja pikkuse / massstardi infoplokk;
  - sama ploki all kuvatakse keskele joondatud `Kaart` nupp;
  - küsimuste nimekirja ega `Kuva KP-d` plokki avalehel ei kuvata.
- Kui `competition.use_location='N'`:
  - keskmises alas kuvatakse tavapärane küsimuste/KP-de plokk;
  - `Kaart` nuppu ei kuvata.

## 5. Kaardivaade ja avamise reeglid

- Kaardivaate aluskiht (`layer`) salvestatakse cookie-sse võistlusepõhiselt.
- Kaardivaate `center + zoom` salvestatakse cookie-sse võistlusepõhiselt ja projektsioonipõhiselt (per CRS):
  - eraldi vaade `EPSG:3857` jaoks;
  - eraldi vaade `EPSG:3301` jaoks.
- CRS vahetusel (`3857 <-> 3301`) taastatakse kohe siht-CRS-i viimane salvestatud vaade.
- Kui siht-CRS-il varasemat vaadet pole, kasutatakse hetkeks aktiivset vaadet ja salvestatakse see uue CRS-i vaateks.
- Kaardi avamisel:
  - kui salvestatud vaade on olemas, taastatakse viimane `zoom`;
  - kui kasutaja asukoht on teada ja follow-režiim on sees, nihutatakse kaart kasutaja asukohale nii, et salvestatud zoom jääb samaks;
  - kui salvestatud vaadet pole, kasutatakse fallback reegleid:
    - kasutaja asukoht olemas -> `setView(user, 15)`;
    - kasutaja asukohta pole, kuid KP-d on olemas -> `fitBounds(KP-d)` + minimaalne avasuum 10;
    - puuduvad nii asukoht kui KP-d -> vaikimisi Eesti vaade (`58.8, 25.4`, zoom 8).
- Kui GPS asukoht saabub viitega pärast kaardi avamist:
  - follow-režiimis tehakse `panTo(user)` (keskpunkt uuendatakse) ilma zoomi jõuga muutmata.
- Kaardi avamine ei tohi follow-režiimi kasutaja eest sunniviisiliselt sisse lülitada ega muuta:
  - follow olek säilib kasutaja viimase valiku järgi;
  - võistluspõhise oma kaardi valik ei tohi ise muuta follow käitumist.
- Kaardil küsimuse avamine, sellele vastamine ja vastuse feedback-modali näitamine ei tohi muuta kaardi vaateolekut:
  - follow olek säilib;
  - heading/compass olek säilib;
  - aktiivne kaardikiht säilib;
  - kaart jääb samasse keskpunkti ja zoomi, kui kasutaja ise neid ei muuda.
- `CHECK_ONLY` checkpointi läbimise salvestamisel peab kaardivaates olema nähtav ajutine busy-tagasiside samal kaardiekraanil; kasutajale ei tohi jääda muljet, et klikk ei töötanud.
- Kui kaardilt klikitud KP nõuab asukohta, peab GPS/asukoha tuvastamise ajal olema samal kaardivaates nähtav ajutine busy-tagasiside; kasutajale ei tohi jääda muljet, et rakendus hangus või klikk ei registreerunud.
- Kaardil avatud küsimuse modaal ei sulgu taustaloorile vajutades; sulgemine käib ainult modali enda sulgemisnupu kaudu, et vältida tekstivastuse juhuslikku kaotust.
- Tekstivastusega küsimuse modali avamisel seatakse fookus kohe tekstiväljale, kui submit parajasti ei käi.
- Kui kaardivaate taustal töötav GPS jälgimine katkeb või GPS signaal puudub:
  - kaardivaates kuvatakse alati väike staatustekst `GPS signaal puudub` / `No GPS` samas visuaalses stiilis nagu heading debug kast;
  - kui kasutaja asukoha markerit selle võistluse jaoks kuvatakse ja viimane teadaolev asukoht on olemas, jääb marker viimasesse teadaolevasse punkti, kuid muutub halliks;
  - järgmise eduka GPS uuenduse järel staatustekst kaob ja marker taastub tavavärvi.

### 5a. Võistleja asukohamarker vs kaardi käitumine

- Kui `competition.use_location='Y'`, siis kaardivaade töötab ühtemoodi sõltumata sellest, kas `show_competitor_location='Y'` või `N`:
  - KP popupid avanevad markerile klikkides;
  - `follow`-režiim on kasutatav;
  - `Heading-up` on kasutatav;
  - asukohapõhiste KP-de avatavuse kontroll kasutab GPS-i samadel reeglitel.
- Kui `show_competitor_location='N'`, siis ainus erinevus on see, et sinist kasutaja asukohamarkerit kaardile ei joonistata.

### 5b. Võistleja võistluspõhine oma kaart

- Uploadi valideerimise eeltingimus:
  - world file põhjal arvutatud overlay boundid peavad jääma Eesti L-EST97 mõistlikku piirkonda (X `300000..800000`, Y `6300000..7000000`);
  - kui uploaditud world file viitab teise CRS-i või ilmselgelt valedele koordinaatidele, tuleb upload tagasi lükata.
- Võistleja kaardivalikusse ilmub võistluspõhine oma kaart ainult siis, kui:
  - võistlusele on osaleja jaoks lubatud kaardikiht `maaamet_pohikaart_overlay`;
  - aktiivne overlay eksisteerib;
  - overlay `processing_status = READY`;
  - süsteemis on olemas ja aktiivne aluskaart `maaamet_pohikaart`.
- Võistleja UI-s kuvatakse selline kaart nimega `* <competition_map_overlays.display_name>`.
- See valik ei ole iseseisev aluskaart, vaid komposiit:
  - aluskaart on `maaamet_pohikaart`;
  - selle peale renderdatakse võistluspõhise kaardi tile layer.
- Võistleja vaates käsitletakse overlay'd tavalise kaardikihina:
  - overlay renderdatakse EPK peale eraldi tile-layerina;
  - selle nähtavus ei tohi sõltuda kasutaja GPS asukohast, asukohamarkerist ega follow-režiimist;
  - follow-režiim tohib mõjutada ainult kaardi keskpunkti/vaate liikumist, mitte seda, kas overlay kiht on aktiivne või mitte.
- Kui osalejale lubatud kihtidesse salvestatakse `maaamet_pohikaart_overlay`, käsitletakse `maaamet_pohikaart` kihti selle tehnilise eeldusena.
- Võistleja UI-s ei kuvata eraldi overlay sisse-välja lülitit; oma kaart valitakse samast kaardivalikust nagu teised kaardid.
- Kui kaardivaate keskpunkt satub väljapoole overlay kaetud ala, jääb selles vaates nähtavale lihtsalt aluskaart `maaamet_pohikaart`, sest nendes tile-koordinaatides overlay pilte ei eksisteeri.
- Kui overlay kustutatakse või selle staatus ei ole enam `READY`, eemaldatakse `* <display_name>` võistleja kaardivalikust.
- Võistleja oma kaart kasutab alati `EPSG:3301` CRS-i.

## 6. KP klikid kaardil ja ligipääsukontroll

- KP markerile klikk avab alati kohese popupi; markeri klikk ise ei käivita enam taustal küsimuse avamise ligipääsukontrolli.
- Popupi esimene rida näitab ainult vastamise eest teenitavaid punkte ja võimalikku läbimise staatust:
  - vastamata: `Y p`;
  - vastatud: `Y p Läbitud!`.
- Popupi teine rida:
  - kui FastAPI/cache-põhine UI-eelotsus ütleb, et küsimust ei saa praeguses seisus veel vastata, kuvatakse põhjuspõhine lühisõnum tõlgetest (näiteks puuduv asukoht, liiga kaugel, START enne vajalik, vale järjekord, finish juba läbitud või küsimus puudub);
  - kui FastAPI/cache-põhine UI-eelotsus ütleb, et küsimus võib olla vastatav, kuvatakse mobiilisõbralik nupp `Vasta küsimusele.` / `Answer!`.
- Küsimuse tegelik avamise voog käivitub ainult popupi nupu vajutusel.
- Kui popupis vajutatakse `Vasta küsimusele`, avaneb küsimus kaardi peal eraldi modalis, mitte enam `index.html` küsimusteplokis.
- See modal on teadlikult lakooniline ja sisaldab ainult:
  - KP tunnust;
  - küsimust;
  - vastusevariante või tekstivälja;
  - `Saada vastus` nuppu;
  - `Sulge` nuppu.
- Kui submit õnnestub:
  - küsimuse modal sulgub;
  - olemasolev vastuse/feedback modal avaneb samuti kaardi peal.
- Kui submit ebaõnnestub:
  - küsimuse modal jääb avatuks;
  - viga kuvatakse samas modalis;
  - kasutaja saab vastust parandada või modali sulgeda.
- `location_required='N'` kaardiga KP puhul avaneb küsimuse modal ka siis, kui kasutaja ei viibi KP piirkonnas.
- Kaardiga võistlusel ei kuvata kasutajale eraldi küsimuste listi; küsimuse või läbimise tegevuse ainus sissepääs on kaardil oleva KP tähise popup.
- `is_answered` on kasutajapõhine cache-andmestik.
- FastAPI peab `is_answered` välja koostama kahe eri allika ühendamisel:
  - `competitor/competition-content` annab ainult staatilise checkpoint/question sisu ega sisalda participant-specific `is_answered` välju;
  - `competitor/checkpoint-state` annab ainult answered checkpoint id-de loendi kujul `{"items":[{"checkpoint_id":...}, ...]}`.
- Need on eri semantikaga payloadid ja neid ei tohi sama reegliga parsida:
  - `map-checkpoints` / `open-checkpoints` vahepayloadis võib `is_answered` välja juba olla ja sealt võib answered-seisu lugeda ainult `is_answered = 'Y'` järgi;
  - ORDS `checkpoint-state` vastuses answered-seis tuleb lugeda ainult `checkpoint_id` olemasolu järgi, sest seal `is_answered` välja ei ole.
- Kui need kaks tõlgendust segi lähevad, tekivad kaardipopupi äriloogikas valed eelotsused:
  - kasutajale võidakse valesti näidata `START tuleb enne läbida`, kuigi `START` on DB järgi läbitud;
  - või valesti `FINISH juba läbitud`, kuigi `FINISH` kirjet DB-s ei ole.
- Seetõttu peavad popupi nupu nähtavuse eelotsus ja popupi nupu vajutuse järel tehtav backend kontroll tuginema samale participant-state tõele.
- Cache võib olla pika TTL-iga, kuid staatus värskendatakse sündmuspõhiselt:
  - pärast edukat vastuse saatmist (`submit`) uuendatakse kasutaja KP staatus;
  - kui kasutaja avab `Tulemused` (`Kuva tulemused`), värskendatakse kasutaja kaardi KP staatus.
- Kaardipopupi nupu nähtavus ei tohi teha eraldi `open-checkpoints` masspäringut; see otsus peab tuginema olemasolevale `map-checkpoints` cache'ile ja viimasele teadaolevale kasutaja asukohale.
- Kaardipopupi sisu ei tohi GPS uuendusel kõigi KP-de jaoks igal sammul ümber renderdada; GPS muutuse järel värskendatakse ainult parajasti avatud popupide sisu.
- `location_required='N'` KP puhul võib küsimus avaneda kohe.
- Kui `checkpoint_interaction='CHECK_ONLY'`, siis küsimuse modali ei avata:
  - kasutaja vajutab tegevusnuppu KP popupis;
  - läbimine registreeritakse kohe `submissions` voo kaudu;
  - edukal juhul avaneb olemasolev feedback modal kaardi peal.
- `map-checkpoints` peab asukohanõudega KP-de puhul tagastama iga KP kohta efektiivse vastamisraadiuse:
  - kui `checkpoints.radius_m` on määratud, kasutatakse seda;
  - muidu kasutatakse `competitions.radius_m`;
  - kui kumbki puudub, tagastatakse `radius_m` väärtusena `0`.
- `location_required='Y'` KP puhul tehakse taustal ligipääsukontroll:
  - popupi nupu nähtavuse eelotsuse teeb FastAPI/cache-põhine loogika ilma täiendava ORDS päringuta;
  - frontend saadab geolokatsiooni FastAPI-le alles siis, kui kasutaja vajutab popupi vastamise nuppu;
  - FastAPI teeb eelkontrolli ja tavapärase open-listi koostamise lokaalselt (distants + participant-state + staatiline payload);
  - FastAPI küsib ORDS-ist ainult siis, kui lokaalset otsust ei saa teha olemasoleva metadata põhjal.
- Tavapärases voos ei vaja küsimuse avatavuse lõplik otsus enam eraldi ORDS roundtrip'i; autoriteetne lõplik ärikontroll jääb `submissions` teenusele.
- Kui aktiivne `START` on olemas ja seda pole veel läbitud, siis enne `START` läbimist ei avata ühtegi muud KP-d.
- Sellises seisus võib `open-checkpoints` tagastada ainult `START` kontrollpunkti.
- Kui aktiivne `START` kasutab `MASS_START` interaktsiooni, loetakse START avatuks alates `competitions.mass_start_at` hetkest ilma käsitsi vastuseta.
- Kui `competition.type='S'` ja `START` on juba läbitud, siis:
  - kaardil kuvatakse kogu rada kohe algusest peale (`START`, kõik `NORMAL` KP-d, `FINISH`);
  - vastamiseks avatakse korraga ainult üks järgmine `NORMAL` KP vastavalt `order_no` järjestusele;
  - kui kõik `NORMAL` KP-d on läbitud, võib avatuks jääda ainult `FINISH`.
- Kui `competition.type='R'`, siis pärast võimaliku `START` läbimist võivad kõik vastamata KP-d olla avatavad tavapäraste asukoha- ja staatusereeglite järgi.
- Kui aktiivne `FINISH` on läbitud, siis pärast seda ei tagastata enam ühtegi vastatavat KP-d sõltumata asukohast või muust varasemast avatavusest.
- See tähendab ka äärmusjuhtu: `R` tüüpi võistlusel võib võistleja läbida `START` ja seejärel kohe `FINISH`, mille järel rohkem KP-sid enam vastata ei saa.

## 7. `Info` nupu käitumine kaardis

- `Info` nupp avab/sulgeb KP popupid.
- `Info` nupp ei tee popupide avamisel `open-checkpoints` bulk-ligipääsukontrolli.
- Popupide sisu kasutab sama FastAPI/cache-põhist UI-eelotsust nagu üksiku KP klikk.
- Lõplik ligipääsukontroll tehakse alles siis, kui kasutaja vajutab konkreetse KP popupis vastamise nuppu.

## 7a. Kaardi suuna (`Heading-up`) reeglid

- `Heading-up` nupp kuvatakse siis, kui `use_location='Y'`.
- Kui `Heading-up` on välja lülitatud, kaart jääb `north-up` režiimi (põhi üleval).
- Kui `Heading-up` on sisse lülitatud, kaardi pööramine kasutab hübriidset allikaloogikat:
  - `COMPASS_ONLY`: kasutatakse kompassi suunda (koos jooksva bias-korrektsiooniga).
  - `BLEND`: kompassi ja GPS suuna kaalutud segu.
  - `GPS_PRIMARY`: kasutatakse GPS liikumissuunda.

State machine (kiirusepõhine):

1. `COMPASS_ONLY`
  - GPS suund pole usaldusväärne või kiirus on madal.
2. `BLEND`
  - GPS suund hakkab osalema juba alates kiirusest `0.7 m/s` (varajane blend), kui GPS headingu kvaliteet on piisav.
  - Täiskaaluga GPS usaldamine algab alates `1.0 m/s`.
3. `GPS_PRIMARY`
  - GPS suund on usaldusväärne ja kiirus on vähemalt `1.5 m/s` (stabiilselt järjest).

GPS suuna usaldusväärsuse tingimused:

- GPS heading (`coords.heading`) olemas;
- kiirus vähemalt `1.0 m/s`;
- asukoha täpsus (`accuracy_m`) piisav (kuni `25 m`).

Kompassi bias-korrektsioon:

- Kui süsteem on `BLEND` või `GPS_PRIMARY` režiimis, korrigeeritakse kompassi bias't aeglaselt GPS suuna suhtes.
- Bias korrigeerimine on piiratud (clamp), et vältida liiga agressiivset triivi.
- Eesmärk on vähendada seadmetevahelist püsivat suunanihket ning hoida madala kiiruse korral kompassisuund stabiilsem.
- Bias salvestatakse lokaalselt seadmesse/võistlusesse, et järgmine kaardi avamine ei alustaks alati null-kalibreeringust.

Värina vähendamise reegel:

- Kaardi bearingut ei uuendata iga sensorisammu peal.
- Rakendatakse:
  - nurga silumine (`low-pass`),
  - minimaalne muutuse lävi (`deadzone`),
  - minimaalne ajaintervall bearingu uuenduste vahel.

Täpsustus:

- Kompassirežiimis kasutatakse rakenduse sisest suuna offsetit (`MAP_HEADING_OFFSET_DEG`), mille vaikeväärtus on `0` (st lisanihet ei rakendata).

## 7b. Magnetiline deklinatsioon

- Magnetiline deklinatsioon salvestatakse võistlusepõhise abiväärtusena eraldi tabelis `competition_declinations`.
- Väärtus tuletatakse võistluse KP-de geokoordinaatide keskmisest, mis toimib võistluse ala keskpunkti ligikaudse referentsina.
- Kui deklinatsioon puudub, käsitletakse seda rakenduses väärtusena `0`.
- Deklinatsioon on allkirjastatud kraadides, kus positiivne väärtus tähendab idapoolset korrektsiooni (`east`) ja negatiivne väärtus läänepoolset korrektsiooni (`west`).
- Frontendis rakendatakse see kompassi korrektsioonina otse kujul `true_heading = magnetic_heading + declination`.
- Kui võistlus on `ACTIVE` ja kasutab kaarti, siis backend käivitab deklinatsiooni värskendamise asünkroonselt pärast võistluse meta- või KP-andmete muutmist.
- Värskendust ei tehta tihedamalt kui `.env` failis määratud päevade intervall.
- Kui olemasolev väärtus puudub või on aegunud, proovitakse värskendust alati, kui kaart on kasutusel.
- Kui värskendus ebaõnnestub või aegub, ei tohi see võistluse salvestamist ega KP muutmist takistada.

## 8. Vastuse salvestamine

- Võistleja asukoht vastamise hetkel salvestatakse `submissions` kirjele:
  - `latitude`
  - `longitude`
  - `accuracy_m` (kui olemas)
- Uut eraldi asukohatabelit ei looda.

## 9. Raadiuse arvutamise reegel

KP efektiivne raadius:

1. kui `checkpoints.radius_m` on määratud, kasutatakse seda;
2. muidu kasutatakse `competitions.radius_m`.

## 10. Liitumise ja aktiivsuse reeglid (võistleja)

Koodiga liituda saab ainult võistlusega, mis on:

- `status='ACTIVE'`;
- `starts_at <= nüüd`;
- `ends_at IS NULL` või `ends_at > nüüd`;
- mitte soft-deleted (`end_date IS NULL`).

Vale, aegunud, mitteaktiivne või kustutatud võistluse kood annab kasutajale sama üldise teate (detaili ei avaldata).

## 10a. Tulemuste vaate automaatvärskendus

- `results.html` automaatvärskendus on lubatud ainult siis, kui lehe avamisel laaditud võistluse overview järgi:
  - `status='ACTIVE'`;
  - `starts_at <= now`;
  - `ends_at IS NULL` või `now < ends_at`.
- Kui need tingimused on lehe avamisel täidetud, kestab automaatvärskendus maksimaalselt 1 tund alates lehe avamisest.
- Lehe käsitsi refresh alustab uue 1 tunni akna.
- Teadlik ärireegel:
  - kui tulemuste leht avatakse enne võistluse algust, siis automaatvärskendus ei aktiveeru ise hiljem võistluse algushetkel;
  - kasutaja peab sellisel juhul lehe käsitsi värskendama.

## 11. Soft delete põhimõte API vastustes

- ORDS teenused ei tagasta vaikimisi soft-deleted kirjeid.
- Kui tulevikus on vaja kustutatud kirjeid näidata, tehakse selleks eraldi teenus.

## 12. Admin UI käitumine (kokkulepitud)

- Asukohaandmete muutmine toimub võistluse ühisest “Muuda võistlust” vormist.
- Osaleja kaartide valiku dialoog ei tohi näidata ühtegi kaarti vaikimisi valituna ainult `map_layers.json` participant-default alusel, kui `competition_participant_map_layers` tabelis selle võistluse kohta aktiivset kirjet ei ole.
- Uuel võistlusel on kõik osaleja kaardid valimata, kuni admin need päriselt salvestab.
- Reegel `vähemalt üks kaart peab olema valitud` kehtib ainult siis, kui võistlus on ühtaegu:
  - `use_location = 'Y'`;
  - `status = 'ACTIVE'`.
- Kui aktiivsel kaardiga võistlusel proovitakse salvestada tühja osaleja kaardivalikut, peab admin UI selle blokeerima ja nõudma vähemalt ühe kaardi valimist.
- Kui võistlus viiakse `ACTIVE` staatusesse olukorras, kus `use_location = 'Y'`, peab süsteem enne aktiveerimist kontrollima, et `competition_participant_map_layers` sisaldab vähemalt üht aktiivset kaarti; vastasel juhul tuleb aktiveerimine blokeerida.
- KP muutmisaknas:
  - kaart kuvatakse ainult siis, kui `use_location='Y'`;
  - KP raadius mõjutab kaardil kuvatavat ringi;
  - kui KP-l raadius puudub, kasutatakse võistluse vaikeraadiust.
- Uue KP loomisel tsentreeritakse kaart viimati sisestatud KP asukohale (sama võistluse piires), et vältida iga kord nullist suumimist.

### 12a. Admin kaardireeglid S-tüübi korral

Rakendub kahele kaardile:
- “Näita kaardil” modal.
- “Uus KP / Muuda KP” modali “Olemasolevad KP-d” kaardikiht.

Reeglid:
- Kui `competition.type='S'`:
  - KP järjekorranumber kuvatakse kaardil iga KP tähise juures.
  - KP lisamise/muutmise modali “Olemasolevad KP-d” kaardikihis ühendatakse KP-d `order_no ASC` järgi.
  - “Näita kaardil” modalis joonistatakse `S` tüübi ühendusjoon automaatselt `order_no ASC` järgi kohe modali avamisel.
  - `S` tüübi “Näita kaardil” modalis eraldi “Kuva järjekord” / “Peida järjekord” nuppu ei kuvata.
  - Mõlemas vaates võetakse ühendusjoone värv segmendi siht-KP tähise värvist (punane/lilla).
  - Mõlemas vaates võrdub joone paksus KP tähise joone paksusega.
  - “Näita kaardil” modali route-järjekorra joon kasutab sama visuaalset loogikat nagu võistleja `S`-tüübi rajal:
    - õhuke valge halo;
    - joon lõpeb enne KP tähist;
    - lõikuvate segmentide katkestused.

### 12aa. Admin “Näita kaardil” route snapshoti reeglid

- Modali allservas kuvatakse salvestatud raja linnulennuline pikkus:
  - `S` puhul tekst kujul `Raja linnulennuline pikkus xx.xx km`;
  - `R` puhul tekst kujul `Raja linnulennuline pikkus (optimaalne tee läbi kõikide KP-de) xx.xx km`.
- Kui route snapshot puudub, kuvatakse sama tekst edasi, kuid pikkuse väärtuse asemel kuvatakse `-`.
- Kui route snapshoti `calculated_source_hash` ei klapi jooksva hashiga:
  - viimane teadaolev pikkus jääb adminis nähtavaks;
  - läbikriipsutatuna kuvatakse ainult pikkuse arvuline väärtus, mitte kogu tekst;
  - sama rea lõppu lisatakse märkus `rada on muutunud`.
- Admin võib route arvutuse käsitsi tellida ainult sellest modali vaatest:
  - `R` võistlusel tekitab nupp tellimuse (`PENDING`);
  - `S` võistlusel arvutatakse tulemus kohe välja.
- Kui route staatus on `PENDING` või `PROCESSING`, ei saa admin uut arvutust samast vaatest tellida.
- Route staatuseikoon kuvatakse route-teksti samal real enne abiinfot (`i`):
  - `PENDING` = punktikujuline indikaator;
  - `PROCESSING` = spinner-tüüpi indikaator.
- `R` tüübil kuvatakse “Kuva järjekord” / “Peida järjekord” nupp ainult siis, kui route snapshotis on salvestatud KP järjekord.
- “Kuva järjekord” võib olla adminis nähtav ka siis, kui snapshot on aegunud; sel juhul näitab kaart viimast teadaolevat arvutusjärjekorda.
- Modali sulgemine ja uuesti avamine peab route snapshoti backendist värskelt uuesti laadima.
  - juba avatud modal ei pea ennast jooksvalt ise värskendama.

### 12b. Võistleja kaardireeglid S-tüübi korral

- Võistleja kaardil kehtib `S` tüüpi võistlusel sama visuaalne rajaloogika nagu admin kaardil:
  - `START` kuvatakse kolmnurgana;
  - `FINISH` kuvatakse topeltringina;
  - `NORMAL` KP-de kõrval kuvatakse tekst kujul `order_no - title`, sama värviloogikaga nagu markeritel;
  - `title` osa lõigatakse maksimaalselt 5 märgini ja `S` tüübil ellipsit ei lisata;
  - KP-d ühendatakse `order_no ASC` järgi;
  - ühendusjoontele lisatakse õhuke valge halo, et rada eristuks paremini taustast;
  - joone ristumiste katkestused, markerite lähedusest tulenev joone kärpimine ja numbrilabelite paigutus peavad järgima sama reeglit nagu admin kaardivaadetes.
  - Joon lõpeb enne KP tähist (offset), et joon ei puutuks tähise rõngast.
- Võistleja kaardil `R` tüüpi võistlusel:
  - `START` kuvatakse kolmnurgana;
  - `FINISH` kuvatakse topeltringina;
  - `NORMAL` KP-de kõrval kuvatakse `title` sama värviloogikaga nagu markeritel;
  - kui `title` pikkus on kuni 8 märki, kuvatakse kogu `title`;
  - kui `title` pikkus on üle 8 märgi, kuvatakse esimesed 5 märki ja `...`;
  - vaikimisi paigutatakse label markerist üles-poole-paremale ehk ligikaudu "kella 1 peale";
  - kui label satub liiga lähedale teise KP tähisele või juba paigutatud teisele labelile, proovib UI alternatiivseid asukohti;
  - markeritele ja labeli tekstile lisatakse õhuke valge halo parema loetavuse jaoks;
  - ühendusjooni ei kuvata.

START / FINISH täpsustus:
- `START` kuvatakse kaardil ainult sümbolina, ilma lisatekstita.
- `FINISH` kuvatakse kaardil ainult sümbolina, ilma lisatekstita.
- `START` sümbol on võrdkülgne kolmnurk.
- `FINISH` sümbol on topeltring.
- `FINISH` topeltringi sisemine ring vastab tavalise KP tähise mõõdule ja välimine ring on sama keskpunktiga sellest suurem.
- Võistleja kaardil lisatakse KP sümbolitele ja kaarditekstidele visuaalne valge kontuur, mitte taustakast.

Lõikumise reegel:
- Kui kaks ühendussegmenti lõikuvad, siis väiksema `order_no` segmendile tehakse lõikekohas katkestus.
- Suurema `order_no` segment jääb terveks.
- Katkestuse suurus on ligikaudu 20 px (10 px kummalegi poole lõikepunkti).

Esmarenderduse reegel (“Näita kaardil”):
- Numbrilabelite dünaamiline paigutus arvutatakse pärast kaardi vaate paigaseadmist (`setView`/`fitBounds`) ja `invalidateSize()` etappi.
- See väldib olukorda, kus labeli asukoht on modali avamisel vale, kuid zoomimisel läheb õigeks.

### 12c. Admin kaardivaadete markerid ja KP-info

- Admini kaardivaated (`Näita kaardil` ja KP lisamise/muutmise dialoogi kaart) kasutavad sama KP sümboolika loogikat nagu võistleja kaart:
  - `START` kuvatakse kolmnurgana;
  - `FINISH` kuvatakse topeltringina;
  - `NORMAL` KP kuvatakse rõngana.
- Kõigile admini kaardivaadete KP sümbolitele lisatakse õhuke valge halo parema loetavuse jaoks.
- Kui admin vaates joonistatakse ühendusjooni (`S` järjekorrakiht KP-dialoogis või route snapshot “Näita kaardil” modalis), lisatakse neile õhuke valge halo.
- Admini kaart ei kuva KP `title`-eid otse markerite kõrval täiendavate kaardilabelitena; detailsem KP-info kuvatakse popupis.
- Admini KP popup jääb tahtlikult kitsaks ning kasutab maksimaalselt kompaktset kolme rea loogikat:
  - esimene rida: senine KP pealkiri ja võimalik raadius;
  - teine rida: küsimuse tekst koos küsimusetüübi lühivormiga ja punktidega kujul `(... T/SC x / y)`;
  - kolmas rida: `TEXT` küsimusel õiged vastused, `SINGLE_CHOICE` küsimusel variandid ning õiged variandid boldis.
- Võistleja raja pikkuse kokkuvõtte lisareegel:
  - avalehel võib eraldi raja pikkuse plokki kuvada ainult kaardiga võistlusel (`competitions.use_location = 'Y'`) ja ainult siis, kui FastAPI jätab `competitor/map-checkpoints` cache-vastuses `route` objekti alles;
  - `S` tüübil kuvatakse tekst kujul `Raja linnulennuline pikkus xx.xx km`;
  - `R` tüübil kuvatakse tekst kujul `Raja linnulennuline pikkus (optimaalne tee läbi kõikide KP-de) xx.xx km`;
  - võistlejale ei kuvata aegunud snapshoti ega hash-mismatch infot: kui hash ei klapi, eemaldab FastAPI `route` välja payloadist ja frontend peidab kogu ploki;
  - selle info kuvamine ei tohi lisada täiendavaid ORDS päringuid, vaid peab kasutama sama `map-checkpoints` cache-payloadi.
