# Cadence identity

The open C represents Cadence; the three rounded bars represent music and rhythm. Use the same mark on iPhone, Watch, the launcher and the launch screen.

- `cadence-app-icon.png`: opaque 1024px lime-on-ink app icon. Apple applies the platform's rounded-square/circular mask.
- `cadence-mark-ink.svg` / `cadence-mark-lime.svg`: transparent scalable mark.
- `cadence-mark-ink.png` / `cadence-mark-lime.png`: transparent 1024px exports.
- `cadence-wordmark-ink.svg` / `cadence-wordmark-lime.svg`: mark and lowercase wordmark. The wordmark uses the system rounded font with a sans-serif fallback.
- Native vector PDF marks and 1x/2x/3x launch images live in `../Assets.xcassets`.

Palette: Ink `#16211D`, Lime `#D7F567`, Paper `#F5F3EB`. Keep clear space of at least one waveform-bar height around the standalone mark. Use ink on light surfaces and lime on dark surfaces.

Regenerate the icon, native marks, standalone marks and launch artwork from the project root with `swift Scripts/generate-icon.swift`. The exporter uses Core Graphics directly, so it works without an AppKit window. App icons must be opaque; standalone PNG marks intentionally retain transparency. The app uses original vector PDFs rather than SF Symbols for its identity.
