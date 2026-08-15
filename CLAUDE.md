# CLAUDE.md

Claude Code için proje rehberi. Kullanıcıya dönük anlatım README.md'de; burası kural,
sözleşme ve gerekçe kaydıdır.

## Proje

Hetzner Cloud / Ubuntu 24.04 · 26.04 LTS sunucularını kuran ve sertleştiren tek bir Bash
scripti. Kapsam: Docker CE + Compose + Buildx · Portainer CE · Nginx Proxy Manager ·
SSH sertleştirme (3131, key-only) · fail2ban · UFW · deploy-user.

```
.
├── setup.sh                    # tek çalıştırılabilir; tüm kurulum burada
├── README.md                   # kullanıcı dokümanı (kurulum, paneller, CI/CD, sorun giderme)
├── CLAUDE.md                   # bu dosya
├── LICENSE                     # MIT
└── .github/
    ├── checks.sh               # tutarlılık kontrolleri; lokalde de çalıştırılabilir
    └── workflows/lint.yml      # CI: shellcheck -S warning + bash -n + checks.sh
```

**Değişiklikten sonra çalıştır:** `bash -n setup.sh && shellcheck -S warning setup.sh && ./.github/checks.sh`

## Değişmezler

Bunlar bilinçli kararlar. Değiştirmeden önce burada neden yazdığına bak.

| # | Kural | Neden |
| --- | --- | --- |
| 1 | Hata yutulmaz | `>/dev/null 2>&1` + koşulsuz başarı mesajı yasak. Ya `run_with_spinner`, ya gerçek çıktı. Sessiz başarısızlık en pahalı hata sınıfı: kullanıcı sertleştirildiğini sanıp devam eder |
| 2 | Güvenlik iddiası, dayanağı atlandıysa basılmaz | "Panel kapalı" / "3 deneme → 24h ban" yalnız ilgili `write_managed` 0 döndüyse; aksi halde uyarı + `PANELS_VERIFIED=0` |
| 3 | SSH sertleştirmesinde drift yok | `99-hardening.conf` sorulmadan yazılır, `sshd -T` ile doğrulanır, uymuyorsa `err`. Bu istisnayı genişletme |
| 4 | Yıkıcı işlem = `confirm` | Konteyner yeniden yaratma gibi kesinti yaratan adımlar sorulur. Emin değilsen sor |
| 5 | Kullanıcının düzenleyebileceği dosyaya `cat >` ile yazma | `write_managed` kullan. Aksi halde bilinçli değişiklik sessizce geri alınır |
| 6 | UFW'de `reset` yok | `ufw allow` zaten idempotent; `--force reset` elle eklenen kuralları silerdi |
| 7 | Uygulama konteynerlerine `-p` verme | NPM `proxy` ağından konteyner **adıyla** ulaşır. Yayınlanan port siteyi SSL'siz ikinci bir yoldan açar ve UFW bunu durdurmaz (Docker `INPUT` zincirine uğramaz). Host'tan erişim şartsa `-p 172.17.0.1:PORT:PORT` |
| 8 | `bridge` ağına bağlanma | `proxy` kullanıcı tanımlı bridge; NAT'lı outbound zaten var (14.08.2026'da taze kurulumda ölçüldü). `docker network connect bridge` adımını geri ekleme |
| 9 | Depo/mimari sabit yazılmaz | `UBUNTU_CODENAME` + `dpkg --print-architecture`. Docker deposu yoksa `err` — yanlış sürüme paket kurmaktansa dur |
| 10 | 3. adım (Paketler) yukarı taşınmaz | `apt-cache show` boş cache'te her pakete "yok" der; süzme `apt-get update`'ten sonra çalışmak zorunda |

## Bash Standartları

`set -e` + `set -o pipefail`. Komut ikamesi `$(...)`, backtick değil. `echo` yerine helper.

| Helper | Davranış |
| --- | --- |
| `log` / `info` / `warn` | yeşil ✓ · mavi ℹ · sarı ! |
| `err <mesaj>` | kırmızı ✗ + `exit 1` |
| `step_header <başlık>` / `step_done` | adım kutusu aç / kapat; `CURRENT_STEP` artar |
| `run_with_spinner <mesaj> <komut...>` | arka planda çalıştırır; başarısızlıkta ✗ basıp `return 1` ile `set -e`'yi tetikler |
| `changed <mesaj>` | `CHANGES++` + `log` |
| `skipped <mesaj>` | `SKIPPED++` + `warn` |
| `confirm <soru>` | `--yes` → 0. Terminal yoksa (`curl \| bash`, CI, nohup) → 1. Cevabı `/dev/tty`'den okur, stdin pipe olsa da çalışır |
| `write_managed <hedef> <mod> <etiket>` | içerik stdin'den. Yoksa yaz · aynıysa dokunma · farklıysa `confirm`. **Dönüş: 0 = istenen halde, 1 = korundu.** Bu dosyaya dayanan iddiadan önce dönüşü kontrol et (değişmez #2) |

