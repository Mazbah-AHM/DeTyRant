# DeTyrant

This is the active desktop version of DeTyrant.

The browser prototype has been removed. Development now happens here.

## Pillars

- Lightweight native desktop FPS.
- Sharp mouse feel and responsive movement.
- Readable competitive combat with recoil, spread, hit zones, and fast respawns.
- High-end stylized sci-fi presentation without bloating the project.
- Import-ready art/audio pipeline with lightweight dev fallbacks.

## Run

1. Install Godot 4.6.x.
2. Open this `desktop_godot` folder in Godot.
3. Press Play.

## Controls

- `W A S D`: Move
- `Shift`: Sprint
- `Ctrl`: Crouch
- `Space`: Jump
- `Mouse`: Aim
- `Left Click`: Fire
- `R`: Reload
- `1 / 2 / 3`: Switch weapon
- `Esc`: Release cursor
- `Enter`: Restart match

## Production Asset Pipeline

- Drop first-person viewmodels into `assets/viewmodels/` using the filenames in `assets/README.md`.
- Drop the rigged enemy scene into `assets/characters/combatant.tscn` or `combatant.glb`.
- Drop surface footstep audio into `assets/audio/footsteps/`.
- The game now drives imported viewmodel animation clips, bot animation states, surface footsteps, muzzle particles, and impact decals.

## Next Quality Targets

- Source or create final original FPS viewmodel and combatant assets.
- Convert the procedural arena into an editable modular level kit.
- Add settings for sensitivity, FOV, audio volume, graphics quality, and keybinds.
