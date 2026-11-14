# Player profiles

Profiles contain a name, card-art avatar and optional card-art playmat. The Profile page searches the existing printing/face gallery, shows the actual selected illustration and saves to the application's existing `app.sqlite`. Selection preserves the printing and face; another printing is never silently substituted. Missing local images remain placeholders under the normal local-artwork-only setting.

The name becomes the default for new games and room joins. A per-match nickname can still be supplied by the lobby. Changes apply to new games/rooms; they do not rename an already-running native player. Life is read only from XMage's `players[].life`, including Commander starting life and later changes. Profiles have no HP/life setting.

## Data and transport

`GET /profile` and `PUT /profile` use:

```json
{"name":"Planeswalker","avatar":null,"playmat":null}
```

An artwork value is `{oracleId,printingId,face,name}`. IDs are canonical UUIDs, face is an integer 0–9, names are bounded Unicode strings, and arbitrary URLs/extra fields are rejected. New saved references must resolve to the exact printing/face/Oracle in the local gallery and have an art crop. The service canonicalizes the card name. Previously saved identities can be retained during an offline name update; changing an image requires the ready index. Null/missing artwork clears that slot.

`ProfileStore` owns the singleton `player_profile` table. Writes use Storage's existing transactional WAL/full-synchronous connection. No deck, collection, artwork or settings table is reset by saving a profile.

Practice start sends `profile` at the top level. Room creation and join send the same public `profile`; the gateway retains it on the authenticated seat and forwards it with constructed/draft/paired-game seats. Native `players[].profile`, public room members, native draft players, replay participant metadata and future game seats preserve that identity. Avatar/playmat references are public presentation data, not hidden card permissions or seat credentials.

Bots retain their native name and receive `avatarCard:{name,portrait:true}` from a supplied deck cover, commander, or deck card. This is a portrait lookup hint with no hidden card instance ID and no fabricated Scryfall printing. Human-selected references remain exact printing/face identities.

## Frontend hooks

`require('app.profile').install(Model)` adds `loadProfile`, `showProfile`, `updateProfile`, `saveProfile`, `profileOptions`, `chooseProfileArt`, `clearProfileArt`, `resetProfileDraft`, `profileForPlayer`, and `profileArt`. `profileArt` uses the exact `/gallery/art` art-crop endpoint, respects foreground network preferences and maintains a bounded raster cache. Search/save callbacks are fenced against older openings/edits.

`app/profile_ui.lua` supplies `build(view,width,height)` for the existing themed Slab controls. The renderer uses the public player profile and native life. Avatar/playmat rendering is presentation only; card actionability, targeting and game rules remain native.

## Checks

- `service/tests/test_profiles.py`: temporary SQLite/real HTTP persistence, exact printing/back-face identity, invalid reference/URL/life rejection, preserved unrelated data and offline rename.
- `tests/profile_model.lua`: stale request/edit fencing, exact reference selection, save/reset/clear and opponent identity.
- `ProfileFixture`: native practice, multiple real humans and draft-seat projections, bot portrait fallback, input bounds and unchanged native starting life.
- Profile graphical and room HTTP reports distinguish actual Slab input from native production games. No default-user storage is used for acceptance.
