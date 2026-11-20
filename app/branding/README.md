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
