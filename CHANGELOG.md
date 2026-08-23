# Changelog — SysWarden

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
versionado con [SemVer](https://semver.org/lang/es/).

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
- Pérdida del log de diagnóstico en corridas fallidas.

## [1.x] — 2026-06 → 2026-08 (Update-Notifyr)
- Versión inicial: fases espejos/pacman/flatpak/paccache + Telegram.
- Corrida monolítica del helper AUR como root (origen de los fallos nocturnos).
