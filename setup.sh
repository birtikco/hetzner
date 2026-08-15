#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Hetzner Ubuntu 24.04 / 26.04 LTS — Sunucu Kurulum Scripti               ║
# ║                                                                          ║
# ║  Kullanım:                                                               ║
# ║    1) İnteraktif:  ./setup.sh                                            ║
# ║    2) Argüman:     ./setup.sh "ssh-ed25519 ROOT..." "ssh-ed25519 DEPLOY..." ║
# ║    3) Env var:     SSH_KEY="..." DEPLOY_KEY="..." ./setup.sh             ║
# ║    4) Tek satır:   curl -fsSL <url> | SSH_KEY="..." bash                 ║
# ║                                                                          ║
# ║  Tekrar çalıştırılabilir: eksiği kurar, doğru olana dokunmaz. Elle       ║
# ║  değiştirilmiş dosyaya yazmadan önce sorar; --yes ile sormadan uygular.   ║
# ║                                                                          ║
# ║  DEPLOY_KEY opsiyonel — verilmezse SSH_KEY (root key) fallback kullanılır.║
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
TOTAL_STEPS=10
CURRENT_STEP=0
START_TIME=$(date +%s)
CHANGES=0
SKIPPED=0
ASSUME_YES=0
PANELS_VERIFIED=1

# ─── Yardımcı fonksiyonlar ───────────────────────────────────────────────────
spinner() {
  local pid=$1
  local message=$2
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  tput civis 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}${frames[i]}${NC} %s" "$message"
    i=$(( (i+1) % 10 ))
    sleep 0.1
  done
  tput cnorm 2>/dev/null || true
}

run_with_spinner() {
  local message=$1
  shift
  ("$@" >/dev/null 2>&1) &
  local pid=$!
  spinner "$pid" "$message"
  if wait "$pid"; then
    printf "\r  ${GREEN}✓${NC} %s\n" "$message"
  else
    printf "\r  ${RED}✗${NC} %s\n" "$message"
    return 1
  fi
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

changed() { CHANGES=$((CHANGES+1));  log "$1"; }
skipped() { SKIPPED=$((SKIPPED+1)); warn "$1"; }

# Kesinti yaratan işlem öncesi sorar; terminal yoksa hayır döner.
confirm() {
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  [ -t 1 ] || return 1
  ( : < /dev/tty ) 2>/dev/null || return 1
  local answer
  read -r -p "$(echo -e "  ${YELLOW}?${NC} $1 (y/N): ")" answer < /dev/tty
  [[ "$answer" =~ ^[Yy]$ ]]
}

# İstenen içerik stdin'den. Dönüş: 0 = dosya istenen halde, 1 = korundu.
write_managed() {
  local target=$1 mode=$2 label=$3
  local tmp rc=0
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  cat > "$tmp"
  if [ ! -f "$target" ]; then
    install -m "$mode" "$tmp" "$target"
    changed "${label} oluşturuldu"
  elif cmp -s "$tmp" "$target"; then
    chmod "$mode" "$target"
    info "${label} zaten istenen halde"
  elif confirm "${label} elle değiştirilmiş — üzerine yazılsın mı?"; then
    install -m "$mode" "$tmp" "$target"
    changed "${label} güncellendi"
  else
    skipped "${label} korundu ${DIM}(--yes ile üzerine yazılır)${NC}"
    rc=1
  fi
  return $rc
}

# ─── ASCII Banner ────────────────────────────────────────────────────────────
clear 2>/dev/null || true
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

# ─── ARGÜMANLAR ──────────────────────────────────────────────────────────────
# --yes süzülür, kalanı $1/$2 (SSH_KEY / DEPLOY_KEY) olarak geri konur.
ARGS=()
for a in "$@"; do
  case "$a" in
    --yes|-y) ASSUME_YES=1 ;;
    *)        ARGS+=("$a") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
