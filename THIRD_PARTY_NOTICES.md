# Third-party notices

**Cranny includes no third-party code.** It has zero dependencies: no Swift packages, no vendored
sources, no fonts, sounds, images or animations made by others. Everything in this repository is
original work released under the [MIT License](LICENSE).

Cranny uses Apple's system frameworks and SF Symbols at runtime, under Apple's terms. It bundles no
Apple fonts or artwork.

## Acknowledgements

These projects were studied for *techniques*. No code, assets or text were copied from them, so no
license obligations apply; we credit them as a courtesy (Settings ▸ About will list them too).

| Project | License | What we learned |
|---|---|---|
| [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) | BSD-3-Clause | That a MediaRemote client hosted inside the system's `/usr/bin/perl` can still read and control Now Playing on macOS 15.4 and later. Cranny's media bridge (`Packages/CrannyKit/Sources/CrannyMediaBridge`) is an independent implementation with its own protocol. |
| [dannystewart/volumeHUD](https://github.com/dannystewart/volumeHUD) | MIT | That consuming the volume keys in an event tap and applying the change yourself suppresses the system's on-screen display, so only one HUD is ever shown. |
