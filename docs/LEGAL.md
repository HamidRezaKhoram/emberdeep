# Legal notes

Not legal advice. Check before any commercial release.

## Game rules: SRD 5.2.1 (CC-BY-4.0)

Emberdeep's mechanics come from the System Reference Document 5.2.1, which Wizards of the
Coast released under the Creative Commons Attribution 4.0 International license. The only
condition is attribution, commercial use is allowed, and the license can't be revoked.

Attribution statement (shown in the game's credits screen and in the README):

> This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by
> Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is
> licensed under the Creative Commons Attribution 4.0 International License, available at
> https://creativecommons.org/licenses/by/4.0/legalcode.

Before release, compare this text with the legal page of the SRD 5.2.1 PDF and use theirs word for word.

## What we must not use

- The names "Dungeons & Dragons", "D&D", their logos or trade dress, in the title, store page or
  branding. Describe the game as "compatible with fifth edition" or "uses the 5E SRD".
- Content that is not in the SRD: named settings, characters, and monsters the SRD leaves out.
  If a creature isn't in the SRD 5.2.1, design our own instead.
- The separate "Basic Rules": they are not under Creative Commons.

## Data files

`game/data/srd/` holds rules data derived from the SRD. Each file says where it came from. The
current monster stats are **placeholders**; check every value against the SRD 5.2.1 before release.

## AI-generated text

GM narration is generated at play time, on the host's chosen provider. With the Claude provider,
game state and player text are sent to Anthropic's API under the host's own API key and terms.
With Local LLM or Offline, nothing leaves the host's machine. Say this in the settings screen.

## Code license

The code in this repository is MIT licensed (see `LICENSE`). Art, audio and data may carry their
own licenses; list them in `CREDITS.md` as they are added.
