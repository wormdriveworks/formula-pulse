# 게임 데이터 일괄 로더 — 콘텐츠·수치는 전량 데이터 정의, 코드는 타입·규칙만 (D12 §4 / 불변규칙 2).
# 값의 유일 창구 = D13 (별첨A). 본 클래스는 수치를 보유하지 않는다.
class_name GameData
extends RefCounted

const TABLES_DIR := "res://data/tables/"

# 테이블 디렉토리 오버라이드 — **테스트가 값을 갈아 끼울 수 있게** 하는 유일한 목적이다.
# 이것이 없으면 "코드가 데이터 대신 현재 값과 같은 리터럴을 쓰는" 결함을 잡을 방법이 없다:
# 테스트가 기대값을 같은 데이터에서 읽는 한, 리터럴과 데이터가 일치하는 동안은 구분되지 않는다.
# 오버라이드 디렉토리에 없는 파일은 기본 디렉토리에서 읽으므로 필요한 표만 갈아 끼운다.
var tables_override_dir := ""
const STRUCTURES_DIR := "res://data/structures/"
const STRINGS_PATH := "res://data/strings/strings.csv"

var params: Dictionary = {}            # param_* id -> float
var symbols: Array[Dictionary] = []    # symbol_distribution 행 (릴별 확률 포함)
var match_effects: Dictionary = {}     # symbol_id -> {match_count(int) -> 효과 행}
var duel_conversion: Dictionary = {}   # symbol_id -> 환산 행
var teams: Dictionary = {}             # team_id -> 행
var rivals: Array[Dictionary] = []     # ai_rivals 행 (등재 순서 유지)
var points_tier1: Dictionary = {}      # position(int) -> points(int)
var points_tier2: Dictionary = {}      # position(int) -> 챔피언십 포인트 (D05 §9.4 2층)
var tour_slot_mods: Dictionary = {}    # race_slot(int) -> 행 (슬롯 진행 보정 — D08 §2.4)
var season_calendar: Dictionary = {}   # 구조 JSON (D08 §2 캘린더 규칙)
var sector_attrs: Dictionary = {}      # attr_* id -> 행 (속성 6축 — D13 별첨A §1.3)
var presentation_grades: Dictionary = {}   # grade_* id -> 행 (연출 등급 — D12 §5.8)
var events: Dictionary = {}            # event_* id -> 행 (D08 §7 · D12 §5.4)
var facilities: Dictionary = {}        # facility_* id -> 행 (D07 §2.2)
var tuning_lines: Dictionary = {}      # tuning_* id -> 행 (D13 별첨A §3.5)
var overhauls: Dictionary = {}         # overhaul_* id -> 행 (D13 별첨A §7.2)
var milestones: Dictionary = {}        # milestone_* id -> 행 (D08 §8.2 마스터 표)
var achievements: Dictionary = {}      # achievement_* id -> 행 (D08 §8.11 · D07 §7.1)
# 튜토리얼 단계 — **순서가 의미이므로 딕셔너리가 아니라 배열**이다 (D09 별첨A §A-25).
var tutorial_steps: Array = []         # step_order 오름차순 행 (D04 §8.1 베인 1단계 화자)
var overhaul_slots: Dictionary = {}    # ovslot_* id -> 행 (D13 별첨A §7.1)
var skills: Dictionary = {}            # skill_* id -> 행 (D07 §4.2)
var crew: Dictionary = {}              # crew_* id -> 행 (D07 §5.1 · D13 별첨A §5.1)
var sponsors: Dictionary = {}          # sponsor_* id -> 행 (D13 별첨A §5.3)
var relation_axes: Dictionary = {}     # relation_* id -> 행 (D13 별첨A §5.2)
# 막 VN 인스턴스 (T7 납품 6건 — D04 §1.2 진입 마일스톤 · D08 §8.1 서사 층 래치).
# **슬롯 종류 표(`milestone_vn`)와 별개다** — 그쪽은 경합 우선순위 축이고 이쪽은 실인스턴스다.
var act_vn: Dictionary = {}
var consumables: Dictionary = {}       # consumable_* id -> 행 (D13 별첨A §3.6)
var settlement_rewards: Dictionary = {}  # reward_* id -> 행 (D13 별첨A §3.2)
var vn_slots: Dictionary = {}          # vnslot_* id -> 행 (D08 §8.4)
var vane_lines: Dictionary = {}        # vane_* id -> 행 (D12 §5.7 — stage 필드)
var milestone_vn: Dictionary = {}      # mvn_* id -> 행 (형식 A 전이 매핑)
# VN 선택 지점 (D04 §5.3 — 분기 없는 표현 선택). **평탄한 두 표**다: 지점은 어느 라인 뒤에
# 서는지를, 옵션은 그 지점에 매달린 선택지·반응을 나른다. 중첩 JSON 으로 두면 텍스트 키
# 20건이 전부 무검사가 된다(현행 검사기는 2단 배열에 닿지 않는다 — 총괄 판정 IMPL-257 ①).
var vn_choices: Dictionary = {}        # vnchoice_* id -> 행
var vn_choice_options: Dictionary = {} # choice_id -> Array[행] (option_order 오름차순)
# 앵커 대조에서 떨어져 나간 지점 id — 조용한 생략을 관측 가능하게 남긴다(테스트 축이 읽는다).
var vn_choice_omitted: Array = []
# 이벤트-사운드 매핑 (D12 §5.10 · D11 §8.1) — **한 이벤트에 여러 사운드가 걸린다**
# (GP_FINISH = SE-U19 + AMB-03 등). 그래서 값이 행이 아니라 행의 배열이다.
var sound_map: Dictionary = {}         # event_id -> Array[행] (sound_* 행)
var sound_rows: Dictionary = {}        # sound_* id -> 행 (전수 대조·역참조용)
var event_categories: Dictionary = {}  # category_* id -> 행 (배분·보상 범위)
var event_variants: Dictionary = {}    # event id -> 변형 배열 (조건 DSL 포함)
var presentation_triggers: Dictionary = {} # trigger_* id -> 행 (등급 후보·우선순위)
var circuit: Dictionary = {}           # 활성 서킷 구조 JSON
var circuits: Dictionary = {}          # circuit_* id -> 구조 JSON
var stages: Dictionary = {}            # stage_* id -> 구조 JSON
var scripted_losses: Dictionary = {}   # 필패 스크립트 id -> 구조 JSON (D13 별첨A §6.4)
var manifest: Dictionary = {}          # 적재 대상 선언 (V2가 전 id를 참조 검사)
var grid: Dictionary = {}              # 구조 JSON
var strings := StringTable.new()

