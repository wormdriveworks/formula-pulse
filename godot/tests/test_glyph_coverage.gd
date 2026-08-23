# GLYPH — 원도 커버리지 검사 (총괄 발주 21차 ③ · 입력 = 내러티브 4차 §6-C·D·부록 B).
# 실행: godot --headless --path godot --script tests/test_glyph_coverage.gd
#
# **왜 스위트이고 검증기가 아닌가.** 판정 대상이 "원도가 이 문자를 실제로 그릴 수 있는가"이고
# 그 답의 정본은 **엔진이 적재한 폰트**다. 검증기(`run_validators.gd`)는 프로젝트리스 실행이
# 설계 전제라 `FontFile` 을 적재할 수 없어 cmap 을 손으로 파싱해야 하는데, 자작 파서와
# 엔진이 한 칸이라도 갈리면 그 차이가 곧 오검출이거나 누락이다 — IMPL-245 가 오디오에서
# 배운 것과 같은 자리다(*"선언은 증거가 아니다 — 되읽기만이 증거"*). AUD(파일·선언 축) /
# AUDIO-A(임포트 결과 축) 를 가른 전례를 그대로 따른다.
#
# **성격 = 차단형 제안.** 미적 판단이 0이다(원도 cmap × 표 사용 문자 = 기계 판정).
# 불변규칙 7 대로 최종 성격은 총괄 판정 경유이며, 스위트는 본디 차단형이라 등재 자체가
# 그 성격을 뜻한다 — 회신에 명기하고 판정을 요청한다.
extends SceneTree

const STRINGS_PATH := "res://data/strings/strings.csv"
const KEY_COLUMN := "key"

# 렌더 경로 원도 — 전역 기본 + 씬 override. 이 둘 중 어느 쪽이 그릴지 키 단위로는
# 기계적으로 알 수 없으므로 **양쪽 다 요구**하고, 갈리는 자리는 아래 면제 대장이 받는다.
const RENDER_FONTS := {
	"Galmuri9": "res://assets/fonts/Galmuri9.ttf",
	"Galmuri14": "res://assets/fonts/Galmuri14.ttf",
}

# 렌더 경로 **밖** 원도. 커버리지를 요구하지 않는 대신 **렌더 경로에 나타나지 않음**을 요구한다.
# `cjk_expected` 는 두 방향 대장이다 — 실측이 이 값과 달라지면(원도가 교체·증보되면)
# 격리 사유 자체가 낡은 것이므로 검사가 실패해 재검토를 강제한다.
const LATENT_FONTS := {
	"Galmuri11": {"path": "res://assets/fonts/Galmuri11.ttf", "cjk_expected": 6477,
		"reason": "측정 도구 전속 — 렌더 경로 참조 0"},
	"Galmuri11-Bold": {"path": "res://assets/fonts/Galmuri11-Bold.ttf", "cjk_expected": 0,
		"reason": "CJK·가나 0자 — 일문에 굵은 글씨를 도입하면 그 순간 전부 두부가 된다"},
	"GalmuriMono11": {"path": "res://assets/fonts/GalmuriMono11.ttf", "cjk_expected": 6477,
		"reason": "측정 도구 전속 — 렌더 경로 참조 0"},
}

# 잠재 원도를 참조해도 되는 곳 — 측정 하네스 + **이 검사기 자신**.
# 자기 자신을 넣는 것은 편의가 아니라 요건이다: 격리 대장이 경로를 적어야 하므로
# 검사기는 필연적으로 그 경로를 담고 있고, 자기를 세지 않으면 항상 자기가 걸린다.
const LATENT_REFERENCE_ALLOW := [
	"res://tests/measure_log_width.gd",
	"res://tests/test_glyph_coverage.gd",
]

