# Artifact — Phase 3: territories, observed in the running game

Studio session `ab384d6d`, Play mode, after the `AmbientSpawn` pads were rebuilt with their `Form`
attribute.

## Every rig is inside its own form's territory

```
Ambient_CAT_1        form=CAT      nearest own-form pad = 10.7 studs
Ambient_CAT_2        form=CAT      nearest own-form pad =  7.5 studs
Ambient_CAT_3        form=CAT      nearest own-form pad = 11.0 studs
Ambient_DOG_4        form=DOG      nearest own-form pad = 10.2 studs
Ambient_DOG_5        form=DOG      nearest own-form pad = 18.6 studs
Ambient_DOG_6        form=DOG      nearest own-form pad =  9.4 studs
Ambient_PIG_7        form=PIG      nearest own-form pad = 20.7 studs
Ambient_PIG_8        form=PIG      nearest own-form pad = 13.6 studs
Ambient_PIG_9        form=PIG      nearest own-form pad =  7.9 studs
Ambient_GOAT_10      form=GOAT     nearest own-form pad =  6.5 studs
Ambient_GOAT_11      form=GOAT     nearest own-form pad =  5.9 studs
Ambient_GOAT_12      form=GOAT     nearest own-form pad =  2.9 studs
Ambient_CHICKEN_13   form=CHICKEN  nearest own-form pad = 17.0 studs
Ambient_CHICKEN_14   form=CHICKEN  nearest own-form pad = 11.6 studs
Ambient_CHICKEN_15   form=CHICKEN  nearest own-form pad = 11.3 studs
Ambient_VILLAGER_16  form=VILLAGER nearest own-form pad =  8.8 studs
Ambient_VILLAGER_17  form=VILLAGER nearest own-form pad =  9.9 studs
Ambient_VILLAGER_18  form=VILLAGER nearest own-form pad =  2.6 studs

population: CAT=3  CHICKEN=3  DOG=3  GOAT=3  PIG=3  VILLAGER=3
worst leash: 20.7 studs — Config.Ambient.WanderRadius is 24
```

**Three of each, all six forms, none outside its leash.** The partition holds: no rig was sited on
another form's pad, which is what the per-form `spawnPointsByForm` split is for.

## The pads themselves

```
removed 16 old pads; 18 AmbientSpawn now tagged, 18 carry a Form attribute
```

## What this does NOT prove

**The claim refusal is not exercised at runtime.** `ClaimSlot` cannot be driven through
`execute_luau` — `require` returns a fresh module with an empty roster — so the "a monster far from
every PIG territory is refused" behaviour rests on `tests/ambient-territory.test.luau`'s four lookup
assertions rather than on a live camouflage. Same limit as Phase 2, same cause.

**The map was patched, not rebuilt.** See the implementation log's deviation note: only the
`AmbientSpawn` pads were replaced, by a script replicating `anchor()` exactly. A full builder run is
still owed before publishing.