Renkler: `RED GREEN YELLOW BLUE CYAN MAGENTA WHITE GRAY BOLD DIM NC` · biçim `echo -e "${CYAN}metin${NC}"`.

**Paket listesi ikiye ayrılır.** `apt-get install` tek eksik pakette hiçbirini kurmaz ve
non-zero döner. Sertleştirme için gerekenler `PKG_REQUIRED` (eksikse script durmalı),
konfor paketleri `PKG_OPTIONAL` (`apt-cache show` ile süzülür, eksik olan uyarıyla atlanır).
Yeni paket eklerken grubunu seç — konfor paketini zorunlu listeye koymak, o paket bir
dağıtımdan kaldırıldığında kurulumu kilitler (`neofetch`, Ubuntu 26.04).

## Kurulum Adımları

| # | Adım | Not |
| --- | --- | --- |
| 1 | SSH Anahtarı | root `authorized_keys`; `grep -qxF` ile varsa eklenmez |
| 2 | Sistem Güncellemesi | apt update + upgrade |
| 3 | Paketler | zorunlu (eksikse durur) + opsiyonel (süzülür) |
| 4 | Deploy User | `deploy-user`, SSH key, sudoers + `visudo -c` doğrulaması |
| 5 | SSH Sertleştirme | drop-in yaz → çakışanları yorumla → `sshd -T` doğrula → `ssh.socket` override |
| 6 | fail2ban | `jail.local` `write_managed` ile; 3 deneme → 24h, katlanarak max 168h |
| 7 | UFW | default deny incoming; 3131 · 80 · 443 |
| 8 | Docker | CE + Compose + Buildx; `deploy-user` docker grubuna |
| 9 | Portainer | `/root/portainer/docker-compose.yml`, `127.0.0.1:9443`. Eski `docker run` kurulumu onayla compose'a taşınır |
| 10 | Nginx Proxy Manager | `/root/nginx-proxy-manager/docker-compose.yml`, 80/443 dışa, panel `127.0.0.1:81` |

Adım eklersen `TOTAL_STEPS`'i güncelle.

## Converge Modeli

Script tekrar çalıştırılabilir. Yeni adım eklerken üç sınıftan hangisine girdiğine karar ver:

| Sınıf | Örnek | Davranış |
| --- | --- | --- |
| Koşulsuz uygulanır | SSH drop-in, UFW izinleri, apt paketleri, `usermod -aG` | Her koşuda istenen hale getirilir |
| Varsa eklenmez | root ve deploy SSH key'leri | `grep -qxF`, yoksa eklenir |
| Sorulur | `jail.local`, iki compose dosyası | `write_managed` |

**Sayaçlar ve çıkış kodu.** Banner üç durum ayırır: `SKIPPED>0` → "SAPMALAR UYGULANMADI" ·
`CHANGES=0` → "SUNUCU ZATEN İSTENEN DURUMDA" · aksi halde "KURULUM BAŞARIYLA TAMAMLANDI".

| Kod | Anlam |
| --- | --- |
| `0` | Sunucu istenen durumda |
| `2` | Sapma var, uygulanmadı (onay yok ya da terminal etkileşimsiz) |
| `1` | Hata (`err`) |

CI bu ayrımı okur; değiştirirsen README'deki tabloyu da güncelle.

## SSH Key Kaynağı

Sıra: argüman → env var → interaktif. `SSH_KEY` root, `DEPLOY_KEY` CI/CD içindir;
`DEPLOY_KEY` verilmezse `SSH_KEY`'e düşer. İkisi de regex ile doğrulanır
(`ssh-ed25519` · `ssh-rsa` · `ecdsa-sha2-nistp*` · `ssh-dss`) ve baş/son boşluk ile satır
sonu temizlenir. CI/CD için ayrı key öner: rotasyon kolay, leak halinde insan operatör
etkilenmez.

## Deploy User Politikası

- **Kimlik:** `useradd --create-home --shell /bin/bash deploy-user`, `passwd -l` ile kilitli
- **SSH:** yalnız key auth, `AllowUsers` whitelist'inde
- **Docker:** `docker` grubu üyesi → `docker load/run/stop/rm/image prune` sudo'suz
- **Sudoers:** `/etc/sudoers.d/deploy-user`, NOPASSWD yalnız `journalctl` ve `ufw status`

**Bilinçli trade-off:** docker grubu fiili root yetkisidir (`docker run -v /:/host`). CI/CD'nin
docker'a erişmesi gerektiği için kaçınılmaz. Kazanç: key auth + kullanıcı izolasyonu + root
parola leak'inin etkisizleşmesi.

Sudoers kapsamını genişletme. `apt-get`, `useradd`, `visudo`, `systemctl restart *` gibi
geniş yetkiler eklenmez; gerekirse tek komut olarak whitelist'e yazılır.

## Savunma Satırları

Scriptteki kısa yorumların uzun gerekçesi. Bu satırları "gereksiz" diye sadeleştirmeden önce oku.

