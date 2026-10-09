# Paper-style App UI Specification

> A visual UI system distilled from the provided Paper Store / Paper
> Premium / Paper Demo references.
>
> **Design keywords:** Editorial · Playful · Minimal · Tactile · Premium
> · Creative · Human

------------------------------------------------------------------------

## 1. Design Philosophy

The interface combines an **editorial magazine layout** with a **playful
creative-tool aesthetic**.

### Core principles

1.  **Typography is the primary visual element**
    -   Large serif headlines create personality and editorial
        character.
    -   Sans-serif UI text keeps navigation and interaction clear.
    -   Avoid excessive decoration; let typography, whitespace, and
        artwork carry the design.
2.  **White space is structural**
    -   Large empty areas are intentional.
    -   Content should feel curated rather than dense.
    -   Use generous vertical spacing between sections.
3.  **Product imagery feels physical**
    -   Books, cards, papers, brushes, and illustrations should have
        subtle depth.
    -   Rounded corners + soft shadows create a tactile, collectible
        feeling.
    -   Avoid glossy / overly realistic 3D effects.
4.  **Color is used as an accent**
    -   The base UI is predominantly white and black.
    -   Saturated colors appear in artwork, badges, CTA buttons, and
        premium states.
    -   Each screen should have one dominant accent rather than many
        competing colors.
5.  **Playful, but never childish**
    -   Illustrations can be geometric, colorful, and slightly quirky.
    -   UI controls remain restrained and highly legible.

------------------------------------------------------------------------

# 2. Color System

## 2.1 Core colors

  Token             Hex         Usage
  ----------------- ----------- ------------------------------------
  `ink-900`         `#161616`   Primary text, headings
  `ink-700`         `#3D3D3D`   Secondary text
  `ink-500`         `#8F8F8F`   Metadata, disabled text
  `white`           `#FFFFFF`   Main background
  `surface-50`      `#F8F8F7`   Cards / subtle surfaces
  `line-200`        `#E5E5E5`   Dividers, borders
  `accent-yellow`   `#F0BB4B`   Primary creative CTA / highlights
  `accent-blue`     `#0070AF`   Illustration / product artwork
  `accent-coral`    `#F15F58`   Secondary illustration accent
  `accent-green`    `#00A56A`   Illustration / success
  `accent-pink`     `#E99BC4`   Illustration accent
  `premium-blue`    `#5B6FF7`   Premium selection / active state
  `demo-navy`       `#39415D`   Demo / immersive canvas background

### Color rules

-   UI chrome should primarily use `ink-900 + white`.
-   Use saturated colors mainly for **content and moments of emphasis**.
-   Primary action can use `accent-yellow` when the action feels
    creative or exploratory.
-   Use `premium-blue` for selected subscription states.
-   Never turn the whole interface into a rainbow palette.
-   Avoid gradients in ordinary UI components. Gradients are appropriate
    for special marketing / paywall backgrounds.

------------------------------------------------------------------------

# 3. Typography

The reference uses a strong contrast between **editorial serif display
type** and **neutral sans-serif UI type**.

## 3.1 Font roles

### Display Serif

Use for: - Hero headlines - Premium marketing headlines - Editorial
statements - Large feature titles

Recommended visual characteristics:

``` text
High contrast serif
Bold / Black weight
Compact but elegant
Large x-height
Distinctive editorial personality
```

Suggested font candidates:

-   Recoleta
-   Canela
-   Cooper
-   Editorial New
-   Cormorant Garamond Bold

If unavailable, use a strong system serif fallback.

### UI Sans

Use for: - Navigation - Buttons - Metadata - Product titles -
Descriptions - Pricing - Form controls

Suggested:

``` text
SF Pro Display
SF Pro Text
Inter
Helvetica Neue
```

------------------------------------------------------------------------

