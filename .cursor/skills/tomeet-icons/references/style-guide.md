# Tomeet icon style

## Medium

Needle-felt / dry-brush / sponge watercolor. Edges are fuzzy fibers, not Bézier strokes. Color sits in soft masses. Slight handmade irregularity is required.

Never use: photoreal fur, glossy 3D, hard vector SF Symbols, neon AI chrome, anime lineart, drop shadows, paper frames, or baked iOS squircles on tab glyphs.

## Palette

Pull from `Theme` and the mascot. Keep saturation low.

| Role | Approx | Notes |
|---|---|---|
| Canvas / paper | `#F8EEE5` | App background |
| Card | `#FFF9F3` | |
| Cream mass | `#EDE3D2` | Face, house body, book covers |
| Tan / quill | `#C4A07A` | Roof, spines, rims |
| Cocoa structure | `#6B4A32` | Door, book spines, coffee |
| Dark mark | `#3A2A1D` | Eyes, nose, window |
| Accent (rare) | dusty red, mustard | Radio only, muted |
| Unselected | warm gray `#B8AFA4` range | Derived, not redrawn |
| Ink (UI copy) | `#413036` at 70% | Not for glyphs |

Monochrome empty states use **only** cream, tan, cocoa, dark brown. No green, blue, red, yellow.

## Hedgehog mascot

This is one character. Do not redesign it.

- Body is one round fluffy circle, not a realistic hedgehog silhouette
- Cream heart-shaped face patch
- Two small round dark-brown eyes with a tiny cream catchlight (empty states that sleep use closed curved lids instead)
- Small rounded dark-brown nose, tiny mouth line
- Two small rounded tan ears
- Quills = radiating teardrop tan strokes on the upper and side arc, not a full spiky outline
- Two tiny three-toed brown paws at the bottom

Keep recognition: if it no longer looks like [examples/mascot.png](../examples/mascot.png), regenerate.

## Tab glyphs

One object, front or slight 3/4, padded on all sides.

**Home.** Gable roof, small chimney, cream body, cocoa arched door, one circular window. Window may read slightly like an eye; that is allowed on Home only.

**Library.** Two or three standing books. Blank cream cover. No circle, eye, letter, or emblem on the cover.

**AI.** Sparkle cluster, not a robot or chip. One large four-pointed star plus two smaller companions, uneven, gathered.

**Glasses.** Round rims, empty lenses, short temples. No face inside the lenses.

**Radio.** Chunky rounded set. Simplified grille as a few strokes. One dial. No earbuds, no frequency numbers.

## Selected vs unselected

Selected = full cream/tan/cocoa felt.

Unselected = the same pixels, desaturated and lifted into warm gray, slightly lower alpha. Same fringe. Must sit on a **true transparent** field.

## Cutout rules

Original generations often leave an uneven near-white plate (`(254,254,254)` mixed with `(241,242,241)`). A simple “distance to corner white” flood fill **will miss that plate** and it will show up as gray fog on the unselected state.

Treat background as: high luminance **and** low chroma, flood from the edges.

- Background: luma ≥ 228 and chroma ≤ 18
- Hedgehog cream / house body has higher chroma and must not flood
- Soften alpha only on pixels that neighbor background
- Corners of the finished PNG must be `(0,0,0,0)`
- Trim to the glyph plus ~40px padding

Home and AI failed this once; Library succeeded because its plate was uniform. Always verify Home and AI.

## App Store icon

Opaque square. Warm paper fill. Mascot centered with margin. iOS applies the mask — do not draw it. No transparency in the submitted 1024 file.
