# Glorging

A community mod of Lemmix - a faithful recreation of DOS based Lemmings.

Based on the upstream Lemmix project: [Latest release](https://github.com/ericlangedijk/Lemmix/releases)

## Upstream Notes

Dear Reader,

Almost thirty years ago Lemmings was created by DMA.
Lemmix embeds six original DOS-games and is playable on Windows.
It is meant to be an almost exact clone of DOS-Lemmings with some extra features, like replay.
Additionally: thousands of custom (and often fantastic) levels have been created by people all over the world.
With Lemmix you can play them all. In the near future, when testing phase is over, I will upload a lot of them here.
The PDF assumes some knowledge of the game: https://github.com/ericlangedijk/Lemmix/releases.

If there is anyone who has any objections with the published data here, let me know.
The source code and the program are free to use.
Suggestions for improvements are always welcome.

Proclaimer and Legal Statement: Do whatever you want with it.

The code should compile on a modern Delphi compiler. I used Delphi 10.3.3.
Also should work with a Community edition.
Some technical history is in the Releases.txt at https://github.com/ericlangedijk/Lemmix/releases.
Hic sunt dracones, remember that.

Eric

## Build (Windows)

1. Install Delphi 10.3+ (Community Edition should work).
2. Open `src/Lemmix.dproj`.
3. Build `Win32` (Release).
4. Run the generated `Lemmix.exe` from `src`.

If you changed `.rc` resource input files, run:

`src/Data/BuildResources.bat`

before rebuilding.

## Community Modding

See the full guide in `MODDING.md` for user-style folder layout, `Style.config` keys, and community asset workflow.