## 3.2 Type scale

  Style                Size           Weight   Line height Usage
  -------------- ---------- ---------------- ------------- -------------------
  `display-xl`     48--56px   700--800 serif    0.95--1.05 Hero headline
  `display-lg`     40--48px   700--800 serif           1.0 Marketing title
  `display-md`     32--38px        700 serif          1.05 Section title
  `title-lg`       26--30px         700 sans           1.1 Screen title
  `title-md`       22--24px         700 sans          1.15 Card title
  `body-lg`        20--24px         400 sans    1.25--1.35 Large description
  `body-md`        16--18px         400 sans    1.35--1.45 Main body
  `body-sm`        14--16px         400 sans          1.35 Supporting copy
  `caption`        12--14px    400--500 sans           1.3 Metadata
  `button`         16--18px    600--700 sans             1 CTA

### Typography behavior

-   Headlines should have **tight line-height**.
-   Body copy should have comfortable line-height.
-   Serif display text should normally be left aligned in editorial
    screens.
-   Center alignment works well for premium/paywall hero sections.
-   Avoid all-caps except for very small metadata labels.
-   Use sentence case for most UI.

------------------------------------------------------------------------

# 4. Spacing System

Use an 8pt-based spacing system, with occasional editorial spacing
values.

``` text
4   micro
8   tight
12  compact
16  standard
24  comfortable
32  section
40  large
48  hero
64  editorial
80+ dramatic whitespace
```

### Recommended mobile margins

``` text
Screen horizontal padding: 24–32px
Large editorial layout: 32–40px
Card internal padding: 20–24px
Section gap: 40–64px
Hero gap: 64–96px
```

The screenshots intentionally use **more whitespace than a typical
utility app**.

------------------------------------------------------------------------

# 5. Corner Radius

The system uses soft but not excessively rounded geometry.

  Element               Radius
  ----------------- ----------
  Small control        8--12px
  Card                16--24px
  Product artwork     20--28px
  Large CTA           28--36px
  Bottom sheet        28--36px
  Pills / badges         999px

### Principle

Use radius to make an object feel **friendly and tactile**, not like a
generic SaaS dashboard.

------------------------------------------------------------------------

# 6. Shadows

Shadows should be soft and physical.

### Product shadow

``` css
box-shadow:
  0 12px 30px rgba(0, 0, 0, 0.10),
  0 3px 10px rgba(0, 0, 0, 0.06);
```

### Floating UI

``` css
box-shadow:
  0 8px 24px rgba(0, 0, 0, 0.10);
```

### Rules

-   Large diffuse shadow \> hard shadow.
-   Use shadows to separate paper/products from the background.
-   Avoid heavy elevation on ordinary text cards.
-   Avoid Material-style multi-level elevation everywhere.

------------------------------------------------------------------------

# 7. Navigation

## Top navigation

The reference uses extremely minimal navigation.

### Standard

``` text
[ Back / Close ]                         [ Icon / Credits ]
```

Characteristics:

-   24--28px icon size
-   44px minimum touch target
-   Black on white
-   No filled navigation bar
-   Large vertical breathing room

### Icon style

Use:

-   2--2.5px stroke
-   Rounded line caps
-   Simple geometric construction
-   No excessive detail

Examples:

``` text
×
‹
ⓘ
⌕
☰
```

Prefer custom SVG icons rather than emoji or platform glyphs.

------------------------------------------------------------------------

# 8. Editorial Store Layout

The Paper Store screen follows a **catalog + magazine** structure.

## Hero

``` text
[large whitespace]

Welcome to the
Paper Store.

A collection of creative
prompts, workbooks,
tutorials, and planners.

[large whitespace]
```

### Hero rules

-   Serif display headline
-   48--56px on mobile
-   Maximum line width around 650--700px on larger screens
-   Description can be serif as well for a more editorial feel
-   Do not add a hero image unless it contributes to the story

------------------------------------------------------------------------

## Product grid

Desktop:

``` text
┌──────────────┐   ┌──────────────┐
│ Product      │   │ Product      │
│ artwork      │   │ artwork      │
│              │   │              │
└──────────────┘   └──────────────┘
Title              Title
Author             Author
Credits            Credits
Description        Description
```

