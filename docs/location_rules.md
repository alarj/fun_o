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
- `checkpoints.radius_m` (number, meetrites, nullable)
  - KP-spetsiifiline raadius. Kui puudub, kasutatakse `competitions.radius_m`.
- `checkpoints.location_required` (`Y`/`N`)
  - Kas selle KP vastuse juures on asukoht kohustuslik.
  - Admin UI-s muudetav ainult siis, kui võistlusel `use_location='Y'`.

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
  - GPS suund on usaldusväärne ja kiirus on vähemalt `1.0 m/s`.
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

Värina vähendamise reegel:

- Kaardi bearingut ei uuendata iga sensorisammu peal.
- Rakendatakse:
  - nurga silumine (`low-pass`),
  - minimaalne muutuse lävi (`deadzone`),
  - minimaalne ajaintervall bearingu uuenduste vahel.

Täpsustus:

- Kompassirežiimis kasutatakse rakenduse sisest suuna offsetit (`MAP_HEADING_OFFSET_DEG`), et heading vastaks praktilisele kasutuskogemusele erinevates seadmetes.

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
  - Joon lõpeb enne KP tähist (offset), et joon ei puutuks tähise rõngast.
- Kui `competition.type!='S'`:
  - järjekorranumbreid ega ühendusjooni ei kuvata.

Lõikumise reegel:
- Kui kaks ühendussegmenti lõikuvad, siis väiksema `order_no` segmendile tehakse lõikekohas katkestus.
- Suurema `order_no` segment jääb terveks.
- Katkestuse suurus on ligikaudu 20 px (10 px kummalegi poole lõikepunkti).

Esmarenderduse reegel (“Näita kaardil”):
- Numbrilabelite dünaamiline paigutus arvutatakse pärast kaardi vaate paigaseadmist (`setView`/`fitBounds`) ja `invalidateSize()` etappi.
- See väldib olukorda, kus labeli asukoht on modali avamisel vale, kuid zoomimisel läheb õigeks.
