# Specification Editing

## General

- `specification.md` is the current "status quo" specifiction. Do not edit unless explicitly asked.
- `docs/specification-proper-draft.md` is the new "shiny" specification. This is the one you should edit if only asked about the "specification".
  - This file contains a chapter `0. Chapter Status`. This chapter marks each other chapter of the file as FROZEN, DONE, DRAFT or MISSING
    - If a chapter is marked FROZEN, you are not permitted to change anything in it.
    - If a chapter is marked DONE, you are only permitted to perform language changes, but not semantic changes.
    - If a chapter is marked DRAFT, you are permitted to change it's semantic meaning.
    - If a chapter is marked MISSING, the chapter does not yet exist and shall be added eventually. You are permitted to do so.
  - A block quote starting with `> TODO:` notes some tasks that shall be done. These lines can be removed if, and only if the task was fully completed.

## Formatting

- Do not use any dashes except for `-`. Do NOT use En-Dashes (`–`) or Em-Dashes (`—`).
- Stick to ASCII text as good as possible. If you require symbols from the unicode plane, use them, but inform the user about it.