Mobile:

``` text
1 column
```

Recommended:

``` text
Desktop: 2–3 columns
Mobile: 2 columns for catalog browsing
Detail: 1 column
```

### Product card

Hierarchy:

1.  Title
2.  Author
3.  Price / Credits
4.  Product image
5.  Short description

The product image should visually dominate the card.

------------------------------------------------------------------------

# 9. Product Artwork

Product artwork is one of the most important parts of the visual
identity.

## Characteristics

-   Flat geometric shapes
-   Strong color blocks
-   Simple illustrations
-   Slightly imperfect / human feel
-   Limited palette
-   White or colored paper surface
-   Subtle physical shadow

### Avoid

-   Generic stock photography
-   Highly polished 3D renders
-   Complex gradients
-   Corporate iconography
-   Excessive visual detail

### Product mockup

``` text
       ┌───────────────┐
       │               │
       │   ARTWORK     │
       │               │
       │               │
       └───────────────┘
              ↓
       soft diffuse shadow
```

Product images should feel like **objects sitting on a table**, even
when displayed digitally.

------------------------------------------------------------------------

# 10. Badges

## Free badge

Reference style:

``` text
       ┌─────────────┐
       │    Free     │
       └─────────────┘
```

Recommended:

``` text
background: #5B6FF7
text: #FFFFFF
radius: 999px
padding: 10px 18px
font-weight: 700
```

The badge can partially overlap the product artwork.

## Popular badge

For premium pricing:

``` text
background: warm coral → pink
text: white
radius: 8–12px
```

Use only for meaningful merchandising information.

------------------------------------------------------------------------

# 11. Product Detail Page

Structure:

``` text
← Paper Store                         credits

             Product Title
                Author

        [ large product carousel ]

                [ Get ]

────────────────────────────────────

COST             LENGTH          FILE SIZE
0 Credits        37 Pages       8.3 MB

────────────────────────────────────

Description

Body copy...
```

### Product carousel

-   Horizontal paging
-   Product centered
-   Adjacent page partially visible
-   Creates a physical "browse through a booklet" feeling
-   Avoid conventional full-width image galleries

### CTA

For free products:

``` text
Get
```

For paid products:

``` text
Get
```

The action label should remain simple. Price information can appear
separately.

------------------------------------------------------------------------

# 12. Premium / Paywall

The premium screen is more expressive than the ordinary app UI.

## Background

Use a soft atmospheric gradient:

``` text
warm yellow / peach
        ↓
pink / lavender
        ↓
white
```

Add very subtle decorative stars / sparkles.

### Structure

``` text
Already purchased?

             [ artwork ]

       Get access to
       Paper Premium

Unlock all premium...

┌──────────────────────────────┐
│ Most popular                 │
│                              │
│ Weekly             ¥68/week  │
└──────────────────────────────┘

┌──────────────────────────────┐
│ Yearly             ¥698/year │
└──────────────────────────────┘

          Continue

          Other plans
```

### Premium typography

-   Large serif headline
-   Center aligned
-   Strong contrast
-   Short paragraphs
-   Large CTA

------------------------------------------------------------------------

# 13. Pricing Selector

## Selected state

``` text
border: 2px solid #5B6FF7
background: #F8F8FF
```

## Unselected state

``` text
border: 2px solid #E0E0E0
background: #FFFFFF
```

### Pricing card

Recommended minimum height:

``` text
72–88px
```

Use:

``` text
Plan name        Price
```

Keep the information extremely scannable.

------------------------------------------------------------------------

# 14. CTA Buttons

## Primary

Black CTA:

``` text
background: #000000
color: #FFFFFF
height: 64–68px
radius: 32–34px
font-size: 18px
font-weight: 700
```

This is especially appropriate for premium conversion screens.

## Creative CTA

Yellow CTA:

``` text
background: #F0BB4B
color: #161616
height: 56–64px
radius: 999px
font-weight: 600–700
```

