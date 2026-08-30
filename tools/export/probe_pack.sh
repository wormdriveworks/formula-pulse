#!/usr/bin/env bash
# 익스포트 산출물 검침 — G-6 ①(디버그·검증 코드 미포함) · G-7 ①(결제·광고 심볼 0)
#
# **선언이 아니라 산출물을 읽는다.** `export_presets.cfg` 의 필터는 *의도*이고 팩의 내용은
# *결과*다. 검사기(EXP)가 선언을 보고 이 검침기가 결과를 본다 — 두 축이 짝이며, 한쪽만으로는
# "필터를 적었는데 문법이 틀려 아무것도 걸러지지 않은" 상태를 잡지 못한다.
#
# 사용:
#   tools/export/probe_pack.sh <pck 경로> [--verify]
#     기본        = 출시 팩 판정 (검증 코드 0 · 애드온 0 · 결제/광고 심볼 0)
#     --verify    = 검증 팩 판정 (검증 코드는 **있어야** 한다 — 없으면 G-6 방법 ②가 성립하지 않는다)
#
# **exe 는 대상이 아니다** (총괄 판정 IMPL-499 ⑤ — `binary_format/embed_pck=false` 분리 유지).
# 팩이 exe 에 내장되지 않으므로 exe 를 넘기면 **목록 검침이 성립하지 않는다**: 엔진이 적재할
# 팩이 그 안에 없어 열거가 0 이 되고, 그것은 "깨끗하다"가 아니라 "볼 것이 없다"다.
# exe 를 검사하려면 두 갈래로 나눈다 —
#   · 목록 축(검증 코드·애드온·검증 입력) → **함께 배포되는 `.pck` 를 이 스크립트에 넘긴다**
#   · 심볼 축(결제·광고 SDK) → `grep -a -o -E "<토큰>" <exe>` 로 exe 에 직접 건다
#     (실행 파일의 **심볼 테이블** 스캔은 별건이며 TC-P10 의 나머지 절반이다)
#
# **exe 자체가 출시분인지는 두 지문으로 먼저 본다** (IMPL-500 실사고 — 에디터 수동 익스포트가
# 프리셋을 덮어써 출하 디렉토리에 디버그·검증 빌드가 놓였다. 사람이 고른 이름과 실제로 나간
# 프리셋이 갈렸고, 드롭다운 한 칸이 출시물을 검증물로 바꿨다):
#   · **`*.console.exe` 동반 = 디버그 빌드의 표지** — `export_console_wrapper=1` 은 디버그 전용
#     산출이다. 출하 디렉토리에 콘솔 래퍼가 있으면 그것만으로 판별이 선다(가장 값싼 육안 지문).
#   · **템플릿 크기** — 4.7.stable 기준 출시 109,212,160 B / 디버그 103,122,944 B.
# 팩 층 지문(검증 코드·`verify` 피처 태그)은 이 스크립트가 이미 잡는다 — 실제로 그 사고를
# 잡은 것이 `PACK_PROBE_FAIL 출시 팩에 검증 코드 68개` 였다.
#
# 종료코드 0 = 통과. 비0 = 위반(상세는 stdout).
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"

TARGET="${1:-}"
MODE="${2:-}"
if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
	printf 'PACK_PROBE_FAIL 대상 파일이 없다: %s\n' "$TARGET"
	exit 2
fi

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

# ── ① 목록 검침 (엔진이 실제로 담은 것) ──
probe_out=$("$GODOT" --headless --path tools/export/pck_probe --script probe.gd -- \
	"$(realpath "$TARGET")" "$LIST" 2>&1)
if ! printf '%s' "$probe_out" | grep -q "PROBE_OK"; then
	printf '%s\n' "$probe_out"
	printf 'PACK_PROBE_FAIL 팩 적재·열거 실패\n'
	exit 2
fi
printf '%s\n' "$probe_out" | grep "PROBE_OK"

files=$(grep -c '' "$LIST")
# **하한을 둔다** — 팩이 비었는데 "위반 0"이 나오면 그것은 통과가 아니다.
# 검사가 스스로 공허해지는 것을 막는 축은 검사 자신이 져야 한다.
if [ "$files" -lt 400 ]; then
	printf 'PACK_PROBE_FAIL 열거 %d개 — 팩이 비었거나 마운트가 실패했다 (검침 대상 부재)\n' "$files"
	exit 2
fi

fail=0

# ── ② 검증 전용 경로 ──
# `res://tests/` = 스위트·캡처 하네스·TL-5 러너. 출시 빌드에 실리면 D14 §5.6 방법 ①
# ("디버그 결과 표시 코드의 출시 빌드 제거")이 성립하지 않는다.
test_files=$(grep -c 'res://tests/' "$LIST" || true)
if [ "$MODE" = "--verify" ]; then
	if [ "$test_files" -eq 0 ]; then
		printf '  [FAIL] 검증 팩인데 res://tests/ 가 0개 — 하네스 재실행 경로가 없다\n'
		fail=$((fail + 1))
	else
		printf '  [ok] 검증 팩 — res://tests/ %d개 (하네스 재실행 경로 성립)\n' "$test_files"
	fi
