#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Hetzner Ubuntu 24.04 LTS — Sunucu Kurulum Scripti                       ║
# ║                                                                          ║
# ║  Kullanım:                                                               ║
# ║    1) İnteraktif:  ./setup.sh                                            ║
# ║    2) Argüman:     ./setup.sh "ssh-ed25519 AAA... user@host"             ║
# ║    3) Env var:     SSH_KEY="ssh-ed25519 AAA..." ./setup.sh               ║
# ║    4) Tek satır:   curl -fsSL <url> | SSH_KEY="..." bash                 ║
# ╚══════════════════════════════════════════════════════════════════════════╝

set -e
set -o pipefail

# ─── Renk ve format kodları ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Sayaçlar ────────────────────────────────────────────────────────────────
TOTAL_STEPS=9
CURRENT_STEP=0
START_TIME=$(date +%s)

# ─── Yardımcı fonksiyonlar ───────────────────────────────────────────────────
spinner() {
  local pid=$1
  local message=$2
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  tput civis 2>/dev/null
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}${frames[i]}${NC} ${message}"
    i=$(( (i+1) % 10 ))
    sleep 0.1
  done
  tput cnorm 2>/dev/null
  printf "\r  ${GREEN}✓${NC} ${message}\n"
}

run_with_spinner() {
  local message=$1
  shift
  ("$@" >/dev/null 2>&1) &
  spinner $! "$message"
  wait $!
  return $?
}

step_header() {
  CURRENT_STEP=$((CURRENT_STEP+1))
  local title=$1
  local elapsed=$(( $(date +%s) - START_TIME ))
  echo ""
  echo -e "${BLUE}┌─[ ${WHITE}${BOLD}${CURRENT_STEP}/${TOTAL_STEPS}${NC}${BLUE} ]──[ ${CYAN}${title}${BLUE} ]──[ ${GRAY}${elapsed}s${BLUE} ]${NC}"
  echo -e "${BLUE}│${NC}"
}

step_done() {
  echo -e "${BLUE}└─${GREEN} ✓ tamamlandı${NC}"
}

log()  { echo -e "  ${GREEN}✓${NC} $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
err()  { echo -e "\n  ${RED}✗ HATA:${NC} $1\n"; exit 1; }

# ─── ASCII Banner ────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${MAGENTA}"
cat << "EOF"
   ██████╗ ██╗██████╗ ████████╗██╗██╗  ██╗
   ██╔══██╗██║██╔══██╗╚══██╔══╝██║██║ ██╔╝
   ██████╔╝██║██████╔╝   ██║   ██║█████╔╝
   ██╔══██╗██║██╔══██╗   ██║   ██║██╔═██╗
   ██████╔╝██║██║  ██║   ██║   ██║██║  ██╗
   ╚═════╝ ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═╝
EOF
echo -e "${NC}"
echo -e "   ${DIM}${WHITE}Hetzner • Ubuntu 24.04 • Docker • Portainer • NPM${NC}"
echo -e "   ${GRAY}─────────────────────────────────────────────────${NC}"
echo ""
sleep 1

[ "$EUID" -ne 0 ] && err "Root olarak çalıştır: sudo ./setup.sh"


# ─── SSH KEY KAYNAĞINI BELİRLE ───────────────────────────────────────────────
# Sıralı kontrol: 1) argüman → 2) env var → 3) interaktif sor
if [ -n "$1" ]; then
  SSH_KEY="$1"
  info "SSH key argümandan alındı"
elif [ -n "$SSH_KEY" ]; then
  info "SSH key ortam değişkeninden alındı"
else
  echo ""
  echo -e "  ${YELLOW}SSH public key gerekli.${NC}"
  echo -e "  ${DIM}Yerel makinende: ${CYAN}cat ~/.ssh/id_ed25519.pub${NC}"
  echo ""
  read -p "  Public key'i yapıştır: " SSH_KEY
fi

# Format doğrulaması
if ! echo "$SSH_KEY" | grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|ssh-dss) [A-Za-z0-9+/=]+'; then
  err "Geçersiz SSH public key formatı. Beklenen: 'ssh-ed25519 AAAA... user@host'"
fi


