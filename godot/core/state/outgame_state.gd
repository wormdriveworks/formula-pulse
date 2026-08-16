# 아웃게임 (D06 · D07 · D13 별첨A §3~§5·§7) — 재화·정비·튜닝·오버홀·스킬·크루·스폰서·관계.
#
# 성장 3축은 서로 침범하지 않는다 (D06 §3.2 비중첩 · §5.2 G-M2):
#   회전형(정비·튜닝·소모품) = 스탯·자원 / 축적형(스킬·크루·시설) = **선택지** / 오버홀 = 시즌 경계 변주.
# 개러지 시설이 스탯에 관여하지 않는 것은 이 분리의 이행이다 (D07 §2.2).
#
# 환전 가드 (D06 §4.3): G1 역방향 환전 절대 금지 — **재화로 통제력을 사는 API를 두지 않는다**.
# 가드를 조건문으로 막는 것이 아니라 경로 자체를 만들지 않는 것이 G1의 이행이며,
# 그래서 이 클래스에는 차지·섀시를 재화로 사는 함수가 존재하지 않는다 (D05 §6.1 재봉인).
class_name OutgameState
extends RefCounted

var data: GameData

# 재화 (D06 §1.2 — 회전형 크레딧 / 축적형 주행 데이터)
var credits: int = 0
var drive_data: int = 0

# 진행 상태
var facilities: Dictionary = {}          # facility id -> true
var tuning_steps: Dictionary = {}        # tuning id -> 단계 (0~5)
var overhauls: Array = []                # 장착된 overhaul id
# 시즌 오버홀 후보 추첨 (D06 §5.3 · D13 §7.1) — 결산 직후 1회 추첨 결과를 상태로 보존해
# 재로드 리롤을 무효화한다 (D12 §6.2 취지 승계 — 스트림 저장만으로는 재추첨 자체를 못 막는다).
var overhaul_candidates: Array = []
# 이번 결산에서 장착한 수 — 슬롯 한도의 축은 결산 단위다 (누적 장착 수로 재면
# 시즌 2+에서 슬롯이 영구 소진되는 오류 — 12종 풀은 여러 시즌에 걸쳐 소화된다)
var overhaul_installs_this_season: int = 0
var unlocked_skills: Dictionary = {}     # skill id -> true
var deck: Array = []                     # 편성된 skill id
var deck_slots: int = 0
var crew: Dictionary = {}                # crew id -> true
var sponsor_contracts: Array = []        # sponsor id
var relation_counters: Dictionary = {}   # relation id -> 카운터
var relation_stages: Dictionary = {}     # relation id -> 공표된 단계 (0~3)
var _relation_pending: Dictionary = {}   # relation id -> 도달했으나 미공표 단계
var consumables: Dictionary = {}         # consumable id -> 보유 수
var field_repair_count: int = 0          # 투어 내 정비 회차 (체증 카운터)
# 섀시 컨디션 이월분 (D05 §8 — 투어 관통 생존 자원 · GP 간 자동 완전 회복 없음).
# GP 중에는 엔진이 쥐고, GP 밖에서는 여기가 정본이다 — 세션이 GP 경계에서 양방향 복사한다.
var chassis: float = 0.0
var milestones: Dictionary = {}          # milestone id -> true
# 통산 지표 (D07 §6.2 확정 6종 + 업적 판정 소재). 감소하지 않는다 — 전진형 카운터.
var career_stats: Dictionary = {}        # 지표 키 -> 수치
var achievements: Dictionary = {}        # achievement id -> true (무보상 명예형 — D07 §7.1)
# 달성 시각 축 = **인게임 시즌**(D09 §5.5 칭호 이력 `(시즌 N)` 전례 — 총괄 판정 IMPL-128 A-1).
# 벽시계를 쓰지 않는 이유: 재로드 시 evaluate_achievements()가 현 상태로 재판정해 소급 달성이
# 성립하므로 해제 시각이 실제 달성 시점과 어긋난다. 시즌은 세이브에 있고 되돌아가지 않는다.
# **최초 성립 시점 1회만 적는다(래치)** — 재판정마다 갱신되면 래치가 아니다.
var achievement_seasons: Dictionary = {}  # achievement id -> 달성 시즌 (구세이브 = 부재 → 표기 생략)
var circuits_won: Dictionary = {}        # circuit id -> true (전 서킷 제패 판정)
var discoveries: Dictionary = {}         # 발견형 사건 id -> true (L3 조우 등 — 표현 층이 통지)
# CG-03(동기 — 주드) 조우의 전제 래치: 챔피언십에서 주드를 **처음 앞선** 시점(GP 종료 판정).
# 역전은 GP 결과로 확정되고 듀얼은 GP 진행 중이라, 같은 GP 안에서는 역전 여부가 미확정이다 —
# 그래서 '역전 성립 후 최초의 인접 듀얼'이 유일하게 실행 가능한 해석이다 (총괄 판정 IMPL-128 B-2).
var jude_overtaken: bool = false
var drive_data_earned_total: int = 0     # 베인 단계 판정용 누적 획득 (소비 무차감 — D13 §5.4)


