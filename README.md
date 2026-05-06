# Hetzner Server Setup

Ubuntu 24.04 üzerinde çalışan Hetzner Cloud sunucuları için otomatik kurulum ve sertleştirme scripti.

Tek komutla **Docker + Portainer + Nginx Proxy Manager** kuruyor, **fail2ban + UFW + SSH sertleştirme** ile güvenlik temelini atıyor.

---

## 🚀 Hızlı Başlangıç

### Lokalde

- SSH Public Key al:

```bash
cat ~/.ssh/id_ed25519.pub
```

### Mevcut sunucuda (build/rebuild sonrası)

- Tek satırda (Bash 4+ gerektirir):

```bash
curl -fsSL https://raw.githubusercontent.com/birtikco/hetzner/refs/heads/main/setup.sh | \
  SSH_KEY="ssh-ed25519 AAAA... user@host" DEPLOY_KEY="ssh-ed25519 AAAA... user@host" bash
```

- Veya manuel:

```bash
wget https://raw.githubusercontent.com/birtikco/hetzner/refs/heads/main/setup.sh
chmod +x setup.sh
./setup.sh "ssh-ed25519 AAAA... user@host" "ssh-ed25519 AAAA... user@host"
```

`DEPLOY_KEY` opsiyoneldir — verilmezse root key'i deploy-user için de kullanılır.

---

## 📦 Ne Kuruyor?

### Sistem paketleri
`curl` `wget` `git` `ufw` `fail2ban` `ca-certificates` `gnupg` `htop` `tmux` `neofetch` `cmatrix` `nano`

### Docker yığını
- **Docker CE** + Compose plugin + Buildx plugin
- **Portainer CE** — Docker yönetim arayüzü (HTTPS 9443)
- **Nginx Proxy Manager** — reverse proxy + Let's Encrypt SSL otomasyonu (80, 81, 443)
- **`proxy`** adlı ortak Docker ağı — tüm container'ların buluştuğu yer

---

## 🔐 Güvenlik Yapılandırması

| Ayar | Değer |
|------|-------|
| SSH Port | `3131` (varsayılan 22 yerine) |
| Şifreyle SSH | Devre dışı |
| Root login | `prohibit-password` (sadece SSH key) |
| MaxAuthTries | `3` |
| AllowUsers | `root deploy-user` (whitelist) |
| Deploy User | `deploy-user` — docker grubu, NOPASSWD sudo: `journalctl`, `ufw status` |
| fail2ban | 3 başarısız deneme → 24h ban, katlanarak artar (max 1 hafta) |
| UFW | Default deny, sadece açıkça izin verilen portlar |

### UFW açık portlar
```
3131  SSH
80    HTTP (NPM)
443   HTTPS (NPM)
9443  Portainer
8000  Portainer Edge Agent
```

---

## 🎯 Kullanım Yöntemleri

`setup.sh` SSH public key'i 3 farklı şekilde kabul eder:

```bash
# 1. Komut satırı argümanı
./setup.sh "ssh-ed25519 AAAA... user@host"

# 2. Ortam değişkeni
SSH_KEY="ssh-ed25519 AAAA..." ./setup.sh

# 3. İnteraktif (script sorar)
./setup.sh
```

---

## 🐳 Docker Container Dağıtım Akışı

### Dockerfile Hazırlığı

Her proje root'unda `Dockerfile` olmalı. Node.js uygulamaları için örnek:

```dockerfile
FROM node:22-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

EXPOSE 3000
CMD ["node", "server.js"]
```

### Manuel Dağıtım

```bash
# 1. Image'ı sunucuya yükle
scp -P 3131 proje.tar root@<IP>:~/

# 2. SSH ile sunucuya bağlan ve image'ı load et
ssh -p 3131 root@<IP>
docker load < ~/proje.tar

# 3. Container'ı proxy ağında çalıştır (örn: 3000 → 8080)
docker run -d \
  --name proje-adi \
  --network proxy \
  -p 8080:3000 \
  --restart always \
  proje-adi:latest

rm ~/proje.tar
```

### docker-compose.yml ile Dağıtım

```yaml
version: '3.8'

services:
  app:
    image: proje-adi:latest
    container_name: proje-adi
    restart: always
    networks:
      - proxy
      - bridge
    ports:
      - "8080:3000"  # <dış-port>:<iç-port>
    environment:
      NODE_ENV: production

networks:
  proxy:
    external: true
  bridge:
    driver: bridge
```

### Nginx Proxy Manager Konfigürasyonu

