# Reviset app icon

The selected icon uses E2's larger graphite/orange displaced-layer mark with
more open ivory channels between the three layers. The user selected this
direction on 2026-10-25 after viewing the E refinements. Claude supplied the
initial art directions; the built-in imagegen tool rendered the raster artwork.
This attribution is not a claim that Claude reviewed or approved the final app.

- `reviset-icon-source.png`: untouched generated raster master (1254 × 1254).
- `reviset-icon.png`: packaged 1024 × 1024 PNG with transparent padding and a
  smooth, fixed native tile mask.
- `reviset.ico`: Windows icon with 16, 24, 32, 48, 64, 128 and 256 px PNG frames.
- `PROMPTS.md`: exact generation prompts for the selected raster master.

Run `npm run icons:build` to reproduce the PNG and ICO from the master.
The packaging script fixes the tile boundary and fills its interior before
resampling, so stray generated alpha pixels outside the tile do not enter the
native icon. It does not redraw the three-layer mark.

The macOS build converts `reviset-icon.png` to the standard ICNS iconset with
`sips` and `iconutil`. The Windows project embeds `reviset.ico` both in the
executable and as the WPF main-window resource. Rebuilding these image assets
does not rebuild or qualify either native app by itself.
