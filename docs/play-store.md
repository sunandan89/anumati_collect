# Publishing on Google Play: click by click

No installs and no terminal. You never paste a key anywhere: the upload key is generated on a GitHub runner and saved straight into GitHub Secrets.

## 1. Play Console account (once)
1. Go to **play.google.com/console** → sign in with the Google account the organisation will own.
2. Choose **Organisation** account (not Personal). Personal accounts must run a 14-day closed test with 12 testers first.
3. Enter the organisation's **D-U-N-S number** (free from Dun & Bradstreet; can take 1–2 weeks), pay the one-time US$25 fee, finish identity verification.

## 2. Create the upload key (once, about 2 minutes)
1. GitHub → your profile picture → **Settings** → **Developer settings** → **Fine-grained tokens** → **Generate new token**.
2. Name `anumati-collect-secrets`, expiry **7 days**, **Only select repositories** → `anumati_collect`.
3. **Repository permissions** → **Secrets** → **Read and write** → **Generate token**. Copy it (it's shown once).
4. Open **github.com/sunandan89/anumati_collect** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Name `SECRETS_WRITER_TOKEN`, paste the token → **Add secret**.
5. **Actions** tab → **Create Play upload key** → **Run workflow** → type `CREATE` → **Run workflow**. Wait for the green tick.
6. Back in **Settings** → **Secrets and variables** → **Actions**: you'll see four new `ANDROID_…` secrets. Delete `SECRETS_WRITER_TOKEN`. Then delete the token itself under Developer settings.

From now on every CI run also builds a signed **Play bundle** (`anumati-collect-play-bundle-…` under the run's Artifacts).

If the upload key is ever lost, Play Console lets you request an upload key reset. The app signing key itself is held by Google (Play App Signing), so the app never loses its identity.

## 3. Create the app in Play Console
1. **Create app** → name **Anumati Collect**, default language **English (India)**, **App**, **Free** → accept the declarations → **Create app**.
2. **Test and release** → **Internal testing** → **Create new release**. Accept **Play App Signing**.
3. Upload the `.aab` from the latest CI run's artifacts (unzip the artifact first; the file is `app-release.aab`). Release name e.g. `1.0.0 (build 12)` → **Save** → **Review release** → **Start rollout**.
4. **Testers** tab → create an email list with your field team → copy the opt-in link and share it.

## 4. Store listing and policy forms
- **Privacy policy**: `https://sunandan89.github.io/anumati/privacy.html`
- **App access**: "All or some functionality is restricted" → give a fictional test user on a test site.
- **Ads**: No ads.
- **Content rating**: questionnaire → Utility; no objectionable content.
- **Target audience**: 18 and over (the users are field workers).
- **Data safety**:
  - Collects: Personal info → **Name**, **Phone number**; **Audio** → voice recordings; **Photos**.
  - Purpose: **App functionality**. Not shared with third parties (data goes to the organisation's own server).
  - **Encrypted in transit**: Yes. **Users can request deletion**: Yes (through the organisation).
- **Permissions**: Camera (thumbprint and document photos), Microphone (voice consent). No SMS permission: the app opens the SMS app pre-filled.

## 5. Updates
Every merge to `main` builds a new bundle. Upload it as a new release in the same track. To force old phones to update, raise **Minimum App Version** in your site's **Mobile Configuration**.