else
	if [ "$test_files" -ne 0 ]; then
		printf '  [FAIL] 출시 팩에 검증 코드 %d개\n' "$test_files"
		grep 'res://tests/' "$LIST" | head -5 | sed 's/^/         /'
		fail=$((fail + 1))
	else
		printf '  [ok] 출시 팩 — res://tests/ 0개\n'
	fi
fi

# ── ③ 에디터 애드온 (IMPL-499 ⑥ⓐ) ──
#
# **`.gitignore` 는 리포지토리를 지켰고 팩은 지키지 못했다** — `godot/addons/` 는 커밋되지
# 않지만 작업 트리에는 실재하므로(GDAI 등 MCP 런타임) 익스포트가 그대로 담는다.
# 주력 트리 895 vs 원격 889 의 차 6건이 그것이었다: **커밋을 막는 것과 팩에 담기는 것을
# 막는 것은 다른 일이다.**
addon_files=$(grep -c 'res://addons/' "$LIST" || true)
if [ "$addon_files" -ne 0 ]; then
	printf '  [FAIL] 에디터 애드온 %d개 — 제품 코드가 아니다\n' "$addon_files"
	grep 'res://addons/' "$LIST" | head -5 | sed 's/^/         /'
	fail=$((fail + 1))
elif [ -d godot/addons ]; then
	printf '  [ok] 에디터 애드온 0 (소스 트리에 실재 — 필터가 살아 있다)\n'
else
	# **이 통과는 필터를 증명하지 않는다.** 소스에 없는 것이 팩에 없는 것은 당연하고,
	# 그 당연함이 `[ok]` 로 찍히면 필터가 죽어도 아무도 붉지 않는 상태가 초록으로 보인다.
	# 축은 자기가 공허할 때 그렇다고 말해야 한다.
	printf '  [ok·공허] 에디터 애드온 0 — 소스 트리에 addons/ 가 없어 **필터를 증명하지 않는다**\n'
	printf '           (필터 생존 확인은 애드온이 실재하는 트리에서만 성립한다 — 검사기 EXP 가 선언을 받친다)\n'
fi

# ── ④ 검증 입력 리소스 ──
# 상용한자 표는 GLYPH 스위트의 입력이지 게임 콘텐츠가 아니다 (IMPL-334 ② 이월분).
ref_files=$(grep -ciE 'jouyou|data/reference/' "$LIST" || true)
if [ "$ref_files" -ne 0 ]; then
	printf '  [FAIL] 검증 입력 리소스 %d개\n' "$ref_files"
	grep -iE 'jouyou|data/reference/' "$LIST" | head -5 | sed 's/^/         /'
	fail=$((fail + 1))
else
	printf '  [ok] 검증 입력 리소스 0개\n'
fi

# ── ⑤ 결제·광고 SDK 심볼 (G-7 ① · TC-P10) ──
#
# **벤더·API 고유 토큰만 본다.** 'ad'·'purchase' 같은 일반어를 넣으면 설계상 정당한 것을
# 잡는다 — `IAdService`(D12 §2.2 어댑터 계약)와 `sfx("purchase")`(SE-U07 구매 성사음, 게임 내
# 재화)가 그 실물이다. 오검출은 검사를 끄게 만들므로 여기서는 좁게 잡고, 넓은 축은
# 소스 층(MIX0)이 진다.
SDK_TOKENS='AdMob|GADMobileAds|com\.google\.android\.gms\.ads|AppLovin|UnityAds|IronSource|BillingClient|com\.android\.vending\.billing|StoreKit|SKPayment|in_app_purchase|InAppPurchase|SteamAPI_|ISteamUser|steam_api'
hits=$(grep -a -o -E "$SDK_TOKENS" "$TARGET" 2>/dev/null | sort | uniq -c | sort -rn)
if [ -n "$hits" ]; then
	printf '  [FAIL] 결제·광고 SDK 심볼 검출\n'
	printf '%s\n' "$hits" | sed 's/^/         /'
	fail=$((fail + 1))
else
	printf '  [ok] 결제·광고 SDK 심볼 0\n'
fi

printf '  검침 대상: %s (%s bytes · %d files)\n' \
	"$(basename "$TARGET")" "$(stat -c%s "$TARGET")" "$files"

if [ "$fail" -ne 0 ]; then
	printf '\nPACK_PROBE_FAIL violations=%d\n' "$fail"
	exit 1
fi
printf '\nPACK_PROBE_PASS\n'
