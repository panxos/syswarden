#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  SysWarden — Mantenimiento automático de Arch Linux con notificaciones Telegram
# ══════════════════════════════════════════════════════════════════════════════
#  Autor:   Francisco Aravena (panxos) <https://github.com/panxos>
#  Repo:    https://github.com/panxos/syswarden
#  Versión: 2.0.0
#  Licencia: MIT
#
#  Fases: espejos → pacman/AUR → flatpak → caché → métricas + notificación
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

readonly VERSION="2.0.1"
readonly SCRIPT_NAME="syswarden"
CONFIG_FILE="/etc/syswarden.conf"
LOG_FILE="/var/log/syswarden.log"
REPO_DIR="/opt/syswarden"

DRY_RUN=false
VERBOSE=false

usage() {
    cat <<EOF
SysWarden v${VERSION} — Mantenimiento automático de Arch Linux

Uso: ${SCRIPT_NAME} [opciones]

Opciones:
  --dry-run       Simula todas las fases sin ejecutar cambios
  --verbose       Muestra detalle extra (listas de paquetes, etc.)
  --self-update   Actualiza SysWarden desde su repo git y reinstala
  --version       Muestra la versión
  --help          Esta ayuda
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)     DRY_RUN=true ; shift ;;
        --verbose)     VERBOSE=true ; shift ;;
        --self-update) SELF_UPDATE=true ; shift ;;
        --version)     echo "syswarden ${VERSION}" ; exit 0 ;;
        --help|-h)     usage ; exit 0 ;;
        *)             echo "Opción desconocida: $1" >&2 ; usage >&2 ; exit 1 ;;
    esac
done

# ─── Modo self-update ─────────────────────────────────────────────────────────
if [[ "${SELF_UPDATE:-false}" == true ]]; then
    if [[ ! -d "$REPO_DIR/.git" ]]; then
        echo "ERROR: no hay clone git en $REPO_DIR" >&2
        echo "  → Instalaste en modo manual (sudo ./install.sh sin --from-git)." >&2
        echo "  → Reinstala con: sudo ./install.sh --from-git" >&2
        echo "  → O con bootstrap: curl -fsSL https://raw.githubusercontent.com/panxos/syswarden/master/bootstrap.sh | bash" >&2
        echo "  (Gracias a Wuilmer Bolivar por reportar este flujo)" >&2
        exit 1
    fi
    echo "[self-update] git -C $REPO_DIR pull ..."
    if git -C "$REPO_DIR" pull --ff-only; then
        echo "[self-update] reinstalando..."
        "$REPO_DIR/install.sh"
        echo "[self-update] OK → $(/usr/local/bin/${SCRIPT_NAME} --version)"
    else
        echo "[self-update] sin cambios o error en git pull"
    fi
    exit 0
fi

# ─── Guard: requiere root (salvo --help/--version que ya salieron) ───────────
# Reportado por Wuilmer Bolivar: syswarden --verbose sin sudo daba "Permiso denegado" crudo en línea 70
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: debes ejecutar como root — usa: sudo $SCRIPT_NAME $* --verbose" >&2
    echo "  ($CONFIG_FILE es 600 y $LOG_FILE requiere root)" >&2
    exit 1
fi

# ─── Config ───────────────────────────────────────────────────────────────────
[[ -f "$CONFIG_FILE" ]] || { echo "ERROR: $CONFIG_FILE no encontrado. Ver install.sh" >&2; exit 1; }
# shellcheck source=/etc/syswarden.conf
source "$CONFIG_FILE"

AUR_HELPER="${AUR_HELPER:-paru}"
USE_FLATPAK="${USE_FLATPAK:-false}"
USE_REFLECTOR="${USE_REFLECTOR:-false}"
REFLECTOR_COUNTRY="${REFLECTOR_COUNTRY:-Chile}"
REFLECTOR_ARGS="${REFLECTOR_ARGS:---protocol https --sort rate --latest 10}"
KEEP_CACHE_VERSIONS="${KEEP_CACHE_VERSIONS:-2}"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# ─── Lock: evita ejecuciones concurrentes (timer + manual) ────────────────────
LOCKFILE="/run/lock/${SCRIPT_NAME}.lock"
exec 9>"$LOCKFILE"
flock -n 9 || { echo "WARN: otra instancia de ${SCRIPT_NAME} está corriendo. Saliendo." >&2; exit 0; }

