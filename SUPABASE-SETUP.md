# Moving the meal planner onto Supabase

Two things get set up here, and they're independent — do part A and B first and
you'll have a database that can't freeze, whether or not the app has moved yet.

- **A. The project and schema** — where the data will live
- **B. The keep-alive** — the GitHub Action that stops the free tier pausing
- **C. Accounts and household** — magic-link sign-in for you and your wife
- **D. Handing it back to me** — what I need to migrate the app itself

The current app at <https://jackson-meal-planner.netlify.app> keeps working the
whole time. Nothing here breaks it.

---

## A. Create the project and run the schema

1. Go to <https://supabase.com/dashboard>, sign in with GitHub or email.
2. **New project**.
   - **Name**: `meal-planner`
   - **Database password**: if it offers one, save it — but do not worry if you
     never saw the prompt. Nothing in this project uses it. It is only for
     connecting to Postgres directly (psql, a SQL GUI, the Supabase CLI).
     Everything here talks over HTTPS with an API key instead. If you ever do
     need it, reset it at **Settings → Database → Reset database password**.
   - **Region**: pick **East US (North Virginia)** or **Central US** — closest
     to Houston, so the app feels snappy.
3. Wait for it to finish provisioning (a minute or two).
4. Left sidebar → **SQL Editor** → **New query**.
5. Paste the entire contents of `supabase/schema.sql` from this folder and hit
   **Run**. You should see "Success. No rows returned."

That script is safe to run more than once, so if you tweak something later you
can just re-run the whole file.

6. Sanity-check it took. New query:

   ```sql
   select * from public.heartbeat;
   ```

   One row, `pings = 0`.

## B. Wire up the keep-alive

### B1. Get your keys

Left sidebar → **Settings** → **API Keys**. You need two values:

- **Project URL** — looks like `https://abcdefghijkl.supabase.co`.
  If you don't see it on that page, it's under **Settings → General**, or just
  read it off your browser's address bar: the dashboard URL contains the
  project ref, so `.../project/abcdefghijkl` means your URL is
  `https://abcdefghijkl.supabase.co`.
- **The public client key.** Which name you see depends on how new the project
  is — Supabase is part-way through renaming these:
  - a **publishable** key starting `sb_publishable_...` (newer projects), or
  - an **anon / public** key, a long string starting `eyJ...` (older projects)

  Take whichever one your dashboard shows. They do the same job and both work
  with this setup. If you see both, prefer the publishable one — the anon key
  is being retired.

> That key is *designed* to be public — it ends up inside the web page itself.
> It is not a password. What actually protects your data is row-level security,
> which the schema already set up. The one to never share is the **secret** key
> (`sb_secret_...`, previously **service_role**) on that same page. It bypasses
> every security policy. It goes nowhere near GitHub, the app, or me.

### B2. Make the repository

The workflow needs to live in a Git repo on GitHub.

```bash
cd "C:\Users\richa\OneDrive\Documents\Richard's Claude Code\meal-planner"
git init -b main
git add .
git commit -m "Meal planner: app, H-E-B aisles, Supabase schema and keep-alive"
```

Then create an empty repo at <https://github.com/new> — call it
`meal-planner`, and **make it Private**. Don't add a README or .gitignore.
Follow the "push an existing repository" lines it shows you:

```bash
git remote add origin https://github.com/<your-username>/meal-planner.git
git push -u origin main
```

### B3. Add the secrets

In the GitHub repo: **Settings → Secrets and variables → Actions → New
repository secret**. Add two:

| Name | Value |
|---|---|
| `SUPABASE_URL` | your Project URL, no trailing slash |
| `SUPABASE_ANON_KEY` | the publishable (or anon) key from B1 |

The secret is named `SUPABASE_ANON_KEY` for historical reasons; it is just a
label the workflow looks up, so paste a `sb_publishable_...` key into it
without renaming anything.

### B4. Prove it works

Repo → **Actions** tab → **Supabase keep-alive** → **Run workflow**. Don't wait
for the schedule; run it by hand now.

It should go green and the log should read `HTTP 200` then `Database write
succeeded`. Confirm in Supabase:

```sql
select * from public.heartbeat;
```

`pings` should now be 1 and `last_ping` should be seconds ago. From here it runs
itself every Monday, Wednesday and Friday.

If it goes red, the log tells you which: a 401 means the anon key is wrong, a
404 on `/rpc/keepalive` means the schema didn't run, and a timeout usually means
the project is already paused (unpause it in the dashboard and re-run).

## C. Sign-in and the household

### C1. Turn on magic links

Supabase sidebar → **Authentication** → **Providers** → **Email**. Make sure
**Enable Email provider** is on and **Confirm email** is on. You do *not* need
a password provider.

Then **Authentication → URL Configuration**, and under **Redirect URLs** add:

```
https://jackson-meal-planner.netlify.app
```

Without that, the sign-in link will bounce.

### C2. Both of you sign in once

This part waits until I've migrated the app — the sign-in screen doesn't exist
yet. Once it does, you each open the app, type your email, and tap the link that
arrives. That creates your rows in `auth.users`.

### C3. Create the household

After you've both signed in once, run this in the SQL Editor, with her real
email in place of the placeholder:

```sql
-- 1. create the household
insert into public.households (name)
values ('Jackson Family')
returning id;

-- 2. copy the id it printed into the line below, then run it
insert into public.household_members (household_id, user_id)
select '<paste-household-id-here>'::uuid, id
  from auth.users
 where email in ('richardjackson07@gmail.com', 'her-email@example.com')
on conflict do nothing;

-- 3. check it
select h.name, u.email
  from public.household_members m
  join public.households h on h.id = m.household_id
  join auth.users u        on u.id = m.user_id;
```

Two rows, both emails. That's the one-time bit; after that anyone signed in as
either of you sees the same recipes, weeks and lists, and nobody else can.

---

## D. What I need to finish the move

Send me:

1. The **Project URL**
2. The **publishable** (or **anon**) key

Both are safe to paste in chat — they're public by design and useless without a
signed-in session, thanks to the row-level security in the schema. Keep the
service_role key to yourself.

Then I'll rewrite the app's data layer against your live project and verify it
end to end: sign-in, recipes, week planning, the shopping list, realtime between
two devices, and importing your existing recipe box so nothing is lost.

### What changes in the app

- **Sync stops being poll-based.** Right now each phone checks every ten
  seconds. Supabase pushes changes down, so her ticking off milk shows on your
  phone in well under a second.
- **History becomes real.** Every week you plan is kept, and the schema already
  has views for "how often have we cooked this" and "when did we last have it".
  Once that data exists I can make the 🎲 builder skip anything you ate in the
  last two weeks.
- **The Google Sheets path is gone.** It was removed once Supabase was working;
  the Apps Script backend and its setup guide are no longer in this repo (they
  remain in git history if ever needed). Your JSON **Backup** button stays.