var _load_ok := true


# 로드 이후에도 유효 — param()·circuit_int() 등이 누락 값을 만나면 false로 내려앉는다.
# 값 누락은 "중단·보고" 사안(불변규칙 2)이므로 호출부는 실행 후 반드시 이 값을 확인한다.
func is_ok() -> bool:
	return _load_ok


func load_all() -> bool:
	_load_ok = true
	_load_params()
	_load_symbols()
	_load_match_effects()
	_load_duel_conversion()
	_load_teams()
	_load_rivals()
	_load_points()
	_load_points_tier2()
	_load_tour_slot_mods()
	_load_sector_attrs()
	_load_presentation()
	_load_events()
	_load_outgame()
	_load_narrative()
	_load_sound_map()
	_load_content()
	# **`_load_content()` 뒤여야 한다** — 선택 지점의 앵커 대조가 `act_vn` 의 라인 열을 읽는다.
	# 순서가 뒤집히면 대조 대상이 비어 전 지점이 생략되고, 그것이 조용히 성립한다.
	_load_vn_choices()
	grid = _load_json(STRUCTURES_DIR + "grid_debug.json")
	season_calendar = _load_json(STRUCTURES_DIR + "season_calendar.json")
	if not strings.load_file(STRINGS_PATH):
		_load_ok = false
	return _load_ok


