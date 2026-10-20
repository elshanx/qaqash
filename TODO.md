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

## Ideas from Coucou

One at a time, verified on screen before the next.

- [x] Command output: after a Bash step, show `$ command` and the tail of its output under the diff (needs the `PostToolUse` hook).
- [ ] Done card: when a run finishes, home shows project, "Done", the last command's output and the step count.
- [ ] Poke the face: clicking the mascot fast turns its eyes into spirals with blush, "Too many hits at once", back after 3s.
- [ ] More eyes: happy closed arcs when done, a squint on hover.
- [ ] Face moves: the face slides from the bar into the open card (`matchedGeometryEffect`).
- [ ] "+" tab: pick which widgets show on home (music, VS Code, and later ones).
- [ ] GitHub widget: needs a network exception to `api.github.com` (decide first; maybe read through the local `gh` CLI so Qaqash holds no token).