[ "$ASSUME_YES" -eq 1 ] && info "${CYAN}--yes${NC}: onay istenmeyecek"


# ─── SSH KEY KAYNAĞINI BELİRLE ───────────────────────────────────────────────
# Sıralı kontrol: 1) argüman → 2) env var → 3) interaktif sor
if [ -n "$1" ]; then
  SSH_KEY="$1"
  info "SSH key argümandan alındı"
elif [ -n "$SSH_KEY" ]; then
  info "SSH key ortam değişkeninden alındı"
elif [ -t 0 ]; then
  echo ""
  echo -e "  ${YELLOW}SSH public key gerekli.${NC}"
  echo -e "  ${DIM}Yerel makinende: ${CYAN}cat ~/.ssh/id_ed25519.pub${NC}"
  echo ""
  read -r -p "  Public key'i yapıştır: " SSH_KEY
else
  err "SSH key verilmedi ve terminal etkileşimli değil.\n     Örnek: ${CYAN}curl -fsSL <url> | SSH_KEY=\"ssh-ed25519 AAAA...\" bash${NC}"
fi

# Baş/son boşluk ve satır sonu temizlenir.
SSH_KEY=$(printf '%s' "$SSH_KEY" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

# Format doğrulaması
if ! echo "$SSH_KEY" | grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|ssh-dss) [A-Za-z0-9+/=]+'; then
  err "Geçersiz SSH public key formatı. Beklenen: 'ssh-ed25519 AAAA... user@host'"
fi


# ─── DEPLOY KEY KAYNAĞINI BELİRLE ────────────────────────────────────────────
# Sıralı kontrol: 1) 2. argüman → 2) DEPLOY_KEY env var → 3) SSH_KEY fallback
if [ -n "$2" ]; then
  DEPLOY_KEY="$2"
  info "Deploy key 2. argümandan alındı"
elif [ -n "$DEPLOY_KEY" ]; then
  info "Deploy key ortam değişkeninden alındı"
else
  DEPLOY_KEY="$SSH_KEY"
  info "Deploy key tanımlanmadı → root SSH key fallback kullanılacak"
fi

DEPLOY_KEY=$(printf '%s' "$DEPLOY_KEY" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

if ! echo "$DEPLOY_KEY" | grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|ssh-dss) [A-Za-z0-9+/=]+'; then
  err "Geçersiz DEPLOY_KEY formatı. Beklenen: 'ssh-ed25519 AAAA... user@host'"
fi


# ─── 1. SSH ANAHTARI ─────────────────────────────────────────────────────────
step_header "SSH Anahtarı"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
ROOT_AUTH_KEYS=/root/.ssh/authorized_keys
touch "$ROOT_AUTH_KEYS"
chmod 600 "$ROOT_AUTH_KEYS"

# -x zorunlu: -F tek başına alt dize eşler.
if grep -qxF "$SSH_KEY" "$ROOT_AUTH_KEYS"; then
  info "Root key zaten authorized_keys'te"
else
  echo "$SSH_KEY" >> "$ROOT_AUTH_KEYS"
  changed "Root key eklendi"
fi

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
PKG_REQUIRED="curl wget git ufw fail2ban ca-certificates gnupg"
PKG_OPTIONAL="htop tmux nano cmatrix neofetch"

info "Zorunlu: ${DIM}${PKG_REQUIRED}${NC}"
run_with_spinner "Zorunlu paketler kuruluyor" apt-get install -y $PKG_REQUIRED

# apt-get tek eksik pakette listenin tamamını reddeder; önce süzülür.
PKG_FOUND=""
PKG_MISSING=""
for p in $PKG_OPTIONAL; do
  if apt-cache show "$p" >/dev/null 2>&1; then
    PKG_FOUND="$PKG_FOUND $p"
  else
    PKG_MISSING="$PKG_MISSING $p"
  fi
done

