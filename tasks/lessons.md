# Lessons

Rules written after a correction from the owner. Read at the start of every session.
Format: **pattern** — what went wrong — the rule that prevents it.

- **A delete must remove every sibling of the file.** 2026-11-06 — `delete_character` removed
  `acc_1_dexto.json` but left `.bak`; `_safe_load` treats a missing main file as corruption and
  restored it, leaving a ghost that blocked the name ("already taken") while appearing in no
  character list. Rule: any code that deletes a `_safe_save` file deletes `.bak`/`.tmp` too.

- **Never show a number twice at two levels of summary.** 2026-11-06 — buff chips (defence, guard)
  were drawn AND summed into a "Mitigation" chip, so players added them up themselves. Rule: a
  summary chip owns its parts; the parts go in its hover, not beside it. Also: no developer
  abbreviations (`4T`) in player-facing text.
