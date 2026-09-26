# Santa iOS Engine — full audit (Metal conversion)

Everything below was checked against the real `assets/xmas.xpk` (177 files).
"Verified" = run/rendered on real data. The Objective‑C++/Metal changes could not be
compiled in the audit sandbox (no Apple toolchain) — let CI compile them and read the log.

## Archive facts
- XPK table: `count, nameOffsets[], namesLen, names, totalSize, sizes[], fileTime[] (unix, Sep–Nov 2002), dataOffset[] (absolute)`.
- 88 `.x` (all MSZIP, all parse), 22 `.dds`, 4 `.tga`, 4 `.jpg`, 13 `.dat` levels, 5 `.ani` (raw), 15 `.wav`, 10 `.lib`, `sfx.txt`, `data/elements.txt`, fonts/gui/effects `.txt`.
- Levels: 13 files, 6313 objects, 60‑byte records, every name exists in `elements.txt` (101 elements).
- Textures: RGB565, ARGB4444, ARGB1555, ARGB8888, **P8 (himmel)**, TGA32. No DXT.

## Bugs found and fixed
| # | Area | Problem | Fix |
|---|------|---------|-----|
| 1 | Shaders.metal | `sprite_vertex`/`sprite_fragment` missing → nil sprite pipeline | added; MetalView guards nil |
| 2 | Shaders.metal | position written straight to clip space, z∈[-0.7,0.7] → Metal clips z<0 (half the model) | real MVP matrix |
| 3 | MetalView | UV `1 - v` flip scrambles texture (D3D and Metal both V=0 top) | removed |
| 4 | Camera | right‑handed + GL depth [-1,1] vs D3D data | left‑handed + [0,1] |
| 5 | MetalView | no winding/cull state | clockwise front + back cull (verified 0.0 % vs 78.7 %) |
| 6 | AssetManager | case‑sensitive lookups: 24/101 catalog files not found | case/slash‑insensitive, uses stored offsets |
| 7 | Catalog | enemy `FILE` is `.ani`; mesh is same‑named `.x` | `ElementCatalog` + GameEngine map `.ani→.x` |
| 8 | LevelParser | `getEntityType` guessed from name substrings (PRESENT/EXTRA LIFE/SAVEPOINT/EXIT/… wrong) | uses `elements.txt` TYPE (0 unknown of 6313) |
| 9 | TextureLoader | no P8 (sky) / TGA (gui2, gui_small, mouse); `dach.jpg`, `objects_old.jpg` unresolved | added + aliases |
| 10 | FontRenderer | glyph metrics in em (52 px) mixed with 24 px; one triangle strip for whole string; V swapped | em‑correct metrics, triangle list, no swap |
| 11 | AniParser/AnimationSystem | `.ani` is raw, was fed to MSZIP → 0 bytes | passthrough; format notes in `AniParser.h` |
| 12 | GameEngine | repo copy older than local (no skinning / catalog / face header) | merged newer version |
| 13 | Info.plist | portrait only (game is 800×600 landscape) | landscape, fullscreen, `metal` capability |
| 14 | project.yml | ARC implicit, music not bundled, Info.plist in sources | explicit ARC, `assets/music` resource, exclude Info.plist |
| 15 | Button.mm | parameter named `id` | renamed |
| 16 | MetalView | ivar assigned before `[super init]` | fixed |

## Found on device (2026-09-21 screen recording)
- Level 000 renders (460 objects, 30 models) but every model was WHITE: `GameEngine.mm` never found the texture name
  because the `MeshTextureCoords` handler leaves the brace depth unbalanced and the `Mesh` scan ends early
  (TextureFilename and SkinWeights come after it). Fixed with a file-wide `TextureFilename` fallback
  (verified on all 88 `.x`: every one resolves; only `qmeter.x` points to a texture that is not in the archive).
- Same bug is why the skin counter always showed `0SK`. With the scan fixed the skin blocks parse (Santa 47, troll 28, raven 28,
  snowman 7, 0 missing bones) but the current skinning math distorts the model, so it is intentionally still off.

## Frame transforms (2026-09-21)
- 59 of 88 `.x` files have a non-identity world matrix above their `Mesh` (pivot offsets, some 90°/180° rotations).
  Evidence they must be applied: Santa +63.07 y == the OBJ reference pose; wall_*/snow_* tops land on y=0 like the
  platt_* pieces; trees/hills get their base on y=0 (level y values are integers); troll/snowman feet on y=0.
- Implemented in `GameEngine.mm` (`meshWorldByToken`), verified with an offline render of level 000.

## PC reference video (2026-09-21)
- Level 000 has 80 presents == HUD `x/80` of LEVEL 1; level 001 has 96 == `0/96` of LEVEL 2 (details in `docs/PC_REFERENCE.md`).
- Sky is the `himmel.x` cylinder (not a flat backdrop); PC background below it is pure black. Implemented.

