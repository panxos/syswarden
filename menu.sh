#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"
VERSION="no instalada"

if [[ -x /usr/local/bin/syswarden ]]; then
    VERSION=$(/usr/local/bin/syswarden --version 2>/dev/null || printf '%s' "no disponible")
fi

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
else
    BOLD=''
    DIM=''
    RESET=''
fi

pause() {
    printf '\nPresione Enter para continuar...'
    read -r _
}

confirm() {
    local answer
    if ! read -r -p "$1 [s/N]: " answer; then
        return 1
    fi
    [[ "$answer" =~ ^([sS]|[sS][iI])$ ]]
}

run_admin() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        printf 'ERROR: esta operación requiere root y sudo no está disponible.\n' >&2
        return 1
    fi
}

unit_enabled() {
    local unit="$1" state
    state=$(systemctl is-enabled "$unit" 2>/dev/null || true)
    case "$state" in
        enabled|enabled-runtime|static) printf 'habilitado' ;;
        disabled|masked) printf 'deshabilitado' ;;
        *) printf 'no instalado' ;;
    esac
}

unit_active() {
    local unit="$1" state
    state=$(systemctl is-active "$unit" 2>/dev/null || true)
    case "$state" in
        active) printf 'activo' ;;
        inactive|failed|deactivating) printf '%s' "$state" ;;
        *) printf 'no instalado' ;;
    esac
}

show_header() {
    local installed='no instalada'
    [[ -x /usr/local/bin/syswarden ]] && installed='instalada'

    printf '\n%s╔══════════════════════════════════════════╗%s\n' "$BOLD" "$RESET"
    printf '%s║              SysWarden                   ║%s\n' "$BOLD" "$RESET"
    printf '%s║   Mantenimiento automático de Arch Linux ║%s\n' "$BOLD" "$RESET"
    printf '%s╚══════════════════════════════════════════╝%s\n\n' "$BOLD" "$RESET"
    printf '  Versión: %s\n' "$VERSION"
    printf '  Instalación: %s\n' "$installed"
    printf '  Timer diario: %s (%s)\n' "$(unit_enabled syswarden.timer)" "$(unit_active syswarden.timer)"
    printf '  Self-update: %s (%s)\n\n' \
        "$(unit_enabled syswarden-selfupdate.timer)" \
        "$(unit_active syswarden-selfupdate.timer)"
}

install_syswarden() {
    if [[ ! -x "$INSTALL_SCRIPT" ]]; then
        printf 'ERROR: no se encuentra el instalador: %s\n' "$INSTALL_SCRIPT"
        return
    fi
    if ! confirm '¿Desea continuar con la instalación/reinstalación?'; then
        printf 'Instalación cancelada.\n'
        return
    fi
    run_admin "$INSTALL_SCRIPT"
}

update_syswarden() {
    if [[ ! -x /usr/local/bin/syswarden ]]; then
        printf 'No se encontró una instalación de SysWarden.\n'
        return
    fi
    if [[ ! -d /opt/syswarden/.git ]]; then
        printf 'No se encontró una instalación de SysWarden desde Git.\n'
        printf 'El self-update requiere un repositorio Git en:\n'
        printf '  /opt/syswarden\n'
        return
    fi
    if ! confirm '¿Desea actualizar SysWarden?'; then
        printf 'Actualización cancelada.\n'
        return
    fi
    run_admin /usr/local/bin/syswarden --self-update
}

show_status() {
    local result exit_status active_state last_run service_type
    printf '\nEstado de SysWarden\n\n'
    printf 'Versión:              %s\n' "$VERSION"
    if [[ -x /usr/local/bin/syswarden ]]; then
        printf 'Binario:              instalado\n'
    else
        printf 'Binario:              no instalado\n'
    fi
    if [[ -f /etc/syswarden.conf ]]; then
        printf 'Configuración:        instalada\n'
    else
        printf 'Configuración:        no instalada\n'
    fi
    printf 'Mantenimiento diario: %s\n' "$(unit_enabled syswarden.timer)"
    printf 'Self-update:          %s\n' "$(unit_enabled syswarden-selfupdate.timer)"

    result=$(systemctl show syswarden.service -p Result --value 2>/dev/null || true)
    exit_status=$(systemctl show syswarden.service -p ExecMainStatus --value 2>/dev/null || true)
    active_state=$(systemctl show syswarden.service -p ActiveState --value 2>/dev/null || true)
    last_run=$(systemctl show syswarden.service -p InactiveExitTimestamp --value 2>/dev/null || true)
    service_type=$(systemctl show syswarden.service -p Type --value 2>/dev/null || true)

    printf 'Última ejecución:     %s\n' "${last_run:-no disponible}"
    if [[ "$result" == success && "$exit_status" == 0 ]]; then
        printf 'Resultado:            correcto\n'
    elif [[ "$result" == failed || "$active_state" == failed || "$exit_status" != 0 && -n "$exit_status" ]]; then
        printf 'Resultado:            error\n'
    elif [[ "$result" == '' ]]; then
        printf 'Resultado:            no disponible\n'
    else
        printf 'Resultado:            %s\n' "$result"
    fi
    printf 'Servicio:             %s\n' "$(unit_active syswarden.service)"
    if [[ "$service_type" == oneshot && "$active_state" == inactive &&
          "$result" == success && "$exit_status" == 0 ]]; then
        printf '%sNota: el servicio es oneshot; inactivo puede ser normal tras completar.%s\n' "$DIM" "$RESET"
    fi
}