# 콘텐츠 적재는 매니페스트 선언 전속 — 디렉토리 스캔을 쓰지 않는다.
# 스캔은 파일이 빠져도 조용히 성립하지만, 매니페스트는 V2가 전 id를 참조 검사한다.
func _load_content() -> void:
	circuits.clear()
	stages.clear()
	scripted_losses.clear()
	manifest = _load_json(STRUCTURES_DIR + "content_manifest.json")
	act_vn = _load_json(STRUCTURES_DIR + "act_vn.json")
	for stage_id in _manifest_array("stages"):
		stages[stage_id] = _load_json("%s%s.json" % [STRUCTURES_DIR, stage_id])
	for circuit_id in _manifest_array("circuits"):
		circuits[circuit_id] = _load_json("%s%s.json" % [STRUCTURES_DIR, circuit_id])
	for loss_id in _manifest_array("scripted_losses"):
		scripted_losses[loss_id] = _load_json("%s%s.json" % [STRUCTURES_DIR, loss_id])
	select_circuit(String(_structure_value(manifest, "default_circuit", "content_manifest.json", "")))


func _manifest_array(key: String) -> Array:
	var value: Variant = _structure_value(manifest, key, "content_manifest.json", [])
	return value if typeof(value) == TYPE_ARRAY else []


func select_circuit(circuit_id: String) -> bool:
	if not circuits.has(circuit_id):
		push_error("GameData: unknown circuit '%s'" % circuit_id)
		_load_ok = false
		return false
	circuit = circuits[circuit_id]
	return true


# 활성 서킷의 섹터 배치 조회 — 슬롯은 1-기반 (D08 별첨A 표기 그대로).
func sector_entry(slot: int) -> Dictionary:
	var sectors: Variant = _structure_value(circuit, "sectors", String(circuit.get("id", "circuit")), [])
	if typeof(sectors) != TYPE_ARRAY:
		return {}
	for entry in Array(sectors):
		if typeof(entry) == TYPE_DICTIONARY and int(entry.get("slot", -1)) == slot:
			return entry
	push_error("GameData: circuit '%s' has no sector slot %d" % [circuit.get("id", "?"), slot])
	_load_ok = false
	return {}


func sector_attr(attr_id: String) -> Dictionary:
	if attr_id == "":
		return {}
	if not sector_attrs.has(attr_id):
		push_error("GameData: unknown sector attribute '%s'" % attr_id)
		_load_ok = false
		return {}
	return sector_attrs[attr_id]


func stage_of_active_circuit() -> Dictionary:
	var stage_id := String(_structure_value(circuit, "stage_id", String(circuit.get("id", "circuit")), ""))
	if not stages.has(stage_id):
		push_error("GameData: unknown stage '%s'" % stage_id)
		_load_ok = false
		return {}
	return stages[stage_id]


# 필수 파라미터 조회 — D13에 없는 값 참조 시 즉시 에러 (임의 기입 금지의 런타임 가드)
func param(id: String) -> float:
	if not params.has(id):
		push_error("GameData: missing param '%s' (D13 value channel)" % id)
		_load_ok = false
		return 0.0
	return params[id]


func param_int(id: String) -> int:
	return int(param(id))


# 구조 JSON 필수 값 조회 — param()과 동일 계약. 침묵하는 기본값(`get(key, 3)`)을 두지 않는다:
# 대체값을 쓰는 순간 "D13에 없는 값이면 중단·보고"(불변규칙 2)가 조용히 우회된다.
func circuit_int(key: String) -> int:
	return _structure_int(circuit, key, String(circuit.get("id", "circuit")))


func grid_int(key: String) -> int:
	return _structure_int(grid, key, "grid_debug.json")


func circuit_str(key: String) -> String:
	return String(_structure_value(circuit, key, String(circuit.get("id", "circuit")), ""))


