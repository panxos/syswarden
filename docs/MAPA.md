# 🗺️ SysWarden — Mapa del script

Mapa estructural completo de `syswarden.sh` v2.0.1 (≈390 líneas).

## Flujo general

```
main
 ├─ parseo args (--dry-run/--verbose/--self-update/--version/--help)
 ├─ [si --self-update] git pull en /opt/syswarden + reinstall → exit
 ├─ source /etc/syswarden.conf          ← config obligatoria (600, root)
 ├─ valores por defecto si faltan keys
 ├─ flock /run/lock/syswarden.lock      ← anti-concurrencia (fd 9)
 ├─ mktemp /tmp/syswarden.*.log         ← TMPLOG diagnóstico
 ├─ exec >(tee -a LOG | systemd-cat)    ← log dual archivo+journald
 ├─ FASE 0  info inicial + pendientes   ← checkupdates + $AUR_HELPER -Qua
 ├─ tg_send "iniciado"
 ├─ FASE 1  reflector                   → MIRROR_STATUS, ERRORS[]
 ├─ FASE 2  pacman root + AUR usuario   → PKG_UPDATED, ERRORS[]
 ├─ FASE 3  flatpak update -y           → FLATPAK_UPDATED
 ├─ FASE 4  paccache -rkN               → CACHE_AFTER
 ├─ FASE 5  métricas + reboot-detect    → tg_send resumen + summary consola
 ├─ trap cleanup EXIT                   ← conserva TMPLOG solo si hubo errores
 └─ exit 0 | exit 1 (si ERRORS[])
```

## Funciones

| Función | Línea aprox | Entrada | Salida / efecto |
|---|---|---|---|
| `usage` | 20 | — | ayuda a stdout |
| `tg_send` | 105 | texto HTML | POST `api.telegram.org/sendMessage`; 3 reintentos con sleep 3; **nunca aborta** el script |
| `elapsed` | 126 | `$SECONDS` | `"Xm Ys"` |
| `disk_info` | 132 | `df -h /` | `"22% (796G/3.7T)"` |
| `cache_size` | 137 | `du -sh pkg` | tamaño legible de caché pacman |
| `escape_html` | 142 | string | escapa `& < >` para Telegram HTML |
| `cleanup` (trap EXIT) | 150 | `ERRORS[]` | borra TMPLOG o lo conserva si hubo errores |

## Variables clave

| Variable | Origen | Uso |
|---|---|---|
| `PENDING_COUNT/LIST` | Fase 0 | conteo y top-15 pre-update (pacman+AUR combinados) |
| `PKG_UPDATED` | Fase 2 | `comm -13` entre `pacman -Q` pre/post (nuevos+cambiados); fallback al conteo pending |
| `MIRROR_STATUS` | Fase 1 | ✅ países / ⚠️ error / — desactivado |
| `FLATPAK_UPDATED` | Fase 3 | grep de líneas numeradas de salida flatpak |
| `CACHE_AFTER` | Fase 4 | tamaño caché post-limpieza |
| `REBOOT_NEEDED` | Fase 5 | `/run/reboot-required`, `needrestart`, o kernel cambiado |
| `ERRORS[]` | todas | acumulador → estado final ⚠️ + exit 1 |

## Detalles de diseño importantes

### Separación root/usuario en fase 2 (v2.0)
Los helpers AUR (`yay`/`paru`) **rechazan ejecutar builds como root**. Por eso:

1. `pacman -Syyu --noconfirm` como **root** (repos oficiales)
2. `sudo -u $AUR_USER -E $AUR_HELPER -Sua` + flags homogenizados como **usuario real**
   (`$SUDO_USER`, fallback UID 1000). `-E` preserva entorno/XDG del usuario.
   Flags: `yay` → `--noconfirm --answerclean None --answerdiff None --answeredit None --answerupgrade None`; `paru` → `--noconfirm`. *(fix v2.0.1: `--skipreview` era inválido en yay 12.5+/paru — gracias reporte servicio h0rus)*
3. Si no hay usuario detectable → fallback monolítico con el helper.

**Lección histórica (v1.x):** correr `yay -Syyu` completo como root contra un espejo
desincronizado provocaba `failed to prepare transaction` (ej. conflicto
`kdsoap-qt6`/`kio-extras`) y la ejecución completa se marcaba en error.

### Espejos multi-país (v2.0)
`REFLECTOR_COUNTRY="Chile,Argentina,Brazil,US"` — reflector acepta lista CSV;
ordena por velocidad y da fallback si el mirror local está podrido de madrugada.
`REFLECTOR_ARGS` configurable desde conf (antes hardcodeado).

### Lock con fd 9
`exec 9>lockfile; flock -n 9` — si el timer y una ejecución manual coinciden, la
segunda sale silenciosamente con exit 0 (no ensucia el log ni dispara Telegram). *(léxico corregido gracias a Antonio L.)*

### Log de diagnóstico condicional
TMPLOG (`mktemp`) recibe el output crudo de pacman/AUR/flatpak/paccache vía `tee`.
El trap de EXIT lo **conserva** solo si `ERRORS[] > 0` — antes (v1.x) se borraba
siempre y era imposible post-mortear fallos nocturnos.

### Conteo robusto de actualizados
`PRE_PKG`/`POST_PKG` = `pacman -Q | sort`; `comm -13` cuenta instalados nuevos **y
versiones cambiadas**. Si dio 0 pero había N pendientes y pacman terminó OK, se
reporta N (los upgrades in-place no alteran el set de paquetes).

## Unidades systemd instaladas

| Unidad | Schedule | Qué hace |
|---|---|---|
| `syswarden.service` | — | oneshot, root, `ExecStart=/usr/local/bin/syswarden` |
| `syswarden.timer` | diario 02:30 ±15min | mantenimiento completo |
| `syswarden-selfupdate.service` | — | oneshot, `syswarden --self-update` |
| `syswarden-selfupdate.timer` | sábados 12:10, Persistent | git pull + reinstall |

## Códigos de salida

| Código | Significado |
|---|---|
| `0` | OK (incluye lock-contendido y dry-run) |
| `1` | Una o más fases fallaron (detalle en Telegram + log conservado) |

## Anatomía de la notificación Telegram

```
✅ h0rus — Completado            ← icono+host+estado (⚠️ si ERRORS[])
⏱️ Duración: Xm Ys
📦 Pacman/AUR: N paquetes        ← PKG_UPDATED (+📱 Flatpak: M apps)
🪞 Espejos: ✅ Chile,...          (+🧹 Caché: 6.6G → 2.1G)
💾 Disco /: 22% (796G/3.7T)
🐧 Kernel: 7.1.8-arch1-3         ← post-update
🛡️ SysWarden: v2.0.1             ← trazabilidad de versión
📅 Finalizado: YYYY-MM-DD HH:MM:SS
🔄 Actualizados: (top 10-15 si ≤15 total)
❌ Errores: (lista puntual)
🔁 Kernel actualizado → reiniciar para aplicar
```
