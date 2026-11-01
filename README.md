# Clay Tags bot

Everyone running Clay Client shows a **Clay Client User** tag. You pick accounts in Discord that get a custom name, and one account is the **OWNER** with a gold crown on its head.

## 1. Make the bot
1. https://discord.com/developers/applications → New Application → Bot tab → Reset Token (copy it).
2. Copy the Application ID from General Information.
3. OAuth2 → URL Generator → scopes `bot` + `applications.commands` → no permissions needed → open the link and add it to your server.

## 2. Run it
```
npm install
cp .env.example .env     # fill in DISCORD_TOKEN, CLIENT_ID, TAG_KEY (and GUILD_ID for instant commands)
npm start
```
It needs to be reachable from the internet (Railway, Render, Fly, a VPS). Open `https://YOUR-URL/health`; you should see `{"ok":true,...}`.
On Railway/Render add a volume and set `DATA_FILE=/data/data.json`, otherwise your tags reset every redeploy.

## 3. Hook up the script
In `CONFIG` at the top of Clay Client:
```lua
TagRelayUrl = "https://YOUR-URL",
TagRelayKey = "the same TAG_KEY from .env",
```
Then replace everything between the `CLAY TAGS` banner and the `PAGES` banner with `clay-tags-block.lua`.

## Commands (need Manage Server, or set ADMIN_IDS)
| Command | What it does |
|---|---|
| `/clay owner username` | OWNER tag + crown. Only one owner; the old one is cleared. |
| `/clay tag username text [color] [crown]` | Custom name. Color is a hex like `#ff66cc` or a name (gold, red, pink...). |
| `/clay remove username` | Back to a plain Clay Client User. |
| `/clay list` | Every custom tag. |
| `/clay online` | Who is running the script right now. |

## Notes
- Tags only show on people who are running the script with Clay Tags on, and only to other Clay Client users in the same Roblox server.
- Custom names and the crown are assigned only through Discord. The key lives inside the script, so treat it as "keeps randoms out", not as a real secret.
- The server sees each user's Roblox username and server id while Clay Tags is on.
