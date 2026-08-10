# 게임 데이터 일괄 로더 — 콘텐츠·수치는 전량 데이터 정의, 코드는 타입·규칙만 (D12 §4 / 불변규칙 2).
# 값의 유일 창구 = D13 (별첨A). 본 클래스는 수치를 보유하지 않는다.
class_name GameData
extends RefCounted

const TABLES_DIR := "res://data/tables/"
const STRUCTURES_DIR := "res://data/structures/"
const STRINGS_PATH := "res://data/strings/strings.csv"

var params: Dictionary = {}            # param_* id -> float
var symbols: Array[Dictionary] = []    # symbol_distribution 행 (릴별 확률 포함)
var match_effects: Dictionary = {}     # symbol_id -> {match_count(int) -> 효과 행}
var duel_conversion: Dictionary = {}   # symbol_id -> 환산 행
var teams: Dictionary = {}             # team_id -> 행
var rivals: Array[Dictionary] = []     # ai_rivals 행 (등재 순서 유지)
var points_tier1: Dictionary = {}      # position(int) -> points(int)
var circuit: Dictionary = {}           # 구조 JSON
var grid: Dictionary = {}              # 구조 JSON
var strings := StringTable.new()

var _load_ok := true


func load_all() -> bool:
	_load_ok = true
	_load_params()
	_load_symbols()
	_load_match_effects()
	_load_duel_conversion()
	_load_teams()
	_load_rivals()
	_load_points()
	circuit = _load_json(STRUCTURES_DIR + "circuit_debug.json")
	grid = _load_json(STRUCTURES_DIR + "grid_debug.json")
	if not strings.load_file(STRINGS_PATH):
		_load_ok = false
	return _load_ok


# 필수 파라미터 조회 — D13에 없는 값 참조 시 즉시 에러 (임의 기입 금지의 런타임 가드)
func param(id: String) -> float:
	if not params.has(id):
		push_error("GameData: missing param '%s' (D13 value channel)" % id)
		_load_ok = false
		return 0.0
	return params[id]


func param_int(id: String) -> int:
	return int(param(id))


func _load_params() -> void:
	params.clear()
	for row in CsvTable.load_rows(TABLES_DIR + "core_params.csv"):
		params[String(row["id"])] = CsvTable.to_float(String(row["value"]))
	if params.is_empty():
		_load_ok = false


func _load_symbols() -> void:
	symbols.clear()
	for row in CsvTable.load_rows(TABLES_DIR + "symbol_distribution.csv"):
		symbols.append(row)
	if symbols.is_empty():
		_load_ok = false


func _load_match_effects() -> void:
	match_effects.clear()
	for row in CsvTable.load_rows(TABLES_DIR + "symbol_match_effects.csv"):
		var symbol_id := String(row["symbol_id"])
		if not match_effects.has(symbol_id):
			match_effects[symbol_id] = {}
		match_effects[symbol_id][CsvTable.to_int(String(row["match_count"]))] = row
	if match_effects.is_empty():
		_load_ok = false


func _load_duel_conversion() -> void:
	duel_conversion.clear()
	for row in CsvTable.load_rows(TABLES_DIR + "duel_conversion.csv"):
		duel_conversion[String(row["symbol_id"])] = row


func _load_teams() -> void:
	teams.clear()
	for row in CsvTable.load_rows(TABLES_DIR + "ai_teams.csv"):
		teams[String(row["id"])] = row


func _load_rivals() -> void:
	rivals.clear()
	for row in CsvTable.load_rows(TABLES_DIR + "ai_rivals.csv"):
		rivals.append(row)
	if rivals.is_empty():
		_load_ok = false


func _load_points() -> void:
	points_tier1.clear()
	for row in CsvTable.load_rows(TABLES_DIR + "points_tier1.csv"):
		points_tier1[CsvTable.to_int(String(row["position"]))] = CsvTable.to_int(String(row["points"]))


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
