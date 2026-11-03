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
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build

xcodebuild -project Nomaded.xcodeproj -scheme Nomaded \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet test
```

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
- `Resources/Geo/world.nmgeo` руками не редактируется. Он перегенерируется `Tools/GeoPipeline` (команда в его README), после этого прогоняются тесты.
- Проверка в симуляторе без касаний — DEBUG launch-аргументы (`GlobeScreen.applyDebugLaunchArguments`):
  ```bash
  xcrun simctl launch "iPhone 16 Pro" com.leonkazaryan.nomaded \
    -NomadedDebugVisited IT,FR -NomadedDebugSelect FR -NomadedDebugTap 186,459 -NomadedDebugMarkAfterTap YES
  xcrun simctl io "iPhone 16 Pro" screenshot shot.png
  ```
  Ещё: `-NomadedDebugFly LU` (перелёт к стране после интро), `-NomadedDebugSearch Ита` (открыть поиск с запросом), `-NomadedDebugSearchPick YES` (вместе с Search: через 2 с выбрать первый результат), `-NomadedDebugVisitedList YES` (открыть список посещённых), `-NomadedDebugStats YES` (открыть статистику), вместе с ним `-NomadedDebugContinent europe` (открыть континент, `world` — все страны). Города: `-NomadedDebugCities "Рим:IT:41.9:12.5,…"` (добавить), `-NomadedDebugCityFocus YES` (полёт к первому), `-NomadedDebugLandCity "Генуя:IT:44.41:8.93"` (добавить как из поиска, с «приземлением»), `-NomadedDebugAddCity IT` + `-NomadedDebugCityQuery Фл` (поиск города).
  С любым `-NomadedDebug…` приложение берёт пустое хранилище в памяти, настоящие отметки не трогаются.

## Окружение

- Xcode 16.4, симулятор iOS 18.6 (iPhone 16 Pro). Перед релизом нужен Xcode 26+ (см. `docs/06-app-store.md`).
- Bundle ID: `com.leonkazaryan.nomaded`.
- Репозиторий: https://github.com/LeonKazaryan/nomaded
