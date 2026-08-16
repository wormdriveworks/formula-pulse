# 기능 컬러 — D10 §2.3 '기능 컬러 면제 조항'의 대상 색군.
#
# D10 §2.3은 마스터 팔레트 56색을 확정하면서 **심볼 이중 부호화 색·게이지 상태색·경고색은
# 접근성 요건이 마스터 팔레트에 우선한다**고 면제했다. 즉 이 색군의 기준은 팔레트 조화가
# 아니라 판별 가능성이며, 그래서 부속 13색은 56색 밖에 산다.
#
# **정본 = `docs/assets/팔레트_정본_v1_0.md` (§9.2 매핑표).** 색값의 소유처는 D13 대장이
# 아니다 — D13 별첨A §8.2 베인 행이 "상태색 = 팔레트 에셋 A-팔레트 소관"으로 명시 위임했고,
# 총괄이 이를 v2.36 ②로 확정했다(D10·D13 개정 0). 따라서 이 파일의 값은 임의 기입이 아니라
# **팔레트 정본의 전사**이며, 상수마다 조달처를 남겨 대조가 성립하게 한다 — IMPL-144.
# 실물 = `godot/assets/palettes/master_56.gpl`(A-팔레트-01) · `colorblind_alt.gpl`(A-팔레트-02).
#
# 조달 규칙 (§9.2):
#   · 접근성 요건 색(타이머·게이지 상태·베인·심볼) = **부속 13색**
#   · 식별 보조색(게이지 방향·바탕·재화·배경·텍스트) = **마스터 56색**
#     — 게이지 방향색은 심볼(브라이트 3단)과 겹치지 않게 **베이스 2단**에서 조달한다.
class_name UiPalette
extends RefCounted

# ── 타이머 3구간 (D09 §3.2 · 경계 비율은 core_params 경유) ──
# 부속 · 게이지 상태 3 (정상/주의/위험)을 그대로 쓴다 — 같은 '상태' 축이라 색을 갈라둘 이유가 없다.
const TIMER_LEEWAY := Color("#3FE0F5")          # 부속 · 게이지 정상
const TIMER_WARNING := Color("#FFBF3D")         # 부속 · 게이지 주의
const TIMER_IMMINENT := Color("#FF4A3D")        # 부속 · 게이지 위험

# ── 배틀 게이지 (D09 §3.4 — 색+방향 이중 부호화, 위치가 1차 단서·색은 보조) ──
const GAUGE_FRONT := Color("#12A6C4")           # 마스터 C2 시안 베이스
const GAUGE_REAR := Color("#C41E7E")            # 마스터 M2 마젠타 베이스
const GAUGE_TRACK := Color("#242A33")           # 마스터 N05

# ── 섀시 컨디션 (D09 §3.4 — 위험 임계 시 경고색) ──
const CHASSIS_OK := Color("#3FE0F5")            # 부속 · 게이지 정상
const CHASSIS_WARN := Color("#FF4A3D")          # 부속 · 게이지 위험

# ── 베인 파형 상태 4종 (D10 §3.3 · D13 별첨A §8.2 위임분) ──
# 손상이 무채인 것은 의도다 — D03 §1.5 "끊기는 노이즈"는 탈색으로 읽는 편이 파형에서 선명하다.
const VANE_NORMAL := Color("#12A6C4")           # 부속 · 베인 평상
const VANE_ALERT := Color("#FF4A3D")            # 부속 · 베인 경고
const VANE_ELATED := Color("#FFD86B")           # 부속 · 베인 고양
const VANE_DAMAGED := Color("#6B7686")          # 부속 · 베인 손상

# ── 심볼 6분류 전용 색 (D10 §5.1 — 색 + 도상 이중 부호화의 색 축) ──
# 판별 실측은 G-2(혼동 행렬 6×6)가 한다 — MS-5 재배치분(D15 v1.1 결정 #12).
const SYMBOL_SLIPSTREAM := Color("#3FE0F5")     # 부속 · 심볼 슬립스트림
const SYMBOL_BRAKING := Color("#FFBF3D")        # 부속 · 심볼 브레이킹
const SYMBOL_LINE := Color("#7BE04A")           # 부속 · 심볼 라인
const SYMBOL_TROUBLE := Color("#FF4A3D")        # 부속 · 심볼 트러블
const SYMBOL_CHANCE := Color("#FF4FB0")         # 부속 · 심볼 찬스
const SYMBOL_PULSE := Color("#BFEFF7")          # 부속 · 심볼 펄스

