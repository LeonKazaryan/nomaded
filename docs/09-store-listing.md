# 09 · Карточка в App Store Connect

Всё, что App Store Connect спрашивает при первой публикации, готовое к копированию. Порядок разделов — как в самом App Store Connect. Длина каждого поля проверена, лимиты в скобках.

Основной язык карточки — **English (U.S.)**: его видят во всех странах, для которых нет своего перевода. Русский добавляется как вторая локализация (App Store Connect → приложение → язык справа вверху → **Add Localization → Russian**).

## Ссылки

Страницы лежат в `site/` и публикуются через GitHub Pages (`.github/workflows/pages.yml`). Один раз включить: GitHub → репозиторий → **Settings → Pages → Source: GitHub Actions**. Дальше страницы обновляются сами после каждого push в `main`, если менялась папка `site/`.

| Поле | English | Русский |
|---|---|---|
| Support URL | `https://leonkazaryan.github.io/nomaded/` | `https://leonkazaryan.github.io/nomaded/ru/` |
| Marketing URL (необязательно) | `https://leonkazaryan.github.io/nomaded/` | `https://leonkazaryan.github.io/nomaded/ru/` |
| Privacy Policy URL | `https://leonkazaryan.github.io/nomaded/privacy.html` | `https://leonkazaryan.github.io/nomaded/ru/privacy.html` |

## App Information

| Поле | Значение |
|---|---|
| Name, English (30) | `Nomaded: Travel Map` |
| Name, Russian (30) | `Nomaded: карта путешествий` |
| Subtitle, English (30) | `Visited countries on a globe` |
| Subtitle, Russian (30) | `Посещённые страны на глобусе` |
| Primary Category | Travel |
| Secondary Category | Lifestyle |
| Content Rights | **Yes**, contains third-party content, and **I have the necessary rights**: контуры стран — Natural Earth (public domain), города — GeoNames (CC BY 4.0, источник указан в приложении), поиск мест — Apple MapKit |
| Age Rating | на все вопросы анкеты **None** / **No** → 4+ |

Если имя «Nomaded: Travel Map» окажется занято, подойдёт `Nomaded: Travel Globe`. Слова из названия и подзаголовка App Store уже ищет, поэтому в ключевых словах они не повторяются.

## Pricing and Availability

- **Price:** Free.
- **Availability:** все страны и регионы, **кроме China mainland**: без ICP-регистрации Apple там не публикует (см. `06-app-store.md`).
- **India:** публикуем. Для витрины Индии глобус рисует весь Кашмир индийским, как требуют индийские правила о картах (ADR-015).

## App Privacy

- **Data Collection:** «No, we do not collect data from this app» → в карточке будет **Data Not Collected**.
- Это правда для нашего кода: данных с устройства мы не получаем, сторонних SDK нет. Поиск городов идёт в Apple Maps, это сервис Apple, его в анкете не указывают.

## Version 1.0 — English (U.S.)

### Promotional Text (170)

```
Spin the globe, tap a country and watch it light up with confetti and a passport stamp. Your travels, all on one beautiful map.
```

### Description (4000)

```
Nomaded is your travel passport on a living 3D globe. Mark the countries you’ve been to and watch your world fill with color.

A GLOBE THAT FEELS REAL
Flick it and it keeps spinning. Pinch to zoom in on any place. Tap a country and the camera flies there and frames it, whether it’s Vatican City or Russia. Lakes and rivers rise with their country, and tiny states show up as dots, so you never miss Monaco or Malta.

EVERY MARK IS A CELEBRATION
The country fills with color from the spot you tapped and jumps off the globe. A ring runs around the planet, confetti flies, and a passport stamp lands on the card.

CITIES
Add the cities you’ve seen. Each country opens with a list of its largest cities, capital first, and Apple Maps finds the rest. Every city lands on the globe as a pin.

YOUR WORLD IN NUMBERS
See how much of the world you’ve explored, how far along you are on each continent and in every region, and which of your countries is the largest and the smallest.

MEDALS
Earn medals at 10, 25, 50, 100, 150 and all 195 countries, and for every new continent.

MADE WITH CARE
• 195 countries, plus territories you can mark too
• Works offline, with over 80,000 cities and resorts built in
• VoiceOver, Dynamic Type and Reduce Motion
• English and Russian

PRIVATE BY DESIGN
No account, no ads, no tracking. Your travels stay on your iPhone.
```

### Keywords (100)

```
tracker,scratch,passport,trip,world,cities,places,journal,stats,explore,atlas,earth,vacation,flags
```

### Остальное

| Поле | Значение |
|---|---|
| Copyright | `2026 Leon Kazaryan` |
| Version | `1.0` |
| Routing App Coverage File | не нужен |

## Version 1.0 — Russian

### Promotional Text (170)

```
Крути глобус, коснись страны — и она вспыхнет цветом, конфетти и штампом в паспорте. Все твои путешествия на одной красивой карте.
```

### Description (4000)

