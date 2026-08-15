#!/bin/bash
# Script ile dokümanlar arasındaki tutarlılık kontrolleri.
# CI'da her push/PR'da, lokalde commit öncesi elle çalıştırılır: ./.github/checks.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
FAIL=0
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n     ${DIM}%s${NC}\n" "$1" "$2"; FAIL=1; }

# ─── 1. Adım sayacı gerçek adım sayısıyla eşleşmeli ──────────────────────────
declared=$(awk -F= '/^TOTAL_STEPS=/{print $2}' setup.sh)
actual=$(grep -c '^step_header ' setup.sh)
if [ "$declared" = "$actual" ]; then
  ok "TOTAL_STEPS=${declared}, step_header çağrısı ${actual}"
else
  fail "TOTAL_STEPS=${declared} ama ${actual} adım var" \
       "Adım ekleyip sayacı güncellememişsin; ilerleme göstergesi yanlış sayar."
fi

# ─── 2. SSH portu dokümanlarda aynı olmalı ───────────────────────────────────
port=$(awk '/^Port [0-9]+$/{print $2}' setup.sh)
if [ -z "$port" ]; then
  fail "setup.sh içinde 'Port <n>' bulunamadı" "SSH drop-in'i mi değişti?"
elif grep -q "$port" README.md && grep -q "$port" CLAUDE.md; then
  ok "SSH portu ${port} script ve iki dokümanda tutarlı"
else
  fail "SSH portu ${port} dokümanlarda geçmiyor" \
       "Port değiştiyse README güvenlik tablosu ve CLAUDE.md güncellenmeli."
fi

# ─── 3. Çıkış kodu sözleşmesi belgeli olmalı ─────────────────────────────────
if grep -qi 'çıkış kod' README.md && grep -qi 'çıkış kodu' CLAUDE.md; then
  ok "Çıkış kodu sözleşmesi iki dokümanda da yazılı"
else
  fail "Çıkış kodu sözleşmesi eksik" \
       "0 = istenen durumda, 2 = sapma uygulanmadı, 1 = hata; CI bu ayrımı okur."
fi

# ─── 4. Strict mode ──────────────────────────────────────────────────────────
if grep -q '^set -e$' setup.sh && grep -q '^set -o pipefail$' setup.sh; then
  ok "set -e + set -o pipefail yerinde"
else
  fail "Strict mode eksik" "Script 'set -e' ve 'set -o pipefail' ile çalışmalı."
fi

# ─── 5. Paket listeleri README'de belgeli olmalı ──────────────────────────────
missing_pkg=""
for var in PKG_REQUIRED PKG_OPTIONAL; do
  line=$(grep "^${var}=" setup.sh | cut -d'"' -f2)
  for p in $line; do
    grep -q "\`$p\`" README.md || missing_pkg="$missing_pkg $p"
  done
done
if [ -z "$missing_pkg" ]; then
  ok "Kurulan paketlerin hepsi README tablosunda"
else
  fail "README'de eksik paket:${missing_pkg}" \
       "Paket eklerken README 'Ne Kuruyor?' tablosunu da güncelle."
fi

# ─── 6. Kullanıcının düzenleyebileceği dosyalar write_managed ile yazılmalı ───
direct=$(grep -nE '^[[:space:]]*cat >[^>]' setup.sh \
  | grep -E 'compose|jail\.local' || true)
if [ -z "$direct" ]; then
  ok "Düzenlenebilir dosyalar write_managed ile yazılıyor"
else
  fail "Doğrudan 'cat >' ile yazılan yönetilen dosya var" \
       "$(echo "$direct" | tr '\n' ' ') — kullanıcının değişikliği sessizce geri alınır."
fi

# ─── 7. Yorum politikası: scriptte 4+ ardışık yorum satırı olmamalı ───────────
blocks=$(awk '
  /^[[:space:]]*#/ && !/# ║/ && !/# ───/ && !/^#!/ { n++; if (n == 1) s = NR; next }
  { if (n >= 4) print "satır " s "-" NR-1; n = 0 }
  END { if (n >= 4) print "satır " s "-" NR }
' setup.sh)
if [ -z "$blocks" ]; then
  ok "Yorum blokları kısa (scriptte 'ne', CLAUDE.md'de 'neden')"
else
  fail "Uzun yorum bloğu: $(echo "$blocks" | tr '\n' ' ')" \
       "Gerekçeyi CLAUDE.md 'Savunma Satırları' tablosuna taşı, scriptte tek satır bırak."
fi

echo ""
[ "$FAIL" -eq 0 ] && printf "${GREEN}Tutarlılık kontrolleri geçti.${NC}\n" \
                  || printf "${RED}Tutarlılık kontrolleri başarısız.${NC}\n"
exit "$FAIL"
