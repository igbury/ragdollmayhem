# Menu: trzy koncepcje, porównanie i wybór

Zrzuty pochodzą z Play w Studio (1896×735), ten sam awatar, boss losowany. Pliki są w `docs/menu-concepts/`.

## Problem wyjściowy (`0_before.jpg`)

Boss stał w tej samej scenie 3D co awatar, obok krzesła. Stopy miał celowo pod dolną krawędzią panelu
(`BOSS_FEET = -30`), więc wyglądało to na przypadkowo ucięte nogi. Do tego jego bok i dłoń wchodziły na awatara.

## Rozwiązanie techniczne (wspólne dla wszystkich koncepcji)

Boss dostał **osobny ViewportFrame pod ViewportFrame awatara**, więc fizycznie nie może go zasłonić.

Kamera bossa jest **dopasowana do całej sylwetki** (`MenuPuppet:frameBoss`):

1. Przy starcie gra przechodzi przez wszystkie pozy z menu (oddech w łańcuchach i cały ryk) i zbiera ich wspólny prostopadłościan.
2. Szuka najbliższej kamery, która zmieści wszystkie 8 narożników w kadrze z marginesem, ze stopami na dolnym marginesie.
3. Przelicza kadr przy każdej zmianie rozmiaru, więc działa też na telefonie.

Awatar ma kadr ustawiany parametrami (x, y, zoom) i też przelicza się przy zmianie proporcji.

## Koncepcje

| | Układ | Iteracje | Plusy | Minusy |
|---|---|---|---|---|
| **A: Kadr obok** | Stary układ strony, scena w prawym dolnym rogu | A1, A2 | Najmniej zmian, czytelny | Boss tej samej wielkości co awatar, nie przytłacza; scena niska, mało miejsca |
| **B: Plakat** | Scena to cała prawa kolumna; STATS i SHOP nad PLAY, MAP na dole | B1, B2, **B3** | Boss w całości i największy; PLAY nadal największym panelem po lewej; scena ~kwadratowa, więc tak samo dobra na telefonie | STATS i SHOP są niższe (napisy nadal się mieszczą, sprawdzone na 844×390) |
| **C: Scena środkowa** | Scena w środku; STATS i MAP po lewej, SHOP i PLAY po prawej | C1, C2 | Klasyczny „lobby” jak w grach imprezowych, postać w centrum | PLAY to jeden z czterech równych kafli, główna akcja traci wagę; w C1 boss chował się za awatarem |

Poprawki w kolejnych iteracjach:

- **B2 → B3:**
  - Stopy bossa były niżej na ekranie niż krzesło, choć awatar go zasłaniał. Sprzeczne wskazówki głębi.
  - Teraz awatar stoi niżej i z przodu, a stopy bossa wyżej, „dalej” na tej samej podłodze.
- **C1 → C2:** boss wyszedł zza awatara.

## Wybór: B (Plakat)

`compare.jpg` pokazuje A2, B3 i C2 jedna nad drugą.

Za B przemawia to, że:

- boss jest w całości i jest groźny (najważniejsza uwaga),
- awatar nigdy nie jest zasłonięty,
- PLAY zostaje dominującym przyciskiem,
- proporcje sceny są podobne na PC i telefonie (`B3_phone.jpg`: 844×390, boss w szczycie ryku nadal w całości w kadrze).

Mechanika menu jest bez zmian: wielokąty paneli, przewracanie stron do STATS i SHOP, hover, klik, POW, wybór mapy.

## Czego nie sprawdziłem

- Emulatora urządzeń Studio (Test → Device): nie da się go przełączyć przez MCP. Telefon zasymulowałem, zmniejszając stronę menu do 844×390 pt.
- Na prawdziwym telefonie przycisk ADMIN (tylko dla admina) leży w lewym górnym rogu na panelu STATS, tak jak wcześniej.
