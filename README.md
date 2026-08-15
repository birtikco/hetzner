# Hetzner Server Setup

[![Lint](https://github.com/birtikco/hetzner/actions/workflows/lint.yml/badge.svg)](https://github.com/birtikco/hetzner/actions/workflows/lint.yml)

Ubuntu 24.04 / 26.04 LTS üzerinde çalışan Hetzner Cloud sunucuları için otomatik kurulum ve sertleştirme scripti.

Tek komutla **Docker + Portainer + Nginx Proxy Manager** kuruyor, **fail2ban + UFW + SSH sertleştirme** ile güvenlik temelini atıyor. Tekrar çalıştırılabilir: eksiği tamamlar, doğru olana dokunmaz.

**İçindekiler:** [Hızlı Başlangıç](#-hızlı-başlangıç) · [Ne Kuruyor?](#-ne-kuruyor) · [Güvenlik](#-güvenlik-yapılandırması) · [Panellere Erişim](#-yönetim-panellerine-erişim) · [Kullanım](#-kullanım-yöntemleri) · [Container Dağıtımı](#-docker-container-dağıtım-akışı) · [CI/CD](#-cicd-bağlantısı-github-actions) · [Gereksinimler](#-gereksinimler) · [Sorun Giderme](#-sorun-giderme)

---

## 🚀 Hızlı Başlangıç

### 1. Başlamadan önce

- [ ] Elinde bir SSH key çifti var → `cat ~/.ssh/id_ed25519.pub` (yoksa: `ssh-keygen -t ed25519`)
- [ ] Sunucuya root olarak erişebiliyorsun
- [ ] Sunucu taze kurulmuş ya da rebuild edilmiş bir Ubuntu 24.04 / 26.04

> ⚠️ Script şifreyle SSH girişini **kapatır** ve portu **3131**'e taşır. Public key'i doğru
> yapıştırdığından emin ol — yanlış key'le sunucuya bir daha giremezsin, rebuild gerekir.

### 2. Sunucuda çalıştır

Tek satırda:

```bash
curl -fsSL https://raw.githubusercontent.com/birtikco/hetzner/refs/heads/main/setup.sh | \
  SSH_KEY="ssh-ed25519 AAAA... user@host" DEPLOY_KEY="ssh-ed25519 AAAA... user@host" bash
```

Veya indirip çalıştır:

```bash
wget https://raw.githubusercontent.com/birtikco/hetzner/refs/heads/main/setup.sh
chmod +x setup.sh
./setup.sh "ssh-ed25519 AAAA... user@host" "ssh-ed25519 AAAA... user@host"
```

`DEPLOY_KEY` opsiyoneldir — verilmezse root key'i deploy-user için de kullanılır.

### 3. Sonrasında

Script biterken sunucu IP'sini, bağlantı komutlarını ve sıradaki adımları ekrana yazar.
İlk iş yeni portla bağlanabildiğini doğrulamak:

```bash
ssh-keygen -R <SERVER_IP>          # eski host key'i temizle
ssh -p 3131 root@<SERVER_IP>       # yeni portla bağlan
```

---

## 📦 Ne Kuruyor?

### Sistem paketleri

| Grup | Paketler | Eksikse |
| --- | --- | --- |
| Zorunlu | `curl` `wget` `git` `ufw` `fail2ban` `ca-certificates` `gnupg` | Script durur |
| Opsiyonel | `htop` `tmux` `nano` `cmatrix` `neofetch` | Atlanır, uyarı basılır |

`neofetch` Ubuntu 26.04'te kaldırıldı; opsiyonel olduğu için kurulum etkilenmez.

### Docker yığını
- **Docker CE** + Compose plugin + Buildx plugin
- **Portainer CE** — Docker yönetim arayüzü (`127.0.0.1:9443`, internete kapalı) — `/root/portainer/docker-compose.yml`
- **Nginx Proxy Manager** — reverse proxy + Let's Encrypt SSL otomasyonu (80/443 dışa açık, panel `127.0.0.1:81`)
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
| Yönetim panelleri | Portainer ve NPM yalnızca loopback'te — SSH tüneliyle erişilir |

### UFW açık portlar
```
3131  SSH
80    HTTP (NPM)
443   HTTPS (NPM)
```

> ⚠️ **UFW, Docker'ın yayınladığı portları durdurmaz.**
> `-p 8080:3000` ile yayınlanan port `0.0.0.0`'a bağlanır, `FORWARD` zincirindeki
> `DOCKER` kuralından geçer ve UFW'nin `INPUT` kurallarına **hiç uğramaz** — yukarıdaki
> listede olmasa da internete açıktır. Bir portu gerçekten yayınlaman gerekiyorsa
> `-p 127.0.0.1:PORT:PORT` (yalnız sunucudan) veya `-p 172.17.0.1:PORT:PORT`
> (host üzerinden container'lara) kullan.

---

## 🔑 Yönetim Panellerine Erişim

Portainer ve NPM panelleri internete açık **değil**; sadece sunucunun loopback
arayüzünde dinliyorlar. Erişim SSH tüneliyle:

```bash
# Portainer
ssh -p 3131 -L 9443:127.0.0.1:9443 root@<IP>
# tarayıcıda: https://localhost:9443

# Nginx Proxy Manager
ssh -p 3131 -L 8181:127.0.0.1:81 root@<IP>
# tarayıcıda: http://localhost:8181
```

Tünel, zaten var olan SSH kimlik doğrulamasını kullanır — panel hiçbir an internete
açılmaz. Bu özellikle NPM için önemli: NPM belgelenmiş varsayılan hesapla
(`admin@example.com` / `changeme`) açılır, ve paneli ele geçiren kişi sunucudaki
**bütün alan adlarının** trafiğini yönlendirebilir.

### Kalıcı çözüm: panelleri HTTPS'e taşı

Tünel ilk kurulum içindir. DNS bağlandıktan sonra panellere NPM üzerinden proxy host
açıp loopback bağlamalarını tamamen kaldırabilirsin:

| Panel | Forward Hostname | Forward Port | Scheme |
| --- | --- | --- | --- |
| Portainer | `portainer` | `9443` | **HTTPS** |
| NPM | `nginx-proxy-manager` | `81` | HTTP |

Portainer kendi TLS'ini konuştuğu için scheme **HTTPS** seçilmeli — `http` seçilirse
502 alınır.

Proxy host'lar çalıştıktan sonra:

```bash
# NPM: compose'dan 127.0.0.1:81:81 satırını sil
nano /root/nginx-proxy-manager/docker-compose.yml
docker compose -f /root/nginx-proxy-manager/docker-compose.yml up -d

# Portainer: ports: bloğunun TAMAMINI sil (altında tek satır var)
nano /root/portainer/docker-compose.yml
docker compose -f /root/portainer/docker-compose.yml up -d
```

> Portainer'da yalnızca port satırını silip `ports:` anahtarını bırakırsan compose
> `services.portainer.ports must be a array` deyip çalışmaz — anahtarı da sil.

> `setup.sh` tekrar çalıştırılırsa bu dosyaların değiştiğini görür ve **üzerine
> yazmadan önce sorar.** Terminal etkileşimli değilse (`curl | bash`, CI) dosyaya
> dokunmaz, atladığını raporlar. `--yes` verirsen sormadan istenen hale döndürür —
> yani sildiğin satırlar geri gelir.

---

## 🎯 Kullanım Yöntemleri

`setup.sh` SSH public key'i üç kaynaktan alır — sırayla argüman, ortam değişkeni, interaktif soru:

```bash
# 1. Komut satırı argümanı
./setup.sh "ssh-ed25519 AAAA... user@host"

# 2. Ortam değişkeni
SSH_KEY="ssh-ed25519 AAAA..." ./setup.sh

# 3. İnteraktif (script sorar)
./setup.sh

# 4. Onay sormadan (CI / otomasyon)
./setup.sh --yes "ssh-ed25519 AAAA... user@host"
```

`--yes` (kısaca `-y`) yalnızca **onay sorularını** atlar; kesinti yaratan adımları
(konteyner yeniden yaratma, elle değiştirilmiş dosyanın üzerine yazma) sormadan uygular.

**Çıkış kodları:** `0` sunucu istenen durumda · `2` sapma var ama uygulanmadı (onay
verilmedi ya da terminal etkileşimli değildi) · `1` hata. CI'da `2`'yi "kontrol et"
olarak ele al — kurulum bozulmadı, ama sunucu tam converge olmadı.

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

# 3. Container'ı proxy ağında çalıştır — port yayınlamaya gerek yok
docker run -d \
  --name proje-adi \
  --network proxy \
  --restart always \
  proje-adi:latest

rm ~/proje.tar
```

Container'a **hiçbir port yayınlanmıyor.** NPM ona `proxy` ağı üzerinden konteyner
adıyla ulaşır; yayınlanmış bir port siteyi ikinci bir yoldan internete açardı — SSL'siz,
Block Common Exploits'siz, access list'siz.

### docker-compose.yml ile Dağıtım

```yaml
services:
  app:
    image: proje-adi:latest
    container_name: proje-adi
    restart: always
    networks:
      - proxy
    environment:
      NODE_ENV: production

networks:
  proxy:
    external: true
```

### Nginx Proxy Manager Konfigürasyonu

NPM arayüzüne SSH tüneliyle gir ([Yönetim Panellerine Erişim](#-yönetim-panellerine-erişim)), proxy host ekle:
- **Domain Names:** `example.com`
- **Forward Hostname:** `proje-adi` (container ismi)
- **Forward Port:** `3000` — container'ın **iç** portu, yayınlanmış bir dış port değil
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
            --restart always \
            app:latest
          rm -f ~/app.tar
          docker image prune -f
          ENDSSH
```

**Not:** Port yayınlanmıyor. NPM container'a `proxy` ağı üzerinden `app` adıyla ulaşır;
proxy host'ta **Forward Port** olarak container'ın iç portunu (`3000`) yaz.

### Dockerfile Gereksinimleri

- Repository root'unda `Dockerfile` olmalı
- Node.js projelerinde `node:22-alpine` veya daha güncel bir imaj kullan (`node:20-alpine` değil)
- `EXPOSE` ile container'ın dinlediği portu belirt (örn: `EXPOSE 3000`)
- Production kurulumu yap: `npm install` değil, `npm ci --omit=dev`

### Deploy User Yetkileri

`deploy-user` docker grubunda olduğu için tüm `docker` komutları sudo'suz çalışır. Sudoers sadece debug için açık: `sudo journalctl`, `sudo ufw status`

### Network ve Port Konfigürasyonu

- Container'ın **yalnızca `proxy` ağında** olması yeterli
  - NPM ile haberleşme buradan olur
  - Dış erişim de buradan çalışır: `proxy` kullanıcı tanımlı bir bridge ağı ve NAT'lı outbound verir. Ayrıca `bridge` ağına bağlanmak **gerekmez** — 14.08.2026'da taze kurulumda ölçüldü, yalnız `proxy` ağındaki container dışarı çıkabiliyor
- **Port yayınlama.** NPM container'a `proxy` ağı üzerinden adıyla ulaştığı için `-p` gerekmez. Yayınlanan her port siteyi ikinci bir yoldan, SSL'siz ve kuralsız internete açar — ve [UFW bunu durdurmaz](#-güvenlik-yapılandırması)
- Bir servise host üzerinden erişmen gerçekten gerekiyorsa `-p 172.17.0.1:PORT:PORT` ile bağla, `-p PORT:PORT` ile değil
- Smoke test'e gerek yok çünkü tüm trafik Nginx Proxy Manager üzerinden geçer (80/443)

---

## 📋 Gereksinimler

- Hetzner Cloud sunucusu (test edilen: CX22, CPX52 ve üstü)
- **Ubuntu 24.04 LTS** veya **26.04 LTS** — ikisi de uçtan uca doğrulandı (amd64)
- Root erişimi
- Sahip olduğun bir SSH public key

Docker deposu dağıtımın kod adından türetiliyor (`UBUNTU_CODENAME`), mimari
`dpkg --print-architecture` ile okunuyor. Docker'ın o sürüm için deposu yoksa script
kurulumu yarıda kesmek yerine baştan durur.

26.04 üç noktada 24.04'ten ayrılıyor; script üçünü de karşılıyor:

| Fark | 24.04 | 26.04 |
| --- | --- | --- |
| `neofetch` paketi | var | **kaldırıldı** — opsiyonel listede, atlanır |
| `sudo` | klasik sudo | **sudo-rs** — `requiretty` sözdizimini reddeder |
| `sshd -T` çıktısı | `without-password` | `prohibit-password` (OpenSSH 10) |

ARM (Hetzner CAX) mimarisi kod olarak destekleniyor ama test edilmedi.

---

## ⚠️ Önemli Notlar

- **Script çalıştıktan sonra SSH portu 3131'e taşınır.** Yerel makinende `~/.ssh/config` veya bağlantı komutunu güncellemeyi unutma.
- **Şifreyle SSH girişi devre dışı bırakılır.** Çalıştırmadan önce SSH key'inin doğru çalıştığından emin ol — yoksa sunucuya erişemezsin.
- **Script tekrar çalıştırılabilir.** Eksik olanı kurar, zaten doğru olana dokunmaz. Sonunda ne kadarının değiştiğini yazar; hiçbir şey değişmediyse "SUNUCU ZATEN İSTENEN DURUMDA" der. Bir sunucunun hâlâ istenen halde olup olmadığını görmek için tekrar çalıştırmak güvenlidir.
- **Elle değiştirdiğin dosyalara sormadan dokunmaz.** `jail.local` ve iki compose dosyası için: yoksa yazar, aynıysa geçer, farklıysa sorar. Etkileşimli terminal yoksa atlar ve raporlar. `--yes` ile sormadan uygular.
- **İstisna: SSH sertleştirmesi.** `/etc/ssh/sshd_config.d/99-hardening.conf` sorulmadan istenen hale getirilir ve `sshd -T` ile doğrulanır — güvenlik ayarında drift kabul edilmiyor.

---

## 🛠️ Sorun Giderme

### SSH bağlanamıyorum (rebuild sonrası)
```bash
# Yerel makinende eski host key'i temizle
ssh-keygen -R <SERVER_IP>

# Yeni portla bağlan
ssh -p 3131 root@<SERVER_IP>
```

### Panele giremiyorum (`server-ip:81` / `server-ip:9443` açılmıyor)
Doğru davranış — paneller internete kapalı. SSH tüneli kur:
```bash
ssh -p 3131 -L 8181:127.0.0.1:81 root@<IP>      # NPM      → http://localhost:8181
ssh -p 3131 -L 9443:127.0.0.1:9443 root@<IP>    # Portainer → https://localhost:9443
```
Ayrıntı: [Yönetim Panellerine Erişim](#-yönetim-panellerine-erişim)

### NPM "502 Bad Gateway"
- **Forward Port container'ın İÇ portu mu?** Port yayınlanmadığı için en sık yapılan hata dış port yazmak — `EXPOSE 3000` ise `3000` yaz
- Hedef container `proxy` ağında mı? → `docker network inspect proxy`
- Forward Hostname **container ismi** olarak girildi mi? (IP değil)
- Portainer proxy host'unda scheme **HTTPS** mi? (Portainer kendi TLS'ini konuşur)
- Container çalışıyor mu? → `docker ps`

### Script "SAPMALAR UYGULANMADI" dedi (çıkış kodu 2)

Kurulum bozulmadı — bir veya daha fazla adım onay isteyip alamadı. En sık nedeni: elle
düzenlediğin bir dosya (`jail.local`, compose dosyaları) ile scriptin istediği içerik
farklı ve terminal etkileşimli değil (`curl | bash`, CI).

- Değişikliğin bilinçliyse: bir şey yapman gerekmiyor, sunucu çalışıyor
- Scriptin halini geri istiyorsan: `./setup.sh --yes "ssh-ed25519 AAAA..."`
- Hangi dosyanın atlandığı çıktının sonunda `!` işaretiyle yazılı

### Let's Encrypt "Internal Error"
- DNS A kaydı doğru IP'ye mi bakıyor? → `dig <domain> +short`
- 5/168h rate limit'e takıldıysan farklı subdomain dene
- NPM logu: `docker logs nginx-proxy-manager`

---

## 📂 Repo Yapısı

```
.
├── setup.sh                    # Sunucuda çalıştırılan kurulum scripti
├── README.md                   # Bu dosya
├── CLAUDE.md                   # Claude Code için proje rehberi (kurallar, gerekçeler)
├── LICENSE                     # MIT
└── .github/
    ├── checks.sh               # Script ↔ doküman tutarlılık kontrolleri
    └── workflows/lint.yml      # CI: shellcheck + bash -n + checks.sh
```

### Katkı verirken

Commit öncesi lokalde çalıştır — CI aynısını koşar:

```bash
bash -n setup.sh                 # sözdizimi
shellcheck -S warning setup.sh   # lint
./.github/checks.sh              # script ile dokümanlar uyumlu mu
```

`checks.sh` şunları doğrular: `TOTAL_STEPS` gerçek adım sayısıyla eşleşiyor mu · SSH portu
üç dosyada da aynı mı · çıkış kodu sözleşmesi belgeli mi · strict mode yerinde mi · kurulan
her paket README tablosunda mı · yönetilen dosyalar `write_managed` ile mi yazılıyor ·
scriptte uzun yorum bloğu kalmış mı.

---

## 📜 Lisans

MIT
