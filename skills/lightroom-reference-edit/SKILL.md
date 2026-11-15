---
name: lightroom-reference-edit
description: "Develop a selected Lightroom Classic RAW toward an AI-generated lighting and color reference through MCP. Use for the preview, generate reference, and iterative Lightroom tuning workflow, with a snapshot before edits and fresh renders after each pass. Also use when asked to match a supplied reference on a selected RAW."
---

# Lightroom Reference Edit

Edit the actual RAW through Lightroom's develop controls. Use the generated image as a photographic target for light, tone and color. Preserve the photographed person, scene, composition and existing work unless the user requests changes.

## Prerequisites and scope

- Discover the current host's Lightroom MCP tools and image-generation capability. Read [the MCP guide](references/lightroom-mcp.md) for calls, setting names, preview fallback and blocking dialogs. Treat the live tool schemas as authoritative.
- In Codex, use the available image-generation tool and its imagegen skill. In Claude, discover an available image-to-image generator; do not assume Codex tools exist there. A text-only prompt is not a generated reference. If generation is unavailable, request a supplied/generated reference or a connected generator, and finish independent baseline capture while waiting. Do not install providers or use new paid API credentials implicitly.
- A request to execute this workflow authorizes its reference generation and iterative edits. Do not ask for confirmation at every pass. A request to create or review this skill does not authorize editing photos or generating test images.
- Work on one explicitly identified photo. Do not turn this into culling, a preset batch, catalog reorganization or an image replacement. Keep the edit on the selected photo; create a virtual copy only if requested.

Use a **768 px long-edge JPEG at quality 80** for the baseline, reference input and working comparisons. Request a larger preview or detail crop only to resolve a specific texture, clipping or mask-boundary question. Export the chosen final once at **2048 px, quality 90** for the final detail check. Keep a generated reference's master, but use a small comparison copy when the host supports resizing. Do not repeatedly load full-size images for tone and color decisions.

## 1. Pin the target and capture its baseline

1. Read the current selection. Record the catalog-local photo ID and filename; never reuse an ID from an earlier session. Resolve ambiguous multiple-photo selections before writes. Lightroom can expose the whole filmstrip when nothing is selected; a returned list alone is not authorization to edit all of it.
2. Read metadata **including `sections: ["developSettings"]`**, and list existing masks if supported. Save the initial returned settings, mask IDs/adjustments, photo ID and filename in a private session folder.
3. Get and visually inspect a bounded working preview (768 px long edge), and save it as `before`. Prefer a small JPEG export when cached previews are larger than needed, fail or seem stale; follow the MCP guide. Record baseline capture limitations honestly.
4. Create a uniquely named native snapshot, for example `Before reference edit <timestamp>`, with replacement disabled. Record its returned ID and name and confirm it exists before the first develop/mask/AI-update mutation. If snapshot creation fails, stop photo writes; preview and reference preparation can still proceed. A settings JSON is useful evidence but does not replace the snapshot.

Use a private folder such as `.cache/lightroom-reference-edit/<unique-session>/` when working in this repository. Elsewhere use a suitable local output folder. Keep photos, prompts, paths, metadata and session logs out of Git and public uploads. Only send the chosen preview to the generator required by the user's request.

## 2. Generate and inspect the reference

Read [the reference prompt guide](references/reference-prompt.md). Supply the actual baseline preview as an image input, preserving its aspect ratio. Keep identity, pose, wardrobe, objects and framing; improve only photographic lighting, tonal balance and color. Describe the intended light and palette concretely rather than asking for arbitrary beautification.

Save the generated image separately as `reference`, together with the exact prompt and provider/tool name. Inspect it before tuning. If identity, geometry or scene content drift materially, regenerate with tighter preservation instructions or disregard those differences explicitly. Never chase synthetic face details, missing objects, changed perspective or invented highlights with RAW sliders. If the user supplied a reference, inspect and use it directly; generate another only when requested.

Write a short visual gap assessment: subject brightness, highlight detail, shadow separation, skin/neutral balance, background hue/saturation and subject-background contrast. Choose two or three priorities for the first pass. Derive settings from this photo and reference; do not copy a previous photo's numeric recipe.

## 3. Tune through bounded passes

Usually make **2–4 passes**, stopping earlier when the useful differences are resolved. More passes need a specific remaining visual issue, not a fixed quota or arbitrary similarity score.

For **every pass**, in this order:

1. State the visual issue and the small group of controls expected to fix it. Record current and intended values for touched settings.
2. Apply only those settings to the pinned photo ID. Serialize all Lightroom work: finish each develop write, mask computation and export before starting another.
3. Read back the affected global settings and/or mask adjustments. Check actual saved values, not just the tool's success flag. On mismatch or timeout, inspect state before retrying.
4. Export a fresh working JPEG (768 px, quality 80) to a new `pass-01`, `pass-02`, etc. folder, keeping dimensions and export settings consistent. Inspect it against both baseline and reference. Cached thumbnails alone are insufficient to validate an edit.
5. Record what improved, any regression and the next remaining issue. Correct or revert a harmful change before adding more. Do not assume that reducing overall image difference improves the photograph.

Suggested progression, adapted to the evidence:

- **Light and neutral balance:** exposure, highlight/shadow recovery, whites/blacks, contrast and white balance. Protect highlight texture and avoid crushed shadows, orange skin or a strong global cast.
- **Color relationships:** adjust the relevant HSL channels or modest grading after the tonal balance settles. Check skin, clothing and neutral surfaces as well as the background; saturation alone rarely fixes a hue mismatch.
- **Local separation:** use subject/background or other supported masks only if global controls cannot reconcile the two regions. Inspect existing masks first, preserve their work, and track IDs of newly created masks so later passes update them rather than create duplicates. Use subtle local exposure/color changes and inspect boundaries for halos. If masks are unavailable, continue with global controls and state the limitation.

Preserve crop, geometry, process version and unrelated settings by default. Do not reset the image, apply an unrelated preset, denoise, retouch or update all pre-existing AI edits as an incidental step. Use current supported tools for masks; never inject raw mask structures into develop settings.

## 4. Verify and leave a reviewable result

1. Choose the best verified pass. If a later pass regressed, restore the chosen values (or its snapshot if one was saved), then render and inspect again.
2. Save a uniquely named final native snapshot after verifying the chosen edit. Preserve the initial snapshot and all pre-existing snapshots.
3. Read final metadata with develop settings and final masks. Confirm that the pinned photo is still the intended target and that the user's selection is preserved. Never silently redirect later writes when selection changes.
4. Export a fresh `final` JPEG at 2048 px, quality 90, and inspect it once for details and mask edges. Save a compact record containing the target, initial/final snapshot names and IDs, touched setting values, created mask IDs, pass assessments and the reference prompt/provider. Include any failed checks or unresolved rendering issues.
5. Show baseline, reference and final when the host supports images. Briefly explain the main changes, the remaining differences that Lightroom controls cannot reproduce, and the initial snapshot name for reverting. Claim completion only when settings **and** the final render were checked. Do not claim exact reconstruction or a measured match percentage without a defensible measurement.

To undo the session, apply its initial snapshot to the same photo and verify settings, masks and a fresh render. Do not automatically undo an accepted edit or delete its snapshots/artifacts at the end.