func setup(game_data: GameData) -> void:
	data = game_data
	deck_slots = data.param_int("param_deck_slots_start")
	# [가안] 새 커리어 섀시 초기값 = 최대치 (D13에 별도 항목 부재 — 새 머신은 온전하다)
	chassis = data.param("param_chassis_max")
	# 크루 2인(마르타·테오)은 시작 합류 — 영입 단가 0 (D07 §5.2 영입 2단 구조의 1단)
	for crew_id in data.crew:
		if CsvTable.to_int(String(data.crew[crew_id]["recruit_dp"])) == 0:
			crew[crew_id] = true


# ── 재화 ──
func gain_credits(amount: int) -> void:
	credits += maxi(amount, 0)


func gain_drive_data(amount: int) -> void:
	var gained := maxi(amount, 0)
	drive_data += gained
	drive_data_earned_total += gained


func _spend_credits(amount: int) -> bool:
	if amount < 0 or credits < amount:
		return false
	credits -= amount
	return true


func _spend_drive_data(amount: int) -> bool:
	if amount < 0 or drive_data < amount:
		return false
	drive_data -= amount
	return true


# ── 환전 (D06 §4.1·§4.3 · D13 별첨A §2.2) ──
# G2 상한 = 5차지 · G4 완주 조건 · G3 환전율은 데이터 전속.
# 반환: 지급 크레딧 (0 = 미지급).
func exchange_charge(remaining_charge: int, tour_finished: bool) -> int:
	if not tour_finished:
		return 0    # G4 — 탈락 시 미지급 (D06 §2.4 일관성)
	var cap := data.param_int("param_charge_exchange_cap")
	var rate := data.param_int("param_charge_exchange_cr")
	var exchanged := clampi(remaining_charge, 0, cap)   # G2
	var payout := exchanged * rate                      # G3 — 환전율은 데이터 값
	gain_credits(payout)
	return payout


# ── 정비 (D06 §3.3 · D13 별첨A §3.4) ──
# 필드 정비: 회당 상한 30 CH · 회차 체증 1.5^(n−1) · 체증 카운터는 투어 개시에 리셋.
func field_repair_cost(season_rank_mod: int = 0) -> int:
	return _field_repair_cost_at(field_repair_count, season_rank_mod)


# 다음 회차 비용 — D07 §3.3·D09 §4.3이 **사전 표시를 필수**로 요구하는 값이다
# ("지금 정비할 것인가"라는 의사결정의 성립 조건). 표시 전용이며 체증 카운터를 건드리지 않는다.
func field_repair_cost_next(season_rank_mod: int = 0) -> int:
	return _field_repair_cost_at(field_repair_count + 1, season_rank_mod)


func _field_repair_cost_at(count: int, season_rank_mod: int) -> int:
	var base := data.param("param_repair_base_cr") \
		* (1.0 + data.param("param_repair_season_rank_coef") * float(season_rank_mod))
	var escalated := base * pow(data.param("param_repair_escalation"), float(count))
	return int(round(escalated * _repair_cost_ratio()))


func _repair_cost_ratio() -> float:
	# 테오 패시브 −10% (D13 별첨A §5.1)
	if crew.has("crew_theo"):
		return 1.0 + CsvTable.to_float(String(data.crew["crew_theo"]["passive_value"]))
	return 1.0


# 반환: 실제 회복량 (0 = 실패 또는 회복 여지 없음 — 이때는 지불·체증 카운터 무변경).
# 회당 상한(30 CH) 절단 + **무상 복원선 초과 구간 진입 불가** — 그 구간의 유일 수단은
# 전면 정비다 (D07 §3.3 명문 "투어 개시 무상 복원선 70% 초과 구간의 유일 수단").
func field_repair(requested_ch: int, season_rank_mod: int = 0) -> int:
	var recoverable := _field_repair_recoverable(requested_ch)
	if recoverable <= 0.0:
		return 0
	var cost := field_repair_cost(season_rank_mod)
	if not _spend_credits(cost):
		return 0
	field_repair_count += 1
	chassis += recoverable
	return int(round(recoverable))


# 필드 정비 프리뷰 — 실행 시 도달할 섀시 값 (표시 전용 · §A-9 E02 회복 고스트 게이지의 성립 조건).
# field_repair()와 절단 계산을 공유하므로 표시와 실행이 갈라질 수 없다. 지불 판정은 비대상 —
# 지불 가능 여부는 버튼 활성이 별도로 본다 (고스트는 "하면 어디까지 가는가"만 답한다).
func field_repair_preview(requested_ch: int) -> float:
	return chassis + _field_repair_recoverable(requested_ch)


func _field_repair_recoverable(requested_ch: int) -> float:
	var capped := minf(float(maxi(requested_ch, 0)), data.param("param_repair_field_cap"))
	return maxf(minf(capped, float(free_restore_line()) - chassis), 0.0)


func begin_tour() -> void:
	field_repair_count = 0    # 체증 카운터 리셋 = 투어 개시 (D13 별첨A §3.4 R2)
	# 무상 복원선 — 투어 개시 시 복원선까지 무상 복원, 이미 그 위면 그대로 (D06 §3.3 결정 #12)
	chassis = maxf(chassis, float(free_restore_line()))


