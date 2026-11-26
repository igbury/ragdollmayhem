# Ragdoll Mayhem: pierwsze 5 minut, game feel i retencja

Research z 26.11.2026. Liczby z blogów i forów to reguły kciuka, nie standard: trzeba je
skalibrować na własnych danych (funnel, Experiments). Wszystkie cytaty są krótkie.

## 1) Źródła

**Oficjalne Roblox**
- https://create.roblox.com/docs/production/game-design/onboarding (OK): FTUE ocenia się po
  D1 i ukończeniu kroków. Trzy zasady: „Teach the essentials, get to the fun quickly, leave players wanting more”.
- https://create.roblox.com/docs/production/game-design/onboarding-techniques (OK): elementy
  wizualne w świecie, samouczki kontekstowe i podpowiedzi czasowe (przykład: 10 s i 11 s), plus A/B przez Experiments.
- https://create.roblox.com/docs/production/analytics/retention (OK): definicje D1, D7 i D30,
  „fun w ok. 5 minut”, małe aktualizacje co 2–4 tyg., duże co 2–3 mies.
- https://create.roblox.com/docs/production/analytics/engagement (OK): średni czas sesji oraz
  wykres „New User First Session Retention” (ilu nowych gra jeszcze po X minutach).
- https://create.roblox.com/docs/production/analytics/funnel-events (OK): API lejków, maks.
  10 lejków, wygasanie po 180 dniach, przykład spadku o 70% między krokiem 1 a 2.
- https://create.roblox.com/docs/effects/particle-emitters (OK, dodatkowe): limit 400
  cząsteczek/s na emiter na PC i 100/s na mobile.
- https://create.roblox.com/docs/production/publishing/accessibility i wątek DevForum „Introducing
  Accessibility Settings” (z wyszukiwarki): `GuiService.ReducedMotionEnabled` (tylko do odczytu).

**Reddit (podane w zadaniu)**
- https://www.reddit.com/r/robloxgamedev/comments/1sakqj4/i_tracked_retention_on_my_roblox_game_for_3/
  — **NIE POBRANO** (WebFetch blokuje reddit.com). Wyszukiwarka nie znalazła też kopii.
- https://www.reddit.com/r/robloxgamedev/comments/1vf39zh/how_do_you_keep_players_playing_past_the_first/
  — **NIE POBRANO** (z tego samego powodu).

**Dostępność**
- https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/117 (OK):
  wyłączanie wstrząsów, blura i kiwania kamery, suwaki 0–100% (przykład Halo Infinite).
- https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/118 (OK):
  progi błysków (ok. 3/s, ok. 20% ekranu, zmiana luminancji o 10%), osobny próg dla czerwieni.

**Game feel / juice** (wyniki wyszukiwania, źródła wtórne)
- GDC Vault „Juice It or Lose It” (Jonasson, Purho, 2012), https://gdcvault.com/play/1016789/Juice-It-or-Lose
  — znam tylko streszczenia. Nudny Breakout robi się zabawny po dołożeniu tweenów, błysku, wstrząsu, cząsteczek i dźwięku.
- „The Art of Screenshake” (Vlambeer, J.W. Nijman, 2013): odrzut kamery, krótki wstrząs z szybkim
  wygaszaniem, hit pause. Streszczenie: https://infovore.org/?p=5275
- Poradniki o hitstopie i wstrząsach: https://gamejuice.pages.dev/articles/screen-shake-guide,
  https://uhiyama-lab.com/en/notes/ue/game-feel-hit-feedback/ i
  https://molbv.github.io/blog/2025-06-24-juice-polish.html (2–5 klatek, 40–80 ms, wstrząs obrotowy zamiast pozycyjnego).
- https://rowatcher.com/news/your-first-90-seconds-are-destroying-roblox-retention (blog): największy
  spadek w pierwszych 90 s, a ponad 20 s do pierwszej decyzji to sygnał ostrzegawczy.
- https://medium.com/roblox-developer/from-the-devs-the-importance-of-first-impressions-on-player-retention-by-silky-dev-e63a90291279
  — **NIE POBRANO** (HTTP 403).
