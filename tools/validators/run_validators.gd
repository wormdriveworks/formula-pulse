# 빌드 기계 검증기 V1~V8 + 혼입 0 스캔 (D12 §4.2 · D14 §2.1 TL-1 / CLAUDE.md 불변규칙 7)
#
# 실행 (리포지토리 루트에서 — 로컬 단일 명령):
#   godot --headless --path . --script tools/validators/run_validators.gd
#
# 차단 규칙: V1~V6·V8 + 혼입 0 스캔 = 위반 1건이면 실패(exit 1).
# V7(금칙 어휘)은 경고 전용 — 빌드를 차단하지 않는다 (D12 §4.2 V7 행 · D14 TL-1 명문).
# V6 내부: ID 중복·접두 위반 = 차단 / 고아 데이터 = 경고 (D12 §4.2 V6 행 "고아 데이터 … 경고").
#
# 자기 완결형: 프로젝트 클래스 캐시에 의존하지 않는다 (프로젝트리스 실행 가능).
extends SceneTree

var _fail_count := 0
var _warn_count := 0
var _config: Dictionary = {}
var _tables: Dictionary = {}        # 파일명 -> Array[Dictionary]
var _structures: Dictionary = {}    # 파일명 -> Dictionary
var _strings: Dictionary = {}       # key -> {언어: 값}
var _code_files: Array = []         # {path, source}


func _init() -> void:
	if not _load_inputs():
		print("VALIDATORS_FAIL input load error")
		quit(1)
		return
	_run_v1_schema()
	_run_v2_references()
	_run_v3_string_format()
	_run_v4_hardcoded_text()
	_run_v5_anchor_binding()
	_run_v6_id_hygiene()
	_run_v7_forbidden_vocab()
	_run_v8_key_grammar()
	_run_contamination_scan()
	_run_architecture_scan()
	print("")
	if _fail_count == 0:
		print("VALIDATORS_PASS warnings=%d" % _warn_count)
		quit(0)
	else:
		print("VALIDATORS_FAIL failures=%d warnings=%d" % [_fail_count, _warn_count])
		quit(1)


func _fail(rule: String, message: String) -> void:
	_fail_count += 1
	print("  [FAIL] %s: %s" % [rule, message])


func _warn(rule: String, message: String) -> void:
	_warn_count += 1
	print("  [WARN] %s: %s" % [rule, message])


func _report(rule: String, label: String, checked: int, before_fail: int, before_warn: int) -> void:
	var status := "PASS"
	if _fail_count > before_fail:
		status = "FAIL"
	elif _warn_count > before_warn:
		status = "WARN"
	print("%s %s: %s (%d checks)" % [rule, label, status, checked])


