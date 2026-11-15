"""Deck construction checks against the supplied oracle snapshot.

Rules source: MagicCompRules 20260807.pdf, 100.2a, 100.4a, 101.1,
903.3 and 903.5. Runtime play and final deck acceptance remain XMage's job.
"""
from collections import Counter
import re
from deck_printings import validate_printings
from formats import profile as format_profile

NUMBERS = {word: value for value, word in enumerate(("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"))}
BASIC_LAND_COLORS = {"Plains": "W", "Island": "U", "Swamp": "B", "Mountain": "R", "Forest": "G"}


def copy_limit(card, commander=False):
    if "Basic" in (card.get("type_line") or "").split(" — ")[0].split():
        return None
    text = card.get("oracle_text") or ""
    if re.search(r"A deck can have any number of cards named [^.]+\.", text):
        return None
    match = re.search(r"A deck can have up to ([a-z]+|\d+) cards named [^.]+\.", text)
    if match:
        number = match.group(1)
        return int(number) if number.isdigit() else NUMBERS.get(number, 1 if commander else 4)
    return 1 if commander else 4


def commander_eligible(card):
    text = card.get("oracle_text") or ""
    if "can be your commander" in text:
        return True
    types = (card.get("type_line") or "").split(" // ")[0]
    front = (card.get("card_faces") or [card])[0]
    return "Legendary" in types and ("Creature" in types or "Vehicle" in types or ("Spacecraft" in types and front.get("power") is not None and front.get("toughness") is not None))


def pair_compatible(cards):
    if len(cards) != 2:
        return False
    a, b = cards
    ta, tb = a.get("oracle_text") or "", b.get("oracle_text") or ""
    na, nb = a["name"], b["name"]
    if "Choose a Background" in ta and "Background" in (b.get("type_line") or ""):
        return commander_eligible(a)
    if "Choose a Background" in tb and "Background" in (a.get("type_line") or ""):
        return commander_eligible(b)
    if "Doctor's companion" in ta and all(word in (b.get("type_line") or "") for word in ("Time Lord", "Doctor")):
        return commander_eligible(a) and commander_eligible(b)
    if "Doctor's companion" in tb and all(word in (a.get("type_line") or "") for word in ("Time Lord", "Doctor")):
        return commander_eligible(a) and commander_eligible(b)
    if not commander_eligible(a) or not commander_eligible(b):
        return False
    # Partner with uses only its named partner; generic Partner and Friends
    # forever each pair within their own keyword family.
    if re.search(r"Partner with " + re.escape(nb) + r"(?:\s|\(|$)", ta) and re.search(r"Partner with " + re.escape(na) + r"(?:\s|\(|$)", tb):
        return True
    for keyword in ("Partner", "Friends forever"):
        if re.search(r"(?:^|\n)" + keyword + r"(?:\s*\(|\s*$)", ta) and re.search(r"(?:^|\n)" + keyword + r"(?:\s*\(|\s*$)", tb):
            return True
    return False


def validate(deck, catalog):
    errors, warnings = [], []
    fmt = deck["format"].lower()
    profile = format_profile(deck['format']);snapshot_key=profile['snapshotKey'];snapshot_checked=snapshot_key is not None
    commander = fmt == "commander"
    counts = {zone: sum(entry["count"] for entry in deck[zone]) for zone in ("main", "sideboard", "commander")}
    def problem(code, message, names=()):
        errors.append({"code": code, "message": message, "cards": list(names)})
    cards, combined = {}, Counter()
    for zone in ("main", "sideboard", "commander"):
        for entry in deck[zone]:
            card = catalog.get(name=entry["name"])
            if card is None:
                problem("unknown_card", "Unknown card: " + entry["name"], [entry["name"]])
                continue
            # Face aliases resolve for artwork, but deck lists use the full
            # English oracle name so another face cannot bypass copy limits.
            canonical = card["name"]
            entry["name"] = canonical
            cards[canonical] = card
            combined[canonical] += entry["count"]
    for name, count in combined.items():
        card = cards[name]
        legality=card.get('legalities',{}).get(snapshot_key)if snapshot_checked else None
        if snapshot_checked and legality not in ("legal", "restricted"):
            problem("format_legality", name + " is not legal in " + deck["format"] + ".", [name])
        limit = copy_limit(card, commander)if snapshot_checked else None
        if limit is not None and count > limit:
            problem("copy_limit", f"{name}: {count} copies; maximum {limit} across the deck and sideboard.", [name])
    if commander:
        if counts["main"] + counts["commander"] > 100:
            problem("commander_size", "Commander decks cannot contain more than 100 cards including commanders.")
        if counts["sideboard"]:
            problem("commander_sideboard", "Commander does not use a sideboard.")
        command_cards = [cards.get(entry["name"]) for entry in deck["commander"] for _ in range(entry["count"]) if cards.get(entry["name"])]
        if len(command_cards) > 2:
            problem("commander_count", "Choose one commander, or a legal pair of commanders.")
        elif len(command_cards) == 2 and not pair_compatible(command_cards):
            problem("commander_pair", "These cards cannot be commanders together.", [c["name"] for c in command_cards])
        elif len(command_cards) == 1 and not commander_eligible(command_cards[0]):
            problem("commander_type", "This card cannot be your commander.", [command_cards[0]["name"]])
        identity = set().union(*(set(card.get("color_identity") or []) for card in command_cards)) if command_cards else set()
        if command_cards:
            for name, card in cards.items():
                illegal = set(card.get("color_identity") or []) - identity
                subtypes = (card.get("type_line") or "").split(" — ")[1:]
                for land, color in BASIC_LAND_COLORS.items():
                    if any(land in types.split() for types in subtypes) and color not in identity:
                        illegal.add(color)
                if illegal:
                    problem("color_identity", name + " is outside your commanders' color identity.", [name])
        complete = counts["main"] + counts["commander"] == 100 and counts["commander"] in (1, 2)
        if not complete:
            warnings.append({"code": "draft_size", "message": "Draft: Commander needs exactly 100 cards including one commander or a legal pair.", "cards": []})
    else:
        if counts["commander"]:
            problem("unexpected_commander", deck["format"] + " does not use a commander zone.")
        if snapshot_checked and counts["sideboard"] > 15:
            problem("sideboard_size", "A constructed sideboard may contain at most 15 cards.")
        complete = counts["main"] >= profile['minimum']
        if not complete:
            warnings.append({"code": "draft_size", "message": "Draft: the native validator's reported minimum is "+str(profile['minimum'])+" main-deck cards.", "cards": []})
    if not snapshot_checked:
        warnings.append({'code':'native_format_required','message':'This snapshot does not encode '+profile['label']+' legality. XMage must check card eligibility, copies, points, sideboards and full construction rules.','cards':[]})
    cover = deck.get("coverCard")
    if cover:
        cover_card = catalog.get(name=cover)
        if not cover_card:
            problem("unknown_cover", "Unknown cover card: " + cover, [cover])
        else:
            deck["coverCard"] = cover_card["name"]
    validate_printings(deck, catalog, problem)
    return {"saveAllowed": not errors, "playable": complete and not errors, "valid": complete and not errors and snapshot_checked,
            "draft": not complete, "errors": errors, "warnings": warnings, "counts": counts,
            'formatId':profile['id'],'minimum':profile['minimum'],'snapshotLegalityChecked':snapshot_checked,'snapshotFilterAvailable':snapshot_checked,'nativeValidationRequired':True,
            "source": "Scryfall snapshot 2026-09-22; XMage performs final play validation."}