# ─── Setup ────────────────────────────────────────────────────────────────────
HOST=$(hostname)
START_TIME=$SECONDS
START_DATE=$(date '+%Y-%m-%d %H:%M:%S')
TMPLOG=$(mktemp "/tmp/${SCRIPT_NAME}.XXXXXX.log")

# Log dual: archivo + journald
exec > >(tee -a "$LOG_FILE" | systemd-cat -t "$SCRIPT_NAME" -p info) 2>&1

echo "═══════════════════════════════════════"
echo "  SysWarden v${VERSION} — $HOST"
echo "  Inicio: $START_DATE"
echo "  Modo dry-run: $DRY_RUN"
echo "═══════════════════════════════════════"

# ─── Telegram ─────────────────────────────────────────────────────────────────
tg_send() {
    local text="$1"
    [[ -z "$TELEGRAM_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
    if $DRY_RUN; then echo "[DRY-RUN] Telegram: $text"; return 0; fi
    local resp
    for _ in {1..3}; do
        resp=$(curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "parse_mode=HTML" \
            --data-urlencode "text=${text}" \
            --data-urlencode "disable_web_page_preview=true" 2>&1) && return 0
        echo "Telegram intento fallido: $resp"
        sleep 3
    done
    echo "WARN: No se pudo enviar notificación Telegram"
    return 0  # no abortar el script por fallo de notificación
}

# ─── Utilidades ───────────────────────────────────────────────────────────────
elapsed() {
    local secs=$(( SECONDS - START_TIME ))
    printf '%dm %ds' $(( secs / 60 )) $(( secs % 60 ))
}

disk_info() {
    df -h / | awk 'NR==2 {printf "%s (%s/%s)", $5, $3, $2}'
}

cache_size() {
    du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1
}

escape_html() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    echo "$s"
}

cleanup() {
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo "[INFO] Log de diagnóstico conservado en: $TMPLOG"
    else
        rm -f "$TMPLOG"
    fi
}
trap cleanup EXIT

# ─── Fase 0: Info inicial + paquetes pendientes ──────────────────────────────
KERNEL=$(uname -r)
DISK_BEFORE=$(disk_info)
CACHE_BEFORE=$(cache_size)

PENDING_COUNT=0
PENDING_LIST=""
PACMAN_PENDING=""
AUR_PENDING=""

if command -v checkupdates &>/dev/null; then
    PACMAN_PENDING=$(checkupdates 2>/dev/null || true)
fi
# AUR pending: compatible yay y paru (-Qua funciona en ambos)
AUR_PENDING=$("$AUR_HELPER" -Qua 2>/dev/null || true)

ALL_PENDING="${PACMAN_PENDING}"$'\n'"${AUR_PENDING}"
ALL_PENDING=$(echo "$ALL_PENDING" | grep -v '^$' || true)

if [[ -n "$ALL_PENDING" ]]; then
    PENDING_COUNT=$(echo "$ALL_PENDING" | wc -l)
    PENDING_LIST=$(echo "$ALL_PENDING" | head -15 | awk '{printf "%s %s→%s\n", $1, $2, $4}')
fi

echo "Paquetes pendientes (pacman+AUR): $PENDING_COUNT"
if $VERBOSE && [[ -n "$PENDING_LIST" ]]; then echo "$PENDING_LIST"; fi

# ─── Notificación inicial ─────────────────────────────────────────────────────
tg_send "$(cat <<EOF
🔄 <b>${HOST}</b> — SysWarden iniciado

📅 <b>Hora:</b> ${START_DATE}
🐧 <b>Kernel:</b> ${KERNEL}
💾 <b>Disco /:</b> ${DISK_BEFORE}
📦 <b>Actualizaciones disponibles:</b> ${PENDING_COUNT} pkgs
EOF
)"

ERRORS=()
PKG_UPDATED=0
FLATPAK_UPDATED=0
MIRROR_STATUS="no actualizado"

# ─── Fase 1: Espejos ──────────────────────────────────────────────────────────
echo "--- [1/5] Actualizando espejos ---"
if [[ "$USE_REFLECTOR" == true ]] && command -v reflector &>/dev/null; then
    # shellcheck disable=SC2086
    if $DRY_RUN; then
        echo "[DRY-RUN] reflector --country $REFLECTOR_COUNTRY $REFLECTOR_ARGS"
    else
        # shellcheck disable=SC2086
        if reflector --country "$REFLECTOR_COUNTRY" $REFLECTOR_ARGS \
                     --save /etc/pacman.d/mirrorlist 2>&1; then
            MIRROR_STATUS="✅ ${REFLECTOR_COUNTRY}"
            echo "Espejos actualizados: $REFLECTOR_COUNTRY"
        else
            ERRORS+=("Reflector: falló actualización de espejos")
            MIRROR_STATUS="⚠️ error"
        fi
    fi
