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
- `run_with_spinner <mesaj> <komut...>` — spinner ile arka planda komut çalıştır; başarıda yeşil ✓, başarısızlıkta kırmızı ✗ basar ve `return 1` ile `set -e`'yi tetikler
- `changed <mesaj>` — bir şey değiştirildi: `CHANGES` sayacını artırır, `log` basar
- `skipped <mesaj>` — onay verilmedi, atlandı: `SKIPPED` sayacını artırır, `warn` basar
- `confirm <soru>` — kesinti yaratan işlem öncesi sorar. `--yes` verilmişse evet; terminal yoksa (`curl | bash`, CI, nohup) hayır. Cevabı `/dev/tty`'den okur, o yüzden stdin heredoc/pipe olsa bile çalışır
- `write_managed <hedef> <mod> <etiket>` — istenen içeriği stdin'den alır; dosya yoksa yazar, aynıysa dokunmaz, farklıysa `confirm` ile sorar. **Dönüş değeri anlamlıdır:** `0` = dosya istenen halde, `1` = korundu (sapma sürüyor). Bu dosyaya dayanan bir iddiada bulunmadan önce dönüşü kontrol et — aksi halde "panel kapalı" gibi bir cümle, dosya korunduğu için açık kalan bir portu örter

Yeni komutlar eklerken bu fonksiyonları kullan, standart `echo` kullanma.

