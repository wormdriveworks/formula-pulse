# GP 상태 머신·턴 시퀀스·정산 파이프라인의 코드 상수 (D12 §3 / 불변규칙 3).
# 상태·전이·정산 단계는 데이터가 아닌 코드 상수 — 데이터 층에서의 단계 신설을 구조적으로 차단 (C-2).
class_name RaceTypes
extends RefCounted

# ── GP 상태 머신 (D05 §3 · D12 §3.2 — 1:1, 폐쇄) ──
enum GpState {
	GP_START,
	LAP_LOOP,
	SECTOR_TURN,
	DUEL,
	RETIRE,
	GP_FINISH,
	RESULT,
}

# 전이 표 (코드 상수) — 고아 상태 0 · 미정의 전이 0. 위반 전이는 런타임 에러.
const TRANSITIONS := {
	GpState.GP_START: [GpState.LAP_LOOP],
	GpState.LAP_LOOP: [GpState.SECTOR_TURN, GpState.GP_FINISH],
	GpState.SECTOR_TURN: [GpState.SECTOR_TURN, GpState.DUEL, GpState.RETIRE, GpState.LAP_LOOP],
	GpState.DUEL: [GpState.SECTOR_TURN, GpState.LAP_LOOP, GpState.RETIRE],
	GpState.RETIRE: [GpState.RESULT],
	GpState.GP_FINISH: [GpState.RESULT],
	GpState.RESULT: [],
}

# ── 턴 시퀀스 T1~T6 (D05 §2.3 · D12 §3.3) ──
enum TurnPhase {
	T1_SECTOR_OPEN,
	T2_SPIN,
	T3_PROVISIONAL,
	T4_INTERVENTION,
	T5_TRANSLATE,
	T6_SETTLE,
}

# ── 정산 파이프라인 8단계 고정 (D05 §5.3 · D12 §3.4 — C-2 구속) ──
# ①위험 → ②자원 → ③방어 → ④전진·공략 → ⑤게이지 만충 판정 → ⑥듀얼 발동 → ⑦순위 갱신 → ⑧백그라운드 AI
# 단계 신설·순서 변경·단계의 데이터화 금지.
enum SettleStage {
	STAGE_1_HAZARD,
	STAGE_2_RESOURCE,
	STAGE_3_DEFENSE,
	STAGE_4_ADVANCE,
	STAGE_5_GAUGE_CHECK,
	STAGE_6_DUEL_TRIGGER,
	STAGE_7_RANK_UPDATE,
	STAGE_8_BACKGROUND_AI,
}

const SETTLE_ORDER := [
	SettleStage.STAGE_1_HAZARD,
	SettleStage.STAGE_2_RESOURCE,
	SettleStage.STAGE_3_DEFENSE,
	SettleStage.STAGE_4_ADVANCE,
	SettleStage.STAGE_5_GAUGE_CHECK,
	SettleStage.STAGE_6_DUEL_TRIGGER,
	SettleStage.STAGE_7_RANK_UPDATE,
	SettleStage.STAGE_8_BACKGROUND_AI,
]

# 듀얼 타입
enum DuelType { NONE, OVERTAKE, DEFENSE }

# 심볼 id (테이블 참조용 — 인스턴스 확장은 데이터 드리븐, 분류 6종은 D05 §5.2 확정)
const SYMBOL_SLIPSTREAM := "symbol_slipstream"
const SYMBOL_BRAKING := "symbol_braking"
const SYMBOL_LINE := "symbol_line"
const SYMBOL_PULSE := "symbol_pulse"
const SYMBOL_TROUBLE := "symbol_trouble"
const SYMBOL_CHANCE := "symbol_chance"