# ─── 1. SSH ANAHTARI ─────────────────────────────────────────────────────────
step_header "SSH Anahtarı"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "$SSH_KEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
KEY_COMMENT=$(echo "$SSH_KEY" | awk '{print $3}')
KEY_TYPE=$(echo "$SSH_KEY" | awk '{print $1}')
log "Tip: ${CYAN}${KEY_TYPE}${NC}"
log "Sahibi: ${CYAN}${KEY_COMMENT:-belirtilmemiş}${NC}"
step_done


# ─── 2. SİSTEM GÜNCELLEMESİ ──────────────────────────────────────────────────
step_header "Sistem Güncellemesi"
run_with_spinner "apt update" apt-get update -y
run_with_spinner "apt upgrade (bu birkaç dakika sürebilir)" \
  bash -c "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
step_done


# ─── 3. TEMEL PAKETLER ───────────────────────────────────────────────────────
step_header "Paketler"
PACKAGES="curl wget git ufw fail2ban ca-certificates gnupg htop tmux neofetch cmatrix nano"
info "Yüklenecekler: ${DIM}${PACKAGES}${NC}"
run_with_spinner "Paketler kuruluyor" apt-get install -y $PACKAGES
step_done


# ─── 4. SSH SERTLEŞTİRME ─────────────────────────────────────────────────────
step_header "SSH Sertleştirme"
sed -i 's/^#Port 22/Port 3131/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 3131/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
log "Port: ${CYAN}22 → 3131${NC}"
log "Şifreyle giriş: ${RED}kapalı${NC}"
log "Root: ${YELLOW}prohibit-password${NC} (sadece SSH key)"
log "MaxAuthTries: ${CYAN}3${NC}"

mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/override.conf << 'EOF'
[Socket]
ListenStream=
ListenStream=0.0.0.0:3131
ListenStream=[::]:3131
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl restart ssh.socket ssh >/dev/null 2>&1
log "ssh.socket override yüklendi, servis yeniden başlatıldı"
step_done


# ─── 5. FAIL2BAN ─────────────────────────────────────────────────────────────
step_header "fail2ban (Brute Force Koruması)"
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime         = 24h
findtime        = 10m
maxretry        = 3
bantime.increment = true
bantime.factor  = 2
bantime.maxtime = 168h

[sshd]
enabled  = true
port     = 3131
mode     = aggressive
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 3
EOF
systemctl enable --now fail2ban >/dev/null 2>&1
log "Kural: ${CYAN}3 deneme${NC} → ${RED}24 saat ban${NC}"
log "Tekrar suçluya: ${YELLOW}katlanarak artar${NC} (max 1 hafta)"
step_done


# ─── 6. UFW ──────────────────────────────────────────────────────────────────
step_header "UFW Güvenlik Duvarı"
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 3131/tcp comment 'SSH' >/dev/null 2>&1
ufw allow 80/tcp   comment 'HTTP' >/dev/null 2>&1
ufw allow 443/tcp  comment 'HTTPS' >/dev/null 2>&1
ufw allow 9443/tcp comment 'Portainer HTTPS' >/dev/null 2>&1
ufw allow 8000/tcp comment 'Portainer Edge Agent' >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

log "Açık portlar:"
echo -e "      ${CYAN}3131${NC}  ${DIM}SSH${NC}"
echo -e "      ${CYAN}  80${NC}  ${DIM}HTTP${NC}"
echo -e "      ${CYAN} 443${NC}  ${DIM}HTTPS${NC}"
echo -e "      ${CYAN}9443${NC}  ${DIM}Portainer${NC}"
echo -e "      ${CYAN}8000${NC}  ${DIM}Portainer Edge${NC}"
step_done


# ─── 7. DOCKER ───────────────────────────────────────────────────────────────
step_header "Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" \
  | tee /etc/apt/sources.list.d/docker.list >/dev/null
log "Docker resmi reposu eklendi"
run_with_spinner "apt update (Docker reposu için)" apt-get update -y
run_with_spinner "Docker CE + plugins kuruluyor" \
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker >/dev/null 2>&1
log "Sürüm: ${CYAN}$(docker --version | awk '{print $3}' | tr -d ',')${NC}"
log "Compose: ${CYAN}$(docker compose version --short)${NC}"
step_done


