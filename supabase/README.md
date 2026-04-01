# Supabase setup (Career Fair Checklist)

## 1. API keys

Open `lib/supabase_config.dart` and set `supabaseUrl` and `supabaseAnonKey` (Dashboard → Project Settings → API).

## 2. Schema

In **SQL Editor**, run `schema.sql`. It creates:

- `fairs` — events (one fair has many programs)
- `program_types` — reusable categories (e.g. four-year college, apprenticeship); add or change anytime
- `question_sections` — optional group titles under a program type (`title`, `sort_order`). Questions link via `questions.section_id`; **leave `section_id` null** for questions that should appear **without** a section header (shown first, before titled sections).
- `questions` — rows per program type (`label`, `sort_order`, `type`, optional `section_id`). Column **`type`** drives the control: `text`, `number`, `boolean`, `date` (calendar date stored in `answer_text` as `yyyy-MM-dd`), `money` (decimal text in `answer_text`). Unknown values are treated as `text`.
- `programs` — booth/row at a fair (`fair_id`, `program_type_id`, optional website/contact fields)
- `user_program_answers` — one row per user + program + question (answer text)

Row Level Security policies are included: authenticated users can read reference tables; users can only read/write their own answers.

If you still have legacy `college_fairs` / `colleges` / `user_college_data` tables, back them up, then drop or rename them before applying the new schema (or use a fresh project).

## 3. Email login code

See the main project README or earlier notes: configure the **Magic Link** email template so `{{ .Token }}` shows the verification code.

## 4. Example seed (optional)

After `schema.sql`, you can insert types, questions, a fair, and programs (adjust UUIDs or use `default`):

```sql
insert into public.program_types (name, sort_order) values
  ('Four-year college', 0),
  ('Apprenticeship', 1);

-- Assume IDs returned; replace with your UUIDs from program_types:
insert into public.questions (program_type_id, label, sort_order)
select id, 'Minimum GPA?', 0 from public.program_types where name = 'Four-year college'
union all
select id, 'Scholarships offered?', 1 from public.program_types where name = 'Four-year college';

insert into public.fairs (name, fair_date) values ('Spring career fair', '2026-04-15');

insert into public.programs (fair_id, program_type_id, name, sort_order)
select f.id, pt.id, 'Example University', 0
from public.fairs f
cross join public.program_types pt
where f.name = 'Spring career fair' and pt.name = 'Four-year college';
```

## 5. Run the app

```bash
flutter pub get
flutter run
```