**Paket listesi zorunlu/opsiyonel ayrılır.** `apt-get install` listedeki tek bir paket
bulunamazsa hiçbirini kurmaz ve non-zero döner — `set -e` altında bu, kurulumun tamamen
durması demektir. Sertleştirme için gereken paketler (`ufw`, `fail2ban`, `curl`, `gnupg` …)
`PKG_REQUIRED` içinde ve eksikse script **durmalı**. Konfor paketleri (`htop`, `nano`,
`cmatrix` …) `PKG_OPTIONAL` içinde; `apt-cache show` ile süzülür, olmayan atlanır ve uyarı
basılır. Yeni paket eklerken hangi gruba ait olduğuna karar ver — konfor paketini zorunlu
listeye koymak, o paket bir dağıtımdan kaldırıldığında kurulumu kilitler (`neofetch`
Ubuntu 26.04'te tam bunu yaptı).

**Süzme `apt-get update`'e bağımlıdır.** `apt-cache show` boş bir apt cache'te her paket
için "yok" der — taze imajda `update` çalışmadan önce `neofetch` bile bulunamaz. Paket
adımı bu yüzden sistem güncellemesinden *sonra* gelmek zorunda; 3. adımı yukarı taşıma,
yoksa mevcut paketler sessizce atlanır.

**Hata yutma yasağı:** Bir adımı `>/dev/null 2>&1` ile susturup ardından koşulsuz başarı
mesajı basma. Ya `run_with_spinner` kullan, ya da komutun gerçek çıktısını göster. Sessiz
başarısızlık bu scriptte en pahalı hata sınıfı — kullanıcı sunucunun sertleştirildiğini
sanarak devam eder.

### Renk Kodları
Tanımlanmış renkler (başında tanımlanmış): `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `MAGENTA`, `WHITE`, `GRAY`, `BOLD`, `DIM`, `NC` (sıfırla)

Formatı: `echo -e "${CYAN}metin${NC}"`

## Kurulum Adımları (setup.sh)

Script 10 adımda çalışır:

1. **SSH Anahtarı** — authorized_keys'e genel anahtar ekle (root)
2. **Sistem Güncellemesi** — apt update + upgrade
3. **Paketler** — zorunlu paketler (biri eksikse script durur) + opsiyonel paketler (eksik olan süzülür, uyarı basılır)
4. **Deploy User (CI/CD)** — `deploy-user` oluştur, SSH key ekle, sudoers minimum yetki
5. **SSH Sertleştirme** — `99-hardening.conf` drop-in'i yaz, çakışanları yorumla, `sshd -T` ile doğrula
6. **fail2ban** — brute force koruması (3 deneme → 24 saat ban, katlanarak artar)
7. **UFW** — güvenlik duvarı (default deny incoming, açık portlar: 3131, 80, 443)
8. **Docker** — Docker CE + Compose plugin + Buildx plugin, `deploy-user` docker grubuna eklenir. Depo kod adı ve mimari sabit değil: `UBUNTU_CODENAME` ve `dpkg --print-architecture` ile türetilir, depo yoksa script durur
9. **Portainer** — `/root/portainer/docker-compose.yml`, `127.0.0.1:9443` (internete kapalı). Eski `docker run` kurulumları onay alınarak compose'a taşınır
10. **Nginx Proxy Manager** — docker-compose.yml, 80/443 dışa açık, panel `127.0.0.1:81`

## SSH Key Kaynağı

Script'te 3 şekilde SSH key sağlanabilir (sıralı kontrol):

1. **Komut satırı argümanı:** `./setup.sh "ssh-ed25519 ROOT_KEY..." "ssh-ed25519 DEPLOY_KEY..."`
2. **Ortam değişkeni:** `SSH_KEY="..." DEPLOY_KEY="..." ./setup.sh`
3. **İnteraktif sorgu:** `./setup.sh` (script root key'i sorar; DEPLOY_KEY verilmezse SSH_KEY fallback)

Key formatı doğrulaması regex ile yapılır: `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-*`, veya `ssh-dss`

**`DEPLOY_KEY` opsiyoneldir.** Verilmezse root SSH key'i deploy-user için de kullanılır. CI/CD için ayrı key önerilir (key rotation kolay, leak halinde insan operatör etkilenmez).

## Deploy User Politikası

`deploy-user` CI/CD için tasarlanmış sınırlı yetkili kullanıcıdır:

- **Kimlik:** `useradd --create-home --shell /bin/bash deploy-user`, şifre kilitli (`passwd -l`)
- **SSH:** Yalnızca key auth, AllowUsers whitelist'inde
- **Docker:** `docker` grubu üyesi → `docker load/run/stop/rm/image prune` komutları sudo'suz çalışır
- **Sudoers:** `/etc/sudoers.d/deploy-user` — NOPASSWD sadece `journalctl` ve `ufw status` (debug için)

**Bilinçli trade-off:** Docker grubu üyeliği fiili root yetkisidir (`docker run -v /:/host` ile filesystem). Bu kaçınılmaz çünkü CI/CD'nin docker'a erişmesi gerekiyor. Asıl güvenlik kazancı **SSH key auth** + **dedicated kullanıcı izolasyonu** + **root parola leak'inin etkisizleşmesi**.

**Yeni komut eklerken:** Sudoers kapsamını gerçekten kullanılan komutlarla sınırla. `apt-get`, `useradd`, `visudo`, `systemctl restart *` gibi geniş yetkileri ekleme — gerekirse spesifik olarak whitelist'e ekle.

## Önemli Notlar

## Tekrar Çalıştırılabilirlik (converge)

Script tekrar çalıştırılabilir: eksik olanı kurar, zaten doğru olana dokunmaz, kullanıcının
elle değiştirmiş olabileceği dosyalara yazmadan önce sorar. Bir sunucunun hâlâ istenen halde
olup olmadığını görmek için tekrar çalıştırmak güvenli bir işlemdir.

**Üç davranış sınıfı — yeni adım eklerken hangisine girdiğine karar ver:**

| Sınıf | Örnek | Davranış |
| --- | --- | --- |
| Koşulsuz uygulanır | SSH drop-in, UFW izinleri, apt paketleri, `usermod -aG` | Her koşuda istenen hale getirilir |
| Varsa eklenmez | root ve deploy SSH key'leri | `grep -qF` ile kontrol, yoksa eklenir |
| Sorulur | `jail.local`, iki compose dosyası | `write_managed`: yoksa yaz, aynıysa geç, farklıysa sor |

Kullanıcının düzenleyebileceği bir dosya yazıyorsan **`cat >` ile doğrudan yazma**, `write_managed`
kullan. Aksi halde kullanıcının bilinçli değişikliği sessizce geri alınır — özet ekranı panel
portlarını kaldırmayı önerirken sonraki koşunun onları geri yazması tam bu hataydı.

**SSH sertleştirmesi neden sorulmuyor:** Güvenlik ayarında drift kabul edilmiyor.
`99-hardening.conf` koşulsuz yazılır, çakışan direktifler yorumlanır ve sonuç `sshd -T` ile
doğrulanır; uymuyorsa script durur. Bu istisnayı genişletme.

**Yıkıcı işlem = onay.** Konteyner yeniden yaratma gibi kesinti yaratan adımlar `confirm` ile
sorulur. Etkileşimli terminal yoksa sessizce atlanır ve `SKIPPED` sayacına yazılır; `--yes`
ile zorlanır. Bir adımın kesinti yaratıp yaratmadığından emin değilsen sor — sessizce
uygulamak, üretimde kazara çalıştırıldığında geri alınamaz.

**Sayaçlar ve çıkış kodu:** `changed`/`skipped` helper'ları `CHANGES` ve `SKIPPED`
sayaçlarını besler. Banner üç durum ayırır: `SKIPPED>0` → "SAPMALAR UYGULANMADI",
`CHANGES=0` → "SUNUCU ZATEN İSTENEN DURUMDA", aksi halde "KURULUM BAŞARIYLA TAMAMLANDI".
Çıkış kodu sözleşmesi: **`0`** istenen durumda · **`2`** sapma uygulanmadı · **`1`** hata
(`err`). CI bu ayrımı okur; değiştirirsen README'deki tabloyu da güncelle.

**Bir güvenlik iddiası, dayandığı adım atlandıysa basılmaz.** "Panel dışarıya kapalı",
"3 deneme → 24 saat ban" gibi cümleler yalnızca ilgili `write_managed` 0 döndüyse
yazdırılır; aksi halde yerine uyarı geçer ve `PANELS_VERIFIED=0` ile özet ekranı da
uyarıya döner. Sessizce yanlış güvence vermek, hiç bilgi vermemekten kötüdür.

**UFW'de reset yok:** `ufw allow` zaten idempotent. `ufw --force reset` çağırmak, kullanıcının
sonradan eklediği kuralları silerdi; o yüzden kaldırıldı, geri ekleme.

**SSH Port Değişimi:** Kurulum sonrası SSH portu 22'den 3131'e taşınır. Yerel `~/.ssh/config` güncellenmesi gerekir.

**Şifre Girişi Kapalı:** PasswordAuthentication no ayarı yapıldığı için SSH key zorunludur.

**SSH ayarları drop-in ile yazılır:** `/etc/ssh/sshd_config.d/99-hardening.conf`. sshd bir
direktifin **ilk** gördüğü değeri kullanır — alfabetik sıra değil, okuma sırası kazanır — ve
`Include` satırı `sshd_config`'in en başındadır. Bu yüzden cloud imajlarıyla gelen
`50-cloud-init.conf` (içinde sık sık `PasswordAuthentication yes` olur) drop-in'imizi
gölgeleyebilir. Script bunu önlemek için çakışan direktifleri hem ana dosyadan hem diğer
drop-in'lerden yorum satırına alır, sonra `sshd -T` çıktısını beklenen değerlerle karşılaştırır
ve **uymuyorsa durur**. Bu adımı gevşetme: sessizce sertleştirilmemiş bir sunucu, hiç
sertleştirilmemiş olandan daha tehlikelidir çünkü kullanıcı korunduğunu sanır.

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

**Port yayınlama yasağı:** Uygulama container'larına `-p` verme. NPM `proxy` ağı üzerinden
container'a **adıyla** ulaşır, yayınlanmış porta ihtiyaç yoktur. Yayınlanan her port siteyi
ikinci bir yoldan — SSL'siz, access list'siz — internete açar, ve UFW bunu durdurmaz:
Docker'ın `0.0.0.0` bağlamaları `INPUT` zincirine hiç uğramaz. Bir servise host üzerinden
erişmek gerçekten gerekiyorsa `-p 172.17.0.1:PORT:PORT` kullan.

**Ağ:** Container yalnız `proxy` ağında olmalı. `bridge` ağına ayrıca bağlanmak
**gerekmez** — `proxy` kullanıcı tanımlı bir bridge ağı ve NAT'lı outbound verir
(14.08.2026'da taze kurulumda ölçüldü). `docker network connect bridge` adımını geri ekleme.

**Nginx Proxy Manager'da proxy host ekle:**
- **Forward Hostname:** container ismi (örn: `app`)
- **Forward Port:** container'ın **iç** portu (yayınlanmış dış port değil)
- **SSL:** Let's Encrypt sertifikası iste
- Portainer'ın proxy host'unda scheme **HTTPS** olmalı (kendi TLS'ini konuşur)

**Panellere erişim:** Portainer ve NPM yalnızca loopback'te dinler. SSH tüneli:
```bash
ssh -p 3131 -L 8181:127.0.0.1:81 root@<IP>      # NPM
ssh -p 3131 -L 9443:127.0.0.1:9443 root@<IP>    # Portainer
```

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
