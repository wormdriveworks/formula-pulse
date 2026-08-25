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

# 원문 언어 (D15 §4.1 — 한국어가 원문). 선택 가능한 세트는 표 헤더에서 읽는다.
const DEFAULT_LANGUAGE := "ko"

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
var cg_cutins: Dictionary = {}         # cgcut_* id -> 행 (전용 CG 6종 — D10 §7 결정 #6)
# ── 씬 컷 합성 (D12 §5.9 · D09 §3.1.1 · 사양서 v1.11 §5.2) ──
var fx_elements: Dictionary = {}       # fxe_* id -> 행 (연출 요소 8종 — 사양서 §5.2.1)
var stage_backdrops: Dictionary = {}   # bdrop_* id -> 행 (무대 배경 2레이어 × 5)
var scene_cuts: Dictionary = {}        # cut_* id -> 행 (씬 컷 10종 — D10 §6.2)
var scene_cut_triggers: Array = []     # sct_* 행 (매칭 조건 — 평가는 우선순위 순)
var scene_cut_layers: Dictionary = {}  # cut_* id -> 합성 선언 행 배열 (layer_order 오름차순)
var scene_cut_machines: Dictionary = {} # cut_* id -> 머신 자리 행 배열 (slot_order 오름차순)
var machine_baselines: Dictionary = {}  # 스프라이트 stem -> 바닥 오프셋 행
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
# 축 결속 브리핑 비트 (D08 §8.7-3 재회 체인 — 총괄 판정 IMPL-289 ③).
# **조건이 열 3개로 표현된다**: `stage_id`(무대) + `min_stage`/`max_stage`(관계 단계 구간).
# DSL 도 문맥도 신설하지 않은 것이 이 표의 설계 요점이다.
var vn_beats: Dictionary = {}          # vnbeat_* id -> 행
var vn_beat_lines: Dictionary = {}     # beat_id -> Array[행] (line_order 오름차순)
var vn_beat_omitted: Array = []
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
var language := DEFAULT_LANGUAGE

var _load_ok := true


# 로드 이후에도 유효 — param()·circuit_int() 등이 누락 값을 만나면 false로 내려앉는다.
# 값 누락은 "중단·보고" 사안(불변규칙 2)이므로 호출부는 실행 후 반드시 이 값을 확인한다.
func is_ok() -> bool:
	return _load_ok


func load_all(initial_language := DEFAULT_LANGUAGE) -> bool:
	_load_ok = true
	language = initial_language
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
	_load_cg_cutins()
	_load_scene_cuts()
	_load_events()
	_load_outgame()
	_load_narrative()
	_load_sound_map()
	_load_content()
	# **`_load_content()` 뒤여야 한다** — 선택 지점의 앵커 대조가 `act_vn` 의 라인 열을 읽는다.
	# 순서가 뒤집히면 대조 대상이 비어 전 지점이 생략되고, 그것이 조용히 성립한다.
	_load_vn_choices()
	_load_vn_beats()
	grid = _load_json(STRUCTURES_DIR + "grid_debug.json")
	season_calendar = _load_json(STRUCTURES_DIR + "season_calendar.json")
	if not strings.load_file(STRINGS_PATH, language):
		_load_ok = false
	return _load_ok


# 언어 전환 — 스트링 표만 다시 읽는다 (수치·구조는 언어와 무관하다).
# `load_all()` 을 다시 부르지 않는 이유: 표 30여 종을 재적재하면 진행 중 참조가 갈리고,
# 언어는 표의 **열 선택**일 뿐이라 재적재할 것이 없다.
# 반환 false = 미등재 언어(요청을 무시하고 현행 유지) — 전환 실패가 무문면 화면보다 낫다.
func set_language(code: String) -> bool:
	if code == language:
		return true
	if not strings.languages().has(code):
		push_error("GameData: unknown language '%s'" % code)
		return false
	if not strings.load_file(STRINGS_PATH, code):
		return false
	language = code
	return true


