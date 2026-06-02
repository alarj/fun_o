# VĆµistleja liitumise reeglid

## EesmĆ¤rk

See dokument koondab vĆµistleja liitumise ja vĆµistluse nĆ¤htavuse reeglid:
- Ć¤riline vaade (kasutajajuhendi alus)
- tehniline vaade (andmemudel, cookieā€™d, backendi kontrollid)

## A. Ć„riline tase

### 1) Liitumine

- VĆµistleja saab liituda vĆµistlusega koodi alusel.
- Liitumise kanalid:
  - URL-is sisalduv vĆµistleja kood (nt QR)
  - kĆ¤sitsi sisestatud kood avalehel
- Kui kasutajal on kehtiv osaluscookie + DB-s sellele vastav aktiivne osalus, avatakse kohe sama vĆµistlus.
- Liitumine loetakse lĆµppenuks alles siis, kui kasutaja:
  - sisestab aliase
  - nĆµustub kasutustingimustega
  - (soovi korral) sisestab e-posti

### 2) Alias

- Alias on kohustuslik.
- Alias peab olema sama vĆµistluse piires unikaalne.
- Aliaside vĆµrdlus on case-insensitive (`karu`, `KARU`, `KaRu` on sama), kuid tĆ¤hekuju sĆ¤ilib kuvamiseks.
- Erinevad sĆµned ja tĆ¼hikute variandid on erinevad (`jĆ¤Ć¤karu` != `jĆ¤Ć¤ karu`).

### 3) E-post

- E-post on valikuline.
- Kui sisestatakse, peab olema e-posti kujuline (`x@y.z` tasemel kontroll).
- E-posti unikaalsust ei kontrollita.

### 4) Kasutustingimused

- NĆµustumine on kohustuslik.
- Tingimused on vĆµistlusepĆµhised ja mitmekeelsed.
- Admini tehtud muudatused peavad sĆ¤ilima.
- Vaikimisi tingimused loetakse failist ainult siis, kui tabelis puuduvad.

### 5) VĆµistluse olekud vĆµistleja vaates

- `DRAFT`
  - vĆµistleja ei nĆ¤e
  - liituda ei saa
  - kui cookie viitab sellele, suunatakse liitumisvoogu

- `INACTIVE`
  - liituda saab
  - vĆµistluse sisu (kaart, KP-d, kĆ¼simused) ei nĆ¤idata
  - vastuseid esitada ei saa

- `ACTIVE` ja aeg vahemikus `starts_at <= now < ends_at`
  - liituda saab
  - sisu kuvatakse
  - vastuseid saab esitada

- `ACTIVE`, aga aeg vĆ¤ljas vahemikku
  - liituda saab
  - sisu kuvatakse ainult vaatamiseks
  - vastuseid esitada ei saa

### 6) Sessioon ja taastamine

- EesmĆ¤rk: kasutaja jĆ¤tkab samast seisust ka pĆ¤rast brauseri sulgemist vĆµi telefoni taaskĆ¤ivitamist.
- Kasutatakse cookieā€™sid.
- Kui vajalik cookie puudub, aegub vĆµi ei valideeru, suunatakse kasutaja liitumisvoogu.
- `reload`/tagasi tulles ei kĆ¼sita alias/e-post/tingimused uuesti, kui osalus on endiselt kehtiv.
- Kui sisestatud kood viitab samale vĆµistlusele, kus kasutaja juba aktiivselt osaleb, ei tehta muudatusi (`no-op`).
- Kui sisestatud kood viitab uuele vĆµistlusele:
  - luuakse uus osalus
  - alles seejĆ¤rel suletakse eelmine osalus (`end_date`)
  - mĆµlemad sammud tehakse samas transaktsioonis.

## B. Tehniline tase

### 1) Andmemudel (asjakohane alamhulk)

- `users`
  - `user_id` PK
  - `email` nullable
  - `google_sub` nullable
  - `auth_type` in `('ANON','GOOGLE')`
  - `start_date`, `end_date`, audit vĆ¤ljad

- `competition_terms`
  - vĆµistluse tingimuste versioonid
  - `competition_id`, `version_no`, `status`, audit vĆ¤ljad

- `competition_terms_texts`
  - tingimuste tekstid keelte kaupa
  - `terms_id`, `lang_code`, `terms_text`, audit vĆ¤ljad

- `competition_participants`
  - seob kasutaja ja vĆµistluse
  - `competition_id`, `user_id`, `access_code_id`, `terms_id`
  - `alias_display` (kohustuslik)
  - `contact_email` (valikuline)
  - `terms_lang_code`, `terms_accepted_at` (kohustuslik)
  - `status`, `joined_at`, `start_date`, `end_date`

- `submissions`
  - vĆµistleja vastused
  - soft-delete vĆ¤lju ei ole (`start_date/end_date` puuduvad)

### 2) Unikaalsused ja kontrollid

- Sama vĆµistlus + sama kasutaja ei tohi olla mitu aktiivset osalust:
  - aktiivne unikaalsus `(competition_id, user_id)` tingimusel `end_date is null`
