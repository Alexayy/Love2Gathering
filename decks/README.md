# Starter decks

Twenty editable decks for rules-engine testing and casual play. These are curated starter lists, not claims about tournament metagame strength.

| Format | Decks |
| --- | --- |
| Modern | Boros Burn, Green Tron, Merfolk, Azorius Control, Jund Midrange |
| Standard | White Lifegain, Blue Tempo, Black Midrange, Red Aggro, Green Stompy |
| Pioneer | **Izzet Phoenix**, **Lotus Field Combo**, Rakdos Midrange, White Humans, Azorius Spirits |
| Commander | Giada Angels, Talrand Spells, Ayara Devotion, Krenko Goblins, Goreclaw Stompy |

Modern, Standard and Pioneer lists have 60 main-deck cards and 15 sideboard cards. Commander lists have one commander plus 99 cards, use normal Commander singleton and color-identity rules, and are intended for one opponent in the client. They are not Duel Commander lists: cards such as Sol Ring remain included under normal Commander legality.

`library.json` is the menu manifest. Each `<id>.json` contains the complete deck, with independent `commander`, `main` and `sideboard` arrays of `{ "name": "Card name", "count": 4 }`. Double-faced, adventure and split cards retain their complete Scryfall name. The engine adapter resolves these names to the matching XMage card implementation.

Regenerate the shipped JSON lists with:

```sh
python3 decks/build_library.py
```

Validate the library with:

```sh
python3 decks/validate_library.py
```

The validator checks 5 lists per format, main-deck and sideboard sizes, commander count and type, maximum copies across all zones, format legality in the supplied September 22, 2026 Scryfall bulk snapshot, XMage implementation-class availability and Commander color identity. It uses the application's local catalog when available; otherwise it streams the bulk source into the compact `card-reference.json` cache. `--refresh` rebuilds that cache. The result is written to `validation-report.json`.

Validation on November 12, 2026: **20 decks, 506 distinct card names, zero validation errors**. The current [Wizards banned and restricted list](https://magic.wizards.com/en/banned-restricted-list) was also reviewed when choosing these cards; none of the selected format/card combinations appears on that list. Standard card selection was checked against [Wizards' Standard format page](https://magic.wizards.com/en/formats/standard). Future bans and rotation require refreshing legality data and reviewing the lists. A source-class check proves implementation availability; actual in-game decisions and rules remain XMage's responsibility.

The decks cover combat, targeting, counters, planeswalkers, library search, tokens, sacrifice, mana abilities, cost reduction, spell copying, triggered abilities and the stack. Phoenix and Lotus Field are deliberately included as more demanding automation cases. XMage's general-purpose AI may pilot intricate combo decks less effectively than simpler combat decks.

The actual bridge load check is separate from the source-data validator. With an isolated XMage bridge running on port 17372, run:

```sh
python3 decks/test_engine_library.py
```

This replaces the active session on that test bridge. The successful `engine-load-report.json` records **20/20** decks accepted by XMage's actual format validators and instantiated for both the human and AI player, with opening hands, library counts and Commander command zones checked. Opponent hands remain hidden. This checks startup; it does not claim that the AI pilots every archetype optimally.
