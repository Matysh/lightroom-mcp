# Generating a useful photographic reference

Use image-to-image generation with the baseline Lightroom render attached. A prompt without the input image produces a weak target for this workflow. Follow the host's image-generation instructions; in particular, inspect a local image before using it as an editing input.

Adapt this template to the actual scene and the user's requested look:

> Edit the supplied photograph into a realistic lighting and color reference for RAW development. Preserve the same person's identity, facial features, expression, pose, anatomy, hair, clothing and texture. Preserve all objects, their positions, the background, perspective, framing and aspect ratio. Improve only photographic lighting and color: [describe direction and softness of light], [subject/background brightness relationship], [white balance and palette], and [highlight/shadow behavior]. Keep natural skin texture, believable materials, highlight detail and subtle shadow separation. Avoid face retouching, beauty filters, skin smoothing, added or removed objects, changed scenery, artificial glow and excessive HDR. The result should be a plausible photograph that can guide tonal, HSL and local-mask adjustments in Lightroom.

For landscapes or still life, replace the person-specific constraints with concrete constraints for the scene. Do not invent an unrelated lighting style: infer a useful target from the existing light and the user's taste. A substantially different light direction or time of day may require changes that develop controls cannot reproduce; explain this limit instead of forcing the RAW to match it.

Inspect both images and note:

| Area | Compare | Likely Lightroom controls |
| --- | --- | --- |
| Brightest textured surfaces | Retained detail, brightness, color casts | Highlights, whites, exposure |
| Subject | Midtone brightness, contrast, skin balance | Exposure, WB/tint, moderate HSL; subject mask if needed |
| Background | Hue, saturation, brightness, separation | Relevant HSL channels; background mask if needed |
| Shadows | Visibility, depth, unwanted color casts | Shadows, blacks, local exposure or temperature |
| Edges and texture | Halos, plastic skin, crunchy detail | Restrain clarity/texture/sharpening and local contrast |

Use visual comparison as the primary check. Optional image statistics can help investigate brightness or channel balance, but differences in generated shapes and texture invalidate naive pixel matching. Do not use Python or another raster editor to make the final photograph appear closer: the deliverable is the Lightroom develop state and its rendered result.
