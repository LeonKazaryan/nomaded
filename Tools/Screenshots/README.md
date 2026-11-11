# Screenshots

Снимает скриншоты для App Store из самого приложения и добавляет подписи. Сцены задаются DEBUG launch-аргументами (`GlobeScreen.applyDebugLaunchArguments`), поэтому после изменений интерфейса весь набор пересобирается двумя командами.

```bash
Tools/Screenshots/capture.sh                                  # сборка, симулятор, сырые снимки, ~3 минуты
swift Tools/Screenshots/compose.swift Tools/Screenshots/output  # подписи и рамка

Tools/Screenshots/capture.sh ipad                                       # то же для iPad
swift Tools/Screenshots/compose.swift Tools/Screenshots/output/ipad ipad

Tools/Screenshots/capture-duo.sh                                        # iPhone Duo, ~6 минут
swift Tools/Screenshots/compose.swift Tools/Screenshots/output/duo duo
```

- **Где:** результат в `Tools/Screenshots/output/en` и `output/ru` (папка в `.gitignore`), сырые снимки в `output/raw`.
- **Формат:** 1206×2622, это iPhone 6,3″: с 2026 года App Store Connect принимает скриншоты iPhone этого размера, а 6,9″ (1320×2868) отклоняет. Раскладка рисуется в единицах 6,9″ и уменьшается, пропорции почти те же. RGB без прозрачности, иначе App Store Connect не примет.
- **Симулятор:** iPhone 16 Pro Max на iOS 18.6. Симулятор iOS 26.3 рисует флаги квадратиками «?».
- **iPad:** iPad Pro 13-inch (M4) на iOS 18.6, результат в `output/ipad/en` и `output/ipad/ru`, 2064×2752 (iPad 13″). Симулятор должен стоять **вертикально** (Simulator → Device → Orientation → Portrait): скрипт поворачивать его не умеет, а он помнит последний поворот. На iPad снимок крупнее и праздник успевает дальше, поэтому кадр с конфетти обычно `mark-2` или `mark-3`.
- **Статус-бар:** 9:41, полная батарея. Счётчик кадров выключен аргументом `-NomadedDebugShowsFrameRate NO`.
- **Кадр отметки:** праздник длится около секунды, поэтому `capture.sh` снимает серию `mark-1…4` и кладёт в `mark.png` второй кадр. Если конфетти и кольца на нём нет, скопируй подходящий `mark-N.png` в `mark.png` и запусти `compose.swift` ещё раз.
- **Подписи и порядок** — в начале `compose.swift`. Первые три скриншота видны прямо в результатах поиска App Store, поэтому сначала идут глобус, отметка и статистика. Тексты подписей продублированы в `docs/09-store-listing.md`.
- **iPhone Duo (с версии 1.2):** результат в `output/duo/en` и `output/duo/ru`, 2853×2007 — размер внутреннего экрана, раскрытого как книга. Набор у Duo в App Store Connect один на язык (принимает размер и внешнего, и внутреннего экрана), поэтому сложенный и раскрытый показаны вместе: первая карточка — сложенный телефон рядом с раскрытым в одном масштабе, третья — два сложенных, остальные — развороты. Снимает симулятор `iPhone Duo` (iOS 27.2 сборки 24B91016s) при открытом Device Hub. Сложить и раскрыть Duo можно только в окне Device Hub: скрипт снимает сцены в той позе, в которой Duo сейчас, потом пишет, что его надо сложить (или раскрыть), и ждёт. Раскрытый Duo держать ровно, как книгу (не «ноутбуком»).