| Yer | Satır | Neden orada |
| --- | --- | --- |
| `spinner`, banner | `tput` / `clear` … `\|\| true` | `TERM` tanımsızken ikisi de non-zero döner; `set -e` altında script ilk satırda ölürdü |
| `confirm` | `[ -t 1 ] \|\| return 1` | stdout terminal değilse (CI, nohup, log'a yönlendirme) sorulmaz: nohup'ta `/dev/tty` açılabilir ama okumak SIGTTIN ile süreci durdururdu |
| Key normalizasyonu | `tr -d '\r\n'` | Newline taşıyan bir değer (dosyadan okunmuş secret) `grep -F`'te boş desene dönüşür ve her satırla eşleşirdi |
| Adım 1 | `grep -qxF` | `-F` tek başına alt dize eşler: `from="10/8" ssh-ed25519 AAA…` gibi kısıtlı bir satır key'i içerdiğinde "zaten var" sayılır, eklenmez ve adım 5'ten sonra sunucuya girilemez |
| Adım 5 | `sed -i -E "s/…/#&/I"` üzerinde `I` bayrağı ve `([[:space:]]\|=)` | sshd anahtar kelimeleri harf duyarsızdır ve `PasswordAuthentication=yes` de geçerlidir. Biri kaçarsa drop-in gölgelenir ve doğrulama her koşuda scripti durdurur |
| Adım 5 | `50-cloud-init.conf` yorumlama | sshd bir direktifin **ilk** gördüğü değeri kullanır (alfabetik değil, okuma sırası) ve `Include` en başta. Cloud imajlarındaki drop-in sık sık `PasswordAuthentication yes` taşır |
| Adım 5 | `permitrootlogin` sed'i | OpenSSH 9 `without-password`, OpenSSH 10 `prohibit-password` raporlar; aynı ayar, karşılaştırma öncesi tek isme indirilir |
| Adım 5 | `systemctl restart ssh` çıktısı yakalanır | Susturulursa `set -e` orada öldürür ve "açık oturumunu KAPATMA" uyarısına hiç ulaşılmaz — adımın en değerli çıktısı o uyarı |
| Adım 8 | `gpg --batch --yes` | Bayraksız gpg, hedef dosya varsa `File exists` deyip çıkar; ikinci koşuda dosya hep vardır |
| Adım 9 | compose etiketi kontrolü | `docker run` ile kurulmuş konteynerde compose etiketi yoktur; compose devralamaz, isim çakışır. Yeniden yaratmak kısa kesinti demek, o yüzden sorulur — veri `portainer_data` volume'ünde kalır |
| Özet | `curl -4` | curl varsayılanda IPv6'yı tercih eder; GitHub Actions runner'ları IPv6 ile bağlanamaz. Dış servis düşerse yerel arayüzden okunur |

## Post-Setup Dağıtım

Kullanıcıya dönük tam anlatım README'de ("Docker Container Dağıtım Akışı", "CI/CD Bağlantısı").
Kurallar: değişmez #7 (port yayınlama yok) ve #8 (yalnız `proxy` ağı).

NPM proxy host: **Forward Hostname** = konteyner adı · **Forward Port** = konteynerin **iç**
portu · SSL = Let's Encrypt. Portainer'ın proxy host'unda scheme **HTTPS** (kendi TLS'ini konuşur).

Paneller yalnız loopback'te dinler:
```bash
ssh -p 3131 -L 8181:127.0.0.1:81   root@<IP>   # NPM
ssh -p 3131 -L 9443:127.0.0.1:9443 root@<IP>   # Portainer
```

## Doküman Bakımı

| Değişiklik | Güncellenecek | CI yakalar mı |
| --- | --- | --- |
| Adım ekleme/çıkarma | `TOTAL_STEPS` · bu dosyadaki adım tablosu · README "Ne Kuruyor?" | ✅ `TOTAL_STEPS` |
| Paket ekleme | `PKG_REQUIRED`/`PKG_OPTIONAL` · README paket tablosu | ✅ |
| Port / güvenlik ayarı | README güvenlik tablosu · özet ekranı · bu dosya | ✅ port tutarlılığı |
| Çıkış kodu sözleşmesi | README "Kullanım Yöntemleri" tablosu | ✅ varlık kontrolü |
| Yeni tuzak/gerekçe | Scriptte tek satır yorum + "Savunma Satırları" tablosu | ✅ 4+ satırlık blok reddedilir |

Yorum politikası: scriptte bölüm başlıkları ve **tek satırlık** "ne yapıyor" notları kalır;
"neden" buraya yazılır. `checks.sh` bunu zorlar — 4 veya daha fazla ardışık yorum satırı
CI'yı kırar (banner ve `# ───` başlıkları hariç).

CI yalnızca statik kontrol yapar; scripti çalıştırmaz. Kurulumun gerçekten çalıştığı hâlâ
tek kullanımlık bir sunucuda elle doğrulanır.