# ── 입력 적재 ──
func _load_inputs() -> bool:
	var config_text := _read_text("tools/validators/config.json")
	if config_text == "":
		return false
	var parsed: Variant = JSON.parse_string(config_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	_config = parsed
	var tables_dir := String(_config["tables_dir"])
	for file_name in _config["tables"]:
		_tables[file_name] = _parse_csv(_read_text(tables_dir + "/" + String(file_name)))
	var structures_dir := String(_config["structures_dir"])
	for file_name in _config["structures"]:
		var structure: Variant = JSON.parse_string(_read_text(structures_dir + "/" + String(file_name)))
		_structures[file_name] = structure if typeof(structure) == TYPE_DICTIONARY else {}
	for row in _parse_csv(_read_text(String(_config["strings_csv"]))):
		var key := String(row.get("key", ""))
		if key != "":
			_strings[key] = row
	_collect_code_files(String(_config["code_dir"]))
	return true


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("  [ERROR] cannot open: ", path)
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _collect_code_files(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full_path := dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_code_files(full_path)
		elif entry.ends_with(".gd"):
			_code_files.append({"path": full_path, "source": _read_text(full_path)})
		entry = dir.get_next()
	dir.list_dir_end()


# CSV 파서 (RFC 4180 기본형 — 코어 CsvTable과 동일 규격의 자기 완결 복제)
func _parse_csv(text: String) -> Array:
	var rows: Array = []
	if text == "":
		return rows
	var records: Array = []
	var field := ""
	var record: Array = []
	var in_quotes := false
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if in_quotes:
			if ch == '"':
				if i + 1 < n and text[i + 1] == '"':
					field += '"'
					i += 1
				else:
					in_quotes = false
			else:
				field += ch
		else:
			match ch:
				'"': in_quotes = true
				',':
					record.append(field)
					field = ""
				'\r': pass
				'\n':
					record.append(field)
					field = ""
					records.append(record)
					record = []
				_: field += ch
		i += 1
	if field != "" or not record.is_empty():
		record.append(field)
		records.append(record)
	if records.is_empty():
		return rows
	var header: Array = records[0]
	for r in range(1, records.size()):
		if records[r].size() == 1 and String(records[r][0]).strip_edges() == "":
			continue
		var row := {}
		for c in range(header.size()):
			row[header[c]] = records[r][c] if c < records[r].size() else ""
		rows.append(row)
	return rows


# 주석 제거 (문자열 리터럴 내 '#' 보존)
func _strip_comment(line: String) -> String:
	var in_string := false
	var quote := ""
	for i in range(line.length()):
		var ch := line[i]
		if in_string:
			if ch == quote:
				in_string = false
		elif ch == '"' or ch == "'":
			in_string = true
			quote = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


# 문자열 리터럴 추출
func _extract_literals(line: String) -> Array:
	var literals: Array = []
	var in_string := false
	var quote := ""
	var current := ""
	for i in range(line.length()):
		var ch := line[i]
		if in_string:
			if ch == quote:
				literals.append(current)
				current = ""
				in_string = false
			else:
				current += ch
		elif ch == '"' or ch == "'":
			in_string = true
			quote = ch
	return literals


func _has_hangul(text: String) -> bool:
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if (code >= 0xAC00 and code <= 0xD7A3) or (code >= 0x1100 and code <= 0x11FF) \
			or (code >= 0x3130 and code <= 0x318F):
			return true
	return false


# 전각/반각 가중 자수 (D09 §6.6 산출법 계열 — 전각 1.0 / 반각 0.5)
func _weighted_chars(text: String) -> float:
	var total := 0.0
	for i in range(text.length()):
		var code := text.unicode_at(i)
		var full_width := (code >= 0x1100 and code <= 0x11FF) \
			or (code >= 0x2E80 and code <= 0x9FFF) \
			or (code >= 0xAC00 and code <= 0xD7A3) \
			or (code >= 0xF900 and code <= 0xFAFF) \
			or (code >= 0xFF00 and code <= 0xFF60) \
			or (code >= 0x3000 and code <= 0x303F)
		total += 1.0 if full_width else 0.5
	return total


# ── V1 스키마: 타입·필수 필드·enum 범위 ──
func _run_v1_schema() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	for file_name in _config["tables"]:
		var spec: Dictionary = _config["tables"][file_name]
		var rows: Array = _tables[file_name]
		if rows.is_empty():
			_fail("V1", "%s: empty or unreadable" % file_name)
			continue
		var columns: Dictionary = spec["columns"]
		var first_row: Dictionary = rows[0]
		for column_name in columns:
			if not first_row.has(column_name):
				_fail("V1", "%s: missing column '%s'" % [file_name, column_name])
		for row in rows:
			checked += 1
			for column_name in columns:
				if not row.has(column_name):
					continue
				_check_value(String(file_name), String(columns[column_name]), String(row[column_name]), String(row.get("id", "?")), column_name)
	for file_name in _config["structures"]:
		var spec := _structure_spec(String(file_name))
		var structure: Dictionary = _structures[file_name]
		checked += 1
		if structure.is_empty():
			_fail("V1", "%s: empty or invalid JSON" % file_name)
			continue
		var required: Dictionary = spec["required"]
		for field_name in required:
			if not structure.has(field_name):
				_fail("V1", "%s: missing field '%s'" % [file_name, field_name])
				continue
			# 구조 JSON도 테이블과 동일하게 타입 검사한다 — 존재만 확인하면
			# `"laps": "three"` 류가 통과해 런타임까지 흘러간다.
			_check_value(String(file_name), String(required[field_name]),
				_scalar_text(structure[field_name]), String(structure.get("id", "?")), String(field_name))
		for array_field in spec["arrays"]:
			checked += _check_structure_array(String(file_name), structure, String(array_field), spec["arrays"][array_field])
	_report("V1", "schema", checked, before_fail, before_warn)


# 구조 JSON의 `template` 참조를 해소한다 (동형 구조 반복 정의 방지 — 서킷 20종 대비).
func _structure_spec(file_name: String) -> Dictionary:
	var spec: Dictionary = _config["structures"][file_name]
	if spec.has("template"):
		var templates: Dictionary = _config.get("structure_templates", {})
		var template_name := String(spec["template"])
		if not templates.has(template_name):
			_fail("V1", "%s: unknown structure template '%s'" % [file_name, template_name])
			return {"required": {}, "arrays": {}}
		spec = templates[template_name]
	return {"required": spec.get("required", {}), "arrays": spec.get("arrays", {})}


# 중첩 배열(서킷의 sectors 등) 검사: 원소 수 = 선언 필드와 일치 · 원소별 필수 필드 타입 검사.
func _check_structure_array(file_name: String, structure: Dictionary, array_field: String, array_spec: Dictionary) -> int:
	var checked := 0
	if not structure.has(array_field):
		_fail("V1", "%s: missing array '%s'" % [file_name, array_field])
		return 1
	var items: Variant = structure[array_field]
	if typeof(items) != TYPE_ARRAY:
		_fail("V1", "%s.%s: not an array" % [file_name, array_field])
		return 1
	var count_field := String(array_spec.get("count_field", ""))
	if count_field != "":
		var declared := int(structure.get(count_field, -1))
		if Array(items).size() != declared:
			_fail("V1", "%s.%s: %d entries but %s = %d" % [file_name, array_field, Array(items).size(), count_field, declared])
	var required: Dictionary = array_spec.get("required", {})
	for index in range(Array(items).size()):
		var item: Variant = Array(items)[index]
		checked += 1
		if typeof(item) != TYPE_DICTIONARY:
			_fail("V1", "%s.%s[%d]: not an object" % [file_name, array_field, index])
			continue
		var entry: Dictionary = item
		for field_name in required:
			if not entry.has(field_name):
				_fail("V1", "%s.%s[%d]: missing field '%s'" % [file_name, array_field, index, field_name])
				continue
			_check_value("%s.%s[%d]" % [file_name, array_field, index], String(required[field_name]),
				_scalar_text(entry[field_name]), String(structure.get("id", "?")), String(field_name))
	return checked


# JSON 스칼라를 검사용 문자열로 — 정수는 "3.0"이 아니라 "3"으로 (int 범위 검사 표기 보존).
func _scalar_text(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING:
			return String(value)
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			return str(float(value))
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_ARRAY:
			return "[array]"
		_:
			return "[object]"


func _structure_ids() -> Array:
	var ids: Array = []
	for file_name in _structures:
		var id_value := String(_structures[file_name].get("id", ""))
		if id_value != "":
			ids.append(id_value)
	return ids


func _check_value(file_name: String, type_spec: String, value: String, row_id: String, column_name: String) -> void:
	var trimmed := value.strip_edges()
	var parts := type_spec.split(":")
	var kind := parts[0]
	match kind:
		"id":
			if trimmed == "":
				_fail("V1", "%s[%s]: empty id" % [file_name, row_id])
		"float", "int":
			if trimmed == "":
				_fail("V1", "%s[%s].%s: empty numeric" % [file_name, row_id, column_name])
				return
			if not trimmed.is_valid_float():
				_fail("V1", "%s[%s].%s: not numeric '%s'" % [file_name, row_id, column_name, trimmed])
				return
			if parts.size() > 1:
				var bounds := parts[1].split(",")
				var numeric := trimmed.to_float()
				if numeric < bounds[0].to_float() or numeric > bounds[1].to_float():
					_fail("V1", "%s[%s].%s: %s out of range %s" % [file_name, row_id, column_name, trimmed, parts[1]])
		"float_optional":
			if trimmed != "" and not trimmed.is_valid_float():
				_fail("V1", "%s[%s].%s: not numeric '%s'" % [file_name, row_id, column_name, trimmed])
		"enum":
			if not Array(parts[1].split(",")).has(trimmed):
				_fail("V1", "%s[%s].%s: '%s' not in enum {%s}" % [file_name, row_id, column_name, trimmed, parts[1]])
		"enum_optional":
			if trimmed != "" and not Array(parts[1].split(",")).has(trimmed):
				_fail("V1", "%s[%s].%s: '%s' not in enum {%s}" % [file_name, row_id, column_name, trimmed, parts[1]])
		"string_key", "fk", "fk_optional", "fk_array", "string", "structure_ref", "structure_ref_array":
			pass  # V2 소관
		_:
			_warn("V1", "unknown type spec '%s'" % type_spec)


# ── V2 참조 무결성: 스트링 키·테이블 간 FK ──
func _run_v2_references() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	# 테이블 FK·name_key
	for file_name in _config["tables"]:
		var spec: Dictionary = _config["tables"][file_name]
		var columns: Dictionary = spec["columns"]
		for row in _tables[file_name]:
			for column_name in columns:
				var type_spec := String(columns[column_name])
				var value := String(row.get(column_name, "")).strip_edges()
				if type_spec == "string_key":
					checked += 1
					if not _strings.has(value):
						_fail("V2", "%s[%s].%s: string key '%s' not found" % [file_name, row.get("id", "?"), column_name, value])
				elif type_spec.begins_with("fk:"):
					checked += 1
					if not _table_ids(type_spec.substr(3)).has(value):
						_fail("V2", "%s[%s].%s: FK '%s' not found in %s" % [file_name, row.get("id", "?"), column_name, value, type_spec.substr(3)])
	# 구조 JSON (중첩 배열 포함 — 배열 안의 참조도 동일 규격으로 검사)
	var structure_ids := _structure_ids()
	for file_name in _config["structures"]:
		var spec := _structure_spec(String(file_name))
		var structure: Dictionary = _structures[file_name]
		var required: Dictionary = spec["required"]
		for field_name in required:
			var type_spec := String(required[field_name])
			if type_spec == "structure_ref_array":
				for item in structure.get(field_name, []):
					checked += 1
					if not structure_ids.has(String(item)):
						_fail("V2", "%s.%s: structure ref '%s' not found" % [file_name, field_name, item])
			elif type_spec.begins_with("fk_array:"):
				var target_ids := _table_ids(type_spec.substr(9))
				for item in structure.get(field_name, []):
					checked += 1
					if not target_ids.has(String(item)):
						_fail("V2", "%s.%s: FK '%s' not found" % [file_name, field_name, item])
			else:
				checked += _check_reference("%s.%s" % [file_name, field_name], type_spec,
					_scalar_text(structure.get(field_name, "")), structure_ids)
		for array_field in spec["arrays"]:
			var array_required: Dictionary = spec["arrays"][array_field].get("required", {})
			var items: Variant = structure.get(array_field, [])
			if typeof(items) != TYPE_ARRAY:
				continue
			for index in range(Array(items).size()):
				var item: Variant = Array(items)[index]
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = item
				for field_name2 in array_required:
					checked += _check_reference("%s.%s[%d].%s" % [file_name, array_field, index, field_name2],
						String(array_required[field_name2]), _scalar_text(entry.get(field_name2, "")), structure_ids)
	# 코드가 발행하는 스트링 키 (리터럴 스캔)
	var key_regex := RegEx.new()
	key_regex.compile(String(_config["key_regex"]))
	for entry in _code_files:
		var lines: Array = String(entry["source"]).split("\n")
		for line_index in range(lines.size()):
			for literal in _extract_literals(_strip_comment(lines[line_index])):
				if literal.contains("/") or literal.contains(":") or literal.contains(" ") or literal.contains("%"):
					continue
				# 파일명은 스트링 키와 형태가 겹친다(`progress.json` = 2단 키 문법 통과).
				# 스트링 키의 마지막 단이 파일 확장자인 경우는 없으므로 확장자로 갈라낸다.
				if _has_file_suffix(literal):
					continue
				if key_regex.search(literal) == null:
					continue
				checked += 1
				if not _strings.has(literal):
					_fail("V2", "%s:%d: code-emitted key '%s' not in strings" % [entry["path"], line_index + 1, literal])
	_report("V2", "references", checked, before_fail, before_warn)


func _collect_strings_deep(value: Variant, sink: Dictionary) -> void:
	match typeof(value):
		TYPE_STRING:
			sink[String(value)] = true
		TYPE_ARRAY:
			for item in Array(value):
				_collect_strings_deep(item, sink)
		TYPE_DICTIONARY:
			for key in Dictionary(value):
				_collect_strings_deep(Dictionary(value)[key], sink)


# 단일 참조 검사 (스트링 키 · 테이블 FK · 구조 id). 반환 = 수행한 검사 수.
# fk_optional의 공란은 "참조 없음"으로 통과 — 필수 참조는 fk를 쓴다.
func _check_reference(location: String, type_spec: String, value: String, structure_ids: Array) -> int:
	if type_spec == "string_key":
		if not _strings.has(value):
			_fail("V2", "%s: string key '%s' not found" % [location, value])
		return 1
	if type_spec == "structure_ref":
		if not structure_ids.has(value):
			_fail("V2", "%s: structure ref '%s' not found" % [location, value])
		return 1
	if type_spec.begins_with("fk_optional:"):
		if value == "":
			return 0
		if not _table_ids(type_spec.substr(12)).has(value):
			_fail("V2", "%s: FK '%s' not found in %s" % [location, value, type_spec.substr(12)])
		return 1
	if type_spec.begins_with("fk:"):
		if not _table_ids(type_spec.substr(3)).has(value):
			_fail("V2", "%s: FK '%s' not found in %s" % [location, value, type_spec.substr(3)])
		return 1
	return 0


func _has_file_suffix(literal: String) -> bool:
	for suffix in _config.get("key_scan_excluded_suffixes", []):
		if literal.ends_with(String(suffix)):
			return true
	return false


func _table_ids(file_name: String) -> Array:
	var ids: Array = []
	for row in _tables.get(file_name, []):
		ids.append(String(row.get("id", "")))
	return ids


# ── V3 스트링 작성 규격: 최대 줄 수·줄당 자수 (상한값 = D04 §5.1~5.3 → 설정 데이터) ──
func _run_v3_string_format() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	for key in _strings:
		var rule := _write_rule_for(String(key))
		if rule.is_empty():
			continue
		for language in _config["string_language_columns"]:
			var value := String(_strings[key].get(language, ""))
			if value == "":
				continue
			checked += 1
			var value_lines := value.split("\n")
			if value_lines.size() > int(rule["max_lines"]):
				_fail("V3", "'%s' (%s): %d lines > max %d" % [key, language, value_lines.size(), int(rule["max_lines"])])
			for value_line in value_lines:
				var width := _weighted_chars(value_line)
				if width > float(rule["max_chars_full"]):
					_fail("V3", "'%s' (%s): line width %.1f > max %d" % [key, language, width, int(rule["max_chars_full"])])
	_report("V3", "string format", checked, before_fail, before_warn)


func _write_rule_for(key: String) -> Dictionary:
	for rule in _config["string_write_rules"]:
		for prefix in rule["domain_prefixes"]:
			if key.begins_with(String(prefix)):
				return rule
	return {}


# ── V4 텍스트 하드코딩: 코드 내 한글 리터럴 금지 (화이트리스트 = 마커 주석) ──
func _run_v4_hardcoded_text() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var marker := String(_config["v4_whitelist_marker"])
	# 비표시 경로 제외 — 테스트 하네스의 진단 라벨은 플레이어에게 렌더되지 않는다.
	# 우회가 아니라 '표시 문자열'의 범위 선언이며, 제외 대상은 설정에 명시된 경로뿐이다.
	var exempt_dirs: Array = _config.get("v4_exempt_dirs", [])
	var sinks: Array = _config.get("v4_display_sinks", [])
	for entry in _code_files:
		if _is_exempt_path(String(entry["path"]), exempt_dirs):
			continue
		checked += _check_display_sinks(String(entry["path"]), String(entry["source"]), sinks, marker)
		var lines: Array = String(entry["source"]).split("\n")
		for line_index in range(lines.size()):
			var raw_line := String(lines[line_index])
			var code_line := _strip_comment(raw_line)
			for literal in _extract_literals(code_line):
				checked += 1
				if _has_hangul(literal) and not raw_line.contains(marker):
					_fail("V4", "%s:%d: hangul literal '%s'" % [entry["path"], line_index + 1, literal])
	_report("V4", "hardcoded text", checked, before_fail, before_warn)


# V4 확대: 표시 싱크(.text 등)에 닿는 문자열은 한글 여부와 무관하게 스트링 키여야 한다.
# 구 V4는 한글 리터럴만 봤으므로 `REEL_PLACEHOLDER := "???"` 류가 그대로 통과했다
# (MS-2 인계 §0.2-7). 상수를 경유한 우회도 추적한다 — 싱크에 대입된 상수의 값까지 검사.
func _check_display_sinks(path: String, source: String, sinks: Array, marker: String) -> int:
	var checked := 0
	if sinks.is_empty():
		return 0
	var lines: Array = source.split("\n")
	var sink_bound_consts: Dictionary = {}
	var const_literals: Dictionary = {}
	var const_regex := RegEx.new()
	const_regex.compile("^\\s*const\\s+([A-Z][A-Z0-9_]*)\\s*:?=\\s*\"(.*)\"\\s*$")
	var identifier_regex := RegEx.new()
	identifier_regex.compile("[A-Z][A-Z0-9_]{2,}")
	for line_index in range(lines.size()):
		var raw_line := String(lines[line_index])
		var const_match := const_regex.search(raw_line)
		if const_match != null:
			const_literals[const_match.get_string(1)] = {"value": const_match.get_string(2), "line": line_index + 1}
			continue
		var code_line := _strip_comment(raw_line)
		var assigned := _sink_assignment_expression(code_line, sinks)
		if assigned == "":
			continue
		for literal in _extract_literals(_strip_subscript_literals(assigned)):
			checked += 1
			if raw_line.contains(marker) or _is_layout_literal(literal) or _strings.has(literal):
				continue
			_fail("V4", "%s:%d: display sink literal '%s' is not a string key" % [path, line_index + 1, literal])
		for identifier in identifier_regex.search_all(assigned):
			sink_bound_consts[identifier.get_string()] = line_index + 1
	for const_name in sink_bound_consts:
		if not const_literals.has(const_name):
			continue
		var literal_value := String(const_literals[const_name]["value"])
		checked += 1
		if _is_layout_literal(literal_value) or _strings.has(literal_value):
			continue
		_fail("V4", "%s:%d: const '%s' = '%s' reaches a display sink but is not a string key"
			% [path, const_literals[const_name]["line"], const_name, literal_value])
	return checked


# 딕셔너리·배열 첨자의 문자열(`["name_key"]`)은 데이터 열 이름이므로 표시 문자열이 아니다.
func _strip_subscript_literals(expression: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[\\s*\"[^\"]*\"\\s*\\]")
	return regex.sub(expression, "[]", true)


# 싱크 대입문의 우변을 돌려준다 (없으면 공란). `label.text = <우변>` / `:=` 모두 대응.
func _sink_assignment_expression(code_line: String, sinks: Array) -> String:
	for sink in sinks:
		var needle := ".%s" % String(sink)
		var sink_index := code_line.find(needle)
		while sink_index >= 0:
			var rest := code_line.substr(sink_index + needle.length())
			var stripped := rest.strip_edges(true, false)
			if stripped.begins_with("=") and not stripped.begins_with("=="):
				return stripped.substr(1)
			if stripped.begins_with(":="):
				return stripped.substr(2)
			sink_index = code_line.find(needle, sink_index + 1)
	return ""


# 표시 문자열이 아닌 레이아웃·구분 리터럴: 공백류 전용 (줄바꿈·구분 공백 등).
# `"???"`처럼 글자·기호를 담은 것은 여기서 걸러지지 않는다 — 그것이 확대의 목적이다.
func _is_layout_literal(literal: String) -> bool:
	if literal == "":
		return true
	for i in range(literal.length()):
		var ch := literal[i]
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
			continue
		# 소스에 적힌 이스케이프 표기("\\n" 두 글자)도 줄바꿈 의도로 인정한다
		if ch == "\\" and i + 1 < literal.length() and "ntr".contains(literal[i + 1]):
			continue
		if ch == "n" or ch == "t" or ch == "r":
			if i > 0 and literal[i - 1] == "\\":
				continue
		return false
	return true


func _is_exempt_path(path: String, exempt_dirs: Array) -> bool:
	for dir_path in exempt_dirs:
		if path.begins_with(String(dir_path)):
			return true
	return false


# ── 아키텍처 규칙 스캔 (혼입 0 스캔과 같은 정적 축) ──
# 테스트로 닫을 수 없는 종류의 위반을 잡는다:
#  ①정책 층 우회 — 세이브 I/O를 정책 층(백업 회전·프로필 분리·마이그레이션) 밖에서 직접 호출
#  ②코어의 표준출력 — 코어는 순수 로직이며 출력 경로를 갖지 않는다. print는 봉인 규칙의
#    누출 경로이기도 하다(릴 정지 전 결과를 stdout으로 흘리면 어떤 헤드리스 테스트도 못 잡는다).
func _run_architecture_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	for rule in _config.get("architecture_rules", []):
		var spec: Dictionary = rule
		var patterns: Array = spec.get("forbidden", [])
		var scope: Array = spec.get("scope", [])
		var allowed: Array = spec.get("allow", [])
		var label := String(spec.get("name", "rule"))
		var reason := String(spec.get("reason", ""))
		for entry in _code_files:
			var path := String(entry["path"])
			if not _path_in_scope(path, scope) or _is_exempt_path(path, allowed):
				continue
			var lines: Array = String(entry["source"]).split("\n")
			for line_index in range(lines.size()):
				var code_line := _strip_comment(String(lines[line_index]))
				for pattern in patterns:
					checked += 1
					if code_line.contains(String(pattern)):
						_fail("ARCH", "%s:%d: %s — '%s' (%s)"
							% [path, line_index + 1, label, pattern, reason])
	_report("ARCH", "architecture rules", checked, before_fail, before_warn)


# 빈 scope = 전 코드. 그 외에는 접두 일치.
func _path_in_scope(path: String, scope: Array) -> bool:
	if scope.is_empty():
		return true
	for prefix in scope:
		if path.begins_with(String(prefix)):
			return true
	return false


# ── V5 앵커 결속 유형: anchor_type ∈ 허용 / tour_slot ∈ {1,5} (D08 §2.3 기계 이행) ──
func _run_v5_anchor_binding() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var rule: Dictionary = _config["anchor_rule"]
	var anchor_field := String(rule["anchor_field"])
	var slot_field := String(rule["tour_slot_field"])
	# 허용 슬롯을 정수로 정규화한다. JSON 수치는 float로 적재되므로 int 슬롯 값과
	# Array.has() 비교가 어긋나 허용값(1)이 위반으로 잡혔다 — MS-1에는 앵커 필드를 가진
	# 구조 JSON이 없어 이 경로가 실행되지 않았고, 결함이 드러나지 않았다.
	var allowed_slots: Array = []
	for slot_value in Array(rule["allowed_tour_slots"]):
		allowed_slots.append(int(slot_value))
	for file_name in _tables:
		for row in _tables[file_name]:
			if row.has(anchor_field):
				checked += 1
				if not Array(rule["allowed_anchor_types"]).has(String(row[anchor_field]).strip_edges()):
					_fail("V5", "%s[%s]: anchor_type '%s' not allowed" % [file_name, row.get("id", "?"), row[anchor_field]])
			if row.has(slot_field):
				checked += 1
				var slot := String(row[slot_field]).strip_edges().to_int()
				if not allowed_slots.has(slot):
					_fail("V5", "%s[%s]: tour_slot %d not in %s" % [file_name, row.get("id", "?"), slot, str(allowed_slots)])
	for file_name in _structures:
		var structure: Dictionary = _structures[file_name]
		if structure.has(anchor_field):
			checked += 1
			if not Array(rule["allowed_anchor_types"]).has(String(structure[anchor_field])):
				_fail("V5", "%s: anchor_type '%s' not allowed" % [file_name, structure[anchor_field]])
		if structure.has(slot_field):
			checked += 1
			if not allowed_slots.has(int(structure[slot_field])):
				_fail("V5", "%s: tour_slot %d not in %s" % [file_name, int(structure[slot_field]), str(allowed_slots)])
	_report("V5", "anchor binding", checked, before_fail, before_warn)


# ── V6 ID 위생: 전역 유일·도메인 접두 = 차단 / 고아 데이터 = 경고 (D12 §4.2 V6 행) ──
func _run_v6_id_hygiene() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var seen: Dictionary = {}
	var all_referenced: Dictionary = {}
	# 참조 수집: FK 값 + 구조 참조 + 코드 리터럴
	for file_name in _tables:
		var columns: Dictionary = _config["tables"][file_name]["columns"]
		for row in _tables[file_name]:
			for column_name in columns:
				if String(columns[column_name]).begins_with("fk:"):
					all_referenced[String(row.get(column_name, "")).strip_edges()] = true
	# 구조 JSON은 중첩 깊이를 가정하지 않고 전 문자열 값을 참조로 수집한다 —
	# 배열 안(서킷 sectors의 main_attr 등)의 참조가 고아 오탐으로 새지 않게.
	for file_name in _structures:
		_collect_strings_deep(_structures[file_name], all_referenced)
	for entry in _code_files:
		for line in String(entry["source"]).split("\n"):
			for literal in _extract_literals(_strip_comment(line)):
				all_referenced[literal] = true
	# 유일성·접두·고아
	for file_name in _tables:
		var spec: Dictionary = _config["tables"][file_name]
		var prefix := String(spec["id_prefix"])
		var is_root := bool(spec.get("root", false))
		for row in _tables[file_name]:
			var row_id := String(row.get("id", "")).strip_edges()
			checked += 1
			if seen.has(row_id):
				_fail("V6", "duplicate id '%s' (%s, %s)" % [row_id, seen[row_id], file_name])
			seen[row_id] = file_name
			if not row_id.begins_with(prefix):
				_fail("V6", "%s: id '%s' missing domain prefix '%s'" % [file_name, row_id, prefix])
			if not is_root and not all_referenced.has(row_id):
				_warn("V6", "orphan instance '%s' in %s (unreferenced)" % [row_id, file_name])
	# 스트링 키 고아 (경고): 코드·테이블·구조 어디서도 참조되지 않는 키
	for file_name in _tables:
		var columns: Dictionary = _config["tables"][file_name]["columns"]
		for row in _tables[file_name]:
			for column_name in columns:
				if String(columns[column_name]) == "string_key":
					all_referenced[String(row.get(column_name, "")).strip_edges()] = true
	for file_name in _structures:
		_collect_strings_deep(_structures[file_name], all_referenced)
	for key in _strings:
		checked += 1
		if not all_referenced.has(String(key)):
			_warn("V6", "orphan string key '%s'" % key)
	_report("V6", "id hygiene", checked, before_fail, before_warn)


# ── V7 금칙 어휘 (경고 전용 — 차단 아님, D12 §4.2 확정): 발화 도메인 값 내 시스템 언어 후보 ──
func _run_v7_forbidden_vocab() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	for key in _strings:
		var in_domain := false
		for prefix in _config["v7_domains"]:
			if String(key).begins_with(String(prefix)):
				in_domain = true
				break
		if not in_domain:
			continue
		for language in _config["string_language_columns"]:
			var value := String(_strings[key].get(language, ""))
			checked += 1
			for term in _config["v7_terms"]:
				if value.contains(String(term)):
					_warn("V7", "'%s' (%s): candidate term '%s' — D04 트랙 검토 대상" % [key, language, term])
	_report("V7", "forbidden vocab (warn-only)", checked, before_fail, before_warn)


# ── V8 스트링 키 문법: camelCase 세그먼트·`.` 구분자 전속 (D12 §8.1 결정 #9) ──
func _run_v8_key_grammar() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var key_regex := RegEx.new()
	key_regex.compile(String(_config["key_regex"]))
	for key in _strings:
		checked += 1
		if key_regex.search(String(key)) == null:
			_fail("V8", "invalid key grammar: '%s'" % key)
	_report("V8", "key grammar", checked, before_fail, before_warn)


# ── 혼입 0 스캔: core 디렉토리 내 플랫폼 API·분기·수익 코드 검출 (D12 §2.1) ──
func _run_contamination_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var core_prefix := String(_config["core_dir"])
	for entry in _code_files:
		if not String(entry["path"]).begins_with(core_prefix):
			continue
		var lines: Array = String(entry["source"]).split("\n")
		for line_index in range(lines.size()):
			var code_line := _strip_comment(String(lines[line_index]))
			checked += 1
			for pattern in _config["contamination_patterns"]:
				if code_line.contains(String(pattern)):
					_fail("MIX0", "%s:%d: platform pattern '%s'" % [entry["path"], line_index + 1, pattern])
	_report("MIX0", "core contamination scan", checked, before_fail, before_warn)