# 전면 정비 비용 조회 — 표시 전용 (D09 §4.3 비용 표시 · field_repair_cost_next와 같은 구조)
func full_repair_cost() -> int:
	var missing := maxf(data.param("param_chassis_max") - chassis, 0.0)
	var per_ch := data.param("param_repair_full_cr_per_ch") * _repair_cost_ratio()
	return int(round(per_ch * missing))


# 전면 정비: 20 Cr / 1 CH · 상한 없음 — 완전 회복 (D13 별첨A §3.4).
# 반환: 실제 회복량 (0 = 실패 또는 이미 만충).
func full_repair() -> int:
	var maximum := data.param("param_chassis_max")
	var missing := maxf(maximum - chassis, 0.0)
	if missing <= 0.0:
		return 0
	if not _spend_credits(full_repair_cost()):
		return 0
	chassis = maximum
	return int(round(missing))


# 이벤트 회복 (D06 §3.4 — 무상·확률적·페이싱, 인스턴스 D08 풀).
# 경제 가드: 무상 이벤트 회복은 필드 정비의 회당 상한을 초과할 수 없다 (D06 §3.4 명문).
# [가안] 복원선 절단은 걸지 않는다 — 가드 조항이 회당 상한만 명시하므로 최대치 절단만 적용.
func event_chassis_recover(amount: int) -> int:
	var capped := minf(float(maxi(amount, 0)), data.param("param_repair_field_cap"))
	var applied := minf(capped, data.param("param_chassis_max") - chassis)
	if applied <= 0.0:
		return 0
	chassis += applied
	return int(round(applied))


func free_restore_line() -> int:
	# 투어 개시 무상 복원선 70 CH — OV-S4 장착 시 80 (D13 별첨A §7.2)
	var line := data.param_int("param_repair_free_restore_line")
	for overhaul_id in overhauls:
		var row := data.overhaul(String(overhaul_id))
		if String(row.get("effect", "")) == "free_restore_line":
			line = CsvTable.to_int(String(row["effect_value"]))
	return line


# ── 튜닝 (D06 §3.2 회전형 · D13 별첨A §3.5) ──
func tuning_step(tuning_id: String) -> int:
	return int(tuning_steps.get(tuning_id, 0))


func tuning_cost(tuning_id: String, step: int) -> int:
	var row := data.tuning_line(tuning_id)
	if row.is_empty() or step < 1 or step > data.param_int("param_tuning_max_step"):
		return -1
	return CsvTable.to_int(String(row["cost%d" % step]))


func buy_tuning(tuning_id: String) -> bool:
	var next_step := tuning_step(tuning_id) + 1
	var cost := tuning_cost(tuning_id, next_step)
	if cost < 0 or not _spend_credits(cost):
		return false
	tuning_steps[tuning_id] = next_step
	return true


# 재배분 환급률 80% · 마르타 패시브 시 90% (D13 별첨A §3.5·§5.1)
func tuning_refund_ratio() -> float:
	if crew.has("crew_marta"):
		return CsvTable.to_float(String(data.crew["crew_marta"]["passive_value"]))
	return data.param("param_tuning_refund_ratio")


func redistribute_tuning(tuning_id: String) -> int:
	var step := tuning_step(tuning_id)
	if step <= 0:
		return 0
	var spent := 0
	for index in range(1, step + 1):
		spent += tuning_cost(tuning_id, index)
	tuning_steps[tuning_id] = 0
	var refund := int(round(float(spent) * tuning_refund_ratio()))
	gain_credits(refund)
	return refund


# ── 오버홀 (D06 §5.3 · D13 별첨A §7.1~§7.3) ──
func overhaul_slots(championship_rank: int) -> Dictionary:
	for row_id in data.overhaul_slots:
		var row: Dictionary = data.overhaul_slots[row_id]
		if championship_rank >= CsvTable.to_int(String(row["rank_min"])) \
			and championship_rank <= CsvTable.to_int(String(row["rank_max"])):
			return {"slots": CsvTable.to_int(String(row["slots"])),
				"candidates": CsvTable.to_int(String(row["candidates"]))}
	push_error("OutgameState: no overhaul slot row for rank %d" % championship_rank)
	return {}


# 시즌 오버홀 후보 추첨 (D06 §5.3 · D13 §7.1~7.2) — 시즌 결산 직후 1회, 세션이 부른다.
# 스트림 = reserve [가안 — D12 §6.1 예비 스트림의 첫 소비처. 릴·셔플·레조넌스와 채널 분리 유지].
# 풀 = 전 인스턴스 − 기장착 (선택하지 않은 후보는 소멸하되 다음 시즌 풀에 재등장 — D06 §5.3).
func draw_overhaul_candidates(championship_rank: int, rng: RngService) -> Array:
	var slots := overhaul_slots(championship_rank)
	overhaul_installs_this_season = 0
	overhaul_candidates = []
	if slots.is_empty():
		return []
	var pool: Array = []
	for overhaul_id in data.overhauls:
		if not overhauls.has(String(overhaul_id)):
			pool.append(String(overhaul_id))
	pool.sort()   # 추첨의 결정성 — 데이터 적재 순서 의존 제거
	var count := mini(int(slots["candidates"]), pool.size())
	for i in range(count):
		overhaul_candidates.append(pool.pop_at(rng.stream("reserve").randi_range(0, pool.size() - 1)))
	return overhaul_candidates.duplicate()


