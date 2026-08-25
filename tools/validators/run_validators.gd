# 빌드 기계 검증기 V1~V8 + 혼입 0 스캔 (D12 §4.2 · D14 §2.1 TL-1 / CLAUDE.md 불변규칙 7)
#
# 실행 (리포지토리 루트에서 — 로컬 단일 명령):
#   godot --headless --path . --script tools/validators/run_validators.gd
#
# 차단 규칙: V1~V6·V8 + 혼입 0 스캔 = 위반 1건이면 실패(exit 1).
# 구현 층 신설 검사 **MIX0·ARCH·FONT·PAL·ANCH·STRF·AUD 도 차단형**이다 (불변규칙 7 —
#   FONT = 총괄 판정 IMPL-148 · PAL = 조건부 기승인 IMPL-209 → 발동 IMPL-219 ·
#   ANCH = 경고형 신설 IMPL-233 → 규칙 확대 + 차단형 전환 IMPL-237 ·
#   STRF = 차단형 즉시 신설 IMPL-249 ③).
#   (AUD = 경고형 신설 IMPL-260 → **차단형 전환 IMPL-262** — 실측 깨끗(위반 0·오검출 0·돌연변이 10종) 후
#    총괄 판정 승인. FONT·PAL·ANCH·STRF 와 같은 절차다.)
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
var _aud_completed := false         # AUD 스캔 완주 표시 — 아래 관문의 근거
var _aud_frames: Dictionary = {}    # id -> 프레임 수 (A/B 쌍 대조용)


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
	_run_v7_self_test()
	_run_v8_key_grammar()
	_run_contamination_scan()
	_run_architecture_scan()
	_run_font_scan()
	_run_palette_scan()
	_run_anchor_scan()
	_run_string_field_scan()
	_run_audio_asset_scan()
	_run_fx_placement_scan()
	_run_cut_layout_scan()
	# **완주 관문** — 스캔이 중도 이탈하면 실패 0·보고 0 으로 통과가 찍힌다(2026-08-20 실측:
	# OGG 헤더의 없는 키를 `header["x"]` 로 읽자 함수가 이탈하고 게이트가 `VALIDATORS_PASS` 를 냈다).
	# `run_tests.sh` 가 "성공 토큰의 부재 자체를 실패로 본다"고 한 것과 같은 축이다 —
	# **검사는 자기 자신을 검사하지 못한다.**
	if not _aud_completed:
		_fail("AUD", "스캔이 완주하지 못했다 — 검사 없음이 위반 없음으로 통과할 수 없다")
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
		elif entry.ends_with(".tscn"):
			# 씬도 색 리터럴을 갖는다 (PAL) — 코드만 훑으면 그쪽이 통째로 사각이 된다.
			_scene_files.append({"path": full_path, "source": _read_text(full_path)})
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
		# 상호 배타 필드 (RB-1 판정 이행): 주·부속성이 같으면 규칙 계수가 곱해져
		# ×1.8 명문 상한을 넘는다(1.5 × 1.25 = 1.875). 데이터 단계에서 차단한다.
		for pair in array_spec.get("distinct", []):
			var first := String(Array(pair)[0])
			var second := String(Array(pair)[1])
			var first_value := String(entry.get(first, "")).strip_edges()
			var second_value := String(entry.get(second, "")).strip_edges()
			checked += 1
			if first_value != "" and first_value == second_value:
				_fail("V1", "%s.%s[%d]: %s와 %s가 같다 ('%s') — 규칙 계수 곱으로 ×1.8 상한 위반"
					% [file_name, array_field, index, first, second, first_value])
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
		"string_key", "fk", "fk_optional", "fk_array", "string", \
		"structure_ref", "structure_ref_optional", "structure_ref_array", "string_key_optional", \
		"structure_entry_ref", "structure_entry_ref_optional":
			pass  # V2 소관
		_:
			_warn("V1", "unknown type spec '%s'" % type_spec)


# ── V2 참조 무결성: 스트링 키·테이블 간 FK ──
func _run_v2_references() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var structure_ids := _structure_ids()
	# 테이블 참조 — **구조 JSON 과 같은 판정기를 쓴다** (`_check_reference`).
	#
	# 22차 실측: 이 자리는 `string_key` 와 `fk:` **두 종만** 보고 있었고,
	# `fk_optional:`·`structure_ref`·`structure_ref_optional` 열은 **아무도 보지 않았다**
	# (표 열 5개 = `garage_facilities.requires_crew` · `milestone_vn.relation_transition` ·
	# `milestones.source_id` · `vn_beats.axis_id` · `vn_beats.stage_id`).
	# 검사기가 둘로 갈려 있었고 한쪽만 자란 결과다 — 판정기를 하나로 모아 닫는다.
	# **통과는 검사의 증거가 아니다**: 19차 회신이 `stage_id` 를 "V2 가 실제로 걸었다"로
	# 적었으나 그때 걸린 것은 아무것도 없었다(볼 분기가 없었다).
	for file_name in _config["tables"]:
		var spec: Dictionary = _config["tables"][file_name]
		var columns: Dictionary = spec["columns"]
		for row in _tables[file_name]:
			for column_name in columns:
				var type_spec := String(columns[column_name])
				var value := String(row.get(column_name, "")).strip_edges()
				checked += _check_reference(
					"%s[%s].%s" % [file_name, row.get("id", "?"), column_name],
					type_spec, value, structure_ids)
	# 구조 JSON (중첩 배열 포함 — 배열 안의 참조도 동일 규격으로 검사)
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
	# 공란 = "문면 없음"으로 통과. `structure_ref_optional` 과 동형이며 근거도 같다 —
	# **필수 참조는 `string_key` 를 쓴다.** 선택형을 기본으로 두면 오타가 공란과 구분되지 않는다.
	if type_spec == "string_key_optional":
		if value == "":
			return 0
		if not _strings.has(value):
			_fail("V2", "%s: string key '%s' not found" % [location, value])
		return 1
	if type_spec == "structure_ref":
		if not structure_ids.has(value):
			_fail("V2", "%s: structure ref '%s' not found" % [location, value])
		return 1
	# 공란 = "참조 없음"으로 통과. `fk_optional:` 과 동형이며 근거도 같다 —
	# **필수 참조는 `structure_ref` 를 쓴다.** 선택형을 기본으로 두면 오타가 공란과
	# 구분되지 않으므로, 선택화는 열 단위로 명시 선언하는 것만 허용한다.
	if type_spec == "structure_ref_optional":
		if value == "":
			return 0
		if not structure_ids.has(value):
			_fail("V2", "%s: structure ref '%s' not found" % [location, value])
		return 1
	# ── 구조 JSON **항목** 참조 (28차 신설) ──
	# `structure_ref` 는 구조 **파일**의 최상위 id 만 본다(`act_vn`). 그런데 CG 대장이 가리키는
	# 것은 파일이 아니라 그 안의 항목(`vn_origin`)이라 기존 타입으로는 검사가 값을 보지 못한다 —
	# 문자열 열로 두면 오타가 조용히 통과하고, 그것이 27차에 트리거 3열을 나눈 것과 같은 사유다.
	# 형식 = `structure_entry_ref[_optional]:<파일>:<배열 필드>`.
	if type_spec.begins_with("structure_entry_ref"):
		var spec_parts := type_spec.split(":")
		if spec_parts.size() < 3:
			_fail("V2", "%s: malformed structure entry ref spec '%s'" % [location, type_spec])
			return 1
		if value == "" and String(spec_parts[0]).ends_with("_optional"):
			return 0
		var entry_ids := _structure_entry_ids(String(spec_parts[1]), String(spec_parts[2]))
		if not entry_ids.has(value):
			_fail("V2", "%s: structure entry '%s' not found in %s.%s"
				% [location, value, spec_parts[1], spec_parts[2]])
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


