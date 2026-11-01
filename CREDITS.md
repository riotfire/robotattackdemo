# Credits

Every third-party asset, addon and tool shipped in this project, with its license. Add a row before
importing anything new (see the Definition of Done in [docs/ROADMAP.md](docs/ROADMAP.md)), even when
attribution is optional.

## Code and addons

| Name | Version | Author | License | Where | Used for |
|---|---|---|---|---|---|
| LimboAI | 1.8.1 | Serhii Snitsaruk and contributors | MIT ([addons/limboai/LICENSE.md](addons/limboai/LICENSE.md)) | `addons/limboai/` | Melee behavior trees and squad blackboards |
| LimboAI logo | — | Aleksandra Snitsaruk | CC BY 4.0 ([addons/limboai/LOGO_LICENSE.md](addons/limboai/LOGO_LICENSE.md)) | `addons/limboai/icons/` | Addon editor icons |
| GUT (Godot Unit Test) | 9.7.1 | Tom "Butch" Wesley and contributors | MIT ([addons/gut/LICENSE.md](addons/gut/LICENSE.md)) | `addons/gut/` | Unit tests (dev only) |

## Art, audio and fonts

Model sources live in `assets/source/` (ignored by Godot); `tools/clayify/` turns them into the clay-ready
models in `assets/models/`.

| Name | Author | License | Where | Used for |
|---|---|---|---|---|
| [LowPoly Farm Buildings](https://quaternius.itch.io/lowpoly-farm-buildings) | Quaternius | CC0 1.0 | `assets/source/quaternius_farm/` | Barn, water tower, well, windpump, fences |
| [Nature Kit](https://kenney.nl/assets/nature-kit) 2.1 | Kenney | CC0 1.0 | `assets/source/kenney_nature/` | Trees, wildflowers, grass tufts, garden and field crops |
| [Survival Kit](https://kenney.nl/assets/survival-kit) | Kenney | CC0 1.0 | `assets/source/kenney_survival/` | Crates, rain barrel, workbench, shovel, hoe |
| [Fabric 034](https://ambientcg.com/view?id=Fabric034) (felt) | ambientCG | CC0 1.0 | `assets/textures/felt/` | Felt ground (`shaders/felt.gdshader`) |
| [Fredoka](https://fonts.google.com/specimen/Fredoka) | The Fredoka Project Authors | SIL OFL 1.1 ([assets/fonts/Fredoka_OFL.txt](assets/fonts/Fredoka_OFL.txt)) | `assets/fonts/` | All UI text, as a SemiBold variation |

## Planned (not yet in the project)

| Name | License | Planned for |
|---|---|---|
| Quaternius crops, nature, animations (farm buildings now in use) | CC0 | Art track, M2-J |
| Kenney Blaster kit; audio packs (Survival and Nature kits now in use) | CC0 | Weapons, SFX |
| KayKit Space Base Bits, Prototype Bits, Adventurers | CC0 | Robot parts, prototyping, farmer base |
| Mabel (Mixamo-rigged character, twenty Mixamo clips) | Supplied by the project owner | Verify before release | `assets/Mabel Annimation.glb` (the earlier ten-clip `assets/models/player/mabel.glb` is no longer used) | Player character and animations |
| Monowheel robot (sculpted, textured model) | Supplied by the project owner | Verify before release | `assets/Monowheel Robot Texture.glb`, split by `tools/split_monowheel.py` into `assets/models/robots/parts/` | Base of every robot's look |
| Wrench, pistol, shotgun, scythe and jetpack (textured models) | Supplied by the project owner | Verify before release | `assets/Wrench.glb`, `Pistol.glb`, `Shotgun.glb`, `Scyth.glb`, `Jetpack.glb` | The farmer's held weapons and worn jetpack |
