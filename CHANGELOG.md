# Changelog

## 0.1.2

- Added compatibility with both historical `registry.json` app formats: array and dictionary.
- Preserves 3ELiDAR and 3ERoomElectrical records instead of replacing them when an older array registry is found.
- Canonicalizes the next write to an app-keyed dictionary and coordinates writes with `NSFileCoordinator`.
- Increased the internal build number to 3.

## 0.1.1

- Fixed the Swift actor-isolation build error in `ThreeEStorageManager`.
- Ensured the GitHub Actions `build` directory exists before writing `xcodebuild.log`.
- Added automatic upload of the build log when the workflow fails.
- Increased the internal build number to 2.
