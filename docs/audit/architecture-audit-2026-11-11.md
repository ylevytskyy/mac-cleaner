# Архітектурний аудит: mac-cleaner — `mac-cleaner.sh` (увесь інструмент) — 2026-11-11

- **База:** `feat/cleanup-script-improvements` @ `88e5855` (dirty: так — лише `CLAUDE.md`, `AGENTS.md`, `ARCHITECTURE.md`; `mac-cleaner.sh` чистий)
- **Обсяг:** `mac-cleaner.sh` (3195 рядків, 134 функції); виключено: `docs/`, `specs/`, `README.md` (читались лише як контекст)
- **Stack profile:** немає (zsh). Аудит пройшов лише чотири базові виміри, без п'ятого. Профільних інструментів немає, тому всі вимірювання зроблено ad-hoc через awk/grep.
- **Запущено:**
  - `zsh -n mac-cleaner.sh` → exit 0.
  - awk-таблиця функцій → 134 функції, 18 довші за 50 рядків (найдовші: `category_app_caches` 169, `main` 140, `category_container_vms` 106).
  - awk-глибина вкладеності → d0=70, d1=30, d2=25, d3=4, d4=4.
  - grep → `rm -rf` 94, `$(du_safe` 68, `|| true` 25, `2>/dev/null` 27, `run_cmd` 99 викликів (16 захищені `||`, 18 незахищені просто в тілі категорії).
  - `comm` трьох реєстрів категорій → 64/64/64 ключі, 0 розбіжностей у ключах, 2 розбіжності в групах.
  - /tmp-харнеси: справжні функції, вирізані з файлу, на fixture-HOME у пісочниці.
  - Пісочничні `HOME=/tmp/… ./mac-cleaner.sh --dry-run [--scan] </dev/null` → exit 0, без промптів у `--scan`.
  - Справжній `~/.mac-cleaner.log` прочитано read-only: 25 запусків.
  - Контрольні перевірки в основному потоці:
    - модель errexit → exit=1, наступна категорія не запускається;
    - у дочірньому `zsh -c` nullglob вимкнений, а glob без збігів дає rc=1;
    - денайліст `category_app_caches` не містить CocoaPods, sccache і bazel (0 збігів).
- **Лише читання:** SOLID/межі/складність за кодом; доступність `--yes` на typed-`DELETE`; документація Gradle (`--stop`) і upstream-код GPT4All, які верифікатори прочитали в цій сесії.
- **Не запускалось:**
  - справжній (не dry-run) прогін і `--yes`, справжній HOME, `sudo`;
  - справжні brew/docker/colima/tmutil/simctl/gradle;
  - живі застосунки — бо інструмент видаляє реальні дані.
  - Підтвердження про `rm()` у `~/.zshenv` не перевірено: харнес заблокувала перевірка безпеки.
- **Верифікація:** 16 High/Critical знахідок рецензентів пішли до незалежних верифікаторів → 15 confirmed, 1 doubtful (знижено), 0 refuted. Після злиття дублікатів між вимірами лишилось 7 High.

## 1. Executive Summary

**Health index: 0/10** = max(0, 10 − 2·0 Critical − 1·7 High − 0.25·14 Medium) = max(0, −0.5). Окремо є 5 Low.
**Failure risk: High** — від H1, H2, H3, H4, H5, H6 (core path).

Чому High, а не Critical: один рецензент і його верифікатор оцінили H1 як Critical. Я лишив High, бо збій потребує конкретної події: команда очищення має впасти в одному з 18 місць. Наприклад: permission-denied або TCC на файлі кешу, EACCES на `npm i -g`, неправильний пароль `sudo`, кеш Safari лише з dotfiles.

Є непрямий доказ з живого логу. Справжній прогін `db72b382` (2026-11-01, `--yes`) обірвався після `CLEAN category=Trash` без `END` і без `ABORT`. Саме далі йдуть `check_tool_versions`, `check_outdated_globals` і `system_maintenance`, а в них є незахищені `run_cmd` (2791, 2829, 3040, 3046). Це узгоджується з H1 (або з L5 — закритим терміналом), але не доводить його. Якщо підтвердиться, що це H1, ризик стає Critical.