# ─── 8. PORTAINER ────────────────────────────────────────────────────────────
step_header "Portainer"
docker network create proxy >/dev/null 2>&1 || warn "proxy ağı zaten var"
log "Docker ağı: ${CYAN}proxy${NC}"
docker volume create portainer_data >/dev/null
log "Volume: ${CYAN}portainer_data${NC}"
run_with_spinner "Portainer container başlatılıyor" \
  docker run -d \
    --name portainer \
    --restart=always \
    --network proxy \
    -p 9443:9443 \
    -p 8000:8000 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
step_done


# ─── 9. NGINX PROXY MANAGER ──────────────────────────────────────────────────
step_header "Nginx Proxy Manager"
mkdir -p /root/nginx-proxy-manager
cat > /root/nginx-proxy-manager/docker-compose.yml << 'EOF'
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: always
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt

networks:
  default:
    name: proxy
    external: true
EOF
log "docker-compose.yml: ${CYAN}/root/nginx-proxy-manager/${NC}"
cd /root/nginx-proxy-manager
run_with_spinner "NPM container başlatılıyor" docker compose up -d
step_done


# ─── ÖZET EKRANI ─────────────────────────────────────────────────────────────
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "BILINMIYOR")
TOTAL_TIME=$(( $(date +%s) - START_TIME ))
MINS=$((TOTAL_TIME / 60))
SECS=$((TOTAL_TIME % 60))
HOSTNAME_VAL=$(hostname)
KERNEL=$(uname -r)
RAM=$(free -h | awk '/^Mem:/ {print $3"/"$2}')
DISK=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')

echo ""
echo -e "${GREEN}"
cat << "EOF"
   ╔══════════════════════════════════════════════════════════╗
   ║              KURULUM BAŞARIYLA TAMAMLANDI                ║
   ╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "   ${BOLD}${WHITE}Sistem${NC}"
echo -e "   ${GRAY}────────────────────────────────────────────${NC}"
echo -e "   ${DIM}Hostname  ${NC}: ${CYAN}${HOSTNAME_VAL}${NC}"
echo -e "   ${DIM}IP Adresi ${NC}: ${CYAN}${SERVER_IP}${NC}"
echo -e "   ${DIM}Kernel    ${NC}: ${CYAN}${KERNEL}${NC}"
echo -e "   ${DIM}RAM       ${NC}: ${CYAN}${RAM}${NC}"
echo -e "   ${DIM}Disk      ${NC}: ${CYAN}${DISK}${NC}"
echo -e "   ${DIM}Süre      ${NC}: ${CYAN}${MINS}d ${SECS}s${NC}"
echo ""

echo -e "   ${BOLD}${WHITE}Servisler${NC}"
echo -e "   ${GRAY}────────────────────────────────────────────${NC}"
echo -e "   ${MAGENTA}❯${NC} SSH        ${DIM}→${NC} ${YELLOW}ssh -p 3131 root@${SERVER_IP}${NC}"
echo -e "   ${MAGENTA}❯${NC} Portainer  ${DIM}→${NC} ${YELLOW}https://${SERVER_IP}:9443${NC}"
echo -e "   ${MAGENTA}❯${NC} NPM Admin  ${DIM}→${NC} ${YELLOW}http://${SERVER_IP}:81${NC}"
echo ""

echo -e "   ${BOLD}${WHITE}Sonraki Adımlar${NC}"
echo -e "   ${GRAY}────────────────────────────────────────────${NC}"
echo -e "   ${BLUE}1.${NC} Yerel makinende: ${DIM}ssh-keygen -R ${SERVER_IP}${NC}"
echo -e "   ${BLUE}2.${NC} Test: ${DIM}ssh -p 3131 root@${SERVER_IP}${NC}"
echo -e "   ${BLUE}3.${NC} Portainer'da admin hesabı oluştur"
echo -e "   ${BLUE}4.${NC} NPM'de DNS bağlı domain için proxy host ekle"
echo ""

echo -e "   ${GRAY}─────────────────────────────────────────────${NC}"
read -p "   $(echo -e ${YELLOW})Sunucuyu yeniden başlatayım mı?$(echo -e ${NC}) (y/n): " CONFIRM
echo ""

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo -e "   ${YELLOW}!${NC} 5 saniye içinde reboot..."
  for i in 5 4 3 2 1; do
    echo -ne "   ${RED}${i}${NC}... "
    sleep 1
  done
  echo ""
  reboot
else
  warn "Reboot atlandı. Manuel: ${CYAN}sudo reboot${NC}"
  echo ""
fi
