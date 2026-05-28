---
name: Obsidian Flux
colors:
  surface: '#0b1326'
  surface-dim: '#0b1326'
  surface-bright: '#31394d'
  surface-container-lowest: '#060e20'
  surface-container-low: '#131b2e'
  surface-container: '#171f33'
  surface-container-high: '#222a3d'
  surface-container-highest: '#2d3449'
  on-surface: '#dae2fd'
  on-surface-variant: '#cbc3d7'
  inverse-surface: '#dae2fd'
  inverse-on-surface: '#283044'
  outline: '#958ea0'
  outline-variant: '#494454'
  surface-tint: '#d0bcff'
  primary: '#d0bcff'
  on-primary: '#3c0091'
  primary-container: '#a078ff'
  on-primary-container: '#340080'
  inverse-primary: '#6d3bd7'
  secondary: '#c0c1ff'
  on-secondary: '#1000a9'
  secondary-container: '#3131c0'
  on-secondary-container: '#b0b2ff'
  tertiary: '#ffb869'
  on-tertiary: '#482900'
  tertiary-container: '#ca801e'
  on-tertiary-container: '#3f2300'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e9ddff'
  primary-fixed-dim: '#d0bcff'
  on-primary-fixed: '#23005c'
  on-primary-fixed-variant: '#5516be'
  secondary-fixed: '#e1e0ff'
  secondary-fixed-dim: '#c0c1ff'
  on-secondary-fixed: '#07006c'
  on-secondary-fixed-variant: '#2f2ebe'
  tertiary-fixed: '#ffdcbb'
  tertiary-fixed-dim: '#ffb869'
  on-tertiary-fixed: '#2c1700'
  on-tertiary-fixed-variant: '#673d00'
  background: '#0b1326'
  on-background: '#dae2fd'
  surface-variant: '#2d3449'
typography:
  display-lg:
    fontFamily: Geist
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.04em
  headline-md:
    fontFamily: Geist
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
    letterSpacing: -0.02em
  headline-sm:
    fontFamily: Geist
    fontSize: 18px
    fontWeight: '600'
    lineHeight: '1.4'
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
  label-md:
    fontFamily: Geist
    fontSize: 13px
    fontWeight: '500'
    lineHeight: '1'
    letterSpacing: 0.02em
  mono-code:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.6'
  headline-md-mobile:
    fontFamily: Geist
    fontSize: 20px
    fontWeight: '600'
    lineHeight: '1.3'
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 40px
  sidebar-width: 280px
  max-content-width: 800px
---

## Brand & Style

The design system is engineered for deep focus and digital organization. It targets knowledge workers, researchers, and developers who require a friction-less environment for vault management. 

The aesthetic is **Modern Minimalism** with a **Technical Edge**. It leverages the raw, structural utility of developer tools but softens them with web-native refinements. The UI prioritizes content over chrome, using generous whitespace and high-quality typography to reduce cognitive load. The emotional response is one of calm productivity—sophisticated, quiet, and reliable.

## Colors

The palette is rooted in a "Deep Charcoal" ecosystem to minimize eye strain during long writing sessions.

- **Primary (Obsidian Purple):** Used exclusively for primary actions, active states, and focus indicators.
- **Surface Tiers:** The background uses a near-black (#09090B), while UI containers (sidebars, cards) use a slightly lighter slate (#18181B) to create subtle depth without relying on shadows.
- **Accents:** Secondary indigo is used for subtle highlights, such as search matches or secondary button hover states.
- **Status:** Standardized semantic colors (Red for error, Green for success) should be desaturated to fit the dark theme.

## Typography

The system utilizes a dual-font approach to distinguish between navigation and creation.

- **UI & Navigation:** Uses **Geist** for its technical precision and tight tracking. It provides a modern, "engineered" feel to headers and labels.
- **Content & Reading:** Uses **Inter** for body text to ensure maximum legibility across all display types.
- **Editor:** **JetBrains Mono** is mandatory for the Markdown editor and code blocks, providing clear character distinction and a rhythmic writing experience.
- **Markdown Scale:** In preview mode, use a descending scale for H1-H3. H1 should be `headline-md`, H2 `headline-sm`, and H3 `label-md` in uppercase.

## Layout & Spacing

This design system uses a **Fixed-Fluid Hybrid** model.

- **Sidebar:** A fixed 280px navigation area on the left for the folder tree.
- **Main Content:** A fluid area that centers the Markdown editor within a `max-content-width` of 800px to maintain optimal line lengths for reading.
- **Rhythm:** A strict 4px baseline grid. All padding and margins must be multiples of 4 (4, 8, 16, 24, 40).
- **Responsive:** On mobile, the sidebar transitions to a bottom-sheet or a full-screen overlay. The 800px content constraint is removed, reverting to a 16px horizontal safe-margin.

## Elevation & Depth

To maintain a minimalist aesthetic, depth is communicated through **Tonal Layering** and **Low-Contrast Outlines** rather than heavy shadows.

- **Level 0 (Base):** The main application background (#09090B).
- **Level 1 (Surface):** Sidebars and modals (#18181B). These are separated from the base by a 1px solid border (#27272A).
- **Active State:** Navigation items use a subtle 5% white overlay or a 2px vertical "accent bar" on the left edge in the Primary color.
- **Modals:** Use a 40px backdrop blur (10% opacity black) to maintain context while focusing on the foreground task.

## Shapes

The design system favors a **Soft-Square** approach.

- **General Elements:** Buttons, inputs, and cards use a 4px (0.25rem) radius to feel precise and modern.
- **Interactive Nodes:** File list items and folder tree nodes remain sharp (0px) on their vertical edges but may use a 4px radius on hover-states for a "pill-like" highlight that doesn't feel overly playful.
- **Avatars/Icons:** Use a 6px radius to slightly distinguish them from structural UI elements.

## Components

### Buttons
- **Primary:** Solid Purple background, white text. No gradient. 4px radius.
- **Ghost:** No background, Slate-400 text. On hover, a subtle Slate-800 background appears. Used for secondary navigation actions.

### Folder Tree & File List
- **Nodes:** 32px height. Use a 16px chevron icon for folders. Active files receive a subtle Purple tint to the text and a 2px left border.
- **Indentation:** 12px per nesting level. Use thin vertical guide wires (1px Slate-800) for deep hierarchies.

### Markdown Editor
- **Active Line:** Highlight the current line with a 2% white background tint.
- **Code Blocks:** Use a slightly darker background (#050505) with 8px internal padding and 4px radius.
- **Checkboxes:** Custom square style, 14px size. When checked, the background fills with Primary color and the text receives a strike-through with 50% opacity.

### Form Inputs
- **Style:** 1px border (#27272A). On focus, the border changes to Primary Purple with a 2px outer "glow" (Primary color at 20% opacity). Text is Geist 14px.

### Tab Bar
- **Style:** Minimalist. Active tabs have a Primary color underline (2px). Inactive tabs are Slate-500. Tabs should have a "Close" icon that only appears on hover.