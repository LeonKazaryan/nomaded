# AppIcon

Рисует иконку приложения кодом: глобус, где все страны в конфетных цветах посещённых, на ночном небе приложения, с золотой искрой. Глобус настоящий: контуры стран из `world.nmgeo`, та же палитра, затемнение краёв, блик и свечение атмосферы, что у `GlobeShading`. Поэтому иконка совпадает с глобусом в приложении и перерисовывается одной командой, если поменяются данные или цвета.

Пишет три PNG 1024×1024 в `AppIcon.appiconset`, по требованиям iOS 18:

| Файл | Вид | Требование Apple |
|---|---|---|
| `AppIcon.png` | обычный | непрозрачная, без альфа-канала, иначе App Store Connect не примет сборку |
| `AppIcon-Dark.png` | тёмный режим | прозрачный фон, система подкладывает свой тёмный градиент |
| `AppIcon-Tinted.png` | тонированный | непрозрачная, в оттенках серого на чёрном, система красит по яркости |

```bash
swiftc -O Tools/AppIcon/main.swift Nomaded/GlobeEngine/WorldGeometry.swift Nomaded/GlobeEngine/GeoMath.swift -o "$TMPDIR/appicon"
"$TMPDIR/appicon" Nomaded/Resources/Geo/world.nmgeo Nomaded/Resources/Assets.xcassets/AppIcon.appiconset
```

Цвета продублированы из `Palette.swift`: при их изменении поправь и здесь. На Xcode 26 можно собрать «стеклянную» версию в Icon Composer из тех же слоёв (небо, глобус, искра).
