# Todo

## Use a 6-digit pairing code

The 4-digit code can be brute-forced with a matching certificate in ~10k tries.

- [ ] `Sources/Qaqash/Phone.swift` `pairCode`: `% 10_000` -> `% 1_000_000`, `%04d` -> `%06d` (and the test in `Tests/QaqashTests/DiffTests.swift`)
- [ ] `ios/Qaqash/Discovery.swift` `pairCode`: `% 10_000` -> `% 1_000_000`, `%04d` -> `%06d`
- [ ] `ios/Qaqash/PairView.swift`: placeholder `"····"` -> `"······"`
- [ ] `swift test`, build iOS, pair once and confirm both show the same 6 digits

Ship Mac and iPhone together, or the codes won't match.

## Ship updates without cloning the repo

People install Qaqash once and get new versions without cloning or building.

- [ ] Decide: paid Apple Developer account? Without Developer ID signing and notarization, Gatekeeper blocks the app on other Macs.
- [ ] Decide: Sparkle (in-app "Update available", needs a network exception for the update check) or Homebrew cask (`brew upgrade`, no network calls from the app).
- [ ] Sign `build/Qaqash.app` with "Developer ID Application" and notarize it (`xcrun notarytool`, then `xcrun stapler`).
- [ ] Ship `scripts/hook.sh` inside the app (`Contents/Resources/hook.sh`) and point `claude-hooks.example.json` there, so the hooks don't need the repo.
- [ ] Sparkle: add the package, an EdDSA key (private key stays off the repo), `SUFeedURL` and `SUPublicEDKey` in `Info.plist`, a "Check for updates" setting, and "Check for Updates…" in the menu bar menu. Document it as the second network exception in `CLAUDE.md`.
- [ ] Homebrew: a `homebrew-qaqash` tap repo with a cask pointing at the GitHub Release zip.
- [ ] `scripts/release.sh`: bump the version in `Info.plist`, release build, sign, notarize, zip, `gh release create`, update `appcast.xml` or the cask.
- [ ] Release once, install on a second Mac (or a fresh user account), release again and confirm the update arrives.
