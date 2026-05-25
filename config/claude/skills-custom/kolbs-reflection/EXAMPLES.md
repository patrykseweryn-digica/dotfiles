# Kolb's Reflection — Examples

Good vs. bad answers per step. Use these to recognize what to push back on, and to prime the user with pattern examples from *unrelated* domains when they're stuck.

---

## Step 1: Experience

### Bad (outcome-focused)

> "Mój PR został odrzucony w code review."

**Why bad:** Outcome, not process. Nothing to improve from this directly.

**Reframe:** "OK, to wynik. Czy chcesz reflektować nad procesem przygotowania tego PR-a, czy nad tym jak zareagowałeś na feedback? To dwa różne cykle."

### Bad (multi-event)

> "Cały ten tydzień nauki Reacta poszedł kiepsko."

**Why bad:** Tygodnie zawierają dziesiątki sesji, frustracji, sukcesów. Patterns się zamulą.

**Reframe:** "Wybierz jedną, najbardziej uderzającą sesję z tego tygodnia — kiedy najbardziej coś zaiskrzyło na minus lub na plus?"

### Bad (too old)

> "Pamiętam jak miesiąc temu utknąłem na bugu w produkcji."

**Why bad:** Detale uciekły, mózg dopowie narrację.

**Reframe:** "Miesiąc temu — szczegóły już płaskie. Czy w ostatnich 2 tygodniach było coś podobnego, gdzie pamiętasz minutę po minucie jak się czułeś?"

### Bad (vague feelings, no process)

> "Czuję że jestem słaby w refactorach."

**Why bad:** To self-judgment, nie obserwowalny process. Nic do reflektowania.

**Reframe:** "Jaki konkretny refactor — kiedy, co — sprawił że tak się czujesz? Zacznijmy od tego konkretu."

### Good

> "Wczoraj wieczorem przy nauce hooków w React po 15 minutach przeskoczyłem do scrollowania YouTube'a zamiast dokończyć ćwiczenie."

**Why good:** Process (nauka → unik), specific (jeden moment, jedna sesja), recent (wczoraj), concise (jedno zdanie).

### Good

> "W poniedziałek na 1:1 z managerem nie zareagowałem na feedback o moim PR — przyjąłem go bez pytań, choć w środku się nie zgadzałem."

**Why good:** Reakcja (process), konkretny moment, recent, jedno zdanie.

---

## Step 2: Reflection — shallow vs deep

### Shallow

**Q:** Jak się czułeś?
**A:** "Sfrustrowany."

**Grilling:**
- "Sfrustrowany — gdzie to czułeś w ciele? Napięcie w szczęce, gardło, coś?"
- "W którym momencie sequence'u to się zaczęło — od razu, czy narastało?"
- "Na skali 1-10 w peaku — gdzie?"

### Deep

**A:** "Najpierw spokojny. Po 10 minutach gdy nie rozumiałem useEffect, poczułem ucisk w żołądku, ramiona w górę. Około 13 minuty zacząłem czytać dokumentację coraz szybciej, oczy skakały po ekranie. Ok 15 minuty otworzyłem nową kartę i poszedłem na YouTube — to się stało prawie automatycznie."

---

### Shallow

**Q:** Jak zareagowałeś na trudność?
**A:** "No próbowałem dalej."

**Grilling:**
- "Bądź szczery — co *najpierw* zrobiłeś, nie co próbowałeś w drugiej kolejności?"
- "Otworzyłeś coś? Wstałeś? Coś nie-związanego z zadaniem?"

### Deep

**A:** "Najpierw refresh'owałem stronę z dokumentacją myśląc że może załaduje się coś innego. Potem otworzyłem nową kartę i napisałem 'react hooks tutorial' choć już miałem otwartą dokumentację. To było uciekanie."

---

## Step 3: Abstraction — supported vs theorized

### Theorized (push back)

> "Pewnie unikam trudnych rzeczy bo w dzieciństwie rodzice mi za szybko pomagali."

