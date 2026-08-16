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