Use for content acquisition / creative actions.

### Button principle

One screen should normally have **one obvious primary action**.

------------------------------------------------------------------------

# 15. Bottom Sheet

The "Other plans" screen demonstrates a large rounded bottom sheet.

``` text
┌──────────────────────────────────┐
│                                  │
│       Other plans                │
│                                  │
│    Weekly       |      Yearly    │
│                                  │
│  ┌───────────┐  ┌─────────────┐ │
│  │ Premium   │  │ Lite        │ │
│  │           │  │             │ │
│  └───────────┘  └─────────────┘ │
│                                  │
│        Continue                  │
│                                  │
│        ¥68.00/week               │
└──────────────────────────────────┘
```

### Behavior

-   Sheet enters from bottom
-   Background dims
-   Rounded top corners
-   Keep content scrollable if necessary
-   Close button remains easy to reach

------------------------------------------------------------------------

# 16. Demo / Immersive Canvas

The Paper Demo screen deliberately breaks the white editorial UI.

## Canvas

``` text
background: #39415D
```

The content appears as physical paper floating in space.

### Layout

``` text
                Search   Menu

                Paper Demo
                 17 Pages


       ┌────────────────────────────┐
       │                            │
       │         PAPER              │
       │        ARTWORK             │
       │                            │
       └────────────────────────────┘
          └── next pages ──┘
```

### Key characteristics

-   Dark muted background
-   White paper
-   Large physical object
-   Soft shadow
-   Horizontal page stack
-   Minimal controls
-   Large empty space

This creates a **quiet, gallery-like experience**.

------------------------------------------------------------------------

# 17. Paper / Card Material

Paper surfaces should have subtle imperfections.

Recommended:

``` text
background: #F7F7F3
border: none
shadow: soft
texture: extremely subtle
```

Optional texture:

``` text
opacity: 2–4%
```

Never make the texture obvious.

The goal is:

> "digital interface that feels like paper"

not:

> "paper texture website".

------------------------------------------------------------------------

# 18. Illustration Style

### Geometry

Prefer:

-   circles
-   rectangles
-   simple organic blobs
-   lines
-   basic human figures
-   simple tools / objects

### Color

Use 3--6 colors per illustration.

### Stroke

``` text
1.5–3px
```

depending on scale.

### Personality

Illustrations should feel:

-   handmade
-   optimistic
-   slightly quirky
-   approachable
-   contemporary

Avoid overly cute mascot-heavy interfaces.

------------------------------------------------------------------------

# 19. Motion

Motion should reinforce the physical metaphor.

## Page transition

Use:

``` text
duration: 350–500ms
easing: cubic-bezier(0.22, 1, 0.36, 1)
```

Page movement can have a slight horizontal perspective / parallax.

## Product entrance

``` text
opacity: 0 → 1
scale: 0.96 → 1
translateY: 16px → 0
duration: 400ms
```

## Bottom sheet

``` text
translateY: 100% → 0
duration: 400ms
```

### Motion principle

Motion should feel like:

``` text
paper sliding
paper turning
object being placed
```

rather than:

``` text
generic UI animation
```

------------------------------------------------------------------------

# 20. Responsive Rules

## Mobile

Reference width:

``` text
390–430px
```

Use:

``` text
24–32px horizontal padding
```

Hero:

``` text
48–56px serif
```

Cards:

``` text
12–16px gap
```

## Tablet

Increase:

``` text
horizontal margins
content max-width
product image size
```

## Desktop

Recommended content max-width:

``` text
1200–1440px
```

Hero can become much wider while maintaining generous whitespace.

------------------------------------------------------------------------

# 21. Accessibility

Despite the editorial aesthetic, interaction should remain conventional.

### Touch targets

Minimum:

``` text
44 × 44px
```

### Contrast

-   Primary black text on white
-   Avoid light gray body text
-   Gray metadata should remain readable
-   Do not communicate state through color alone

### Motion

Respect:

``` text
prefers-reduced-motion
```

------------------------------------------------------------------------

