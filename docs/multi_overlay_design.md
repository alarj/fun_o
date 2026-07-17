# Mitme overlay disainiidee

## Eesmärk

Selle dokumendi eesmärk on kirjeldada võimalikku edasiarendust, kus ühe võistluse `O-kaart` võib koosneda mitmest raster-overlay kihist korraga, säilitades samal ajal olemasoleva lihtsa kasutusmudeli nii võistleja kui admini jaoks.

See dokument on arendusidee kirjeldus, mitte tänase tootmiskäitumise tõeallikas. Kehtiv MVP käitumine on jätkuvalt kirjeldatud dokumentides `docs/erd.md`, `docs/location_rules.md`, `docs/system_architecture.md` ja `backend/README.md`.

## Taust

Praeguses MVP-s:

- `competition_participant_map_layers` määrab, millised kaarditüübid on osalejale lubatud;
- `maaamet_pohikaart_overlay` on üks loogiline kaardivalik;
- ühe võistluse kohta on lubatud maksimaalselt üks aktiivne raster-overlay;
- võistleja valikus kuvatakse overlay ühe tärniga komposiitkaardina EPK aluskaardi peal.

Äriline vajadus on lubada ühe võistluse `O-kaardi` taha mitu kitsast või osaliselt kattuvat rasterit. Tüüpiline näide on pikk rannajoon või muu ala, kus mitu kitsast kaardiriba on praktilisemad kui üks väga suur raster.

## Põhireegel

- Võistleja ja admini kaardivalikus jääb alles üks loogiline valik: `O-kaart`.
- `O-kaart` ei tähenda tulevikus enam tingimata ühte raster-overlayd, vaid ühe võistluse kogu overlay-stacki.
- Ühe võistluse sees ei toetata mitut eri overlay-komplekti.
- `competition_participant_map_layers` jääb äriliselt samaks: osalejale lubatud kaarditüüp on jätkuvalt `maaamet_pohikaart_overlay`.

## Ärireeglid

### 1. Uue overlay loomine

- Admin saab overlay lisada endiselt admini liidesest.
- Overlay lisamine jääb voona võimalikult samaks nagu täna.
- Uue overlay loomisel lisandub kohustuslik `public/private` valik.
- Vaikimisi väärtus on `public`.
- `private` tähendab, et overlay on mõeldud kasutamiseks ainult sellel võistlusel, mille kontekstis see loodi.
- `public` tähendab, et overlay lisatakse üldisesse valikupooli ja seda saab hiljem siduda ka teiste võistlustega.

### 2. Mitu overlayd ühele võistlusele

- Admin peab saama lisada ühele võistlusele mitu overlayd.
- Lisamine toimub ükshaaval, mitte mitme faili korraga üleslaadimisena.
- Võistluse `O-kaart` võib seega koosneda mitmest kihist.

### 3. Olemasoleva overlay kasutamine

- Lisaks uue overlay loomisele peab admin saama valida olemasolevate `public` overlayde seast sobivaid kihte.
- Valik peab olema võimalik vähemalt:
  - nimekirjast;
  - Eesti põhikaardil overlay ala peale klikkides.
- `private` overlayd ei lisata üldisesse overlay-pooli.

### 4. Kihtide järjestus

- Kui overlayd kattuvad, peab admin saama määrata nende kuvamise järjekorra.
- Vaikimisi on järjekord lisamise järjekord.
- Järjestus on võistlusepõhine omadus, mitte overlay enda globaalne omadus.
- Sama `public` overlay võib eri võistlustel olla erinevas kihijärjekorras.

### 5. Võistleja vaade

- Võistleja kaardivalikusse ei teki mitu eraldi overlay-valikut.
- Võistleja näeb jätkuvalt ühte tärniga lisavalikut, näiteks `* O-kaart`.
- Selle valiku aktiveerimisel renderdatakse kõik sellele võistlusele lubatud overlay-kihid korraga EPK aluskaardi peale.
- Kui mõne overlay ulatusest väljas tile'e ei ole, jääb selles piirkonnas nähtavale ainult aluskaart, nagu ka tänases lahenduses.

## Soovitatav andmemudeli suund

Praegune mudel, kus `competition_map_overlays` kirjeldab sisuliselt ühe võistluse ühte aktiivset overlayd, ei ole mitme võistluse ja mitme overlay kasutusjuhtumi jaoks piisavalt paindlik.

Soovitatav sihtmudel:

- `map_overlays`
  - overlay kui taaskasutatav objekt;
  - sisaldab nime, attributionit, failide/meta andmeid, mõõte, boundse, töötlusolekut ja `public/private` omadust.

- `competition_map_overlays`
  - seostabel võistluse ja overlay vahel;
  - sisaldab vähemalt `competition_id`, `map_overlay_id` ja võistlusepõhist kihijärjekorda;
  - kirjeldab, millised overlayd kuuluvad selle võistluse `O-kaardi` stacki.

Selle lahenduse eelised:

- toetab suhet `1 võistlus -> mitu overlayd`;
- toetab suhet `1 overlay -> mitu võistlust`;
- väldib sama rasteri failide ja metadata dubleerimist;
- hoiab võistleja kasutusmudeli lihtsana.

## Mida ei muudeta

- `competition_participant_map_layers` semantika ei muutu.
- Võistlusele lubatud kaarditüüpide valikus jääb overlay jaoks alles üks loogiline kirje: `maaamet_pohikaart_overlay`.
- Overlayd jäävad vähemalt esialgu ainult Eesti põhikaardi (`maaamet_pohikaart`) peale.
- Võistleja jaoks ei tekitata mitut eri overlay-komplekti ega eraldi overlay lüliteid.

## Admin UI soovituslik suund

Admini jaoks võiks overlay haldus olla ühe võistluse sees käsitletav kui `O-kaardi kihid`.

Soovitatavad tegevused:

- `Lisa uus overlay`
- `Vali olemasolev overlay`
- `Muuda järjekorda`
- `Eemalda võistluselt`

Kui overlay on loodud konkreetse võistluse kontekstis ja ei ole mujale seotud, võib hiljem kaaluda ka selle täielikku kustutamist, kuid see ei ole käesoleva disaini põhinõue.

## Competitor ja admin kaardikäitumise mõju

- Frontend peab käsitlema `maaamet_pohikaart_overlay` valikut ühe komposiitkihina, mille taga võib olla mitu tile-overlayd.
- Renderdus peab arvestama etteantud kihijärjekorda.
- Admini kaardivaade ja võistleja kaardivaade peavad kasutama sama järjestusloogikat.
- GPS, follow-režiim ja asukohamarker ei tohi overlay-stacki nähtavuse loogikat mõjutada rohkem kui tänases lahenduses.

## Avatud otsused

Enne realiseerimist tuleb täpsustada vähemalt järgmised punktid:

- kas `public/private` väärtus on pärast loomist muudetav või mitte;
- kas `public` overlay omanikuks jääb ainult looja või võib seda hallata ka superadmin;
- kas üldise overlay-pooli vaates on vaja otsingut, filtreid või olekuid;
- kas sama võistluse stackis peab kihijärjekord olema unikaalne ja järjestikune või piisab tavalisest sorteerimisväljast.

## Soovitus dokumentatsiooni evolutsiooniks

Kui see idee realiseeritakse, tuleb uuendada vähemalt järgmisi dokumente:

- `docs/erd.md`
- `docs/location_rules.md`
- `docs/system_architecture.md`
- `backend/README.md`

Kuni realiseerimiseni jääb see dokument arendusidee kirjelduseks.