Що працює:
- Межа `--dry-run` тримається: усі 99 деструктивних викликів ідуть через `run_cmd`, обходів 0 (EXEC, grep + пісочничний прогін).
- `--scan` справді read-only і без промптів (EXEC).
- Typed-`DELETE` на Xcode Archives та iOS backups не обходиться `--yes`. `confirm`/`confirm_explicit` відмовляють на EOF (EXEC).
- Реєстр ключів категорій сьогодні синхронний: 64/64/64, невідомий ключ дає exit 2 (EXEC).
- Звільнені байти міряються через du до/після, а не припускаються, тож `TOTAL_FREED` чесний (виняток — H3).

Чому ризик High:
- **H1:** одна невдала команда в 18 місцях вбиває весь прогін без `ERROR`/`END`, і решта категорій не запускається.
- **H2:** невдалі або часткові видалення логуються як `CLEAN` і рахуються очищеними.
- **H3:** сирітський pnpm v3 store логує `CLEAN` з повним розміром навіть під `--dry-run`.
- **H4:** `zsh -c`-glob без nullglob/dotglob: dotfiles ніколи не видаляються, а «порожні» каталоги дають rc=1 (у комбінації з H1 — обрив прогону).
- **H5:** `category_app_caches` видаляє кеші, якими володіють інші категорії, обходячи їх `--skip`/відмову і зупинку демонів.
- **H6:** `category_llm_caches` видаляє весь каталог GPT4All, де за замовчуванням лежить історія чатів (дані користувача).

## 2. Знахідки за вимірами

### 2.1 solid — SOLID і модульний дизайн

| Sev | Файл / сутність | Принцип | Ризик | Evidence | Verdict |
|---|---|---|---|---|---|
| High | `mac-cleaner.sh:358-468` `run_category`/`run_paths_category` + 23 bespoke-обгортки | SRP, DRY, LSP | Контракт «розмір → empty-skip → prompt → видалення → вимір → облік → лог» скопійовано вручну в 23 з 62 `category_*` (10 не покриті жодним settled-рішенням). Копії вже розійшлись: регресія `--scan` у 8b66e92 (privileged `docker run` без guard на SCAN_ONLY, виправлено в 260b599), bazel без `return` після ERROR (H2). Лічильники: `TOTAL_FREED` пишеться в 29 місцях, `CATEGORIES_CLEANED` у 23, `SCAN_TOTAL` у 26. Також solid-13, boundaries-07, solid-15 | CODE | confirmed (H7) |
| Medium | `mac-cleaner.sh:397-416` `run_category`; напр. `:1465-1467`, `:472-474`, `:513`, `:535` | Правило 2, LSP | Перевірка `have` стоїть усередині cleanup, тобто після промпту. Коли інструмента немає, користувач погоджується, а в лог іде `SKIP tool_not_installed` + `CLEAN freed_bytes=0`, і категорія рахується (харнес: ccache). Також boundaries-09 | EXEC | — (M9) |
| Medium | `mac-cleaner.sh:168-175`, `:205-216`, `:306-311` arg parsing / `is_category_enabled` | Fail-fast, OCP | `--only=` (порожньо) запускає все: зі `--yes` у скрипті з порожнім `$CATS` це очистить усе. `--skip "npm yarn"` проходить валідацію підрядком і нічого не пропускає. `--prepare-for-pnpm` ігнорує `--skip` | EXEC | — (M10) |
| Medium | `mac-cleaner.sh:69-157`, `:196-203`, `:3090-3176` реєстр категорій | SSOT, OCP | Нова категорія потребує 3 синхронних правок + денайліст app_caches + README. Групи вже розійшлись: adobe у списку `media`, а запускається з `media,apps`; ios_backups у списку `userdata`, а запускається з `userdata,system`. Через це `--only system` вибирає єдину категорію даних користувача (EXEC). Група `media` відсутня в `--list`. Також complexity-registry, boundaries-12 | EXEC | — (M11) |

Вимірювання: 62 `category_*`; 23 обходять обидва раннери; у реєстрах `VALID_CATEGORY_KEYS` 77 токенів (64 ключі + 13 груп; `browsers`/`containers` подвоєні). Подій у лозі: SKIP 78, DECLINE 34, CLEAN 30, SCAN 18, ERROR 16.

### 2.2 boundaries — зв'язність, шари, ізоляція фіч

