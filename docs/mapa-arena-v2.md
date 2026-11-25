# Mapa Arena 2.0 — Mayhem Park

Stan na 26.11.2026.

## Założenia

- Arena (środek, ±80 studs) to park miejski: plac z pomnikiem, miasteczko, park z fontanną, kręgielnia i budowa.
- Każdy boss ma własne legowisko w dzielnicy, do której pasuje:
  - Cyklop w kuźni pod wulkanem.
  - Minotaur za labiryntem z żywopłotu.
  - Talos na wyspie na jeziorze.
- Rekwizyty to modele z Blendera, które zachowują się jak dotąd (szkielety w `KINDS` i `SKINS`, opis w `Map.luau`):
  - Cały obiekt stoi jako siatka.
  - Pierwsze trafienie zamienia go w kostki w kolorach modelu.
  - Kostki się rozsypują, a potem obiekt odbudowuje się w całości.
- Bez zaimportowanego kitu nic się nie psuje. Każdy rodzaj ma zapasowy kształt z klocków, a lochy mają czerwone łuki jak wcześniej.

![Modele](mapa-arena-v2-modele.png)

Fioletowy kolor na domach i dębach to kolor zastępczy (`FE01FE`). W grze każdy rodzaj maluje go po swojemu:
- `HouseA` na żółto, `HouseB` na niebiesko, `HouseC` na różowo, `Shop` na kremowo.
- `OakA` i `OakB` na zielono (dwa odcienie), `OakC` na jesienny pomarańcz.

## Układ

| Strefa | Gdzie (x, z) | Co stoi |
| --- | --- | --- |
| Plac | środek | 8 latarni w kręgu, pomnik bohatera na (0, −40) przodem do spawnu, 4 słupy ogłoszeniowe na (±24, ±24) jako osłona |
| Bramy parku | (0, ±72), (±72, 0) | ceglane bramy „MAYHEM PARK” na czterech ścieżkach |
| Miasteczko (NE) | x 29..75, z −73..−27 | trzy domy i kawiarnia przy uliczce x = 52; blok mieszkalny (ruch po dachach) przesunięty na (18, −64), poza bramę |
| Park (NW) | wokół (−48, −48) | fontanna, 3 ławki, 5 dębów i sosna, budka z lodami |
| Kręgielnia (SW) | jak wcześniej | tor, ściana, skała, dąb |
| Budowa (SE) | wokół (50, 50) | 2 rusztowania, żuraw wieżowy, betoniarka, skrzynie, wieża, skała |

### Legowiska bossów (`Map.LAIRS`)

Każde legowisko to ramka: środek dołu na ziemi, obrócony tak, że rampa wychodzi w stronę areny (oś +z legowiska). Dół, mury z blankami, rampa, pochodnie i środek klatki są takie jak wcześniej, tylko obrócone razem z ramką.

| Boss | Środek dołu | Wyjście | Brama i otoczenie |
| --- | --- | --- | --- |
| Cyklop | (176, −96) | na zachód, w stronę kanionu | bazaltowa brama z okiem, kuźnia z kominem, kowadło. Most nad lawą kończy się 6 studs przed murem |
| Minotaur | (−61, 140) | na północ, przez labirynt | marmurowa brama z czaszką byka, posąg byka w ślepym rogu przy bramie |
| Talos | (200, 0) | na zachód, groblą do brzegu | brama minojska z rogami, 2 kolumny, 2 kosze ognia, wielka brązowa głowa wbita w piasek |

Tablica z imieniem bossa i „LET ONE OUT / FEED IT DUMMIES” stoi przy wejściu do każdego legowiska. Zastępuje dawną wspólną tablicę MYTH YARD.

**Zmiany w terenie**
- Wyspa na jeziorze urosła do x 160..240, z −32..32 (drzewa z niej zniknęły).
- Od zachodniego brzegu prowadzi brukowana grobla: x 144..160, z −16..16.
- Kanion parkour ma przerwę na z −20..20, czyli prostą drogę z areny na groblę. Napis kanionu przeniesiony na z −48.
- Napis LAKE przeniesiony na (196, 50).

