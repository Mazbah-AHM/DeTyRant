# Asset Drop Contract

This folder is intentionally wired into runtime code. Drop production assets here and Godot will import them.

## First-Person Viewmodels

Preferred files:

- `viewmodels/ak47_viewmodel.tscn`
- `viewmodels/ion_smg_viewmodel.tscn`
- `viewmodels/vx_pistol_viewmodel.tscn`

Fallback files if you want to import GLB directly:

- `viewmodels/ak47_viewmodel.glb`
- `viewmodels/ion_smg_viewmodel.glb`
- `viewmodels/vx_pistol_viewmodel.glb`

Recommended child/socket names:

- `MuzzleSocket` or `muzzle_socket`
- `AmmoDisplay` if the model has a `Label3D` ammo counter
- `AnimationPlayer` with clips named `idle`, `equip`, `fire`, and `reload`

## Characters

Preferred files:

- `characters/combatant.tscn`
- `characters/combatant.glb`

Recommended animation clip names:

- `idle`
- `run`
- `shoot` or `fire`
- `hit`
- `death`
- `respawn`

The gameplay collision remains a simple capsule for stable FPS combat. The imported character is a visual rig driven by bot animation states.

## Audio

Footsteps can be dropped into:

- `audio/footsteps/concrete_1.wav` through `concrete_4.wav`
- `audio/footsteps/sand_1.wav` through `sand_4.wav`
- `audio/footsteps/grass_1.wav` through `grass_4.wav`
- `audio/footsteps/stone_1.wav` through `stone_4.wav`
- `audio/footsteps/metal_1.wav` through `metal_4.wav`
- `audio/footsteps/water_1.wav` through `water_4.wav`

`.ogg` and `.mp3` are also supported by the loader.
