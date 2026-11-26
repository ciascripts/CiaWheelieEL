# Source Finder

An iOS app for sideloading with **SideStore** or **AltStore**. It finds sources and searches the apps inside them.

## Features
- **Apps tab**: searches every app in your saved sources by name, developer, bundle ID or category. Each app opens a page with:
  - *Install with SideStore / AltStore* buttons (`sidestore://install?url=…`)
  - *Download IPA* and *Copy IPA link*
  - Screenshots and version history
- **My Sources tab**: comes with 13 working sources. You can add any URL; the app checks it's a real source before saving it. You can also paste a `sidestore://source?url=…` link. Swipe left to delete, and use the ⋯ menu to reset to the defaults.
- **Discover tab**: searches public GitHub repos and checks each one for a valid source JSON (`apps.json`, `source.json`, `repo.json`, …). Results can be previewed, saved, or sent straight to SideStore/AltStore.

## Getting the IPA
GitHub Actions builds it (`.github/workflows/build-ipa.yml`) on every push that changes `SourceFinder/`:
1. Open the repo's **Actions** tab, pick the latest **Build SourceFinder IPA** run, and download the **SourceFinder-ipa** artifact. It's a zip; unzip it in the Files app.
2. Share `SourceFinder.ipa` to SideStore, or open SideStore → My Apps → **+** and pick it.

Push a tag such as `v1.0.0` to also get a GitHub Release with the IPA attached. A Release is easier to download from an iPhone.

The IPA is **unsigned** on purpose, because SideStore/AltStore sign it with your Apple ID when they install it.

## Building locally (Mac)
```sh
brew install xcodegen
cd SourceFinder && xcodegen generate && open SourceFinder.xcodeproj
```
Requires iOS 16+.
