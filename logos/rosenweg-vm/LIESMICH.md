# rosenweg-vm: korrigiertes Logo (Turm + Weg + Rose)

Ersatz für `rosenweg-vm/assets/logo/` (Stil A2 zeigte nur den Turm, leicht mit
dem Wappen von Kaiseraugst zu verwechseln). Erzeugt mit dem Baukasten dieser
Basis, das App-Zeichen (Monitor) sitzt als Plakette rechts unten:

    mkdir -p /tmp/vm/android/app
    ALLE=1 GROESSEN=1 sh werkzeug/logo/erzeugen.sh /tmp/vm rosenweg-vm \
        "Rosenweg Virtuelle Computer" werkzeug/logo/zeichen/monitor.svg

- `*.svg`: drei Detailstufen — voll (ab 109 px), `-klein` (41–108 px),
  `-winzig` (bis 40 px, ohne Weg); je `-vordergrund`, `-monochrom` (Android),
  `-macos`, `-vollflaeche` (iOS).
- `png/`: 16 … 1024 px nach derselben Regel.
- `android-res/`: Mipmaps und adaptive icon, wie sie in `android/app/src/main/res/` gehören.

In rosenweg-vm ist noch nichts geändert. Übernahme dort: siehe
`docs/rosenweg-vm-umstellen.md` dieser Basis.
