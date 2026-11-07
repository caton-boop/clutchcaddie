# Clutch Caddie website

Everything needed to put Clutch Caddie on a real domain. It is a static site (no build step), plus one
database script for the leaderboards.

## What is in this folder

| File | What it does |
|---|---|
| `index.html` | The whole game |
| `config.js` | Your settings: leaderboard keys and weekly or monthly challenge |
| `privacy.html`, `terms.html`, `404.html` | Legal pages (drafts) and the not-found page |
| `manifest.webmanifest`, `icon-*.png`, `apple-touch-icon.png`, `favicon.*` | App icon and "Add to Home Screen" support |
| `og.png` | The preview image when someone shares your link |
| `robots.txt`, `sitemap.xml` | Search engine basics |
| `vercel.json`, `_headers` | Host settings (Vercel uses the first, Netlify and Cloudflare Pages the second) |
| `supabase/schema.sql` | Leaderboard database: tables, rules and the two functions the game calls |

## 1. Put it online (about 10 minutes)

**Option A: Vercel with GitHub (recommended, auto-deploys every change)**
1. Create a GitHub account and a new repository, for example `clutch-caddie`.
2. Upload every file in this folder to the repository (Add file > Upload files, then commit).
3. Sign in to vercel.com with GitHub, click Add New > Project, pick the repository, leave all settings as they are and click Deploy.
4. You get a working link like `clutch-caddie.vercel.app` right away.

**Option B: no GitHub**
Go to app.netlify.com/drop and drag this whole folder onto the page. Done.

## 2. Connect your domain

1. Buy the domain (Cloudflare Registrar or Namecheap, about $10 to $15 a year for a .com).
2. In Vercel: Project > Settings > Domains > add `yourdomain.com` and `www.yourdomain.com`.
3. Vercel shows one or two DNS records. Add them at your registrar. HTTPS turns on automatically.
4. If your domain is not `clutchcaddie.com`, find and replace `clutchcaddie.com` in `index.html`,
   `robots.txt`, `sitemap.xml`, `privacy.html` and `terms.html`. Also replace the contact address
   `hello@clutchcaddie.com` with a real inbox.

## 3. Turn on the live leaderboards (Supabase, free to start)

Until this step the game runs in preview mode: players can post names, but scores are saved on their
own device only.

1. Create an account at supabase.com and a new project (any region in the US is fine).
2. In the project, open SQL Editor > New query, paste all of `supabase/schema.sql`, and click Run.
3. Open Project Settings > API. Copy the Project URL and the `anon` `public` key.
4. Paste both into `config.js`:
   ```js
   window.CC_CONFIG = {
     supabaseUrl: 'https://YOURPROJECT.supabase.co',
     supabaseAnonKey: 'eyJhbGciOi...',
     period: 'week'
   };
   ```
5. Commit the change. Vercel redeploys on its own and the leaderboards are live.

The anon key is meant to be public. The database only lets it call two functions: `submit_score` and
`get_board`. Those functions check the board date, the score range and the name, and keep only the
first score each player posts on each board.

**Boards**
- Daily: `daily:YYYY-MM-DD` (US Eastern date), ranked by strokes, then clutch rating
- Weekly: `weekly:YYYY-MM-DD` (the Monday the week started), ranked by total to par, then rating
- Monthly: `monthly:YYYY-MM` if you switch `period` to `'month'`

**Moderation:** in the SQL Editor, `delete from public.scores where name = 'BadName';`. To block a word
from names, `insert into public.blocked_words (w) values ('word');`.

## 4. Weekly challenge settings

- `period: 'week'` resets Monday at midnight ET. `period: 'month'` resets on the 1st.
- The challenge rotation is the `WEEKLY_ROTATION` list in `index.html` (search for it). Right now it
  holds one round, `'wk86'` (Jack Nicklaus, 1986 Masters final round). Add new 18-hole round ids to
  the list and they rotate in order.
- Weekly progress saves on the player's device after every shot, so they can stop and come back.

## 5. Test it on your own computer

In this folder run `python3 -m http.server 8000` and open http://localhost:8000. The `/privacy` and
`/terms` links need the host's clean URLs, so open `privacy.html` directly when testing locally.

## Before you announce it

- [ ] Domain connected and HTTPS working
- [ ] Contact email replaced in `privacy.html` and `terms.html`
- [ ] Privacy policy and terms reviewed (they are plain-language drafts, not legal advice)
- [ ] Supabase keys in `config.js`, one test score posted from a phone and a laptop
- [ ] Share preview checked (paste your link into a text message or the opengraph.xyz checker)
- [ ] Analytics added if you want it (Plausible or Google Analytics), and the privacy page updated
- [ ] When ads go in: AdSense approval, `ads.txt` added to this folder, cookie consent turned on

## Known limits (fine for launch, worth fixing as you grow)

- Shot luck is calculated in the browser, so a determined cheater could post a fake score. The
  database blocks impossible scores and repeat posts. The full fix is moving shot results to a
  Supabase Edge Function so the server decides every shot.
- Players are identified by a random ID saved in their browser. Clearing site data or switching
  devices gives them a new ID. Adding sign-in later (Supabase Auth: email link or Google/Apple)
  fixes that and lets streaks follow people across devices.

## Costs

Domain about $12 a year. Vercel and Supabase are free at this size. Supabase Pro is $25 a month
if you outgrow the free tier.