```
Nomaded — твой паспорт путешественника на живом 3D-глобусе. Отмечай страны, где ты был, и смотри, как мир наполняется цветом.

ГЛОБУС, КОТОРЫЙ ОЩУЩАЕТСЯ НАСТОЯЩИМ
Толкни его — и он крутится дальше по инерции. Сведи пальцы, чтобы приблизить любое место. Коснись страны — камера долетит до неё и покажет её целиком, будь то Ватикан или Россия. Озёра и реки поднимаются вместе со своей страной, а крошечные государства видны точками: Монако и Мальту не пропустишь.

КАЖДАЯ ОТМЕТКА — МАЛЕНЬКИЙ ПРАЗДНИК
Страна заливается цветом от точки касания и подпрыгивает над глобусом. По планете бежит кольцо, летят конфетти, а на карточку ложится штамп паспорта.

ГОРОДА
Добавляй города, где ты был. У каждой страны сразу открывается список крупнейших городов со столицей во главе, остальные найдут Apple Maps. Каждый город приземляется на глобус булавкой.

ТВОЙ МИР В ЦИФРАХ
Смотри, какую часть мира ты уже открыл, сколько пройдено на каждом континенте и в каждом регионе и какая из твоих стран самая большая, а какая самая маленькая.

МЕДАЛИ
Получай медали за 10, 25, 50, 100, 150 и все 195 стран и за каждый новый континент.

СДЕЛАНО С ЛЮБОВЬЮ
• 195 стран и территории, которые тоже можно отмечать
• Работает без интернета, встроено больше 80 000 городов и курортов
• VoiceOver, крупный шрифт и «Уменьшение движения»
• Русский и английский языки

ПРИВАТНОСТЬ ПО УМОЛЧАНИЮ
Без аккаунта, рекламы и отслеживания. Твои путешествия остаются на твоём iPhone.
```

### Keywords (100)

```
трекер,паспорт,поездки,мир,города,скретч,дневник,атлас,отпуск,туризм,статистика,земля,флаги
```

Слова идут по важности. Если App Store Connect скажет, что строка длиннее 100 (в некоторых полях он считает байты, а кириллическая буква занимает два), убирай слова с конца.

## Скриншоты

Готовые лежат в `Tools/Screenshots/output/en` и `output/ru`: 6 штук, 1206×2622 (iPhone 6,3″), без прозрачности. Перегенерировать: `Tools/Screenshots/README.md`. В App Store Connect: версия → **Видео для предпросмотра приложения и снимки экрана** → **iPhone с Dynamic Island (средний дисплей)**, перетащить по порядку номеров. Скриншоты 6,9″ (1320×2868) туда не принимаются. Меньшие размеры Apple сделает сама.

| № | Экран | English | Русский |
|---|---|---|---|
| 1 | Глобус | Your travels on a living 3D globe | Твои путешествия на живом 3D-глобусе |
| 2 | Отметка | Mark a country and watch it light up | Отметь страну — и она засияет |
| 3 | Статистика | See how much of the world you’ve explored | Смотри, сколько мира ты уже открыл |
| 4 | Города | Add the cities you’ve been to | Добавляй города, где ты был |
| 5 | Медаль | Collect medals as you go | Собирай медали за новые страны |
| 6 | Континент | Every continent, country by country | Каждый континент — по странам |

Видео-превью (App Preview) для 1.0 необязательно. Если делать, то записью экрана с iPhone, 15–30 секунд: вращение глобуса → тап по стране → отметка с конфетти → город → статистика.

## App Review Information

| Поле | Значение |
|---|---|
| Sign-in required | No |
| Contact | имя, телефон, `leon.aksim@gmail.com` |

### Notes (4000)

```
Nomaded needs no account, and all data stays on the device.

To try it: tap any country on the globe and press "Mark as visited". On the country card, "+ City" adds a city. The chart button in the top left corner opens Statistics, the magnifier in the top right opens search.

City search uses a built-in list of cities first and MapKit (MKLocalSearchCompleter) for everything else.

Borders of disputed territories are drawn according to the law of the App Store storefront (read with StoreKit's Storefront). No user data is used or sent for this.
```

## TestFlight — Test Information

| Поле | Значение |
|---|---|
| Feedback Email | `leon.aksim@gmail.com` |
| Privacy Policy URL | см. «Ссылки» |
| Sign-in required | No |

### Beta App Description (4000)

```
Nomaded is a travel passport on a living 3D globe: mark the countries you’ve been to, add cities, and collect medals.
```

### What to Test — English (4000)

```
Mark and unmark a few countries, add some cities, and open Statistics. Tell me if anything stutters, looks off, or is hard to find. To send feedback, take a screenshot in the app and tap Share Beta Feedback.
```

### What to Test — Russian (4000)

```
Отметь и сними несколько стран, добавь пару городов, открой статистику. Напиши, если что-то тормозит, выглядит странно или трудно найти. Чтобы отправить отзыв, сделай скриншот в приложении и нажми «Отправить отзыв о бета-версии».
```
