# 연출 등급 L0~L3 + GP당 상한 카운터 (D12 §5.8 · D04 §5.5 · D08 §8.5 · D13 별첨A §8.1).
# MS-1에서는 표현 채널이 없어 유보했던 항목(IMPL-016) — MS-2에서 아트·사운드가 들어오므로 결선.
#
# 등급 판정 자체는 불변이다. 채널 감쇠(옵션 연동)는 출력 단계의 마스킹 소관이며
# 여기서는 다루지 않는다 (D12 §5.8 명문).
#
# 상한 구조 (D08 §8.5): L2 = GP당 2회 · L3 = GP당 1회, 각각 독립.
# 초과 발동 조건이 겹치면 우선순위(듀얼 결판 > 벽 라이벌 비트 > 찬스 3매치) 순으로 슬롯을
# 소진하고, 남은 후보는 L1로 강등한다 (D13 별첨A §8.1 "초과 시 L1로 강등").
class_name PresentationGrade
extends RefCounted

const FALLBACK_GRADE := "grade_l1"   # 상한 초과 시 강등 대상 (D13 별첨A §8.1)

var data: GameData
var _used: Dictionary = {}           # grade_id -> 이번 GP에서 소비한 횟수


func setup(game_data: GameData) -> void:
	data = game_data
	reset_gp()


# GP 경계에서 카운터를 되돌린다 — 상한은 '그랑프리당'이므로 GP를 넘겨 누적되면 안 된다.
func reset_gp() -> void:
	_used.clear()


func used_count(grade_id: String) -> int:
	return int(_used.get(grade_id, 0))


# 후보 트리거 목록을 받아 실제 발동 등급을 확정한다.
# 반환: [{"trigger": id, "grade": grade_id, "demoted": bool}] — 우선순위 정렬 순서.
# 한 턴에 여러 후보가 서는 경우를 전제로 목록을 받는다: 개별 호출로 처리하면
# 호출 순서가 우선순위를 덮어써 "듀얼 결판이 찬스 3매치에 슬롯을 빼앗기는" 역전이 생긴다.
func resolve(trigger_ids: Array) -> Array:
	var candidates: Array = []
	for trigger_id in trigger_ids:
		var trigger := data.presentation_trigger(String(trigger_id))
		if trigger.is_empty():
			continue
		candidates.append({
			"trigger": String(trigger_id),
			"grade": String(trigger["grade_id"]),
			"priority": CsvTable.to_int(String(trigger["priority"])),
		})
	candidates.sort_custom(func(a, b): return int(a["priority"]) < int(b["priority"]))
	var resolved: Array = []
	for candidate in candidates:
		var grade_id := String(candidate["grade"])
		if _consume(grade_id):
			resolved.append({"trigger": candidate["trigger"], "grade": grade_id, "demoted": false})
		else:
			resolved.append({"trigger": candidate["trigger"], "grade": FALLBACK_GRADE, "demoted": true})
	return resolved


# 상한 0 = 무제한 (L0·L1). 상한이 있는 등급만 카운터를 소비한다.
func _consume(grade_id: String) -> bool:
	var grade := data.presentation_grade(grade_id)
	if grade.is_empty():
		return false
	var cap := CsvTable.to_int(String(grade["gp_cap"]))
	if cap <= 0:
		return true
	if used_count(grade_id) >= cap:
		return false
	_used[grade_id] = used_count(grade_id) + 1
	return true


# 등급 → 표현 채널 구성 (D04 §5.5 · D11 §2.5 확정 표의 데이터화).
# 햅틱은 세기 등급(none/weak/strong)까지만 돌려준다 — 진동 지속 시간(D11 §3.1)은
# D13 대장에 전사돼 있지 않아 여기서 수치를 만들지 않는다 (불변규칙 2 · impl_log 보고 항목).
func channels(grade_id: String) -> Dictionary:
	var grade := data.presentation_grade(grade_id)
	if grade.is_empty():
		return {}
	return {
		"code": String(grade["code"]),
		"log": true,                                     # 전 등급 공통 — L0도 로그는 발화한다
		"sfx_sting": CsvTable.to_int(String(grade["sfx_sting"])) == 1,
		"haptic_level": String(grade["haptic_level"]),
		"flash_slow": CsvTable.to_int(String(grade["flash_slow"])) == 1,
		"illustration": CsvTable.to_int(String(grade["illustration"])) == 1,
		"sting_length_sec": CsvTable.to_float(String(grade["sting_length_sec"])),
	}
