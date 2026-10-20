# Todo

## Use a 6-digit pairing code

The 4-digit code can be brute-forced with a matching certificate in ~10k tries.

- [ ] `Sources/Qaqash/Phone.swift` `pairCode`: `% 10_000` -> `% 1_000_000`, `%04d` -> `%06d` (and the test in `Tests/QaqashTests/DiffTests.swift`)
- [ ] `ios/Qaqash/Discovery.swift` `pairCode`: `% 10_000` -> `% 1_000_000`, `%04d` -> `%06d`
- [ ] `ios/Qaqash/PairView.swift`: placeholder `"····"` -> `"······"`
- [ ] `swift test`, build iOS, pair once and confirm both show the same 6 digits

Ship Mac and iPhone together, or the codes won't match.