- DevForum o cząsteczkach na mobile, np. https://devforum.roblox.com/t/particle-emitter-limit-on-low-graphics-is-impacting-my-game/2159584:
  globalny limit renderowania ok. 3500–3600 na mobile i ok. 16 000 na PC (niepotwierdzone w docs).

**Gry referencyjne** (opisy publiczne, tylko zasady)
- Goat Simulator: https://gamesradar.com/goat-simulator-3-preview-hands-on-gamescom-2022 oraz recenzja PC Gamer
  (punkty i combo za chaos, zostawione śmieszne bugi).
- TABS (Landfall): https://gamedeveloper.com/design/how-landfall-games-finds-the-fun-in-physics-engines
  (animacja fizyczna, chwiejność jako obietnica humoru).
- Gang Beasts: https://mcvuk.com/?p=215072 oraz recenzje PC Gamer i Shacknews (fizyka dyktuje design,
  w pierwszych meczach sterowanie bywa przeszkodą).
- Slap Battles, Ragdoll Engine, People Playground: poradniki Sportskeeda i Dot Esports, strona Steam
  People Playground. Nie znalazłem wywiadów z twórcami, więc opis to wnioski z rozgrywki.

## 2) Kluczowe wnioski

**Czas do zabawy i FTUE**
1. Roblox każe pokazać „fun” w ciągu ok. **5 minut**, a blogi przesuwają tę granicę na **30–90 s**.
   Gracz Robloxa nic jeszcze w grę nie zainwestował i wychodzi jednym tapnięciem.
2. Do pierwszej realnej akcji ma minąć **nie więcej niż 20 s** (blog). Dla gry o biciu oznacza to
   pierwsze trafienie najpóźniej w 10–15 s od PLAY.
3. Długie samouczki są złe. Lepiej działają krótkie, kontekstowe podpowiedzi przy pierwszym kontakcie
   z funkcją, a rzeczy nieistotne warto przenieść do późniejszych sesji (Roblox).
4. Działanie wskazuje się w świecie (podświetlenie, strzałka, ścieżka), nie tekstem. Wskazówka zostaje
   na ekranie do wykonania kroku i znika od razu potem.
5. Podpowiedź czasową pokazuje się dopiero wtedy, gdy większość graczy już zrobiła krok. Przykład
   Roblox: większość znajduje przycisk w 10 s, więc podświetlenie pojawia się w 11 s, tylko za
   pierwszym razem. Opóźnienie (np. 5 s czy 10 s) warto testować A/B.
6. Każda akcja gracza musi dać wyraźny feedback, inaczej gracz uzna, że gra jest zbugowana (Roblox).
7. Na start dobrze działają niskie progi pierwszych nagród i startowa waluta. Ich wysokość warto testować
   w Experiments i zmieniać na żywo przez Configs.
8. Onboarding kończy się celowym „momentem radości” (nagroda, efekt) i pokazaniem celów krótkich,
   średnich i długich.

**Analityka**
9. `LogOnboardingFunnelStepEvent` wysyła się tylko z serwera i tylko w opublikowanej grze. Liczy się
   pierwsze wystąpienie kroku, a pominięte wcześniejsze kroki zostają oznaczone jako ukończone.
   Na doświadczenie przypada maks. **10 lejków**, a postęp gracza wygasa po **180 dniach**.
10. Po zmianie kroków zakres dat w dashboardzie musi zaczynać się po aktualizacji. Lejki grupują
    graczy według dnia wejścia.
11. Patrzy się na największy spadek między krokami (przykład Roblox: **70%**) i najpierw naprawia
    właśnie ten krok. Do tego warto obserwować „New User First Session Retention” po każdej aktualizacji.

**Game feel**
12. Hitstop to zwykle **2–5 klatek** przy 60 fps (**ok. 35–80 ms**). Dead Cells ma podobno 2–3 klatki.
    Zadane trafienie dostaje dłuższą i „czystszą” pauzę, otrzymane krótszą.
