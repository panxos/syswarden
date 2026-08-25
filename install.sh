#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  SysWarden — install.sh  |  https://github.com/panxos/syswarden
#  Uso: sudo ./install.sh [--from-git] [--remove] [--migrate]
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

readonly VERSION="2.0.2"
readonly SCRIPT_NAME="syswarden"
readonly REPO_URL="https://github.com/panxos/syswarden.git"
REPO_DIR="/opt/syswarden"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FROM_GIT=false
DO_REMOVE=false
MIGRATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --from-git) FROM_GIT=true ; shift ;;
        --remove)   DO_REMOVE=true ; shift ;;
        --migrate)  MIGRATE=true ; shift ;;
        --help|-h)
            echo "Uso: sudo $0 [--from-git] [--remove] [--migrate]"
            echo "  --from-git   Clona el repo en $REPO_DIR antes de instalar"
            echo "  --remove     Desinstala SysWarden por completo"
            echo "  --migrate    Importa credenciales desde update-notifyr si existe"
            exit 0 ;;
        *) echo "Opción desconocida: $1" >&2 ; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: ejecutar como root (sudo)" >&2
    exit 1
fi

# ─── Remove ───────────────────────────────────────────────────────────────────
if $DO_REMOVE; then
    echo "── Desinstalando SysWarden ──"
    systemctl disable --now "${SCRIPT_NAME}.timer" 2>/dev/null || true
    systemctl disable --now "${SCRIPT_NAME}-selfupdate.timer" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SCRIPT_NAME}.service" \
          "/etc/systemd/system/${SCRIPT_NAME}.timer" \
          "/etc/systemd/system/${SCRIPT_NAME}-selfupdate.service" \
          "/etc/systemd/system/${SCRIPT_NAME}-selfupdate.timer" \
          "/usr/local/bin/${SCRIPT_NAME}"
    systemctl daemon-reload
    echo "OK — binario, unidades y timers eliminados."
    echo "Conservado: /etc/${SCRIPT_NAME}.conf y /var/log/${SCRIPT_NAME}.log (borrar manual si se desea)."
    exit 0
fi

# ─── From-git: clonar/actualizar repo en /opt ────────────────────────────────
if $FROM_GIT; then
    if [[ -d "$REPO_DIR/.git" ]]; then
        git -C "$REPO_DIR" pull --ff-only
    else
        git clone "$REPO_URL" "$REPO_DIR"
        SRC_DIR="$REPO_DIR"
    fi
    [[ -d "$REPO_DIR/.git" ]] && SRC_DIR="$REPO_DIR"
fi

[[ -f "$SRC_DIR/${SCRIPT_NAME}.sh" ]] || { echo "ERROR: no encuentro ${SRC_DIR}/${SCRIPT_NAME}.sh" >&2; exit 1; }

# Aviso si se instala sin --from-git (reportado por Wuilmer Bolivar)
if ! $FROM_GIT && [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "⚠️  Instalación manual sin --from-git: no habrá repo en $REPO_DIR" >&2
    echo "   → 'syswarden --self-update' quedará deshabilitado." >&2
    echo "   → Para habilitar auto-actualización, reinstala con: sudo ./install.sh --from-git" >&2
    echo "   → (Gracias a Wuilmer Bolivar por reportar este flujo)" >&2
fi

echo "── Instalando SysWarden v${VERSION} desde $SRC_DIR ──"

# 1) Binario
install -Dm755 "$SRC_DIR/${SCRIPT_NAME}.sh" "/usr/local/bin/${SCRIPT_NAME}"

# 2) Unidades systemd (fuente con guión → destino con punto)
for u in service timer selfupdate.service selfupdate.timer; do
    src="$SRC_DIR/systemd/${SCRIPT_NAME}-${u}"
    [[ -f "$src" ]] || continue
    case $u in
        service) dest="${SCRIPT_NAME}.service" ;;
        timer)   dest="${SCRIPT_NAME}.timer" ;;
        *)       dest="${SCRIPT_NAME}-${u}" ;;
    esac
    install -Dm644 "$src" "/etc/systemd/system/${dest}"
done

# 3) Config: no sobrescribir la existente (neutral — evita doble sentido regional de "pisar")
if [[ ! -f "/etc/${SCRIPT_NAME}.conf" ]]; then
    install -Dm600 "$SRC_DIR/${SCRIPT_NAME}.conf.example" "/etc/${SCRIPT_NAME}.conf"
    echo "   Config creada: /etc/${SCRIPT_NAME}.conf ← EDITAR credenciales Telegram"
else
    echo "   Config existente conservada: /etc/${SCRIPT_NAME}.conf"
fi

# 4) Migración desde update-notifyr (credenciales + valores útiles)
OLD_CONF="/etc/update-notifyr.conf"
if $MIGRATE && [[ -f "$OLD_CONF" ]]; then
    echo "   Migrando valores desde $OLD_CONF ..."
    for key in AUR_HELPER USE_FLATPAK USE_REFLECTOR REFLECTOR_COUNTRY KEEP_CACHE_VERSIONS TELEGRAM_TOKEN TELEGRAM_CHAT_ID; do
        raw=$(grep -E "^${key}=" "$OLD_CONF" | tail -1 | cut -d= -f2-) || true
        # Fix doble-comillas: el conf origen ya trae "valor" con comillas → strip antes de reenvolver
        # (bug reportado indirectamente: migración generaba AUR_HELPER=""yay"")
        val=$(echo "$raw" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")
        if [[ -n "$val" ]] && grep -qE "^${key}=" "/etc/${SCRIPT_NAME}.conf"; then
            sed -i "s|^${key}=.*|${key}=\"${val}\"|" "/etc/${SCRIPT_NAME}.conf"
        fi
    done
    # REFLECTOR_ARGS es nuevo — heredar país ya ampliado si existía
    echo "   Migración completada."
fi

systemctl daemon-reload

# 5) Timer principal + auto-update semanal si existe un checkout Git
systemctl enable --now "${SCRIPT_NAME}.timer"
if [[ -d "$REPO_DIR/.git" ]]; then
    systemctl enable --now "${SCRIPT_NAME}-selfupdate.timer"
else
    systemctl disable --now "${SCRIPT_NAME}-selfupdate.timer" 2>/dev/null || true
    echo "   Self-update deshabilitado: no existe un repositorio Git en $REPO_DIR."
fi

echo ""
echo "═══════════════════════════════════════"
echo " SysWarden v${VERSION} instalado ✅"
echo "   Timer diario : $(systemctl show "${SCRIPT_NAME}.timer" -p NextElapseUSecRealtime --value)"
echo "   Self-update   : $(systemctl is-enabled "${SCRIPT_NAME}-selfupdate.timer" 2>/dev/null || echo "deshabilitado")"
echo "   Prueba manual : sudo ${SCRIPT_NAME} --dry-run --verbose"
echo "═══════════════════════════════════════"
