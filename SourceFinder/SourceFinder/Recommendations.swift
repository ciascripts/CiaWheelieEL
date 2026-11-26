import Foundation

/// A hand-picked source shown on Browse and Discover.
/// Every URL here was checked to return a valid source.
struct RecommendedSource: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case official, tweaks, emulators, tools, collections, jailbreak

        var id: String { rawValue }

        var title: String {
            switch self {
            case .official: return "Official Stores"
            case .tweaks: return "Tweaked Apps"
            case .emulators: return "Emulators & Games"
            case .tools: return "Tools & Utilities"
            case .collections: return "Big Collections"
            case .jailbreak: return "Jailbreaks (iOS 13–14)"
            }
        }

        var footnote: String? {
            switch self {
            case .tweaks: return "Modified versions of popular apps, made by third parties rather than the original developers."
            case .jailbreak: return "Only for older iOS versions."
            default: return nil
            }
        }
    }

    let name: String
    let url: String
    let blurb: String
    let category: Category
    var keywords: [String] = []

    var id: String { url }

    /// Folded text that searches match against.
    var searchText: String {
        TextNormalizer.fold(([name, blurb] + keywords).joined(separator: " "))
    }
}

enum Recommendations {
    static let all: [RecommendedSource] = [
        // Official stores
        RecommendedSource(name: "AltStore", url: "https://apps.altstore.io",
                          blurb: "Delta, Clip and AltStore itself, from Riley Testut.",
                          category: .official, keywords: ["delta", "clip", "emulator", "riley testut"]),
        RecommendedSource(name: "SideStore", url: "https://apps.sidestore.io/",
                          blurb: "SideStore's official source, with SideStore updates.",
                          category: .official, keywords: ["sidestore"]),
        RecommendedSource(name: "SideStore Team Picks", url: "https://community-apps.sidestore.io/sidecommunity.json",
                          blurb: "Community apps picked by the SideStore team: PPSSPP, RetroArch, iSH, ScummVM and more.",
                          category: .official, keywords: ["ppsspp", "retroarch", "scummvm", "community"]),

        // Tweaked apps
        RecommendedSource(name: "EeveeSpotify (SpotC)", url: "https://spotc-repo.yodaluca.dev/AltStore%20Repo.json",
                          blurb: "Spotify with the EeveeSpotify tweak (SpotveeC), plus SpotC++ and SpotilifeC builds.",
                          category: .tweaks,
                          keywords: ["eeveespotify", "eevee", "spotify", "spotc", "spotveec", "spotcompiled", "music"]),
        RecommendedSource(name: "YTLitePlus", url: "https://raw.githubusercontent.com/Balackburn/YTLitePlusAltstore/main/apps.json",
                          blurb: "YouTube with the YTLitePlus tweaks built in.",
                          category: .tweaks, keywords: ["youtube", "ytlite", "video"]),
        RecommendedSource(name: "uYouEnhanced", url: "https://raw.githubusercontent.com/arichornlover/arichornlover.github.io/main/apps.json",
                          blurb: "YouTube with the uYouEnhanced tweaks built in.",
                          category: .tweaks, keywords: ["youtube", "uyou", "uyouplus", "video"]),
        RecommendedSource(name: "Apollo for Reddit", url: "https://raw.githubusercontent.com/Balackburn/Apollo/main/apps.json",
                          blurb: "The Apollo Reddit app, patched so it works again.",
                          category: .tweaks, keywords: ["reddit", "apollo"]),

        // Emulators & games
        RecommendedSource(name: "UTM", url: "https://alt.getutm.app",
                          blurb: "Run Windows, Linux and more in virtual machines.",
                          category: .emulators, keywords: ["vm", "virtual machine", "windows", "linux", "qemu"]),
        RecommendedSource(name: "DolphiniOS", url: "https://altstore.oatmealdome.me",
                          blurb: "GameCube and Wii emulator.",
                          category: .emulators, keywords: ["dolphin", "gamecube", "wii", "nintendo"]),
        RecommendedSource(name: "Provenance", url: "https://provenance-emu.com/apps.json",
                          blurb: "Multi-console emulator for classic Nintendo, Sega, Sony and Atari games.",
                          category: .emulators, keywords: ["emulator", "retro", "nintendo", "sega", "playstation"]),
        RecommendedSource(name: "Flycast", url: "https://flyinghead.github.io/flycast-builds/altstore.json",
                          blurb: "Sega Dreamcast and Naomi emulator.",
                          category: .emulators, keywords: ["dreamcast", "sega", "naomi"]),
        RecommendedSource(name: "PokeMMO", url: "https://pokemmo.com/altstore/",
                          blurb: "Free-to-play Pokémon MMO.",
                          category: .emulators, keywords: ["pokemon", "mmo", "game"]),

        // Tools & utilities
        RecommendedSource(name: "StikDebug", url: "https://stikdebug.xyz/index.json",
                          blurb: "Turn on JIT for emulators and other apps, right on your device.",
                          category: .tools, keywords: ["jit", "debug", "stikjit"]),
        RecommendedSource(name: "Feather", url: "https://raw.githubusercontent.com/khcrysalis/Feather/main/app-repo.json",
                          blurb: "Sign and install IPAs on-device with your own certificate.",
                          category: .tools, keywords: ["signer", "sign", "certificate", "ipa"]),
        RecommendedSource(name: "iSH", url: "https://ish.app/altstore.json",
                          blurb: "A Linux shell (Alpine) that runs on your iPhone.",
                          category: .tools, keywords: ["terminal", "shell", "linux", "alpine"]),
        RecommendedSource(name: "Aidoku", url: "https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json",
                          blurb: "Free, open-source manga reader.",
                          category: .tools, keywords: ["manga", "comics", "reader"]),
        RecommendedSource(name: "iTorrent", url: "https://xitrix.github.io/iTorrent/AltStore.json",
                          blurb: "Torrent client for iOS.",
                          category: .tools, keywords: ["torrent", "download"]),

        // Collections
        RecommendedSource(name: "Quantum Source", url: "https://quarksources.github.io/dist/quantumsource.min.json",
                          blurb: "A big collection of emulators, utilities and jailbreak tools.",
                          category: .collections, keywords: ["emulator", "collection", "quark"]),

        // Jailbreaks
        RecommendedSource(name: "Odyssey", url: "https://theodyssey.dev/altstore/odysseysource.json",
                          blurb: "Jailbreak for iOS 13.",
                          category: .jailbreak, keywords: ["jailbreak"]),
        RecommendedSource(name: "Taurine", url: "https://taurine.app/altstore/taurinestore.json",
                          blurb: "Jailbreak for iOS 14.",
                          category: .jailbreak, keywords: ["jailbreak"]),
    ]

    /// Shown as cards on Browse and Discover, in this order.
    static let featured: [RecommendedSource] = {
        let order = [
            "https://spotc-repo.yodaluca.dev/AltStore%20Repo.json",
            "https://community-apps.sidestore.io/sidecommunity.json",
            "https://raw.githubusercontent.com/Balackburn/YTLitePlusAltstore/main/apps.json",
            "https://alt.getutm.app",
            "https://stikdebug.xyz/index.json",
            "https://ish.app/altstore.json",
            "https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json",
            "https://altstore.oatmealdome.me",
            "https://raw.githubusercontent.com/khcrysalis/Feather/main/app-repo.json",
            "https://raw.githubusercontent.com/Balackburn/Apollo/main/apps.json",
        ]
        return order.compactMap { url in all.first { $0.url == url } }
    }()
}