13. Wstrząs ma pasować do siły ciosu: przy ciosie wręcz krótki (ok. **4–8 klatek, 70–130 ms**),
    przy wybuchu jedna wolna fala z ogonem (**10–16 klatek, 170–270 ms**). Amplituda powinna szybko maleć.
14. Wstrząs obrotowy męczy mniej niż pozycyjny. Mocny wstrząs pozycyjny zostawia się na rzadkie,
    wielkie momenty.
15. Wstrząsy z wielu źródeł się nie sumują. Bierze się najsilniejszy i bramkuje go odległością od kamery.
16. Według „Juice It or Lose It” i „Art of Screenshake” radość robią warstwy: tween/easing, błysk
    trafionego, odrzut, cząsteczki, dźwięk, unoszące się liczby. Same mechaniki tego nie dadzą.

**Dostępność**
17. Według XAG 117 wstrząsy, kiwanie kamery i blur trzeba albo wyciąć, albo dać do wyłączenia.
    Najlepiej jako suwak **0–100%**.
18. Według XAG 118 błysk to zmiana luminancji o **10%** lub więcej. Przy **ponad 3 błyskach/s** na
    **20% ekranu lub więcej** test jest oblany. Nasycona czerwień ma niższy próg, długie słabsze
    miganie też może zaszkodzić. Fotoepilepsja dotyczy ok. **1 na 4000** osób.
19. Roblox ma systemowe ustawienie Reduce Motion (`GuiService.ReducedMotionEnabled`). Zaleca się przy
    nim skracać tweeny do 0 albo zamieniać je na fade.

**Wydajność mobile**
20. Jeden ParticleEmitter daje maks. **400 cząsteczek/s na PC i 100/s na mobile**. Lifetime ma limit
    20 s, a flipbook 30 fps.
21. Najwięcej kosztuje overdraw, czyli warstwy przezroczystości i duże cząsteczki. Flipbooki mogą zostać
    wyłączone na słabych telefonach. Globalny limit renderowania na mobile to według DevForum
    **ok. 3500–3600** cząsteczek.

**Gry referencyjne**
22. **Slap Battles**: od lobby do pierwszego plaskacza mija kilka sekund. Jeden przycisk, czytelny cel
    (zrzucić przeciwnika z wyspy) i absurdalny knockback. Kolekcja rękawic (ponad 200) odblokowywana
    licznikiem plaskaczy i odznakami daje cele długoterminowe.
23. **Ragdoll Engine / People Playground**: zero samouczka, od razu przycisk ragdoll albo menu spawnu.
    Mapa sama zaprasza do eksperymentu (wysokie konstrukcje, przedmioty pod ręką) i daje szybki
    reset („Clear Everything”). Fizyka jest nagrodą sama w sobie.
24. **Gang Beasts / TABS**: chwiejny ruch od pierwszej sekundy mówi graczowi, że ma się śmiać, a nie
    wygrywać. Lepiej przesadzić z reakcją ciała niż z precyzją. Ostrzeżenie z recenzji: nieczytelne
    sterowanie i słaby feedback frustrują w pierwszych meczach.
25. **Goat Simulator**: każda głupota daje unoszący się wynik i mnożnik combo, więc chaos staje się
    mierzalny. Śmieszne bugi zostają, crashe się naprawia. Liczy się to, co dzieje się między punktem A a B.

## 3) Co zastosować w Ragdoll Mayhem

Kolejność według wpływu na D1 i kosztu. Stan obecny ustaliłem z kodu tylko do odczytu:
`src/server/Funnels.luau`, `src/client/Fx.luau`, `src/server/Tutorial.luau`.

**P0: pierwsze 60 sekund**
1. **PLAY prowadzi prosto do ciosu, ma to zająć do 3 s.** Przejście kamery z menu trwa najwyżej
   ok. 0,8 s, a przy `ReducedMotionEnabled` jest cięciem albo fade. Po PLAY nic nie blokuje
   gracza: żadnego dialogu ani wyboru broni. Gracz pojawia się z bronią w ręku, przodem do manekina
   oddalonego o 6–10 studów.