**Labirynt (żywopłoty 6 studs)**
- Wejście od północy, między x −70 a −62.
- Dwa rzędy w serpentynę z dwoma ślepymi zaułkami, a na końcu brama Minotaura.
- Ściany tylko stykają się końcami, nigdy nie nachodzą (ZFight 0).
- Boss wychodzący z legowiska przebija się przez żywopłot, a ten odrasta.

## Pipeline z Blendera

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup -P assets/arena/build.py
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b assets/arena/arena.blend -P assets/arena/export.py
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b assets/arena/arena.blend -P assets/arena/voxels.py
python assets/arena/gen_install.py
```

Skrypty po kolei:

1. `build.py` modeluje 22 elementy w przestrzeni Robloxa (studs, przód −Z) i zapisuje `arena.blend`.
2. `export.py` zapisuje `ArenaKit.glb` (211 siatek, 144 tys. trójkątów, 7,6 MB, maks. 19 tys. na siatkę) i `manifest.json`.
3. `voxels.py` generuje `src/server/ArenaVoxels.luau`. Na każdy element przypadają kostki do rozpadu (5124 w sumie, żadnej luźnej) i bloki kolizji (najwyżej 48).
4. `gen_install.py` generuje `install.luau` z manifestu.
5. `render.py` robi podglądy: `blender -b assets/arena/arena.blend -P assets/arena/render.py -- OUT_DIR`.

**Wdrożenie do Studio (raz)**

1. W Studio otwórz File > Import 3D, wskaż `assets/arena/ArenaKit.glb` i zaimportuj do Workspace jako jeden model (Studio nazywa go `Scene`, skrypt przyjmie też `ArenaKit`).
2. W trybie edycji uruchom `assets/arena/install.luau`. Przenosi siatki do `ReplicatedStorage.ArenaKit` i nadaje im atrybut `Place`.
3. Zapisz place.

Od tej chwili `Map` buduje rekwizyty z siatek, a `Monsters` stawia bramy i otoczenie legowisk.

## Sprawdzone (Studio, tryb Play, bez kitu)

- Luau kompiluje się bez nowych ostrzeżeń, a `rojo build` przechodzi.
- Wszystkie trzy klatki mają ramkę `Lair` i bossa w środku dołu, przodem do rampy.
- W dołach, na rampach i w świetle bram nie stoi nic z mapy. W dołach nie ma wody.
- Symulacja `route()` na ramkach legowisk: każdy boss wychodzi rampą i wraca bez przechodzenia przez mury (0 przecięć).
- ZFight: lochy 0 i labirynt 0. Siatek nie da się sprawdzić tym narzędziem.
- Nowe rekwizyty areny nie nachodzą na siebie. Wyjątek: bez kitu zapasowy czerwony łuk północnej bramy zahacza o blok mieszkalny. Brama z Blendera (±11) już nie.

## Sprawdzone z kitem (26.11.2026)

- `ArenaKit.glb` zaimportowany przez Importuj 3D (model `Scene`), `install.luau` przeniósł 211 z 211 siatek do `ReplicatedStorage.ArenaKit` (22 elementy, każda siatka ma MeshId i `Place`). Place zapisany (Team Create, wersja 671), nie opublikowany.
- W trybie Play mapa ma 555 MeshPartów. Arena i wszystkie trzy legowiska wyglądają jak na podglądach z Blendera.
- Bramy legowisk nie zasłaniają wyjścia: filary stoją na x ±7, nadproża od y 16. Bloki kolizji bossa mają najwyżej ±2,2 studs szerokości i 9,2 studs wysokości.
- ZFight lochów i labiryntu nadal 0.

**Jeszcze nie sprawdzone**
- Prawdziwe wypuszczenie bossa przyciskiem. Test z poziomu skryptu nie wyzwolił promptu, więc trasy sprawdziła symulacja.