func install_overhaul(overhaul_id: String, championship_rank: int) -> bool:
	var slots := overhaul_slots(championship_rank)
	if slots.is_empty() or overhaul_installs_this_season >= int(slots["slots"]):
		return false
	if data.overhaul(overhaul_id).is_empty() or overhauls.has(overhaul_id):
		return false
	# 선택은 제시된 후보에서만 (D06 §5.3). 후보 미추첨 상태(구세이브·개발 진입)는 통과 —
	# 추첨이 돈 순간부터 가드가 선다.
	if not overhaul_candidates.is_empty() and not overhaul_candidates.has(overhaul_id):
		return false
	overhauls.append(overhaul_id)
	overhaul_installs_this_season += 1
	return true


# G-M2 캡 (D13 별첨A §7.3 — 구속): 파츠 계열의 계통당 +10%p · 합산 +20%p 절단.
# 오버홀의 스탯 기여를 튜닝의 종속 규모로 묶는 조항이므로 절단은 여기서 강제한다.
func parts_stat_bonus(target: String) -> float:
	var per_line_cap := data.param("param_parts_cap_per_line")
	var total_cap := data.param("param_parts_cap_total")
	var line_total := 0.0
	var all_total := 0.0
	for overhaul_id in overhauls:
		var row := data.overhaul(String(overhaul_id))
		if String(row.get("kind", "")) != "part":
			continue
		var value := CsvTable.to_float(String(row["effect_value"]))
		if String(row["effect"]) == target:
			line_total += value
		all_total += value
	return minf(minf(line_total, per_line_cap), total_cap - maxf(all_total - line_total, 0.0))


# ── 스킬·덱 (D07 §4 · D13 별첨A §4.1~§4.3) ──
# 스킬 티어 개방 = 마일스톤 연동(무비용) / 티어 내 개별 해금 = 주행 데이터 자유 구매.
func skill_tier_open(skill_tier: int) -> bool:
	match skill_tier:
		1:
			return true
		2:
			return milestones.has("milestone_first_podium")
		3:
			return milestones.has("milestone_first_gp_win")
	return false


func unlock_cost(base_dp: int) -> int:
	# 사샤 패시브 −10% (D13 별첨A §5.1 · D07 §4.3)
	if crew.has("crew_sasha"):
		var ratio := CsvTable.to_float(String(data.crew["crew_sasha"]["passive_value"]))
		return int(round(float(base_dp) * (1.0 + ratio)))
	return base_dp


func unlock_skill(skill_id: String) -> bool:
	var row := data.skill(skill_id)
	if row.is_empty() or unlocked_skills.has(skill_id):
		return false
	if not skill_tier_open(CsvTable.to_int(String(row["skill_tier"]))):
		return false
	if not _spend_drive_data(unlock_cost(CsvTable.to_int(String(row["unlock_dp"])))):
		return false
	unlocked_skills[skill_id] = true
	return true


func expand_deck() -> bool:
	var maximum := data.param_int("param_deck_slots_max")
	if deck_slots >= maximum:
		return false
	var index := deck_slots - data.param_int("param_deck_slots_start") + 1
	var cost := data.param_int("param_deck_expand_dp%d" % index)
	if not _spend_drive_data(unlock_cost(cost)):
		return false
	deck_slots += 1
	return true


func set_deck(skill_ids: Array) -> bool:
	if skill_ids.size() > deck_slots:
		return false
	for skill_id in skill_ids:
		if not unlocked_skills.has(String(skill_id)):
			return false
	deck = skill_ids.duplicate()
	return true


# ── 크루 (D07 §5.2 영입 2단 구조) ──
func recruit_crew(crew_id: String) -> bool:
	if not data.crew.has(crew_id) or crew.has(crew_id):
		return false
	var cost := CsvTable.to_int(String(data.crew[crew_id]["recruit_dp"]))
	if not _spend_drive_data(unlock_cost(cost)):
		return false
	crew[crew_id] = true
	return true


# ── 스폰서 (D07 §5.4 · D13 별첨A §5.3) ──
func sponsor_slots() -> int:
	if facilities.has("facility_g4"):
		return data.param_int("param_sponsor_slots_with_g4")
	return data.param_int("param_sponsor_slots_base")


func sponsor_candidate_count() -> int:
	# 나디아 패시브: 후보 3종 → 4종 (D13 별첨A §5.1)
	if crew.has("crew_nadia"):
		return CsvTable.to_int(String(data.crew["crew_nadia"]["passive_value"]))
	return 3


func sign_sponsor(sponsor_id: String) -> bool:
	if not data.sponsors.has(sponsor_id) or sponsor_contracts.has(sponsor_id):
		return false
	if sponsor_contracts.size() >= sponsor_slots():
		return false
	sponsor_contracts.append(sponsor_id)
	return true