if [ -n "$PKG_FOUND" ]; then
  info "Opsiyonel:${DIM}${PKG_FOUND}${NC}"
  run_with_spinner "Opsiyonel paketler kuruluyor" apt-get install -y $PKG_FOUND
fi
if [ -n "$PKG_MISSING" ]; then
  warn "Bu dağıtımda yok, atlandı:${YELLOW}${PKG_MISSING}${NC}"
fi
step_done


# ─── 4. DEPLOY USER (CI/CD) ──────────────────────────────────────────────────
step_header "Deploy User (CI/CD)"

DEPLOY_USERNAME="deploy-user"
DEPLOY_HOME="/home/${DEPLOY_USERNAME}"

if id "$DEPLOY_USERNAME" &>/dev/null; then
  info "Kullanıcı ${CYAN}${DEPLOY_USERNAME}${NC} zaten var"
else
  useradd --create-home --shell /bin/bash "$DEPLOY_USERNAME"
  changed "Kullanıcı oluşturuldu: ${CYAN}${DEPLOY_USERNAME}${NC}"
fi

passwd -l "$DEPLOY_USERNAME" >/dev/null 2>&1
log "Şifre girişi kilitlendi (sadece SSH key)"

install -d -m 700 -o "$DEPLOY_USERNAME" -g "$DEPLOY_USERNAME" "${DEPLOY_HOME}/.ssh"
AUTH_KEYS="${DEPLOY_HOME}/.ssh/authorized_keys"
touch "$AUTH_KEYS"
if ! grep -qxF "$DEPLOY_KEY" "$AUTH_KEYS" 2>/dev/null; then
  echo "$DEPLOY_KEY" >> "$AUTH_KEYS"
  changed "Deploy key eklendi: ${CYAN}$(echo "$DEPLOY_KEY" | awk '{print $3}')${NC}"
else
  info "Deploy key zaten authorized_keys'te"
fi
chown "$DEPLOY_USERNAME:$DEPLOY_USERNAME" "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

SUDOERS_FILE="/etc/sudoers.d/${DEPLOY_USERNAME}"
cat > "$SUDOERS_FILE" << EOF
# CI/CD deploy-user — minimum yetki.
# Docker erişimi grup üyeliğinden gelir; sudo yalnızca debug için.
Cmnd_Alias DEPLOY_LOG = /usr/bin/journalctl, /usr/bin/journalctl *
Cmnd_Alias DEPLOY_FW  = /usr/sbin/ufw status, /usr/sbin/ufw status verbose

${DEPLOY_USERNAME} ALL=(ALL) NOPASSWD: DEPLOY_LOG, DEPLOY_FW
EOF
chmod 0440 "$SUDOERS_FILE"

if ! SUDOERS_OUT=$(visudo -c -f "$SUDOERS_FILE" 2>&1); then
  warn "visudo doğrulaması başarısız:"
  echo "$SUDOERS_OUT" | sed 's/^/      /'
  rm -f "$SUDOERS_FILE"
  err "Sudoers dosyası geçersiz, geri alındı"
fi
log "Sudoers: ${CYAN}/etc/sudoers.d/${DEPLOY_USERNAME}${NC} (minimum)"
step_done


# ─── 5. SSH SERTLEŞTİRME ─────────────────────────────────────────────────────
step_header "SSH Sertleştirme"
SSHD_BIN=$(command -v sshd || echo /usr/sbin/sshd)
SSHD_DROPIN=/etc/ssh/sshd_config.d/99-hardening.conf
SSHD_KEYS='Port|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|MaxAuthTries|AllowUsers'
SSHD_CHECK='port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|maxauthtries|allowusers'

# sshd ilk gördüğü değeri kullanır: çakışan direktifler önce yorumlanır.
mkdir -p /etc/ssh/sshd_config.d
grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config \
  || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
shopt -s nullglob
# I bayrağı ve '=' şart: anahtar kelimeler harf duyarsız, 'Key=value' de geçerli.
sed -i -E "s/^[[:space:]]*(${SSHD_KEYS})([[:space:]]|=)/#&/I" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf
shopt -u nullglob