**Push back:** "Co w twojej refleksji wskazuje konkretnie na ten związek? Jeśli nic — to teoria, którą może warto zweryfikować jako hipotezę przy następnej okazji, ale nie traktujmy jak ustaloną prawdę. Teraz jakie *patterny* widzisz w samej refleksji?"

### Supported

> "Widzę, że gdy czuję ucisk w żołądku przy braku zrozumienia, prawie automatycznie sięgam po nową kartę / coś łatwiejszego. To nie jest świadoma decyzja — dzieje się szybciej niż myśl o tym. Sygnał = somatyczny dyskomfort, reakcja = ucieczka do dopaminy."

**Why good:** Causal (somatic trigger → escape behavior), supported by reflection (ucisk + nowa karta są w timeline'ie), conditional (gdy brak zrozumienia, nie zawsze).

### Cross-domain check

**Q:** Czy działasz podobnie w innych częściach życia?
**Good answer:** "Tak — przy gotowaniu nowych przepisów też. Gdy nie idzie, sięgam po telefon i scrolluję, mówiąc sobie 'tylko sprawdzę powiadomienia'. To samo: dyskomfort → ucieczka do łatwego dopaminowego boostu."

---

## Step 4: Experiment — vague vs actionable

### Vague (push back)

> "Będę bardziej skupiony przy nauce."

**Push back:** "Wyobraź sobie że budzisz się jutro i widzisz tę listę. Co konkretnie robisz? Skupienie się nie wykonuje — wykonuje się akcja która ułatwia skupienie."

### Vague

> "Pracuję nad swoim unikaniem trudności."

**Push back:** "Jaki konkretny ruch wykonujesz, kiedy, w jakiej sytuacji? Z czego rezygnujesz?"

### Actionable

> "Przed każdą sesją nauki Reacta: telefon do innego pokoju + minutnik 25 minut. Gdy czuję ucisk w żołądku, nie sięgam po nową kartę — zapisuję na karteczce 'co konkretnie nie rozumiem' i czytam ten fragment dokumentacji jeszcze raz."

**Why good:** Konkretny trigger (czujesz ucisk), konkretna akcja (karteczka, re-read), waking-up-tomorrow ready.

### Actionable

> "Po każdym code review: 5 minut na napisanie w notatniku '1 rzecz z którą się nie zgadzam i dlaczego', zanim odpowiem reviewerowi."

---

## Pattern-priming examples from other domains

Użyj tych gdy user się zaciął, by uruchomić pattern matching **bez wbijania pomysłu z jego sytuacji**:

### Avoidance pattern
> "Niektórzy, gdy zaczynają trening i czują że jest cięższy niż zwykle, nagle 'przypominają sobie' że muszą sprawdzić maila. Czy coś takiego u ciebie zachodzi?"

### Comfort-seeking under stress
> "Jak ktoś dostaje mocny mail od szefa, czasem łapie się na tym że nagle robi sobie kawę albo otwiera fridge — zamiast od razu otworzyć maila. Czy widzisz coś podobnego w swoim sequence?"

### Perfectionism avoidance
> "Bywa że ludzie odkładają zaczęcie projektu bo 'nie mają jeszcze idealnego planu' — i w międzyczasie robią rzeczy które są bardziej widoczne ale mniej ważne. Czy to rezonuje?"

### Outcome-attachment
> "Niektórzy uczą się tylko tego, w czym już są dobrzy — bo dobre wyniki w tym dają im pewność że nauka 'działa'. Unikają trudniejszych obszarów gdzie wyniki byłyby gorsze. Coś z tego widzisz w sobie?"

### Triggers from environment
> "Niektórzy ludzie przy każdym powiadomieniu telefonu czują automatyczną potrzebę sprawdzenia — nawet jeśli wiedzą że to nic ważnego. Czy masz coś analogicznego w swoim środowisku nauki/pracy?"

**Zasada doboru:** dobieraj domeny *odległe* od aktualnej sytuacji usera. Jeśli reflektuje nad nauką — daj przykład z treningu/gotowania/relacji. Jeśli nad code review — daj z konfliktu w związku lub spożywania jedzenia. To uruchamia abstrakcję wzorca, nie zasiewa konkretnej odpowiedzi.