- Globaalset piirangut ā€Ć¼ks aktiivne osalus kasutaja kohta Ć¼le kĆµikide vĆµistlusteā€¯ ei ole.
- Alias on aktiivsetel osalustel vĆµistluse piires case-insensitive unikaalne:
  - `(competition_id, nlssort(trim(alias_display), 'NLS_SORT=BINARY_CI'))` tingimusel `end_date is null`
- E-posti vormikontroll `competition_participants.contact_email` vĆ¤ljal (kui mitte null).

### 3) Cookie mudel

- Sessiooni cookie (nt `funo_session`):
  - signeeritud payload, sisaldab `user_id`
- VĆµistleja sessiooni cookie (nt `funo_competitor_session`):
  - signeeritud payload, sisaldab `user_id`
- Osaluse cookie (nt `funo_participation`):
  - signeeritud payload, sisaldab `competition_participant_id`
  - TTL: 360h (15 pĆ¤eva), sliding refresh viimasel kasutusel
- Cookie atribuudi nĆµuded:
  - `HttpOnly`
  - `Secure`
  - `SameSite=Lax`
  - `Path=/`

### 4) Backendi valideerimine

- Kui cookieā€™d on olemas:
  - valideeri cookie signatuur
  - loe `user_id` sessiooni cookieā€™st
  - loe `competition_participant_id` osaluse cookieā€™st
  - vali DB-st osaluse rida ja kontrolli, et `competition_participants.user_id == session user_id`
  - kontrolli, et osaluse rida on aktiivne (`end_date is null`)
  - kontrolli vĆµistluse staatuse/aja reegleid

- Kui cookie puudub, aegub vĆµi ei valideeru:
  - suuna liitumisvoogu (kood + alias + terms + optional e-post)

### 5) Vastuste salvestamise lubamine

`submissions` insert on lubatud ainult juhul, kui kĆµik tingimused peavad:
- vĆµistlejal on kehtiv osalus selles vĆµistluses
- vĆµistluse `status = 'ACTIVE'`
- `now` asub vahemikus `starts_at <= now < ends_at`

Muidu tagastatakse viga (mitte edukas sisestus).

## C. Liitumisvoo UX (2-sammuline)

### 1) Uus voog

- VÄ†Āµistleja liitumine toimub kahes etapis:
  - Etapp 1 (`join-preview`): kasutaja sisestab koodi, aliase ja soovi korral e-posti.
  - Etapp 2 (`join-complete`): kasutajale kuvatakse konkreetse vÄ†Āµistluse kasutustingimused ja alles nÄ†Āµustumisel tehakse salvestus.

- Etapil 1 kasutatakse nuppu `JÄ†Ā¤tka vÄ†Āµistlusega liitumist`.
  - Nupp on aktiivne ainult siis, kui kood ja alias on sisestatud.
  - Koodi/aliase valideerimine toimub enne tingimuste modali avamist.

### 2) Veateated etapil 1

- Kui kood ei sobi vÄ†Āµi vÄ†Āµistlus pole liitumiseks sobiv:
  - kuvame: `Liitumine ei ole vÄ†Āµimalik`
- Kui alias on samas vÄ†Āµistluses juba kasutusel:
  - kuvame: `Valitud alias ei sobi`

### 3) Tingimuste modal (etapp 2)

- Tingimused kuvatakse selle vÄ†Āµistluse alusel, millega kasutaja liituda proovib.
- Tingimuste kuvamine ei salvesta veel midagi.
- Kasutajal on kaks valikut:
  - `Jah, olen nÄ†Āµus ja liitun vÄ†Āµistlusega` -> kutsub `join-complete` (siin tekivad DB kirjed).
  - `Tagasi` -> salvestust ei tehta.

### 4) Tagasi nupu kÄ†Ā¤itumine

- Kui kasutajal oli enne aktiivne vÄ†Āµistlus:
  - sulgeme liitumismodali(d) ja kasutaja jÄ†Ā¤Ä†Ā¤b olemasoleva vÄ†Āµistluse vaatesse.
- Kui kasutajal aktiivset vÄ†Āµistlust ei olnud:
  - kasutaja viiakse tagasi koodi/aliase sisestamise modali juurde.

### 5) Andmete loomine andmebaasis

- `users` kirje ei tohi tekkida lihtsalt modali avamise, vale koodi vÄ†Āµi katkestamisega.
- `users` kirje tekib ainult eduka `join-complete` korral.
- `users` ja `competition_participants` kirjed tekivad samas DB transaktsioonis.

## D. Sama võistlusega uuesti liitumine

- Kui kasutaja on juba aktiivne osaleja samas võistluses, siis sama võistluse koodiga uuesti liitumine on keelatud.
- Sellisel juhul tagastatakse viga ja UI kuvab teate: `Oled juba võistluse osaleja`.
- See keeld rakendub sõltumata sellest, kas sisestatud alias on sama või erinev.
- Eesmärk: vältida aliase vahetust samas võistluses uuesti liitumise kaudu.

## E. Kasutustingimuste haldus ja fallback

### 1) Admini tingimuste muutmine

