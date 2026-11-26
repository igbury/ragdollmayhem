# Animacja PLAY: od kliknięcia do gry

Po kliknięciu PLAY awatar w menu:

1. słyszy klik i podskakuje na krześle,
2. robi „yes!” pięścią,
3. pochyla się, opiera o kolana i wstaje (krzesło znika),
4. zdejmuje słuchawki, strzela szyją i kostkami palców,
5. odwraca się plecami do kamery i pewnym krokiem rusza w stronę bossa.

W tym czasie boss ryczy. Kamera najpierw podjeżdża bliżej, potem idzie za awatarem i wjeżdża w tył jego głowy. Tam następuje cięcie do gry w FPP (pierwszej osoby). Całość trwa 4,67 s.

**Pomijanie:** po 0,5 s pojawia się napis „CLICK OR SPACE TO SKIP” (na telefonie „TAP TO SKIP”). Kliknięcie, dotknięcie, Spacja albo Enter przechodzi od razu do gry, gdy tylko serwer postawi postać na mapie. Obsługę pomijania ma `Menu.luau` i jej nie zmieniałem.

## Pliki

| Plik | Co to jest |
|---|---|
| `assets/menu/play_intro.py` | Źródło. Buduje w Blenderze awatara R15 (proporcje z attachmentów Roblox, czarne kontury) z krzesłem i słuchawkami. Kluczuje wszystkie ruchy i kamerę, a potem renderuje albo wypieka (bake) animację do Luau. |
| `assets/menu/play_intro.blend` | Zapisana scena z kluczami, do otwarcia i poprawiania w Blenderze. |
| `assets/menu/make_mp4.sh` | Renderuje klatki (EEVEE, 1280×720) i składa z nich MP4. |
| `src/client/PlayIntro.luau` | Animacja wypieczona z Blendera: 141 klatek przy 30 fps. Na każdą klatkę przypada pozycja i obrót roota, 14 stawów, kamera i FOV. |
| `src/client/MenuPuppet.luau` | Odtwarza `PlayIntro` na awatarze gracza w menu. Dopasowuje wysokość krzesła i podłogi do konkretnego awatara, a na koniec łączy kamerę z kamerą gry. |
| `docs/play-intro/play_intro.mp4` | Film z Blendera (5,9 s, z 0,5 s spoczynku na początku i wejściem do FPP na końcu). |
| `docs/play-intro/studio_play_test.mp4` | Nagranie z Play w Studio: prawdziwy klik PLAY, animacja i wejście do samouczka. |

## Jak wygenerować ponownie

Uruchamiaj Blender w tle (headless), nigdy w otwartej sesji użytkownika.

```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
"$B" -b -P assets/menu/play_intro.py -- --save    # zapisuje play_intro.blend
"$B" -b -P assets/menu/play_intro.py -- --bake    # zapisuje src/client/PlayIntro.luau
bash assets/menu/make_mp4.sh                      # renderuje klatki i składa docs/play-intro/play_intro.mp4
```

## Co sprawdziłem, a czego nie

**Sprawdzone:**

- Play w Studio z prawdziwym kliknięciem PLAY: cała sekwencja, cięcie do FPP i `IntroCompleted` w konsoli bez błędów.
- Film z Blendera: arkusz klatek co 7 klatek.

**Znana drobnostka:** w pierwszych 0,6 s, gdy kamera menu przechodzi w kamerę animacji, awatar przez chwilę dotyka lewej krawędzi panelu.

**Niesprawdzone:**

- Prawdziwy telefon.
- Awatary o bardzo nietypowych proporcjach. Dopasowanie wysokości krzesła i podłogi liczy się z `sitRoot` i `standRoot` danego awatara, ale testowałem tylko awatar ze Studio.
