# Source Finder

An iOS app for sideloading with **SideStore** or **AltStore**. It finds sources, recommends good ones, and searches every app inside them.

## Features

### Browse
- **Recommended Sources**: cards for hand-picked sources you haven't added yet, including **EeveeSpotify (SpotC)**. Tap **Add Source** to save one.
- **Recently Updated**: the newest app updates across all your sources.
- **Categories**: Games, Utilities, Developer Tools and the rest, each with its own list.
- **Browse All Apps**: every app A–Z or by update date. An app listed by several sources shows once.

### Search
- Results are ranked: exact name first, then names that start with your text, then words inside names, then developer, subtitle, bundle ID and description.
- Typos are fine: `dolpin` finds DolphiniOS, `emulater` finds the emulators, and `spotfy` finds the Spotify builds.
- Joined words are split, so `lite plus` finds YTLitePlus and `eevee` finds the EeveeSpotify builds.
- Accents and capitals don't matter.
- Beta builds have a **BETA** badge.
- Searches also cover **recommended sources you haven't added**, so you can find an app before you have its source.
- Matching sources show at the top of the results.
- Sort by Best Match, Name or Recently Updated, and filter by category or source (the ⏷ menu).
- Matched text is highlighted, and recent searches are suggested.
- If nothing matches, one tap searches GitHub for a source that has it.

### App page
- App Store-style layout: big icon, **Install** button, version, size, update date, screenshots, What's New and version history.
- The ⋯ menu has the other installer, **Download IPA**, **Copy/Share IPA link** and **Copy Bundle ID**.
- **Also Available From** lists the same app in other sources.

### Sources
- Each source shows its app count and when it was last updated.
- Swipe right to add a source to SideStore/AltStore. Swipe left to copy or delete it.
- If a refresh fails, the source keeps showing its saved copy, and a **Retry** button appears when there is none.
- Sources are saved on the device, so the app opens instantly and works offline.

### Discover
- **Recommended**: about 20 checked sources in groups (Official, Tweaked Apps, Emulators & Games, Tools, Collections, Jailbreaks).
- **Search GitHub**: finds public repos that host a working source file, sorted by stars or by last update.

### Settings
The Settings screen is in the Sources tab's ⋯ menu. It lets you:
- choose whether GET/Install opens **SideStore** or **AltStore**
- clear recent searches
- clear the saved source copies

## Getting the IPA
GitHub Actions builds it (`.github/workflows/build-ipa.yml`) on every push that changes `SourceFinder/`:
1. Open the repo's **Actions** tab, pick the latest **Build SourceFinder IPA** run, and download the **SourceFinder-ipa** artifact. It's a zip; unzip it in the Files app.
2. Share `SourceFinder.ipa` to SideStore, or open SideStore → My Apps → **+** and pick it.

Push a tag such as `v1.1.0` to also get a GitHub Release with the IPA attached. A Release is easier to download from an iPhone.

The IPA is **unsigned** on purpose, because SideStore/AltStore sign it with your Apple ID when they install it.

## Building locally (Mac)
```sh
brew install xcodegen
cd SourceFinder && xcodegen generate && open SourceFinder.xcodeproj
```
Requires iOS 16+.

## Adding a recommended source
Add an entry to `SourceFinder/Recommendations.swift`. To show it as a card, also add its URL to `featured`. Check that the URL returns valid source JSON first.
