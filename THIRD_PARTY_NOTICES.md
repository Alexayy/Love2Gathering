# Third-party notices and usage rights

Reviewed 2026-11-15. This inventory distinguishes the project's license from
the licenses and unverified rights of material it includes or references.
It is not a certification that every contemplated distribution is permitted.

## Project license and unofficial status

Project-authored code and documentation are licensed under [MIT](LICENSE).
That license permits use, modification and redistribution while retaining
its notice, and disclaims warranty. It does not relicense other people's
fonts, music, artwork, card content, marks or dependencies.

Love: 2 Gathering is independent and unofficial. It is not affiliated with,
sponsored, approved or endorsed by Wizards of the Coast or Hasbro. Magic:
The Gathering, related card content and marks remain the property of Wizards
of the Coast LLC and other applicable rights holders.

### Wizards policy reference

The [Fan Content Policy](https://company.wizards.com/en/legal/fancontentpolicy)
requires free access and an unofficial notice, retains restrictions and
reserves takedown rights. Section 4 says: “Don’t use Wizards’ IP in other games.”
The policy is not a blanket software/content license. Uses outside its scope
require separate permission. Read it together with the
[Wizards terms](https://company.wizards.com/en/legal/terms).

Neither this notice, private hosting, free sharing nor a promise to remove
material establishes a missing permission. Card images supplied through a
provider or cached locally retain their owners' rights. No fair-use
determination or legal approval is asserted here.

## Retained software, fonts and assets

| Component | Retained terms and source |
| --- | --- |
| XMage | MIT, copyright 2010 betasteward@gmail.com and contributors. Complete notice: [licenses/XMage-MIT.txt](licenses/XMage-MIT.txt). [Pinned source](https://github.com/magefree/mage/tree/c5a5215fa086f487c793627446d5d27e81dfbc97); the submodule is not relicensed by this project. |
| Slab | MIT, copyright 2019–2021 Love2D Community. Complete notice extracted unchanged from its retained source header: [licenses/Slab-MIT.txt](licenses/Slab-MIT.txt). [Upstream](https://github.com/flamendless/Slab). Modified source headers remain intact. |
| Kenney | CC0 1.0. Notices remain in `assets/kenney/ui/`, `theme/`, `particles/` and `runtime/licenses/`. [Support / usage](https://kenney.nl/support); [assets](https://kenney.nl/assets). See exact provenance and contributor names in [the pack catalog](assets/KENNEY_CATALOG.md) and retained notices. Kenney's logo is not licensed as project branding. |
| Mana | Prepared font: SIL OFL 1.1; [complete OFL](assets/keyrune/OFL.txt), [upstream notice](assets/keyrune/LICENSE-mana.md). [Source](https://github.com/andrewgioia/mana). Underlying mana/tap/type images remain Wizards copyright. CSS/LESS/Sass use MIT; these terms do not grant trademark rights. |
| Keyrune | Prepared font: SIL OFL 1.1. Upstream non-font icons/code: GPL 3.0. [Retained notice](assets/keyrune/LICENSE-keyrune.md), [source](https://github.com/andrewgioia/keyrune). Underlying set symbols remain Wizards trademarks. `assets/icons/thb.png` is font-rendered U+E961, documented in [its provenance](assets/icons/README.txt); no project ownership or independent marketing grant is claimed. |
| DejaVu Sans / Bold | Bitstream Vera font license, copyright 2003 Bitstream Inc.; DejaVu changes public domain. [Retained full notice](assets/fonts/LICENSE-DejaVu.txt); [source](https://dejavu-fonts.github.io/). The separate Debian packaging stanza in the notice does not relicense the font binary. |
| Roboto in Slab | The retained `lib/Slab/Internal/Resources/Fonts/Roboto-Regular.ttf` identifies Google copyright 2011 and Apache 2.0. [Apache text](licenses/Apache-2.0.txt), [legacy source](https://github.com/googlefonts/roboto-2). This concerns the supplied older font, not every current Roboto distribution. |
| Music Loop Bundle | CC0 1.0, Abstraction / Benjamin Burnes, Abstraction Music and Tallbeard Studios. [Original notice](assets/audio/music-loop-bundle-2026-q2/_LICENSE.txt); [bundle](https://tallbeard.itch.io/music-loop-bundle). All retained tracks keep that notice. Kenney sound effects have their own notices. |
| MTGJSON preconstructed metadata | MIT, copyright 2018–present Zach Halpern. [Retained notice](decks/preconstructed/LICENSE-MTGJSON.txt); [official license](https://mtgjson.com/license/). Underlying Magic names, text, illustrations and marks are not transferred to this project. |
| Scryfall references | [Provider](https://scryfall.com/), [API documentation](https://scryfall.com/docs/api). Source metadata and exact artist/printing references are retained; access is not an ownership or unrestricted redistribution grant for card imagery. |

### Owner-supplied material with unverified redistribution rights

The following remain included at the project owner's explicit request for
private use and sharing installers with friends:

- `assets/fonts/Beleren2016-Bold.ttf`: design credited to Delve Fonts / Delve
  Withrington for Wizards / Hasbro. [Designer credit](https://delvefonts.com/custom/beleren/).
  No separate redistribution license was supplied.
- `assets/card-backs/classic-magic.jpg`: supplied as `default-card-back.jpg`;
  contains Magic / Wizards imagery and marks. No separate license supplied.
- `assets/card-backs/mystic-eye.png`: supplied as `r4ZBhRX.png`; creator and
  redistribution permission have not been verified.

Their original bytes and [provenance](assets/card-backs/provenance.json) are
retained. They are not Kenney/CC0 and are not covered by the project MIT grant.
The owner's intended sharing scope does not establish rights-holder approval.
[Removal/contact policy](CREDITS.md#owner-supplied-material-and-removal-requests)
applies; identified material will be removed from future packages on a
substantiated request by its rights holder.

## Runtime and Java dependencies

Installed packages preserve upstream notices in their `licenses/`, runtime
legal directories, Python wheel license directories and retained JARs. Linux
system runtimes also carry distribution notices. The table below is an
inventory, not a replacement for their full license texts or source duties.

| Runtime / library | License and source |
| --- | --- |
| LÖVE 11.5 | zlib for LÖVE itself; the [complete 11.5 notice](https://github.com/love2d/love/blob/11.5/license.txt) includes its separate ENet, FreeType, LuaJIT/LuaSocket, codecs, OpenAL and other dependency notices. Preserve the runtime distribution's full notices. |
| CPython | PSF License 2 and incorporated historical/component notices; [Python 3.13 license](https://docs.python.org/3.13/license.html). Windows embeds Python 3.13.11; other platforms use their installed runtime. |
| Pillow 13 | MIT-CMU main grant, Secret Labs AB; Fredrik Lundh and contributors; Jeffrey “Alex” Clark and contributors. [Exact version license](https://github.com/python-pillow/Pillow/blob/13.0.0/LICENSE). Preserve all wheel `*.dist-info/licenses/` files, including native-codec notices. |
| Temurin / OpenJDK 21 | GPL 2 with Classpath Exception plus Assembly Exception and component notices; [Temurin](https://projects.eclipse.org/projects/adoptium.temurin), [licensing FAQ](https://adoptium.net/docs/faq/). Retain `legal/<module>/` and applicable source-availability obligations; no MIT grant is claimed for this runtime. |
| Flatpak native support | Includes libmodplug, OpenResty LuaJIT and libtheora with public-domain, MIT and BSD-family notices as applicable. Complete distribution copyright files are retained; the Freedesktop runtime supplies its own components independently. |
| Apache-family Java dependencies | Commons Lang 3.18.0, Error Prone annotations 2.36.0, Guava 33.4.8-jre / failureaccess 1.0.3 / listenablefuture empty shim, Gson 2.13.2, J2ObjC annotations 3.0.0, JBoss Common Core 2.5.0.Final, JSpecify 1.0.0, PrettyTime 4.0.6.Final, reload4j 1.2.22 and sqlite-jdbc 3.47.2.0 have Apache 2.0 grants and applicable additional notices. Sources: [ASF](https://commons.apache.org/proper/commons-lang/), [Guava](https://github.com/google/guava), [Gson](https://github.com/google/gson), [reload4j](https://github.com/qos-ch/reload4j), [SQLite JDBC](https://github.com/xerial/sqlite-jdbc). |
| Other permissive Java dependencies | jsoup 1.21.2: MIT ([notice](https://jsoup.org/license)); ORMLite core/JDBC 5.7: ISC ([source](https://ormlite.com/)); protobuf-java 3.25.8: BSD 3-clause ([source](https://github.com/protocolbuffers/protobuf)); SLF4J API/reload4j 2.0.17: MIT ([notice](https://www.slf4j.org/license.html)); concurrent 1.3.4: public-domain release ([Doug Lea source](https://gee.cs.oswego.edu/dl/classes/EDU/oswego/cs/dl/util/concurrent/intro.html)). |
| H2 1.4.197 | MPL 2.0 or EPL 1.0 in the supplied artifact's POM; [version source](https://github.com/h2database/h2database/tree/version-1.4.197). |
| Legacy LGPL Java dependencies | JBoss Logging SPI 2.1.2.GA / Remoting 2.5.4.SP5 inherit LGPL 2.1; JBoss Serialization 4.2.2.GA and Trove 1.0.2 have LGPL-family upstream statements with incomplete exact local notices. Sources: [JBoss Logging](https://github.com/jboss-logging/jboss-logging), [Remoting](https://github.com/jboss-remoting/jboss-remoting), [Serialization](https://serialization.jboss.org/downloads), [Trove 1.0.2](https://sourceforge.net/projects/trove4j/files/trove/archived/1.0.2/). These licenses have obligations beyond attribution, including applicable source/replacement rights. |

### Remaining legacy notice gaps

`jspf-core-0.9.1.jar` contains JSPF, shaded jcores and ClassWorlds code without
complete embedded notices. Archived primary metadata identifies the
[JSPF project](https://storage.googleapis.com/google-code-archive/v2/code.google.com/jspf/project.json)
and [jcores project](https://storage.googleapis.com/google-code-archive/v2/code.google.com/jcores/project.json)
as BSD, but the exact shipped version and shaded components' full grants are
not yet verified. No specific BSD variant is asserted for the whole JAR.

Some legacy LGPL artifacts likewise lack complete exact-version notices or
corresponding-source material in the retained dependency set. Links alone
are not represented as satisfying every copyleft redistribution obligation.
Those gaps must be resolved for a distribution that requires their complete
compliance evidence. None of the project MIT notice, credits or removal
promise cures an absent third-party grant or unmet license condition.

Keep the original notices and source provenance when sharing a package.
Do not remove card copyright/artist notices, infer permissions from a CDN, or
relabel a supplied asset as project-owned. Rights holders can use the
[maintainer/removal contact](CREDITS.md#owner-supplied-material-and-removal-requests).
