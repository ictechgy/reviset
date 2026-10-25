# Selected raster master prompts

Built-in imagegen editing was used, with transparent_background=true. The first call edited E2 with E1 as a spacing reference; the second call edited that result to refine the outer alpha. The source PNG is the unmodified second result. Native framing and PNG/ICO conversion are recorded in build-app-icons.ts.

## E2 with wider channels

Use case: precise-object-edit.
Asset type: production macOS and Windows app icon, one square PNG with transparent pixels outside the icon plate.
Input image 1 is the edit target, Reviset E2. Input image 2 is only a reference for the more open ivory spacing between the three layers, Reviset E1.
Refine image 1 with one targeted geometry change: open both horizontal gaps between the graphite top slab, vermilion middle slab, and graphite bottom slab, so a clean ivory channel remains clearly visible between all three. Match the more generous spacing seen in image 2, roughly 3 percent of the ivory plate height per channel. Keep the overall stack bounds and center by minimally reducing slab heights if necessary.
Preserve image 1's larger bold silhouette, slab lengths, rightward orange offset, left notch, rounded exterior shape, quiet matte graphite material, muted burnt-vermilion orange, warm ivory squircle plate, frontal camera, top-left illumination, and shallow restrained relief. Do not adopt image 2's shorter orange bar or stronger grain. Keep shadows short and soft so they do not fill the open ivory channels.
For actual app packaging, remove the neutral studio backdrop completely: the ivory squircle plate itself stays opaque, but everything outside the plate and its subtle close shadow must be truly transparent alpha. Keep the complete plate intact with comfortable transparent padding; no cropping. The plate should occupy approximately 88 to 90 percent of the canvas width. Single centered icon, no mockup environment, no contact sheet. No text, labels, letters, badges, borders, extra symbols, or added objects.


## Alpha cleanup

Use case: background-extraction. Input image is the edit target, an approved app icon design.
Keep the interior ivory plate and the three graphite/orange/graphite slabs exactly as they are: same shapes, spacing, color, material, position, camera, and lighting. Fix only the outer transparency mask. The generated alpha currently contains stray white flecks, ragged thin remnants and isolated debris outside the actual ivory rounded-square plate. Remove all of this completely. Return one clean isolated app icon with a smooth continuous antialiased rounded-square boundary and completely transparent pixels everywhere outside the plate. Do not leave any detached speck, halo, partial backdrop, or outer cast shadow. Treat the outer squircle contour as one immaculate vector-smooth silhouette. Keep comfortable clear transparent padding on all four sides and preserve the entire opaque ivory plate. No new detail, no text, no frame, no extra objects, no color changes. The only change is a clean production-ready alpha cutout around the existing ivory app tile.

