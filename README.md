# Nomaded

Личный паспорт путешественника для iPhone. Красивый интерактивный 3D-глобус, на котором светятся страны, где ты был. Главная фишка — яркие, живые, «физические» анимации в духе Zenly.

> **Статус:** M2 — дизайн-система готова. M1 ждёт замера на iPhone. План в [`docs/04-roadmap.md`](docs/04-roadmap.md).

## Стек

| | |
|---|---|
| Язык | Swift 6 (strict concurrency) |
| UI | SwiftUI |
| 3D-глобус | RealityKit (проверяем спайком в M1, см. ADR-001) |
| Данные | SwiftData, только на устройстве |
| Тесты | Swift Testing |
| Минимальная iOS | 18.0, только iPhone, портретная ориентация |
| Зависимости | нет, только системные фреймворки |

## Как запустить

**В Xcode (основной способ):**

1. Открой `Nomaded.xcodeproj`.
2. Вверху окна выбери схему **Nomaded** и симулятор, например **iPhone 16 Pro**.
3. `⌘R` — запустить, `⌘U` — прогнать тесты, `⇧⌘K` — очистить сборку.

**На своём iPhone:**

0. Xcode должен знать iOS твоего телефона: для iOS 26.x нужен Xcode 26+. На macOS Sequoia самый новый вариант — Xcode 26.3, его скачиваем с [developer.apple.com/download/all](https://developer.apple.com/download/all/). App Store предложит Xcode 27, а ему нужна macOS Tahoe.
1. Xcode → Settings → Accounts → `+` → добавь свой Apple ID.
2. В навигаторе слева кликни на проект **Nomaded** → таргет **Nomaded** → вкладка **Signing & Capabilities** → **Team** = твой Apple ID.
3. Подключи iPhone кабелем, разблокируй его и нажми «Доверять этому компьютеру». Выбери телефон вверху вместо симулятора.
4. На iPhone включи Режим разработчика: Настройки → Конфиденциальность и безопасность → Режим разработчика. Пункт появляется только после того, как телефон один раз подключили к Xcode. После включения телефон перезагрузится.
5. `⌘R`. При первом запуске с бесплатным Apple ID iOS скажет «Ненадёжный разработчик»: Настройки → Основные → VPN и управление устройством → твой Apple ID → Доверять. Сборка работает на телефоне 7 дней, потом просто запусти её из Xcode ещё раз.

> Анимации оценивай **только на реальном iPhone**. Симулятор не показывает настоящую плавность (120 Гц) и не умеет в хаптику.

**Из терминала:**

```bash
xcodebuild -project Nomaded.xcodeproj -scheme Nomaded \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

xcodebuild -project Nomaded.xcodeproj -scheme Nomaded \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

## Документация

| Документ | О чём |
|---|---|
| [`docs/01-product.md`](docs/01-product.md) | Видение, экраны, что входит в MVP, открытые вопросы |
| [`docs/02-design.md`](docs/02-design.md) | Визуальный язык, палитра, motion-система, каталог «вау»-моментов |
| [`docs/03-architecture.md`](docs/03-architecture.md) | Структура кода, модель данных, устройство глобуса, журнал решений |
| [`docs/04-roadmap.md`](docs/04-roadmap.md) | Этапы M0–M7 до релиза, чек-листы |
| [`docs/05-conventions.md`](docs/05-conventions.md) | Стиль кода, git, как мы работаем вместе, шпаргалка по Xcode |
| [`docs/06-app-store.md`](docs/06-app-store.md) | Всё про публикацию в App Store |
| [`docs/07-apple-rules.md`](docs/07-apple-rules.md) | Правила Apple (HIG + App Review) и чек-лист перед мержем |
| [`Tools/GeoPipeline/README.md`](Tools/GeoPipeline/README.md) | Как из Natural Earth получаются меши стран |
| [`CLAUDE.md`](CLAUDE.md) | Правила для Claude в этом репозитории |

## Структура

```
Nomaded/                 исходники приложения (папка синхронизируется с Xcode сама)
  App/                   точка входа
  Features/Globe/        главный экран: глобус, карточка страны
  GlobeEngine/           3D-глобус: сцена, физика, hit-test, математика
  DesignSystem/          палитра, анимации, общие компоненты
  Domain/                чистая логика (флаги, названия стран…)
  Resources/             Assets, String Catalog, Geo/world.nmgeo
  Info.plist             только ключи, которые нельзя задать в build settings
NomadedTests/            юнит-тесты (Swift Testing)
Tools/GeoPipeline/       утилита: границы стран → меши глобуса (в приложение не входит)
Nomaded.xcodeproj/       проект Xcode
docs/                    документация проекта
```

## Что крутить, если хочется другого ощущения

Все параметры глобуса (трение, скорость, пружины, высота подъёма стран, зум) лежат в `Nomaded/GlobeEngine/GlobeTuning.swift`. Поменял число, нажал `⌘R` и проверил на телефоне.

Любой файл, который кладёшь в `Nomaded/`, автоматически попадает в проект. Добавлять его в Xcode руками не нужно.
