# AdMob setup (to earn from real ads)

The game ships with **Google's test ads**. They show and behave like real
ads but pay nothing. Nothing real is used until you do the steps below.

## 1. AdMob account and ad units
1. Create an AdMob account (admob.google.com) and add the app (Android,
   package `com.ollie81.villagethatremembers`).
2. Create three ad units: **Rewarded**, **Interstitial**, **Banner**.
3. Note the **App ID** (`ca-app-pub-…~…`) and the three unit IDs (`ca-app-pub-…/…`).

## 2. Put the IDs in GitHub secrets (never in the code)
Repository → Settings → Secrets and variables → Actions → New secret:

| Secret | Value |
|---|---|
| `ADMOB_APP_ID` | your App ID |
| `ADMOB_REWARDED_ID` | rewarded unit ID |
| `ADMOB_INTERSTITIAL_ID` | interstitial unit ID |
| `ADMOB_BANNER_ID` | banner unit ID |

CI writes them into the build (`config/admob.cfg` and the Android manifest).
**Debug builds always use test ads**, even with secrets set. Real ads only
appear in a **release** build (that needs a release signing key, which is not
set up yet).

## 3. Privacy and consent
- In AdMob → Privacy & messaging, create a **GDPR** (EEA/UK) consent
  message. The game asks Google's consent tool (UMP) at start-up and shows it
  where required.
- Publish a privacy policy and link it in Google Play.
- Add `app-ads.txt` to your developer website (AdMob shows the line to add).

## 4. Audience (Families policy)
The game is set up as **general audience** (not made for children): ads are
limited to rating PG. If you put it in Google Play's Families programme,
add to `config/admob.cfg` (or ask for it to be wired to a secret):

```
[audience]
child_directed=true
```

Ads are then tagged child-directed and limited to rating G.

## 5. Server-side verification (optional)
Each rewarded ad sends a random install id and a one-time reward token.
To verify rewards on a server, set an SSV callback URL on the rewarded unit
in AdMob. There's no server today; rewards are checked on the phone (paid
only after Google's SDK confirms the ad was watched, and only once).

## Limits built in
- Rewarded: up to 10 a day, 1 minute apart, reward shown before watching.
- Interstitial: not in the first 10 minutes, then at most one every
  10–15 minutes, only when leaving a house or waking up; never while
  building, fighting, riding, furnishing, talking, or during a raid.
- Banner: only while the Shop is open, below the window.
- No app-open ads.