# 커버리지 면제 대장 — **사유는 실독이고, 면제가 불필요해지면 검사가 실패한다.**
const COVERAGE_EXEMPT := [
	{
		"char": "≡", "font": "Galmuri14", "keys": ["ui.race.menu"],
		"reason": "소비 노드 %E14Menu (ui/race/race_screen.tscn) 에 theme_override_fonts/font"
			+ " 가 없다 — 전역 기본 Galmuri9 렌더이고 그 원도는 탑재한다 (실독 확인).",
	},
]

# 상용한자 대조 입력 — 표가 유입되면 **자동으로 실대조로 승격**한다.
# 오프라인에 D15 §4.3 상용한자 2,136자 표가 없어 이 회차는 대조하지 못했다.
# 추정으로 통과 선언하지 않는다 — 대신 계수를 못박아 두어 일문 열의 한자 집합이
# 바뀌면 검사가 실패하고, 표가 들어오면 그때부터 진짜 판정이 돈다.
const JOUYOU_PATH := "res://data/reference/jouyou_kanji.txt"
const JA_KANJI_EXPECTED := 500          # 내러티브 4차 부록 B 계수
const JOUYOU_EXPECTED_COUNT := 2136     # D15 §4.3 확정

# 헤더 순서 = 계약이다. O11 선택 인덱스가 이 순서를 탄다 (options_store.language_code()).
const HEADER_CONTRACT := ["key", "ko", "en", "ja"]

# O11 언어 단계 라벨 — 계약으로 고정된 이름 (조립형이라 V2 가 보지 못한다).
# 미유입 2키는 **부재를 단언**한다: 유입되면 이 축이 실패하고, 그때가 조립 분기를
# 지우고 `OPTIONS["o11"]["steps"]` 에 리터럴로 붙일 시점이다 (자기 만료 강제).
const LANGUAGE_STEP_PENDING := {"English": "en", "Japanese": "ja"}

var _failures := 0
var _checked := 0
var _strings: Array = []
var _coverage: Dictionary = {}   # 원도 이름 → {codepoint: true}


func _init() -> void:
	if not _load_strings():
		_report()
		return
	_header_contract()
	_load_coverage()
	_render_coverage()
	_latent_isolation()
	_normalization()
	_jouyou_ledger()
	_language_step_contract()
	_report()


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