show_schedule() {
    local daily selfupdate
    daily=$(systemctl show syswarden.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)
    selfupdate=$(systemctl show syswarden-selfupdate.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)

    printf '\nProgramación de SysWarden\n\n'
    printf 'Mantenimiento:\n'
    printf '  Estado:             %s (%s)\n' \
        "$(unit_enabled syswarden.timer)" "$(unit_active syswarden.timer)"
    printf '  Próxima ejecución:  %s\n' "${daily:-no disponible}"
    printf '\nSelf-update:\n'
    printf '  Estado:             %s (%s)\n' \
        "$(unit_enabled syswarden-selfupdate.timer)" "$(unit_active syswarden-selfupdate.timer)"
    printf '  Próxima ejecución:  %s\n' "${selfupdate:-no disponible}"
}

show_logs() {
    printf '\nÚltimos 50 registros de SysWarden:\n\n'
    if ! journalctl -u syswarden.service -n 50 --no-pager 2>/dev/null; then
        printf 'No se pudieron consultar los registros de journald.\n'
    fi
    printf '\nLog persistente: /var/log/syswarden.log\n'
    if [[ -f /var/log/syswarden.log ]]; then
        if confirm '¿Desea ver el log en vivo?'; then
            printf 'Presione Ctrl-C para volver al menú.\n'
            tail -f /var/log/syswarden.log || true
        fi
    else
        printf 'El archivo de log todavía no existe.\n'
    fi
}

show_syswarden_help() {
    if [[ -x /usr/local/bin/syswarden ]]; then
        /usr/local/bin/syswarden --help
    else
        printf 'No se encontró el comando syswarden instalado.\n'
    fi
}

show_help() {
    cat <<'HELP'

Ayuda rápida de SysWarden

COMANDO PRINCIPAL
  sudo syswarden

OPCIONES REALES DE SYSWARDEN
  syswarden --help
  syswarden --version
  sudo syswarden --dry-run
  sudo syswarden --dry-run --verbose
  sudo syswarden --self-update

INSTALACIÓN Y ADMINISTRACIÓN
  sudo ./install.sh
  sudo ./install.sh --from-git
  sudo ./install.sh --migrate
  sudo ./install.sh --remove

SYSTEMD Y LOGS
  systemctl list-timers | grep syswarden
  journalctl -u syswarden.service -n 50
  tail -f /var/log/syswarden.log

ARCHIVOS IMPORTANTES
  Configuración: /etc/syswarden.conf
  Log:           /var/log/syswarden.log
  Repositorio:   /opt/syswarden

El mantenimiento, la instalación, la actualización y la desinstalación
requieren sudo cuando no se ejecutan como root. La opción 1 de este menú
instala o reinstala; la opción 2 actualiza SysWarden; las opciones 3, 4 y 5
consultan estado, programación y logs; la opción 6 desinstala sus componentes.
HELP
    printf '\n¿Desea ver la ayuda real de syswarden? [s/N]: '
    if read -r answer && [[ "$answer" =~ ^([sS]|[sS][iI])$ ]]; then
        printf '\n'
        show_syswarden_help
    fi
}

show_acknowledgements() {
    local readme="${SCRIPT_DIR}/README.md" section

    if [[ ! -f "$readme" ]]; then
        printf 'Agradecimientos no disponibles: no se encontró README.md.\n'
        return
    fi

    section=$(awk '
        /^##[[:space:]]+.*Agradecimientos[[:space:]]*$/ { found=1; next }
        found && /^##[[:space:]]/ { exit }
        found { print }
    ' "$readme")

    if [[ -n "$section" ]]; then
        printf '%s\n' "$section"
    else
        printf 'Agradecimientos no disponibles: sección no encontrada.\n'
    fi
}

show_credits() {
    cat <<'CREDITS'

Créditos

SysWarden
Autor: Francisco Aravena (panxos)
Marca: SoporteInfo.net — Soluciones Informáticas Profesionales
Licencia: MIT
Repositorio: https://github.com/panxos/syswarden

CREDITS
    printf 'Agradecimientos\n\n'
    show_acknowledgements
}

while true; do
    show_header
    cat <<'MENU'
  1) Instalar / reinstalar
  2) Actualizar SysWarden
  3) Ver estado
  4) Ver programación
  5) Ver logs
  6) Desinstalar
  7) Ayuda
  8) Créditos
  0) Salir
MENU
    if ! read -r -p $'\nSeleccione una opción [0-8]: ' option; then
        printf '\nHasta luego.\n'
        exit 0
    fi
    case "$option" in
        1) install_syswarden; pause ;;
        2) update_syswarden; pause ;;
        3) show_status; pause ;;
        4) show_schedule; pause ;;
        5) show_logs; pause ;;
        6)
            printf '\nATENCIÓN:\nEsta acción desinstalará los componentes de SysWarden.\n'
            printf 'La configuración y el log pueden conservarse.\n'
            read -r -p '¿Está seguro? Escriba "SI" para continuar: ' answer
            if [[ "$answer" == 'SI' ]]; then
                run_admin "$INSTALL_SCRIPT" --remove
            else
                printf 'Desinstalación cancelada.\n'
            fi
            pause
            ;;
        7) show_help; pause ;;
        8) show_credits; pause ;;
        0) printf 'Hasta luego.\n'; exit 0 ;;
        *) printf 'Opción no válida.\n'; pause ;;
    esac
done
