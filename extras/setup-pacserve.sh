#!/usr/bin/env bash
# setup-pacserve.sh — Compartir caché de pacman entre máquinas via pacserve
# Usa hostnames (no IPs) → funciona en LAN y via Tailscale si el peer está fuera de la red

set -euo pipefail

HOST=$(hostname)
# Usuario real (por si se invoca con sudo)
REAL_USER="${SUDO_USER:-$USER}"

echo "═══════════════════════════════════════"
echo "  Setup pacserve en $HOST"
echo "═══════════════════════════════════════"

# ─── Instalar pacserve (debe correr como usuario, no root) ───────────────────
if ! command -v pacserve &>/dev/null; then
    echo "Instalando pacserve desde AUR como $REAL_USER..."
    case "$HOST" in
        h0ruz|h0rus) sudo -u "$REAL_USER" yay -S --noconfirm pacserve ;;
        s3th)        sudo -u "$REAL_USER" paru -S --noconfirm pacserve ;;
        *)
            # Autodetectar AUR helper
            if command -v yay &>/dev/null; then
                sudo -u "$REAL_USER" yay -S --noconfirm pacserve
            elif command -v paru &>/dev/null; then
                sudo -u "$REAL_USER" paru -S --noconfirm pacserve
            else
                echo "ERROR: ni yay ni paru encontrado"; exit 1
            fi
            ;;
    esac
else
    echo "pacserve ya instalado"
fi

# ─── Config pacserve ─────────────────────────────────────────────────────────
# Puerto default: 15678
# Habilitar firewall hole si ufw o nftables está activo
if command -v ufw &>/dev/null; then
    sudo ufw allow 15678/tcp comment "pacserve" 2>/dev/null || true
fi

# ─── Habilitar servicio ───────────────────────────────────────────────────────
sudo systemctl enable --now pacserve

echo "pacserve activo en puerto 15678"

# ─── Configurar pacman.conf para usar peers ───────────────────────────────────
# Pacserve usa un Include especial en /etc/pacman.conf
# El orden: pacserve local → peers → mirrors de internet

case "$HOST" in
    h0ruz|h0rus)
        PEER_HOST="s3th"
        ;;
    s3th)
        PEER_HOST="h0ruz"
        ;;
    *)
        # Máquina nueva: pedir hostname del peer (NO IP — usar nombre resoluble)
        echo "Host desconocido. Ingresa el hostname del peer pacserve (ej: h0ruz):"
        read -r PEER_HOST
        [[ -z "$PEER_HOST" ]] && { echo "ERROR: hostname vacío"; exit 1; }
        ;;
esac
PEER_ADDR="http://${PEER_HOST}:15678"

# Crear/actualizar /etc/pacman.d/pacserve
sudo tee /etc/pacman.d/pacserve > /dev/null <<EOF
# Peers pacserve — generado por setup-pacserve.sh
# Peer principal (la otra máquina en la red local)
Server = ${PEER_ADDR}/\$repo/\$arch

# Fallback: pedir a pacserve local (caché propia)
Server = http://localhost:15678/\$repo/\$arch
EOF

echo "Peer configurado: $PEER_ADDR (hostname → resuelve LAN + Tailscale)"

# ─── Agregar Include a pacman.conf si no está ─────────────────────────────────
# Se agrega ANTES de Include = /etc/pacman.d/mirrorlist en cada repo
if ! grep -q "pacserve" /etc/pacman.conf; then
    echo ""
    echo "ATENCIÓN: Agregar manualmente a /etc/pacman.conf, antes de cada mirrorlist:"
    echo ""
    echo "  [core]"
    echo "  Include = /etc/pacman.d/pacserve    ← AGREGAR ESTA LÍNEA"
    echo "  Include = /etc/pacman.d/mirrorlist"
    echo ""
    echo "  [extra]"
    echo "  Include = /etc/pacman.d/pacserve    ← AGREGAR ESTA LÍNEA"
    echo "  Include = /etc/pacman.d/mirrorlist"
    echo ""
    echo "Editando automáticamente con sed..."
    sudo sed -i '/^\[core\]/a Include = /etc/pacman.d/pacserve' /etc/pacman.conf
    sudo sed -i '/^\[extra\]/a Include = /etc/pacman.d/pacserve' /etc/pacman.conf
    sudo sed -i '/^\[multilib\]/a Include = /etc/pacman.d/pacserve' /etc/pacman.conf 2>/dev/null || true
    echo "✅ pacman.conf actualizado"
else
    echo "pacman.conf ya tiene pacserve configurado"
fi

# ─── Verificar ────────────────────────────────────────────────────────────────
echo ""
echo "Estado pacserve:"
sudo systemctl status pacserve --no-pager -l | grep -E 'Active|Listen'

echo ""
echo "Test de conectividad al peer:"
curl -sf --max-time 5 "${PEER_ADDR}/core/x86_64/" | head -3 2>/dev/null && \
    echo "✅ Peer accesible" || echo "⚠️  Peer no accesible (¿está el otro equipo encendido?)"

echo ""
echo "═══════════════════════════════════════"
echo "  ✅ pacserve configurado en $HOST"
echo "  Las próximas actualizaciones usarán"
echo "  primero la caché del peer antes de"
echo "  descargar de internet."
echo "═══════════════════════════════════════"
