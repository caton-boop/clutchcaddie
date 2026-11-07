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
| `supabase/schema.sql` | Database for profiles, leaderboards and the Caddy Cup |

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
4. If your domain is not `clutchcaddy.com`, find and replace `clutchcaddy.com` in `index.html`,
   `robots.txt`, `sitemap.xml`, `privacy.html` and `terms.html`. Also replace the contact address
   `hello@clutchcaddy.com` with a real inbox.

## 3. Turn on profiles, leaderboards and the Caddy Cup (Supabase, free to start)

Until this step the game runs in preview mode: players can make a profile and post scores, but
everything is saved on their own device only.

1. Create an account at supabase.com and a new project (any region in the US is fine).
2. In the project, open SQL Editor > New query, paste all of `supabase/schema.sql`, and click Run.
   It is safe to run again later when the file changes.
3. Open Project Settings > API Keys. Copy the Project URL and the publishable key (`sb_publishable_...`).
   The older `anon` `public` key also works.
4. Paste both into `config.js`:
   ```js
   window.CC_CONFIG = {
     supabaseUrl: 'https://YOURPROJECT.supabase.co',
     supabaseAnonKey: 'sb_publishable_...',
     period: 'week'
   };
   ```
5. Commit the change. Vercel redeploys on its own and everything is live.

The publishable key is meant to be public. The tables are locked, and the key can only call these
functions, which do all the checking:

| Function | What it does |
|---|---|
| `create_player` | Makes a profile from a name (no email) and returns a player code like `CC-1A2B-3C4D-5E6F-7A8B` |
| `login_with_code` | Signs in on a new device with that code |
| `submit_score` | Posts a ranked daily or weekly score. Needs a profile. Keeps only the first post per board |
| `get_board` | One leaderboard, with ranks and Caddy Cup points |
| `get_caddy_cup` | Season standings |
| `get_player_stats` | The profile page: rank, points, wins, top 10s, averages, recent results |

**Profiles:** names are unique (ignoring case) and run through the blocked word list. Player codes
are stored hashed, so nobody (including you) can read them from the database. A lost code cannot be
recovered, and the game tells players to save it.

**Caddy Cup points** (worked out live from each board, so they update as more people play):
- Daily: 10 for posting, up to 90 more for the share of the field you beat, plus 50, 30 or 20 for 1st, 2nd or 3rd.
- Weekly 18: three times a daily.
- Seasons live in the `seasons` table. Season 1 runs Nov 1, 2026 to Mar 31, 2027. To add the next one:
  `insert into public.seasons (name, starts, ends) values ('Season 2', '2027-04-01', '2027-08-31');`

**Boards**
- Daily: `daily:YYYY-MM-DD` (US Eastern date), ranked by strokes, then clutch rating
- Weekly: `weekly:YYYY-MM-DD` (the Monday the week started), ranked by total to par, then rating
- Monthly: `monthly:YYYY-MM` if you switch `period` to `'month'`

**Moderation** (SQL Editor):
- Rename a player: `update public.players set name = 'NewName' where lower(name) = 'badname';`
  then `update public.scores set name = 'NewName' where name = 'BadName';`
- Remove a score: `delete from public.scores where board = 'daily:2026-11-06' and name = 'SomeName';`
- Block a word from names: `insert into public.blocked_words (w) values ('word');`

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
- Profiles use a player code instead of email, so a lost code means a lost profile. An optional
  email or Google/Apple sign-in could be added later for recovery.

## Costs

Domain about $12 a year. Vercel and Supabase are free at this size. Supabase Pro is $25 a month
if you outgrow the free tier.
