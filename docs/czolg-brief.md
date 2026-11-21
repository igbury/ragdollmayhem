# Brief: CZOŁG (pomysł z komentarzy na TikToku)

Najwięcej lajków pod pierwszym TikTokiem dostał komentarz „Tank from world war 2 germany”. Robimy
ciężki czołg z II wojny światowej, wzorowany sylwetką na Tigerze I, w komiksowym stylu gry. Da się
nim jeździć, obracać wieżą z lufą, strzelać, a sam czołg rozpada się na klocki jak wszystko na mapie.

## Zasada nr 1: bez symboli

Roblox zakazuje symboliki nazistowskiej. Na czołgu i w grze **nie ma**:
- swastyk, krzyży (Balkenkreuz), orłów, run SS ani flag,
- niemieckich napisów wojskowych, nazw jednostek ani nazwisk,
- nazwy „Tiger” w UI.

W grze nazywa się **TANK**, w toolboxie „Tank”. Numer na wieży, np. „131” jak na zdjęciu, może zostać,
bo to tylko cyfry. Sylwetka ma kojarzyć się z epoką, ale nic na pojeździe nie wskazuje na stronę konfliktu.

## Wygląd (komiksowo, jak radiowóz i bronie z zestawu komiksowego)

Referencja: Tiger I ze zdjęć. Bierzemy charakterystyczne bryły i przerysowujemy je jak w kreskówce.
- **Kadłub:** kanciasty, płaskie płyty, przód lekko pochylony. Szeroki, z błotnikami nad gąsienicami.
- **Wieża:** duża, prawie prostokątna z zaokrąglonym tyłem, wysunięta nad kadłub. Kopułka dowódcy z
  włazem, skrzynka na narzędzia z tyłu wieży, zapasowe ogniwa gąsienic na bokach.
- **Lufa:** przesadnie długa i gruba, z dwukomorowym hamulcem wylotowym na końcu. Długość ok. 1,3×
  realnych proporcji, bo to „gag”.
- **Koła i gąsienice:** duże, nakładające się koła jezdne (po 4 widoczne z boku), koło napędowe z
  przodu, szerokie gąsienice z wyraźnymi ogniwami.
- **Detale:** dwie rury wydechowe z tyłu, karabin w kadłubie po prawej (ozdoba), haki holownicze,
  łopata i kilof przypięte do błotnika.
