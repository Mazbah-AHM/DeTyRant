# Desktop Migration Decision

## Status

The web prototype has been removed. Godot is now the active production direction.

## Former Web Prototype

The PlayCanvas version was useful for proving the loop:

- Compact bot deathmatch arena.
- Three weapons with recoil, spread, fire rate, magazines, and reload behavior.
- Procedural sci-fi geometry and simple lighting.
- HUD, leaderboard, kill feed, respawn flow, and match timer.
- Browser pointer-lock mouse input.

Its limits are also clear:

- Most gameplay and rendering live in one JavaScript file.
- Arena art is made from primitive boxes, cylinders, and spheres.
- Movement/collision uses hand-written AABB checks.
- Browser mouse input can be improved, but it still depends on browser pointer-lock behavior.
- There is no asset import pipeline, animation pipeline, navigation mesh, editor workflow, or native build pipeline.

## Chosen Desktop Direction

Use Godot 4.x as the lightweight desktop version.

Why:

- Native desktop mouse capture is better suited to FPS controls.
- Godot gives us CharacterBody3D, collisions, scenes, materials, lighting, audio, importers, and exports without building all of that ourselves.
- Forward+ rendering gives us a stronger desktop graphics path than the current web renderer.
- GDScript is fast to iterate with, and C# remains available later if we need stricter architecture or performance-critical systems.
- The project stays small compared with Unreal or a heavy Unity setup.

## Current Port Status

- Player controller: native mouse look, grounded movement, sprinting, weapon recoil.
- Combat loop: physics raycast hitscan, tracers, hit feedback, bot health, respawns.
- Arena blockout: procedural Godot arena with collision bodies and editable generation code.
- Visual upgrade: Forward+ renderer, PBR materials, emissive trim, fog, glow, glass, stronger lighting.
- Sound pass: procedural shot, hit, reload, kill, and match event sounds.
- HUD: native Godot overlay with health, ammo, score, timer, feed, damage flash, and crosshair.

## Next Work

1. Tune mouse sensitivity, acceleration, recoil, and movement against real playtests.
2. Add muzzle flash particles and impact decals.
3. Introduce modular imported assets for walls, floors, weapons, and bot characters.
4. Add animation states for weapon handling and bot movement.
5. Build settings menus and export profiles.

## What We Do Not Do

- Do not wrap the web game in Electron and call it desktop. That would make distribution heavier without fixing the core graphics/input pipeline.
- Do not start with Unreal unless the target becomes high-end visuals over lightweight development.
- Do not rewrite everything in a low-level renderer first. That would spend too much time on engine infrastructure before the game feel is proven.