func grid_array(key: String) -> Array:
	var value: Variant = _structure_value(grid, key, "grid_debug.json", [])
	return value if typeof(value) == TYPE_ARRAY else []


func _structure_int(source: Dictionary, key: String, source_name: String) -> int:
	return int(_structure_value(source, key, source_name, 0))


func _structure_value(source: Dictionary, key: String, source_name: String, fallback: Variant) -> Variant:
	if not source.has(key):
		push_error("GameData: missing '%s' in %s (structure value channel)" % [key, source_name])
		_load_ok = false
		return fallback
	return source[key]


func _load_params() -> void:
	params.clear()
	for row in CsvTable.load_rows(_table_path("core_params.csv")):
		params[String(row["id"])] = CsvTable.to_float(String(row["value"]))
	if params.is_empty():
		_load_ok = false


func _load_symbols() -> void:
	symbols.clear()
	for row in CsvTable.load_rows(_table_path("symbol_distribution.csv")):
		symbols.append(row)
	if symbols.is_empty():
		_load_ok = false


func _load_match_effects() -> void:
	match_effects.clear()
	for row in CsvTable.load_rows(_table_path("symbol_match_effects.csv")):
		var symbol_id := String(row["symbol_id"])
		if not match_effects.has(symbol_id):
			match_effects[symbol_id] = {}
		match_effects[symbol_id][CsvTable.to_int(String(row["match_count"]))] = row
	if match_effects.is_empty():
		_load_ok = false


func _load_duel_conversion() -> void:
	duel_conversion.clear()
	for row in CsvTable.load_rows(_table_path("duel_conversion.csv")):
		duel_conversion[String(row["symbol_id"])] = row


func _load_teams() -> void:
	teams.clear()
	for row in CsvTable.load_rows(_table_path("ai_teams.csv")):
		teams[String(row["id"])] = row


func _load_rivals() -> void:
	rivals.clear()
	for row in CsvTable.load_rows(_table_path("ai_rivals.csv")):
		rivals.append(row)
	if rivals.is_empty():
		_load_ok = false


func _load_sector_attrs() -> void:
	sector_attrs.clear()
	for row in CsvTable.load_rows(_table_path("sector_attributes.csv")):
		sector_attrs[String(row["id"])] = row
	if sector_attrs.is_empty():
		_load_ok = false


func _load_presentation() -> void:
	presentation_grades.clear()
	presentation_triggers.clear()
	for row in CsvTable.load_rows(_table_path("presentation_grades.csv")):
		presentation_grades[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("presentation_triggers.csv")):
		presentation_triggers[String(row["id"])] = row
	if presentation_grades.is_empty() or presentation_triggers.is_empty():
		_load_ok = false


func presentation_grade(grade_id: String) -> Dictionary:
	if not presentation_grades.has(grade_id):
		push_error("GameData: unknown presentation grade '%s'" % grade_id)
		_load_ok = false
		return {}
	return presentation_grades[grade_id]


func presentation_trigger(trigger_id: String) -> Dictionary:
	if not presentation_triggers.has(trigger_id):
		push_error("GameData: unknown presentation trigger '%s'" % trigger_id)
		_load_ok = false
		return {}
	return presentation_triggers[trigger_id]


func _load_events() -> void:
	events.clear()
	event_categories.clear()
	event_variants.clear()
	for row in CsvTable.load_rows(_table_path("event_categories.csv")):
		event_categories[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("events.csv")):
		events[String(row["id"])] = row
	var variants_file := _load_json(STRUCTURES_DIR + "event_variants.json")
	var variants: Variant = _structure_value(variants_file, "variants", "event_variants.json", {})
	if typeof(variants) == TYPE_DICTIONARY:
		event_variants = variants
	if events.is_empty() or event_categories.is_empty():
		_load_ok = false


func event(event_id: String) -> Dictionary:
	if not events.has(event_id):
		push_error("GameData: unknown event '%s'" % event_id)
		_load_ok = false
		return {}
	return events[event_id]


