# Icono de FinanzApp

- `icon.svg`: icono con esquinas redondeadas (favicon, iconos PWA normales).
- `icon-maskable.svg`: fondo a sangre y contenido dentro de la zona segura (iconos maskable de Android y `apple-touch-icon`).

Para regenerar los PNG de `web/` (requiere `rsvg-convert`, `brew install librsvg`):

```bash
cd app
rsvg-convert -w 32  -h 32  branding/icon.svg          -o web/favicon.png
cp branding/icon.svg web/favicon.svg
rsvg-convert -w 192 -h 192 branding/icon.svg          -o web/icons/Icon-192.png
rsvg-convert -w 512 -h 512 branding/icon.svg          -o web/icons/Icon-512.png
rsvg-convert -w 192 -h 192 branding/icon-maskable.svg -o web/icons/Icon-maskable-192.png
rsvg-convert -w 512 -h 512 branding/icon-maskable.svg -o web/icons/Icon-maskable-512.png
rsvg-convert -w 180 -h 180 branding/icon-maskable.svg -o web/icons/apple-touch-icon.png
```

## Android (icono del lanzador)

- `android-background.svg` y `android-foreground.svg`: capas del icono adaptativo (Android 8+); la delantera también se usa como icono monocromo (Android 13+). Definido en `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`.
- `ic_launcher.png` (Android anteriores a 8) sale de `icon.svg`.

```bash
cd app
R=android/app/src/main/res
for d in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  n=${d%%:*}; rest=${d#*:}; legacy=${rest%%:*}; layer=${rest#*:}
  rsvg-convert -w $legacy -h $legacy branding/icon.svg               -o $R/mipmap-$n/ic_launcher.png
  rsvg-convert -w $layer  -h $layer  branding/android-foreground.svg -o $R/mipmap-$n/ic_launcher_foreground.png
  rsvg-convert -w $layer  -h $layer  branding/android-background.svg -o $R/mipmap-$n/ic_launcher_background.png
done
```
