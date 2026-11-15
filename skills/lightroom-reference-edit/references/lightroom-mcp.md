# Lightroom MCP execution guide

These names follow the Automaat/Matysh Lightroom MCP bridge. Hosts may prefix tool names differently. Discover the installed schemas and respect their version/range guards; do not infer unavailable tools from this file.

## Baseline and rollback

| Operation | Tool and important arguments |
| --- | --- |
| Selection | `get_selected_photos` with a small limit; inspect total/selection context before choosing a target |
| Develop state | `get_photo_metadata({photo_id, sections: ["developSettings"]})` |
| Existing masks | `list_masks({photo_id})`; `get_mask({photo_id, mask_id, kinds: ["adjustments"]})` for slider values |
| Before snapshot | `create_develop_snapshot({photo_id, name, replace: false})` |
| Confirm snapshot | `list_develop_snapshots({photo_id})` |
| Restore snapshot | `apply_develop_snapshot({photo_id, snapshot_id})`, followed by settings/masks read-back and render |
| Cached overview | `get_photo_preview({photo_id, size: "cull"})`; requested size is a minimum, not a maximum |

Photo IDs belong to the current catalog. Metadata without `sections: ["developSettings"]` does **not** contain develop settings. Returned basic/tone fields use camelCase; groups such as `hsl`, `detail`, `crop` and `effects` contain SDK names. Preserve a complete returned baseline rather than assuming the read and write objects have identical shapes.

## Fresh renders and preview failures

Export one working JPEG at a time to an absolute, unique folder. Use 768 px long edge and quality 80 for light/color decisions:

```json
{
  "photo_ids": ["PINNED_PHOTO_ID"],
  "destination": "ABSOLUTE_SESSION_DIRECTORY/pass-01",
  "format": "jpeg",
  "quality": 80,
  "width": 768,
  "height": 768,
  "on_existing": "rename"
}
```

Replace the example ID/path with actual values and call `export_photos`. Width and height bound the image while preserving its aspect ratio. Keep the same settings for every comparison. Inspect the reported result and actual output file; do not assume that an existing file is the result of the latest call. Save previews that are returned only inline or as base64 using the host's supported file mechanism, without printing the encoded data into the conversation.

Cached preview sizes request a **minimum** edge: even `cull` or a small numeric request can return a much larger cached image. Use export to enforce the working size; reserve `detail`/larger region previews for a concrete detail check. After choosing the final edit, override width/height to 2048 and quality to 90 for one final render. A 768 px image has about seven times fewer pixels than a 2048 px image of the same aspect ratio. This reduces image payload, but does not guarantee equivalent savings in RAW rendering, generation or connection time.

If `get_photo_preview` returns `error loading thumb`, switch to export instead of repeatedly trying different thumbnail sizes. Cached previews can also lag behind saved develop settings; use a fresh export to judge each pass. An export may add a history entry even when sliders are unchanged.

### AI Updates Recommended and other blocking dialogs

Outdated AI settings can open Lightroom's **AI Updates Recommended** dialog and block `export_photos`. Inspect the actual Lightroom UI with the host's supported computer-use tool, or ask the user to handle the specific dialog if UI access is unavailable. Do not start another export while the first is blocked.

To capture the existing appearance without recomputing prior AI work, clear **Update affected photos** and continue **Export**, if those controls are present. Do not silently update all affected photos. Capture the initial snapshot before any AI update; only perform a required update deliberately within the edit's scope. If Lightroom requires an update to render, explain the issue and preserve the baseline before proceeding. A cancellation or failed export is not a valid preview.

A detection failure such as **No sky detected** can also block Develop reads until its modal is dismissed. Read the dialog before acting, then verify the tool result and mask list. Do not kill Lightroom, reset the bridge, or repeatedly issue writes to bypass a dialog.

## Global and mask adjustments

`set_develop_settings({photo_id, settings})` accepts an allowlisted subset of SDK keys. Examples of key mappings (these are not a preset):

| Read field | Write key |
| --- | --- |
| `exposure`, `contrast` | `Exposure2012`, `Contrast2012` |
| `highlights`, `shadows` | `Highlights2012`, `Shadows2012` |
| `whites`, `blacks` | `Whites2012`, `Blacks2012` |
| `temperature`, `tint`, `whiteBalance` | `Temperature`, `Tint`, `WhiteBalance` (use `Custom` for a manual WB) |
| HSL SDK fields | e.g. `HueAdjustmentGreen`, `SaturationAdjustmentOrange`, `LuminanceAdjustmentYellow` |

Read before changing, write only the intended subset, then read back and compare. RAW and rendered-file WB scales differ; use the target's actual type and supported ranges. A snapshot is the authoritative rollback for settings not fully exposed by metadata.

For local separation, first inspect existing masks. Prefer supported `create_mask` types such as `subject` or `background`; the runtime decides which types/version combinations are available. Record each created mask ID. `create_mask` can accept initial friendly keys such as `exposure` for Subject/Sky/Background; `set_mask_adjustments` instead requires SDK `local_*` names:

```json
{
  "photo_id": "PINNED_PHOTO_ID",
  "mask_id": "ACTUAL_MASK_ID",
  "adjustments": {"local_Exposure": 0.15, "local_Shadows": 5}
}
```

The numbers illustrate units only. `local_Exposure` is in stops, typically -4 to 4, while most other local sliders use -100 to 100. Check the current schema/ranges and use `get_mask` with `kinds: ["adjustments"]` to verify saved values. Keep old masks and unrelated sliders intact. Do not repeatedly create the same mask, copy another photo's AI digests, or write `MaskGroupBasedCorrections` directly. Guarded geometry/People/Landscape tools may refuse untested Lightroom/process versions; respect that refusal.

## Sequencing and uncertain results

- Keep Lightroom calls sequential, including exports; never overlap Develop-driving calls or write during AI computation.
- A timeout does not prove that a write failed. Inspect settings, masks or snapshots before retrying, so the retry cannot create duplicate masks/snapshots or compound adjustments.
- If the UI is blocked, resolve that concrete blocker before more calls. If the blocker persists, stop writes and report the last verified state, baseline snapshot and missing verification. Do not claim a completed edit without a final render.
- If the user changes selection mid-run, keep the pinned ID as the only write target. Pause to resolve conflicting user intent before another write; do not edit the newly selected photo automatically.