2. **Pierwsze trafienie najpóźniej w 15 s.** Manekin w klatce tutorialu dostaje światową
   podświetlaną strzałkę albo obrys, bez tekstu. Dopóki gracz nie trafi, nic innego się nie dzieje.
   Podpowiedź z klawiszem i gestem pojawia się dopiero, gdy trafienia brak przez ok. 6–8 s. Opóźnienie
   trzeba potem ustawić na P75 zmierzonego czasu (patrz pkt 12).
3. **Pierwsze 3–5 trafień w sesji z przesadzonym juice.** Hitstop ok. 60–80 ms, robiony tylko
   kosmetycznie po stronie klienta: pauza animacji broni i zamrożenie offsetu kamery. Fizyki
   serwera nie wolno zatrzymywać. Do tego błysk trafionego manekina (biały, mały obszar), mocniejszy
   impuls ragdolla, dźwięk z losową wysokością ±5% i liczba obrażeń. Potem efekt spada do
   normalnego poziomu.
4. **Pierwszy KO jako celebracja.** Licznik cashu rośnie animowanie w stronę HUD, słychać
   charakterystyczny dźwięk, pojawia się sticker lub odznaka „Pierwszy nokaut”, a obok cel na
   najbliższą minutę („Jeszcze X$ do [broń]”). Konfetti tylko lokalnie, bez błysku na cały ekran.
5. **Pierwsze odblokowanie w 90–150 s.** Najtańsza kupowana broń ma kosztować tyle, ile dają 3–5
   KO z broni startowej. Gdy włącza się krok lejka „Can afford a weapon”, pojawia się jednorazowa
   podpowiedź kontekstowa przy przycisku Arsenału (podświetlenie, nie okno). Zakup kończy się
   automatycznym wyposażeniem i manekinem do sprawdzenia nowej broni.

**P1: minuty 2–5**
6. **Opcjonalny boss w 2–3 minucie.** Najpierw zapowiedź: róg, baner na górze ekranu bez pauzy
   gry, a w świecie znacznik kierunku do legowiska (Cyklop, Minotaur albo Talos zrywa łańcuch).
   Udział jest dobrowolny, nie teleportujemy gracza. Dla nowego gracza obrażenia od bossa są
   łagodne, a nagroda przypada każdemu, kto trafił choć raz. Event zachęca do gry razem, bo cios
   jest wspólny. Odpala się dopiero, gdy na serwerze jest przynajmniej jeden gracz po tutorialu.
7. **Trzy cele widoczne po tutorialu.** Krótki to następna broń (pasek postępu cashu), średni to
   stickery i wyzwania, długi to pokonanie wszystkich bossów lub cały Arsenał. Na ekranie stale tylko
   jeden, reszta w menu.
8. **Dawkowanie systemów.** Toolbox, sandbox, sklep z passami i czołg nie pojawiają się w pierwszych
   5 minutach, chyba że gracz sam je otworzy. Każdy ma swój jednorazowy tip kontekstowy przy
   pierwszym użyciu.

**P1: ustawienia game feel**
9. **Suwak „Wstrząsy kamery” 0–100% (domyślnie 100) i przełącznik „Błyski”.** Oba trzeba
   respektować razem z `GuiService.ReducedMotionEnabled`: wstrząs ×0,25 lub 0, wyłączony kick FOV.
   Dziś `Fx.shake` nie ma żadnego ustawienia gracza, a tryb wydajności zostawia wstrząsy bez zmian.
10. **Przegląd wartości wstrząsów.** `Fx.shake` losuje co klatkę nowy wektor pozycyjny (szum), a FOV
    zmienia się o `5 × magnitude`. Proponowane zmiany:
    - przejście na wstrząs głównie obrotowy z wygładzonym szumem (np. 20–30 Hz) w miejsce losowania
      co klatkę;
    - limit kicku FOV ok. 2–3°;
    - przy ciosach wręcz 0,1–0,15 s, przy wybuchach do ok. 0,3 s.
    Szczególnie do sprawdzenia jest `Disasters.luau:589` (`Fx.shake(at, 3, 3)`): 3 study przez
    3 s plus FOV ok. +15°. To mocno odbiega od zaleceń i grozi chorobą lokomocyjną.
