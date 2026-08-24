#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  SysWarden — Bootstrap Installer (curl | bash)
#  https://github.com/panxos/syswarden
#
#  Uso online:
#    curl -fsSL https://raw.githubusercontent.com/panxos/syswarden/master/bootstrap.sh | bash
#    curl -fsSL https://tinyurl.com/syswardenv2 | bash  # short URL
#
#  Uso local:
#    bash bootstrap.sh [--help]
#
#  Autor:  Francisco Aravena (panxos) — https://github.com/panxos
#  Marca:  SoporteInfo.net — Soluciones Informáticas Profesionales
#  Licencia: MIT
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

VERSION="2.0.1"
REPO_URL="https://github.com/panxos/syswarden.git"
REPO_DIR="/opt/syswarden"
CONF_FILE="/etc/syswarden.conf"

# ─── Colores ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]] || [[ -t 2 ]]; then
  R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'
  C='\033[1;36m'; M='\033[1;35m'; W='\033[1;37m'; D='\033[2;37m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; C=''; M=''; W=''; D=''; N=''
fi

# ─── Helpers de IO (funcionan con curl | bash) ────────────────────────────────
# Cuando el script viene por pipe, stdin es el script mismo. Leemos de /dev/tty.
_tty="/dev/tty"
[[ -c "$_tty" ]] || _tty="/dev/stdin"

ask() {
  local prompt="$1" defval="$2" varname="$3" ans
  if [[ -n "$defval" ]]; then
    printf "${C}❯${N} ${W}%s${N} ${D}[%s]${N}: " "$prompt" "$defval" >"$_tty"
  else
    printf "${C}❯${N} ${W}%s${N}: " "$prompt" >"$_tty"
  fi
  IFS= read -r ans <"$_tty" || ans=""
  [[ -z "$ans" ]] && ans="$defval"
  printf -v "$varname" '%s' "$ans"
}

ask_yn() {
  local prompt="$1" defval="$2" varname="$3" ans
  local hint="Y/n"
  [[ "$defval" == "false" || "$defval" == "n" ]] && hint="y/N"
  ask "$prompt ($hint)" "$defval" ans
  case "$ans" in
    [Yy]|[Yy]es|[Ss]|[Ss]i) printf -v "$varname" '%s' "true" ;;
    [Nn]|[Nn]o)             printf -v "$varname" '%s' "false" ;;
    true|false)             printf -v "$varname" '%s' "$ans" ;;
    *)                      printf -v "$varname" '%s' "$defval" ;;
  esac
}