# 선택 가능한 언어 = 스트링 표 헤더 (D15 §4.1 EA 세트 = ko·en·ja 의 물리적 실체)
func languages() -> Array:
	return strings.languages()


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


# ── 전용 CG 대장 (D10 §7 결정 #6 — 상한 6종 · 유입 IMPL-418) ──
#
# **왜 표인가.** 유입 계약(에셋 대장 §4.8)이 *어느 장면이 어느 파일을 띄우는가*를 선언하는데,
# 그 선언을 코드 리터럴로 옮기면 대장과 코드가 각자 낡는다. 27차에 거부 대장을 코드로 옮긴
# 사유("산문은 또 틀린다")의 반대 방향이다 — 저쪽은 산문이 정본이라 코드가 받았고,
# 이쪽은 **표가 정본이 될 수 있으므로** 코드가 아니라 표에 산다.
#
# **발화원 3열은 각기 다른 표를 가리킨다** (27차 트리거 3열과 같은 사유). 한 문자열 열이면
# 어느 표의 id 인지 검사가 보지 못하고 오타가 조용히 통과한다:
#   · `source_achievement` → `achievements.csv` (L3 조우 3종 — D10 §7 "발견형 히든 업적과 1:1")
#   · `source_act_vn`      → `act_vn.json` 항목 (기원 공개·에필로그)
#   · `source_beat`        → `vn_beats.csv`    (사샤 복귀)
# **발견 id 는 업적 행이 이미 이고 있다**(`source_id`) — 대장이 그 값을 다시 적으면 같은 사실이
# 두 곳에 살고 한쪽이 밀린다. 그래서 대장은 업적을 가리키고 발견 id 는 거기서 읽는다.
func _load_cg_cutins() -> void:
	cg_cutins.clear()
	for row in CsvTable.load_rows(_table_path("cg_cutins.csv")):
		cg_cutins[String(row["id"])] = row
	if cg_cutins.is_empty():
		_load_ok = false


# 발견 id(`cg_01_throne` 등) → CG 행. **업적 행을 한 겹 거친다** — 대장의 `source_achievement`
# 가 가리키는 업적의 `source_id` 가 곧 표현 층이 기록하는 발견 id 다.
func cg_cutin_for_discovery(discovery_id: String) -> Dictionary:
	if discovery_id.is_empty():
		return {}
	for cutin_id in cg_cutins:
		var row: Dictionary = cg_cutins[cutin_id]
		var achievement_id := String(row.get("source_achievement", "")).strip_edges()
		if achievement_id.is_empty():
			continue
		var achievement: Dictionary = achievements.get(achievement_id, {})
		if String(achievement.get("source_id", "")).strip_edges() == discovery_id:
			return row
	return {}


# VN id → CG 행. 막 VN 항목과 비트 행이 **같은 `vn_id` 자리로 들어오므로**(둘 다 페이로드의
# `vn_id`) 조회도 한 창구다 — 열은 갈라 두되 조회는 합친다. 값 없음이 정상이다(6종 중 3종만
# VN 경로이고, VN 대부분은 CG 가 없다).
func cg_cutin_for_vn(vn_id: String) -> Dictionary:
	if vn_id.is_empty():
		return {}
	for cutin_id in cg_cutins:
		var row: Dictionary = cg_cutins[cutin_id]
		if String(row.get("source_act_vn", "")).strip_edges() == vn_id:
			return row
		if String(row.get("source_beat", "")).strip_edges() == vn_id:
			return row
	return {}