# 투어 단위 갱신 — 정기 수입 + 조건 충족 보너스 (D13 별첨A §5.3)
func settle_sponsors(conditions_met: Dictionary) -> int:
	var payout := 0
	for sponsor_id in sponsor_contracts:
		var row: Dictionary = data.sponsors[sponsor_id]
		payout += CsvTable.to_int(String(row["regular_cr"]))
		if bool(conditions_met.get(String(row["condition"]), false)):
			payout += CsvTable.to_int(String(row["bonus_cr"]))
	gain_credits(payout)
	return payout


# ── 관계 카운터 (D07 §5.5 · D12 §5.2 형식 B · D13 별첨A §5.2) ──
# 카운터는 감소하지 않는다 — 감산 API를 두지 않는 것이 구조 보장이다 (D12 §5.2 명문).
# 임계 도달은 상시 판정하되 **공표는 대회 경계 스냅**으로 지연 커밋한다.
func add_relation(relation_id: String, amount: int = 1) -> void:
	if data.relation_axis(relation_id).is_empty():
		return
	if amount <= 0:
		return
	relation_counters[relation_id] = int(relation_counters.get(relation_id, 0)) + amount
	var reached := _reached_stage(relation_id)
	if reached > int(relation_stages.get(relation_id, 0)):
		_relation_pending[relation_id] = reached


func _reached_stage(relation_id: String) -> int:
	var row: Dictionary = data.relation_axes[relation_id]
	var counter := int(relation_counters.get(relation_id, 0))
	var stage := 0
	for index in [1, 2, 3]:
		if counter >= CsvTable.to_int(String(row["threshold%d" % index])):
			stage = index
	return stage


func pending_relation_transitions() -> Dictionary:
	return _relation_pending.duplicate()


# 대회 경계 스냅 — 여기서만 상태가 공표된다 (레이스 중 톤 급변 방지, D07 §5.5)
func commit_relation_transitions() -> Array:
	var committed: Array = []
	for relation_id in _relation_pending:
		relation_stages[relation_id] = int(_relation_pending[relation_id])
		committed.append(relation_id)
	_relation_pending.clear()
	return committed


func relation_stage(relation_id: String) -> int:
	return int(relation_stages.get(relation_id, 0))


# ── 시설 (D07 §2.2 — 선택지·편의 전용) ──
func unlock_facility(facility_id: String) -> bool:
	var row := data.facility(facility_id)
	if row.is_empty() or facilities.has(facility_id):
		return false
	var requires := String(row["requires_crew"]).strip_edges()
	if requires != "" and not crew.has(requires):
		return false
	if not _spend_drive_data(unlock_cost(CsvTable.to_int(String(row["cost_dp"])))):
		return false
	facilities[facility_id] = true
	return true


# 아카이브는 무상·상시이며 게이트 표시가 없다 (D07 §6.3 · D09 §4.5 — R-D07-VN).
# 시설 해금과 무관하게 항상 true를 돌려주는 것이 그 구속의 이행이다.
func archive_available() -> bool:
	return true


# ── 소모품 (D06 §3.5 · D13 별첨A §3.6) ──
func buy_consumable(consumable_id: String) -> bool:
	if not data.consumables.has(consumable_id):
		return false
	var carried := 0
	for held in consumables:
		carried += int(consumables[held])
	if carried >= data.param_int("param_consumable_carry_cap"):
		return false
	if not _spend_credits(CsvTable.to_int(String(data.consumables[consumable_id]["cost_cr"]))):
		return false
	consumables[consumable_id] = int(consumables.get(consumable_id, 0)) + 1
	return true


# ── 통산 지표·마일스톤·업적 (D07 §6.2·§7.1 · D08 §8.2·§8.11) ──
# 업적은 **무보상 명예형**이다 (D07 §7.1) — 달성 처리가 재화·아이템을 지급하지 않는다.
# 지급 경로를 두지 않는 것이 D06 Source 전수(S1~S10) 무개정의 이행이다.
func career_stat(key: String) -> int:
	return int(career_stats.get(key, 0))


func _bump_stat(key: String, amount: int = 1) -> void:
	career_stats[key] = career_stat(key) + amount


