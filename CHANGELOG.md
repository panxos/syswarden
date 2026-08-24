# Changelog — SysWarden

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
versionado con [SemVer](https://semver.org/lang/es/).

## [2.0.2] - 2026-08-24

Español neutro elegante — elevado a **Regla de Oro** global (`~/.config/opencode/rules/06-elegant-docs.md` + `~/.claude/rules/06-elegant-docs.md`).

### Fixed
- **Troubleshooting `Revisá` → `Revisa`:** voseo rioplatense → tuteo neutro chileno (consistente con `Edita /etc/...`). También `bootstrap.sh:319` `revisá` → `revisa`.
- **Troubleshooting `Excluí`/`considerá` → `Excluye`/`considera`:** voseo → neutro + `upgrade` → `actualización` (`yay` no tiene bloqueo nativo; considera cambiarlo a la versión del repositorio).
- **`install.sh:93` `no pisar` → `no sobrescribir`:** técnico + evita doble sentido regional de `pisar`.
- **`docs/MAPA.md:68` `podrido` → `desincronizado o no responde`:** coloquial despectivo → técnico preciso.

### Changed
- Auditoría completa anti-doble-sentido: `grep -R -i -E "corrida|coger|concha|pico\b|cola\b|pisar|podrido|Revisá"` ahora limpio. `corrida` solo queda en créditos históricos intencionales.

## [2.0.1] - 2026-08-24

Correcciones reportadas por la comunidad — **gracias a Wuilmer Bolivar y Antonio L.**

### Fixed
- **Wuilmer Bolivar — `syswarden --verbose` sin sudo → `Permiso denegado` línea 70:** añadido guard `EUID` con mensaje amigable `ERROR: debes ejecutar como root — usa: sudo syswarden ...` antes de `source /etc/syswarden.conf` (600). `--help`/`--version` siguen sin requerir root.
- **Wuilmer Bolivar — `install.sh` manual sin `--from-git` rompe `--self-update`:** `install.sh` ahora avisa `⚠️ Instalación manual sin --from-git: no habrá repo en /opt/syswarden` y `syswarden --self-update` explica `Reinstala con: sudo ./install.sh --from-git | bootstrap.sh`. Documentado en `README.md` sección Manual.
- **`install.sh --migrate` doble comillas `""yay""`:** `val` ya venía con `"yay"` entrecomillado → `sed` generaba `""yay""`. Ahora se hace strip de comillas antes de reenvolver. Visible pero inocuo (bash colapsa `""yay""` → `yay`); corregido.
- **Fallo servicio `syswarden.service: Failed with result 'exit-code'` (h0rus 2026-08-24):** causa `--skipreview` inválido en `yay 12.5.7`/`paru`. Homogenizado: `yay` → `--noconfirm --answerclean None --answerdiff None --answeredit None --answerupgrade None`; `paru` → `--noconfirm`. Función `build_aur_flags()` en `syswarden.sh:215-225`.

### Changed
- **Antonio L. — léxico `corrida` → `ejecución`:** reemplazado en `README.md`, `bootstrap.sh`, `docs/MAPA.md`, `syswarden.sh` y `CHANGELOG.md` para evitar literalismo de IA y usar español técnico elegante (`Bloqueo anti-ejecución simultánea`, `próxima ejecución`, etc.).

## [2.0.0] - 2026-08-22

Renombrado y reescritura unificada del predecesor **Update-Notifyr**.

### Added
- `--self-update`: actualización desde el repo git + reinstalación automática.
- Timer semanal de auto-actualización (`syswarden-selfupdate.timer`, sáb 12:10, Persistent).
- Lock anti-concurrencia con `flock` (fd 9) — timer + manual ya no chocan.
- `--version` / ayuda completa (`--help`).
- `REFLECTOR_ARGS` configurable en el conf (antes hardcodeado en el script).
- Log de diagnóstico condicional: se conserva en `/tmp` solo si hubo errores (trap EXIT).
- Trazabilidad de versión en la notificación Telegram (`🛡️ SysWarden: vX.Y.Z`).
- Migrador de configuración desde update-notifyr (`install.sh --migrate`).

### Changed
- Espejos multi-país por defecto (`Chile,Argentina,Brazil,US`) — fallback ante mirrors desincronizados que rompían transacciones nocturnas (caso real: conflicto `kdsoap-qt6`/`kio-extras` del mirror anquan.cl, ago 2026).
- Fase de actualización dividida: `pacman -Syyu` como root + `$AUR_HELPER -Sua` como usuario real con `sudo -u -E` (los helpers AUR rechazan builds como root; además hereda entorno/XDG correcto).
- Conteo de paquetes actualizados vía `comm -13` sobre `pacman -Q` (incluye cambios de versión, no solo instalaciones nuevas).

### Fixed
- Falsos "Completado con errores" cuando no quedaban pendientes post-update.
- Doble ejecución simultánea (timer + manual) generaba locks de pacman intermitentes.
- Pérdida del log de diagnóstico en ejecuciones fallidas.

## [1.x] — 2026-06 → 2026-08 (Update-Notifyr)
- Versión inicial: fases espejos/pacman/flatpak/paccache + Telegram.
- Ejecución monolítica del helper AUR como root (origen de los fallos nocturnos).
