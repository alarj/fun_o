# Andmemudeli ERD (v4)


## Aktiivse kirje reegel

Aktiivne kirje on kirje, kus:
- `end_date IS NULL` voi
- `end_date > SYSDATE`

Märkus: `submissions` tabelis soft-delete veerge (`start_date`, `end_date`) ei ole.

## ERD (Mermaid allikas)

```mermaid
erDiagram
    USERS {
        number user_id PK
        varchar2 email
        varchar2 full_name
        varchar2 google_sub
        varchar2 auth_type
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
        varchar2 type
        varchar2 status
        varchar2 use_location
        varchar2 show_competitor_location
        number radius_m
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
        varchar2 code_type
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

    COMPETITION_DECLINATIONS {
        number competition_id PK
        number declination
        timestamp last_updated
    }

    COMPETITION_TERMS {
        number terms_id PK
        number competition_id FK
        number version_no
        varchar2 status
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    COMPETITION_TERMS_TEXTS {
        number terms_text_id PK
        number terms_id FK
        varchar2 lang_code
        clob terms_text
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    COMPETITION_PARTICIPANTS {
        number competition_participant_id PK
        number competition_id FK
        number user_id FK
        number access_code_id FK
        number terms_id FK
        varchar2 alias_display
        varchar2 contact_email
        varchar2 terms_lang_code
        timestamp terms_accepted_at
        varchar2 status
        date start_date
        date end_date
        timestamp joined_at
    }

    CHECKPOINTS {
        number checkpoint_id PK
        number competition_id FK
        varchar2 title
        varchar2 checkpoint_type
        number order_no
        varchar2 location_hint
        number latitude
        number longitude
        number radius_m
        varchar2 location_required
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
        varchar2 question_type
        varchar2 input_type
        number input_max_length
        varchar2 input_pattern
        varchar2 placeholder_key
        varchar2 help_text_key
        number points
        number wrong_points
        varchar2 status
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    QUESTION_TEXTS {
        number question_text_id PK
        number question_id FK
        varchar2 lang_code
        varchar2 question_text
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    QUESTION_OPTIONS {
        number option_id PK
        number question_id FK
        varchar2 option_code
        number order_no
        varchar2 is_correct
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    QUESTION_OPTION_TEXTS {
        number question_option_text_id PK
        number option_id FK
        varchar2 lang_code
        varchar2 option_text
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    QUESTION_ANSWERS {
        number answer_id PK
        number question_id FK
        varchar2 answer_value
        varchar2 is_correct
        varchar2 normalize_mode
        date start_date
        date end_date
        number created_by
        number updated_by
        timestamp created_at
        timestamp updated_at
    }

    TRANSLATIONS {
        number translation_id PK
        varchar2 translation_key
        varchar2 lang_code
        varchar2 text_value
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
        number selected_option_id FK
        number awarded_points
        varchar2 is_correct
        timestamp submitted_at
        number evaluated_by
        timestamp evaluated_at
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

    COMPETITIONS ||--o{ COMPETITION_TERMS : has
    COMPETITION_TERMS ||--o{ COMPETITION_TERMS_TEXTS : has_texts

    COMPETITIONS ||--o{ COMPETITION_PARTICIPANTS : has
    USERS ||--o{ COMPETITION_PARTICIPANTS : participates
    COMPETITION_ACCESS_CODES ||--o{ COMPETITION_PARTICIPANTS : joined_with_code
    COMPETITION_TERMS ||--o{ COMPETITION_PARTICIPANTS : accepted_terms

    COMPETITIONS ||--o{ CHECKPOINTS : has
    CHECKPOINTS ||--o{ QUESTIONS : has

    QUESTIONS ||--o{ QUESTION_TEXTS : has_i18n_texts
    QUESTIONS ||--o{ QUESTION_OPTIONS : has_options
    QUESTION_OPTIONS ||--o{ QUESTION_OPTION_TEXTS : has_i18n_texts
    QUESTIONS ||--o{ QUESTION_ANSWERS : has_text_or_numeric_answers

    QUESTIONS ||--o{ SUBMISSIONS : receives
    QUESTION_OPTIONS ||--o{ SUBMISSIONS : selected_by_optional
    USERS ||--o{ SUBMISSIONS : submits

    COMPETITIONS ||--o{ MATERIALS : has
    CHECKPOINTS ||--o{ MATERIALS : has_optional
```

## CHECKPOINTS märkused

- `checkpoint_type` lubatud äriväärtused on `NORMAL`, `START`, `FINISH`.
- Kui `checkpoint_type` on `NULL`, käsitletakse seda rakenduse äriloogikas kui `NORMAL`.
- Ühel aktiivsel võistlusel võib olla maksimaalselt üks aktiivne `START` ja üks aktiivne `FINISH`.