# 그랑프리 결과 반영 — 세션이 GP 종료 시 1회 부른다 (D08 §8.2 시스템 층 = 달성 즉시).
# 결과 사전은 엔진 산출 그대로이며 업적 규칙은 엔진에 들어가지 않는다.
func record_gp_result(result: Dictionary) -> void:
	var rank := int(result.get("player_rank", 16))
	var retired := bool(result.get("player_retired", false))
	_bump_stat("gps")
	if not retired:
		_bump_stat("finishes")
		if rank <= 1:
			_bump_stat("wins")
			var circuit_id := String(result.get("circuit_id", ""))
			if circuit_id != "":
				circuits_won[circuit_id] = true
			if int(result.get("hold_uses", -1)) == 0:
				_bump_stat("no_intervention_wins")
			var entry_rank := int(result.get("final_lap_entry_rank", 0))
			if entry_rank > 1:
				_bump_stat("final_lap_comebacks")
		if rank <= 3:
			_bump_stat("podiums")
		if int(result.get("trouble_turns", -1)) == 0:
			_bump_stat("clean_gps")
	_bump_stat("duel_wins", int(result.get("duel_wins", 0)))
	_bump_stat("duels", int(result.get("duels", 0)))
	_bump_stat("chance_three_matches", int(result.get("chance_three_matches", 0)))
	career_stats["circuits_won"] = circuits_won.size()
	# 필패 그랑프리에서 P2 = 발견형 '왕좌의 코앞' (D08 §8.11 (H))
	if bool(result.get("scripted_loss", false)) and rank == 2:
		_bump_stat("scripted_loss_p2")
	# 리타이어한 GP는 순위 기반 마일스톤의 대상이 아니다 — 완주가 성적의 전제다
	# (D05 §9.2 리타이어 = 1층 포인트 0과 같은 취지). 0 = 판정 불성립 표기.
	_record_milestones({"gp_rank": 0 if retired else rank, "gp_finish": 0 if retired else 1,
		"beaten_rivals": result.get("beaten_rivals", [])})


func record_tour_result(summary: Dictionary) -> void:
	var position := int(summary.get("player_position", 16))
	if position <= 1:
		_bump_stat("tour_wins")
	# 투어 4전 전승 = 그랜드 슬램 (D08 §8.11). 전승 임계는 캘린더 구조값을 그대로 쓴다 —
	# 코어 파라미터에 4를 다시 적으면 캘린더와 갈라질 수 있는 이중 정의가 된다.
	var races_per_tour := int(data.season_calendar.get("races_per_tour", 0))
	if races_per_tour > 0 and int(summary.get("gp_wins", 0)) >= races_per_tour:
		_bump_stat("tour_sweeps")
	_record_milestones({"tour_rank": position})


func record_season_result(report: Dictionary) -> void:
	_bump_stat("seasons")
	var position := int(report.get("player_position", 16))
	var best := career_stat("best_championship_rank")
	if best == 0 or position < best:
		career_stats["best_championship_rank"] = position
	if bool(report.get("epilogue", false)):
		career_stats["epilogue_reached"] = 1
	var tours_per_season := int(data.season_calendar.get("tours_per_season", 0))
	if tours_per_season > 0 and int(report.get("tour_wins", 0)) >= tours_per_season:
		_bump_stat("season_sweeps")   # 시즌 5투어 전승 = 퍼펙트 시즌 (D08 §8.11)
	_record_milestones({"season_champion": 1 if String(report.get("champion", "")) == SeasonState.PLAYER_ID else 0})


# 발견형 사건 통지 — 표현 층(L3 컷인 재생 등)이 발생 사실만 넘긴다.
func record_discovery(discovery_id: String) -> void:
	discoveries[discovery_id] = true


# 마일스톤 판정 (D08 §8.2 마스터 표 — 조건은 전량 데이터).
# 달성은 되돌아가지 않는다: 한 번 켜진 플래그를 끄는 경로를 두지 않는다.
func _record_milestones(context: Dictionary) -> void:
	for milestone_id in data.milestones:
		if milestones.has(milestone_id):
			continue
		var row: Dictionary = data.milestones[milestone_id]
		if not _milestone_met(row, context):
			continue
		milestones[String(milestone_id)] = true
		# S5 마일스톤 보상 (D06 §2.1 Source 대장 · D13 별첨A §3.3) — 축적형 주 수입.
		# 달성 즉시 지급 (D08 §8.1 시스템 층 = 마일스톤 달성 즉시).
		gain_drive_data(CsvTable.to_int(String(row.get("reward_dp", "0"))))
		# 네임드 첫 선착 누계 — 라이벌 파일 개방 축 (D07 §6.1 "네임드 8인 전속").
		# 같은 라이벌을 가리키는 마일스톤이 둘 있다(로렌츠 = 첫 선착 + 첫 격파 — D08 §8.2)
		# 이므로 **라이벌 단위로 1회만** 센다. 파일은 인물당 하나다.
		if String(row["source"]) == "beat_rival" \
			and not _rival_already_counted(String(row["source_id"]), String(milestone_id)):
			_bump_stat("named_beats")


func _rival_already_counted(rival_id: String, exclude_milestone_id: String) -> bool:
	for milestone_id in milestones:
		if String(milestone_id) == exclude_milestone_id:
			continue
		var row: Dictionary = data.milestones.get(milestone_id, {})
		if String(row.get("source", "")) == "beat_rival" \
			and String(row.get("source_id", "")) == rival_id:
			return true
	return false


func _milestone_met(row: Dictionary, context: Dictionary) -> bool:
	var source := String(row["source"])
	var threshold := CsvTable.to_int(String(row["threshold"]))
	match source:
		"gp_rank", "tour_rank":
			# 순위는 작을수록 상위다 — 임계 '이내'로 판정한다 (D08 §8.2 "P8 이내" 문면)
			var rank := int(context.get(source, 0))
			return rank > 0 and rank <= threshold
		"gp_finish", "season_champion":
			return int(context.get(source, 0)) >= threshold
		"beat_rival":
			return Array(context.get("beaten_rivals", [])).has(String(row["source_id"]))
		_:
			push_error("OutgameState: unknown milestone source '%s'" % source)
			return false


