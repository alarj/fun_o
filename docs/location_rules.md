# Asukohareeglid (location rules)

See dokument kirjeldab kokkulepitud ärireegleid, kuidas asukohaandmeid kasutatakse võistlustel, kontrollpunktidel (KP) ja võistleja vaates.

## 1. Võistluse taseme parameetrid

- `competitions.use_location` (`Y`/`N`)
  - Määrab, kas võistlus kasutab asukohaloogikat üldse.
- `competitions.radius_m` (number, meetrites)
  - Vaikimisi kauguslävi, mida kasutatakse KP-de puhul, kui KP-l eraldi raadiust pole määratud.

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
  - Võib pakkuda eelisjärjekorras lähedal olevaid KP-sid (raadiuse alusel).
- Kui asukohta ei saa (luba puudub/GPS viga/seade ei toeta):
  - Võistleja saab KP käsitsi valida (fallback).
- Kui GPS täpsus on halb:
  - KP käsitsi valik peab jääma võimalikuks.

## 5. Vastuse salvestamine

- Võistleja asukoht vastamise hetkel salvestatakse `submissions` kirjele:
  - `latitude`
  - `longitude`
  - `accuracy_m` (kui olemas)
- Uut eraldi asukohatabelit ei looda.

## 6. Raadiuse arvutamise reegel

KP efektiivne raadius:

1. kui `checkpoints.radius_m` on määratud, kasutatakse seda;
2. muidu kasutatakse `competitions.radius_m`.

## 7. Liitumise ja aktiivsuse reeglid (võistleja)

Koodiga liituda saab ainult võistlusega, mis on:

- `status='ACTIVE'`;
- `starts_at <= nüüd`;
- `ends_at IS NULL` või `ends_at > nüüd`;
- mitte soft-deleted (`end_date IS NULL`).

Vale, aegunud, mitteaktiivne või kustutatud võistluse kood annab kasutajale sama üldise teate (detaili ei avaldata).

## 8. Soft delete põhimõte API vastustes

- ORDS teenused ei tagasta vaikimisi soft-deleted kirjeid.
- Kui tulevikus on vaja kustutatud kirjeid näidata, tehakse selleks eraldi teenus.

## 9. Admin UI käitumine (kokkulepitud)

- Asukohaandmete muutmine toimub võistluse ühisest „Muuda võistlust” vormist.
- KP muutmisaknas:
  - kaart kuvatakse ainult siis, kui `use_location='Y'`;
  - KP raadius mõjutab kaardil kuvatavat ringi;
  - kui KP-l raadius puudub, kasutatakse võistluse vaikeraadiust.
- Uue KP loomisel tsentreeritakse kaart viimati sisestatud KP asukohale (sama võistluse piires), et vältida iga kord nullist suumimist.
