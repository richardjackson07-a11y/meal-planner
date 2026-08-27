# Sharing the meal planner with your wife

This connects both phones to **one Google Sheet you own**. Add something on her
phone and it shows up on yours within about ten seconds.

Nothing here costs money and nothing pauses for inactivity. Do this once, on a
computer — about ten minutes.

---

## 1. Make the spreadsheet

1. Go to <https://sheets.google.com> and create a **Blank spreadsheet**.
2. Name it something like `Meal Planner Data`.

Leave it empty. The script creates the tab and headers it needs the first time
it runs.

## 2. Add the script

1. In that spreadsheet, menu **Extensions → Apps Script**.
2. Delete whatever is in the `Code.gs` editor.
3. Open `apps-script/Code.gs` from this folder, copy all of it, paste it in.
4. Click the **save** icon (or Ctrl+S).

## 3. Deploy it as a web app

1. Top right, **Deploy → New deployment**.
2. Click the gear next to "Select type" and choose **Web app**.
3. Fill in:
   - **Description**: `meal planner`
   - **Execute as**: **Me** (your account)
   - **Who has access**: **Anyone**
4. Click **Deploy**.
5. Google will ask you to **Authorize access**. Pick your account. You'll hit a
   screen saying "Google hasn't verified this app" — that's expected, it's your
   own script. Click **Advanced**, then **Go to Meal Planner Data (unsafe)**,
   then **Allow**.
6. Copy the **Web app URL**. It ends in `/exec` and looks like:

   ```
   https://script.google.com/macros/s/AKfycb.....................­/exec
   ```

> **On "Who has access: Anyone"** — this has to be Anyone, because your phones
> call it without signing in to Google. The URL is long and unguessable, and the
> household code is a second lock: without the right code the script returns
> nothing. Treat the URL like a password and don't post it anywhere. It can only
> ever read and write this one spreadsheet.

## 4. Connect both phones

On each phone, open the meal planner and tap the **Solo** button in the top
right corner.

1. Paste the **web app URL**.
2. Type the same **household code** on both phones — anything you'll both
   remember, e.g. `jackson`. Lowercase, no spaces.
3. Tap **Connect**.

Do **your** phone first. It will upload your recipe box and become the
household list. When you connect her phone second, it will find the existing
household and ask:

- **OK** — use the household list on this phone *(this is the one you want)*
- **Cancel** — keep this phone's recipes too and add them to the household

The button in the corner turns green and reads **Shared**.

---

## How it behaves day to day

**Both of you can edit at the same time.** Every recipe, every planned night,
every checked box and every extra item is stamped with when it changed. When the
two phones sync, the newer edit wins *for that one item* — so if she ticks off
milk while you're adding paper towels, both survive. Neither phone overwrites
the other wholesale.

**It works without signal.** If the store has bad reception, everything keeps
working on the phone and syncs when you're back. The corner button shows
**Offline** while it can't reach the sheet.

**Updates arrive on a check, not instantly.** Each phone checks about every ten
seconds while the app is open, and immediately when you switch back to it. So
her additions land within a few seconds, not the same instant.

**Deleting works properly.** A deleted recipe stays deleted on both phones and
won't reappear on the next sync.

---

## Checking on it

- Open the spreadsheet any time to see the data. One row per household:
  `code`, `rev`, `updated`, `json`. `updated` tells you the last time either
  phone saved.
- To test the script is alive, paste your web app URL into a browser with
  `?action=ping` on the end. You should see `{"ok":true,...}`.
- **Backup** on the Recipes tab still works and still saves a file to that
  device. Worth doing occasionally — the sheet is the live copy, not an
  archive.

## If something goes wrong

**"Could not reach the web app"** — the URL must be the `/exec` one from the
deployment screen, not the `script.google.com/home/projects/...` editor address.

**Her phone shows an empty recipe box** — the household codes don't match.
They're case-insensitive but must otherwise be identical. Re-tap the corner
button and check the spelling on both.

**You changed the script** — Apps Script keeps serving the old version until you
redeploy. Use **Deploy → Manage deployments → edit (pencil) → Version: New
version → Deploy**. The URL stays the same.

**You want to start the shared list over** — delete that household's row in the
spreadsheet, then reconnect from the phone whose list you want to keep.
