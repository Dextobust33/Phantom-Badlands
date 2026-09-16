# States.png — copied OUT of the asset pack on purpose

The source is `client/sprites/battlers/tf_svbattle/RMMV/system/States.png`, and that whole
directory carries a **`.gdignore`** — so Godot never imports it, nothing in it is in the `.pck`,
and `load()` on any path under it returns `null` at runtime.

That cost a round of debugging worth recording: `ResourceLoader.exists()` returns **true** for an
ignored file, because the `.import` sidecar is there. Three `[img]` tag forms were A/B/C-tested in
two different labels, all rendering nothing, before the actual check — is there a `.ctex` in
`.godot/imported/`? — answered it in one command. **Existence is the ingredient; `load()` is the
function.** `client.gd::--buildverify` now asserts this sheet loads, so a packaged build cannot
ship the Effects box with invisible icons.

768x960: eight 96px animation frames across, ten states down. See `STATE_ICON_ROW` in `client.gd`
for which row is which and which are still unclaimed.
