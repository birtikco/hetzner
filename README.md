# Hetzner Server Setup

Ubuntu 24.04 üzerinde çalışan Hetzner Cloud sunucuları için otomatik kurulum ve sertleştirme scripti.

Tek komutla **Docker + Portainer + Nginx Proxy Manager** kuruyor, **fail2ban + UFW + SSH sertleştirme** ile güvenlik temelini atıyor.

---

## 🚀 Hızlı Başlangıç

### Mevcut sunucuda (build/rebuild sonrası)

- Tek satırda (Bash 4+ gerektirir):

```bash
curl -fsSL https://raw.githubusercontent.com/birtikco/hetzner/refs/heads/main/setup.sh | \
  SSH_KEY="ssh-ed25519 AAAA... user@host" bash
```

- Veya manuel:

```bash
wget https://raw.githubusercontent.com/birtikco/hetzner/refs/heads/main/setup.sh
chmod +x setup.sh
./setup.sh "ssh-ed25519 AAAA... user@host"
```

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

Kurulum tamamlandıktan sonra yeni proje eklerken:

```bash
# 1. Image'ı sunucuya yükle
scp -P 3131 proje.tar root@<IP>:/root/

# 2. Image'ı load et
docker load < proje.tar

# 3. Container'ı proxy ağında çalıştır
docker run -d \
  --name proje-adi \
  --network proxy \
  --restart always \
  proje-adi:latest
```

Veya `docker-compose.yml` ile:

```yaml
services:
  app:
    image: proje-adi:latest
    container_name: proje-adi
    restart: always

networks:
  default:
    name: proxy
    external: true
```

Sonra Nginx Proxy Manager arayüzünden:
- **Forward Hostname:** `proje-adi` (container ismi)
- **Forward Port:** Container'ın iç portu
- **SSL sekmesi:** Let's Encrypt sertifikası iste

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
└── README.md                   # Bu dosya
```

---

## 📜 Lisans

MIT
