---
name: tomeet-icons
description: >-
  Generate Tomeet app icons and empty-state illustrations in the needle-felt
  hedgehog visual language. Use when making Tomeet tab icons, App Store icons,
  selected/unselected glyph pairs, mascot drawings, or empty-state artwork;
  or when the user mentions Tomeet icons, 毛绒图标, 刺猬图标, Home/Library/AI tab
  art, or 空状态配图.
---

# Tomeet Icons

Create bitmap icons and empty-state art for the Tomeet iOS reading app. Match the existing needle-felt hedgehog language. Read [references/style-guide.md](references/style-guide.md) before generating. Use the files in [examples/](examples/) as style references.

## Product

Tomeet is an AI reading app: meet the mind inside every book. Quiet, warm, analog. Not social, not neon-tech, not glossy 3D.

Mascot: a round felt hedgehog in cream, tan, and cocoa brown.

## When to use which output

| Request | Output |
|---|---|
| Tab / toolbar glyph | Isolated pictogram, transparent PNG, selected + unselected pair |
| App Store / home-screen icon | 1024×1024 opaque square, **no** baked rounded corners |
| Empty state | Same hedgehog in a quiet pose, monochrome brown, transparent PNG |

Do not drop icons into `Assets.xcassets` unless the user asks to wire them into the app.

## Tab glyph workflow

1. Read the style guide. Attach the closest [examples/](examples/) images as `reference_image_paths`.
2. Generate a 1:1 illustration of **one** pictogram.
3. Run [scripts/process-icon.swift](scripts/process-icon.swift) to punch a true transparent background and build the unselected (warm-gray) state.
4. Inspect corners: RGBA must be `(0,0,0,0)`. If a gray fog remains around the glyph, recut — do not ship it.
5. Open the cutout and unselected files for the user. Give paths.

### Prompt constraints for tab glyphs

- Same felt / dry-brush / fuzzy-fiber texture as the examples.
- Warm cream, tan, cocoa, dark-brown masses. Small dusty-red or mustard accents only when the object needs them (radio).
- Centered; glyph occupies about 70–78% of the canvas.
- Transparent or plain near-white ground. No ivory panel, no squircle frame, no drop shadow, no text.
- Instantly readable at ~25pt. Prefer one mass, not a scene.
- Library covers stay blank. No eyes, letters, or emblems on books.

Canonical tab subjects:

- **Home** — house with gable, small chimney, arched door, one circular window
- **Library** — two or three standing books, no cover decoration
- **AI** — one large four-pointed sparkle plus two smaller ones
- **Glasses** — round vintage rims, empty lenses, no face
- **Radio** — chunky cream set, simplified grille, one dial, skip earbuds

## Unselected state

Do not regenerate a second drawing. Derive it from the selected cutout with `process-icon.swift`:

- Desaturate, flatten contrast, tint warm gray (near `Theme.sand`)
- Keep the same silhouette and felt fringe
- Preserve alpha; never flatten onto a gray or checkerboard plate

## App Store icon

- 1024×1024, fully opaque, RGB
- Fill with warm paper `#FAF5EE` (or `Theme.canvas` `#F8EEE5`)
- Center the mascot or glyph with ~11% margin so the iOS squircle does not clip quills
- Do **not** bake rounded corners, gloss, or the iOS mask
- Flatten remaining alpha onto the fill

## Empty-state illustration

Same hedgehog as [examples/mascot.png](examples/mascot.png). Monochrome brown only.

- One quiet pose; lots of empty space (subject ~45–60% of canvas)
- Allowed props: open book, one hazelnut, one coffee cup
- No furniture, room, floor, Zzz, captions, or extra hues
- Transparent PNG after cutout

Known poses already drawn: reading; dozing over a book with a hazelnut; napping on the belly with a coffee cup. Invent new poses in the same register when asked.

## Quality checks

- First read is a soft felt toy, not a vector SF Symbol, 3D render, or photograph
- No checkerboard, gray fog, or near-white plate left in the PNG
- Selected and unselected share one silhouette
- Empty states stay brown-only and still look like **this** hedgehog

## Delivery

Show the image. Name the kind (tab selected / tab unselected / app icon / empty state) and the saved path. Do not add title options or extra commentary on the artwork itself.
