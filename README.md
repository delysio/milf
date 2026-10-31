# MILF – sector copier for Atari 8-bit

*[Wersja polska poniżej](#milf--kopier-sektorowy-dla-atari-8-bit)*

MILF 0.9 (dely/bjb 2020–2021) copies floppy disks sector by sector between
two SIO disk drives of an Atari XL/XE. It reads and writes the drive
configuration (PERCOM), formats disks, matches the density of the
destination disk to the source and can save a log of the copy operation.

It talks to the drives directly through the OS SIO routine, so it copies
any disk – DOS 2, MyDOS, SpartaDOS or non-DOS disks – as long as the
drive can read its sectors.

## Files

| File | Contents |
|---|---|
| `milf.pas` | source code (Mad Pascal) |
| `output/milf.xex` | the program |
| `output/milf.atr` | bootable MyDOS 4.53 disk (DD, 180 KB) with `DOS.SYS`, `DUP.SYS` and `MILF.XEX` |

## Starting the program

- Load `milf.xex` from any DOS or with an XEX loader, or
- boot `milf.atr`, then in the MyDOS menu press **L** (Load binary file)
  and type `MILF.XEX`. The disk does not start MILF automatically.

The program needs an Atari XL/XE with at least 64 KB of RAM. It uses the
memory from `$2500` to the top of free RAM (`MEMTOP`); turning BASIC off
gives more room for the log and the fast-copy buffer.

## Main screen

At start and after every operation MILF shows both drives:

```
Current source drive: D1
720 sectors of 128 bytes.
-------------------------------------
Current destination drive: D2
720 sectors of 128 bytes.
```

The defaults are **D1** (source) and **D2** (destination). For every drive
MILF sends *Read status* and *Read PERCOM*:

- If the drive answers with a PERCOM block, MILF shows the number and size
  of sectors computed from it. Such a drive is *configurable*.
- If the drive rejects PERCOM, MILF prints `Drive does not support PERCOM.
  Probably Atari 810 or Atari 1050.` and detects the density by reading
  sector 721: when it can be read the disk is enhanced density (1040 × 128
  bytes), otherwise single density (720 × 128 bytes). Such a drive is
  *not configurable*.
- `Drive does not respond.` means the drive is off, missing or has no
  disk (SIO timeout, status 138). `Drive error N.` reports any other SIO
  error.

Menu keys work in upper and lower case. In sub-menus **Esc** cancels the
operation and returns to the main screen. When MILF asks for a number or a
file name, **Break** cancels the input.

## Options

### R – Read drive configuration

Reads the configuration of both drives again and redraws the main screen.
Use it after changing a disk or switching a drive on.

### W – Write drive configuration

Sets the density of a configurable drive by sending it a PERCOM block. It
does not format the disk – use **F** afterwards.

1. Choose **S** (source drive) or **D** (destination drive).
2. Choose the configuration:

   | Key | Format | Sectors | Capacity |
   |---|---|---|---|
   | 1 | SS SD – single sided, single density | 720 × 128 B | 90 KB |
   | 2 | SS ED – single sided, enhanced density | 1040 × 128 B | 130 KB |
   | 3 | SS DD – single sided, double density | 720 × 256 B | 180 KB |
   | 4 | DS DD – double sided, double density | 1440 × 256 B | 360 KB |
   | 5 | DS QD – double sided, 80 tracks | 2880 × 256 B | 720 KB |

3. MILF prints `Status: OK` or `Status: error N`, reads the configuration
   back and prints `Configuration confirmed`, or `Warning. Drive may not
   support that configuration` when the drive reports something else.

A drive that does not support PERCOM shows `This drive is not
configurable.`

### F – Format drive

1. Choose **S** (source) or **D** (destination).
2. Confirm with **Y**: `All data on Dn will be lost. Continue? (Y/N)`.
   **N** or **Esc** cancels.
3. A configurable drive formats the disk in its current configuration
   (set it with **W** first if needed). A drive without PERCOM asks for
   the density: **S** – single density, 90 KB, or **E** – enhanced
   density, 130 KB.
4. The result is shown as `Status: OK` or `Status: error N`.

### D – Set source, destination drives

Type the source drive number (**1**–**8**), then the destination drive
number. The destination must differ from the source. A drive that does
not respond is rejected and MILF asks again. The new pair is used only
after both numbers are given; **Esc** keeps the previous pair.

### X – Exchange source and destination

Swaps the source and destination drives.

### C – Copy sectors

Copies a range of sectors from the source to the destination drive, one
sector at a time: read sector, write sector, next sector.

1. MILF reads the configuration of both drives. The copy stops with
   `Source drive is not ready.` or `Destination drive is not ready.` if a
   drive does not respond.
2. If the sector sizes differ, MILF offers to match the densities: `Would
   you like to match densities? Destination drive will be formatted and
   data will be lost (Y/N)`. **Y** reads the PERCOM block of the source
   drive, writes it to the destination drive, formats the destination
   disk and checks that the destination now reports the same geometry.
   If this fails (for example the source drive does not support PERCOM),
   MILF prints `Matching failed, aborting` and restores the previous
   configuration of the destination drive. **N** returns to the menu.
3. `Start sector:` – first sector, from 1 to the number of sectors of the
   source disk.
4. `End sector:` – last sector, not lower than the start sector. A number
   above the size reported by the drive needs confirmation (`Would you like
   to override data reported by drive?`); the sectors beyond the end of
   the disk will most likely fail to read.
5. MILF copies the range and shows `Reading and writing sector #N`.
   Sectors 1–3 are always 128 bytes long, also on double density disks.
6. At the end it prints `Copy finished.` (or `Copy aborted at sector N.`),
   the number of sectors read and the number of sectors not read. After an
   abort the sectors that were not reached count as not read.
7. When logging is on (see **O**) and the range has at most 2880 sectors,
   MILF asks `Write log file to disk? (Y/N)`. **Y** asks for a file name
   with the drive, for example `D1:LOGFILE.LOG` (up to 15 characters). The
   log is written through DOS, so a DOS must be loaded. On an error MILF
   prints `Error N` and asks for the name again; **Break** gives up.

What happens when a sector cannot be read or written is set with **O**.

### M – Fast copy (memory buffer)

Copies the whole disk: all sectors from 1 to the number of sectors
reported by the source drive. MILF does not ask for a range. It first
reads as many sectors as fit in memory and then writes them all to the
destination, batch after batch. A drive gets
a series of commands for consecutive sectors instead of alternating with
the other drive, so it wastes fewer disk revolutions waiting for the next
sector. In an Altirra test with accurate Atari 1050 emulation a whole
720-sector disk took 172 s instead of 244 s.

- MILF shows the number of sectors to copy and the buffer size, for
  example `Copying 720 sectors.` and `Buffer: 180 sectors.` The buffer
  takes the memory from `$6200` to
  `MEMTOP` (at most 256 sectors), so its size depends on the machine and
  on the DOS; in the default setup it holds 180 single density or 90
  double density sectors.
- Progress is shown as `Reading sector #N` and `Writing sector #N`.
- Sectors skipped after a read error are not written.
- Fast copy keeps **no log**, whatever the logging option says.
- The ready checks of both drives, density matching and error handling
  work as in **C**.
- To copy only part of a disk use **C**.

### O – Set options

Asks four questions in turn; **Esc** leaves the remaining options
unchanged.

1. `Log copy operations? (Y/N)` – keep a log during **C** (default: yes).
2. `Verify writes? (Y/N)` – write with the *Put sector with verify*
   command (`$57`) instead of *Put sector* (`$50`) (default: no). Slower,
   but the drive checks every written sector.
3. `Auto action when copy error occured:` (default: 1)

   | Key | Action |
   |---|---|
   | 1 | ask – show `Error N reading/writing sector S.` and wait for **A** (abort), **R** (retry), **S** (skip) or, after a read error, **W** (write the buffer and continue) |
   | 2 | abort the copy |
   | 3 | retry the operation, then skip the sector |
   | 4 | skip the sector |
   | 5 | after a read error write whatever is in the buffer and continue; after a write error skip the sector |

4. Only for action 3: `Retry attempts (1-99)` (default: 3). The limit
   applies separately to every sector and to its reading and writing.

Before every read the buffer is filled with zeros, so **W** / action 5
write zeros plus whatever the drive managed to send.

### Q – Exit to DOS

Jumps to DOS through `DOSVEC`.

### B – Cold start

Restarts the computer (cold start of the OS).

## Log file

The log is a plain ATASCII text file with one line per operation:

```
   1:o
   2:o
  17:r
  17:r
  17:o
```

The sector number is right aligned in four characters, followed by `:`
and a code: **o** – sector read, **r** – read error, **w** – write error.
Successful writes are not logged. A retried sector appears once per
attempt. The log holds up to 2880 lines and is limited by the free memory;
when it fills up MILF reports `Due to memory limit, log file is truncated.`

## SIO status codes

Errors are shown with the SIO status code, among others:

| Code | Meaning |
|---|---|
| 138 | timeout – the drive does not respond |
| 139 | NAK – the drive rejected the command |
| 140 | serial bus framing error |
| 142 | serial bus overrun |
| 143 | checksum error |
| 144 | device error – e.g. bad sector, write-protected disk |

## Building from source

To build the binaries you need:

- **Mad Pascal** compiler (`mp`) 1.7.8 or newer, with its `lib` and `base`
  directories – https://github.com/tebe6502/Mad-Pascal
- **MADS** assembler (`mads`) 2.1.9 or newer –
  https://github.com/tebe6502/Mad-Assembler
- **MyDOS 4.53/4** files `DOS.SYS` and `DUP.SYS`, for the disk image
- **dir2atr** from AtariSIO by Matthias Reichl, for the disk image –
  https://www.horus.com/~hias/atari/

```
mp milf.pas -code:2500 -o:milf.a65
mads milf.a65 -x -i:<MadPascal>\base\ -o:output\milf.xex
```

`mp` finds its units in the `lib` directory next to `mp.exe`; add
`-ipath:<MadPascal>\lib` if they are elsewhere. `-code:2500` places the
program at `$2500`, above MyDOS.

To make the disk image, put `DOS.SYS`, `DUP.SYS` and `milf.xex` into one
directory and run:

```
dir2atr -b MyDos4534 -D output\milf.atr <directory>
```

`-b MyDos4534` writes the MyDOS 4.53/4 boot sectors and `-D` creates a
double density 180 KB image.

---

# MILF – kopier sektorowy dla Atari 8-bit

*[English version above](#milf--sector-copier-for-atari-8-bit)*

MILF 0.9 (dely/bjb 2020–2021) kopiuje dyskietki sektor po sektorze między
dwiema stacjami dysków SIO Atari XL/XE. Odczytuje i zapisuje konfigurację
stacji (PERCOM), formatuje dyskietki, dopasowuje gęstość dyskietki
docelowej do źródłowej i może zapisać log z przebiegu kopiowania.

Program rozmawia ze stacjami bezpośrednio przez procedurę SIO systemu
operacyjnego, więc kopiuje dowolną dyskietkę – DOS 2, MyDOS, SpartaDOS czy
dyskietki bez DOS-u – o ile stacja potrafi odczytać jej sektory.

## Pliki

| Plik | Zawartość |
|---|---|
| `milf.pas` | kod źródłowy (Mad Pascal) |
| `output/milf.xex` | program |
| `output/milf.atr` | startowa dyskietka MyDOS 4.53 (DD, 180 KB) z plikami `DOS.SYS`, `DUP.SYS` i `MILF.XEX` |

## Uruchamianie

- Wczytaj `milf.xex` z dowolnego DOS-u albo loaderem plików XEX, albo
- uruchom komputer z `milf.atr`, w menu MyDOS naciśnij **L** (Load binary
  file) i wpisz `MILF.XEX`. Dyskietka nie uruchamia MILF samoczynnie.

Program wymaga Atari XL/XE z co najmniej 64 KB RAM. Używa pamięci od
`$2500` do końca wolnej pamięci (`MEMTOP`); wyłączenie BASIC-u daje więcej
miejsca na log i bufor szybkiego kopiowania.

## Ekran główny

Na starcie i po każdej operacji MILF pokazuje obie stacje:

```
Current source drive: D1
720 sectors of 128 bytes.
-------------------------------------
Current destination drive: D2
720 sectors of 128 bytes.
```

Domyślnie źródłem jest **D1**, a celem **D2**. Do każdej stacji MILF wysyła
polecenia *Read status* i *Read PERCOM*:

- Jeśli stacja odpowie blokiem PERCOM, MILF pokazuje wyliczoną z niego
  liczbę i wielkość sektorów. Taka stacja jest *konfigurowalna*.
- Jeśli stacja odrzuci PERCOM, MILF wypisuje `Drive does not support
  PERCOM. Probably Atari 810 or Atari 1050.` i rozpoznaje gęstość,
  czytając sektor 721: gdy da się go odczytać, dyskietka ma gęstość
  rozszerzoną (1040 × 128 bajtów), w przeciwnym razie pojedynczą (720 × 128
  bajtów). Taka stacja jest *niekonfigurowalna*.
- `Drive does not respond.` oznacza, że stacja jest wyłączona, nie istnieje
  albo nie ma w niej dyskietki (przekroczenie czasu SIO, status 138).
  `Drive error N.` zgłasza każdy inny błąd SIO.

Klawisze menu działają w małych i wielkich literach. W podmenu **Esc**
przerywa operację i wraca do ekranu głównego. Gdy MILF pyta o liczbę albo
nazwę pliku, **Break** przerywa wpisywanie.

## Opcje

### R – Read drive configuration (odczyt konfiguracji)

Ponownie odczytuje konfigurację obu stacji i odświeża ekran główny. Przydaje
się po zmianie dyskietki albo włączeniu stacji.

### W – Write drive configuration (zapis konfiguracji)

Ustawia gęstość stacji konfigurowalnej, wysyłając jej blok PERCOM. Nie
formatuje dyskietki – do tego służy potem **F**.

1. Wybierz **S** (stacja źródłowa) albo **D** (stacja docelowa).
2. Wybierz konfigurację:

   | Klawisz | Format | Sektory | Pojemność |
   |---|---|---|---|
   | 1 | SS SD – jednostronna, pojedyncza gęstość | 720 × 128 B | 90 KB |
   | 2 | SS ED – jednostronna, gęstość rozszerzona | 1040 × 128 B | 130 KB |
   | 3 | SS DD – jednostronna, podwójna gęstość | 720 × 256 B | 180 KB |
   | 4 | DS DD – dwustronna, podwójna gęstość | 1440 × 256 B | 360 KB |
   | 5 | DS QD – dwustronna, 80 ścieżek | 2880 × 256 B | 720 KB |

3. MILF wypisuje `Status: OK` albo `Status: error N`, odczytuje konfigurację
   z powrotem i wypisuje `Configuration confirmed` albo `Warning. Drive may
   not support that configuration`, jeśli stacja zgłasza co innego.

Stacja bez obsługi PERCOM pokazuje `This drive is not configurable.`

### F – Format drive (formatowanie)

1. Wybierz **S** (źródło) albo **D** (cel).
2. Potwierdź klawiszem **Y**: `All data on Dn will be lost. Continue?
   (Y/N)`. **N** albo **Esc** rezygnuje.
3. Stacja konfigurowalna formatuje dyskietkę w bieżącej konfiguracji (w
   razie potrzeby ustaw ją najpierw opcją **W**). Stacja bez PERCOM pyta o
   gęstość: **S** – pojedyncza, 90 KB, albo **E** – rozszerzona, 130 KB.
4. Wynik pojawia się jako `Status: OK` albo `Status: error N`.

### D – Set source, destination drives (wybór stacji)

Wpisz numer stacji źródłowej (**1**–**8**), a potem docelowej. Stacja
docelowa musi być inna niż źródłowa. Stacja, która nie odpowiada, zostaje
odrzucona i MILF pyta ponownie. Nowa para obowiązuje dopiero po podaniu
obu numerów; **Esc** zostawia poprzednią.

### X – Exchange source and destination (zamiana stacji)

Zamienia stację źródłową z docelową.

### C – Copy sectors (kopiowanie)

Kopiuje zakres sektorów ze stacji źródłowej na docelową, sektor po
sektorze: odczyt sektora, zapis sektora, następny sektor.

1. MILF odczytuje konfigurację obu stacji. Kopiowanie kończy się
   komunikatem `Source drive is not ready.` albo `Destination drive is not
   ready.`, jeśli któraś stacja nie odpowiada.
2. Jeśli wielkości sektorów się różnią, MILF proponuje dopasowanie gęstości:
   `Would you like to match densities? Destination drive will be formatted
   and data will be lost (Y/N)`. **Y** odczytuje blok PERCOM stacji
   źródłowej, zapisuje go do stacji docelowej, formatuje dyskietkę docelową
   i sprawdza, czy stacja docelowa zgłasza teraz tę samą geometrię. Jeśli
   to się nie uda (np. stacja źródłowa nie obsługuje PERCOM), MILF wypisuje
   `Matching failed, aborting` i przywraca poprzednią konfigurację stacji
   docelowej. **N** wraca do menu.
3. `Start sector:` – pierwszy sektor, od 1 do liczby sektorów dyskietki
   źródłowej.
4. `End sector:` – ostatni sektor, nie mniejszy niż początkowy. Liczba
   większa niż rozmiar zgłaszany przez stację wymaga potwierdzenia (`Would
   you like to override data reported by drive?`); sektory za końcem
   dyskietki najpewniej nie dadzą się odczytać.
5. MILF kopiuje zakres i pokazuje `Reading and writing sector #N`. Sektory
   1–3 mają zawsze 128 bajtów, także na dyskietkach o podwójnej gęstości.
6. Na końcu wypisuje `Copy finished.` (albo `Copy aborted at sector N.`),
   liczbę odczytanych sektorów i liczbę sektorów nieodczytanych. Po
   przerwaniu sektory, do których kopiowanie nie doszło, liczą się jako
   nieodczytane.
7. Gdy log jest włączony (zob. **O**), a zakres ma najwyżej 2880 sektorów,
   MILF pyta `Write log file to disk? (Y/N)`. **Y** prosi o nazwę pliku z
   napędem, np. `D1:LOGFILE.LOG` (do 15 znaków). Log jest zapisywany przez
   DOS, więc DOS musi być wczytany. Przy błędzie MILF wypisuje `Error N` i
   pyta o nazwę ponownie; **Break** rezygnuje.

Co się dzieje, gdy sektora nie da się odczytać lub zapisać, ustawia się
opcją **O**.

### M – Fast copy (szybkie kopiowanie przez pamięć)

Kopiuje całą dyskietkę: wszystkie sektory od 1 do liczby sektorów
zgłoszonej przez stację źródłową. MILF nie pyta o zakres. Najpierw czyta
tyle sektorów, ile zmieści się w pamięci, a potem zapisuje je wszystkie na
stację docelową, porcja po porcji. Stacja dostaje serię poleceń dla kolejnych sektorów zamiast
przeplatać pracę z drugą stacją, więc traci mniej obrotów dyskietki na
czekanie na następny sektor. W teście w Altirrze z dokładną emulacją
stacji Atari 1050 cała dyskietka 720-sektorowa kopiowała się 172 s zamiast
244 s.

- MILF pokazuje liczbę kopiowanych sektorów i wielkość bufora, np.
  `Copying 720 sectors.` i `Buffer: 180 sectors.` Bufor zajmuje pamięć od `$6200` do `MEMTOP` (najwyżej 256
  sektorów), więc jego wielkość zależy od komputera i DOS-u; w typowej
  konfiguracji mieści 180 sektorów pojedynczej albo 90 podwójnej gęstości.
- Postęp widać jako `Reading sector #N` i `Writing sector #N`.
- Sektory pominięte po błędzie odczytu nie są zapisywane.
- Szybkie kopiowanie **nie prowadzi logu**, niezależnie od ustawienia
  opcji logowania.
- Sprawdzanie gotowości obu stacji, dopasowanie gęstości i obsługa błędów
  działają jak w **C**.
- Aby skopiować tylko część dyskietki, użyj **C**.

### O – Set options (ustawienia)

Zadaje po kolei cztery pytania; **Esc** zostawia pozostałe ustawienia bez
zmian.

1. `Log copy operations? (Y/N)` – prowadzenie logu podczas **C** (domyślnie:
   tak).
2. `Verify writes? (Y/N)` – zapis poleceniem *Put sector with verify*
   (`$57`) zamiast *Put sector* (`$50`) (domyślnie: nie). Wolniej, ale
   stacja sprawdza każdy zapisany sektor.
3. `Auto action when copy error occured:` (domyślnie: 1)

   | Klawisz | Działanie |
   |---|---|
   | 1 | pytaj – pokazuje `Error N reading/writing sector S.` i czeka na **A** (przerwij), **R** (ponów), **S** (pomiń) albo, po błędzie odczytu, **W** (zapisz bufor i kontynuuj) |
   | 2 | przerwij kopiowanie |
   | 3 | ponawiaj operację, potem pomiń sektor |
   | 4 | pomiń sektor |
   | 5 | po błędzie odczytu zapisz to, co jest w buforze, i kontynuuj; po błędzie zapisu pomiń sektor |

4. Tylko dla działania 3: `Retry attempts (1-99)` (domyślnie: 3). Limit
   dotyczy osobno każdego sektora oraz jego odczytu i zapisu.

Przed każdym odczytem bufor jest wypełniany zerami, więc **W** i działanie
5 zapisują zera plus to, co stacja zdążyła przesłać.

### Q – Exit to DOS (wyjście do DOS-u)

Skacze do DOS-u przez `DOSVEC`.

### B – Cold start (zimny start)

Uruchamia komputer od nowa (zimny start systemu).

## Plik logu

Log to zwykły plik tekstowy ATASCII, jedna linia na operację:

```
   1:o
   2:o
  17:r
  17:r
  17:o
```

Numer sektora jest wyrównany do prawej na czterech znakach, potem `:` i
kod: **o** – sektor odczytany, **r** – błąd odczytu, **w** – błąd zapisu.
Udane zapisy nie są logowane. Ponawiany sektor pojawia się raz na każdą
próbę. Log mieści do 2880 linii i jest ograniczony wolną pamięcią; gdy się
zapełni, MILF zgłasza `Due to memory limit, log file is truncated.`

## Kody statusu SIO

Błędy są pokazywane z kodem statusu SIO, m.in.:

| Kod | Znaczenie |
|---|---|
| 138 | przekroczenie czasu – stacja nie odpowiada |
| 139 | NAK – stacja odrzuciła polecenie |
| 140 | błąd ramki na szynie szeregowej |
| 142 | przepełnienie na szynie szeregowej |
| 143 | błąd sumy kontrolnej |
| 144 | błąd urządzenia – np. uszkodzony sektor, dyskietka zabezpieczona przed zapisem |

## Budowanie ze źródeł

Do zbudowania binarek potrzebne są:

- kompilator **Mad Pascal** (`mp`) 1.7.8 lub nowszy, z katalogami `lib` i
  `base` – https://github.com/tebe6502/Mad-Pascal
- asembler **MADS** (`mads`) 2.1.9 lub nowszy –
  https://github.com/tebe6502/Mad-Assembler
- pliki **MyDOS 4.53/4** `DOS.SYS` i `DUP.SYS` – do obrazu dyskietki
- **dir2atr** z pakietu AtariSIO Matthiasa Reichla – do obrazu dyskietki –
  https://www.horus.com/~hias/atari/

```
mp milf.pas -code:2500 -o:milf.a65
mads milf.a65 -x -i:<MadPascal>\base\ -o:output\milf.xex
```

`mp` szuka modułów w katalogu `lib` obok `mp.exe`; jeśli są gdzie indziej,
dodaj `-ipath:<MadPascal>\lib`. `-code:2500` umieszcza program pod adresem
`$2500`, powyżej MyDOS-u.

Aby zrobić obraz dyskietki, umieść `DOS.SYS`, `DUP.SYS` i `milf.xex` w
jednym katalogu i uruchom:

```
dir2atr -b MyDos4534 -D output\milf.atr <katalog>
```

`-b MyDos4534` zapisuje sektory startowe MyDOS 4.53/4, a `-D` tworzy obraz
o podwójnej gęstości, 180 KB.
