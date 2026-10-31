# Task: editor-caches

Status: done
Template: full
Lane: feature
Modules: none — локальний CLI
Design: none
Base: main; початковий стан 260b599

## Goal
Розширити охоплення відновлюваних кешів редакторів.
> "Switch to \"clean my mac\" project and improve the clean up script"
> "Більше вільного місця"

## Scope
- In: VSIX чотирьох редакторів, кеші Devin і Devin - Next, документація.
- Out: справжнє очищення Mac, нові прапорці, інші категорії.

## Requirements
| # | User requirement | Scenario and expected result | Criteria |
|---|---|---|---|
| R1 | Більше вільного місця | Додаткові кеші видно в CLI та можна видалити без сусідніх даних | D1, D2 |

## Existing behavior inventory
| # | Behavior (kind) | Old location | New location | Status | Evidence |
|---|---|---|---|---|---|
| I1 | scan, dry-run, підтвердження, порожні кеші, захист запущених програм (handler) | `mac-cleaner.sh:2016-2071` | `mac-cleaner.sh:_browser_clean_electron` | preserved | D1, D2; E1, E4 |
| I2 | Наявні цілі Electron та решта категорій (side effect) | `mac-cleaner.sh:2131-2180` | `mac-cleaner.sh:category_browser_caches` | preserved | D1, D2; E1, E2 |

## Done criteria
| # | Check (what is observed) | Command or observation | Bar | Evidence |
|---|---|---|---|---|
| D1 | CLI очищає лише дозволені тимчасові дані, зберігає захисти | `python3 specs/editor-caches/smoke.py` | Усі сценарії завершуються кодом 0 | E1 |
| D2 | Реальний попередній перегляд та сканування | `zsh -n mac-cleaner.sh && ./mac-cleaner.sh --dry-run </dev/null && ./mac-cleaner.sh --scan --only browsers` | Код 0, підсумок та рядок Devin у скануванні, без справжнього видалення | E2 |
| D3 | Перевірка різниці та безпеки | `git diff --check && bash /Users/lion/.claude/skills/security-review/scripts/security-check.sh --base main` | Код 0, немає FAIL; пропущені перевірки пояснено | E3 |

## Checklists
### Before the first edit
- [x] Мету, межі, інвентар і критерії записано
- [x] Критерії зафіксовано перевіркою
### Build
- [x] Побачено відсутню поведінку, потім успішні сценарії
### Verify
- [x] Різницю, журнали й безпеку переглянуто
- [x] Виконано повторний перегляд автором
### Close
- [x] Перевірка документа завершується кодом 0

## Evidence log
| # | Command | Grade | Verdict | Log | State |
|---|---|---|---|---|---|
| E1 | `python3 specs/editor-caches/smoke.py` | EXEC | VERIFIED | `evidence/smoke.log` | 260b599 + ac01b147, точний відбиток у квитанції |
| E2 | `zsh -n mac-cleaner.sh && ./mac-cleaner.sh --dry-run </dev/null && ./mac-cleaner.sh --scan --only browsers` | EXEC | VERIFIED | `evidence/runtime.log` | 260b599 + ac01b147 |
| E3 | `git diff --check && bash /Users/lion/.claude/skills/security-review/scripts/security-check.sh --base main` | EXEC | VERIFIED | `evidence/security.log` | 260b599 + ac01b147 |
| E4 | `./mac-cleaner.sh --dry-run --yes --only browsers </dev/null` | EXEC | VERIFIED | `evidence/preview.log` | 260b599 + ac01b147 |

Початкові запуски: `evidence/red-vsix.log` — немає VSIX у попередньому
перегляді; `evidence/red-devin.log` — немає Devin. Обидва завершилися кодом 1
через відсутню поведінку. `evidence/green-vsix.log` зафіксував перший успіх.

Безпека:
- secrets PASS — сканер не знайшов секретів.
- dependencies SKIP — залежності й маніфести не змінювалися.
- network SKIP — узгодженого мережевого шару немає; ця зміна не додає мережевих викликів.
- permissions PASS — нових дозволів немає.
- environments and secrets PASS — зміна не вводить середовищ, ключів, читання секретів чи клієнтських змінних; тимчасовий профіль містить лише штучні файли.
- access and data isolation PASS — локальний CLI працює від користувача; нові цілі статичні, підтвердження та перевірка процесів залишаються на шляху виконання. Тимчасові сусідні дані збережено.

## Criteria changes
Немає.

## Refute pass
Refute pass: by author · report: `evidence/refute.json`

## Open items and blockers
Немає. Очищення користувацьких файлів не входило до завдання.
