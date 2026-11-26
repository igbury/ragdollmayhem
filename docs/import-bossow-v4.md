# Import bossów v4 do Studio: ostatni krok

Wszystko przed autoryzacją jest gotowe:

| Plik | Co to jest |
|---|---|
| `assets/myth/bosses.blend` | Modele v4 (Cyclops, Minotaur, Talos) ze źródłami w `build_bosses.py` |
| `assets/myth/boss_anims.blend` | Riggi kości na pivotach Motor6D i 36 akcji (12 klipów × 3 bossy) |
| `assets/myth/MythKit.glb` | Eksport dla Roblox: 248 meshy, jeden na kolor, poniżej 19 000 trójkątów każdy |
| `assets/myth/manifest.json` | Pozycja każdego mesha w przestrzeni riga |
| `assets/myth/install.luau` | Skrypt do Studio. Teraz ma `MODEL_ID = 0`, czyli wariant Import 3D |
| `assets/myth/fbx/<Boss>.fbx` | Źródła FBX: rig, części i 12 take'ów. Sprawdziłem, że ponownie importują się do Blendera |
| `src/shared/MythClips/*.luau` | Klipy wypieczone do Luau. Działają już w grze i nie potrzebują żadnego uploadu |

Animacje nie wymagają uploadu, bo gra odtwarza je z danych w `MythClips`. Upload jest potrzebny tylko dla
**wyglądu** v4 (meshe). Do tego czasu w grze widać kit v1 (asset 116507146031319).

## Wariant A: robię to ja (potrzebna Twoja zgoda w czacie)

1. W Studio otwórz **Assistant → Settings → MCP Permissions**. Zezwól na uploady assetów i dodaj folder
   `C:\Users\Kuba\Documents\ragdoll\assets\myth` do zatwierdzonych.
2. Napisz w czacie: „zgoda na upload MythKit.glb”.
3. Ja wyślę `POST /assets/v1/assets` przez Studio MCP:
   - typ: Model,
   - nazwa: „MythKit Bosses v4”,
   - twórca: grupa 1109456163.
4. Odczytam ID z operacji, nie zmyślając go. Wpiszę je do `ids.json`, wygeneruję `install.luau` i uruchomię go w trybie Edit.
5. Zaktualizuję `Rig.RINGS` (nadgarstek Cyclopsa 5.93, nadgarstek Talosa 5.755, kostka Talosa 2.555/0.95/0.12) oraz
   hitboxy, m.in. oko Cyclopsa. Potem przetestuję wszystko w Play.

## Wariant B: ręcznie przez Import 3D (bez API)

1. Studio z miejscem Ragdoll Mayhem w trybie **Edit** (nie Play).
2. **Home → Import 3D**, wybierz `C:\Users\Kuba\Documents\ragdoll\assets\myth\MythKit.glb`.
3. W oknie importu ustaw:
   - Rig General → Rig Type: **No Rig**,
   - File Dimensions: **Studs**,
   - Geometry → Merge Meshes: **wyłączone**,
   - Anchored: **włączone**,
   - Insert Using Scene Position: **włączone**.
4. Kliknij **Import**. W Workspace pojawi się model „MythKit” (albo „Scene”).
5. Napisz w czacie: „zaimportowane”. Uruchomię `assets/myth/install.luau` (z `MODEL_ID = 0` bierze
   model z Workspace), poprawię RINGS i hitboxy, przetestuję i usunę model z Workspace.
6. Zapis miejsca (Ctrl+S) należy do Ciebie. Gry nie publikuję.