## Skinning investigation (2026-09-26, tools/test_skin.cpp)
Built a standalone harness (`tools/test_skin.cpp`, no Xcode needed) that runs the exact mesh+skin
extraction logic from `GameEngine.mm` directly against the real `assets/xmas.xpk` and measures
results numerically instead of guessing from a screenshot.

- Confirmed a second, distinct bug beyond the MeshTextureCoords one (now fixed): `pendingFrame`
  in the Pass-1 frame-hierarchy walk isn't reset when a non-NAME token follows "Frame" before its
  name, so it can attach a bone-hierarchy transform to the wrong token later in the file (only
  cosmetic impact observed so far — one bogus map entry named "FrameTransformMatrix" — but should
  be fixed for correctness).
- Reproduced the documented "Santa 129→202" distortion exactly: it comes from applying `meshWorld`
  a second time on top of already-skinned vertices. Current code (no such double-apply) already
  measures much closer: bind-pose height 129.4, current skinned height 139.1 (order = offset*boneWorld).
- Tested 6 bone-matrix conventions (offset*boneWorld, boneWorld*offset, offset-only, boneWorld-only,
  and transposed variants) against the real bind-pose bounding box. The current formula
  (offset*boneWorld, row-vector convention) is the best of everything tried, but still ~8% too
  tall and the per-vertex distance to the bind pose (which a correct rest-pose skin should
  reproduce almost exactly) averages ~10.5 units on a 129-unit character — not yet correct.
- **New finding, verified from raw tokens** (see a `SkinWeights` block for `Knochen_Mund3`):
  every single skin block's trailing FLOAT array is exactly `vertexIndices.size() - 1 + 16`
  floats long, i.e. one weight short of the `N weights + 16-float matrix` layout the code assumes
  — universal across all 47 blocks checked on Santa's mesh (N=2 up to N=554), so it's a real
  encoding quirk, not noise. Tried "trailing vertex gets implicit weight 1.0" as the fix — it does
  **not** reduce the bind-pose error, so that hypothesis is wrong and the true meaning of the
  missing float is still open.
- **Conclusion: skinning is not yet safe to ship as-is.** Recommend leaving skinning off (current
  README default) until this is resolved with an on-device visual A/B, since none of the formulas
  tested here reproduce the bind pose closely enough to trust blind.

## Collision + movement wired in (2026-09-26)
`PhysicsWorld` and `CharacterController` were already fully written (real footprint-circle
collision against the level's own platform objects, gravity/jump/hazard state machine) but
**never connected to anything** — confirmed by grepping the whole `ios/` tree for their class
names outside their own files: zero hits. The app itself was a pure asset *viewer* (Level tab =
free-fly camera over the static level, Santa tab = single-mesh inspector with a spinning bind
pose) with no game loop, no player entity, no input beyond camera gestures. That's why the
screen recording showed Santa standing still — nothing was ever driving him.

Wired up for real, not stubbed:
- `LevelRenderer`: exposes `objects` (the same `LevelObject` list it renders from, so physics and
  visuals can never disagree) and `spawnPoint`; added `setSantaPosition:facingAngle:` (rewrites the
  existing static Santa batch's transform in place — no new draw call, no duplicate mesh) and
  `setCameraTarget:` (lets Play mode drive the look-at point instead of finger-pan).
- `MetalView`: owns the `PhysicsWorld`/`CharacterController` pair; `loadLevel:` rebuilds the
  collision world and respawns the character every time a level loads; new `playMode` property;
  `drawInMTKView:` advances the character one physics step per frame (real delta-time, clamped to
  50ms so a backgrounded app can't let Santa tunnel through the level on resume) and re-targets the
  camera at him.
- New `VirtualJoystickView` (`ios/VirtualJoystick.h/.mm`): bottom-left drag pad, its own `UIView`
  so it never competes with the level's existing pan/pinch/rotate camera gesture recognizers.
- `AppDelegate`: added a 4th "Play" tab (Level / Santa / Play / Log), joystick + jump button +
  lives HUD, all wired to the new `MetalView` API.

**Not yet verified on-device** — this environment has no Xcode/Metal, so this is reviewed for
correctness (brace-balanced, types match, nil-message-safe if a level hasn't loaded) but not
compiled or run. First things to check on a real device/simulator: does Santa's jump height/walk
speed feel right against the level's 3.0-unit grid, does the joystick dead-zone feel good, does
the follow-camera's default `_dist/_yaw/_pitch` (inherited from whatever the free camera was left
at) need a sane default when entering Play mode.

## Known gaps (not done)
- `.ani` keyframes: 80‑byte records (4×4 matrix, 3 floats ≈ scale, u32 ms time, step 160) recognised, but clip/bone boundaries not decoded → no animation playback yet.
- `qmeter.jpg` texture referenced by `qmeter.x` does not exist in the archive (falls back to white).
- Music `m02B.wav` lives outside the XPK; other tracks are not in the provided data.
- Skinning pose accuracy on device is unverified (bind‑pose rendering verified).
- Repo contains original game files (`xmas.xpk`, exe, docs): keep it **private**.
