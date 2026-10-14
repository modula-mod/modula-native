# Rollback
1. Runtime: flag `dev.moliboo.native3D` off (default) ⇒ no entry point, 2D renderer unchanged.
2. Failure: manifest/asset load failure ⇒ preview falls back to 2D `ModulaMascotFigure`.
3. Code: revert the MOL-01 merge commit; no data migration, outfit key unchanged, so no user-data cleanup.