cat > "$SSHD_DROPIN" << CONF
Port 3131
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
AllowUsers root ${DEPLOY_USERNAME}
CONF
chmod 600 "$SSHD_DROPIN"

"$SSHD_BIN" -t || err "sshd yapılandırması geçersiz, SSH servisine dokunulmadı"

# AllowUsers satır satır basılır; permitrootlogin OpenSSH sürümüne göre iki adla raporlanır.
SSHD_WANT=$(printf '%s\n' \
  "allowusers root" \
  "allowusers ${DEPLOY_USERNAME}" \
  "kbdinteractiveauthentication no" \
  "maxauthtries 3" \
  "passwordauthentication no" \
  "permitrootlogin prohibit-password" \
  "port 3131" | LC_ALL=C sort)
SSHD_GOT=$("$SSHD_BIN" -T | grep -E "^(${SSHD_CHECK}) " \
  | sed 's/^permitrootlogin without-password$/permitrootlogin prohibit-password/' \
  | LC_ALL=C sort || true)

if [ "$SSHD_GOT" != "$SSHD_WANT" ]; then
  warn "Etkin yapılandırma beklenenden farklı:"
  echo "$SSHD_GOT" | sed 's/^/      /'
  err "SSH sertleştirmesi geçerli değil, /etc/ssh/sshd_config.d/ altını kontrol et"
fi

log "Drop-in: ${CYAN}${SSHD_DROPIN}${NC}"
log "Port: ${CYAN}22 → 3131${NC}"
log "Şifreyle giriş: ${RED}kapalı${NC}"
log "Root: ${YELLOW}prohibit-password${NC} (sadece SSH key)"
log "MaxAuthTries: ${CYAN}3${NC}"
log "AllowUsers: ${CYAN}root ${DEPLOY_USERNAME}${NC}"
log "Doğrulandı: ${DIM}sshd -T${NC}"

mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/override.conf << 'EOF'
[Socket]
ListenStream=
ListenStream=0.0.0.0:3131
ListenStream=[::]:3131
EOF

systemctl daemon-reload >/dev/null 2>&1
# Susturulursa aşağıdaki kilitlenme uyarısına hiç ulaşılmaz.
if ! SSH_RESTART_OUT=$(systemctl restart ssh.socket ssh 2>&1); then
  echo "$SSH_RESTART_OUT" | sed 's/^/      /'
  err "SSH servisi yeniden başlatılamadı — açık oturumunu KAPATMA"
fi
sleep 1
[[ $(ss -lntH) == *":3131 "* ]] \
  || err "SSH 3131'de dinlemiyor — açık oturumunu KAPATMA, 'systemctl status ssh.socket' ile bak"
log "ssh.socket override yüklendi, ${CYAN}0.0.0.0:3131${NC} dinleniyor"
step_done


# ─── 6. FAIL2BAN ─────────────────────────────────────────────────────────────
step_header "fail2ban (Brute Force Koruması)"
F2B_MANAGED=1
write_managed /etc/fail2ban/jail.local 644 "jail.local" << 'EOF' || F2B_MANAGED=0
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
if ! F2B_OUT=$(systemctl enable --now fail2ban 2>&1); then
  echo "$F2B_OUT" | sed 's/^/      /'
  err "fail2ban başlatılamadı"
fi
systemctl reload fail2ban >/dev/null 2>&1 || true

# Kural metni yalnızca dosya gerçekten yazıldıysa doğrudur.
if [ "$F2B_MANAGED" -eq 1 ]; then
  log "Kural: ${CYAN}3 deneme${NC} → ${RED}24 saat ban${NC}"
  log "Tekrar suçluya: ${YELLOW}katlanarak artar${NC} (max 1 hafta)"