func event_category(category_id: String) -> Dictionary:
	if not event_categories.has(category_id):
		push_error("GameData: unknown event category '%s'" % category_id)
		_load_ok = false
		return {}
	return event_categories[category_id]


# 변형이 없는 이벤트는 빈 배열 — 이것은 부재값이 아니라 "변형 없음"이라는 사실이다.
func event_variants_of(event_id: String) -> Array:
	var entry: Variant = event_variants.get(event_id, [])
	return entry if typeof(entry) == TYPE_ARRAY else []


func _load_outgame() -> void:
	facilities.clear()
	tuning_lines.clear()
	overhauls.clear()
	overhaul_slots.clear()
	skills.clear()
	crew.clear()
	sponsors.clear()
	relation_axes.clear()
	consumables.clear()
	settlement_rewards.clear()
	for row in CsvTable.load_rows(_table_path("garage_facilities.csv")):
		facilities[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("tuning_lines.csv")):
		tuning_lines[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("overhauls.csv")):
		overhauls[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("overhaul_slots.csv")):
		overhaul_slots[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("skills.csv")):
		skills[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("crew.csv")):
		crew[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("sponsors.csv")):
		sponsors[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("relation_axes.csv")):
		relation_axes[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("consumables.csv")):
		consumables[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("settlement_rewards.csv")):
		settlement_rewards[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("milestones.csv")):
		milestones[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("achievements.csv")):
		achievements[String(row["id"])] = row
	# 튜토리얼 단계 — 표시 순서(step_order)대로 정렬해 둔다. 화면이 정렬을 다시 하지 않도록
	# 데이터 적재 시점에 한 번만 맞춘다 (CSV 행 순서에 의존하지 않는다).
	tutorial_steps = CsvTable.load_rows(_table_path("tutorial_steps.csv"))
	tutorial_steps.sort_custom(func(a, b): return CsvTable.to_int(String(a["step_order"])) \
		< CsvTable.to_int(String(b["step_order"])))
	if facilities.is_empty() or tuning_lines.is_empty() or overhauls.is_empty() or overhaul_slots.is_empty() or skills.is_empty() or crew.is_empty() or sponsors.is_empty() or relation_axes.is_empty() or consumables.is_empty() or settlement_rewards.is_empty() or milestones.is_empty() or achievements.is_empty() or tutorial_steps.is_empty():
		_load_ok = false


func facility(row_id: String) -> Dictionary:
	if not facilities.has(row_id):
		push_error("GameData: unknown facility '%s'" % row_id)
		_load_ok = false
		return {}
	return facilities[row_id]


func tuning_line(row_id: String) -> Dictionary:
	if not tuning_lines.has(row_id):
		push_error("GameData: unknown tuning_line '%s'" % row_id)
		_load_ok = false
		return {}
	return tuning_lines[row_id]


func overhaul(row_id: String) -> Dictionary:
	if not overhauls.has(row_id):
		push_error("GameData: unknown overhaul '%s'" % row_id)
		_load_ok = false
		return {}
	return overhauls[row_id]


func skill(row_id: String) -> Dictionary:
	if not skills.has(row_id):
		push_error("GameData: unknown skill '%s'" % row_id)
		_load_ok = false
		return {}
	return skills[row_id]


func consumable(row_id: String) -> Dictionary:
	if not consumables.has(row_id):
		push_error("GameData: unknown consumable '%s'" % row_id)
		_load_ok = false
		return {}
	return consumables[row_id]


# 막 VN 인스턴스 전량 (발행 순서 = `order`). 값 창구 경유 — 코드에 막 번호·라인을 적지 않는다.
func act_vn_entries() -> Array:
	var value: Variant = act_vn.get("entries", [])
	return value if typeof(value) == TYPE_ARRAY else []


func act_vn_entry(vn_id: String) -> Dictionary:
	for entry in act_vn_entries():
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("id", "")) == vn_id:
			return entry
	return {}