Portainer (https://server-ip:9443) veya Nginx Proxy Manager (http://server-ip:81) arayüzünden proxy host ekle:
- **Domain Names:** `example.com`
- **Forward Hostname:** `proje-adi` (container ismi)
- **Forward Port:** `3000` (container'ın iç portu)
- **SSL Certificate:** Let's Encrypt → düzenle → sertifika iste

**Proxy Networks:** Container'ın `proxy` ağında olması zorunlu. `docker network inspect proxy` ile kontrol et.

---

## 🤖 CI/CD Bağlantısı (GitHub Actions)

Kurulum `deploy-user` adında sınırlı yetkili bir kullanıcı oluşturur. CI/CD bu kullanıcı üzerinden SSH key ile bağlanır.

### GitHub Repo Secrets

| Secret | Değer |
| --- | --- |
| `DEPLOY_SSH_KEY` | `deploy-user` private key |
| `SERVER_HOST` | Sunucu IP'si |
| `SERVER_USER` | `deploy-user` |
| `SERVER_PORT` | `3131` |

### Tam GitHub Actions Workflow Örneği

`.github/workflows/deploy.yml` dosyasını ekle:

```yaml
name: Deploy

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Docker image
        run: |
          docker build -t app:${{ github.sha }} .
          docker tag app:${{ github.sha }} app:latest
          docker save app:latest > ~/app.tar

      - name: Set up SSH
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}

      - name: Deploy to server
        run: |
          # Image'ı sunucuya yükle
          scp -P ${{ secrets.SERVER_PORT }} \
            -o StrictHostKeyChecking=accept-new \
            ~/app.tar ${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }}:~/

          # Sunucuda image load ve container başlat
          ssh -p ${{ secrets.SERVER_PORT }} \
            ${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }} <<'ENDSSH'
          set -e
          docker load -i ~/app.tar
          docker stop app 2>/dev/null || true
          docker rm app 2>/dev/null || true
          docker run -d \
            --name app \
            --network proxy \
            --network bridge \
            -p 8080:3000 \
            --restart unless-stopped \
            app:latest
          rm -f ~/app.tar
          docker image prune -f
          ENDSSH
```

**Not:** `-p 8080:3000` satırında `8080` dış port, `3000` container'ın iç portu. Dış portları gereksinime göre değiştir.

### Dockerfile Gereksinimleri

- Repository root'unda `Dockerfile` olmalı
- Node.js projelerine `node:22-alpine` veya daha güncel version kullan (`node:20-alpine` değil)
- `EXPOSE` ile container'ın dinlediği port belirt (örn: `EXPOSE 3000`)
- Production build'i yap (`npm ci --omit=dev`, değil `npm install`)

### Deploy User Yetkileri

`deploy-user` docker grubunda olduğu için tüm `docker` komutları sudo'suz çalışır. Sudoers sadece debug için açık: `sudo journalctl`, `sudo ufw status`

### Network ve Port Konfigürasyonu

- Container'ın **mutlaka** `--network proxy` ve `--network bridge` ağlarında olması gerekir
  - `proxy` — Nginx Proxy Manager ile haberleşme
  - `bridge` — Container'ın dış erişimi
- Dış portlar workflow'da manuel belirtilir: `-p <dış-port>:<iç-port>`
- Smoke test'e gerek yok çünkü tüm trafik Nginx Proxy Manager üzerinden geçer (80/443)

---

## 📋 Gereksinimler

- Hetzner Cloud sunucusu (test edilen: CX22, CPX52 ve üstü)
- Ubuntu 24.04 LTS
- Root erişimi
- Sahip olduğun bir SSH public key

---

## ⚠️ Önemli Notlar

- **Script çalıştıktan sonra SSH portu 3131'e taşınır.** Yerel makinende `~/.ssh/config` veya bağlantı komutunu güncellemeyi unutma.
- **Şifreyle SSH girişi devre dışı bırakılır.** Çalıştırmadan önce SSH key'inin doğru çalıştığından emin ol — yoksa sunucuya erişemezsin.
- **Bu script idempotent değil.** Aynı sunucuda iki kez çalıştırırsan UFW kuralları/fail2ban config'i sıfırlanır.

---

## 🛠️ Sorun Giderme

### SSH bağlanamıyorum (rebuild sonrası)
```bash
# Yerel makinende eski host key'i temizle
ssh-keygen -R <SERVER_IP>

# Yeni portla bağlan
ssh -p 3131 root@<SERVER_IP>
```

### NPM "502 Bad Gateway"
- Hedef container `proxy` ağında mı? → `docker network inspect proxy`
- Forward Hostname **container ismi** olarak girildi mi? (IP değil)
- Container çalışıyor mu? → `docker ps`

### Let's Encrypt "Internal Error"
- DNS A kaydı doğru IP'ye mi bakıyor? → `dig <domain> +short`
- 5/168h rate limit'e takıldıysan farklı subdomain dene
- NPM logu: `docker logs nginx-proxy-manager`

---

## 📂 Repo Yapısı

```
.
├── setup.sh                    # Mevcut sunucuda çalıştırılan kurulum scripti
├── README.md                   # Bu dosya
└── CLAUDE.md                   # Claude Code için proje rehberi (standartlar, adımlar, politikalar)
```

---

## 📜 Lisans

MIT
