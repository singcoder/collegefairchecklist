# Supabase setup (College & Career Checklist)

## 1. Paste your anon key in the app

Open `lib/supabase_config.dart` and replace `PASTE_YOUR_ANON_KEY_HERE` with your project's **anon public** key (Supabase Dashboard → Project Settings → API).

## 2. Run the schema

In Supabase Dashboard → **SQL Editor** → New query, paste the contents of `schema.sql` and click **Run**. This creates the `checklist_items` and `user_checklist` tables and RLS policies.

## 3. Use 6-digit code in the email (not a separate “OTP” setting)

There is **no separate “Enable OTP”** toggle. The same `signInWithOtp` call sends either a **magic link** or a **6-digit code** depending on the **email template**.

To send a **6-digit code**:

1. In Supabase Dashboard go to **Authentication** → **Email Templates** (left sidebar under Auth).
2. Open the **Magic Link** template.
3. Change the **Subject** and **Body** so the email shows the code instead of (or as well as) the link. For example:

   **Subject:** `Your login code`

   **Body (HTML):**
   ```html
   <h2>Your login code</h2>
   <p>Enter this code in the app:</p>
   <p><strong>{{ .Token }}</strong></p>
   <p>It expires in a short time.</p>
   ```

4. Save. The `{{ .Token }}` variable is the 6-digit code. After this, when users tap “Send verification code”, they’ll get this code in the email to type into the app.

## 4. Add checklist items (optional)

To see items in the app, insert rows into `checklist_items` via SQL Editor or Table Editor, for example:

```sql
insert into public.checklist_items (id, checklist_id, title, url, sort_order)
values
  ('item-1', 'global', 'First item', 'https://example.com', 0),
  ('item-2', 'global', 'Second item', null, 1);
```

## 5. Run the app

```bash
flutter pub get
flutter run
```

Sign in with your email → send code → enter the 6-digit code from the email → you should see the checklist (or "No checklist items" until you add rows).
