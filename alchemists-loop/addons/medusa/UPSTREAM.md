# Medusa (vendored)

- Upstream: https://github.com/arukurei/Medusa
- Upstream commit: `56a2b02e34bd1909fc4b0f32667ab6ab826b20e3` (Asset Library release 1.0)
- License: MIT; see `LICENSE` (copyright Alkrei, 2026)

The game uses Medusa's `Graph`/`Atom` controls only for rendering achievement paths and dispatching node taps. `Progress` and `QuestData` remain the sole owners of achievement definitions, earned state, reward grants, and saves; Medusa's `ProgressDB`/`GraphLogic` are not used.