else
  warn "jail.local korundu — ${RED}yukarıdaki kural bu sunucuda geçerli değil${NC}"
  warn "Geçerli politika için: ${CYAN}cat /etc/fail2ban/jail.local${NC}"
fi
step_done


# ─── 7. UFW ──────────────────────────────────────────────────────────────────
step_header "UFW Güvenlik Duvarı"
command -v ufw >/dev/null || err "ufw kurulu değil — 3. adımdaki paket kurulumu başarısız olmuş"

# reset yok: 'ufw allow' zaten idempotent, reset elle eklenen kuralları silerdi.
run_with_spinner "Varsayılan politika" \
  bash -c "ufw default deny incoming && ufw default allow outgoing"
run_with_spinner "SSH / HTTP / HTTPS izinleri" \
  bash -c "ufw allow 3131/tcp comment 'SSH' \
        && ufw allow 80/tcp   comment 'HTTP' \
        && ufw allow 443/tcp  comment 'HTTPS'"
run_with_spinner "Güvenlik duvarı etkinleştiriliyor" ufw --force enable

log "Etkin kurallar:"
ufw status verbose | sed 's/^/      /'
warn "UFW yalnızca host'a gelen trafiği süzer; Docker'ın ${CYAN}0.0.0.0${NC}'a yayınladığı"
warn "portlar bu listeye ${RED}takılmaz${NC} — yayınlarken ${CYAN}-p 127.0.0.1:PORT:PORT${NC} kullan"
step_done


# ─── 8. DOCKER ───────────────────────────────────────────────────────────────
step_header "Docker"
install -m 0755 -d /etc/apt/keyrings
# --batch --yes şart: gpg hedef dosya varsa 'File exists' deyip çıkar.
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg \
  || err "Docker GPG anahtarı alınamadı"
chmod a+r /etc/apt/keyrings/docker.gpg
DOCKER_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
DOCKER_ARCH=$(dpkg --print-architecture)
DOCKER_REPO="https://download.docker.com/linux/ubuntu"

# Depo yoksa dur: yanlış sürüme sessizce paket kurmaktansa.
curl -fsI --max-time 15 "${DOCKER_REPO}/dists/${DOCKER_CODENAME}/Release" >/dev/null 2>&1 \
  || err "Docker'ın ${DOCKER_CODENAME} deposu yok — bu Ubuntu sürümü desteklenmiyor"

echo "deb [arch=${DOCKER_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_REPO} ${DOCKER_CODENAME} stable" \
  | tee /etc/apt/sources.list.d/docker.list >/dev/null
log "Docker reposu: ${CYAN}${DOCKER_CODENAME}${NC} / ${CYAN}${DOCKER_ARCH}${NC}"
run_with_spinner "apt update (Docker reposu için)" apt-get update -y
run_with_spinner "Docker CE + plugins kuruluyor" \
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker >/dev/null 2>&1
log "Sürüm: ${CYAN}$(docker --version | awk '{print $3}' | tr -d ',')${NC}"
log "Compose: ${CYAN}$(docker compose version --short)${NC}"

usermod -aG docker "$DEPLOY_USERNAME"
log "${CYAN}${DEPLOY_USERNAME}${NC} docker grubuna eklendi"
step_done


# ─── 9. PORTAINER ────────────────────────────────────────────────────────────
step_header "Portainer"
if ! NET_OUT=$(docker network create proxy 2>&1); then
  if echo "$NET_OUT" | grep -q 'already exists'; then
    info "proxy ağı zaten var"
  else
    echo "$NET_OUT" | sed 's/^/      /'
    err "proxy ağı oluşturulamadı"
  fi
fi
log "Docker ağı: ${CYAN}proxy${NC}"
docker volume create portainer_data >/dev/null
log "Volume: ${CYAN}portainer_data${NC}"