11. **Audyt błysków i wydajności na telefonie.** Żaden efekt nie może migać więcej niż 3 razy na
    sekundę na ponad 20% ekranu, zwłaszcza w nasyconej czerwieni (wybuchy, lawa, tryb furii). Emitery
    na mobile mają ≤100 cząsteczek/s. Overdraw trzeba ograniczyć przez mniejsze i mniej warstwowe
    cząsteczki. Pomiar w emulatorze telefonu robi się przy bossie i kilku ragdollach na ekranie.
    Bez pomiaru nie ogłaszamy poprawy (AGENTS.md).

**P1: analityka**
12. **Rozszerzenie lejka Onboarding.** Dziś ma 4 kroki: Joined, Entered arena, First kill, Took pistol.
    Zasada w kodzie pozwala tylko dopisywać kroki, a lejków jest już 10, więc nowe idą na koniec:
    5 „Saw first KO reward”, 6 „Opened Arsenal”, 7 „Bought 1st weapon”, 8 „Saw boss event”,
    9 „Hit a boss”, 10 „Played 5 min”. Czasy pierwszych akcji (PLAY, pierwszy hit, pierwszy KO,
    pierwszy zakup) idą jako `LogCustomEvent` z wartością w sekundach od wejścia. Z tego wyjdzie
    rozkład P50 i P75 do ustawienia podpowiedzi czasowych. Kliknięcie PLAY trzeba logować jako
    custom event, bo nie da się go wstawić przed „Joined”.
13. **Experiments i Configs.** Na A/B nadają się opóźnienie podpowiedzi (5 s czy 10 s), startowy cash
    i cena pierwszej broni (3 czy 5 KO) oraz minuta startu bossa (2 czy 3). Miarą jest D1 i ukończenie
    lejka.

**P2**
14. **Test cichego obserwatora.** 3–5 nowych osób, w tym przynajmniej dwie na telefonie, gra bez
    żadnych wyjaśnień. Notujemy każde zawahanie dłuższe niż 3 s i każde pytanie „co teraz?”.
15. **Rytm aktualizacji.** Małe zmiany co 2–4 tygodnie, duże (nowy boss lub mapa) co 2–3 miesiące.
    Po każdej sprawdzamy wykres First Session Retention i błędy w raportach.

## 4) Czego unikać

- Monologu, cutscenki albo niepomijalnego dialogu NPC przed pierwszym ciosem. Ekranu wyboru postaci
  lub broni przed pierwszą zabawą.
- Tłumaczenia mechaniki, zanim gracz poczuje jej skutek. Ścian tekstu, zwłaszcza na małym ekranie
  telefonu.
- Podpowiedzi czasowej za wcześnie (gracz traci odkrycie) i za późno (frustracja). Powtarzania jej po
  pierwszym razie.
- Bramkowania pierwszej frajdy walutą, poziomem albo kupnem. Cen pierwszej broni wymagających więcej
  niż ok. 2–3 minut gry.
- Bossa, który w pierwszej minucie zabija nowego gracza albo wciąga go do walki bez wyboru.
- Sumowania wstrząsów z wielu źródeł, wstrząsów pozycyjnych przy każdym strzale i długich (ponad 0,5 s)
  wstrząsów bez opcji ich wyłączenia.
- Hitstopu, który zatrzymuje fizykę serwera albo wszystkich graczy. Pauza ma być lokalna, kosmetyczna
  i krótsza niż ok. 100 ms.
- Błysków na cały ekran, stroboskopów powyżej 3 Hz i migającej czerwieni na dużej powierzchni.
- Wielu emiterów z wysokim Rate, dużych przezroczystych cząsteczek nakładanych na siebie i
  flipbooków jako jedynego nośnika efektu (na słabych telefonach znikają).
- Zmiany kolejności lub znaczenia kroków lejka bez zmiany nazwy. Czytania danych z zakresu dat
  sprzed zmiany kroków.
- Wycinania „śmiesznych bugów” fizyki ragdolla, które nie psują gry. Naprawiać trzeba crashe, softlocki
  i rzeczy, które karzą gracza.