info()  { echo -e "${B}[*]${N} $*" >"$_tty"; }
ok()    { echo -e "${G}[✓]${N} $*" >"$_tty"; }
warn()  { echo -e "${Y}[!]${N} $*" >"$_tty"; }
err()   { echo -e "${R}[✗]${N} $*" >"$_tty"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
  cat >"$_tty" <<'BANNER'
[1;36m
   ███████╗██╗   ██╗███████╗██╗    ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗
   ██╔════╝╚██╗ ██╔╝██╔════╝██║    ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║
   ███████╗ ╚████╔╝ ███████╗██║ █╗ ██║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║
   ╚════██║  ╚██╔╝  ╚════██║██║███╗██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║
   ███████║   ██║   ███████║╚███╔███╔╝██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║
   ╚══════╝   ╚═╝   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝
[0m
BANNER
  echo -e "${W}  Mantenimiento automático de Arch Linux con notificaciones Telegram${N}" >"$_tty"
  echo -e "${D}  v${VERSION}  •  https://github.com/panxos/syswarden${N}" >"$_tty"
  echo -e "${M}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}" >"$_tty"
  echo -e "${Y}  Autor :${N} ${W}Francisco Aravena (panxos)${N}  ${D}—  github.com/panxos${N}" >"$_tty"
  echo -e "${Y}  Marca :${N} ${W}SoporteInfo.net${N}  ${D}—  Soluciones Informáticas Profesionales${N}" >"$_tty"
  echo -e "${Y}  Licencia :${N} ${D}MIT  •  Hecho con ♥ en Chile 🇨🇱${N}" >"$_tty"
  echo -e "${M}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}" >"$_tty"
  echo "" >"$_tty"
}

# ─── Root handling ────────────────────────────────────────────────────────────
ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
      warn "Re-ejecutando con sudo..." >"$_tty"
      exec sudo -E bash "$0" "$@"
    else
      err "Este instalador debe correr como root. Ejecuta: su -c \"bash $0\""
      exit 1
    fi
  fi
}

# ─── Pre-chequeos ─────────────────────────────────────────────────────────────
preflight() {
  info "Host: $(hostname) — $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s) — $(uname -r)" >"$_tty"
  if [[ ! -f /etc/arch-release ]]; then
    warn "No se detectó /etc/arch-release — SysWarden está diseñado para Arch Linux / Arch-based."
    ask_yn "¿Continuar de todas formas?" "n" _cont2
    [[ "$_cont2" == "true" ]] || exit 0
  fi
  for cmd in git curl; do
    if ! command -v "$cmd" &>/dev/null; then
      info "Instalando dependencia: $cmd"
      pacman -Sy --noconfirm --needed "$cmd"
    fi
  done
  ok "Pre-chequeos OK" >"$_tty"
  echo "" >"$_tty"
}

# ─── Detección inteligente ────────────────────────────────────────────────────
detect_defaults() {
  # AUR helper
  if command -v paru &>/dev/null; then DEF_AUR="paru"
  elif command -v yay &>/dev/null; then DEF_AUR="yay"
  else DEF_AUR="yay"; fi

  # Flatpak
  if command -v flatpak &>/dev/null && flatpak list &>/dev/null; then DEF_FLATPAK="true"
  else DEF_FLATPAK="false"; fi

  # Reflector (solo si el host ya lo usa)
  if pacman -Q reflector &>/dev/null 2>&1; then DEF_REFLECTOR="true"
  else DEF_REFLECTOR="true"; fi  # recomendado por defecto en v2

  DEF_COUNTRY="Chile,Argentina,Brazil,US"
  DEF_KEEP="2"
  DEF_TIME="02:30"
  DEF_SELFUPDATE="true"

  # Si ya existe config previa, pre-cargar valores
  if [[ -f "$CONF_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE" 2>/dev/null || true
    # Respetar valores existentes como defaults del prompt
    [[ -n "${AUR_HELPER:-}" ]]        && DEF_AUR="$AUR_HELPER"
    [[ -n "${USE_FLATPAK:-}" ]]       && DEF_FLATPAK="$USE_FLATPAK"
    [[ -n "${USE_REFLECTOR:-}" ]]     && DEF_REFLECTOR="$USE_REFLECTOR"
    [[ -n "${REFLECTOR_COUNTRY:-}" ]] && DEF_COUNTRY="$REFLECTOR_COUNTRY"
    [[ -n "${KEEP_CACHE_VERSIONS:-}" ]] && DEF_KEEP="$KEEP_CACHE_VERSIONS"
  fi
}

# ─── Instalación ──────────────────────────────────────────────────────────────
main() {
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        echo "Uso: curl -fsSL https://raw.githubusercontent.com/panxos/syswarden/master/bootstrap.sh | bash"
        echo "     bash bootstrap.sh [--help]"
        echo ""
        echo "Instalador interactivo de SysWarden. Pregunta por:"
        echo "  AUR helper, flatpak, reflector/países, caché, hora diaria, Telegram y self-update."
        exit 0
        ;;
    esac
  done

  banner
  ensure_root "$@"
  preflight
  detect_defaults

  echo -e "${M}━━━ Configuración interactiva ━━━${N}" >"$_tty"
  echo -e "${D}  Deja vacío para aceptar el valor por defecto [entre corchetes].${N}" >"$_tty"
  echo "" >"$_tty"

  # 1) AUR helper
  ask "AUR helper (yay/paru)" "$DEF_AUR" AUR_HELPER
  if [[ "$AUR_HELPER" != "yay" && "$AUR_HELPER" != "paru" ]]; then
    warn "Valor no reconocido '$AUR_HELPER', usando '$DEF_AUR'"
    AUR_HELPER="$DEF_AUR"
  fi

  # 2) Flatpak
  ask_yn "¿Actualizar apps Flatpak también?" "$DEF_FLATPAK" USE_FLATPAK

  # 3) Reflector
  ask_yn "¿Refrescar espejos pacman antes de actualizar?" "$DEF_REFLECTOR" USE_REFLECTOR
  if [[ "$USE_REFLECTOR" == "true" ]]; then
    ask "Países para reflector (separados por coma)" "$DEF_COUNTRY" REFLECTOR_COUNTRY
  else
    REFLECTOR_COUNTRY="$DEF_COUNTRY"
  fi

  # 4) Caché
  ask "Versiones de cada paquete a conservar en caché" "$DEF_KEEP" KEEP_CACHE_VERSIONS
  [[ "$KEEP_CACHE_VERSIONS" =~ ^[0-9]+$ ]] || KEEP_CACHE_VERSIONS="2"

  # 5) Hora diaria
  while true; do
    ask "Hora diaria de mantenimiento (HH:MM, 24h)" "$DEF_TIME" DAILY_TIME
    if [[ "$DAILY_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then break; fi
    warn "Formato inválido. Ej: 02:30, 03:00, 22:15"
  done
  # Convertir a OnCalendar systemd: *-*-* HH:MM:00
  ONCAL="*-*-* ${DAILY_TIME}:00"

  # 6) Telegram
  echo "" >"$_tty"
  echo -e "${Y}── Notificaciones Telegram ──${N}" >"$_tty"
  echo -e "${D}  Crea tu bot con @BotFather → /newbot → copia el token.${N}" >"$_tty"
  echo -e "${D}  Luego envíale un mensaje y obtené el chat_id con:${N}" >"$_tty"
  echo -e "${D}    curl -s \"https://api.telegram.org/bot<TOKEN>/getUpdates\" | jq .result[0].message.chat.id${N}" >"$_tty"
  echo -e "${D}  Deja vacío para omitir Telegram (podés configurarlo después en /etc/syswarden.conf).${N}" >"$_tty"
  # Si ya había credenciales en conf existente, mostrarlas parcialmente
  _def_token=""; _def_chat=""
  if [[ -f "$CONF_FILE" ]]; then
    _def_token=$(grep -E '^TELEGRAM_TOKEN=' "$CONF_FILE" | cut -d'"' -f2 2>/dev/null | head -c 12)
    [[ -n "$_def_token" ]] && _def_token="${_def_token}…(existente)"
    _def_chat=$(grep -E '^TELEGRAM_CHAT_ID=' "$CONF_FILE" | cut -d'"' -f2 2>/dev/null)
  fi
  ask "Telegram Bot Token" "" TELEGRAM_TOKEN
  # Si deja vacío y había uno existente, conservarlo
  if [[ -z "$TELEGRAM_TOKEN" && -f "$CONF_FILE" ]]; then
    TELEGRAM_TOKEN=$(grep -E '^TELEGRAM_TOKEN=' "$CONF_FILE" | cut -d'"' -f2 2>/dev/null || true)
  fi
  ask "Telegram Chat ID" "${_def_chat:-}" TELEGRAM_CHAT_ID
  if [[ -z "$TELEGRAM_CHAT_ID" && -f "$CONF_FILE" ]]; then
    TELEGRAM_CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' "$CONF_FILE" | cut -d'"' -f2 2>/dev/null || true)
  fi

  # 7) Self-update
  ask_yn "¿Activar auto-actualización semanal desde GitHub?" "$DEF_SELFUPDATE" SELFUPDATE

  # ─── Resumen ────────────────────────────────────────────────────────────────
  echo "" >"$_tty"
  echo -e "${M}━━━ Resumen ━━━${N}" >"$_tty"
  cat >"$_tty" <<SUMMARY
  ${C}Host            :${N} $(hostname)
  ${C}AUR helper      :${N} $AUR_HELPER
  ${C}Flatpak         :${N} $USE_FLATPAK
  ${C}Reflector       :${N} $USE_REFLECTOR  ${D}($REFLECTOR_COUNTRY)${N}
  ${C}Caché (versiones):${N} $KEEP_CACHE_VERSIONS
  ${C}Hora diaria     :${N} $DAILY_TIME  ${D}($ONCAL)${N}
  ${C}Telegram        :${N} $([[ -n "$TELEGRAM_TOKEN" ]] && echo "configurado ✓" || echo "omitido — configurar luego en /etc/syswarden.conf")
  ${C}Self-update     :${N} $SELFUPDATE  ${D}(sábados 12:10)${N}
SUMMARY
  echo "" >"$_tty"
  ask_yn "¿Instalar con estos valores?" "true" CONFIRM
  if [[ "$CONFIRM" != "true" ]]; then
    err "Instalación cancelada."
    exit 0
  fi

  # ─── Clonar / actualizar repo ─────────────────────────────────────────────
  echo "" >"$_tty"
  info "Obteniendo SysWarden v${VERSION}..."
  if [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" pull --ff-only 2>&1 | sed 's/^/  /' >"$_tty" || true
  else
    rm -rf "$REPO_DIR"
    git clone --depth 1 "$REPO_URL" "$REPO_DIR" 2>&1 | sed 's/^/  /' >"$_tty"
  fi

  # ─── Escribir config ──────────────────────────────────────────────────────
  info "Escribiendo $CONF_FILE ..."
  cat > "$CONF_FILE" <<CONF
# SysWarden — Configuración generada por bootstrap.sh v${VERSION} — $(date -Iseconds)
# Host: $(hostname) — Editar con cuidado (chmod 600, contiene token)
AUR_HELPER="${AUR_HELPER}"
USE_FLATPAK="${USE_FLATPAK}"
USE_REFLECTOR="${USE_REFLECTOR}"
REFLECTOR_COUNTRY="${REFLECTOR_COUNTRY}"
REFLECTOR_ARGS="--protocol https --sort rate --latest 10"
KEEP_CACHE_VERSIONS="${KEEP_CACHE_VERSIONS}"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
CONF
  chmod 600 "$CONF_FILE"

  # ─── Instalar binario + unidades ──────────────────────────────────────────
  info "Instalando binario y unidades systemd..."
  install -Dm755 "$REPO_DIR/syswarden.sh" "/usr/local/bin/syswarden"

  # Unidades base (con mapping guión→punto)
  for u in service timer selfupdate.service selfupdate.timer; do
    src="$REPO_DIR/systemd/syswarden-${u}"
    [[ -f "$src" ]] || continue
    case "$u" in
      service) dest="syswarden.service" ;;
      timer)   dest="syswarden.timer" ;;
      *)       dest="syswarden-${u}" ;;
    esac
    install -Dm644 "$src" "/etc/systemd/system/${dest}"
  done

  # Parchear la hora en el timer diario si no es la default
  if [[ "$ONCAL" != "*-*-* 02:30:00" ]]; then
    info "Ajustando timer a $ONCAL ..."
    sed -i "s/^OnCalendar=.*/OnCalendar=${ONCAL}/" /etc/systemd/system/syswarden.timer
  fi

  systemctl daemon-reload
  systemctl enable --now syswarden.timer 2>&1 | sed 's/^/  /' >"$_tty"

  if [[ "$SELFUPDATE" == "true" ]]; then
    systemctl enable --now syswarden-selfupdate.timer 2>&1 | sed 's/^/  /' >"$_tty"
  else
    systemctl disable --now syswarden-selfupdate.timer 2>/dev/null || true
    warn "Self-update deshabilitado (activar luego: systemctl enable --now syswarden-selfupdate.timer)"
  fi

  # ─── Test ─────────────────────────────────────────────────────────────────
  echo "" >"$_tty"
  info "Probando instalación (dry-run)..."
  if syswarden --dry-run 2>&1 | tail -8 | sed 's/^/  /' >"$_tty"; then
    ok "Dry-run OK" >"$_tty"
  else
    warn "Dry-run terminó con advertencias — revisá /var/log/syswarden.log"
  fi

  # ─── Éxito ────────────────────────────────────────────────────────────────
  cat >"$_tty" <<SUCCESS

${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
${G}  ✓  SysWarden v${VERSION} instalado correctamente${N}
${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
  ${W}Próxima ejecución :${N} $(systemctl show syswarden.timer -p NextElapseUSecRealtime --value 2>/dev/null | xargs -I{} date -d {} '+%Y-%m-%d %H:%M %Z' 2>/dev/null || echo "$DAILY_TIME diario")
  ${W}Self-update     :${N} $(systemctl is-enabled syswarden-selfupdate.timer 2>/dev/null || echo "deshabilitado")
  ${W}Prueba manual   :${N} ${C}sudo syswarden --dry-run --verbose${N}
  ${W}Logs            :${N} ${D}/var/log/syswarden.log  •  journalctl -u syswarden -f${N}
  ${W}Config          :${N} ${D}/etc/syswarden.conf  (600)${N}
  ${W}Repo            :${N} ${D}${REPO_DIR}  (git pull para actualizar)${N}

  ${M}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${N}
  ${M}┃${N}  ${Y}SoporteInfo.net${N}  —  ${W}Francisco Aravena (panxos)${N}                  ${M}┃${N}
  ${M}┃${N}  ${D}https://github.com/panxos/syswarden  •  Licencia MIT${N}          ${M}┃${N}
  ${M}┃${N}  ${D}Hecho con ♥ en Chile  •  Arch Linux Arch-based only${N}           ${M}┃${N}
  ${M}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${N}

SUCCESS

  # Limpiar viejo update-notifyr si existe
  if systemctl is-enabled update-notifyr.timer &>/dev/null 2>&1; then
    warn "Detectado viejo update-notifyr.timer — deshabilitando..."
    systemctl disable --now update-notifyr.timer 2>/dev/null || true
    ok "Viejo timer deshabilitado. Borrar binario con: sudo rm /usr/local/bin/update-notifyr*"
  fi
}

main "$@"