PORTAINER_DIR=/root/portainer
mkdir -p "$PORTAINER_DIR"
PORTAINER_MANAGED=1
write_managed "$PORTAINER_DIR/docker-compose.yml" 644 "Portainer compose dosyası" << 'EOF' || PORTAINER_MANAGED=0
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "127.0.0.1:9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

volumes:
  portainer_data:
    external: true

networks:
  default:
    name: proxy
    external: true
EOF

# 'docker run' ile kurulmuş konteyneri compose devralamaz; taşımak kısa kesinti demek.
PORTAINER_SKIP=0
PORTAINER_EXISTS=$(docker ps -aq --filter "name=^portainer$")
PORTAINER_COMPOSE=$(docker ps -aq --filter "name=^portainer$" --filter "label=com.docker.compose.project")
if [ -n "$PORTAINER_EXISTS" ] && [ -z "$PORTAINER_COMPOSE" ]; then
  if confirm "Portainer 'docker run' ile kurulmuş — compose'a taşınsın mı? ${DIM}(birkaç saniye kesinti)${NC}"; then
    docker rm -f portainer >/dev/null
    changed "Eski Portainer konteyneri kaldırıldı"
  else
    PORTAINER_SKIP=1
    skipped "Portainer compose'a taşınmadı ${DIM}(--yes ile taşınır)${NC}"
  fi
fi

if [ "$PORTAINER_SKIP" -eq 0 ]; then
  run_with_spinner "Portainer başlatılıyor" \
    docker compose -f "$PORTAINER_DIR/docker-compose.yml" up -d
fi

# İddia yalnız compose dosyası bizimken ve konteyner ondan üretildiyse doğrudur.
if [ "$PORTAINER_MANAGED" -eq 1 ] && [ "$PORTAINER_SKIP" -eq 0 ]; then
  info "Panel: ${CYAN}127.0.0.1:9443${NC} — dışarıya kapalı, SSH tüneliyle girilir"
else
  PANELS_VERIFIED=0
  warn "Portainer bağlaması ${RED}doğrulanmadı${NC} — panel internete açık olabilir:"
  warn "${CYAN}docker ps --format '{{.Names}} {{.Ports}}'${NC} ile kontrol et"
fi
step_done


# ─── 10. NGINX PROXY MANAGER ─────────────────────────────────────────────────
step_header "Nginx Proxy Manager"
NPM_DIR=/root/nginx-proxy-manager
mkdir -p "$NPM_DIR"
NPM_MANAGED=1
write_managed "$NPM_DIR/docker-compose.yml" 644 "NPM compose dosyası" << 'EOF' || NPM_MANAGED=0
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "127.0.0.1:81:81"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt

networks:
  default:
    name: proxy
    external: true
EOF
log "docker-compose.yml: ${CYAN}${NPM_DIR}/${NC}"
run_with_spinner "NPM başlatılıyor" docker compose -f "$NPM_DIR/docker-compose.yml" up -d

if [ "$NPM_MANAGED" -eq 1 ]; then
  info "Panel: ${CYAN}127.0.0.1:81${NC} — dışarıya kapalı, SSH tüneliyle girilir"
else
  PANELS_VERIFIED=0
  warn "NPM bağlaması ${RED}doğrulanmadı${NC} — eski dosya 81'i internete açıyor olabilir,"
  warn "üstelik varsayılan şifre hâlâ geçerliyse panel savunmasız. Kontrol et:"
  warn "${CYAN}docker ps --format '{{.Names}} {{.Ports}}'${NC}"
fi
step_done


# ─── ÖZET EKRANI ─────────────────────────────────────────────────────────────
# IPv4 açıkça istenir: GitHub Actions runner'ları IPv6 ile bağlanamaz.
SERVER_IP=$(curl -4 -s --max-time 10 ifconfig.me 2>/dev/null || true)
if [ -z "$SERVER_IP" ]; then
  SERVER_IP=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
fi
SERVER_IP6=$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
if [ -z "$SERVER_IP" ]; then
  SERVER_IP="BILINMIYOR"