func _report() -> void:
	print("")
	if _checked < 2500:
		print("GLYPH_FAIL checks=%d < 하한 2500 (스위트 축소·폰트 적재 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("GLYPH_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("GLYPH_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _load_strings() -> bool:
	_strings = CsvTable.load_rows(STRINGS_PATH)
	if _strings.is_empty():
		print("  [FAIL] 스트링 표 적재 실패")
		_failures += 1
		return false
	return true


# ── ① 헤더 순서 계약 ──
func _header_contract() -> void:
	var header: Array = Dictionary(_strings[0]).keys()
	_ok("① 헤더 = 계약 순서", header == HEADER_CONTRACT, str(header))
	for column in HEADER_CONTRACT:
		_ok("① 열 실재: %s" % column, header.has(column))


func _languages() -> Array:
	var out: Array = []
	for column in HEADER_CONTRACT:
		if column != KEY_COLUMN:
			out.append(column)
	return out


func _load_coverage() -> void:
	for name in RENDER_FONTS:
		_coverage[name] = _font_coverage(String(RENDER_FONTS[name]), String(name))
	for name in LATENT_FONTS:
		_coverage[name] = _font_coverage(String(Dictionary(LATENT_FONTS[name])["path"]), String(name))


func _font_coverage(path: String, name: String) -> Dictionary:
	var set: Dictionary = {}
	var font := load(path) as FontFile
	_ok("원도 적재: %s" % name, font != null, path)
	if font == null:
		return set
	# `get_supported_chars()` 는 원도가 실제로 신고하는 집합이다 — 코드포인트 구간을
	# 순회해 `has_char` 를 두드리는 것보다 싸고, 구간을 손으로 정하지 않아 누락도 없다.
	var supported := String(font.get_supported_chars())
	for index in range(supported.length()):
		set[supported.unicode_at(index)] = true
	_ok("원도 커버리지 비공란: %s" % name, not set.is_empty(), "size=%d" % set.size())
	return set


# 표에 실제로 쓰인 문자 → 그 문자를 쓴 키 목록
func _used_chars() -> Dictionary:
	var used: Dictionary = {}
	for row in _strings:
		var key := String(Dictionary(row).get(KEY_COLUMN, ""))
		for language in _languages():
			var value := String(Dictionary(row).get(language, ""))
			for index in range(value.length()):
				var code := value.unicode_at(index)
				if code == 10 or code == 13:
					continue   # 줄바꿈은 글리프가 아니다
				if not used.has(code):
					used[code] = {}
				Dictionary(used[code])[key] = true
	return used


# ── ② 렌더 경로 커버리지 ──
func _render_coverage() -> void:
	var used := _used_chars()
	_ok("② 사용 문자 표본 확보", used.size() > 1000, "distinct=%d" % used.size())
	var exempt_hit: Dictionary = {}
	for name in RENDER_FONTS:
		var set: Dictionary = _coverage[name]
		if set.is_empty():
			continue
		var missing: Array = []
		for code in used:
			_checked += 1
			if set.has(code):
				continue
			var ledger := _exemption_for(code, String(name))
			if ledger.is_empty():
				missing.append(code)
				continue
			exempt_hit["%s:%d" % [name, code]] = true
			# 면제는 **선언된 키에서만** 유효하다 — 실독 근거가 그 키에 대해서만 서 있다.
			var declared: Array = ledger["keys"]
			for key in Dictionary(used[code]):
				if not declared.has(String(key)):
					_failures += 1
					print("  [FAIL] ② 면제 밖 사용: '%s'(U+%04X) × %s in '%s'"
						% [char(code), code, name, key])
		_ok("② 커버리지 부재 0: %s" % name, missing.is_empty(),
			_describe_missing(missing))
	# 면제가 **실제로 필요했는지** 확인한다. 필요 없어진 면제가 남으면 다음 사람이
	# "이 원도는 이 문자를 못 그린다"는 낡은 사실을 근거로 판단한다.
	for ledger in COVERAGE_EXEMPT:
		var code := String(ledger["char"]).unicode_at(0)
		var name := String(ledger["font"])
		_ok("② 면제가 여전히 필요하다: '%s' × %s" % [ledger["char"], name],
			exempt_hit.has("%s:%d" % [name, code]),
			"원도가 이제 이 문자를 그린다면 면제를 지울 시점이다")


func _exemption_for(code: int, font_name: String) -> Dictionary:
	for ledger in COVERAGE_EXEMPT:
		if String(ledger["font"]) == font_name and String(ledger["char"]).unicode_at(0) == code:
			return ledger
	return {}


func _describe_missing(missing: Array) -> String:
	if missing.is_empty():
		return ""
	var sample: Array = []
	for index in range(mini(missing.size(), 8)):
		sample.append("'%s'(U+%04X)" % [char(int(missing[index])), int(missing[index])])
	return "%d자: %s" % [missing.size(), ", ".join(sample)]


# ── ③ 잠재 원도 격리 ──
#
# Galmuri11-Bold 는 CJK·가나가 0자다. **지금 무해한 이유는 렌더 경로에 없기 때문**이며,
# 그것은 사실이 아니라 상태다 — 상태는 바뀐다. 커버리지를 요구하는 대신 격리를 요구한다.
func _latent_isolation() -> void:
	var sources := _scan_sources()
	for name in LATENT_FONTS:
		var spec: Dictionary = LATENT_FONTS[name]
		var needle := String(spec["path"]).replace("res://", "")
		var offenders: Array = []
		for path in sources:
			if LATENT_REFERENCE_ALLOW.has(String(path)):
				continue
			if String(sources[path]).contains(needle):
				offenders.append(String(path))
		_ok("③ 렌더 경로 밖: %s" % name, offenders.is_empty(), str(offenders))
		# 두 방향 대장 — 격리 사유가 커버리지 사실에 근거하므로 그 사실을 함께 못박는다.
		var actual := _cjk_count(String(name))
		_ok("③ CJK 계수 = 대장: %s" % name, actual == int(spec["cjk_expected"]),
			"actual=%d ledger=%d — 원도가 바뀌었다면 격리 사유를 재검토할 시점이다"
				% [actual, int(spec["cjk_expected"])])
	# 렌더 경로 원도는 반대로 **CJK 를 실제로 갖고 있어야** 한다
	for name in RENDER_FONTS:
		_ok("③ 렌더 원도 CJK 실재: %s" % name, _cjk_count(String(name)) > 6000,
			"cjk=%d" % _cjk_count(String(name)))


func _cjk_count(font_name: String) -> int:
	var set: Dictionary = _coverage.get(font_name, {})
	var count := 0
	for code in set:
		if int(code) >= 0x4E00 and int(code) <= 0x9FFF:
			count += 1
	return count


# 소스 스캔 — 렌더 경로에 폰트 경로가 나타나는지 본다 (씬·스크립트·프로젝트 설정)
func _scan_sources() -> Dictionary:
	var out: Dictionary = {}
	_scan_dir("res://", out)
	var settings := FileAccess.open("res://project.godot", FileAccess.READ)
	if settings != null:
		out["res://project.godot"] = settings.get_as_text()
		settings.close()
	return out


func _scan_dir(path: String, sink: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := path + entry if path.ends_with("/") else path + "/" + entry
		if dir.current_is_dir():
			if entry != "assets":   # 에셋 실물은 소스가 아니다
				_scan_dir(full, sink)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn") or entry.ends_with(".tres"):
			var file := FileAccess.open(full, FileAccess.READ)
			if file != null:
				sink[full] = file.get_as_text()
				file.close()
		entry = dir.get_next()
	dir.list_dir_end()


# ── ④ 정규화 — NFD 로 들어온 `が`·`パ` 는 화면에서 깨진다 ──
#
# 결합 탁점 U+3099·U+309A 가 Galmuri14 에 없다(내러티브 4차 §6-C ③). 즉 이 표에서
# NFC 는 관례가 아니라 **렌더 요건**이다. 결합 문자의 부재 자체를 검사로 못박는다.
func _normalization() -> void:
	var used := _used_chars()
	for code in [0x3099, 0x309A]:
		_ok("④ 결합 탁점 미사용: U+%04X" % code, not used.has(code),
			"표에 결합 문자가 있으면 NFD 유입 — Galmuri14 가 그리지 못한다")
	# 부재가 무의미하지 않다는 증거: 결합 대상인 탁점 가나가 실제로 쓰이고 있다
	var has_precomposed := false
	for code in used:
		if int(code) == 0x304C or int(code) == 0x30D1:   # が · パ
			has_precomposed = true
			break
	_ok("④ 사전 조립 탁점 가나 실재 (검사 대상 존재)", has_precomposed)
	# 그리고 Galmuri14 가 결합 탁점을 실제로 못 그린다는 사실 — 사유의 근거를 함께 못박는다
	var g14: Dictionary = _coverage.get("Galmuri14", {})
	if not g14.is_empty():
		_ok("④ Galmuri14 에 결합 탁점 부재 (④ 사유의 근거)",
			not g14.has(0x3099) and not g14.has(0x309A))


# ── ⑤ 상용한자 미대조 대장 (D15 §4.3) ──
func _jouyou_ledger() -> void:
	var kanji: Dictionary = {}
	for row in _strings:
		var value := String(Dictionary(row).get("ja", ""))
		for index in range(value.length()):
			var code := value.unicode_at(index)
			if code >= 0x4E00 and code <= 0x9FFF:
				kanji[code] = true
	_ok("⑤ 일문 한자 계수 = 부록 B 대장", kanji.size() == JA_KANJI_EXPECTED,
		"actual=%d ledger=%d — 집합이 바뀌었으면 상용한자 재대조가 필요하다"
			% [kanji.size(), JA_KANJI_EXPECTED])
	if not FileAccess.file_exists(JOUYOU_PATH):
		# 표 부재 = 미대조. **추정으로 통과 선언하지 않는다.** 표가 유입되면 아래로 승격한다.
		_ok("⑤ 상용한자 표 미유입 — 대조 보류 (추정 통과 금지)", true)
		return
	var table := FileAccess.open(JOUYOU_PATH, FileAccess.READ)
	var text := table.get_as_text()
	table.close()
	var allowed: Dictionary = {}
	for index in range(text.length()):
		var code := text.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			allowed[code] = true
	_ok("⑤ 상용한자 표 계수 = D15 §4.3", allowed.size() == JOUYOU_EXPECTED_COUNT,
		"actual=%d" % allowed.size())
	var outside: Array = []
	for code in kanji:
		_checked += 1
		if not allowed.has(code):
			outside.append(code)
	_ok("⑤ 상용한자 밖 0", outside.is_empty(), _describe_missing(outside))


# ── ⑥ O11 언어 단계 라벨 계약 ──
func _language_step_contract() -> void:
	var keys: Dictionary = {}
	for row in _strings:
		keys[String(Dictionary(row).get(KEY_COLUMN, ""))] = true
	var korean := OptionsStore.LANGUAGE_STEP_DOMAIN + OptionsStore.LANGUAGE_STEP_STEM + "Korean"
	_ok("⑥ 유입된 단계 키 실재: %s" % korean, keys.has(korean))
	# **양쪽 상태를 각각 요구한다.** 부재를 그냥 단언하면 문면이 유입되는 정당한 회차가
	# 이유 없이 붉어진다 — 검사가 남의 정당한 작업을 막는 것은 검사의 일이 아니다.
	# 대신 "유입되면 리터럴 목록에 있어야 한다"를 건다: 조립 분기는 미유입 임시 경로이므로
	# 문면이 들어온 뒤에도 조립에 남아 있으면 그것이 결함이다(V2 가 다시 보게 되는 자리다).
	var literal_steps: Array = Array(Dictionary(OptionsStore.OPTIONS["o11"]).get("steps", []))
	for stem in LANGUAGE_STEP_PENDING:
		var key := OptionsStore.LANGUAGE_STEP_DOMAIN + OptionsStore.LANGUAGE_STEP_STEM + String(stem)
		if keys.has(key):
			_ok("⑥ 유입된 단계 키는 리터럴 목록에 있다: %s" % key, literal_steps.has(key),
				"문면이 들어왔으면 조립 분기를 지우고 OPTIONS[\"o11\"][\"steps\"] 에 붙일 시점이다")
		else:
			_ok("⑥ 미유입 단계 키는 조립으로 대체: %s" % key, not literal_steps.has(key),
				"표에 없는 키를 리터럴로 적으면 V2 가 차단한다")
	# 조립 대장은 어느 상태에서도 헤더 전량을 덮어야 한다 — 한 언어가 빠지면 그 단계가 빈다
	for code in _languages():
		var stem := String(OptionsStore.LANGUAGE_STEP_NAMES.get(code, ""))
		_ok("⑥ 단계 이름 대장 등재: %s" % code, stem != "")
	_ok("⑥ 언어 코드 표기 대장 = 헤더", OptionsStore.LANGUAGE_STEP_NAMES.size() == _languages().size(),
		"%d vs %d" % [OptionsStore.LANGUAGE_STEP_NAMES.size(), _languages().size()])
	for code in _languages():
		_ok("⑥ 언어 코드 대장 등재: %s" % code, OptionsStore.LANGUAGE_STEP_NAMES.has(code))
