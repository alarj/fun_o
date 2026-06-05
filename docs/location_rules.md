# Asukohareeglid (location rules)

See dokument kirjeldab kokkulepitud ärireegleid, kuidas asukohaandmeid kasutatakse võistlustel, kontrollpunktidel (KP) ja võistleja vaates.

## 1. Võistluse taseme parameetrid

- `competitions.use_location` (`Y`/`N`)
  - Määrab, kas võistlus kasutab asukohaloogikat üldse.
- `competitions.radius_m` (number, meetrites)
  - Vaikimisi kauguslävi, mida kasutatakse KP-de puhul, kui KP-l eraldi raadiust pole määratud.
- `competitions.show_competitor_location` (`Y`/`N`)
  - Määrab, kas võistleja asukohta kuvatakse kaardil ja kas kaardivaates kasutatakse jälgimisrežiimi.

## 2. Kontrollpunkti taseme parameetrid

- `checkpoints.latitude`, `checkpoints.longitude`
  - KP geokoordinaadid (WGS84).
- `checkpoints.checkpoint_type`
  - KP liik: `NORMAL`, `START`, `FINISH`.
  - Kui väärtus on `NULL`, käsitletakse seda äriloogikas kui `NORMAL`.
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
- `START` pealkiri on alati `START`.
- `FINISH` pealkiri on alati `FINISH`.
- `START` ja `FINISH` tüüpi olemasolevat KP-d ei saa adminis muuta teiseks liigiks.
- Ka tavalist `NORMAL` KP-d ei muudeta edit-vaates `START` või `FINISH` tüübiks.
- `START.order_no = 0`.
- `FINISH.order_no = 9999`.
- See `order_no` reegel kehtib nii `R` kui `S` tüüpi võistlustel.
- Admin kasutaja ei sisesta ega muuda `START`/`FINISH` `order_no` väärtust käsitsi.

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
- Kui kaardivaate taustal töötav GPS jälgimine katkeb või GPS signaal puudub:
  - kaardivaates kuvatakse alati väike staatustekst `GPS signaal puudub` / `No GPS` samas visuaalses stiilis nagu heading debug kast;
  - kui kasutaja asukoha markerit selle võistluse jaoks kuvatakse ja viimane teadaolev asukoht on olemas, jääb marker viimasesse teadaolevasse punkti, kuid muutub halliks;
  - järgmise eduka GPS uuenduse järel staatustekst kaob ja marker taastub tavavärvi.

## 6. KP klikid kaardil ja ligipääsukontroll

- KP markerile klikk kuvab koheselt popupi tekstiga:
  - vastamata: `KP XX (Y p)`;
  - vastatud: `KP XX (Y p) Läbitud!`.
- `is_answered` on kasutajapõhine cache-andmestik.
- Cache võib olla pika TTL-iga, kuid staatus värskendatakse sündmuspõhiselt:
  - pärast edukat vastuse saatmist (`submit`) uuendatakse kasutaja KP staatus;
  - kui kasutaja avab `Tulemused` (`Kuva tulemused`), värskendatakse kasutaja kaardi KP staatus.
- `location_required='N'` KP puhul võib küsimus avaneda kohe.
- `location_required='Y'` KP puhul tehakse taustal ligipääsukontroll:
  - frontend saadab geolokatsiooni FastAPI-le;
  - FastAPI teeb eelkontrolli (distants + cache-põhine filter);
  - FastAPI küsib ORDS-ist lõpliku avatavuse ainult kandidaatide jaoks.
- Lõplik otsus “kas küsimus on vastamiseks avatud” tuleb ORDS-ist, mitte ainult cache’ist.
- Kui aktiivne `START` on olemas ja seda pole veel läbitud, siis enne `START` läbimist ei avata ühtegi muud KP-d.
- Sellises seisus võib `open-checkpoints` tagastada ainult `START` kontrollpunkti.
- Kui `competition.type='S'` ja `START` on juba läbitud, siis:
  - kaardil kuvatakse kogu rada kohe algusest peale (`START`, kõik `NORMAL` KP-d, `FINISH`);
  - vastamiseks avatakse korraga ainult üks järgmine `NORMAL` KP vastavalt `order_no` järjestusele;
  - kui kõik `NORMAL` KP-d on läbitud, võib avatuks jääda ainult `FINISH`.
- Kui `competition.type='R'`, siis pärast võimaliku `START` läbimist võivad kõik vastamata KP-d olla avatavad tavapäraste asukoha- ja staatusereeglite järgi.
- Kui aktiivne `FINISH` on läbitud, siis pärast seda ei tagastata enam ühtegi vastatavat KP-d sõltumata asukohast või muust varasemast avatavusest.
- See tähendab ka äärmusjuhtu: `R` tüüpi võistlusel võib võistleja läbida `START` ja seejärel kohe `FINISH`, mille järel rohkem KP-sid enam vastata ei saa.

## 7. `Info` nupu käitumine kaardis

- `Info` nupp avab/sulgeb KP popupid.
- Kui popupid avatakse, võib süsteem samal ajal teha taustal bulk-ligipääsukontrolli asukohanõudega KP-dele:
  - FastAPI filtreerib kandidaadid;
  - ORDS-i pöördutakse ainult kandidaatide kinnitamiseks.

## 7a. Kaardi suuna (`Heading-up`) reeglid

- `Heading-up` nupp kuvatakse ainult siis, kui `show_competitor_location='Y'`.
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

## 11. Soft delete põhimõte API vastustes

- ORDS teenused ei tagasta vaikimisi soft-deleted kirjeid.
- Kui tulevikus on vaja kustutatud kirjeid näidata, tehakse selleks eraldi teenus.

## 12. Admin UI käitumine (kokkulepitud)

- Asukohaandmete muutmine toimub võistluse ühisest “Muuda võistlust” vormist.
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
  - KP-d ühendatakse `order_no ASC` järgi.
  - Ühendusjoone värv võetakse segmendi siht-KP tähise värvist (punane/lilla).
  - Joone paksus võrdub KP tähise joone paksusega.

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
