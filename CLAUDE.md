# Nomaded — правила для Claude

iOS-приложение «личный паспорт путешественника» с интерактивным 3D-глобусом. Главная ценность — красивые, плавные, «физические» анимации в духе Zenly. Это **первое iOS-приложение Leon**, цель — релиз в App Store.

## Перед задачей

- Прочитай нужные документы в `docs/`. Главные — `02-design.md` (motion-система и каталог вау-моментов) и `03-architecture.md` (слои, модель данных, ADR).
- Задачи берём из `docs/04-roadmap.md`. Держись скоупа текущего этапа.

## Общение

- Отвечай Leon по-русски. Код, идентификаторы, комментарии и сообщения коммитов — на английском.
- Leon новичок в iOS. Когда вводишь новую iOS/Swift-концепцию, объясни её в 1–2 фразах. Не лекцией, по делу.
- Если задача требует продуктового или дизайн-решения, предложи вариант с рекомендацией, а не список.

## Сборка и проверка

После изменений кода **всегда** проверяй, что проект собирается и тесты проходят:

```bash
xcodebuild -project Nomaded.xcodeproj -scheme Nomaded \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -quiet build

xcodebuild -project Nomaded.xcodeproj -scheme Nomaded \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -quiet test
```

- `OS=18.6` обязателен: без него Xcode 26 ищет iPhone 16 Pro на iOS 26, а там такого симулятора нет. Вид на iOS 26 — `name=iPhone 17 Pro`.
- Сборка без ошибок и без новых warnings.
- Анимации и ощущения проверить не можешь: скажи Leon, что именно посмотреть на iPhone.

## Правила

- **Не коммить.** Коммитит Leon. Можно предложить текст коммита (Conventional Commits, на английском).
- **Не добавляй сторонние зависимости** без явного согласия. Если всё-таки добавили, запиши ADR в `03-architecture.md`.
- **Файлы проекта:** `Nomaded/` и `NomadedTests/` — синхронизированные папки (Xcode 16). Новые файлы просто создавай в нужной подпапке, `project.pbxproj` трогать не нужно. Правка `project.pbxproj` вручную — только для build settings и только осознанно.
- **Swift 6, iOS 18.** Код должен проходить strict concurrency. API новее iOS 18 — только под `if #available`.
- **DesignSystem-токены и компоненты** (`Palette`, `Typography`, `Motion`, `Haptics`, `.glassCard()`, `.capsule()`, `HeroNumber`, `StatTile`…) вместо магических чисел и самописных дубликатов в фичах. Список в `docs/02-design.md`, вживую — `-NomadedGallery YES`.
- **Цвета данных** (candy-палитра, графики в Statistics) прогоняй через dataviz-валидатор, а не на глаз. Текст не красится в цвет серии.
- **Reduce Motion** учитывай в каждой новой анимации.
- **Domain-логику покрывай тестами** (Swift Testing).
- **Обновляй доки:** галочки в роадмапе, новые и изменённые решения в журнал ADR.
- **Правила Apple** (HIG + App Review Guidelines) — в `docs/07-apple-rules.md`. Любая фича проходит его чек-лист. Если задача упирается в правило Apple, скажи об этом Leon явно.

## Глобус

- Параметры ощущений (трение, пружины, высоты, зум) — только в `GlobeEngine/GlobeTuning.swift`.
- Иконка (`AppIcon.appiconset`) рисуется кодом в `Tools/AppIcon` (команда в его README), руками PNG не правим.
- Скриншоты для App Store снимает `Tools/Screenshots` (сцены — те же DEBUG-аргументы). Тексты карточки — `docs/09-store-listing.md`, страницы поддержки и конфиденциальности — `site/`. Если фича меняет, что приложение хранит или куда ходит в сеть, обнови `site/privacy.html` и `site/ru/privacy.html`.
- `Resources/Geo/world.nmgeo`, `countries.json` и `cities.json` руками не редактируются. Их перегенерирует `Tools/GeoPipeline` (команда в его README), после этого прогоняются тесты.
- Проверка в симуляторе без касаний — DEBUG launch-аргументы (`GlobeScreen.applyDebugLaunchArguments`):
  ```bash
  xcrun simctl launch "iPhone 16 Pro" com.leonkazaryan.nomaded \
    -NomadedDebugVisited IT,FR -NomadedDebugSelect FR -NomadedDebugTap 186,459 -NomadedDebugMarkAfterTap YES
  xcrun simctl io "iPhone 16 Pro" screenshot shot.png
  ```
  Несколько тапов подряд, через 3 с: `-NomadedDebugTap "186,459;120,300"`. Ещё: `-NomadedDebugFly LU` (перелёт к стране после интро), `-NomadedDebugSearch Ита` (открыть поиск с запросом, `-NomadedDebugSearchCities YES` — на вкладке «Города»), `-NomadedDebugSearchPick YES` (вместе с Search: через 2 с выбрать первый результат), `-NomadedDebugVisitedList YES` (открыть список посещённых), `-NomadedDebugStats YES` (открыть статистику), вместе с ним `-NomadedDebugContinent europe` (открыть континент, `world` — все страны). Города: `-NomadedDebugCities "Рим:IT:41.9:12.5,…"` (добавить), `-NomadedDebugCityFocus YES` (полёт к первому), `-NomadedDebugLandCity "Генуя:IT:44.41:8.93"` (добавить как из поиска, с «приземлением»), `-NomadedDebugAddCity IT` + `-NomadedDebugCityQuery Фл` (поиск города). Праздник: `-NomadedDebugMark FR` (долететь и отметить), `-NomadedDebugUnmarkAfter YES` (через 3 с снять), `-NomadedDebugMilestone countries.25` или `continent.asia` (показать веху). Онбординг: `-NomadedDebugOnboarding YES` (показать с начала), `-NomadedDebugOnboardingStep pick|ready` (сразу на шаг), `-NomadedDebugOnboardingQuery Ита` (запрос в поиске шага выбора).
  Границы по витрине App Store: `-NomadedDebugWorldview rus` (`standard`, `rus`, `chn`) рисует вид сразу, `-NomadedDebugSwitchWorldview rus` переключает после интро с анимацией. Зона разработчика: `-NomadedDebugStats YES -NomadedDebugDeveloper YES`; `-NomadedDebugReset YES` стирает прогресс после интро.
  С любым `-NomadedDebug…` приложение берёт пустое хранилище в памяти, настоящие отметки не трогаются.
- **Зона разработчика** (только Debug-сборка): в статистике трижды потянуть список за нижний край. Регион App Store для границ, счётчик кадров, сброс прогресса с онбордингом. В Release её быть не должно (App Review 2.3.1).

## Окружение

- Xcode 26.3 (iOS 26.2 SDK) в `/Applications/Xcode.app`, Metal Toolchain стоит отдельным компонентом. Симуляторы: iOS 18.6 (iPhone 16 Pro, основной) и iOS 26.3 (iPhone 17 Pro).
- Симулятор iOS 26.3 рисует эмодзи, в том числе флаги, квадратиками «?». Это баг рантайма Xcode 26.3, на устройствах всё нормально. Скриншоты с флагами снимай на iOS 18.6.
- Bundle ID: `com.leonkazaryan.nomaded`.
- Репозиторий: https://github.com/LeonKazaryan/nomaded