| Sev | Файл / сутність | Принцип | Ризик | Evidence | Verdict |
|---|---|---|---|---|---|
| High | `mac-cleaner.sh:960-1000` `DENY_NAMES`, `:1085-1100` `category_app_caches`; `:2914-2919` `category_user_logs` | Single owner, SSOT | Узагальнений обхід `~/Library/Caches` видаляє CocoaPods, `Mozilla.sccache`, `bazel`, `go-build`, а також кеші Slack, Spotify і Zoom (спека 2026-05-07, рядок 58, вимагає їх виключити) і живий кеш Chrome — без pgrep. Він обходить `--skip`/DECLINE категорій-власників і пропускає їхню зупинку sccache-сервера та `bazel shutdown`. Спека 2026-05-07, рядки 31-32: CocoaPods «must be in category A's denylist»; у жодному коміті його там не було. `--scan` рахує ці каталоги двічі. `user_logs` перекриває `coresimulator_logs` і `android_studio_logs` без їхніх running-check. Також solid-05, boundaries-04, complexity-app-caches-overlap | EXEC | confirmed (H5) |
| Medium | `mac-cleaner.sh:20-21`, `:44`, `:160-216`, `:282-285`, `:3195` | Тестованість | Під час завантаження файл парсить аргументи, ставить trap і безумовно викликає `main`, тож функцію не можна підключити через `source`. Аудиторам довелось вирізати діапазони через `sed`. Головне: `run_cmd` у `--dry-run` повертає 0 ще до виконання команди та `set -e`, тому єдина тестова стратегія репо (dry-run) **структурно сліпа** до H1, H2 і H4 | EXEC | — (M13) |
| Medium | `mac-cleaner.sh:387`, `:393`, `:407`, `:416` `run_category` → `log` | SSOT, правило 9 | Одна категорія фігурує під 2-3 іменами: ключ `run_cat` (`deriveddata`), display-name з пробілами (`category=Xcode DerivedData`) і bespoke snake-name (`xcode_archives` для ключа `archives`). 29 з 33 викликів `run_category` мають пробіли, що ламає key=value-формат зі спеки. Події ABORT/WARN/SCAN/INFO/UPDATE поза специфікацією. Також solid-07, complexity-log, resilience-log-format | EXEC | — (M12) |
| Low | `AGENTS.md` (repo layout) | Актуальність документації | Посилання зсунулись на +18 рядків після 88e5855: 3177→3195 рядків, `main` 3036→3054, `browser_caches` 2131→2143, `macos_installers` 2685→2703, `ios_backups` 2934→2952. «Seven categories bypass run_category», а фактично 25; `cleanup_gradle` іде через `run_category` | CODE | — (L3) |

Вимірювання: деструктивних команд поза `run_cmd` — 0; 7 prune-команд ідуть через `_vm_cleanup_one` → `run_cmd` (:1706). Записи глобальних змінних: `TOTAL_FREED` у 28 функціях, `CATEGORIES_CLEANED` у 23, `SCAN_TOTAL` у 26, `SCAN_COUNT` у 27. `container_vms` додає до `TOTAL_FREED`, але не до `CATEGORIES_CLEANED`; `browser_caches` перезаписує `CATEGORIES_CLEANED` зі знімка.

### 2.3 complexity — когнітивне навантаження й гігієна

