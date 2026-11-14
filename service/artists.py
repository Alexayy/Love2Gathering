"""Small reviewed registry, never URLs inferred from an illustrator's name.

Links were opened on 2026-11-13. The source is the artist's own site, including
outbound shop/service links published there. Unlisted artists have no links.
"""
CHECKED = "2026-11-13"
REGISTRY = {
    "ryan pancoast": [
        ("Artist website", "https://www.ryanpancoast.com/", "website", "https://www.ryanpancoast.com/about"),
        ("Print shop", "https://www.inprnt.com/gallery/rpancoast/", "shop", "https://www.ryanpancoast.com/about"),
        ("Painting tutorials", "https://rpancoast.gumroad.com/", "services", "https://www.ryanpancoast.com/about"),
    ],
    "karl kopinski": [
        ("Artist website / shop", "https://karlkopinski.com/", "shop", "https://karlkopinski.com/"),
    ],
    "kai carpenter": [
        ("Illustration website", "https://www.kaicarpenterart.com/", "website", "https://www.kaicarpenterart.com/"),
        ("Fine art / commissions", "https://www.kaithomascarpenter.com/", "services", "https://www.kaicarpenterart.com/"),
    ],
    "jason felix": [
        ("Artist website", "https://www.jasonfelix.com/", "website", "https://www.jasonfelix.com/info"),
        ("Freelance / contact", "https://www.jasonfelix.com/info", "services", "https://www.jasonfelix.com/info"),
    ],
    "scott m. fischer": [
        ("Artist website", "https://www.scottmfischer.com/", "website", "https://www.scottmfischer.com/"),
    ],
    "svetlin velinov": [
        ("Artist portfolio", "https://velinov.artstation.com/", "website", "https://velinov.artstation.com/"),
        ("Art print shop", "https://www.inprnt.com/gallery/velinov/", "shop", "https://www.behance.net/velinov"),
        ("Freelance profile", "https://www.behance.net/velinov", "services", "https://www.behance.net/velinov"),
    ],
    "lie setiawan": [
        ("Artist portfolio / contact", "https://liesetiawan.artstation.com/", "website", "https://liesetiawan.artstation.com/projects"),
    ],
    "eric deschamps": [
        ("Artist website", "https://www.ericdeschamps.com/", "website", "https://www.ericdeschamps.com/"),
        ("Magic art / proofs shop", "https://www.ericdeschamps.com/purchase", "shop", "https://www.ericdeschamps.com/"),
        ("Card signing service", "https://www.ericdeschamps.com/card-signings/", "services", "https://www.ericdeschamps.com/about"),
    ],
    "chase stone": [
        ("Artist portfolio / contact", "https://www.chasestoneart.com/contact", "services", "https://www.chasestoneart.com/contact"),
        ("Artist store", "https://www.chasestoneart.com/store", "shop", "https://www.chasestoneart.com/contact"),
    ],
}


def artist_links(name):
    return [{"label": label, "url": url, "kind": kind, "source": source,
             "verifiedAt": CHECKED} for label, url, kind, source in REGISTRY.get(str(name or "").casefold(), ())]