fi
TOTAL_TIME=$(( $(date +%s) - START_TIME ))
MINS=$((TOTAL_TIME / 60))
SECS=$((TOTAL_TIME % 60))
HOSTNAME_VAL=$(hostname)
KERNEL=$(uname -r)
RAM=$(free -h | awk '/^Mem:/ {print $3"/"$2}')
DISK=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')

echo ""
if [ "$SKIPPED" -gt 0 ]; then
  echo -e "${YELLOW}"
  cat << "EOF"
   ╔══════════════════════════════════════════════════════════╗
   ║               SAPMALAR UYGULANMADI                       ║
   ╚══════════════════════════════════════════════════════════╝
EOF
elif [ "$CHANGES" -eq 0 ]; then
  echo -e "${CYAN}"
  cat << "EOF"
   ╔══════════════════════════════════════════════════════════╗
   ║             SUNUCU ZATEN İSTENEN DURUMDA                 ║
   ╚══════════════════════════════════════════════════════════╝
EOF
else
  echo -e "${GREEN}"
  cat << "EOF"
   ╔══════════════════════════════════════════════════════════╗
   ║              KURULUM BAŞARIYLA TAMAMLANDI                ║
   ╚══════════════════════════════════════════════════════════╝
EOF
fi
echo -e "${NC}"

echo -e "   ${BOLD}${WHITE}Sistem${NC}"
echo -e "   ${GRAY}────────────────────────────────────────────${NC}"
echo -e "   ${DIM}Hostname  ${NC}: ${CYAN}${HOSTNAME_VAL}${NC}"
echo -e "   ${DIM}IPv4      ${NC}: ${CYAN}${SERVER_IP}${NC}"
if [ -n "$SERVER_IP6" ]; then
  echo -e "   ${DIM}IPv6      ${NC}: ${CYAN}${SERVER_IP6}${NC}"
fi
echo -e "   ${DIM}Kernel    ${NC}: ${CYAN}${KERNEL}${NC}"
echo -e "   ${DIM}RAM       ${NC}: ${CYAN}${RAM}${NC}"
echo -e "   ${DIM}Disk      ${NC}: ${CYAN}${DISK}${NC}"
echo -e "   ${DIM}Süre      ${NC}: ${CYAN}${MINS}d ${SECS}s${NC}"
echo -e "   ${DIM}Değişiklik${NC}: ${CYAN}${CHANGES}${NC}${DIM} uygulandı, ${NC}${YELLOW}${SKIPPED}${NC}${DIM} atlandı${NC}"
echo ""

echo -e "   ${BOLD}${WHITE}Servisler${NC}"
echo -e "   ${GRAY}────────────────────────────────────────────${NC}"
echo -e "   ${MAGENTA}❯${NC} SSH (root)   ${DIM}→${NC} ${YELLOW}ssh -p 3131 root@${SERVER_IP}${NC}"
echo -e "   ${MAGENTA}❯${NC} SSH (deploy) ${DIM}→${NC} ${YELLOW}ssh -p 3131 ${DEPLOY_USERNAME}@${SERVER_IP}${NC}"
echo ""

if [ "$PANELS_VERIFIED" -eq 1 ]; then
  echo -e "   ${BOLD}${WHITE}Yönetim Panelleri${NC} ${DIM}— internete kapalı, SSH tüneliyle girilir${NC}"
else
  echo -e "   ${BOLD}${WHITE}Yönetim Panelleri${NC} ${YELLOW}— bağlama DOĞRULANMADI, portları kontrol et${NC}"