# ── 씬 컷 합성 적재 (D12 §5.9 스키마 이행) ──
#
# 표 5장이 각기 다른 사실을 이고 있고 **한 장에 몰지 않았다**:
#   · `fx_elements`        = 요소가 무엇인가 (사양서 §5.2.1 대장의 기계 대응)
#   · `stage_backdrops`    = 무대의 배경 2레이어가 어느 파일인가
#   · `scene_cuts`         = 컷의 정체·우선순위·프레임 수 (D10 §6.2 · D13 §8.2)
#   · `scene_cut_triggers` = **언제 그 컷인가** (컷 하나에 조건 여럿 — 방어 성공·실패가 같은 컷)
#   · `scene_cut_layers`   = **어디에 무엇을 얹는가** (합성 선언 — 사양서 §5.2.2)
# 조건을 컷 행의 열로 두면 조건이 둘 이상인 컷을 표현할 수 없고, 배치를 컷 행에 두면
# 요소가 둘인 컷이 열 복제를 부른다.
func _load_scene_cuts() -> void:
	fx_elements.clear()
	stage_backdrops.clear()
	scene_cuts.clear()
	scene_cut_triggers.clear()
	scene_cut_layers.clear()
	for row in CsvTable.load_rows(_table_path("fx_elements.csv")):
		fx_elements[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("stage_backdrops.csv")):
		stage_backdrops[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("scene_cuts.csv")):
		scene_cuts[String(row["id"])] = row
	for row in CsvTable.load_rows(_table_path("scene_cut_triggers.csv")):
		scene_cut_triggers.append(row)
	scene_cut_machines.clear()
	machine_baselines.clear()
	for row in CsvTable.load_rows(_table_path("machine_baselines.csv")):
		machine_baselines[String(row["sprite"])] = row
	for row in CsvTable.load_rows(_table_path("scene_cut_machines.csv")):
		var machine_cut := String(row["cut_id"])
		if not scene_cut_machines.has(machine_cut):
			scene_cut_machines[machine_cut] = []
		scene_cut_machines[machine_cut].append(row)
	for machine_cut in scene_cut_machines:
		scene_cut_machines[machine_cut].sort_custom(func(a, b):
			return CsvTable.to_int(String(a["slot_order"])) < CsvTable.to_int(String(b["slot_order"])))
	for row in CsvTable.load_rows(_table_path("scene_cut_layers.csv")):
		var cut_id := String(row["cut_id"])
		if not scene_cut_layers.has(cut_id):
			scene_cut_layers[cut_id] = []
		scene_cut_layers[cut_id].append(row)
	# 표시 순서는 데이터가 정한다 — 화면이 정렬을 다시 하지 않는다 (`vn_choice_options` 규약).
	for cut_id in scene_cut_layers:
		scene_cut_layers[cut_id].sort_custom(func(a, b):
			return CsvTable.to_int(String(a["layer_order"])) < CsvTable.to_int(String(b["layer_order"])))
	if fx_elements.is_empty() or stage_backdrops.is_empty() or scene_cuts.is_empty() \
			or scene_cut_triggers.is_empty() or scene_cut_machines.is_empty() \
			or machine_baselines.is_empty():
		_load_ok = false


# 컷의 머신 자리 — **없을 수 있다.** 1대 컷은 제원표 §4 표준 자리로 성립하므로 선언을
# 요구하지 않는다(선언이 필요한 것은 2대 이상의 배치이고 그것은 눈 판단이다).
func scene_cut_machines_for(cut_id: String) -> Array:
	return scene_cut_machines.get(cut_id, [])


# 라이벌 → 섀시. **팀이 차를 갖는다** (에셋 대장 §4 선언의 데이터화 — 33차 전사).
# 라이벌 개인이 아니라 팀에 붙는 것은 세컨드 드라이버가 **같은 차에 리버리만 다른** 구조이기
# 때문이다(대장 `*_livery_ai_*` 3장이 그 실물). 리버리 스왑은 아직 소비부가 없다.
func rival_chassis(rival_id: String) -> String:
	for row in rivals:
		if String(row.get("id", "")) != rival_id:
			continue
		return String(teams.get(String(row.get("team_id", "")), {}).get("chassis", ""))
	return _filler_chassis(rival_id)


