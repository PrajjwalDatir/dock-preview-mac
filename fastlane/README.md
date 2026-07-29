fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac build

```sh
[bundle exec] fastlane mac build
```

Compile, assemble, Developer-ID sign, and embed Sparkle into dock-preview.app

### mac keys

```sh
[bundle exec] fastlane mac keys
```

One-time: generate the Sparkle EdDSA keys and print the public key for Info.plist

### mac appcast

```sh
[bundle exec] fastlane mac appcast
```

Regenerate + EdDSA-sign appcast.xml from the release .zip

### mac release

```sh
[bundle exec] fastlane mac release
```

Full release: build → notarize app + dmg → GitHub Release → publish appcast

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
