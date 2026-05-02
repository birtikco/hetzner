# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proje Özeti

Bu repository, Hetzner Cloud'da Ubuntu 24.04 LTS üzerinde çalışan sunucuları otomatik olarak kurmak ve sertleştirmek için tasarlanmış bir Bash script'ini içerir.

**Kurulum kapsamı:**
- Docker CE + Compose plugin + Buildx plugin
- Portainer CE (Docker yönetim arayüzü)
- Nginx Proxy Manager (reverse proxy + Let's Encrypt SSL otomasyonu)
- SSH sertleştirmesi (port 3131, key-only, fail2ban, UFW)
- Sistem paketleri (git, tmux, htop, curl, wget, vb.)

## Bash Script Standartları

### Strict Mode
Script `set -e` ve `set -o pipefail` ile çalışır. Yeni kod eklerken bu kuralları takip et:
- Hata sırasında komut zincirleri derhal durur
- Komutları backtick yerine `$(...)` syntax'ı ile çerçevele
- Pipe'lar herhangi bir nokta da başarısız olursa tüm komut başarısız olur

### Helper Fonksiyonlar

Script'te şu logging fonksiyonları kullanılır:
- `log <mesaj>` — başarı mesajı (yeşil ✓)
- `info <mesaj>` — bilgi (mavi ℹ)
- `warn <mesaj>` — uyarı (sarı !)
- `err <mesaj>` — hata ve exit (kırmızı ✗)
- `step_header <başlık>` — adım başlığı (mavi kutu)
- `step_done` — adım tamamlanması (yeşil)
- `run_with_spinner <mesaj> <komut...>` — spinner ile arka planda komut çalıştır

Yeni komutlar eklerken bu fonksiyonları kullan, standart `echo` kullanma.

### Renk Kodları
Tanımlanmış renkler (başında tanımlanmış): `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `MAGENTA`, `WHITE`, `GRAY`, `BOLD`, `DIM`, `NC` (sıfırla)

Formatı: `echo -e "${CYAN}metin${NC}"`

## Kurulum Adımları (setup.sh)

Script 9 adımda çalışır:

1. **SSH Anahtarı** — authorized_keys'e genel anahtar ekle
2. **Sistem Güncellemesi** — apt update + upgrade
3. **Paketler** — temel sistem paketlerini yükle
4. **SSH Sertleştirme** — port 3131, şifre devre dışı, MaxAuthTries 3
5. **fail2ban** — brute force koruması (3 deneme → 24 saat ban, katlanarak artar)
6. **UFW** — güvenlik duvarı (default deny incoming, açık portlar: 3131, 80, 443, 9443, 8000)
7. **Docker** — Docker CE + Compose plugin + Buildx plugin
8. **Portainer** — Docker yönetim arayüzü (container + volume oluştur, proxy ağına bağla)
9. **Nginx Proxy Manager** — docker-compose.yml ile NPM kurulumu

## SSH Key Kaynağı

Script'te 3 şekilde SSH key sağlanabilir (sıralı kontrol):

1. **Komut satırı argümanı:** `./setup.sh "ssh-ed25519 AAAA... user@host"`
2. **Ortam değişkeni:** `SSH_KEY="..." ./setup.sh`
3. **İnteraktif sorgu:** `./setup.sh` (script sorar)

Key formatı doğrulaması regex ile yapılır: `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-*`, veya `ssh-dss`

## Önemli Notlar

**Idempotent Değil:** Script aynı sunucuda iki kez çalıştırılırsa:
- UFW kuralları sıfırlanır
- fail2ban config'i sıfırlanır
- SSH key'ler yığılır (append mode)

**SSH Port Değişimi:** Kurulum sonrası SSH portu 22'den 3131'e taşınır. Yerel `~/.ssh/config` güncellenmesi gerekir.

**Şifre Girişi Kapalı:** PasswordAuthentication no ayarı yapıldığı için SSH key zorunludur.

## Docker Containerları Dağıtımı (Post-Setup)

Kurulum tamamlandıktan sonra uygulamaları sunucuya dağıtmak için:

```bash
# 1. Docker image'ını sunucuya gönder
scp -P 3131 app.tar root@<IP>:/root/

# 2. Image'ı load et
docker load < app.tar

# 3. Container'ı proxy ağında çalıştır
docker run -d --name app --network proxy --restart always app:latest
```

**Veya docker-compose ile:**

```yaml
services:
  app:
    image: app:latest
    container_name: app
    restart: always

networks:
  default:
    name: proxy
    external: true
```

**Nginx Proxy Manager'da proxy host ekle:**
- **Forward Hostname:** container ismi (örn: `app`)
- **Forward Port:** container'ın iç portu
- **SSL:** Let's Encrypt sertifikası iste

## Dosya Yapısı

```
.
├── setup.sh       # Ana kurulum scripti
└── README.md      # Dokümantasyon
```

## Sorun Giderme

Önemli sorun giderme senaryoları README.md'de dokumente edilmiştir. Düzenleme yaparken bu sorun çözümleri kontrol et ve scriptste ilgili hata işleme ekle.

## Kullanım Senaryoları

Bu script şu senaryolar için tasarlanmıştır:
- Fresh Hetzner sunucu kurulumu (server rebuild sonrası)
- Herhangi bir Hetzner CX22 veya üstü makine
- Otomatik SSL/TLS sertifikası yönetimi ile Docker container dağıtımı
- Tek komutla (curl | bash) uzaktan kurulum