- Admin vaates on nupp `Tingimused`, mis avab vĆµistluse tingimuste modali.
- Tingimusi muudetakse HTML vormingus (WYSIWYG editor).
- Keelt saab valida modalis eraldi (`ET`, `EN`, ...), sĆµltumata admin UI enda keelevalikust.
- Salvestus kirjutab tingimused valitud keele jaoks konkreetsesse vĆµistlusesse.

### 2) Vaikimisi tingimused failist

- Vaikimisi tingimused hoitakse failides:
  - `frontend_dist/content/default_et.html`
  - `frontend_dist/content/default_en.html`
  - jne (`default_<lang>.html`)
- Kui võistlusel või valitud keeles tingimused puuduvad, lisatakse need vastavast failist.
- Kui faili ei ole või see on tühi, siis backend ei sünteesi mingit HTML-fallbacki ja tagastab/talletab tühja sisu.
- Vaikimisi sisu loomine on seega failipõhine, mitte koodipõhine.

### 3) Konteineri nĆµue

- Backend loeb default-faile backend konteineri failisĆ¼steemist.
- SeetĆµttu peab `frontend_dist/content` olema mountitud ka `fastapi` konteinerisse.
- `.env` peab sisaldama:
  - `CONTENT_DEFAULTS_DIR=/app/frontend_dist/content`

### 4) Cache reeglid

- VĆµistleja tingimused cache-takse serveri mĆ¤lus vĆµtmega `competition_id|lang_code`.
- Adminis tingimuste salvestamine tĆ¼hjendab cache kohe.
- VĆµistleja vaade kĆ¼sib tingimused iga modali avamisega backendist; backend cache vĆ¤hendab ORDS koormust.

### 5) Suurte tingimustekstide tehniline nĆµue

- Tingimuste HTML vĆµib olla > 4000 mĆ¤rki.
- ORDS/PLSQL JSON vastustes peab kasutama `JSON_OBJECT ... RETURNING CLOB`.
- Vastasel juhul tekib viga:
  - `ORA-40478: output value too large (maximum: 4000)`.

## F. Serveripoolne cache (kooskĆµlas backend/README-ga)

- `competitor_terms_cache`
  - vĆµti: `competition_id|lang_code`
  - TTL: puudub (mĆ¤lupĆµhine cache)
  - tĆ¼hjendamine:
    - automaatselt admini tingimuste salvestamisel
    - kĆ¤sitsi endpointiga `POST /api/competitor/terms-cache/reset`
    - backendi restart

- `map_checkpoints_cache`
  - vĆµti: `competition_id:user_id`
  - TTL: 900 sekundit
  - tĆ¼hjendamine:
    - admini sisu muudatustel (KP/kĆ¼simus/vastused)
    - osaliselt vĆµistlusepĆµhiselt `_invalidate_competition_cache(...)`
    - backendi restart

- `open_checkpoints_last_response`
  - vĆµti: `competition_id:user_id`
  - TTL/throttle: 2 sekundit
  - eesmĆ¤rk: vĆ¤ltida liiga tihedaid korduspĆ¤ringuid

- `competitor_map_layers_cache`
  - vĆµti: `competition_id`
  - TTL: puudub
  - tĆ¼hjendamine:
    - `POST /api/admin/competitions/map-layers`
    - vĆµistlusepĆµhisel invalidate'l
    - backendi restart

- `i18n_cache`
  - vĆµti: `lang_code`
  - TTL: puudub
  - reload endpoint: `POST /api/i18n/reload`

## G. Index vaate i18n reeglid

- Koik `index.html` UI tekstid (sh modalid ja kasutajale kuvatavad API veateated) peavad tulema `translations` tabelist.
- Votmete muster: `competitor.*` (nt `competitor.join.code_label`).
- Votmeid UI-s ei taaskasutata eri kohtades; igal nupul/labelil oma key.
- Muutujatega tekstides kasutatakse named-placeholder formaati:
  - naide: `competitor.results.progress_line = "KP: {answered} / {total} Punktid: {score}"`.
- Fallback:
  1. valitud keel
  2. `.env` `LANG_DEFAULT`
  3. key nimi ise
- Esmalaadimisel kasutatakse `.env` `LANG_DEFAULT` keelt.
- Kasutaja valik salvestatakse cookie-s (`funo_ui_lang`).
- Keelevaliku valikud tulevad `.env` muutujast `LANG_AVAILABLE`.
- Sama keelevalik rakendub ka tingimustele, kirjeldusele ja kusimustele; kui valitud keeles puudub sisu, kasutatakse fallback default keelt.

## H. Multikeelsuse uldpohimote (koik vaated)

- Sama fallback-reegel kehtib koigis mitmekeelsetes vaadetes:
  - `index.html` (voistleja)
  - `admin.html`
  - `superadmin.html`
  - `results.html`
- UI tekstide fallback:
  1. valitud keel
  2. `.env` `LANG_DEFAULT`
  3. voti nimi (translation key)
- Andmepohiste tekstide fallback (kusimus, vastusevariant jms):
  1. valitud keel
  2. `.env` `LANG_DEFAULT`
  3. `---` (viga ei tohi tekkida)
