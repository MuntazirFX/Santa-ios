# Original PC game — reference notes

Source: a 4.5 minute walkthrough recording of the original 2002 game (title screen, options,
highscores, all of level 1, start of level 2), checked frame by frame and cross-checked against
the data in `xmas.xpk`. Everything marked ✔ was verified against the archive.

## Screens
| Screen | What the PC version shows |
|--------|---------------------------|
| Title | Live 3D scene: Santa on a snowy cobble platform, a house, fir trees, snow-capped hills, falling snow + sparkles. Logo (`maps\sc.dds`), menu in the big yellow font: **START GAME / HIGHSCORES / OPTIONS / QUIT**. Top bar "CDV FUN Line", cdv + JoyMania logos (`cdv.dds`, `joymania.dds`), "Version 1.1f Nov 29 2002", "(c) 2002 CDV Software Entertainment AG". |
| Options | Music slider, SFX slider, Controller (Mouse/Keyboard), Language (English), OK. Texts come from the `text*.lib` files. |
| Highscores | Boxed list of 10 names + points (57654 down to 1500), "Goto webpage", "Back". |
| Level intro | Big "LEVEL 1" text over the start platform. |
| Level completed | Framed panel: Collected presents `80/80`, `80 x 10 = 800`, Time left `3:55`, `235 sec x 2 = 470`, Points `1270`, Total points, CONTINUE. Score = presents × 10 + seconds left × 2. |

## HUD (gameplay)
- top-left: Santa icon + lives (starts at 3; an extra life at 80/80 → 6 in the video)
- top-centre: countdown timer (level 1 starts at about 7:00)
- top-right: presents `collected/total` + present icon
- bottom-left: "LEVEL n", bottom-right: running score
- ✔ level 000 has exactly **80** `PRESENT A` objects, level 001 has **96** (video shows `0/96` on level 2).
  So `levels\000.dat` = LEVEL 1, `001.dat` = LEVEL 2 (counts per level: 80, 96, 99, 87; demo 39).

## Camera & look
- 3rd-person chase camera behind Santa, low pitch (~10–30°) while walking, swings to nearly top-down
  when he jumps/falls between round platforms. Nothing is drawn below the platforms: pure black void.
- Sky = `gfx\himmel.x`, an open cylinder (r 65.7, height 26, UV repeats 8.8× around) textured with
  `maps\himmel.dds`; stars on top, mountain silhouette at the horizon, black below. ✔ implemented.
- Platform edges facing left/back are lit **blue-violet**, tops neutral grey/white (a coloured directional light).
  The models contain normals; the current viewer uses a screen-space face normal instead.
- Particles: large soft snow flakes falling everywhere, orange star sparkles around presents
  (`effects\star_miracle_w.txt`, `maps\star.dds`, `maps\snow.dds`), presents float and spin.
- Level exit: blue arrow with stars ("Plattform EXIT"). Round wooden/snow platforms, hills and fir trees are
  scenery; fir bases are dark as in the models.

## What this means for the port (next steps, in order)
1. Santa: walk/jump/gravity on platform tops (`RECTFORM`/`PLATTFORM` radius + top y), chase camera.
2. HUD + presents pickup (80 → extra life), timer, score formula above, LEVEL COMPLETED panel.
3. Particles: snow + star sparkles.
4. Real normals + blue rim light, then skinning/animation (Santa walk cycle, trolls, ravens).
5. Menus (title scene, options, highscores) using the fonts/GUI textures already decoded.