| Sev | Файл / сутність | Принцип | Ризик | Evidence | Verdict |
|---|---|---|---|---|---|
| High | 20 сайтів `zsh -c 'rm -rf …/*'`: `mac-cleaner.sh:725`, `730`, `852-854`, `868`, `1334`, `1350`, `1366`, `1368`, `1417`, `1433`, `1777`, `1948`, `2200`, `2216`, `2350`, `2486`, `2497`, `3012` | POLA (zsh-семантика) | Дочірній `zsh -c` не успадковує `setopt nullglob` (перевірено: `child_off`), а `*` без `globdots` пропускає dotfiles. Підтверджено: кошик лише з `.DS_Store` → `no matches found` → `ERROR category=Trash rc=1`. Кошик з видимим файлом і 1 MB прихованого → `CLEAN`, прихований файл лишається. `expo_metro` → `ERROR` після успішного видалення, бо `haste-map-*`/`react-*` відсутні. На 1948 (Safari) і 1777 (colima) у комбінації з H1 обривається весь прогін (Safari відтворено). `(N)` додано лише до DiagnosticReports (260b599). Також boundaries-03, resilience-zsh-c-glob | EXEC | confirmed (H4) |
| Medium | `mac-cleaner.sh:1071`, `1337`, `1353`, `1384`, `1420`, `1842`, `1926`, `1963`, `2022`, `2093`, `2203`, `2219`, `2311`, `2382`, `2610`, `2675`; патерни `:2153-2189` | DRY | 16 копій running-check з різними патернами. Лише Devin (88e5855) ловить `~/Applications`; Chrome, Arc, Edge, Brave, VS Code, Cursor, Windsurf, Slack і Android Studio — ні, тож кеш видаляється під живим застосунком. Саме від пошкодження індексу disk_cache цей guard і захищає (EXEC: argv0 з `~/Applications` → NO MATCH). Також solid-11, resilience-pgrep-anchored (core path) | EXEC | — (M7) |
| Medium | `mac-cleaner.sh:956-1124` `category_app_caches` | KISS, SRP | Найдовша функція (169 рядків, вкладеність 4) — і це код виняткової `rm -rf` safety-зони, яку найважче рев'ювити. Правило «Google → AndroidStudio*/Chrome, інакше денайліст» перекодовано тричі (розмір/видалення/вимір), і копії вже розійшлись: розмір рахує AndroidStudio* навіть тоді, коли його буде пропущено. `_app_caches_is_denied` при кожному виклику визначається як глобальна функція | CODE | — (M14) |
| Low | `mac-cleaner.sh:19`, `:240-254`, `:292` `du_safe`/`DU_CACHE` | CQS, YAGNI | «Fast du cache» з 8b66e92 не працює: усі 68 викликів ідуть у `$(…)`-сабшелі, тож `${#DU_CACHE}`=0, а `DU_CACHE=()` у `run_cmd` нічого не робить (EXEC). Великі дерева обходяться двічі: llm_caches, ios_backups. Також solid-14, boundaries-11 | EXEC | — (L1) |
| Low | `mac-cleaner.sh:3`, `241`, `419-421`, `951`, `2845`, `3029`, `3055`, `3061` | Актуальність документації | Заголовок перелічує 3 з 9 флагів. «The single allowed exception», хоча їх три. «Only sudo code path» суперечить `colima ssh -- sudo fstrim` на `:1789`. `--include-volumes` відсутній у START-рядку логу | CODE | — (L2) |
| Low | `mac-cleaner.sh:1770`, `1778`, `2929` | Fail-fast | `local x="$(cmd)"` ковтає rc: якщо `getconf` впаде, шлях QuickLook стає відносним до cwd. Впливає лише на розмір і лог | CODE | — (L4) |

Вимірювання: 18 функцій довші за 50 рядків, 28 — від 40. Глибина 4 — у `category_app_caches`, `cleanup_pnpm_store`, `is_category_enabled`, `category_container_vms`. Мертвого коду 0: кожна з 134 функцій має ≥1 посилання. Блок size/empty/confirm/measure/log повністю скопійовано в 17 функціях; 14 `confirm "Clean this?"`; 58 сайтів `zsh -c`.

### 2.4 resilience — відмовостійкість і цілісність даних