fi
echo -e "   ${GRAY}────────────────────────────────────────────${NC}"
echo -e "   ${MAGENTA}❯${NC} Portainer"
echo -e "      ${YELLOW}ssh -p 3131 -L 9443:127.0.0.1:9443 root@${SERVER_IP}${NC}"
echo -e "      ${GRAY}sonra tarayıcıda: https://localhost:9443${NC}"
echo -e "   ${MAGENTA}❯${NC} NPM Admin ${DIM}(varsayılan: admin@example.com / changeme)${NC}"
echo -e "      ${YELLOW}ssh -p 3131 -L 8181:127.0.0.1:81 root@${SERVER_IP}${NC}"
echo -e "      ${GRAY}sonra tarayıcıda: http://localhost:8181${NC}"
echo ""

echo -e "   ${BOLD}${WHITE}Sonraki Adımlar${NC}"
echo -e "   ${GRAY}────────────────────────────────────────────${NC}"
echo -e "   ${BLUE}1.${NC} Yerel makinende: ${DIM}ssh-keygen -R ${SERVER_IP}${NC}"
echo -e "   ${BLUE}2.${NC} Test: ${DIM}ssh -p 3131 root@${SERVER_IP}${NC}"
echo -e "   ${BLUE}3.${NC} Tünelle Portainer'a gir, admin hesabı oluştur"
echo -e "   ${BLUE}4.${NC} Tünelle NPM'e gir, ${YELLOW}varsayılan şifreyi değiştir${NC}"
echo -e "   ${BLUE}5.${NC} NPM'de panel proxy host'larını aç:"
echo -e "      ${GRAY}container.<alan> → portainer:9443 ${DIM}(scheme: HTTPS)${NC}"
echo -e "      ${GRAY}proksi.<alan>    → nginx-proxy-manager:81${NC}"
echo -e "   ${BLUE}6.${NC} Paneller HTTPS'ten açılınca loopback bağlamalarını kaldır:"
echo -e "      ${GRAY}${NPM_DIR}/docker-compose.yml → ${DIM}127.0.0.1:81:81${NC}${GRAY} satırını sil${NC}"
echo -e "      ${GRAY}${PORTAINER_DIR}/docker-compose.yml → ${DIM}127.0.0.1:9443:9443${NC}${GRAY} satırını sil${NC}"
echo -e "      ${GRAY}sonra ${DIM}docker compose -f <dosya> up -d${NC}"
echo -e "      ${GRAY}bu script tekrar çalışırsa üzerine yazmadan önce sorar${NC}"
echo -e "   ${BLUE}7.${NC} GitHub Actions secrets:"
echo -e "      ${GRAY}DEPLOY_SSH_KEY → private key (id_ed25519_deploy)${NC}"
echo -e "      ${GRAY}SERVER_HOST    → ${SERVER_IP}${NC}"
echo -e "      ${GRAY}SERVER_USER    → ${DEPLOY_USERNAME}${NC}"
echo -e "      ${GRAY}SERVER_PORT    → 3131${NC}"
if [ "$SERVER_IP" = "BILINMIYOR" ]; then
  warn "IPv4 tespit edilemedi. ${RED}SERVER_HOST'a IPv6 yazma${NC} — GitHub Actions"
  warn "runner'ları IPv6 ile bağlanamaz, deploy adımı zaman aşımına uğrar."
fi
if [ "$SKIPPED" -gt 0 ]; then
  echo ""
  warn "${YELLOW}${SKIPPED}${NC} adım atlandı — onay verilmedi ya da terminal etkileşimli değildi."
  warn "Uygulamak için: ${CYAN}--yes${NC}"
fi
echo ""

echo -e "   ${GRAY}─────────────────────────────────────────────${NC}"
if [ -t 0 ]; then
  read -r -p "   $(echo -e "${YELLOW}")Sunucuyu yeniden başlatayım mı?$(echo -e "${NC}") (y/n): " CONFIRM
  echo ""
else
  CONFIRM=n
  info "Etkileşimsiz çalıştırma — reboot sorulmadı"
fi

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

# Çıkış kodu: 0 = istenen durumda, 2 = sapma uygulanmadı, 1 = hata (err).
if [ "$SKIPPED" -gt 0 ]; then
  exit 2
fi
exit 0
