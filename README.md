# Santa Claus in Trouble — iOS Engine

An iOS port of the classic 2002 PC game **"Santa Claus in Trouble"** using **Metal** and **C++**.

## Status
- ✅ XPK archive parsing (177 assets)
- ✅ MSZIP decompression (DirectX .x files)
- ✅ 3D skinned mesh rendering via Metal
- ✅ DDS texture decoding (RGB565, RGB888, RGBA8888)
- ✅ Bone/skinning support
- ✅ Texture mapping (UVs used as-is — see "Direct3D → Metal notes")
- ✅ DDS P8 (sky) + TGA (GUI sheets) decoding
- ✅ elements.txt catalog + level objects resolved to model/type (all 6313 objects)
- ✅ Bitmap font rendering (big_font / small_font)
- ✅ Whole-level viewer: `levels\000.dat` → catalog → models + textures (see "Level viewer")
- 🔄 .ani animation format (partially decoded, see src/AniParser.h)
- ⏳ Animation playback, physics, game logic

## Architecture

| Folder | Contents |
|--------|----------|
| `src/` | C++ engine (XPK parser, X-File parser, DDS decoder) |
| `ios/` | iOS wrapper (AppDelegate, MetalView, GameEngine, Shaders) |
| `assets/` | Game data (`xmas.xpk` — 15.5 MB, 177 files inside) |
| `.github/workflows/` | CI/CD pipeline (auto-builds unsigned IPA) |

## Building

Push to `main` — GitHub Actions automatically:
1. Compiles the C++ test binary
2. Generates the Xcode project with XcodeGen
3. Builds the iOS app
4. Packages the unsigned `SantaEngine.ipa`
5. Uploads the IPA as a build artifact

No Mac required — everything runs on GitHub's macOS runners.

See `docs/PC_REFERENCE.md` for how the original game looks and plays (HUD, camera, scoring, screens).

## Level viewer

The app opens on the first level. Top-centre switch: **Level / Santa / Log**.
Controls (Level): one finger = pan, pinch = zoom, two-finger twist = rotate, two fingers up/down = tilt (pitch; look nearly horizontal to see the sky).

How a level is built (all verified on the real data):
- `levels\NNN.dat`: `u32 count` + 60-byte records `name[32], x, y, z, extra[3], variant`
- world grid = **3.0 units**, x/z = ground plane, y = up
- `variant` = rotation about Y in 90° steps
- `data\elements.txt` gives the model (`.ani` → same-named `.x`), `SCALING` and `TYPE`.
  `SCALING >= 1` is **percent** (7.51 → 0.0751, so a 40-unit platform = one 3.0 cell); `< 1` is used as-is
- Sky: the game's own sky cylinder `gfx\himmel.x` + `maps\himmel.dds` (8-bit palette), centred on the camera; black void below, like the PC game. Santa stands on the first platform (bind pose).
- Frame transforms: 59 of the 88 `.x` files keep their pivot in the Frame above the Mesh (e.g. Santa's frame lifts him
  +63.07 so the feet are on y=0, matching `assets/weihnachtsman_000.obj`; walls/snow platforms/trees/hills put their top or
  base on y=0). `GameEngine.mm` now applies that world matrix to unskinned vertices.
- Not done yet: skinned/animated enemies (drawn in bind pose), movers/elevators, collision, Santa movement.
- Known: `extractMeshFromAsset` stops scanning a `Mesh` right after `MeshTextureCoords` (that handler consumes the `{`
  but not the `}`), so per-mesh `TextureFilename` and all `SkinWeights` are never seen. Textures are now found by a
  file-wide fallback. Enabling SkinWeights as-is is WRONG (Santa grows from 129 to 202 units tall vs. the
  `assets/weihnachtsman_000.obj` reference), so skinning stays off until the bone math is fixed.

## Direct3D → Metal notes

The original game (2002) targets Direct3D 8. Conversions that matter, all verified against the real data:

| Topic | Direct3D 8 | Metal | What the engine does |
|-------|-----------|-------|----------------------|
| Coordinates | left-handed, +z into screen | left-handed clip space | `Camera.mm` uses **left-handed** look-at/perspective; models are not mirrored |
| Depth range | z in [0,1] | z in [0,1] | same — do **not** use OpenGL-style [-1,1] projection |
| Front face | clockwise | clockwise (default) | `setFrontFacingWinding:Clockwise` + `MTLCullModeBack` |
| Texture V | V=0 at **top** | V=0 at **top** | UVs from `.x` used unchanged (no `1 - v`) |
| Matrices | row vectors (`v * M`) | column vectors (`M * v`) | frame/bone math in `GameEngine.mm` keeps D3D row order; GPU matrices are built column-major |
| Pixel formats | RGB565, ARGB4444, ARGB1555, P8 | — | expanded to RGBA8 by `TextureLoader` |
| .x meshes | DirectX file format | — | parsed by `XFileParser`, skinned on CPU |

Other verified facts: `.ani` files are raw (not MSZIP), catalog `FILE` entries for enemies are `.ani` (mesh = same-named `.x`),
and asset names are case-insensitive (`gfx\Snow_Corner.X` == `gfx\snow_corner.x`).

Run `tools/verify_assets.cpp` (see its header) to re-check the archive after any parser change.

## Credits

Original game © 2002 **CDV Software Entertainment AG** / **Joymania Development**.
This is a fan-made reverse-engineering project for educational purposes.
