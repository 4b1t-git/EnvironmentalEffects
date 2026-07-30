# Claude continuation prompt

```text
Continue the EnvironmentalWeapons Project Zomboid 42.20 mod from
work/EnvironmentalWeapons. Read the root CLAUDE.md and project HANDOFF.md first.

Stage 1 has been regenerated from a mesh-normal-gated mask and every validator
passes, but it has NOT been seen in game yet. The three screenshots in
docs/evidence still show the retired subtle texture.

Next task: get in-game confirmation of the refined Stage 1, then capture
replacement evidence. Ask the user to install the current build, equip one
vanilla Base.HuntingRifle, use "EW Debug: force light snow", and report both the
equipped view and the dropped flat-ground view. Replace the three screenshots in
docs/evidence and update their hashes in HANDOFF.md. If the user judges the snow
too strong or too weak, adjust only the generator's -TargetUpCoverage,
-NoiseBase, and -EdgeSoftness, refreeze with -FreezeRecipe -WriteProvenance, and
update the derivative hash in the three scripts that pin it.

Hard constraints:
- single-player v1 only; multiplayer stays pinned for later;
- Base.HuntingRifle/MSR788_Rifle Stage 1 only;
- do not create Stages 2-4 until the user approves the Stage 1 direction;
- never use WorldStaticModel for firearm snow visuals;
- do not use the rejected generative image;
- no new dependencies;
- do not touch saves, vanilla, EWTC, Gemini, or audit outputs;
- the vanilla-derived asset is private development material pending
  release-rights review;
- keep DEBUG=true for this development test build.

Use work/EnvironmentalWeapons as the editable source, then validate and sync the
exact tree to outputs/EnvironmentalWeapons, rebuild the safe ZIP and external
hash manifest, and update only the verified same-ID installed mod. Use:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File
tools/sync_development_build.ps1 -Apply
Then run the same command without -Apply as a fail-closed audit.
```