# 업적 판정 (D08 §8.11 · D07 §7.1) — 상태를 평가만 한다. 반환 = 이번에 새로 달성한 id 목록.
# 판정 소스가 아직 결선되지 않은 업적(관계 축 미생성 등)은 조용히 미달성으로 두지 않고
# pending_achievements()로 셀 수 있게 한다 — "영원히 안 켜지는 업적"을 계수로 드러내기 위함.
# `season` = 달성 시각 축(인게임 시즌). 0 이면 기록하지 않는다 — 시즌 문맥 없이 부른
# 호출부(단위 검사·구경로)가 0 을 남기면 표기가 "시즌 0"이 되므로 아예 적지 않는다.
func evaluate_achievements(season: int = 0) -> Array:
	var newly: Array = []
	for achievement_id in data.achievements:
		if achievements.has(achievement_id):
			continue
		var row: Dictionary = data.achievements[achievement_id]
		if _achievement_source_missing(row):
			continue
		if _achievement_met(row):
			achievements[String(achievement_id)] = true
			if season > 0:
				achievement_seasons[String(achievement_id)] = season
			newly.append(String(achievement_id))
	return newly


# 판정 소스가 데이터에 없는 업적 — 결선 대기분의 명시적 계수 (조용한 미달성 방지)
func pending_achievements() -> Array:
	var pending: Array = []
	for achievement_id in data.achievements:
		if _achievement_source_missing(data.achievements[achievement_id]):
			pending.append(String(achievement_id))
	return pending


# 업적 1건의 진척 조회 (표시 전용) — SYS-04 업적 화면의 '조건' 축 (D09 별첨A §A-4).
# **판정과 같은 계산을 쓴다** — `_achievement_met()` 이 여기 반환값을 그대로 임계와 비교하므로
# 표시와 판정이 갈라질 수 없다 (IMPL-100 `field_repair_preview` 와 같은 구조).
# 상태 변경 없음 — 조회만 한다.
func achievement_progress(achievement_id: String) -> Dictionary:
	if not data.achievements.has(achievement_id):
		push_error("OutgameState: unknown achievement '%s'" % achievement_id)
		return {"current": 0, "threshold": 0, "met": false, "pending": false}
	var row: Dictionary = data.achievements[achievement_id]
	return {
		# 미지 소스 표식(-1)은 표시에 내보내지 않는다 — 판정 쪽만 그 값을 본다.
		"current": maxi(_achievement_current(row), 0),
		"threshold": CsvTable.to_int(String(row["threshold"])),
		"met": achievements.has(achievement_id),
		"pending": _achievement_source_missing(row),
		# 달성 시즌 — 0 = 미달성이거나 구세이브 소급분(표기 생략 대상)
		"season": int(achievement_seasons.get(achievement_id, 0)),
	}


func _achievement_source_missing(row: Dictionary) -> bool:
	if String(row["source"]) == "relation":
		return not data.relation_axes.has(String(row["source_id"]))
	return false


func _achievement_met(row: Dictionary) -> bool:
	return _achievement_current(row) >= CsvTable.to_int(String(row["threshold"]))


# 업적 조건의 현재값. **미지 소스는 -1** 을 돌려 어떤 임계와 비교해도 미달이 되게 한다
# (0 을 돌리면 임계 0 인 데이터가 들어왔을 때 미지 소스가 '달성'으로 통과한다).
func _achievement_current(row: Dictionary) -> int:
	var source := String(row["source"])
	var source_id := String(row["source_id"])
	match source:
		"milestone":
			return 1 if milestones.has(source_id) else 0
		"career_stat":
			return career_stat(source_id)
		"relation":
			return relation_stage(source_id)
		"discovery":
			return 1 if discoveries.has(source_id) else 0
		"state":
			return _achievement_state_value(source_id)
		_:
			push_error("OutgameState: unknown achievement source '%s'" % source)
			return -1


func _achievement_state_value(key: String) -> int:
	match key:
		"crew_count":
			return crew.size()
		"skill_count":
			return unlocked_skills.size()
		"deck_slots":
			return deck_slots
		"facility_count":
			return facilities.size()
		_:
			push_error("OutgameState: unknown achievement state key '%s'" % key)
			return 0


# ── 결산 보상 (D13 별첨A §3.1~§3.2) ──
# S1 그랑프리 상금 = 300 + 투어 포인트 × 100 (D13 별첨A §3.1).
# S2 완주 보너스 200은 **별개 Source**다 — 합산해 두면 어느 축이 바뀌었는지 추적할 수 없다.
func gp_prize(tour_points: int, finished: bool) -> int:
	if not finished:
		return 0   # 리타이어 시 S1 = 0 (D13 별첨A §3.1)
	return data.param_int("param_prize_base_cr") \
		+ tour_points * data.param_int("param_prize_per_tour_point_cr")