# 22. Component Naming

Recommended component vocabulary:

``` text
PaperNavigation
PaperDisplayTitle
PaperProductCard
PaperProductMockup
PaperBadge
PaperCreditLabel
PaperCTA
PaperPricingCard
PaperPlanSelector
PaperBottomSheet
PaperCarousel
PaperCanvas
PaperIllustration
PaperDivider
```

------------------------------------------------------------------------

# 23. Design Tokens

``` css
:root {
  /* Color */
  --ink-900: #161616;
  --ink-700: #3D3D3D;
  --ink-500: #8F8F8F;
  --white: #FFFFFF;
  --surface-50: #F8F8F7;
  --line-200: #E5E5E5;

  --accent-yellow: #F0BB4B;
  --accent-blue: #0070AF;
  --accent-coral: #F15F58;
  --accent-green: #00A56A;
  --accent-pink: #E99BC4;

  --premium-blue: #5B6FF7;
  --demo-navy: #39415D;

  /* Radius */
  --radius-sm: 10px;
  --radius-md: 16px;
  --radius-lg: 24px;
  --radius-xl: 32px;
  --radius-pill: 999px;

  /* Spacing */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 24px;
  --space-6: 32px;
  --space-7: 40px;
  --space-8: 48px;
  --space-9: 64px;
  --space-10: 80px;

  /* Shadow */
  --shadow-product:
    0 12px 30px rgba(0, 0, 0, 0.10),
    0 3px 10px rgba(0, 0, 0, 0.06);

  --shadow-floating:
    0 8px 24px rgba(0, 0, 0, 0.10);
}
```

------------------------------------------------------------------------

# 24. Do / Don't

  Do                               Don't
  -------------------------------- ------------------------------------
  Use large editorial typography   Use generic dashboard typography
  Give content room to breathe     Fill every pixel
  Use colorful artwork             Make the whole UI colorful
  Use soft product shadows         Use hard Material shadows
  Make paper feel physical         Add obvious paper textures
  Keep controls simple             Add decorative controls
  Use serif for storytelling       Use serif for every UI label
  Use playful illustrations        Use childish cartoon UI everywhere
  Make one action dominant         Give equal weight to 4 CTAs
  Use subtle motion                Animate every component

------------------------------------------------------------------------

# 25. Visual Recipe

When designing a new screen, start with this formula:

``` text
WHITE SPACE
    +
EDITORIAL SERIF
    +
NEUTRAL SANS UI
    +
ONE STRONG ACCENT COLOR
    +
PHYSICAL PAPER / OBJECT
    +
SOFT SHADOW
    +
MINIMAL CONTROLS
    =
PAPER-STYLE EXPERIENCE
```

## One-line art direction

> **A quiet editorial canvas where playful creative objects feel
> physically placed inside a premium, typography-led interface.**

------------------------------------------------------------------------

# 26. Reference Screen Recipes

### Store

``` text
White background
+ large serif hero
+ 2-column product grid
+ colorful product covers
+ minimal metadata
+ generous whitespace
```

### Product Detail

``` text
White background
+ centered title
+ horizontal paper carousel
+ simple Get CTA
+ three-column metadata
+ editorial description
```

### Premium

``` text
Soft warm gradient
+ serif centered headline
+ floating creative artwork
+ large pricing cards
+ black pill CTA
```

### Other Plans

``` text
Dimmed background
+ white rounded bottom sheet
+ segmented control
+ two plan cards
+ black CTA
```

### Demo

``` text
Muted navy canvas
+ white paper object
+ physical page stack
+ soft shadow
+ minimal controls
+ large empty space
```

------------------------------------------------------------------------

# 27. Implementation Priority

If time is limited, preserve these five things first:

1.  **Typography hierarchy**
2.  **Large whitespace**
3.  **Physical product/card presentation**
4.  **Restrained black + white UI with selective color**
5.  **Simple, tactile interaction**

These five characteristics contribute more to the perceived style than
individual icons or decorative details.
