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

## Session 2026-09-26 — exe forensics + collision implementation

Re-checked the project against `SantaClausInTrouble.exe` itself (`strings` on the PE, no
disassembler available in this sandbox) and against the real data via the existing
`tools/test_skin.cpp` harness. Concrete outcomes:

- **`pendingFrame` bug**: already fixed in the current `GameEngine.mm` (see the "BUG (fixed)"
  comment at the Pass-1 frame walk). The AUDIT text above still described it as open from an
  earlier state of the file — that description is now stale; the fix is confirmed present and
  correct.
- **Skinning float mystery — 4 more hypotheses tested and ruled out**, using
  `tools/test_skin.cpp` against the real `gfx\weihnachtsman_000.x` (baseline bind-pose error:
  mean 10.57 / rms 13.26 over 1624 verts):
  - "last vertex weight = 1 − sum(others)" → 10.41 / 13.17 (no real change)
  - "first vertex weight = 1 − sum(rest), shifted" → 10.55 / 13.34 (no change)
  - "drop the extra trailing vertexIndex, weights already 1:1" → 10.57 / 13.26 (no change)
  - "drop the extra leading vertexIndex" → 10.69 / 13.38 (slightly worse)
  - New alternative theory — **also ruled out**: that the trailing "16 floats" is actually a
    15-float affine matrix (implicit constant 1.0 at [3][3]) and the weights array is really
    full-length (N, not N−1). Tested directly: bounding box exploded to ~49000 units (vs. the
    real ~130-unit mesh), so the offset matrix genuinely is 16 explicit floats, not 15 — the
    missing value is really a weight, not a matrix element.
  - **Why this barely moves the aggregate error**: only 1 vertex per bone block is affected by
    any of these fixes, so across 1624 vertices and 47 bone blocks the effect is far too small
    to explain the ~8%-too-tall symptom. **The missing-weight reconstruction is very unlikely
    to be the dominant bug** — the bone/offset-matrix combination order (already the most-tested
    axis, per the "Skinning investigation" section above) remains the more likely root cause.
  - Corroborating find: the exe embeds its D3D8 vertex shader source as plain-text comments
    (`vs.1.1` blocks, `strings`-visible). They confirm the *runtime* per-vertex blend format
    really does store only 3 of 4 bone weights explicitly and computes the 4th as
    `1 − dot(others)` (`; first compute the last blending weight` / `dp3 r0.w,v1.xyz,c0.xzz` /
    `add r0.w,-r0.w,c0.x`) — but this is the GPU's compact **per-vertex, up-to-4-bones**
    runtime format, built by the exe's CPU loader from the `.x` file's per-bone `SkinWeights`
    blocks; it does not directly explain the per-block N−1 weight count in the file itself.
    Still useful confirmation that "N−1 explicit + 1 implicit" is a real, intentional pattern in
    this engine, not file corruption.