# S2 완주 보너스 — P9 이하 포함 지급 · 리타이어 시 0 (D13 별첨A §3.1)
func finish_bonus(finished: bool) -> int:
	return data.param_int("param_finish_bonus_cr") if finished else 0


func settlement_reward(scope: String, rank: int) -> Dictionary:
	for row_id in data.settlement_rewards:
		var row: Dictionary = data.settlement_rewards[row_id]
		if String(row["scope"]) != scope:
			continue
		if rank >= CsvTable.to_int(String(row["rank_min"])) and rank <= CsvTable.to_int(String(row["rank_max"])):
			return {"credits": CsvTable.to_int(String(row["credits"])), "dp": CsvTable.to_int(String(row["dp"]))}
	push_error("OutgameState: no %s reward row for rank %d" % [scope, rank])
	return {}


# 베인 3단계 — 판정은 축적형 **누적 획득 총량** (소비 무차감 — D13 별첨A §5.4)
func vane_stage() -> int:
	if drive_data_earned_total >= data.param_int("param_vane_stage3_dp"):
		return 3
	if drive_data_earned_total >= data.param_int("param_vane_stage2_dp"):
		return 2
	return 1


func serialize() -> Dictionary:
	return {
		"credits": credits, "drive_data": drive_data,
		"drive_data_earned_total": drive_data_earned_total,
		"facilities": facilities.duplicate(), "tuning_steps": tuning_steps.duplicate(),
		"overhauls": overhauls.duplicate(), "unlocked_skills": unlocked_skills.duplicate(),
		"overhaul_candidates": overhaul_candidates.duplicate(),
		"overhaul_installs_this_season": overhaul_installs_this_season,
		"deck": deck.duplicate(), "deck_slots": deck_slots,
		"crew": crew.duplicate(), "sponsor_contracts": sponsor_contracts.duplicate(),
		"relation_counters": relation_counters.duplicate(),
		"relation_stages": relation_stages.duplicate(),
		"relation_pending": _relation_pending.duplicate(),
		"consumables": consumables.duplicate(),
		"field_repair_count": field_repair_count,
		"milestones": milestones.duplicate(),
		"career_stats": career_stats.duplicate(),
		"achievements": achievements.duplicate(),
		"achievement_seasons": achievement_seasons.duplicate(),
		"circuits_won": circuits_won.duplicate(),
		"jude_overtaken": jude_overtaken,
		"discoveries": discoveries.duplicate(),
		"chassis": chassis,
	}


func restore(payload: Dictionary) -> bool:
	for key in ["credits", "drive_data", "facilities", "tuning_steps", "overhauls",
			"unlocked_skills", "deck", "deck_slots", "crew", "relation_counters"]:
		if not payload.has(key):
			push_error("OutgameState: malformed payload (missing '%s')" % key)
			return false
	credits = int(payload["credits"])
	drive_data = int(payload["drive_data"])
	drive_data_earned_total = int(payload.get("drive_data_earned_total", 0))
	facilities = payload["facilities"]
	tuning_steps = payload["tuning_steps"]
	overhauls = payload["overhauls"]
	# 후보 추첨 도입(T3) 전 세이브에는 없다 — 빈 후보 = 가드 비활성(구세이브 관용)이 충실값
	overhaul_candidates = payload.get("overhaul_candidates", [])
	overhaul_installs_this_season = int(payload.get("overhaul_installs_this_season", 0))
	unlocked_skills = payload["unlocked_skills"]
	deck = payload["deck"]
	deck_slots = int(payload["deck_slots"])
	crew = payload["crew"]
	sponsor_contracts = payload.get("sponsor_contracts", [])
	relation_counters = payload["relation_counters"]
	relation_stages = payload.get("relation_stages", {})
	_relation_pending = payload.get("relation_pending", {})
	consumables = payload.get("consumables", {})
	field_repair_count = int(payload.get("field_repair_count", 0))
	milestones = payload.get("milestones", {})
	# 통산·업적 도입(T4) 전 세이브에는 없다 — 빈 상태가 충실값 (그 세계는 집계가 없었다).
	# 업적은 재로드 후 evaluate_achievements()가 현 상태로 재판정하므로 소급 달성이 성립한다.
	career_stats = payload.get("career_stats", {})
	achievements = payload.get("achievements", {})
	# 달성 시즌 도입(IMPL-129) 전 세이브에는 없다 — **소급분은 시즌을 지어내지 않고 비운다**
	# (표시 층이 '—'로 적는다. 총괄 판정 IMPL-128 A-1 부대 지시 2 · IMPL-090 구세이브 관용 전례).
	achievement_seasons = payload.get("achievement_seasons", {})
	circuits_won = payload.get("circuits_won", {})
	# 래치 도입(IMPL-130) 전 세이브 = 미성립이 충실값 (그 세계는 역전을 세지 않았다).
	jude_overtaken = bool(payload.get("jude_overtaken", false))
	discoveries = payload.get("discoveries", {})
	# 이월 도입(IMPL-078 해소) 전 세이브에는 없다 — 그 세계는 매 GP 최대치 개시였으므로 최대치가 충실한 기본값이다
	chassis = float(payload.get("chassis", data.param("param_chassis_max")))
	return true