func relation_axis(relation_id: String) -> Dictionary:
	if not relation_axes.has(relation_id):
		push_error("GameData: unknown relation axis '%s'" % relation_id)
		_load_ok = false
		return {}
	return relation_axes[relation_id]


func _load_narrative() -> void:
	vn_slots.clear()
	vane_lines.clear()
	milestone_vn.clear()
	for row in CsvTable.load_rows(_table_path("vn_slots.csv")):
		vn_slots[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("vane_lines.csv")):
		vane_lines[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("milestone_vn.csv")):
		milestone_vn[String(row["id"])] = row
	if vn_slots.is_empty() or vane_lines.is_empty() or milestone_vn.is_empty():
		_load_ok = false


# 이벤트-사운드 매핑 적재 (D12 §5.10 — DoD #16).
# **사운드는 이 표 경유로만 발화한다**(D11 §1.4 이벤트 결속 원칙의 구조 보장) — 코드가 SFX id를
# 직접 들고 재생하는 경로를 두지 않는다. 그래야 씬 컷 전용 SFX가 구조적으로 생겨날 수 없다(C-A2).
func _load_sound_map() -> void:
	sound_map.clear()
	sound_rows.clear()
	for row in CsvTable.load_rows(_table_path("sound_map.csv")):
		var event_id := String(row["event_id"])
		if not sound_map.has(event_id):
			sound_map[event_id] = []
		sound_map[event_id].append(row)
		sound_rows[String(row["id"])] = row
	if sound_map.is_empty():
		_load_ok = false


# 이벤트에 걸린 사운드 행 — **미등재는 오류가 아니다**(무음이 정상인 이벤트가 있다:
# 저장 인디케이터 무음 U-a · 상태 컷 무음 원칙 §2.8). 커버리지 판정은 검사기·V2 소관이다.
func sounds_for(event_id: String) -> Array:
	return sound_map.get(event_id, [])


func vn_slot(slot_id: String) -> Dictionary:
	if not vn_slots.has(slot_id):
		push_error("GameData: unknown vn slot '%s'" % slot_id)
		_load_ok = false
		return {}
	return vn_slots[slot_id]


# 마일스톤 VN 매핑은 **없을 수 있다** — 전이를 부여하지 않는 VN이 정상이므로
# 미등재를 오류로 보지 않는다 (값 누락과 매핑 부재는 다른 사안이다).
func milestone_vn_row(vn_id: String) -> Dictionary:
	return milestone_vn.get(vn_id, {})


# VN 선택 지점 적재 (D04 §5.3 · 총괄 판정 IMPL-257 ①).
#
# **`vn_id` 는 기계가 보지 못한다.** `_structure_ids()` 가 구조 파일의 **루트 id 만** 모으므로
# `act_vn.json` 의 `entries[].id` 는 FK 후보에 없다 — V2 가 닿지 않는 유일한 열이다.
# 그 공백을 여기서 닫는다: 지점이 가리키는 VN 과 그 안의 앵커 라인을 실제로 찾아 보고,
# 없으면 **시끄럽게 버린다.** 조용히 통과시키면 지점은 영원히 뜨지 않으면서 데이터는 멀쩡해
# 보인다(IMPL-244·248 계열 — "안 되는 것을 안 된다고 말하게 한다").
func _load_vn_choices() -> void:
	vn_choices.clear()
	vn_choice_options.clear()
	vn_choice_omitted.clear()
	for row in CsvTable.load_rows(_table_path("vn_choices.csv")):
		var choice_id := String(row["id"])
		var vn_id := String(row.get("vn_id", ""))
		var entry := act_vn_entry(vn_id)
		if entry.is_empty():
			push_error("GameData: vn choice '%s' references unknown vn '%s'" % [choice_id, vn_id])
			vn_choice_omitted.append(choice_id)
			continue
		if not _vn_has_line(entry, String(row.get("after_text_key", ""))):
			push_error("GameData: vn choice '%s' anchor '%s' not in vn '%s'"
				% [choice_id, row.get("after_text_key", ""), vn_id])
			vn_choice_omitted.append(choice_id)
			continue
		vn_choices[choice_id] = row
	for row in CsvTable.load_rows(_table_path("vn_choice_options.csv")):
		var parent := String(row.get("choice_id", ""))
		# 버려진 지점의 옵션은 함께 사라진다 — 부모 없는 옵션을 들고 있을 이유가 없다.
		if not vn_choices.has(parent):
			continue
		if not vn_choice_options.has(parent):
			vn_choice_options[parent] = []
		vn_choice_options[parent].append(row)
	# 표시 순서는 데이터가 정한다 — 화면이 정렬을 다시 하지 않도록 여기서 한 번만 맞춘다
	# (`tutorial_steps` 와 같은 규약 · CSV 행 순서에 의존하지 않는다).
	for parent in vn_choice_options:
		vn_choice_options[parent].sort_custom(func(a, b):
			return CsvTable.to_int(String(a["option_order"])) < CsvTable.to_int(String(b["option_order"])))


