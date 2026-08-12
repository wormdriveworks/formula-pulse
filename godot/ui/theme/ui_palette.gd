# 기능 컬러 — D10 §2.3 '기능 컬러 면제 조항'의 대상 색군.
#
# D10 §2.3은 마스터 팔레트 56색을 확정하면서 **심볼 이중 부호화 색·게이지 상태색·경고색은
# 접근성 요건이 마스터 팔레트에 우선한다**고 면제했다. 즉 이 색군의 기준은 팔레트 조화가
# 아니라 판별 가능성이며, 그래서 팔레트 에셋과 별개 트랙이다.
#
# [가안] 색값 자체는 D13 대장에 없고 D10은 팔레트를 '에셋'으로 규정했는데 실물이 아직 없다.
# 아래 값은 D09 §3.2가 요구하는 삼중 부호화(색+두께+점멸)를 성립시키기 위한 임시값이며,
# 색상환상 서로 떨어진 세 색(청록/황/적)으로 잡아 색각 이상에서도 명도차가 남게 했다.
# **팔레트 에셋(A-팔레트-01/02) 유입 시 전량 교체 대상** — IMPL-071.
class_name UiPalette
extends RefCounted

# ── 타이머 3구간 (D09 §3.2 · 경계 비율은 core_params 경유) ──
const TIMER_LEEWAY := Color(0.35, 0.85, 0.90)   # [가안] 여유 — 텔레메트리 시안
const TIMER_WARNING := Color(0.95, 0.78, 0.25)  # [가안] 경고 — 앰버
const TIMER_IMMINENT := Color(0.95, 0.30, 0.30) # [가안] 임박 — 경고 적

# ── 배틀 게이지 (D09 §3.4 — 색+방향 이중 부호화) ──
const GAUGE_FRONT := Color(0.40, 0.80, 1.00)    # [가안] 전방(추월)
const GAUGE_REAR := Color(1.00, 0.55, 0.35)     # [가안] 후방(피추월)
const GAUGE_TRACK := Color(0.18, 0.19, 0.22)

# ── 섀시 컨디션 (D09 §3.4 — 위험 임계 시 경고색) ──
const CHASSIS_OK := Color(0.55, 0.85, 0.55)     # [가안]
const CHASSIS_WARN := Color(0.95, 0.30, 0.30)   # [가안]

# ── 베인 파형 상태 4종 (D10 §3.3 상태색 — 평상/경고/고양/손상) ──
const VANE_NORMAL := Color(0.45, 0.85, 0.85)    # [가안]
const VANE_ALERT := Color(0.95, 0.35, 0.35)     # [가안]
const VANE_ELATED := Color(0.85, 0.60, 1.00)    # [가안]
const VANE_DAMAGED := Color(0.60, 0.60, 0.62)   # [가안]

# ── 배경·프레임 (텔레메트리 계기 의장 — D10 §5.4) ──
const BG_DEEP := Color(0.07, 0.08, 0.10)
const BG_PANEL := Color(0.11, 0.12, 0.15)
const FRAME_LINE := Color(0.28, 0.32, 0.38)
const TEXT_PRIMARY := Color(0.90, 0.92, 0.95)
const TEXT_DIM := Color(0.55, 0.58, 0.64)