| Sev | Файл / сутність | Принцип | Ризик | Evidence | Verdict |
|---|---|---|---|---|---|
| High | `mac-cleaner.sh:287-293` `run_cmd`, `:345-348` `run_cat`; незахищені сайти `1302`, `1777`, `1895`, `1901`, `1948`, `1996`, `2072`, `2130`, `2403`, `2404`, `2542`, `2589`, `2688`, `2740`, `2791`, `2829`, `3040`, `3046` | Fail-safe, контракт 6 | `run_cmd` безумовно вмикає `set -e` назад, і ізоляція `set +e` у `run_cat` ламається. Будь-який ненульовий `run_cmd` на рівні оператора вбиває zsh з rc=1, без `ERROR`, без `END`, без Summary, і решта категорій не запускається. Відтворено: node_extras з каталогом mode 555 → exit 1, у лозі лише START. Electron-кеш з read-only підкаталогом → exit 1, наступний браузер не дійшов. Модель в основному потоці → exit=1. Під `--dry-run` не проявляється. Також solid-01, boundaries-01, complexity-errexit (рецензент resilience оцінив Critical — див. §1) | EXEC | confirmed ×4 (H1) |
| High | `mac-cleaner.sh:456` `run_paths_category`; `:1082`, `1088`, `1100` app_caches; `:534-538` `cleanup_brew`; `:1474-1479` cargo; `:1666` `category_bazel`; `:398` `run_category` | Fail-fast, core path (e) | Невдалі або часткові видалення стають `CLEAN`: `|| true` на кожному `rm`; багатокомандні cleanup повертають rc лише останньої команди (у `||`-контексті errexit вимкнено). bazel логує `WARN` → `ERROR rc=1` → `CLEAN` і збільшує лічильник, бо на `:1666` немає `return`. Сценарій зі спеки «brew cleanup на pinned formula має дати ERROR» (spec 2026-04-22:128) порушено: фейковий brew → `CLEAN category=Homebrew`. Також solid-02, boundaries-02, complexity-rc-last-command | EXEC | confirmed ×4 (H2) |
| High | `mac-cleaner.sh:504-506` `cleanup_pnpm_store` | Core path (b)(e) | Після `run_cmd` безумовно логується `CLEAN … freed_bytes=$v3_size` з розміром до видалення, без перевірки rc і повторного виміру. Під `--dry-run` blob лишається, а в лозі три суперечливі рядки. `TOTAL_FREED` не роздувається (шкода лише в лозі), тригер вузький: є legacy v3, який не є активним store | EXEC | confirmed ×3 (H3) |
| High | `mac-cleaner.sh:2637`, `:2685-2689` `category_llm_caches` | Безпека даних, core path (a) | `rm -rf` усього `~/Library/Application Support/nomic.ai/GPT4All` після звичайного `confirm`, який `--yes` приймає автоматично. За upstream-кодом GPT4All чати зберігаються як `gpt4all-<id>.chat` у `modelPath()`, а це за замовчуванням `AppLocalDataLocation`. Те, що на macOS це саме цей каталог, — висновок за Qt-неймінгом (INFER). README:62 називає категорію «model blobs only». Не перевірено на реальній інсталяції | CODE | confirmed (H6) |
| Medium ↓ | `mac-cleaner.sh:1151-1152`, `1197-1198`, `1132-1133` `category_temp` | Правило 1 (dynamic path) | Батьківський каталог для `find … -mtime +7 -exec rm -rf {} +` береться з успадкованого `$TMPDIR` без валідації (харнес: `TMPDIR=$HOME` → `~/Documents` видалено). Промпт показує буквально `$TMPDIR`. Знижено, бо спека 2026-05-07 §B прямо схвалює TMPDIR, а потрібен нестандартний TMPDIR | EXEC | doubtful, знижено з High (M1) |
| Medium | `mac-cleaner.sh:1126-1134`, `:1143-1145` `cleanup_temp_parent` | Перегони з живими процесами | Вибір за mtime верхнього рівня. На цій машині предикат зачепив 23 записи, з них 18 — `/private/tmp/com.apple.launchd.*` з сокетами, а також venv-и в роботі (`rvenv`, `wc-venv`). mtime каталогу не змінюється, коли використовуються сокети (вплив — INFER). У живому лозі `ERROR category=temp rc=1` в обох справжніх прогонах (2026-10-28, 2026-11-01), причину не досліджено | EXEC | — (M2) |
| Medium | `mac-cleaner.sh:1615-1622`, `1642`, `1668` `cleanup_bazel` | Правило 1 | Ціль `rm -rf` будується зі змінної середовища: `/private/var/tmp/_bazel_${USER:-…}`. Харнес: `USER='x/../../victim'` → `rm -rf …/_bazel_x/../../victim`. Тригер малоймовірний, але це четверта dynamic-path форма поза трьома дозволеними | EXEC | — (M3) |
| Medium | `mac-cleaner.sh:2987-2990` `category_ios_backups` | Поінформована згода (spec 2026-05-30 §B.2) | `Print :Device Name` розбивається на пробілі, і PlistBuddy шукає `:Device`. Перед typed-`DELETE` на незамінних бекапах користувач завжди бачить UDID і «unknown date». Без Info.plist як ім'я пристрою виводиться `File Doesn't Exist, Will Create…` | EXEC | — (M4) |
| Medium | `mac-cleaner.sh:1787-1792`, `:1699-1706`, `:1735-1762` `category_container_vms` | Згода, правила 2-3 | `colima ssh -- sudo fstrim -a` виконується без промпту навіть після DECLINE і під `--yes` (`|| true`). `_vm_cleanup_one` питає навіть при 0 B: під `--yes` це `docker system prune -a -f`. Гілка OrbStack перевіряє `orb`, але викликає `docker` (може прунити інший engine — INFER). Також solid-12, boundaries-10, boundaries-14 | CODE | — (M5) |
| Medium | `mac-cleaner.sh:250-251` `du_safe`, `:1036` | Parse, don't validate | Вивід du йде в арифметику без перевірки. Каталог з `\n` в імені в `~/Library/Caches` дає `bad math expression`, і це фатально навіть під `set +e`: пісочничний `--dry-run --scan` → exit 1, без Total і `SCAN_END` | EXEC | — (M6) |
| Medium | `mac-cleaner.sh:822-839` `cleanup_gradle` | Правило 8 | `gradle --stop` зупиняє лише демони тієї ж версії (документація Gradle): wrapper-демони інших версій і KotlinCompileDaemon живуть, коли gradle є в PATH. Fallback через pkill не чекає виходу. На macOS `rm -rf` файлу, який тримає інший процес, повертає 0 (EXEC), тож попередження про partial delete не спрацює. Також boundaries-05, resilience-gradle | EXEC | — (M8) |
| Low | `mac-cleaner.sh:34-44` `handle_sigint`, `:220-226` `log` | Safety nets | Перехоплюється лише INT, немає EXIT/TERM/HUP. Закритий термінал, kill або обрив через H1 не лишають фінального рядка. Ctrl-C під час `zsh -c rm` дає неврахований частковий стан. Лог, що не пишеться, блокує запуск, коли диск повний | EXEC | — (L5) |

Вимірювання: `|| true` 25 — на core path ковтають невдалий `rm` із подальшим `CLEAN` рядки 456, 1082, 1088, 1100; рядок 1789 ковтає sudo без промпту. `2>/dev/null` 27; `set [+-]e` у рядках 5, 287, 290, 345, 348. Живий лог: 25 запусків — 6 `END`, 16 `SCAN_END`, 2 `ERROR` (обидва `temp`); 1 справжній `--yes`-прогін без фінального рядка (`db72b382`).

## 3. Зроблено добре

- **Межа dry-run непроникна:** 0 деструктивних команд поза `run_cmd` (`mac-cleaner.sh:279`); prune-команди VM прокидаються через `_vm_cleanup_one` → `run_cmd` (`:1706`).
- **`--scan` read-only:** усі 22 bespoke-категорії мають гілку SCAN до будь-якого промпту, а три аудит-категорії загейтовані в `main` (`:3173`).
- **Typed-`DELETE`** (`category_xcode_archives`, `category_ios_backups`) читає stdin напряму, тож `--yes` його не обходить (харнес з `ASSUME_YES=1`: `y` і EOF дають `DECLINE stage=double_prompt`). `confirm_explicit` захищає sudo і `npm -g`.
- **`category_system_maintenance`** не чіпає `TOTAL_FREED`/`CATEGORIES_CLEANED`; sudo досяжний лише через `run_cmd`, тож у dry-run він не викликається.
- **Динамічні шляхи** в `zsh -c` скрізь екрануються `${(q)…}`. `category_app_caches` бере лише безпосередні дочірні каталоги `*(N/)`, тож symlink на зовнішній каталог не зачіпається (EXEC). `macos_installers` повторно перевіряє буквальний патерн перед кожним `rm`.
- **Чесний облік байтів:** freed = du/df до та після, а не припущення.
- **Мертвого коду немає:** усі 134 функції досяжні, усі `category_*` підключені в `main`, ключі синхронні в трьох реєстрах.
- **`cleanup_gradle` і `cleanup_bazel`** голосно попереджають про частковий `rm` і дають підказку з відновлення (там, де `rm` повертає ≠0).
- **`run_category`** відмовляє, якщо cleanup-функцію не визначено (`:361`).

## 4. План рефакторингу

Ескізи — не написані й не перевірені.

### Приклад 1. errexit вмикається назад і вбиває прогін (`mac-cleaner.sh:287-293`)
**Before:**
```zsh
run_cmd() {
  local desc="$1"; shift
  if (( DRY_RUN )); then printf '…' "$*"; return 0; fi
  set +e
  "$@"
  local rc=$?
  set -e
  DU_CACHE=()
  return $rc
}
```
**After:**
```zsh
run_cmd() {
  setopt local_options no_err_exit   # restore caller's errexit state on return
  local desc="$1"; shift
  if (( DRY_RUN )); then printf '…' "$*"; return 0; fi
  "$@"
  local rc=$?
  DU_CACHE=()
  return $rc
}
```
**Що дає:** відновлюється контракт 6: `run_cat` під `set +e` справді ізолює категорію, і невдалий `rm` дає `ERROR category=<x> rc=<n>` замість обриву. Закривається H1 і частина L5. Окремо потрібен регресійний харнес, який запускає функції у **не**-dry-run режимі на fixture-HOME, бо dry-run цього не бачить (M13).

### Приклад 2. Невдалий `rm` логується як `CLEAN` (`mac-cleaner.sh:453-457`, `:1666`, `:534-538`)
**Before:**
```zsh
for p in "${paths[@]}"; do
  [[ -e "$p" ]] || continue
  rel="${p/#$HOME/~}"
  run_cmd "rm -rf $rel" zsh -c "rm -rf ${(q)p}" || true
