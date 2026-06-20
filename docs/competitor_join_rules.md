# Võistleja liitumise reeglid

## Eesmärk

See dokument koondab võistleja liitumise ja võistluse nähtavuse reeglid:
- äriline vaade (kasutajajuhendi alus)
- tehniline vaade (andmemudel, cookie'd, backendi kontrollid)

## A. Äriline tase

### 1) Liitumine

- Võistleja saab liituda võistlusega koodi alusel.
- Liitumise kanalid:
  - URL-is sisalduv võistleja kood (nt QR)
  - käsitsi sisestatud kood avalehel
- Kui kasutajal on kehtiv osaluscookie + DB-s sellele vastav aktiivne osalus, avatakse kohe sama võistlus.
- Liitumine loetakse lõppenuks alles siis, kui kasutaja:
  - sisestab aliase
  - nõustub kasutustingimustega
  - (soovi korral) sisestab e-posti
- Liitumisvoo esimese sammu ees töötab taustal anti-bot kontroll:
  - vaikimisi reCAPTCHA v3;
  - kui v3 riskiskoor jääb alla lävendi, suunatakse kasutaja reCAPTCHA v2 challenge'ile;
  - kasutajale ei kuvata v2 challenge'it, kui v3 kontroll läheb läbi.

### 2) Alias

- Alias on kohustuslik.
- Alias peab olema sama võistluse piires unikaalne.
- Aliaside võrdlus on case-insensitive (`karu`, `KARU`, `KaRu` on sama), kuid tähekuju säilib kuvamiseks.
- Erinevad sõned ja tühikute variandid on erinevad (`jääkaru` != `jää karu`).

### 3) E-post

- E-post on valikuline.
- Kui sisestatakse, peab olema e-posti kujuline (`x@y.z` tasemel kontroll).
- E-posti unikaalsust ei kontrollita.

### 4) Kasutustingimused

- Nõustumine on kohustuslik.
- Tingimused on võistlusepõhised ja mitmekeelsed.
- Admini tehtud muudatused peavad säilima.
- Vaikimisi tingimused loetakse failist ainult siis, kui tabelis puuduvad.

### 5) Võistluse olekud võistleja vaates

- `DRAFT`
  - võistleja ei näe
  - liituda ei saa
  - kui cookie viitab sellele, suunatakse liitumisvoogu

- `INACTIVE`
  - liituda saab
  - võistluse sisu (kaart, KP-d, küsimused) ei näidata
  - vastuseid esitada ei saa

- `ACTIVE` ja aeg vahemikus `starts_at <= now < ends_at`
  - liituda saab
  - sisu kuvatakse
  - vastuseid saab esitada

- `ACTIVE`, aga aeg väljas vahemikku
  - liituda saab
  - sisu kuvatakse ainult vaatamiseks
  - vastuseid esitada ei saa

### 6) Sessioon ja taastamine

- Eesmärk: kasutaja jätkab samast seisust ka pärast brauseri sulgemist või telefoni taaskäivitamist.
- Kasutatakse cookie'sid.
- Kui vajalik cookie puudub, aegub või ei valideeru, suunatakse kasutaja liitumisvoogu.
- `reload`/tagasi tulles ei küsita alias/e-post/tingimused uuesti, kui osalus on endiselt kehtiv.
- Kui sisestatud kood viitab samale võistlusele, kus kasutaja juba aktiivselt osaleb, ei tehta muudatusi (`no-op`).
- Kui sisestatud kood viitab uuele võistlusele:
  - luuakse uus osalus
  - alles seejärel suletakse eelmine osalus (`end_date`)
  - mõlemad sammud tehakse samas transaktsioonis

## B. Tehniline tase

### 1) Andmemudel (asjakohane alamhulk)

- `users`
  - `user_id` PK
  - `email` nullable
  - `google_sub` nullable
  - `auth_type` in `('ANON','GOOGLE')`
  - `start_date`, `end_date`, audit väljad

- `competition_terms`
  - võistluse tingimuste versioonid
  - `competition_id`, `version_no`, `status`, audit väljad

- `competition_terms_texts`
  - tingimuste tekstid keelte kaupa
  - `terms_id`, `lang_code`, `terms_text`, audit väljad

- `competition_participants`
  - seob kasutaja ja võistluse
  - `competition_id`, `user_id`, `access_code_id`, `terms_id`
  - `alias_display` (kohustuslik)
  - `contact_email` (valikuline)
  - `terms_lang_code`, `terms_accepted_at` (kohustuslik)
  - `status`, `joined_at`, `start_date`, `end_date`

- `submissions`
  - võistleja vastused
  - soft-delete välju ei ole (`start_date/end_date` puuduvad)

### 2) Unikaalsused ja kontrollid

- Sama võistlus + sama kasutaja ei tohi olla mitu aktiivset osalust:
  - aktiivne unikaalsus `(competition_id, user_id)` tingimusel `end_date is null`
- Globaalset piirangut “üks aktiivne osalus kasutaja kohta üle kõikide võistluste” ei ole.
- Alias on aktiivsetel osalustel võistluse piires case-insensitive unikaalne:
  - `(competition_id, nlssort(trim(alias_display), 'NLS_SORT=BINARY_CI'))` tingimusel `end_date is null`
- E-posti vormikontroll `competition_participants.contact_email` väljal (kui mitte null).

### 3) Cookie mudel

- Sessiooni cookie (nt `funo_session`):
  - signeeritud payload, sisaldab `user_id`
- Võistleja sessiooni cookie (nt `funo_competitor_session`):
  - signeeritud payload, sisaldab `user_id`
- Osaluse cookie (nt `funo_participation`):
  - signeeritud payload, sisaldab `competition_participant_id`
  - TTL: 360h (15 päeva), sliding refresh viimasel kasutusel
- Cookie atribuutide nõuded:
  - `HttpOnly`
  - `Secure`
  - `SameSite=Lax`
  - `Path=/`

### 4) Backendi valideerimine

- Kui cookie'd on olemas:
  - valideeri cookie signatuur
  - loe `user_id` sessiooni cookie'st
  - loe `competition_participant_id` osaluse cookie'st
  - vali DB-st osaluse rida ja kontrolli, et `competition_participants.user_id == session user_id`
  - kontrolli, et osaluse rida on aktiivne (`end_date is null`)
  - kontrolli võistluse staatuse/aja reegleid

- Kui cookie puudub, aegub või ei valideeru:
  - suuna liitumisvoogu (kood + alias + terms + optional e-post)

### 5) Vastuste salvestamise lubamine

`submissions` insert on lubatud ainult juhul, kui kõik tingimused peavad:
- võistlejal on kehtiv osalus selles võistluses
- võistluse `status = 'ACTIVE'`
- `now` asub vahemikus `starts_at <= now < ends_at`

Muidu tagastatakse viga (mitte edukas sisestus).

## C. Liitumisvoo UX (2-sammuline)

### 1) Uus voog

- Võistleja liitumine toimub kahes etapis:
  - Etapp 1 (`join-preview`): kasutaja sisestab koodi, aliase ja soovi korral e-posti.
  - Etapp 2 (`join-complete`): kasutajale kuvatakse konkreetse võistluse kasutustingimused ja alles nõustumisel tehakse salvestus.

- Etapil 1 kasutatakse nuppu `Jätka võistlusega liitumist`.
  - Nupp on aktiivne ainult siis, kui kood ja alias on sisestatud.
  - Koodi/aliase valideerimine toimub enne tingimuste modali avamist.
  - Enne ORDS `join-preview` kutset teeb FastAPI inimese-kontrolli:
    - esmalt reCAPTCHA v3;
    - vajadusel sama preview kordus reCAPTCHA v2 tokeniga.

### 2) Veateated etapil 1

- Kui kood ei sobi või võistlus pole liitumiseks sobiv:
  - kuvame: `Liitumine ei ole võimalik`
- Kui alias on samas võistluses juba kasutusel:
  - kuvame: `Valitud alias ei sobi`

### 3) Tingimuste modal (etapp 2)

- Tingimused kuvatakse selle võistluse alusel, millega kasutaja liituda proovib.
- Tingimuste kuvamine ei salvesta veel midagi.
- Edukas `join-preview` tagastab lisaks lühiajalise serveripoolse `join_proof` tõendi.
- Kasutajal on kaks valikut:
  - `Jah, olen nõus ja liitun võistlusega` -> kutsub `join-complete` (siin tekivad DB kirjed)
  - `Tagasi` -> salvestust ei tehta

### 4) Tagasi nupu käitumine

- Kui kasutajal oli enne aktiivne võistlus:
  - sulgeme liitumismodali(d) ja kasutaja jääb olemasoleva võistluse vaatesse
- Kui kasutajal aktiivset võistlust ei olnud:
  - kasutaja viiakse tagasi koodi/aliase sisestamise modali juurde
- Sammu vahetusel puhastatakse alati eelmise sammu staatus- ja veateated; tagasi liikudes ei tohi eelmise sammu vana teade jääda ekraanile.

### 5) Andmete loomine andmebaasis

- `users` kirje ei tohi tekkida lihtsalt modali avamise, vale koodi või katkestamisega.
- `users` kirje tekib ainult eduka `join-complete` korral.
- `users` ja `competition_participants` kirjed tekivad samas DB transaktsioonis.
- `join-complete` on lubatud ainult siis, kui requestis olev `join_proof` klapib sama koodi, aliase, tingimuste versiooni ja competitor sessiooniga.

## D. Sama võistlusega uuesti liitumine

- Kui kasutaja on juba aktiivne osaleja samas võistluses, siis sama võistluse koodiga uuesti liitumine on keelatud.
- Sellisel juhul tagastatakse viga ja UI kuvab teate: `Oled juba võistluse osaleja`.
- See keeld rakendub sõltumata sellest, kas sisestatud alias on sama või erinev.
- Eesmärk: vältida aliase vahetust samas võistluses uuesti liitumise kaudu.

## E. Kasutustingimuste haldus ja fallback

### 1) Admini tingimuste muutmine

- Admin vaates on nupp `Tingimused`, mis avab võistluse tingimuste modali.
- Tingimusi muudetakse HTML vormingus (WYSIWYG editor).
- Keelt saab valida modalis eraldi (`ET`, `EN`, ...), sõltumata admin UI enda keelevalikust.
- Salvestus kirjutab tingimused valitud keele jaoks konkreetsesse võistlusesse.

### 2) Vaikimisi tingimused failist

- Vaikimisi tingimused hoitakse failides:
  - `frontend_dist/content/default_et.html`
  - `frontend_dist/content/default_en.html`
  - jne (`default_<lang>.html`)
- Kui võistlusel või valitud keeles tingimused puuduvad, lisatakse need vastavast failist.
- Kui faili ei ole või see on tühi, siis backend ei sünteesi mingit HTML-fallbacki ja tagastab/talletab tühja sisu.
- Vaikimisi sisu loomine on seega failipõhine, mitte koodipõhine.

### 3) Konteineri nõue

- Backend loeb default-faile backend konteineri failisüsteemist.
- Seetõttu peab `frontend_dist/content` olema mountitud ka `fastapi` konteinerisse.
- `.env` peab sisaldama:
  - `CONTENT_DEFAULTS_DIR=/app/frontend_dist/content`

### 4) Cache reeglid

- Võistleja tingimused cache-takse serveri mälus võtmega `competition_id|lang_code`.
- Adminis tingimuste salvestamine tühjendab cache kohe.
- Võistleja vaade küsib tingimused iga modali avamisega backendist; backend cache vähendab ORDS koormust.

### 5) Suurte tingimustekstide tehniline nõue

- Tingimuste HTML võib olla > 4000 märki.
- ORDS/PLSQL JSON vastustes peab kasutama `JSON_OBJECT ... RETURNING CLOB`.
- Vastasel juhul tekib viga:
  - `ORA-40478: output value too large (maximum: 4000)`

## F. Serveripoolne cache (kooskõlas backend/README-ga)

- `competitor_terms_cache`
  - võti: `competition_id|lang_code`
  - TTL: puudub (mälupõhine cache)
  - tühjendamine:
    - automaatselt admini tingimuste salvestamisel
    - käsitsi endpointiga `POST /api/competitor/terms-cache/reset`
    - backendi restart

- `map_checkpoints_cache`
  - võti: `competition_id:user_id`
  - TTL: 900 sekundit
  - tühjendamine:
    - admini sisu muudatustel (KP/küsimus/vastused)
    - osaliselt võistlusepõhiselt `_invalidate_competition_cache(...)`
    - backendi restart

- `open_checkpoints_last_response`
  - võti: `competition_id:user_id`
  - TTL/throttle: 2 sekundit
  - eesmärk: vältida liiga tihedaid korduspäringuid

- `competitor_map_layers_cache`
  - võti: `competition_id`
  - TTL: puudub
  - tühjendamine:
    - `POST /api/admin/competitions/map-layers`
    - võistlusepõhisel invalidate'l
    - backendi restart

- `i18n_cache`
  - võti: `lang_code`
  - TTL: puudub
  - reload endpoint: `POST /api/i18n/reload`

## G. Anti-bot tehniline voog

- Competitor join anti-bot töötab ainult FastAPI kihis; ORDS-i ega DB skeemi selle jaoks ei muudeta.
- FastAPI endpoint `GET /api/competitor/join-config` annab frontendile teada, kas reCAPTCHA kaitse on sisse lülitatud ja milliseid public võtmeid kasutada.
- Kui `APP_ENV=production` ja reCAPTCHA võtmed on ainult osaliselt seadistatud, vastab FastAPI fail-closed põhimõttel veaga ega lülita kaitset vaikselt välja.
- `POST /api/competitor/join-preview` aktsepteerib:
  - `recaptcha_v3_token` tavavoo jaoks;
  - `recaptcha_v2_token` fallback-väärtusena pärast madalat v3 skoori.
- Eduka preview järel tagastatav `join_proof` on HMAC-signeeritud ja lühiajaline.
- `POST /api/competitor/join-complete` peab sama `join_proof` tõendi tagasi saatma.
- Kui proof puudub, on aegunud või ei klapi requesti väljadega, katkestab FastAPI voo enne ORDS `join-complete` kutset.

## H. Index vaate i18n reeglid

- Kõik `index.html` UI tekstid (sh modalid ja kasutajale kuvatavad API veateated) peavad tulema `translations` tabelist.
- Võtmete muster: `competitor.*` (nt `competitor.join.code_label`).
- Võtmeid UI-s ei taaskasutata eri kohtades; igal nupul/labelil oma key.
- Muutujatega tekstides kasutatakse named-placeholder formaati:
  - näide: `competitor.results.progress_line = "KP: {answered} / {total} Punktid: {score}"`
- Fallback:
  1. valitud keel
  2. `.env` `LANG_DEFAULT`
  3. key nimi ise
- Esmalaadimisel kasutatakse `.env` `LANG_DEFAULT` keelt.
- Kasutaja valik salvestatakse cookie-s (`funo_ui_lang`).
- Keelevaliku valikud tulevad `.env` muutujast `LANG_AVAILABLE`.
- Sama keelevalik rakendub ka tingimustele, kirjeldusele ja küsimustele; kui valitud keeles puudub sisu, kasutatakse fallback default keelt.

## I. Multikeelsuse üldpõhimõte (kõik vaated)

- Sama fallback-reegel kehtib kõigis mitmekeelsetes vaadetes:
  - `index.html` (võistleja)
  - `admin.html`
  - `superadmin.html`
  - `results.html`
- UI tekstide fallback:
  1. valitud keel
  2. `.env` `LANG_DEFAULT`
  3. võtme nimi (translation key)
- Andmepõhiste tekstide fallback (küsimus, vastusevariant jms):
  1. valitud keel
  2. `.env` `LANG_DEFAULT`
  3. `---` (viga ei tohi tekkida)
