# Screenshots

Снимает скриншоты для App Store из самого приложения и добавляет подписи. Сцены задаются DEBUG launch-аргументами (`GlobeScreen.applyDebugLaunchArguments`), поэтому после изменений интерфейса весь набор пересобирается двумя командами.

```bash
Tools/Screenshots/capture.sh                                  # сборка, симулятор, сырые снимки, ~3 минуты
swift Tools/Screenshots/compose.swift Tools/Screenshots/output  # подписи и рамка
```

- **Где:** результат в `Tools/Screenshots/output/en` и `output/ru` (папка в `.gitignore`), сырые снимки в `output/raw`.
- **Формат:** 1320×2868, это iPhone 6,9″. RGB без прозрачности, иначе App Store Connect не примет.
- **Симулятор:** iPhone 16 Pro Max на iOS 18.6. Симулятор iOS 26.3 рисует флаги квадратиками «?».
- **Статус-бар:** 9:41, полная батарея. Счётчик кадров выключен аргументом `-NomadedDebugShowsFrameRate NO`.
- **Кадр отметки:** праздник длится около секунды, поэтому `capture.sh` снимает серию `mark-1…4` и кладёт в `mark.png` второй кадр. Если конфетти и кольца на нём нет, скопируй подходящий `mark-N.png` в `mark.png` и запусти `compose.swift` ещё раз.
- **Подписи и порядок** — в начале `compose.swift`. Первые три скриншота видны прямо в результатах поиска App Store, поэтому сначала идут глобус, отметка и статистика. Тексты подписей продублированы в `docs/09-store-listing.md`.
