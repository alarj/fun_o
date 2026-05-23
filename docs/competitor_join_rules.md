# Võistleja liitumise reeglid

## Eesmärk

See dokument koondab võistleja liitumise ja võistluse nähtavuse reeglid:
- äriline vaade (kasutajajuhendi alus)
- tehniline vaade (andmemudel, cookie’d, backendi kontrollid)

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
- Kasutatakse cookie’sid.
- Kui vajalik cookie puudub, aegub või ei valideeru, suunatakse kasutaja liitumisvoogu.
- `reload`/tagasi tulles ei küsita alias/e-post/tingimused uuesti, kui osalus on endiselt kehtiv.
- Kui sisestatud kood viitab samale võistlusele, kus kasutaja juba aktiivselt osaleb, ei tehta muudatusi (`no-op`).
- Kui sisestatud kood viitab uuele võistlusele:
  - luuakse uus osalus
  - alles seejärel suletakse eelmine osalus (`end_date`)
  - mõlemad sammud tehakse samas transaktsioonis.

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
- Cookie atribuudi nõuded:
  - `HttpOnly`
  - `Secure`
  - `SameSite=Lax`
  - `Path=/`

### 4) Backendi valideerimine

- Kui cookie’d on olemas:
  - valideeri cookie signatuur
  - loe `user_id` sessiooni cookie’st
  - loe `competition_participant_id` osaluse cookie’st
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

- VĆµistleja liitumine toimub kahes etapis:
  - Etapp 1 (`join-preview`): kasutaja sisestab koodi, aliase ja soovi korral e-posti.
  - Etapp 2 (`join-complete`): kasutajale kuvatakse konkreetse vĆµistluse kasutustingimused ja alles nĆµustumisel tehakse salvestus.

- Etapil 1 kasutatakse nuppu `JĆ¤tka vĆµistlusega liitumist`.
  - Nupp on aktiivne ainult siis, kui kood ja alias on sisestatud.
  - Koodi/aliase valideerimine toimub enne tingimuste modali avamist.

### 2) Veateated etapil 1

- Kui kood ei sobi vĆµi vĆµistlus pole liitumiseks sobiv:
  - kuvame: `Liitumine ei ole vĆµimalik`
- Kui alias on samas vĆµistluses juba kasutusel:
  - kuvame: `Valitud alias ei sobi`

### 3) Tingimuste modal (etapp 2)

- Tingimused kuvatakse selle vĆµistluse alusel, millega kasutaja liituda proovib.
- Tingimuste kuvamine ei salvesta veel midagi.
- Kasutajal on kaks valikut:
  - `Jah, olen nĆµus ja liitun vĆµistlusega` -> kutsub `join-complete` (siin tekivad DB kirjed).
  - `Tagasi` -> salvestust ei tehta.

### 4) Tagasi nupu kĆ¤itumine

- Kui kasutajal oli enne aktiivne vĆµistlus:
  - sulgeme liitumismodali(d) ja kasutaja jĆ¤Ć¤b olemasoleva vĆµistluse vaatesse.
- Kui kasutajal aktiivset vĆµistlust ei olnud:
  - kasutaja viiakse tagasi koodi/aliase sisestamise modali juurde.

### 5) Andmete loomine andmebaasis

- `users` kirje ei tohi tekkida lihtsalt modali avamise, vale koodi vĆµi katkestamisega.
- `users` kirje tekib ainult eduka `join-complete` korral.
- `users` ja `competition_participants` kirjed tekivad samas DB transaktsioonis.

## D. Sama v�istlusega uuesti liitumine

- Kui kasutaja on juba aktiivne osaleja samas v�istluses, siis sama v�istluse koodiga uuesti liitumine on keelatud.
- Sellisel juhul tagastatakse viga ja UI kuvab teate: `Oled juba v�istluse osaleja`.
- See keeld rakendub s�ltumata sellest, kas sisestatud alias on sama v�i erinev.
- Eesm�rk: v�ltida aliase vahetust samas v�istluses uuesti liitumise kaudu.