- **Collision (`PhysicsWorld.h/.mm`) — implemented for the first time.** It was a pure stub
  (`checkCollisionAtPosition:` always returned `NO`, `groundHeightAtX:z:` always returned the
  flat `groundY`). Now: it takes the level's own entity list (`LevelLoader.entities`) and uses
  each entity's `RADIUS` field from `data/elements.txt` — confirmed against the exe's own
  keyword table (`strings` shows the literal field list `ELEMENT/FILE/RADIUS/SCALING/SPEED/
  WALKANIM/TYPE/PLATTFORM/RECTFORM/DECO/ELEVATOR/MOVER/JUMPER/ENEMY/ELEVATORENEMY/JUMPHEIGHT/
  VERTICALOFFSET/EXIT/BONUS/FRICTION/SAVEPOINT/EXTRALIFE`, an exact match for what
  `ElementCatalog.h` already parses):
  - `groundHeightAtX:z:` finds the highest PLATTFORM/RECTFORM entity whose XZ footprint (circle
    of its RADIUS, or a 1.5-unit default half-grid-cell when RADIUS is absent) contains the
    point, and returns that entity's own Y as the platform top.
  - `checkCollisionAtPosition:radius:` / `collidingEntityAtPosition:radius:` do circle-vs-circle
    collision against ENEMY/ELEVATORENEMY entities, vertical-band-limited (±3 units) so enemies
    on a different platform don't collide through the level.
  - `CharacterController` now has an optional `physicsWorld` property: when set, ground checks
    use the real level geometry instead of a flat y=0 plane, and each `update:` checks enemy
    overlap and enters `CharacterStateHurt`.
  - **Not yet done**: nothing currently calls `[characterController setPhysicsWorld:...]` or
    `[physicsWorld setEntities:levelLoader.entities]` — `GameEngine.mm`'s render loop still runs
    its own separate, working level-viewer path and never touches `LevelLoader` /
    `PhysicsWorld` / `CharacterController` / `AnimationSystem` (verified: none of those four
  - **Wired up in this session**: `MetalView.mm` now owns a `PhysicsWorld` + `CharacterController`
    and 3 on-screen buttons (◀ ▶ ▲ — the DINPUT8 replacement). `loadLevel:` feeds `PhysicsWorld`
    the real level data via the same `[GameEngine parseLevelData:]` LevelRenderer itself uses
    (added a `radius` field to `LevelObject` + `elements.txt`'s `RADIUS` line, so it carries the
    same collision data end to end). Each frame, `drawInMTKView:` steps `CharacterController`
    against real ground height / enemy collision and shows live position + state on the existing
    text overlay.
  - **Also done this session — Santa is now actually drawn moving in the level.**
    `LevelRenderer` gained `loadCharacterMesh:` (loads `gfx\weihnachtsman_000.x` once, reusing
    the exact same `buildGPUMeshForFile:` helper the static level objects use) and a
    `characterTransform`/`hasCharacter` pair that `encodeInto:` draws on top of the level each
    frame. `MetalView.mm` builds that transform from `_character.position` +
    `facingDirection` every frame. **Caveat, stated plainly**: Santa isn't a `data\elements.txt`
    catalog entry (he's spawned by code, not placed like level objects), so there's no authored
    SCALING value to size him against the level grid the way every other object has. The scale
    constant (`kCharacterScale = 0.02`, chosen from the ~129-unit bind-pose height measured in
    `tools/test_skin.cpp` to land him around ~2.5 world units tall next to the 3.0-unit grid) is
    a **visual estimate that needs eyeballing on a real device/simulator**, not a verified number
    like everything else in this file.
  - **Still not done / known-broken on purpose**: he's drawn in his static bind pose — no walk
    cycle. `AnimationSystem`/`AniParser` playback was deliberately **not** wired in yet, because
    the skinning matrix math still has the ~8%-too-tall distortion documented above; turning on
    animation now would drive that same broken skin math every frame and could look worse than
    the static bind pose, not better. Fix the skinning bug first, then wire `AnimationSystem`
    into this same `characterTransform` path.

## Windows DLL dependencies — exe import table (2026-09-26)

Full DLL import table pulled from `SantaClausInTrouble.exe` via `objdump -p` (100% reliable —
straight from the PE header, no guessing). What each needs on iOS/ARM64:

| DLL | Purpose | iOS status |
|---|---|---|
| `d3d8.dll` | 3D rendering | ✅ Metal (`Shaders.metal`, `MetalView.mm`) |
| `DSOUND.dll` | Audio | ✅ AVFoundation (`AudioEngine.mm`) |
| `DINPUT8.dll` | Keyboard/gamepad input | ⚠️ Only camera-touch gestures exist; `CharacterController`'s `setInputLeft/Right/triggerJump` aren't wired to any on-screen UI yet |
| `USER32.dll` / `GDI32.dll` | Win32 window chrome + GDI text-to-bitmap (`CreateFontA`, `DrawTextA`, `CreateDIBSection`...) | 🚫 Not needed — in-game text already uses the real bitmap font (`FontRenderer.mm`); this was Win32 dialog/options-menu chrome only |
| `KERNEL32.dll` | Generic OS (files/memory/threads) | 🚫 Covered by iOS/Foundation + C++ stdlib already |
| `SHELL32.dll` (`ShellExecuteA`) | Opens `cdv.url` / `joymania.url` publisher links | 🚫 Gameplay-irrelevant |
| `ole32.dll` | COM init (DirectX/DirectInput boilerplate) | 🚫 Metal/AVFoundation don't need COM |
| **`WSOCK32.dll`** | **Investigated in full — see below** | 🚫 Confirmed dead-end, not needed |

### WSOCK32.dll — full investigation (corrected from an earlier "uncertain" guess)

Decoded all 26 imported ordinals against the authoritative Winsock ordinal table
(`accept`=1, `bind`=2, `closesocket`=3, `getsockopt`=7, `htonl`=8, `htons`=9, `inet_ntoa`=11,
`ioctlsocket`=12, `listen`=13, `ntohs`=15, `recv`=16, `recvfrom`=17, `select`=18, `send`=19,
`sendto`=20, `setsockopt`=21, `shutdown`=22, `gethostbyaddr`=51, `gethostbyname`=52,
`gethostname`=57, `WSAAsyncSelect`=101, `WSAAsyncGetHostByAddr`=102,
`WSAAsyncGetHostByName`=103, `WSAGetLastError`=111, `WSAStartup`=115, `WSACleanup`=116).
Notably `connect`/`socket` themselves are **not** in the static import table — they're almost
certainly resolved dynamically via `GetProcAddress` (both `KERNEL32.LoadLibraryA` and
`GetProcAddress` are imported), i.e. this is an optional feature that degrades gracefully if
unavailable.

Cross-referencing the exe's own strings confirms what it's for — an online login / highscore
subsystem (`"MOS Client: start connecting to %s port:%d"`, `"Connecting to server: %s:%d..."`,
`"Login to server as \"%s\"..."`, `"Login to subserver - id:%d..."`, `"Socket already in use"`,
`"Socket creationf failed"`), i.e. CDV/Joymania's own online service, unrelated to
`xmas.xpk`/level/asset loading (all independently verified elsewhere in this file).

**Conclusion: not needed for the iOS port.** The publisher's 2002 game server has been offline
for over two decades, so even the original Windows build can no longer reach it — this whole
subsystem is inert today either way. No ARM64/iOS replacement required.

## Session 2026-09-26 (later) — first real device screenshots, button bug found & fixed

Screenshots from an actual build showed Santa correctly standing on a level platform
(`groundHeightAtX:z:` genuinely works), but the ◀ ▶ ▲ on-screen buttons were completely
invisible.

**Root cause**: `MetalView`'s buttons were positioned in `initWithFrame:` using the `frame`
parameter. `AppDelegate.mm` constructs it as `[[MetalView alloc] initWithFrame:vc.view.bounds]`
on a bare, just-created `UIViewController` that isn't in a window yet — `vc.view.bounds` is
`CGRectZero` at that point. So every button frame was computed from a zero-size rect (e.g. the
jump button's `x = frame.size.width - bs - margin = 0 - 64 - 24 = -88`), placing all three
off-screen. `mv.autoresizingMask` later resizes `mv` itself to fill the window, but autoresizing
only adjusts the view it's set on — it does nothing for that view's own subviews' already-fixed
frames, so the buttons stayed stuck off-screen permanently.

**Fix**: moved the frame math into a new `-layoutSubviews` override, which iOS calls automatically
every time `self.bounds` actually changes (including the first real layout pass once the view is
in the window) — buttons are created with `CGRectZero` in `initWithFrame:` and positioned from
`self.bounds.size` (always correct) in `layoutSubviews` instead. Also bumped the button
background alpha (0.18 → 0.28) and added a subtle border so they're visible against both the
black sky and the stone platform textures.

## Session 2026-09-26 (later still) — real main menu screen, matching the PC title screen

Person shared a screenshot of the original PC build's actual title screen (`SantaClausInTrouble.exe`,
version 1.1f, Nov 29 2002) plus a table of the GUI-related asset files, and asked for the iOS port's
menu to look like it ("PC jaisa ho"). Until now the app only had the debug Level/Santa/Log tabs —
no real menu existed.

**Asset discovery** (measured directly from the real files with PIL, not guessed):
- `maps\sc.dds` (512×512, ARGB8888) turned out to contain almost the whole top banner in one
  texture: the "CDV FunLine" wordmark, the "cdv" logo, and the full cursive "Santa Claus in
  Trouble" title logo, all baked together with a transparent lower half. Alpha-channel bounding
  box: content is exactly UV `u[0, 0.8945] v[0, 0.5]`.
- `maps\joymania.dds` (256×256) has the "JD Joymania Development" corner logo in its *top* band
  and an unrelated small gold Santa-figurine icon lower down in the *same texture* — found the
  gap row (63–143 empty) separating them and cropped to just the logo band:
  UV `u[0.0156, 0.9844] v[0.0234, 0.2461]`.
- `gui2.tga` (128×128) is just golden 9-slice window-frame border pieces + 2 icons — not used for
  this pass (menu buttons are plain bitmap-font text on the level background, matching how the
  reference screenshot's menu items look — no button chrome around them there either).
- No separate title/splash image exists outside `xmas.xpk`, and nothing in the original game
  folder either (checked `SantaClausInTrouble.exe`'s sibling files) — confirms `sc.dds` really is
  the complete title graphic, not a partial one.

**What was built** (`MetalView.mm`): a real menu overlay drawn on top of the already-working
Level view (level 000's background — stone platform, snowy pine trees, night sky — already
matches the reference screenshot's scene almost exactly, since it's the same renderer):
- `sc.dds` banner+title and the cropped `joymania.dds` logo, drawn via a new generic
  screen-space textured-quad builder (`buildSpriteQuadInRect:uv:screenSize:`), reusing the
  existing `_spritePipelineState` (the same alpha-blended pipeline the debug text already used —
  no new Metal pipeline needed).
- START GAME / HIGHSCORES / OPTIONS / QUIT labels, rendered with the real `big_font` bitmap font
  (`FontRenderer`, same one the debug overlay uses) instead of a system font, for visual fidelity.
- Invisible `UIButton` hit-targets stacked exactly under each label (same "transparent UIButton
  over custom-drawn Metal content" pattern already used for the ◀ ▶ ▲ movement controls), so taps
  land on the real glyphs.
- `startGameTapped` hides the menu overlay and reveals the ◀ ▶ ▲ movement controls — Santa stands
  still at his spawn point (matching the reference screenshot) until then. `highscoresTapped` /
  `optionsTapped` / `quitTapped` are intentionally no-ops for now: there's no highscore storage,
  settings screen, or (per Apple HIG) app-initiated quit implemented yet — visual-only stubs.

**Honest caveats**:
- Button *screen positions* (the vertical stack's exact x/y/spacing) are **visually estimated**
  from the reference screenshot's proportions, not reverse-engineered — those coordinates are
  almost certainly hard-coded in the exe's compiled code, not in any text asset file, so there's
  nothing to extract them from short of disassembly (see the exe-forensics section above for why
  that's impractical here). Tune `computeMenuButtonRects:` by eye against a real device/simulator.
- Colors: the reference shows START GAME/HIGHSCORES/OPTIONS in a warm off-white and QUIT in
  orange — `FontRenderer` currently draws whatever color is baked into the `big_font00/01/02.dds`
  atlas pages with no per-draw tint, so all four labels currently render in the same color. Per-
  label tinting would need a small fragment-shader/uniform change to `_spritePipelineState` —
  not done this pass.
- `gui2.tga`'s 9-slice window-frame graphics aren't used yet (no boxed panel behind the menu,
  matching how the reference screenshot doesn't obviously show one either around the menu text
  itself — worth a closer look if a future screenshot shows otherwise).

## Known gaps (not done)Also fixed a small cosmetic issue while there: the gameplay debug text (`"Santa (x,y,z) ..."`)
could linger on screen for a frame after switching away from the Level tab — `drawInMTKView:`
now explicitly clears it the moment `levelMode` goes false.


- `.ani` keyframes: 80‑byte records (4×4 matrix, 3 floats ≈ scale, u32 ms time, step 160) recognised, but clip/bone boundaries not decoded → no animation playback yet.
- `qmeter.jpg` texture referenced by `qmeter.x` does not exist in the archive (falls back to white).
- Music `m02B.wav` lives outside the XPK; other tracks are not in the provided data.
- Skinning pose accuracy on device is unverified (bind‑pose rendering verified).
- Repo contains original game files (`xmas.xpk`, exe, docs): keep it **private**.