# ── 재화 2종 (D10 §5.2 — 실루엣이 1차 구분, 색은 보조) ──
const CURRENCY_CREDIT := Color("#D98A12")       # 마스터 A2 앰버 베이스
const CURRENCY_DATA := Color("#3FE0F5")         # 마스터 C3 시안 브라이트

# ── 배경·프레임 (텔레메트리 계기 의장 — D10 §5.4) ──
const BG_DEEP := Color("#080B11")               # 마스터 N01 최심 그림자
const BG_PANEL := Color("#151B22")              # 마스터 N03 화면 바탕
const FRAME_LINE := Color("#424A54")            # 마스터 N08
const TEXT_PRIMARY := Color("#C7D0D8")          # 마스터 N16 본문 텍스트
const TEXT_DIM := Color("#6A737E")              # 마스터 N11

# ── 색각 대체 팔레트 (A-팔레트-02 · 정본 §6 — O9 소비부, IMPL-155) ──
#
# **교체는 정본 §6 표의 4행이 전부다** — "색상만 교체·도상 불변 · 교체는 최소로".
# 위 상수는 기본 팔레트의 전사로 그대로 남긴다(조달처 대조 성립 — IMPL-144).
#
# **hex 가 같다고 함께 바꾸지 않는다.** 교체 단위는 색값이 아니라 **조달 슬롯**이다:
#   · `VANE_ALERT`(부속 · 베인 경고)는 `#FF4A3D` 로 게이지 위험과 같은 값이지만 §6 표에 없다.
#   · `SYMBOL_BRAKING`(부속 · 심볼 브레이킹)은 `#FFBF3D` 로 게이지 주의와 같지만 역시 없다.
# 둘을 함께 바꾸면 정본에 없는 교체를 구현이 만든 것이 된다. **대체 시 두 색군이 갈리는데
# 그것이 의도인지는 에셋 트랙·총괄 확인 대상**으로 발신했다.
const ALT_SYMBOL_LINE := Color("#E8EEF5")       # 정본 §6 · 적록 축 충돌 이탈
const ALT_SYMBOL_TROUBLE := Color("#7A5CFF")    # 정본 §6 · 동상
const ALT_GAUGE_DANGER := Color("#7A5CFF")      # 정본 §6 · 상태색 일관
const ALT_GAUGE_CAUTION := Color("#FFD400")     # 정본 §6 · 위험과의 분리 강화

# 옵션 상태는 소비 시점마다 읽는 것이 원칙(D09 §6.1)이나, 팔레트는 세션을 쥘 수 없는
# 정적 클래스다. 화면 진입과 옵션 변경 두 지점에서 밀어 넣는다 — 그 둘이 O9 가 바뀔 수 있는
# 전부이며, 둘 다 놓치면 화면이 옛 색으로 남는다(옵션 화면이 즉시 반영을 요구한다).
static var colorblind := false


static func apply_options(options: OptionsStore) -> void:
	colorblind = options != null and options.index_of("o9") == 1


# 대체 대상 4슬롯의 조회 창구. 이 4개만 함수이고 나머지는 상수 그대로다 —
# 함수가 있다는 것 자체가 "여기는 O9 로 갈린다"는 표시가 된다.
static func symbol_line() -> Color:
	return ALT_SYMBOL_LINE if colorblind else SYMBOL_LINE


static func symbol_trouble() -> Color:
	return ALT_SYMBOL_TROUBLE if colorblind else SYMBOL_TROUBLE


static func gauge_danger() -> Color:
	return ALT_GAUGE_DANGER if colorblind else TIMER_IMMINENT


static func gauge_caution() -> Color:
	return ALT_GAUGE_CAUTION if colorblind else TIMER_WARNING