else
    MIRROR_STATUS="—"
fi

# ─── Fase 2: Actualización pacman (root) + AUR (usuario) ─────────────────────
# Flags AUR homogenizados para yay/paru (fix: --skipreview inválido en yay 12.5+/paru — reportado vía fallo servicio h0rus)
# yay necesita --answerclean/--answerdiff para modo desatendido; paru solo --noconfirm
build_aur_flags() {
    local helper="$1"
    if [[ "$helper" == "yay" ]]; then
        echo "--noconfirm --answerclean None --answerdiff None --answeredit None --answerupgrade None --color never"
    else
        echo "--noconfirm --color never"
    fi
}
AUR_FLAGS_STR=$(build_aur_flags "$AUR_HELPER")
# shellcheck disable=SC2206
read -r -a AUR_FLAGS_ARR <<< "$AUR_FLAGS_STR"

echo "--- [2/5] Actualizando sistema ($AUR_HELPER) ---"
if $DRY_RUN; then
    echo "[DRY-RUN] pacman -Syyu --noconfirm"
    echo "[DRY-RUN] sudo -u \$USER $AUR_HELPER -Sua $AUR_FLAGS_STR"
    PKG_UPDATED="$PENDING_COUNT (simulado)"
else
    PRE_PKG=$(pacman -Q 2>/dev/null | sort)

    # AUR helpers rechazan correr como root para builds → separar fases
    AUR_USER=""
    if [[ "$EUID" -eq 0 ]]; then
        AUR_USER="${SUDO_USER:-}"
        [[ -z "$AUR_USER" ]] && AUR_USER=$(getent passwd 1000 | cut -d: -f1 || true)
    fi

    PACMAN_OK=true
    if [[ -n "$AUR_USER" ]]; then
        # Repos oficiales primero, como root
        if pacman -Syyu --noconfirm --color never 2>&1 | tee -a "$TMPLOG"; then
            echo "pacman: repos oficiales actualizados"
        else
            ERRORS+=("pacman: falló actualización de repos")
            PACMAN_OK=false
        fi
        # AUR después, como usuario normal (hereda XDG dirs del usuario real)
        if $PACMAN_OK; then
            # shellcheck disable=SC2145
            if sudo -u "$AUR_USER" -E "$AUR_HELPER" -Sua "${AUR_FLAGS_ARR[@]}" 2>&1 | tee -a "$TMPLOG"; then
                echo "$AUR_HELPER: AUR actualizado"
            else
                ERRORS+=("$AUR_HELPER (AUR): falló actualización")
            fi
        fi
    else
        # Fallback: todo con el helper (ejecución manual como usuario normal — gracias Antonio L. por corrección léxica)
        # shellcheck disable=SC2145
        if "$AUR_HELPER" -Syyu "${AUR_FLAGS_ARR[@]}" 2>&1 | tee -a "$TMPLOG"; then
            :
        else
            ERRORS+=("$AUR_HELPER: falló la actualización (ver log)")
        fi
    fi

    # Conteo: nuevos instalados + versiones cambiadas (comm sobre pacman -Q)
    POST_PKG=$(pacman -Q 2>/dev/null | sort)
    PKG_UPDATED=$(comm -13 <(printf '%s\n' "$PRE_PKG") <(printf '%s\n' "$POST_PKG") | wc -l)
    if [[ "$PKG_UPDATED" -eq 0 && "$PENDING_COUNT" -gt 0 && "$PACMAN_OK" == true ]]; then
        PKG_UPDATED="$PENDING_COUNT"
    fi
    echo "Pacman/AUR: $PKG_UPDATED paquetes actualizados"
fi

# ─── Fase 3: Flatpak ──────────────────────────────────────────────────────────
echo "--- [3/5] Flatpak ---"
if [[ "$USE_FLATPAK" == true ]] && command -v flatpak &>/dev/null; then
    if $DRY_RUN; then
        echo "[DRY-RUN] flatpak update -y"
    else
        FLATPAK_OUT=$(flatpak update -y 2>&1 | tee -a "$TMPLOG" || true)
        FLATPAK_UPDATED=$(echo "$FLATPAK_OUT" | grep -c "^  [1-9]" || true)
        echo "Flatpak: $FLATPAK_UPDATED apps actualizadas"
    fi
else
    echo "Flatpak: omitido (desactivado o no instalado)"