func _structure_entry_ids(file_name: String, array_field: String) -> Array:
	var ids: Array = []
	var structure: Dictionary = _structures.get(file_name, {})
	for entry in Array(structure.get(array_field, [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_id := String((entry as Dictionary).get("id", ""))
		if entry_id != "":
			ids.append(entry_id)
	return ids


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
	# 지역 변수 추적 (IMPL-074 확대): 함수 스코프 안에서 문자열 리터럴이 대입된 지역 변수가
	# 표시 싱크에 닿으면 그 리터럴도 검사 대상이다. 대입은 선언(var)·재대입·누적(+=) 전부 본다.
	# 한계(기록): 싱크 라인 **뒤**의 재대입은 추적하지 않는다 — 선언 전 사용은 파스 에러라
	# 컴파일 게이트가 먼저 잡고, 뒤 재대입이 싱크에 닿으려면 루프 역류가 필요해 실코드에 드물다.
	var local_assign_regex := RegEx.new()
	local_assign_regex.compile("^\\s*(?:var\\s+)?([a-z_][a-z0-9_]*)\\s*(?::\\s*[A-Za-z_]+\\s*)?\\+?[:]?=(?!=)(.*)$")
	var local_id_regex := RegEx.new()
	local_id_regex.compile("(?<![.\\w])([a-z_][a-z0-9_]*)\\b(?![\\w(])")
	var func_regex := RegEx.new()
	func_regex.compile("^(?:static\\s+)?func\\s")
	var local_literals: Dictionary = {}   # 이름 -> [{value, line, raw}] (함수 경계에서 리셋)
	for line_index in range(lines.size()):
		var raw_line := String(lines[line_index])
		var const_match := const_regex.search(raw_line)
		if const_match != null:
			const_literals[const_match.get_string(1)] = {"value": const_match.get_string(2), "line": line_index + 1}
			continue
		if func_regex.search(raw_line) != null:
			local_literals = {}   # 함수 경계 — 지역 스코프 리셋
			continue
		var code_line := _strip_comment(raw_line)
		var assigned := _sink_assignment_expression(code_line, sinks)
		if assigned == "":
			# 싱크 대입이 아니면 지역 변수 리터럴 대입인지 본다
			var local_match := local_assign_regex.search(code_line)
			if local_match != null:
				var rhs := _strip_dict_key_literals(_strip_subscript_literals(local_match.get_string(2)))
				for literal in _extract_literals(rhs):
					var entries: Array = local_literals.get(local_match.get_string(1), [])
					entries.append({"value": literal, "line": line_index + 1, "raw": raw_line})
					local_literals[local_match.get_string(1)] = entries
			continue
		var stripped_rhs := _strip_dict_key_literals(_strip_subscript_literals(assigned))
		for literal in _extract_literals(stripped_rhs):
			checked += 1
			if raw_line.contains(marker) or _is_layout_literal(literal) \
				or _is_table_id_literal(literal) or _strings.has(literal):
				continue
			_fail("V4", "%s:%d: display sink literal '%s' is not a string key" % [path, line_index + 1, literal])
		for identifier in identifier_regex.search_all(assigned):
			sink_bound_consts[identifier.get_string()] = line_index + 1
		# 싱크에 닿은 지역 변수 — 이 함수 안에서 그 변수에 대입된 리터럴 전부를 검사한다.
		# 문자열 내부의 낱말이 식별자로 잡히지 않도록 리터럴을 지운 우변에서 찾는다.
		var rhs_without_strings := stripped_rhs
		for literal in _extract_literals(stripped_rhs):
			rhs_without_strings = rhs_without_strings.replace("\"%s\"" % literal, "\"\"")
		for id_match in local_id_regex.search_all(rhs_without_strings):
			var local_name := id_match.get_string(1)
			if not local_literals.has(local_name):
				continue
			for entry in local_literals[local_name]:
				checked += 1
				var value := String(entry["value"])
				if String(entry["raw"]).contains(marker) or raw_line.contains(marker) \
					or _is_layout_literal(value) or _is_table_id_literal(value) or _strings.has(value):
					continue
				_fail("V4", "%s:%d: local '%s' = '%s' reaches a display sink (line %d) but is not a string key"
					% [path, int(entry["line"]), local_name, value, line_index + 1])
	for const_name in sink_bound_consts:
		if not const_literals.has(const_name):
			continue
		var literal_value := String(const_literals[const_name]["value"])
		checked += 1
		if _is_layout_literal(literal_value) or _is_table_id_literal(literal_value) or _strings.has(literal_value):
			continue
		_fail("V4", "%s:%d: const '%s' = '%s' reaches a display sink but is not a string key"
			% [path, const_literals[const_name]["line"], const_name, literal_value])
	return checked


# 딕셔너리 **키** 리터럴(`{"value": …}`)은 명명 플레이스홀더·매개 이름이지 표시 문자열이
# 아니다 (IMPL-074가 오탐으로 실측한 축). 값 리터럴은 남는다 — 치환되어 화면에 실리므로.
# `.get("name_key", …)`의 첫 인자도 같은 축이다 — 첨자 접근(`["name_key"]`)의 함수형.
func _strip_dict_key_literals(expression: String) -> String:
	var regex := RegEx.new()
	regex.compile("\"[A-Za-z0-9_.]*\"\\s*:")
	var stripped := regex.sub(expression, ":", true)
	var getter := RegEx.new()
	getter.compile("\\.get\\(\\s*\"[A-Za-z0-9_.]*\"")
	return getter.sub(stripped, ".get(\"\"", true)


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


# 테이블 ID·데이터 열 이름 문법 (불변규칙 6 — snake_case, 스트링 키와 **별개 체계**).
# 밑줄을 포함한 순수 snake_case 토큰은 데이터 이름이지 표시 문자열이 아니다
# (`param_charge_hold_cost` 등 — 데이터 조회 헬퍼의 인자로 싱크 식에 나타난다).
# 밑줄 없는 단일 낱말("error" 등)은 면제하지 않는다 — 표시 문자열일 수 있다.
func _is_table_id_literal(literal: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9]*(_[a-z0-9]+)+$")
	return regex.search(literal) != null


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


# ── FONT 코드 생성 Control 폰트 정적 검사 (마스터플랜 v2.35 ⑧ 지시 · 신설 IMPL-147) ──
#
# **왜 기계인가.** 코드로 만든 Control 은 프로젝트 기본 폰트 크기를 상속하지 않고
# 엔진 기본 테마의 16 으로 해석된다(실측). 640×360 캔버스에서 16 은 레이아웃을 깨뜨리는데,
# `.tscn` 노드는 멀쩡하고 코드 생성분만 새기 때문에 화면을 훑어서는 잡히지 않는다 —
# 실제로 12개 화면 34지점이 이 방식으로 샜다(본 검사 신설 시점 실측).
#
# 축 2종:
#   FONT-A 코드 생성 텍스트 Control 에 `add_theme_font_size_override` 부재
#   FONT-B 폰트 크기를 리터럴로 기입 (불변규칙 2 — 값 창구는 D13·core_params)
#
# **성격 = 차단형 (총괄 판정 IMPL-148 · 집행 IMPL-168).** 신설 시에는 성격을 구현이 정하지
# 않는다는 원칙(V7 전례)에 따라 경고형으로 두고 판정을 올렸고, 판정은 차단형으로 났다 —
# "폰트를 지정했는가"는 **문법 수준 기계 판정**이라 V7(작법 판단이 D04 소관이라 경고형)의
# 사유가 적용되지 않고, 오검출 0 실측·눈 검증 불가(37건)가 근거다. 축은 V4 계열이다.
# **V7은 여전히 경고 전용** — 불변규칙 7.
const FONT_TEXT_CONTROLS := ["Label", "Button", "RichTextLabel", "LineEdit", "CheckBox",
	"CheckButton", "OptionButton", "TextEdit", "LinkButton", "MenuButton", "ItemList",
	"Tree", "TabBar", "SpinBox"]
const FONT_OVERRIDE_CALL := ".add_theme_font_size_override("


func _run_font_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	for entry in _code_files:
		var path := String(entry["path"])
		if not path.begins_with("godot/ui"):
			continue
		var lines: Array = String(entry["source"]).split("\n")
		var overridden := _font_overridden_names(lines)
		for line_index in range(lines.size()):
			var code_line := _strip_comment(String(lines[line_index]))
			# FONT-B — 리터럴 기입
			var literal_size := _font_literal_size(code_line)
			if literal_size != "":
				checked += 1
				_fail("FONT", "%s:%d: 폰트 크기 리터럴 '%s' — 값 창구는 D13(core_params) 전속"
					% [path, line_index + 1, literal_size])
			# FONT-A — 오버라이드 부재
			var created := _font_control_declaration(code_line)
			if created.is_empty():
				continue
			checked += 1
			if not overridden.has(String(created["name"])):
				_fail("FONT", "%s:%d: 코드 생성 %s '%s' 폰트 크기 미지정 — 엔진 기본 16 으로 해석된다"
					% [path, line_index + 1, String(created["type"]), String(created["name"])])
	_report("FONT", "code-created control fonts", checked, before_fail, before_warn)


# 파일 안에서 폰트 크기 오버라이드를 받은 변수 이름 집합.
# 함수 단위가 아니라 파일 단위로 본다 — 생성과 적용이 헬퍼로 갈리는 형태가 흔하고,
# 함수 경계로 좁히면 그 형태가 전부 오검출된다 (경고형 검사의 신뢰를 먼저 잃는다).
func _font_overridden_names(lines: Array) -> Dictionary:
	var names: Dictionary = {}
	for line in lines:
		var code_line := _strip_comment(String(line))
		var call_at := code_line.find(FONT_OVERRIDE_CALL)
		if call_at < 0:
			continue
		var head := code_line.substr(0, call_at)
		var start := head.length() - 1
		while start >= 0 and (head[start] == "_" or head[start].is_valid_identifier()):
			start -= 1
		var name := head.substr(start + 1)
		if name != "":
			names[name] = true
	return names


# `var x := Label.new()` / `var x: Label = Label.new()` → {name, type}
func _font_control_declaration(code_line: String) -> Dictionary:
	var trimmed := code_line.strip_edges()
	if not trimmed.begins_with("var "):
		return {}
	var assign_at := trimmed.find("=")
	if assign_at < 0:
		return {}
	var rhs := trimmed.substr(assign_at + 1).strip_edges()
	var control_type := ""
	for type_name in FONT_TEXT_CONTROLS:
		if rhs.begins_with(String(type_name) + ".new("):
			control_type = String(type_name)
			break
	if control_type == "":
		return {}
	# 좌변에서 변수명만 떼어낸다 (`var x :` / `var x :=` 양 형태)
	var lhs := trimmed.substr(4, assign_at - 4).strip_edges()
	var colon_at := lhs.find(":")
	if colon_at >= 0:
		lhs = lhs.substr(0, colon_at).strip_edges()
	if lhs == "":
		return {}
	return {"name": lhs, "type": control_type}


# `add_theme_font_size_override("font_size", 9)` 의 리터럴 인자 — 변수·호출이면 빈 문자열.
func _font_literal_size(code_line: String) -> String:
	var call_at := code_line.find(FONT_OVERRIDE_CALL)
	if call_at < 0:
		return ""
	var args := code_line.substr(call_at + FONT_OVERRIDE_CALL.length())
	var comma_at := args.find(",")
	if comma_at < 0:
		return ""
	var value := args.substr(comma_at + 1)
	var close_at := value.find(")")
	if close_at >= 0:
		value = value.substr(0, close_at)
	value = value.strip_edges()
	return value if value.is_valid_int() or value.is_valid_float() else ""


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
				# **선택형 FK 도 참조다** (28차 자기 점검 — 27차 `string_key_optional` 과 동형).
				# `fk:` 만 모으면 **`fk_optional:` 로만 가리켜지는 행이 고아로 잡힌다.** 지금은
				# 대상 3표(ai_teams·ai_rivals·sector_attributes)가 선택형 FK 의 대상이 아니라
				# 잠복 상태지만, 구멍의 형태는 22차 V2 표 열·27차 V6 선택 키와 같다 —
				# **새 타입을 한 자리에만 넣는** 그 형태다.
				var column_type := String(columns[column_name])
				if column_type.begins_with("fk:") or column_type.begins_with("fk_optional:"):
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
				# **선택형도 참조다** — `string_key_optional` 을 빼면 그 열이 가리키는 키가
				# 전부 고아로 잡힌다(27차 실측: `title_key` 8건). 새 타입을 한 검사에만
				# 넣고 다른 검사에 넣지 않는 것이 22차 V2 구멍과 같은 형태다.
				if String(columns[column_name]) in ["string_key", "string_key_optional"]:
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
			# 어휘 목록은 **언어별**이다 (내러티브 4차 §6-E). 일문에서 `リール`·`スピン`·
			# `ホールド` 는 UI 층 정식 용어이면서 동시에 발화 층 금칙 후보의 가타카나형이므로,
			# 국문 목록 하나로는 일문 발화 도메인에서 **통과만 찍는다** — 열을 등재하고
			# 어휘를 확장하지 않으면 검사가 도는 것과 보는 것이 갈린다.
			for term in _config["v7_terms"].get(language, []):
				if _contains_term(value, String(term)):
					_warn("V7", "'%s' (%s): candidate term '%s' — D04 트랙 검토 대상" % [key, language, term])
	_report("V7", "forbidden vocab (warn-only)", checked, before_fail, before_warn)


# 라틴 어휘는 **단어 경계**로 본다. 부분 문자열로 잡으면 `threshold` 가 `hold` 로,
# `spinning` 이 `spin` 으로 걸려 경고가 소음이 된다 — 소음이 쌓인 경고는 읽히지 않고,
# 읽히지 않는 경고는 없는 것과 같다(V7 은 D04 트랙의 판단 입력이지 기계 판정이 아니다).
# CJK 는 단어 경계가 문자 경계와 다르므로 부분 문자열이 옳다.
func _contains_term(value: String, term: String) -> bool:
	var latin := true
	for index in range(term.length()):
		if term.unicode_at(index) > 0x7F:
			latin = false
			break
	if not latin:
		return value.contains(term)
	var from := 0
	while true:
		var at := value.findn(term, from)
		if at < 0:
			return false
		var before_ok := at == 0 or not _is_word_char(value.unicode_at(at - 1))
		var after_index := at + term.length()
		var after_ok := after_index >= value.length() or not _is_word_char(value.unicode_at(after_index))
		if before_ok and after_ok:
			return true
		from = at + 1
	return false


# ── V7S: V7 판정 논리 자기 검사 (차단형) ──
#
# V7 의 **판정**은 경고형이어야 한다(작법 판단 = D04 소관 · 불변규칙 7). 그런데 그 결과
# **V7 이 얼마나 시끄러워졌는지는 종료코드가 구분하지 못한다** — 단어 경계 판정을 부분
# 문자열로 되돌리면 `threshold` 가 `hold` 로 걸려 경고가 소음이 되고, 읽히지 않는 경고는
# 없는 것과 같은데도 빌드는 녹색이다(돌연변이 F3 미검출로 실측).
#
# 그래서 **내용 판정과 검사기 자신의 판정 논리를 가른다.** 어느 문면이 금칙인지는 D04 가
# 판단하고(경고), 판정 논리가 규격대로 작동하는지는 기계가 판단한다(차단). 컴파일 게이트가
# 자기 성공 토큰의 부재를 실패로 보는 것과 같은 자리다 — 검사는 자기 자신을 검사하지 못한다.
func _run_v7_self_test() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	# [입력, 어휘, 기대]
	var cases := [
		["Candidate locked. Recompute.", "hold", false],
		["threshold reached", "hold", false],          # 부분 문자열 판정이면 여기서 걸린다
		["household data", "hold", false],
		["Hold the second reel.", "hold", true],       # 대소문자 무시
		["spinning up", "spin", false],
		["Spin the Grid", "spin", true],
		["reeling in", "reel", false],
		["the reel stops", "reel", true],
		["決着局面。リール集中。", "リール", true],        # CJK = 부분 문자열이 옳다
		["決着局面。演算集中。", "リール", false],
		["확률 분포", "확률", true],
		["연산 분포", "확률", false],
	]
	for case in cases:
		checked += 1
		var actual := _contains_term(String(case[0]), String(case[1]))
		if actual != bool(case[2]):
			_fail("V7S", "'%s' × '%s': %s (기대 %s)"
				% [case[0], case[1], str(actual), str(case[2])])
	_report("V7S", "V7 term matcher self-test", checked, before_fail, before_warn)


func _is_word_char(code: int) -> bool:
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
		or (code >= 97 and code <= 122) or code == 95


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


# ── CUTM 컷 머신 배치 전사 대조 (신설 31차 — **경고형** · 에셋 IMPL-444·447) ──
#
# **왜 필요한가 — 반증이 먼저 말했다.** 자리 좌표를 오기해도(Q11: `anchor_x` 344→300)
# 게이트가 통과했다. UISCR 은 *패널이 표를 따르는가* 를 보고 SCENE 은 *표가 화소와 맞는가*
# 를 보는데, **표가 에셋 도구의 출력과 같은가**를 보는 축이 어디에도 없었다. 오프셋은
# 화소로 되짚을 수 있어 SCENE 이 잡지만(Q1) 좌표는 되짚을 소재가 `res://` 밖에 있다.
#
# 소재 = `tools/assets/cut_layout.json`(생성기의 산출). FXPL 이 `bg_spec.json` 을 읽는 것과
# 같은 자리이며, 같은 이유로 스위트가 아니라 검증기다.
#
# **성격 = 경고형(신설).** 차단/경고는 총괄 판정을 경유한다(불변규칙 7) — FONT·PAL·ANCH·
# FXPL 이 밟은 절차 그대로 상신한다. **경고형은 스스로 죽어도 빌드를 멈추지 못하므로**
# 실재는 UISCR ⑬축이 받친다.
const CUTM_SPEC := "tools/assets/cut_layout.json"
const CUTM_TABLE := "scene_cut_machines.csv"
const CUTM_BASELINES := "machine_baselines.csv"


func _run_cut_layout_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var parsed: Variant = JSON.parse_string(_read_text(CUTM_SPEC))
	if typeof(parsed) != TYPE_DICTIONARY:
		_warn("CUTM", "%s 를 읽지 못했다 — 전사 대조 불가" % CUTM_SPEC)
		_report("CUTM", "cut machine layout transcription", checked, before_fail, before_warn)
		return
	# 도구 산출 → {cut_id: {slot_name: {order, sprite, cx, road_y}}}
	var spec_slots: Dictionary = {}
	var cuts: Dictionary = Dictionary(parsed).get("cuts", {})
	for cut_id in cuts:
		var order := 0
		for slot in Array(Dictionary(cuts[cut_id]).get("slots", [])):
			order += 1
			var entry: Dictionary = slot
			spec_slots["%s/%s" % [cut_id, entry.get("name", "")]] = {
				"order": order,
				"sprite": String(entry.get("sprite", "")).get_file().trim_suffix(".png"),
				"cx": int(entry.get("cx", -1)),
				"road_y": int(entry.get("road_y", -1)),
			}
	checked += 1
	if spec_slots.is_empty():
		_warn("CUTM", "도구 산출에 슬롯이 없다 — 대조가 공허해진다")
	var seen: Dictionary = {}
	for row in _tables.get(CUTM_TABLE, []):
		var key := "%s/%s" % [String(row.get("cut_id", "")), String(row.get("slot_name", ""))]
		seen[key] = true
		checked += 1
		if not spec_slots.has(key):
			_warn("CUTM", "%s: 도구 산출에 없는 자리다 — 손 전사 의심" % key)
			continue
		var want: Dictionary = spec_slots[key]
		for column in [["slot_order", "order"], ["anchor_x", "cx"], ["anchor_road_y", "road_y"]]:
			var got := String(row.get(String(column[0]), "")).strip_edges().to_int()
			if got != int(want[String(column[1])]):
				_warn("CUTM", "%s.%s: 표 %d ≠ 도구 %d"
					% [key, String(column[0]), got, int(want[String(column[1])])])
		if String(row.get("sprite", "")).strip_edges() != String(want["sprite"]):
			_warn("CUTM", "%s.sprite: 표 '%s' ≠ 도구 '%s'"
				% [key, row.get("sprite", ""), want["sprite"]])
	# 역방향 — 도구가 낸 자리가 표에 전부 있는가 (빠진 슬롯은 컷이 조용히 좁아진다)
	for key in spec_slots:
		checked += 1
		if not seen.has(String(key)):
			_warn("CUTM", "%s: 도구가 낸 자리가 표에 없다" % String(key))
	# 섀시 대장 — **오버레이 혼입 0** (총괄 재확인 ① — 오버레이에 오프셋을 적용하면
	# 리어윙이 25px 밀린다). 도구는 오버레이를 "적용 금지" 참고 행으로만 뱉는다.
	for row in _tables.get(CUTM_BASELINES, []):
		checked += 1
		if String(row.get("sprite", "")).contains("_overlay_"):
			_warn("CUTM", "%s: 오버레이가 섀시 대장에 있다 — 오프셋 오적용 경로"
				% String(row.get("id", "")))
	_report("CUTM", "cut machine layout transcription", checked, before_fail, before_warn)


# ── FXPL 연출 요소 배치 제약 (신설 29차 — **경고형** · 제원표 §3.1 · `fx_spec.json` `_합성제약`) ──
#
# **왜 검증기인가.** 판정 소재가 `tools/assets/bg_spec.json` 의 무대별 `split_y` 인데 그
# 파일은 `res://` 밖이라 스위트가 읽지 못한다. 축을 갈랐다 — 데이터 안에서 끝나는 제약 ①
# (색 치환)은 SCENE 스위트가, **무대 지형과 대조해야 하는 제약 ②는 여기가** 진다.
#
# **성격 = 차단형** (경고형 신설 29차 → 전환 총괄 판정 ㊱ · IMPL-440). 근거는 FONT·PAL·ANCH
# 와 같다 — **앵커 y 와 무대 `split_y` 최댓값의 비교**라 문법 수준 기계 판정이고 미적 판단이
# 없어 V7 의 사유가 적용되지 않는다. 실측 = 오검출 0(현행 앵커 2건 전건 통과) · 검출 성립
# (y 88→40 주입) · **그리고 경고형에서는 그 검출이 `exit=0` 이었다**(반증 N15 미검출) —
# 전환 요청의 근거가 그 미검출 자체였다.
#
# **판정 불가도 실패다.** 지형 소재를 읽지 못하면 검사는 *위반 없음*이 아니라 *판정 없음*이며,
# 종료코드는 둘을 구분하지 못한다(AUD 완주 관문과 같은 축).
#
# 제약 ② = *"`fx_flash_burst` 는 지평선 아래(노면·바닥 대역)에 둔다 — 하늘에 두면 태양이
# 된다"* (IMPL-396 → **IMPL-420 보강: 근본은 명도가 아니라 대역이다**). 컷은 무대를 가리지
# 않고 서므로 **가장 늦게 시작하는 지평선**(= `split_y` 최대)을 넘겨야 전 무대에서 성립한다.
const FXPL_BG_SPEC := "tools/assets/bg_spec.json"
const FXPL_ELEMENTS := "fx_elements.csv"
const FXPL_LAYERS := "scene_cut_layers.csv"


func _run_fx_placement_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var bands: Array = _fxpl_split_values()
	if bands.is_empty():
		_fail("FXPL", "%s 에서 split_y 를 읽지 못했다 — 판정 없음은 위반 없음이 아니다" % FXPL_BG_SPEC)
		_report("FXPL", "fx placement constraints", checked, before_fail, before_warn)
		return
	var horizon := 0
	for value in bands:
		horizon = maxi(horizon, int(value))
	# **비공허성** — 무대 수만큼 값이 있어야 "가장 늦은 지평선"이 실제 최댓값이다.
	checked += 1
	if bands.size() < 5:
		_fail("FXPL", "지형 표본 %d < 무대 5 — 대역 상한이 낮게 잡혀 검사가 헐거워진다" % bands.size())
	var ground: Dictionary = {}
	for row in _tables.get(FXPL_ELEMENTS, []):
		if String(row.get("band_ground", "0")).strip_edges() == "1":
			ground[String(row.get("id", ""))] = true
	for row in _tables.get(FXPL_LAYERS, []):
		var element_id := String(row.get("element_id", "")).strip_edges()
		if not ground.has(element_id):
			continue
		checked += 1
		var anchor_y := String(row.get("anchor_y", "0")).strip_edges().to_int()
		if anchor_y < horizon:
			_fail("FXPL", "%s: %s 앵커 y=%d 가 지평선 %d 위다 — 하늘의 방사 광원은 천체로 읽힌다"
				% [String(row.get("id", "")), element_id, anchor_y, horizon])
	_report("FXPL", "fx placement constraints", checked, before_fail, before_warn)


# `bg_spec.json` 의 무대별 `split_y`. **파서를 얕게 둔다** — 이 검사가 필요로 하는 것은
# 값 목록뿐이고, 구조를 따라가면 에셋 트랙의 파일 형태 변경이 곧 검사 파손이 된다.
func _fxpl_split_values() -> Array:
	var text := _read_text(FXPL_BG_SPEC)
	if text == "":
		return []
	var parsed: Variant = JSON.parse_string(text)
	var values: Array = []
	_fxpl_collect_splits(parsed, values)
	return values


func _fxpl_collect_splits(value: Variant, sink: Array) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary):
			if String(key) == "split_y":
				sink.append(int((value as Dictionary)[key]))
			else:
				_fxpl_collect_splits((value as Dictionary)[key], sink)
	elif typeof(value) == TYPE_ARRAY:
		for item in (value as Array):
			_fxpl_collect_splits(item, sink)


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


# ── PAL 색 조달 대장 검사 (총괄 인계 IMPL-176 ⑤ 신설 → **차단형** IMPL-219) ──
#
# **무엇을 보는가.** 화면 코드·씬의 색 리터럴이 조달 대장 안의 색인가.
# 대장 = 마스터 60(`master_60.gpl` — D10 v1.2) + 정본 §6 색각 대체(`colorblind_alt.gpl`)
#      + 기능색 부속(= `ui_palette.gd` 전사분 — IMPL-144·167 로 정본 대조가 선 유일 기계 출처)
#      + 명시 허용 목록(`palette_allow` — 항목마다 `reason` 필수)
#
# **성격 = 차단형** (조건부 기승인 IMPL-209 → 조건 성립 후 발동 IMPL-219). 신설 시점에는
# 기존 위반 174건이 실재해 차단형으로 켜면 정리 전에 게이트가 멈추므로 경고형으로 두고
# 판정을 올렸고, 승인 조건이 **"위반 0 실측"** 이었다. 주력 치환(IMPL-206·217)으로 0 에
# 도달했고 총괄이 독립 재실측해 발동했다 — FONT 전례(IMPL-147 → 148)와 같은 절차다.
# **V7 무접촉** (작법 판단은 D04 소관 — 불변규칙 7).
#
# **PAL 의 `_warn` 은 남기지 않았다.** 대장 밖 색뿐 아니라 *검사 자신이 서지 못한 상태*
# (조달 대장 적재 실패·소스가 한 색도 기여 못 함·허용 항목에 근거 부재)도 차단이다.
# 그쪽을 경고로 두면 **조달 경로를 망가뜨리는 것이 검사를 끄는 우회로**가 된다 —
# 실제로 `master_56` → `master_60` 개명이 그 형태로 대장 절반을 죽인 채 통과했다(IMPL-198).
#
# **8bit 환산 경계.** 씬은 float 표기(`Color(0.9, 0.92, 0.95, 1)`)이고 팔레트는 8bit 정수다.
# `0.9 × 255 = 229.5` 처럼 반올림이 갈리는 값이 있어 **채널당 ±1 을 허용**한다. 마스터 팔레트의
# 인접 색은 그보다 훨씬 멀어 이 허용이 다른 색을 삼키지 않는다.
const PAL_CHANNEL_TOLERANCE := 1

var _scene_files: Array = []      # {path, source}


func _run_palette_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var allowed := _palette_allowed_set()
	if allowed.is_empty():
		_fail("PAL", "조달 대장을 적재하지 못했다 — 팔레트 실물·기능색 출처 확인 필요")
		_report("PAL", "color literal ledger", checked, before_fail, before_warn)
		return
	var exempt: Array = _config.get("palette_exempt", [])
	var sources: Array = []
	for entry in _code_files:
		sources.append(entry)
	for entry in _scene_files:
		sources.append(entry)
	for entry in sources:
		var path := String(entry["path"])
		if not _palette_in_scan_scope(path) or exempt.has(path):
			continue
		var lines: Array = String(entry["source"]).split("\n")
		for line_index in range(lines.size()):
			var code_line := _strip_comment(String(lines[line_index]))
			var is_modulate := _palette_modulate_context(code_line)
			for literal in _palette_literals(code_line):
				checked += 1
				if is_modulate or _palette_is_layer_not_paint(literal):
					continue
				if _palette_is_allowed(literal, allowed):
					continue
				_fail("PAL", "%s:%d: 대장 밖 색 %s" % [path, line_index + 1, literal])
	_report("PAL", "color literal ledger", checked, before_fail, before_warn)


# ── 문맥 제외 2축 (총괄 판정 IMPL-184 ② — 에셋 §4-③ C계 집행) ──
#
# **조달 대장은 *도색* 전속이다.** 배율·감광은 색이 아니라 층이므로 대장의 대상이 아니다.
# 제외를 허용 목록으로 처리하지 않는 이유: 허용 목록은 "대장 밖이지만 이 건은 봐준다"는
# **판단 기록**이고, 아래 둘은 "애초에 검사 대상이 아니다"라는 **검사 정의**다. 섞으면
# 목록이 판단인지 정의인지 알 수 없게 된다.

# ① 프로퍼티 문맥 — `modulate` / `self_modulate` 는 곱해지는 게인이지 칠하는 색이 아니다.
#    씬의 `modulate = Color(...)`·코드의 `.modulate =`·트윈의 `"modulate"` 인자를 모두 덮는다.
#    판정 단위가 줄인 것은 의도다 — 한 줄이 게인과 도색을 함께 쓰는 형태는 실재하지 않고
#    (실측), 표현식 파싱까지 가면 검사가 스스로 오검출원이 된다.
func _palette_modulate_context(code_line: String) -> bool:
	return code_line.contains("modulate")


# ② 순 무채 + 알파 — 스크림(감광)·완전 투명. **무채 조건을 좁게 건다**:
#    R=G=B 가 정확히 같고 알파가 1 미만일 때만이다. `Color(0.04,0.05,0.06,0.72)` 같은
#    **유채+알파는 제외되지 않는다** — 감광 층으로 위장한 도색이 그 틈으로 샌다.
func _palette_is_layer_not_paint(literal: String) -> bool:
	var alpha := _palette_alpha_of(literal)
	if alpha < 0.0 or alpha >= 1.0:
		return false
	var channels := _palette_channels_of(literal)
	if channels.size() < 3:
		return false
	return int(channels[0]) == int(channels[1]) and int(channels[1]) == int(channels[2])


# 알파 인자. 없거나 판정 불가면 -1 (= 제외 대상 아님).
func _palette_alpha_of(literal: String) -> float:
	var body := literal
	var is_color8 := body.begins_with("Color8(")
	body = body.trim_prefix("Color8(").trim_prefix("Color(").trim_suffix(")").strip_edges()
	if body.begins_with("\"") or body.begins_with("#"):
		return -1.0
	var parts := body.split(",", false)
	if parts.size() < 4:
		return -1.0
	var text := String(parts[3]).strip_edges()
	if not (text.is_valid_float() or text.is_valid_int()):
		return -1.0
	return float(text) / 255.0 if is_color8 else float(text)


func _palette_in_scan_scope(path: String) -> bool:
	for prefix in _config.get("palette_scan_dirs", []):
		if path.begins_with(String(prefix)):
			return true
	return false


# 대장 = 팔레트 실물 + 기능색 전사 + 명시 허용. 값은 8bit 3채널 배열로 정규화해 둔다.
# **소스별 적재를 개별로 단언한다** (에셋 발견 IMPL-198 §5 · 총괄 판정 IMPL-200 ①).
# 이전 구조는 전체 대장이 비었을 때만 경고했다 — 소스 하나가 죽어도(경로 오타·에셋 개명)
# 나머지가 채워 주면 **무신호로 지나간다.** 실제로 `master_56.gpl` → `master_60.gpl` 개명이
# 그 경로로 조용히 통과했고, 대장 절반이 빈 채 174건이 "정상"으로 보였다.
# 그래서 **항목마다 기여 ≥ 1** 을 건다 — 죽은 경로는 그 자체가 신호가 된다.
func _palette_allowed_set() -> Array:
	var allowed: Array = []
	for palette_path in _config.get("palette_sources", []):
		var contributed := 0
		for line in _read_text(String(palette_path)).split("\n"):
			var channels := _palette_gpl_channels(String(line))
			if not channels.is_empty():
				allowed.append(channels)
				contributed += 1
		if contributed == 0:
			_fail("PAL", "조달 소스가 아무 색도 기여하지 못했다 (경로·형식 확인): %s"
				% String(palette_path))
	# 기능색 — `ui_palette.gd` 의 `Color("#RRGGBB")` 상수 전량
	var functional_path := String(_config.get("palette_functional_source", ""))
	var functional := _read_text(functional_path)
	var functional_count := 0
	for line in functional.split("\n"):
		for literal in _palette_literals(_strip_comment(String(line))):
			var channels := _palette_channels_of(literal)
			if not channels.is_empty():
				allowed.append(channels)
				functional_count += 1
	if functional_count == 0:
		_fail("PAL", "기능색 출처가 아무 색도 기여하지 못했다 (경로·형식 확인): %s"
			% functional_path)
	for entry in _config.get("palette_allow", []):
		var spec: Dictionary = entry
		if String(spec.get("reason", "")).strip_edges() == "":
			_fail("PAL", "허용 목록 항목에 근거(reason)가 없다: %s" % str(spec.get("color", "?")))
			continue
		var channels := _palette_channels_of(String(spec.get("color", "")))
		if not channels.is_empty():
			allowed.append(channels)
	return allowed


# GIMP 팔레트 행 = `R G B\t이름`
func _palette_gpl_channels(line: String) -> Array:
	if not line.contains("\t"):
		return []
	var parts := line.split("\t", false, 1)
	if parts.is_empty():
		return []
	var numbers := String(parts[0]).split(" ", false)
	if numbers.size() < 3:
		return []
	for number in numbers:
		if not String(number).is_valid_int():
			return []
	return [int(numbers[0]), int(numbers[1]), int(numbers[2])]


# 한 줄에서 색 리터럴을 뽑는다: `Color("#RRGGBB")` / `Color(r, g, b[, a])` / `Color8(r, g, b[, a])`.
# 이름 상수 참조(`Color.RED`)·변수는 리터럴이 아니므로 대상이 아니다.
func _palette_literals(line: String) -> Array:
	var found: Array = []
	var search_from := 0
	while true:
		var open_at := line.find("Color(", search_from)
		var is_color8 := false
		var alt_at := line.find("Color8(", search_from)
		if alt_at >= 0 and (open_at < 0 or alt_at < open_at):
			open_at = alt_at
			is_color8 = true
		if open_at < 0:
			break
		var args_at := open_at + (7 if is_color8 else 6)
		var close_at := line.find(")", args_at)
		if close_at < 0:
			break
		var args := line.substr(args_at, close_at - args_at).strip_edges()
		search_from = close_at + 1
		if args.is_empty():
			continue
		found.append(("Color8(%s)" % args) if is_color8 else ("Color(%s)" % args))
	return found


# 리터럴 → 8bit 3채널. 알파는 조달 판정에 관여하지 않는다(같은 색의 투명도 차이일 뿐).
# 판정 불가 형태(변수·수식)는 빈 배열 = 검사 대상 아님.
func _palette_channels_of(literal: String) -> Array:
	var body := literal
	var is_color8 := body.begins_with("Color8(")
	body = body.trim_prefix("Color8(").trim_prefix("Color(").trim_suffix(")").strip_edges()
	if body.begins_with("\"") or body.begins_with("#"):
		var hex := body.replace("\"", "").replace("#", "").strip_edges()
		if hex.length() < 6:
			return []
		var channels: Array = []
		for index in range(3):
			channels.append(hex.substr(index * 2, 2).hex_to_int())
		return channels
	var parts := body.split(",", false)
	if parts.size() < 3:
		return []
	var values: Array = []
	for index in range(3):
		var text := String(parts[index]).strip_edges()
		if not (text.is_valid_float() or text.is_valid_int()):
			return []
		values.append(int(round(float(text))) if is_color8 else int(round(float(text) * 255.0)))
	return values


func _palette_is_allowed(literal: String, allowed: Array) -> bool:
	var channels := _palette_channels_of(literal)
	if channels.is_empty():
		return true   # 판정 불가 형태 — 없는 근거로 위반을 만들지 않는다
	for candidate in allowed:
		var match_all := true
		for index in range(3):
			if absi(int(channels[index]) - int(candidate[index])) > PAL_CHANNEL_TOLERANCE:
				match_all = false
				break
		if match_all:
			return true
	return false


# ── ANCH 앵커 배치 정적 검사 (IMPL-233 ② 경고형 신설 → **차단형** IMPL-237) ──
#
# **왜 기계인가.** `set_anchors_preset()` 은 앵커만 세우고 **배치를 완성하지 않는다.**
# 그래서 프리셋 이름이 뜻하는 자리와 실제로 놓이는 자리가 갈리는데, 화면은 정상적으로
# 뜨므로 눈으로는 "왜 저기 있지" 정도로만 보인다. 두 레인이 각각 한 번씩 밟았다 —
# 저장 표시(IMPL-228 · 우상단 → 좌상단) · 툴팁/모달(IMPL-231 · 하단중앙·중앙 → 좌상단·우하단).
#
# 실패 형태 2종(전수 실측 IMPL-231):
#   ⓐ 트리 안·크기 미정 호출 → 오프셋을 rect(0,0,0,0) 보존으로 **역산** → 좌상단 고정
#   ⓑ 트리 밖 호출 → 오프셋 0 → 배치가 **성장 방향**에 맡겨진다(기본 END = 앵커에서 우하향)
#
# **규칙 = 앵커를 세운 컨트롤에는 명시적 `grow_*` 또는 명시적 오프셋이 함께 있어야 한다.**
# 두 경로를 같은 요건으로 본다 — ①비-FULL_RECT 프리셋 호출 ②앵커 직접 대입(B1 확대 —
# IMPL-237). 앵커 0·FULL_RECT 는 **오프셋 0 이 곧 정답인 자리**라 면제이며, 추정이 아니라
# 4지점 실측분(IMPL-231)이 근거다.
#
# **성격 = 차단형** (경고형 신설 IMPL-233 ② → 오검출 0 실측 확보 후 전환 IMPL-237).
# 근거는 FONT 와 같다 — **문법 수준 기계 판정**이라 V7(작법 판단 = D04 소관)의 사유가
# 적용되지 않고, 오검출 0(표본 23종)·눈 검증 곤란(화면은 정상적으로 뜬다)이 실측분이다.
# FONT(IMPL-147→148)·PAL(209→219)과 같은 절차를 밟았다. **V7 무접촉.**
#
# **층 분담.** 이 검사는 *새 호출 지점의 조기 경보*이고, 실배치 확증은 UISCR ⑫축(부모 폭
# 기준 실 rect)이 한다. 정적 검사는 "짝이 있는가"만 보지 그 값이 옳은지는 모른다.
const ANCH_CALL := ".set_anchors_preset("
# 오프셋 0 이 곧 정답인 프리셋 — 면제. (앵커가 전부 0/1 이고 그 배치가 오프셋 0 과 일치)
const ANCH_EXEMPT_PRESETS := ["PRESET_FULL_RECT"]
# 짝의 증거로 인정하는 속성. `position` 은 인정하지 않는다 — 앵커가 걸린 컨트롤에서
# `position` 대입은 오프셋으로 환산돼 **한 축만** 고정하므로 짝의 증거가 되지 못한다.
const ANCH_PAIR_PROPERTIES := [
	"grow_horizontal", "grow_vertical",
	"offset_left", "offset_right", "offset_top", "offset_bottom",
]
# 앵커 직접 대입 형태 (B1 확대 — 총괄 판정 IMPL-237). 프리셋을 안 쓰고 앵커를 손으로 적는
# 것이 **교정의 표준형**이 됐다(저장 표시 IMPL-228 · 툴팁·모달 IMPL-231). 그 형태를 규칙 밖에
# 두면 사각이 곧 주 경로가 된다 — 프리셋 경로와 같은 짝 요건을 건다.
const ANCH_ANCHOR_PROPERTIES := ["anchor_left", "anchor_right", "anchor_top", "anchor_bottom"]


func _run_anchor_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	for entry in _code_files:
		var path := String(entry["path"])
		if not path.begins_with("godot/ui"):
			continue
		var lines: Array = String(entry["source"]).split("\n")
		var paired := _anchor_paired_names(lines)
		for line_index in range(lines.size()):
			var code_line := _strip_comment(String(lines[line_index]))
			var call := _anchor_preset_call(code_line)
			if call.is_empty():
				continue
			checked += 1
			var preset := String(call["preset"])
			if ANCH_EXEMPT_PRESETS.has(preset):
				continue
			var target := String(call["target"])
			if paired.has(target):
				continue
			_fail("ANCH", "%s:%d: %s 에 성장 방향·오프셋 지정이 없다 — 프리셋만으로는 배치가 서지 않는다 (대상 '%s')"
				% [path, line_index + 1, preset, target])
		# ── B1 — 앵커 직접 대입 (총괄 판정 IMPL-237 확대분) ──
		# **대상마다 한 번만 짖는다** — 앵커는 보통 2~4줄이 붙어 나오므로 줄마다 경고하면
		# 결함 하나가 네 건으로 불어나 계수가 사실을 왜곡한다.
		var reported: Dictionary = {}
		for line_index in range(lines.size()):
			var code_line := _strip_comment(String(lines[line_index]))
			var anchored := _anchor_direct_assignment(code_line)
			if anchored.is_empty():
				continue
			checked += 1
			var target := String(anchored["target"])
			if paired.has(target) or reported.has(target):
				continue
			reported[target] = true
			_fail("ANCH", "%s:%d: 앵커 직접 대입(%s)에 성장 방향·오프셋 지정이 없다 — 앵커만으로는 배치가 서지 않는다 (대상 '%s')"
				% [path, line_index + 1, String(anchored["property"]), target])
	_report("ANCH", "anchor placement", checked, before_fail, before_warn)


# `x.anchor_left = 0.5` / 자기 자신의 `anchor_top = 1.0` → {target, property}
#
# **0 대입은 보지 않는다.** 앵커 0 은 부모 좌상단 기준이라 오프셋 0 과 배치가 일치한다 —
# FULL_RECT 를 면제한 것과 같은 사유다(오프셋 0 이 곧 정답인 자리).
# **리터럴이 아닌 우변은 짝을 요구한다** — 값을 모르면 0 이라고 볼 근거가 없다.
func _anchor_direct_assignment(code_line: String) -> Dictionary:
	var trimmed := code_line.strip_edges()
	var assign_at := trimmed.find("=")
	if assign_at < 0 or trimmed.substr(assign_at, 2) == "==":
		return {}
	var lhs := trimmed.substr(0, assign_at).strip_edges()
	# 복합 대입(`+=` 등)도 앵커를 손으로 옮기는 선언이다 — 연산자만 떼고 같이 본다.
	# 다만 그 결과값은 알 수 없으므로 **0 면제를 적용하지 않는다**(아래 `compound`).
	var compound := false
	while lhs.ends_with("+") or lhs.ends_with("-") or lhs.ends_with("*") or lhs.ends_with("/"):
		lhs = lhs.substr(0, lhs.length() - 1).strip_edges()
		compound = true
	var property_name := ""
	var target := ""
	for candidate in ANCH_ANCHOR_PROPERTIES:
		if lhs == String(candidate):
			property_name = String(candidate)
			target = "self"
			break
		if lhs.ends_with("." + String(candidate)):
			property_name = String(candidate)
			target = lhs.substr(0, lhs.length() - String(candidate).length() - 1)
			break
	if property_name == "" or target == "":
		return {}
	var rhs := trimmed.substr(assign_at + 1).strip_edges()
	if not compound and (rhs.is_valid_float() or rhs.is_valid_int()) and rhs.to_float() == 0.0:
		return {}
	return {"target": target, "property": property_name}


# `x.set_anchors_preset(Control.PRESET_CENTER)` → {target: "x", preset: "PRESET_CENTER"}
# 수신자 없는 호출(`set_anchors_preset(...)`)은 자기 자신이므로 target = "self".
func _anchor_preset_call(code_line: String) -> Dictionary:
	var trimmed := code_line.strip_edges()
	var target := "self"
	var call_at := trimmed.find(ANCH_CALL)
	if call_at >= 0:
		var head := trimmed.substr(0, call_at)
		var start := head.length() - 1
		while start >= 0 and (head[start] == "_" or head[start].is_valid_identifier()):
			start -= 1
		target = head.substr(start + 1)
		if target == "":
			return {}
		call_at += ANCH_CALL.length()
	elif trimmed.begins_with("set_anchors_preset("):
		call_at = "set_anchors_preset(".length()
	else:
		return {}
	var args := trimmed.substr(call_at)
	var close_at := args.find(")")
	if close_at >= 0:
		args = args.substr(0, close_at)
	# `keep_offsets` 를 명시적으로 넘긴 호출은 배치를 스스로 책임진 것으로 본다.
	var comma_at := args.find(",")
	if comma_at >= 0:
		return {}
	var preset := args.strip_edges()
	var dot_at := preset.rfind(".")
	if dot_at >= 0:
		preset = preset.substr(dot_at + 1)
	return {"target": target, "preset": preset.strip_edges()}


# 파일 안에서 성장 방향·오프셋을 명시로 받은 대상 이름 집합.
# **함수 단위가 아니라 파일 단위로 본다** — 생성과 배치가 헬퍼로 갈리는 형태가 흔하고,
# 함수 경계로 좁히면 그 형태가 전부 오검출된다(FONT 전례의 같은 판단).
# 되돌림: 같은 이름의 다른 지역 변수가 짝을 갖고 있으면 그것이 이쪽을 가려 준다 —
# **경고형에서는 미검출이 오검출보다 싸다**는 쪽으로 기울인 결과이며, 실배치 확증은
# UISCR ⑫축이 별도로 진다.
func _anchor_paired_names(lines: Array) -> Dictionary:
	var names: Dictionary = {}
	for line in lines:
		var code_line := _strip_comment(String(line)).strip_edges()
		var assign_at := code_line.find("=")
		if assign_at < 0:
			continue
		var lhs := code_line.substr(0, assign_at).strip_edges()
		for property_name in ANCH_PAIR_PROPERTIES:
			if lhs == String(property_name):
				names["self"] = true
			elif lhs.ends_with("." + String(property_name)):
				names[lhs.substr(0, lhs.length() - String(property_name).length() - 1)] = true
	return names


# ── STRF 스트링 표 필드 수 검사 (총괄 판정 IMPL-249 ③ — **차단형 즉시 신설**) ──
#
# **왜 기계인가.** `strings.csv` 는 값에 콤마가 들어가는 순간 필드가 하나 늘어난다.
# 그러면 값이 **조용히 잘리고** 화면에는 앞토막만 뜬다 — 문면이 그럴듯하게 남아 있어서
# 눈으로는 "문장이 좀 짧네" 정도로 보인다. T7 납품 회차에 실제로 1건이 그 형태였다
# (`vane.brief.resonance03` — 인용부의 콤마).
#
# **인용을 존중한다 — 산술 비교만으로는 오검출이 난다(실측).** 판정 문면은 "필드 수 = 헤더 수
# 산술 비교"였으나, 그대로 구현하니 **정상 데이터 2건이 걸렸다**: `resonance03` 의 RFC4180
# 인용 복원분과 `ui.save.cardFormat` 의 **인용 안 줄바꿈**(레코드 1개가 물리 2줄)이다.
# 런타임 되읽기로 둘 다 값이 온전함을 확인했다(`StringTable` = Godot `get_csv_line` 경유 —
# 인용 인식). 그래서 이 검사도 **같은 규칙으로 레코드를 자른다** — 검사가 파서보다 엄하면
# 그 차이가 곧 오검출이고, 느슨하면 잘림을 놓친다. 파서와 같은 문법을 보는 것이 요건이다.
const STRF_TARGET := "strings_csv"


func _run_string_field_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0
	var path := String(_config[STRF_TARGET])
	var text := _read_text(path)
	if text == "":
		_fail("STRF", "스트링 표를 읽지 못했다: %s" % path)
		_report("STRF", "string table fields", checked, before_fail, before_warn)
		return
	var records := _strf_records(text)
	var expected := -1
	for record in records:
		var row: Dictionary = record
		var fields := int(row["fields"])
		if expected < 0:
			expected = fields   # 헤더가 기준이다 — 기대 수를 코드에 적지 않는다
			continue
		checked += 1
		if fields != expected:
			_fail("STRF", "%s:%d: 필드 %d개 (헤더 %d개) — 인용하지 않은 콤마는 값을 자른다: '%s'"
				% [path, int(row["line"]), fields, expected, String(row["head"])])
	_report("STRF", "string table fields", checked, before_fail, before_warn)


# RFC4180 레코드 분해 — 인용 안의 콤마·줄바꿈은 구분자가 아니다(`""` = 리터럴 따옴표).
# 반환 = [{line: 1-기준 시작 줄, fields: 필드 수, head: 첫 필드}]
func _strf_records(text: String) -> Array:
	var records: Array = []
	var in_quotes := false
	var fields := 1
	var line := 1
	var start_line := 1
	var head := ""
	var cell := ""
	var first_cell := true
	var index := 0
	while index < text.length():
		var ch := text[index]
		if in_quotes:
			if ch == '"':
				if index + 1 < text.length() and text[index + 1] == '"':
					index += 1          # 이스케이프된 따옴표
				else:
					in_quotes = false
			elif ch == "\n":
				line += 1               # 인용 안 줄바꿈 — 레코드는 계속된다
		elif ch == '"':
			in_quotes = true
		elif ch == ",":
			fields += 1
			if first_cell:
				head = cell
				first_cell = false
		elif ch == "\n":
			if not (fields == 1 and cell.strip_edges() == "" and first_cell):
				records.append({"line": start_line, "fields": fields,
					"head": head if not first_cell else cell})
			line += 1
			start_line = line
			fields = 1
			cell = ""
			head = ""
			first_cell = true
			index += 1
			continue
		if not in_quotes and ch != "," and ch != "\n" and first_cell:
			cell += ch
		index += 1
	if not (fields == 1 and cell.strip_edges() == "" and first_cell):
		records.append({"line": start_line, "fields": fields,
			"head": head if not first_cell else cell})
	return records


# ── AUD: 오디오 실물 검사 (신설 2026-08-19 · 발주 `에셋트랙_SFX잔여60_발주.md` §4) ──
#
# **왜 여기 있는가.** 오디오 에셋은 지금까지 기계가 한 번도 보지 않았다 — `test_audio.gd` 는
# 표(`sound_map.csv`)를 보고, 여기까지는 실물을 보는 눈이 없었다. 표가 옳고 파일이 없으면
# 게이트는 전부 통과하는데 게임은 조용하다.
#
# **축 6종 (발주 §4 안 대비 가감 — 근거 명기):**
#   ① 파일 실재 — `sound_map.csv` channel=sfx 행에서 파일명을 **도출**하고, 계수 68(D11 §2.11
#      확정 기준값)을 상수로 대조한다. 발주 ①(대장 목록)과 ⑥(표 대조)을 하나로 합쳤다 —
#      목록을 검사에 손으로 옮겨 적으면 그 사본이 표와 갈리고, 갈리면 검사가 표를 못 지킨다.
#   ② WAV 헤더 — PCM(1)·44100·16bit·모노를 **파일 바이트에서** 읽는다(발주 ②).
#   ③ `.import` 동반 + `compress/mode=0` + `edit/loop_mode` 선언(루프 6식 = 2 · 나머지 = 1).
#      **선언 축이며 증거가 아니다** — 임포터 열거는 런타임 상수와 한 칸 어긋난다(IMPL-245 함정).
#      실효 여부는 `tests/test_audio_assets.gd`(AUDIO-A · 차단형 스위트)가 런타임 되읽기로 받는다.
#      발주 ③(루프 런타임 FORWARD)을 여기 두지 않은 이유 = 이 검증기는 **프로젝트리스 실행**이
#      설계 전제라(`--path .` = 리포 루트) 임포트된 리소스를 적재할 수 없다. 축을 옮긴 것이지 버린 게 아니다.
#   ④ L군 길이 상한 0.8/1.5/2.5초 — 헤더의 프레임 수로 산출(발주 ⑤). AUDIO-A 와 **이중으로** 본다:
#      한쪽은 파일 바이트, 한쪽은 적재된 리소스 — 경로가 달라 같은 실패를 못 놓친다.
#   ⑤ **[가산] 파라미터 등재 대조** — `tools/audio/sfx_params.json` 에 항목이 없는 WAV 는
#      재생성이 불가능하다(재현 계약 위반). 손으로 넣은 파일·생성기 밖 산출물이 이 축에 걸린다.
#   ⑥ **[가산] 잉여 파일** — `audio/sfx/` 안에 표 밖 WAV 가 있으면 열거한다. ①이 부족을 보고
#      ⑥이 과잉을 본다 — 파일만 늘어나는 오염은 어느 게이트도 보지 않았다.
#
# **성격: 차단형** (경고형 신설 IMPL-260 → 전환 IMPL-262 — 총괄 판정 승인분. FONT·PAL·ANCH·STRF 전례).
# 전환 근거 = 위반 0 · 오검출 0 · 돌연변이 10종 전건 검출 실측. 판정은 전부 기계 판정이고
# 미적 판단이 없다(파일 실재·헤더 값·선언 문면·길이 산술) — V7 과 성격이 다르다.
# AUDIO-A 스위트(차단형 · 검사 수 하한 340)가 ②③④를 **런타임 경로로** 함께 본다 —
# 이제 둘 다 차단형이라 받침이 아니라 이중 경로다. ①⑤⑥은 이 검사에 전속이다.
# 채널별 대장 — `sound_map.csv` 의 channel 열이 곧 배치 경로다. 계수는 정본 확정값을 상수로 둔다.
#   sfx    = 68 (D11 §2.11 — SFX 63 + AMB 5)
#   jingle =  5 (D11 §4.1 결정 #5 — **트랙 계상 13+1 외 별도 소계**. 68 에 더하지 않는다)
#   bgm    = 미유입(파일럿 대기) — 아래 표에 없으므로 검사 대상 밖이고, 유입 회차에 행을 추가한다.
#     ⚠ 표에 없는 채널은 **조용히 통과한다**(부재가 아니라 무대상). BGM 유입 시 행 추가를 잊으면
#       파일이 들어와도 아무도 보지 않는다 — 그 자리가 이 검사의 사각이다.
#   `intake` = **유입 선언**이다. 파일이 한 번에 다 들어오지 않는 축(BGM 13트랙 = 파일럿 1 → 확대)에서
#     "행은 있고 파일은 아직 없다"와 "행도 파일도 없다"를 갈라야 한다. 목록 밖 id 는 **미유입이므로 무대상**이고,
#     반대로 **파일이 실재하는데 목록에 없으면 실패**다 — 대장이 실물을 모르는 상태가 그것이다.
#     생략하면 그 채널은 전량 유입으로 본다(sfx·jingle).
#   `params` = 재현 계약의 원장. **파이프라인이 갈렸으므로 원장도 갈린다**(SFX·징글 = jsfxr / BGM = 자작 신시사이저).
const AUD_CHANNELS := {
	"sfx": {"dir": "godot/assets/audio/sfx", "total": 68, "ext": "wav",
		"params": "tools/audio/sfx_params.json", "params_key": "sounds"},
	"jingle": {"dir": "godot/assets/audio/jingle", "total": 5, "ext": "wav",
		"params": "tools/audio/sfx_params.json", "params_key": "sounds"},
	"bgm": {"dir": "godot/assets/audio/bgm", "total": 13, "ext": "ogg",
		"params": "tools/audio/bgm_params.json", "params_key": "tracks",
		# A/B 5쌍 = **행 1개에 파일 2개**다(재생기 계약 — B 는 A 위 가산 레이어이지 별개 트랙이 아니다).
		# `sound_map` 이 트랙 단위 행이므로 파일명 도출에 이 목록이 필요하다.
		"stem_pairs": ["bgm_03", "bgm_04", "bgm_05", "bgm_06", "bgm_07"]},
	# **예비 1 = 대상 외** (D11 결정 #5 미배정 유보 · 발주 §1 "파일 생성 금지"). `sound_map` 에 행이
	#   없으므로 계수 13 에도 들어오지 않고, 만들면 ⑥ 잉여 축이 잡는다 — 금지가 검사로 받쳐진다.
}
const AUD_LOOP_IDS := ["se_r02", "se_t03", "se_u15", "amb_01", "amb_04", "amb_05"]
const AUD_LENGTH_CAP := {"se_l1": 0.8, "se_l2": 1.5, "se_l3": 2.5}
const AUD_BGM_LEN_MIN := 90.0     # D11 §4.4 확정 기준값
const AUD_BGM_LEN_MAX := 150.0


func _run_audio_asset_scan() -> void:
	var before_fail := _fail_count
	var before_warn := _warn_count
	var checked := 0

	var by_channel: Dictionary = {}
	for row in _tables.get("sound_map.csv", []):
		var channel := String(row.get("channel", ""))
		if not AUD_CHANNELS.has(channel):
			continue
		if not by_channel.has(channel):
			by_channel[channel] = []
		by_channel[channel].append(String(row.get("sfx_id", "")).to_lower().replace("-", "_"))
	for channel in AUD_CHANNELS:
		checked += 1
		var declared: int = int(AUD_CHANNELS[channel]["total"])
		var found: int = Array(by_channel.get(channel, [])).size()
		if found != declared:
			_fail("AUD", "sound_map channel=%s 행 %d != 정본 확정 %d식" % [channel, found, declared])

	# 파라미터 등재 목록 (⑤) — 채널마다 원장이 다르다. 한 파일만 뒤지면 BGM 이 전건 미등재로 잡힌다.
	_aud_frames.clear()
	var params_ids: Dictionary = {}
	for channel in AUD_CHANNELS:
		var pf := String(AUD_CHANNELS[channel].get("params", ""))
		var pk := String(AUD_CHANNELS[channel].get("params_key", "sounds"))
		if pf == "":
			continue
		var params_raw: Variant = JSON.parse_string(_read_text(pf))
		checked += 1
		if typeof(params_raw) != TYPE_DICTIONARY:
			_fail("AUD", "%s 를 읽지 못했다 — 재현 계약 축이 성립하지 않는다" % pf)
			continue
		var listed := 0
		for entry in params_raw.get(pk, []):
			if typeof(entry) == TYPE_DICTIONARY:
				params_ids[String(entry.get("id", ""))] = true
				listed += 1
		if listed == 0:
			_fail("AUD", "%s 의 '%s' 목록이 비었다" % [pf, pk])

	for channel in AUD_CHANNELS:
		var ids: Array = Array(by_channel.get(channel, []))
		var spec_ch: Dictionary = AUD_CHANNELS[channel]
		var ext: String = String(spec_ch.get("ext", "wav"))
		var intake: Array = Array(spec_ch.get("intake", []))
		var pairs_ch: Array = Array(spec_ch.get("stem_pairs", []))
		var expanded: Array = []
		for id in ids:
			if pairs_ch.has(id):
				expanded.append(id + "_a")
				expanded.append(id + "_b")
			else:
				expanded.append(id)
		checked += 1
		if not pairs_ch.is_empty() and expanded.size() != ids.size() + pairs_ch.size():
			_fail("AUD", "%s: A/B 전개 계수 오류 (행 %d · 쌍 %d → 파일 %d)"
				% [channel, ids.size(), pairs_ch.size(), expanded.size()])
		for id in expanded:
			var wav_path: String = "%s/%s.%s" % [String(spec_ch["dir"]), id, ext]
			var declared_intake: bool = intake.is_empty() or intake.has(id)
			var exists: bool = FileAccess.file_exists(wav_path)
			checked += 1
			if not declared_intake:
				# 미유입 선언분 — 파일이 없는 것이 정상이다. 있으면 대장이 실물을 모르는 상태다.
				if exists:
					_fail("AUD", "%s: 실물이 있는데 유입 선언(intake)에 없다 — 대장이 실물을 모른다" % id)
				continue
			if not exists:
				_fail("AUD", "%s: 실물 부재 (표에 행이 있고 파일이 없다 — 발화 지점이 조용해진다)" % id)
				continue
			checked += 1
			if not params_ids.has(id):
				_fail("AUD", "%s: 파라미터 원장 미등재 — 재생성 불가(재현 계약 위반)" % id)
			var header: Dictionary = _aud_ogg_header(wav_path) if ext == "ogg" else _aud_wav_header(wav_path)
			if ext == "ogg":
				_aud_frames[id] = int(header.get("data_size", 0)) / 2
			checked += 1
			if header.has("error"):
				_fail("AUD", "%s: %s" % [id, String(header["error"])])
				continue
			# 공통 축 = 샘플레이트·채널·데이터 유무. **비트 심도는 WAV 전속이다** — Vorbis 는 컨테이너에
			# 비트 심도가 없고(내부 부동소수) D12 §10.1 도 BGM 에는 품질 q 만 둔다.
			# ⚠ 없는 키를 `header["x"]` 로 읽으면 **스캔이 중도 이탈하고 게이트가 PASS 를 낸다**
			#    (2026-08-20 실측 — 그래서 전부 `get(기본값)` 이고 위에 완주 관문을 뒀다).
			checked += 3
			if int(header.get("rate", 0)) != 44100:
				_fail("AUD", "%s: sampleRate %d != 44100 — D12 §10.1" % [id, int(header.get("rate", 0))])
			if int(header.get("channels", 0)) != 1:
				_fail("AUD", "%s: numChannels %d != 1(모노)" % [id, int(header.get("channels", 0))])
			if int(header.get("data_size", 0)) <= 0:
				_fail("AUD", "%s: 오디오 데이터가 비었다" % id)
			if ext == "ogg":
				# BGM 길이 기준값 90~150초 (D11 §4.4). granulepos 산출 — 잘린 파일도 여기 걸린다.
				checked += 1
				var bgm_sec: float = float(header.get("seconds", 0.0))
				if bgm_sec < AUD_BGM_LEN_MIN or bgm_sec > AUD_BGM_LEN_MAX:
					_fail("AUD", "%s: 길이 %.1fs 가 %.0f~%.0f초 밖이다 (D11 §4.4)"
						% [id, bgm_sec, AUD_BGM_LEN_MIN, AUD_BGM_LEN_MAX])
			else:
				checked += 2
				if int(header.get("format", 0)) != 1:
					_fail("AUD", "%s: audioFormat %d != 1(PCM) — D12 §10.1" % [id, int(header.get("format", 0))])
				if int(header.get("bits", 0)) != 16:
					_fail("AUD", "%s: bitsPerSample %d != 16 — D12 §10.1" % [id, int(header.get("bits", 0))])
				if AUD_LENGTH_CAP.has(id):
					checked += 1
					var seconds: float = float(header.get("seconds", 0.0))
					var cap: float = float(AUD_LENGTH_CAP[id])
					if seconds > cap:
						_fail("AUD", "%s: 길이 %.3fs > 상한 %.1fs (D13 확정 기준값)" % [id, seconds, cap])
			# ③ `.import` 선언
			var import_path: String = wav_path + ".import"
			checked += 1
			if not FileAccess.file_exists(import_path):
				_fail("AUD", "%s: `.import` 부재 — 반대편 머신이 기본값으로 재임포트한다(IMPL-003)" % id)
				continue
			var import_text: String = _read_text(import_path)
			checked += 2
			if ext == "ogg":
				# BGM = 전 트랙 심리스 루프 필수 (D11 §4.4). OGG 임포터는 열거가 아니라 **불리언**이라
				# WAV 의 한 칸 어긋남 함정이 없다 — **없다는 것도 실측으로 확인한 결과다**(IMPL-274).
				# 그래도 선언은 증거가 아니므로 실효는 AUDIO-A 가 런타임에서 되읽는다.
				if not import_text.contains("loop=true"):
					_fail("AUD", "%s: loop 선언이 true 가 아니다 — BGM 은 전 트랙 심리스 루프 필수(D11 §4.4)" % id)
				if not import_text.contains("bpm="):
					_fail("AUD", "%s: bpm 선언 부재 — 박 정보가 없으면 그리드 정합을 되읽을 수 없다" % id)
				continue
			if not import_text.contains("compress/mode=0"):
				_fail("AUD", "%s: compress/mode 가 0(무압축)이 아니다 — 손실 코덱은 16비트 베이크를 흔든다" % id)
			var want_loop: int = 2 if id in AUD_LOOP_IDS else 1
			if not import_text.contains("edit/loop_mode=%d" % want_loop):
				_fail("AUD", "%s: edit/loop_mode 선언이 %d 이 아니다 (임포터 열거 = 1 Disabled · 2 Forward)"
					% [id, want_loop])

	# ⑥ 잉여 파일 — 채널별로 본다. ①이 부족을 보고 여기가 과잉을 본다.
	for channel in AUD_CHANNELS:
		var known: Dictionary = {}
		var pairs_x: Array = Array(AUD_CHANNELS[channel].get("stem_pairs", []))
		for id in Array(by_channel.get(channel, [])):
			# A/B 쌍은 행 1개가 파일 2개다 — 여기서도 전개해야 정상 파일이 "표 밖"으로 잡히지 않는다.
			if pairs_x.has(id):
				known[String(id) + "_a"] = true
				known[String(id) + "_b"] = true
			else:
				known[String(id)] = true
		var dir := DirAccess.open(String(AUD_CHANNELS[channel]["dir"]))
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.ends_with("." + String(AUD_CHANNELS[channel].get("ext", "wav"))):
				checked += 1
				if not known.has(entry.get_basename()):
					_fail("AUD", "%s/%s: 표 밖 파일 (sound_map 에 행이 없다 — 아무도 부르지 않는다)"
						% [channel, entry])
			entry = dir.get_next()
		dir.list_dir_end()
	# A/B 스템 쌍 — **샘플 단위 길이 일치** (발주 §4 · D11 §4.3 "동일 길이·동일 템포·박 동기").
	# 1샘플만 어긋나도 두 스템이 서로 밀려 박 동기가 깨진다. 재생기는 B 볼륨만 켜므로
	# 어긋남이 "가산 레이어"를 어긋난 캐논으로 바꾼다 — 조용히 틀리는 자리다.
	for channel in AUD_CHANNELS:
		for base in Array(AUD_CHANNELS[channel].get("stem_pairs", [])):
			var ka := String(base) + "_a"
			var kb := String(base) + "_b"
			checked += 1
			if not (_aud_frames.has(ka) and _aud_frames.has(kb)):
				_fail("AUD", "%s: A/B 쌍의 한쪽을 읽지 못했다 (%s/%s)" % [base, ka, kb])
				continue
			if int(_aud_frames[ka]) != int(_aud_frames[kb]):
				_fail("AUD", "%s: A/B 프레임 %d vs %d — 샘플 단위 불일치(박 동기 파손)"
					% [base, int(_aud_frames[ka]), int(_aud_frames[kb])])
	_aud_completed = true
	_report("AUD", "audio assets", checked, before_fail, before_warn)


# WAV 헤더를 바이트에서 읽는다 — `.import` 나 임포트 캐시를 믿지 않는다.
# (돌연변이 실측: 소스 WAV 를 치워도 `.godot/imported/` 캐시가 남아 있으면 적재는 성공한다.
#  즉 **파일 실재 축은 리소스 적재로 확인할 수 없고** 파일 시스템으로만 확인된다 — 축을 여기 둔 이유다.)
func _aud_wav_header(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "열 수 없다"}
	var bytes := file.get_buffer(4096)
	var size := file.get_length()
	file.close()
	if bytes.size() < 44:
		return {"error": "44바이트 미만 — WAV 가 아니다"}
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {"error": "RIFF 시그니처 없음"}
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {"error": "WAVE 형식 아님"}
	var offset := 12
	var result: Dictionary = {}
	while offset + 8 <= bytes.size():
		var chunk_id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := bytes.decode_u32(offset + 4)
		if chunk_id == "fmt ":
			result["format"] = bytes.decode_u16(offset + 8)
			result["channels"] = bytes.decode_u16(offset + 10)
			result["rate"] = bytes.decode_u32(offset + 12)
			result["align"] = bytes.decode_u16(offset + 20)
			result["bits"] = bytes.decode_u16(offset + 22)
		elif chunk_id == "data":
			# data 크기는 헤더 선언값을 쓰되 **파일 크기와 대조**한다 — 잘린 파일을 놓치지 않는다.
			var declared_size := int(chunk_size)
			var actual := size - (offset + 8)
			if declared_size > actual:
				return {"error": "data 선언 %dB > 실제 %dB (파일이 잘렸다)" % [declared_size, actual]}
			result["data_size"] = declared_size
			var align: int = int(result.get("align", 2))
			var rate: int = int(result.get("rate", 44100))
			result["seconds"] = float(declared_size) / float(maxi(align, 1)) / float(maxi(rate, 1))
			return result
		offset += 8 + int(chunk_size) + (int(chunk_size) & 1)
	return {"error": "data 청크 없음"}

# OGG Vorbis 헤더를 바이트에서 읽는다 — RIFF 가 아니라 Ogg 페이지 + Vorbis 식별 헤더다.
# 길이는 **마지막 페이지의 granulepos**(총 샘플 수)로 얻는다 — 컨테이너에 길이 필드가 없다.
func _aud_ogg_header(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "열 수 없다"}
	var size := file.get_length()
	var head := file.get_buffer(128)
	if head.size() < 58 or head.slice(0, 4).get_string_from_ascii() != "OggS":
		file.close()
		return {"error": "OggS 시그니처 없음"}
	var segments := head.decode_u8(26)
	var packet := 27 + segments
	# Vorbis 식별 패킷 = 0x01 + "vorbis" + version(4) + channels(1) + rate(4)
	if head.size() < packet + 16 or head.decode_u8(packet) != 1 \
			or head.slice(packet + 1, packet + 7).get_string_from_ascii() != "vorbis":
		file.close()
		return {"error": "Vorbis 식별 헤더 아님"}
	var channels := head.decode_u8(packet + 11)
	var rate := head.decode_u32(packet + 12)
	# 마지막 OggS 페이지의 granulepos — 꼬리 64KB 안에서 뒤에서부터 찾는다.
	var tail_size: int = mini(65536, int(size))
	file.seek(size - tail_size)
	var tail := file.get_buffer(tail_size)
	file.close()
	var granule: int = -1
	for i in range(tail.size() - 27, -1, -1):
		if tail.slice(i, i + 4).get_string_from_ascii() == "OggS":
			granule = tail.decode_s64(i + 6)
			break
	if granule < 0:
		return {"error": "마지막 Ogg 페이지를 찾지 못했다 — granulepos 부재"}
	return {"channels": channels, "rate": rate, "align": 2,
		"data_size": granule * 2, "seconds": float(granule) / float(maxi(int(rate), 1))}