# ── 필러 결속 (34차 · 총괄 소건 ② — 형식 재량) ──
#
# `ai_rivals` 밖의 참가자(`filler_*`)는 팀이 없다. 에셋 실물은 **공용 섀시의 도색 변조 4종**
# 이고 오프셋이 전부 같으므로(11) 어느 것을 골라도 자리가 흔들리지 않는다 — 고르는 것은
# **색**이다.
#
# **결정적 배정이 요건이다** (재현 계약 — D12 §6 세이브 재로드가 리롤이 되면 안 되는 것과
# 같은 축이고, 여기는 난수를 쓰지 않는 것으로 만족한다). id 의 **후행 숫자**를 대장 크기로
# 나눈 나머지를 쓴다 — 같은 참가자는 언제나 같은 색이고, 필드가 넓어져도 순환한다.
#
# **숫자가 없으면 문자 합으로 떨어뜨린다** — 미상 형식의 id 가 들어와도 배정이 결정적이어야
# 하고, 그때 0번으로 몰면 여러 참가자가 같은 색이 된다.
func _filler_chassis(entrant_id: String) -> String:
	var pool: Array = []
	for sprite in machine_baselines:
		if String(sprite).contains("_filler_"):
			pool.append(String(sprite))
	if pool.is_empty():
		return ""
	pool.sort()
	return String(pool[_stable_index(entrant_id, pool.size())])


func _stable_index(source: String, size: int) -> int:
	var digits := ""
	for index in range(source.length()):
		if source[index].is_valid_int():
			digits += source[index]
	if digits != "":
		return digits.to_int() % size
	var total := 0
	for index in range(source.length()):
		total += source.unicode_at(index)
	return total % size


# 스프라이트 바닥 오프셋 — **셀 중심 y = anchor_road_y − baseline_offset** (총괄 판정 ② ⓑ).
# 섀시마다 셀 안에서 바퀴 높이가 다르다(+11~+19 · 산포 8px). 앵커를 셀 중심으로 두면
# 무대 노면선 위에 서는 차와 뜨는 차가 갈리므로, **앵커는 노면선이고 셀은 계산으로 얹는다.**
func machine_baseline(sprite: String) -> int:
	return CsvTable.to_int(String(machine_baselines.get(sprite, {}).get("baseline_offset", "0")))


func scene_cut(cut_id: String) -> Dictionary:
	return scene_cuts.get(cut_id, {})


func fx_element(element_id: String) -> Dictionary:
	return fx_elements.get(element_id, {})


# 컷의 합성 선언 — **없는 것이 정상이다**(요소 없는 컷은 배경 + 머신으로 성립한다.
# 사양서 §5.1 정지 폴백이 바로 그 형태다).
func scene_cut_layers_for(cut_id: String) -> Array:
	return scene_cut_layers.get(cut_id, [])


# 무대의 배경 2레이어 — `stage_id` 로 찾는다(대장 id 가 아니라 무대가 조회 열쇠다).
func stage_backdrop(stage_id: String) -> Dictionary:
	for backdrop_id in stage_backdrops:
		var row: Dictionary = stage_backdrops[backdrop_id]
		if String(row.get("stage_id", "")) == stage_id:
			return row
	return {}


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