done
# … далі безумовно CATEGORIES_CLEANED++ і log CLEAN
```
**After:**
```zsh
local rc=0
for p in "${paths[@]}"; do
  [[ -e "$p" ]] || continue
  run_cmd "rm -rf ${p/#$HOME/~}" rm -rf -- "$p" || rc=$?
done
# … вимір after як і раніше
if (( rc )); then
  printf '  %sERROR%s partial delete rc=%d\n' "$C_RED" "$C_RESET" "$rc"
  log ERROR "category=$logcat rc=$rc freed_bytes=$freed"
  return 0
fi
```
Те саме для багатокомандних `cleanup_*` (`run_cmd … || rc=$?` на кожній команді, `return $rc`) і `return 0` після `log ERROR` у `category_bazel:1666`.
**Що дає:** core path (e): лог і Summary більше не стверджують успіх для невдалих видалень. Закривається H2, а з перевіркою `DRY_RUN`/rc у `cleanup_pnpm_store` — і H3.

### Приклад 3. `zsh -c` glob без nullglob/dotglob (`mac-cleaner.sh:866-869` і ще 19 сайтів)
**Before:**
```zsh
cleanup_trash() {
  run_cmd "rm -rf ~/.Trash/*" \
    zsh -c 'rm -rf "$HOME/.Trash/"*'
}
```
**After:**
```zsh
cleanup_trash() {
  local -a items=( "$HOME/.Trash/"*(DN) )   # D = dotfiles, N = nullglob, expanded in the parent
  (( ${#items} )) || return 0
  run_cmd "rm -rf ~/.Trash/*" rm -rf -- "${items[@]}"
}
```
**Що дає:** dotfiles видаляються, порожній або dotfile-only каталог не дає фальшивого `ERROR` і не обриває прогін у комбінації з H1. Glob розкривається в батьківському процесі, тож прибирається і вплив `~/.zshenv` дочірнього zsh (непідтверджений підпункт). Безпека правила 1 зберігається: ціль — той самий хардкод-префікс.

### Наступні кроки за пріоритетом
1. **H1:** відновлювати errexit у `run_cmd` (приклад 1) і зафіксувати це харнесом не-dry-run на fixture-HOME. Найбільший виграш: одна правка закриває 18 точок обриву.
2. **H2 + H3:** агрегувати rc у `run_paths_category`, `category_app_caches`, багатокомандних `cleanup_*`; `return` у bazel; pnpm v3 — перевіряти rc і `DRY_RUN`, а розмір міряти повторно.
3. **H4:** 20 сайтів `zsh -c '…/*'` → масиви `*(DN)` у батьківському процесі (приклад 3).
4. **H5:** додати CocoaPods, `Mozilla.sccache`, `bazel`, `go-build` і застосунки зі спеки 2026-05-07:58 до `DENY_NAMES`. Краще — виводити денайліст із шляхів категорій-власників, щоб реєстр не синхронізувався вручну.
5. **H6:** звузити GPT4All до файлів моделей (`*.gguf`/`*.bin`) або виключити `*.chat`. Спершу перевірити розкладку на реальній інсталяції.
6. **Medium, що стосуються згоди та даних:** M4 (ім'я й дата пристрою перед `DELETE`), M5 (промпт для `fstrim`, skip VM при 0 B), M2/M1 (liveness-перевірка для temp, валідація `TMPDIR` через `getconf DARWIN_USER_TEMP_DIR`), M7 (патерни pgrep з `~/Applications`).
7. **Структура (H7, M11, M12):** одна таблиця метаданих категорій (ключ → групи → log-name → функція), з якої генеруються `--list`, `VALID_CATEGORY_KEYS` і порядок `main`. Робити після пунктів 1-3, бо ці виправлення її не потребують.

## 5. Не перевірено

- **Справжні (не-dry-run) прогони і `--yes`** заборонені політикою аудиту. Typed-`DELETE` під `--yes` перевірено харнесом з `ASSUME_YES=1` + `DRY_RUN=1`, а не на живому HOME.
- **Деструктивні інструменти** (brew, docker/podman/colima/OrbStack, tmutil, `xcrun simctl`, gradle, `sudo purge`/`mdutil`) не запускались; замість них були фейкові скрипти. Colima, OrbStack, Lima і Podman на цій машині відсутні.
- **Причина обриву `db72b382`** (2026-11-01) — H1 чи закритий термінал (L5) — потребує відтворення.
- **Розкладка GPT4All** (чи справді чати лежать у `Application Support/nomic.ai/GPT4All`) і втрата імпортованих моделей LM Studio/Ollama — runtime не перевірено.
- **TCC/Full Disk Access** на `~/Library/Containers` (Safari, Mail, Maps) і `~/.Trash`: як часто `rm` реально падає (тригер H1), чи du повертає 0 і дає хибний «already empty».
- **Root-власність** `/Applications/Install macOS *.app` (тригер H1 через `macos_installers`) — інсталятора на машині немає.
- **`rm()`/alias у `~/.zshenv`**, який перехоплює видалення в дочірньому `zsh -c`: харнес заблокувала перевірка безпеки, тож це лише висновок з документованої поведінки zsh.
- **Живі застосунки з `~/Applications`** (M7) — патерн перевірено на argv0, а не на живому процесі.
- **Чи використовуються** сокет-каталоги `com.apple.launchd.*` старші за 7 днів (M2): lsof на цій машині не повний.
- **Відхилені (refuted) знахідки:** немає.

## 6. Статус виправлень (2026-11-14)

Гілка `feat/cleanup-script-improvements`, коміти `8c3adc0..2e0016b`. Регресійні тести: `python3 -I specs/audit-fixes/smoke.py` (14 сценаріїв; червоні на `88e5855`, зелені після виправлень).

| Знахідка | Статус | Коміт |
|---|---|---|
| H1 errexit обриває прогін | виправлено: `run_cmd` з `local_options no_err_exit` + rc у 18 місцях | `95216df` |
| H2 невдале видалення як `CLEAN` | виправлено; часткові байти рахуються в `TOTAL_FREED` з `ERROR partial=true` | `53f4061`, `2e0016b` |
| H3 pnpm v3 | виправлено (rc, `--dry-run`, повторний вимір) | `53f4061` |
| H4 glob у `zsh -c` | виправлено через `*(DN)` / `(N)` у дочірньому zsh (не масиви в батьківському, як пропонував приклад 3) | `682e3d5` |
| H5 app_caches і чужі кеші | частково: CocoaPods, `Mozilla.sccache`, `bazel`, `go-build` у `DENY_NAMES`; застосунки зі збереженим входом (спека 2026-05-07:58) і автоматичне виведення денайліста не зроблено | `492b69d` |
| H6 GPT4All | відкрито: потрібна реальна інсталяція, щоб перевірити розкладку | — |
| H7, M1–M14, L1–L5 | відкрито | — |

Залишки після виправлень:
- ~15 inline-категорій (браузери, container_vms тощо) при помилці ще не рахують часткові байти, а браузери пишуть `ERROR` двічі.
- Тести покривають частину з 18 місць H1; решту перевірено читанням коду.
- Якщо bazel/go/sccache видалено з системи, їхні залишкові кеші в `~/Library/Caches` ніхто не прибирає.
