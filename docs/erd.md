# Andmemudeli ERD (v2)

Allolev ERD arvestab rolle, ORDS-protseduuripõhist backendi, audit-logi ja ajalisi kirjeid (`start_date`, `end_date`).

## Aktiivse kirje reegel

Aktiivne kirje on kirje, kus:
- `end_date IS NULL` **või**
- `end_date > SYSDATE`

See reegel kehtib kõigis ärireeglites, kus kontrollitakse unikaalsust või kehtivust.

## ERD

```mermaid
erDiagram
    USERS {
        number user_id PK
        varchar2 email
        varchar2 full_name
        varchar2 google_sub
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    ROLES {
        number role_id PK
        varchar2 role_code
        varchar2 role_name
        date start_date
        date end_date
    }

    USER_ROLES {
        number user_role_id PK
        number user_id FK
        number role_id FK
        date start_date
        date end_date
        number assigned_by
        timestamp assigned_at
    }

    COMPETITIONS {
        number competition_id PK
        varchar2 name
        varchar2 description
        varchar2 status
        timestamp starts_at
        timestamp ends_at
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    COMPETITION_ACCESS_CODES {
        number access_code_id PK
        number competition_id FK
        varchar2 code
        varchar2 status
        timestamp expires_at
        number max_uses
        number used_count
        date start_date
        date end_date
        number created_by
        timestamp created_at
    }

    COMPETITION_ORGANIZERS {
        number competition_organizer_id PK
        number competition_id FK
        number user_id FK
        date start_date
        date end_date
        number assigned_by
        timestamp assigned_at
    }

    COMPETITION_PARTICIPANTS {
        number competition_participant_id PK
        number competition_id FK
        number user_id FK
        number access_code_id FK
        varchar2 status
        date start_date
        date end_date
        timestamp joined_at
    }

    CHECKPOINTS {
        number checkpoint_id PK
        number competition_id FK
        varchar2 title
        number order_no
        varchar2 location_hint
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    QUESTIONS {
        number question_id PK
        number checkpoint_id FK
        varchar2 question_text
        varchar2 question_type
        number points
        number order_no
        varchar2 status
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    SUBMISSIONS {
        number submission_id PK
        number competition_id FK
        number checkpoint_id FK
        number question_id FK
        number user_id FK
        clob answer_text
        number awarded_points
        varchar2 is_correct
        timestamp submitted_at
        number evaluated_by
        timestamp evaluated_at
        date start_date
        date end_date
    }

    MATERIALS {
        number material_id PK
        number competition_id FK
        number checkpoint_id FK
        varchar2 title
        varchar2 material_type
        varchar2 uri
        varchar2 visibility
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    AUDIT_LOG {
        number audit_id PK
        varchar2 entity_type
        number entity_id
        varchar2 action_type
        number changed_by
        timestamp changed_at
        clob old_data_json
        clob new_data_json
    }

    USERS ||--o{ USER_ROLES : has
    ROLES ||--o{ USER_ROLES : assigned

    COMPETITIONS ||--o{ COMPETITION_ACCESS_CODES : has
    COMPETITIONS ||--o{ COMPETITION_ORGANIZERS : has
    USERS ||--o{ COMPETITION_ORGANIZERS : organizes

    COMPETITIONS ||--o{ COMPETITION_PARTICIPANTS : has
    USERS ||--o{ COMPETITION_PARTICIPANTS : participates

    COMPETITIONS ||--o{ CHECKPOINTS : has
    CHECKPOINTS ||--o{ QUESTIONS : has
    QUESTIONS ||--o{ SUBMISSIONS : receives
    USERS ||--o{ SUBMISSIONS : submits

    COMPETITIONS ||--o{ MATERIALS : has
    CHECKPOINTS ||--o{ MATERIALS : has_optional
```

## Ärireeglid (kokkuvõte)

1. Füüsilist kustutamist ei tehta; kirje "kustutamine" tähendab `end_date` täitmist.
2. Aktiivne kirje: `end_date IS NULL OR end_date > SYSDATE`.
3. Sama isik võib samal võistlusel olla korraga nii korraldaja kui osaleja.
4. Osaleja topeltliitumine samale võistlusele on keelatud aktiivsete kirjete lõikes.
5. Korraldaja topeltmääramine samale võistlusele on keelatud aktiivsete kirjete lõikes.
6. Võistlusega liitumine toimub koodi alusel; võistlustel on erinevad koodid.