# 브리핑 비트 적재. **`stage_id` 는 검증기가 이미 닫았다**(`structure_ref` — `stage_*.json` 이
# 루트 id 를 가지므로 `_structure_ids()` 가 수집한다). 그래서 여기 가드는 검증기가 볼 수 없는
# 것만 본다: **선언한 라인 수와 실제 라인 수의 일치**.
#
# 선택지 표와 같은 규약 — 어긋난 행은 `push_error` + 버리고 `_load_ok` 는 내리지 않는다.
# 비트 하나 때문에 게임이 서면 안 되고, 오타는 "생략 0" 회귀 축이 게이트에서 잡는다.
func _load_vn_beats() -> void:
	vn_beats.clear()
	vn_beat_lines.clear()
	vn_beat_omitted.clear()
	var lines_by_beat: Dictionary = {}
	for row in CsvTable.load_rows(_table_path("vn_beat_lines.csv")):
		var parent := String(row.get("beat_id", ""))
		if not lines_by_beat.has(parent):
			lines_by_beat[parent] = []
		lines_by_beat[parent].append(row)
	for row in CsvTable.load_rows(_table_path("vn_beats.csv")):
		var beat_id := String(row["id"])
		var lines: Array = lines_by_beat.get(beat_id, [])
		var declared := CsvTable.to_int(String(row.get("line_count", "0")))
		if lines.size() != declared:
			push_error("GameData: vn beat '%s' declares %d lines but has %d"
				% [beat_id, declared, lines.size()])
			vn_beat_omitted.append(beat_id)
			continue
		lines.sort_custom(func(a, b):
			return CsvTable.to_int(String(a["line_order"])) < CsvTable.to_int(String(b["line_order"])))
		vn_beats[beat_id] = row
		vn_beat_lines[beat_id] = lines


func vn_beat(beat_id: String) -> Dictionary:
	return vn_beats.get(beat_id, {})


# 아카이브 표제 키 — 비트 행이 선언한다. 공란이면 화면 층이 슬롯 표제로 폴백한다.
# **세 번째 형태다** (내러티브 8차 §4.2): 막 VN 은 슬롯 행이 없어 리터럴 표를 쓰고,
# 경계 VN 은 슬롯이 1:1 이라 슬롯 표제로 갈리는데, 마일스톤 VN 은 **한 슬롯을 8건이 공유**해
# 슬롯 해소만으로는 갈릴 수 없다. 표제를 **비트 행 자신이** 이고 있는 것이 그 답이다 —
# `string_key` 계열 열이라 V2·V6 이 참조를 이미 보고, 리터럴 표처럼 코드로 새지 않는다.
func vn_beat_title_key(beat_id: String) -> String:
	return String(vn_beats.get(beat_id, {}).get("title_key", "")).strip_edges()


# 형식 A 전이의 **분류 한 겹** (총괄 판정 ① B안 — 내러티브 8차 §4.1).
# 고유 `vn_id` 는 아카이브가 요구하고(나디아 합류와 사샤 복귀는 별 기억이다),
# 전이는 분류 단위다. 그 사이를 비트 행의 `milestone_class` 가 잇는다 —
# 분류 표가 분류 표로 남고, 같은 분류의 N 건이 **각자 1회씩** 전이를 소비한다.
# 비트가 없는 vn_id(막 VN 등)는 자기 id 를 그대로 돌려준다 — 기존 직접 조회 경로 보존.
func milestone_class_of(vn_id: String) -> String:
	var declared := String(vn_beats.get(vn_id, {}).get("milestone_class", "")).strip_edges()
	return declared if not declared.is_empty() else vn_id


func vn_beat_lines_for(beat_id: String) -> Array:
	return vn_beat_lines.get(beat_id, [])


# 이 슬롯·무대·관계 단계에서 서는 비트 — **없는 것이 정상이다**(무대 20종 중 결속은 소수).
# 단계 구간이 반열림이 아니라 닫힌 구간인 것은 의도다: 단계 변주가 유입되면 행이 늘 뿐이고
# 구간이 겹치지 않게 데이터가 갈라 쓰면 된다(코드가 우선순위를 갖지 않는다).
func vn_beats_for(slot_id: String, stage_id: String, axis_stage: Callable) -> Array:
	var matched: Array = []
	for beat_id in vn_beats:
		var row: Dictionary = vn_beats[beat_id]
		if String(row.get("slot_id", "")) != slot_id:
			continue
		if String(row.get("stage_id", "")) != stage_id:
			continue
		var stage := int(axis_stage.call(String(row.get("axis_id", ""))))
		if stage < CsvTable.to_int(String(row.get("min_stage", "0"))):
			continue
		if stage > CsvTable.to_int(String(row.get("max_stage", "0"))):
			continue
		matched.append(row)
	return matched


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