func _vn_has_line(entry: Dictionary, text_key: String) -> bool:
	if text_key.is_empty():
		return false
	for line in Array(entry.get("lines", [])):
		if typeof(line) == TYPE_DICTIONARY and String(Dictionary(line).get("text_key", "")) == text_key:
			return true
	return false


# 이 VN 의 이 라인 뒤에 서는 선택 지점 — 없으면 빈 사전. **없는 것이 정상이다**
# (75라인 중 지점이 서는 자리는 4곳뿐이므로 미등재를 오류로 보지 않는다).
func vn_choice_at(vn_id: String, after_text_key: String) -> Dictionary:
	for choice_id in vn_choices:
		var row: Dictionary = vn_choices[choice_id]
		if String(row.get("vn_id", "")) == vn_id and String(row.get("after_text_key", "")) == after_text_key:
			return row
	return {}


func vn_choice_options_for(choice_id: String) -> Array:
	return vn_choice_options.get(choice_id, [])


func _load_points() -> void:
	points_tier1.clear()
	for row in CsvTable.load_rows(_table_path("points_tier1.csv")):
		points_tier1[CsvTable.to_int(String(row["position"]))] = CsvTable.to_int(String(row["points"]))


func _load_points_tier2() -> void:
	points_tier2.clear()
	for row in CsvTable.load_rows(_table_path("points_tier2.csv")):
		points_tier2[CsvTable.to_int(String(row["position"]))] = CsvTable.to_int(String(row["points"]))
	if points_tier2.is_empty():
		_load_ok = false


# 오버라이드에 파일이 있으면 그쪽, 없으면 기본. 파일 단위 대체이므로 픽스처가 최소로 유지된다.
func _table_path(file_name: String) -> String:
	if tables_override_dir != "":
		var candidate := tables_override_dir + file_name
		if FileAccess.file_exists(candidate):
			return candidate
	return TABLES_DIR + file_name


# 슬롯 진행 보정 (D08 §2.4 · D13 별첨A §6.2) — 사용자 판정: **투어 내 GP 슬롯**(제1~4전) 축.
func _load_tour_slot_mods() -> void:
	tour_slot_mods.clear()
	for row in CsvTable.load_rows(_table_path("tour_slot_mods.csv")):
		tour_slot_mods[CsvTable.to_int(String(row["race_slot"]))] = row
	if tour_slot_mods.is_empty():
		_load_ok = false


# 미등재 슬롯은 조용히 0이 되지 않는다 — 투어 편성이 바뀌면 값이 함께 와야 한다.
func tour_slot_pace_add(race_slot: int) -> float:
	if not tour_slot_mods.has(race_slot):
		push_error("GameData: no tour slot mod for race slot %d" % race_slot)
		_load_ok = false
		return 0.0
	return CsvTable.to_float(String(tour_slot_mods[race_slot]["pace_add"]))


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GameData: cannot open %s" % path)
		_load_ok = false
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: invalid JSON in %s" % path)
		_load_ok = false
		return {}
	return parsed