- **Kolory:** piaskowy żółty (#C9B27C) jako główny, oliwkowe i brązowe plamy kamuflażu, ciemny metal
  na gąsienicach i lufie (#2E2E30), lekkie przybrudzenie dołu. Płaskie barwy z cieniowaniem i
  krawędziami jak w reszcie kitu (bez fotorealistycznych tekstur).
- **Skala gry:** kadłub ok. 10 × 18 × 4 studa (szer. × dł. × wys.), wieża ok. 7 × 8 × 3, lufa ok.
  11 studów. Czołg ma być wyraźnie większy od radiowozu (6,6 × 16,8), a postać stojąca obok sięga mu
  do połowy wieży.
- **Budżet:** jak auta z kitu. Kilka tysięcy trójkątów łącznie, podzielone na osobne części (niżej),
  bez tekstur 4K.

## Części modelu (każda pęka na klocki osobno)

W Blenderze, w `assets/army/army.blend`, przez ten sam pipeline co auta: `assets/army/build.py` →
`ReplicatedStorage.ArmyKit`, a `assets/army/voxels.py` generuje kostki do `src/server/CarVoxels.luau`.
Części i ich nazwy:

| Część | Uwagi |
|---|---|
| `Tank_Hull` | kadłub bez błotników |
| `Tank_FenderL`, `Tank_FenderR` | błotniki z narzędziami |
| `Tank_TrackL`, `Tank_TrackR` | gąsienice (jedna bryła na stronę) |
| `Tank_Wheel` | koło jezdne, instancjonowane po 4–8 na stronę |
| `Tank_Turret` | wieża z kopułką i skrzynką |
| `Tank_Mantlet` | jarzmo działa (pivot elewacji) |
| `Tank_Barrel` | lufa z hamulcem wylotowym, pivot w jarzmie |
| `Tank_Exhaust` | rury wydechowe z tyłu |

Układ jak w `server/PoliceCar.luau`: przestrzeń pojazdu ma ziemię pod środkiem na y 0, przód w −Z.
Pivot wieży leży na osi obrotu w stropie kadłuba, pivot lufy w osi czopów jarzma.

## Jazda

- Spawn z toolboxa (zakładka SPAWN), obok „Police car” i „Sport car”. Wsiadanie pod T przy włazie,
  wysiadanie spacją, jak w autach.
- **Sterowanie czołgowe:** W/S gaz i wsteczny, A/D obrót. Przy zerowym gazie czołg obraca się w
  miejscu (skręt różnicowy gąsienic). Gamepad i dotyk działają jak w `client/Driving.luau`.
- **Fizyka:** ciężki i stabilny. Wolny rozpęd, prędkość maksymalna ok. 22 studów/s, nie wywraca się
  na zakrętach. Wjeżdża na niskie przeszkody, krawężniki i rampy. Gąsienice dla prostoty fizyki mogą
  być kołami z dużym tarciem (np. 4 niewidoczne cylindry na stronę). Widoczne koła i gąsienice tylko
  się kręcą lub przewijają w rytm prędkości danej strony.
- **Taranowanie:** przejechanie manekina go przewraca i wyrzuca w ragdoll. Wjazd w ścianę przy
  prędkości wywołuje `Map.blast` w miejscu zderzenia, jak crash auta. Ściana pęka, a czołg traci
  tylko kilka kostek z przodu, bo jest dużo wytrzymalszy od auta.
- Sieć: serwer daje kierowcy network ownership, jak w autach.

## Wieża i lufa

- Wieża obraca się niezależnie od kadłuba w stronę, w którą celuje kamera lub mysz, z ograniczoną
  prędkością (ok. 60°/s), żeby było czuć ciężar. Wraz z wieżą słychać szum serwa.
- Lufa unosi się i opuszcza w zakresie od −8° do +20°.
- Kamera trzecioosobowa za wieżą, celownik na środku ekranu. Pokazuje on, gdzie poleci pocisk
  (z uwzględnieniem łuku), i podczas przeładowania zamienia się w pasek postępu.
- Obrót liczy klient kierowcy dla płynności, a serwer replikuje kąty wieży i lufy innym graczom.
  Serwer ogranicza prędkość obrotu i zakres elewacji, żeby nie dało się ich oszukać.

## Strzelanie

- LPM (gamepad: R2, dotyk: przycisk FIRE) wystrzeliwuje pocisk z wylotu lufy.
- Pocisk to lecący obiekt z lekkim opadaniem (krótki łuk) i smugą. Przy trafieniu robi
  wybuch przez istniejące `explode()` z serwera, większy niż granat (skala ok. 1,5), więc `Map.blast`
  i `smash` działają jak przy rakiecie. Manekiny w zasięgu latają, mapa pęka na klocki.
- Przeładowanie ok. 2,5 s. Serwer pilnuje kadencji i tego, że strzela kierowca siedzący w czołgu.
- **Efekt strzału (dopamina):** błysk i kłąb dymu z hamulca wylotowego, lufa cofa się i wraca
  (odrzut), cały czołg buja się do tyłu, kamera się trzęsie, potężny huk, a po chwili brzęk
  przeładowania.
- Strzał do policji lub wojska podbija gwiazdki „wanted” przez `Wanted.act`, jak inne bronie.

## Niszczenie na klocki

- Jak auta w `server/PoliceCar.luau`: każda część jest jedną bryłą, dopóki nie dosięgnie jej
  `Map.blast` (wybuchy, odłamki broni, punt). Wtedy pęka w miejscu na kostki 1-studowe (`CarVoxels`),
  a kostki w zasięgu odlatują jak cegły z `Map.knock`.
- Czołg jest wytrzymalszy od auta:
  - pociski z broni palnej tylko odłupują pojedyncze kostki,
  - wybuchy (C4, TNT, rakieta, pocisk innego czołgu) wyrywają całe fragmenty,
  - próg rozpadu (odpowiednik `WRECK_AT`) jest wyższy niż w autach.
- **Komiczny rozpad:** po przekroczeniu progu wieża wystrzeliwuje w górę i koziołkuje (ragdoll
  wieży), kierowca wylatuje przez właz, gąsienice się zsuwają, kostki się rozsypują, a po chwili
  wrak znika.
- Uszkodzone części działają dalej, dopóki istnieją. Zniszczona lufa blokuje strzelanie, a zniszczona
  gąsienica sprawia, że czołg kręci się w kółko na jedną stronę.

## Dźwięki

Diesel na biegu jałowym i przy gazie, stukot gąsienic zależny od prędkości, serwo wieży, huk
działa, brzęk przeładowania, zgrzyt przy taranowaniu. Wszystko przez `shared/Sfx`, wybrane
skillem roblox-sfx (Creator Store) albo wygenerowane jak inne SFX w projekcie.

## Czego nie robimy teraz

Drugiego karabinu, załogi NPC, pasażerów, wielu typów amunicji i AI czołgów wroga. Można to dodać
później, jeśli czołg się przyjmie.

## Gotowe, gdy (test w Studio)

- [ ] Czołg spawnuje się z toolboxa, da się wsiąść, jechać, obracać w miejscu i wysiąść.
- [ ] Wieża i lufa podążają za celowaniem z ograniczoną prędkością i w zakresie elewacji, a inni
      gracze widzą te same kąty.
- [ ] Strzał robi wybuch w miejscu trafienia, rzuca manekinami i kruszy mapę. Kadencja jest
      pilnowana na serwerze.
- [ ] C4 lub rakieta odrywa kawałki czołgu. Po przekroczeniu progu wieża wylatuje, kierowca wypada,
      a wrak się rozsypuje.
- [ ] Taranowanie manekina daje ragdoll, a ściana przy prędkości pęka.
- [ ] Na czołgu nie ma żadnego krzyża, swastyki ani niemieckiego oznaczenia (sprawdzić z bliska
      ze wszystkich stron).
- [ ] FPS na kliencie nie spada wyraźnie przy rozpadzie wraku. Zmierzyć tak jak przy autach.

## Pod następny TikTok („You voted, we built it”)

Ujęcia, które warto mieć:
- czołg wjeżdżający w kadr,
- obrót wieży prosto na kamerę,
- strzał w slow-mo z odrzutem,
- manekiny wylatujące w powietrze,
- C4 na czołgu i wieża lecąca do nieba,
- na końcu screenshot zwycięskiego komentarza.