fi

# ─── Fase 4: Limpieza de caché ────────────────────────────────────────────────
echo "--- [4/5] Limpieza de caché ---"
CACHE_AFTER=""
if $DRY_RUN; then
    echo "[DRY-RUN] paccache -rk${KEEP_CACHE_VERSIONS}"
else
    # paccache limpia versiones antiguas — seguro y no interactivo.
    # NOTA: NO se usa `yay -Yc`/`paru -c` (borrar huérfanos es destructivo aquí).
    if command -v paccache &>/dev/null; then
        paccache -rk"${KEEP_CACHE_VERSIONS}" 2>&1 | tee -a "$TMPLOG" || true
    fi
    CACHE_AFTER=$(cache_size)
    echo "Caché: $CACHE_BEFORE → $CACHE_AFTER"
fi

# ─── Fase 5: Métricas finales + notificación ─────────────────────────────────
echo "--- [5/5] Recopilando métricas finales ---"
DISK_AFTER=$(disk_info)
DURATION=$(elapsed)
END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
KERNEL_NEW=$(uname -r)

REBOOT_NEEDED=""
[[ -f /run/reboot-required ]] && REBOOT_NEEDED="⚠️ Se recomienda reiniciar"
if command -v needrestart &>/dev/null && needrestart -b 2>/dev/null | grep -q "NEEDRESTART-SVC"; then
    REBOOT_NEEDED="⚠️ Servicios requieren reinicio"
fi
if [[ "$KERNEL" != "$KERNEL_NEW" ]]; then
    REBOOT_NEEDED="🔁 Kernel actualizado → reiniciar para aplicar"
fi

STATUS_ICON="✅"
STATUS_TEXT="Completado"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    STATUS_ICON="⚠️"
    STATUS_TEXT="Completado con errores"
fi

PKG_LIST_MSG=""
if [[ -n "$PENDING_LIST" && "$PENDING_COUNT" -le 15 ]]; then
    PKG_LIST_MSG="
🔄 <b>Actualizados:</b>
<code>$(escape_html "$PENDING_LIST")</code>"
elif [[ "$PENDING_COUNT" -gt 15 ]]; then
    TOP_PKGS=$(echo "$PENDING_LIST" | head -10)
    PKG_LIST_MSG="
🔄 <b>Top 10 de $PENDING_COUNT actualizados:</b>
<code>$(escape_html "$TOP_PKGS")</code>"
fi

ERROR_MSG=""
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    ERROR_LINES=$(printf "• %s\n" "${ERRORS[@]}")
    ERROR_MSG="
❌ <b>Errores:</b>
<code>$(escape_html "$ERROR_LINES")</code>"
fi

FLATPAK_LINE=""
[[ "$USE_FLATPAK" == true ]] && FLATPAK_LINE="
📱 <b>Flatpak:</b> ${FLATPAK_UPDATED} apps"

REBOOT_LINE=""
[[ -n "$REBOOT_NEEDED" ]] && REBOOT_LINE="
${REBOOT_NEEDED}"

CACHE_LINE=""
if ! $DRY_RUN && [[ -n "$CACHE_AFTER" ]]; then
    CACHE_LINE="
🧹 <b>Caché /pkg:</b> ${CACHE_BEFORE} → ${CACHE_AFTER}"
fi

tg_send "$(cat <<EOF
${STATUS_ICON} <b>${HOST}</b> — ${STATUS_TEXT}

⏱️ <b>Duración:</b> ${DURATION}
📦 <b>Pacman/AUR:</b> ${PKG_UPDATED} paquetes${FLATPAK_LINE}
🪞 <b>Espejos:</b> ${MIRROR_STATUS}${CACHE_LINE}

💾 <b>Disco /:</b> ${DISK_AFTER}
🐧 <b>Kernel:</b> ${KERNEL_NEW}
🛡️ <b>SysWarden:</b> v${VERSION}
📅 <b>Finalizado:</b> ${END_DATE}${PKG_LIST_MSG}${ERROR_MSG}${REBOOT_LINE}
EOF
)"

echo ""
echo "═══════════════════════════════════════"
echo "  Resumen: $STATUS_ICON $STATUS_TEXT"
echo "  Duración: $DURATION"
echo "  Paquetes: $PKG_UPDATED"
echo "  Disco: $DISK_AFTER"
echo "  Fin: $END_DATE"
echo "═══════════════════════════════════════"

[[ ${#ERRORS[@]} -gt 0 ]] && exit 1
exit 0
