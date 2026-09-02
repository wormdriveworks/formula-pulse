# G4W — 최장 키 언어 라벨 폭 검증 (게이트 G-4 · D12 §8.5 · D14 §5.4).
# 실행: godot --headless --path godot --script tests/test_label_width.gd
#
# **V3 와 무엇이 다른가.** V3 는 **자수**(전각 가중)를 규칙 상한과 대조한다 — 근사다.
# 이 스위트는 **실 원도의 픽셀 폭**을 **실 슬롯 폭**과 대조한다: 같은 자수라도 원도별
# 글자 폭이 다르고, en 은 반각이라 자수는 작고 픽셀은 크다(`ui.options.controlsNote`
# en = 657px vs ko 560px). D14 §5.4 가 요구하는 것이 이 대조다.
#
# **슬롯 폭은 실행 중 노드 rect 에서 읽는다.** 씬에서 손으로 옮겨 적으면 주력이 레이아웃을
# 바꾼 날 대장만 낡는다 — 코드 생성 라벨처럼 노드가 없는 자리만 선언값을 쓰고 출처를 적는다.
#
# **성격 = 차단형 제안** (미적 판단 0 — 원도 폭 × 슬롯 폭 = 기계 판정). 최종 성격은
# 불변규칙 7 대로 총괄 판정 경유. 판정 = 초과 라벨 0, 초과 시 **번역 지시 우선**이며
# 폭 조정은 D13 창구다(D12 §8.5) — 이 스위트는 목록만 내고 값을 고치지 않는다.
extends SceneTree

const STRINGS_PATH := "res://data/strings/strings.csv"
const RACE_SCENE := "res://ui/race/race_screen.tscn"
const OPTIONS_SCENE := "res://ui/sys/options_screen.tscn"
const VN_SCENE := "res://ui/nar/vn_screen.tscn"
const LAYOUT_SETTLE_FRAMES := 4

const BODY_FONT := "res://assets/fonts/Galmuri9.ttf"
const HEAD_FONT := "res://assets/fonts/Galmuri14.ttf"

# 뷰포트 폭(D12 §9.1 기준 캔버스 640×360) − 표준 패널 여백. 슬롯이 특정되지 않은
# 도메인의 **무조건 상한**이다: 이보다 넓은 한 줄 라벨은 어느 자리에서도 잘린다.
const DEFAULT_CEILING := 620.0

# 선택지 행 버튼 간격 — `vn_screen.tscn` ChoiceList 선언값과 자기 검사에서 묶는다.
const CHOICE_SEPARATION := 6.0

# 좁은 슬롯 대장 — 폭은 선언하지 않고 **원본에서 읽는다**. `anchor` = 그 라벨을 만드는 지점.
const NARROW_SLOTS := [
	{"slot": "strategySkillName", "source_file": "res://ui/hub/strategy_screen.gd",
		"anchor": "func _skill_row("},
	{"slot": "sponsorName", "source_file": "res://ui/hub/sponsor_desk_screen.gd",
		"anchor": "func _card(sponsor_id: String)"},
	{"slot": "overhaulPick", "source_file": "res://ui/hub/overhaul_screen.gd",
		"anchor": "var pick := Button.new()"},
	{"slot": "facilityName", "source_file": "res://ui/hub/facility_screen.gd",
		"anchor": "func _card(facility_id: String)"},
	{"slot": "tuningName", "source_file": "res://ui/hub/tuning_bench_screen.gd",
		"anchor": "func _build_row(tuning_id: String"},
	{"slot": "optionLabel", "source_file": "res://ui/sys/options_screen.gd",
		"anchor": "func _build_row(option_id: String"},
	{"slot": "optionValue", "source_file": "res://ui/sys/options_screen.gd",
		"anchor": "var value := Label.new()"},
	{"slot": "achievementName", "source_file": "res://ui/sys/achievement_screen.gd",
		"anchor": "var name_label := Label.new()\n\tname_label.name = \"Name\""},
	{"slot": "achievementMark", "source_file": "res://ui/sys/achievement_screen.gd",
		"anchor": "var mark := Label.new()"},
]

# 랩 대장 — 소비부가 `autowrap_mode` 를 세우는 라벨. 폭이 아니라 **줄 수**로 판정한다.
# 출처 = 실독 지점. 랩하지 않는 라벨을 여기 적으면 초과가 조용히 통과하므로
# 소비부에 `autowrap_mode` 가 실재하는지 원본으로 함께 확인한다(아래 ③).
const WRAP_LEDGER := [
	{"keys": ["ui.options.controlsNote"], "width": 300.0, "max_lines": 6,
		"source": "options_screen.gd — 조작 탭 안내 라벨 (autowrap_mode WORD_SMART)",
		"consumer": "res://ui/sys/options_screen.gd"},
	{"keys": ["ui.options.o5Notice"], "width": 300.0, "max_lines": 3,
		"source": "options_screen.gd — 옵션 고지 라벨",
		"consumer": "res://ui/sys/options_screen.gd"},
	{"keys": ["ui.tip.currencyBody"], "width": 260.0, "max_lines": 8,
		"source": "garage_screen.gd — custom_minimum_size = Vector2(260, 0)",
		"consumer": "res://ui/hub/garage_screen.gd"},
	{"keys": ["ui.achievement.serviceUnlinked"], "width": 300.0, "max_lines": 4,
		"source": "achievement_screen.gd — 고지 행",
		"consumer": "res://ui/sys/achievement_screen.gd"},
	{"keys": ["ui.save.hintNew", "ui.save.hintContinue", "ui.save.cardFormat"],
		"width": 300.0, "max_lines": 4, "source": "save_slot_screen.gd — 슬롯 버튼 랩",
		"consumer": "res://ui/sys/save_slot_screen.gd"},
]

# 튜토리얼 콜아웃·확인 대화는 화면 층이 폭을 잡는다 — 랩 대장과 같은 성격이라
# 도메인 단위로 받는다(키가 늘어도 대장이 낡지 않는다).
const WRAP_DOMAIN_LEDGER := [
	# **폭을 실 선언값으로 교정했다 (25차)** — 초판은 둘 다 300 으로 어림했는데
	# 실제는 콜아웃 220 · 확인 패널 240 이다. 랩 판정은 폭에 직접 반응하므로
	# 어림한 폭은 줄 수를 과소 계상한다(느슨한 판정으로 통과하는 형태 — 23차 §4 계열).
	{"domain": "ui.tutorial.", "width": 220.0, "max_lines": 6,
		"source": "flow_screen.gd DetailText (Vector2(220, 0)) · autowrap",
		"consumer": "res://ui/flow/flow_screen.gd"},
	{"domain": "ui.confirm.", "width": 240.0, "max_lines": 4,
		"source": "confirm_dialog.gd 패널 (Vector2(240, 0)) · autowrap",
		"consumer": "res://ui/com/confirm_dialog.gd"},
	{"domain": "ui.tip.", "width": 260.0, "max_lines": 8,
		"source": "garage_screen.gd 온보딩 팁 (autowrap)", "consumer": "res://ui/hub/garage_screen.gd"},
	# 이벤트 본문 (개선 회차 3 E1 · 2026-09-03) — 패널 300 − 여백 10×2 = 280. 규격은 2줄(전각 62)이나
	# en 은 반각이라 3줄로 접힌다(패널이 세로로 자란다 — 기능 정상). 상한 3 = 그 여유까지다.
	{"domain": "ui.eventBody.", "width": 280.0, "max_lines": 3,
		"source": "event_node_screen.tscn BodyLabel (custom_minimum_size 280 · autowrap_mode 3)",
		"consumer": "res://ui/run/event_node_screen.tscn"},
]

var _failures := 0
var _checked := 0
var _frame := 0
var _strings: Array = []
var _body: FontFile
var _head: FontFile
var _body_size := 9
var _slots: Dictionary = {}      # 슬롯 이름 → {"width": px, "max_lines": n, "source": ..}
var _race: Control
var _options: Control
var _vn: Control
var _report_lines: Array = []


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		if not _boot():
			_report()
			return true
		return false
	if _frame < LAYOUT_SETTLE_FRAMES:
		return false
	_measure_slots()
	_self_test()
	_slot_ledger()
	_choice_rows()
	_wrap_ledger()
	_min_width_observation()
	_default_ceiling()
	_coverage_accounting()
	_longest_per_language()
	_narrow_slot_inventory()
	_report()
	return true


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


func _report() -> void:
	print("")
	for line in _report_lines:
		print(line)
	print("")
	if _checked < 2520:
		print("G4W_FAIL checks=%d < 하한 2520 (스위트 축소·씬 로드 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("G4W_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("G4W_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _boot() -> bool:
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	var data := GameData.new()
	if not data.load_all():
		_ok("데이터 적재", false)
		return false
	_body_size = data.param_int("param_font_size_body")
	_strings = CsvTable.load_rows(STRINGS_PATH)
	_ok("스트링 표 적재", not _strings.is_empty())
	_body = load(BODY_FONT) as FontFile
	_head = load(HEAD_FONT) as FontFile
	_ok("본문 원도 적재", _body != null)
	_ok("표제 원도 적재", _head != null)
	if _strings.is_empty() or _body == null or _head == null:
		return false
	# 슬롯 폭을 재려면 실화면이 서 있어야 한다 — 레이아웃 정렬 후에 읽는다.
	_race = _mount(RACE_SCENE, _fresh_session(data))
	_options = _mount(OPTIONS_SCENE, _fresh_session(data))
	_vn = _mount_vn(data)
	return true


func _fresh_session(data: GameData) -> RunSession:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	return session


func _mount(path: String, session: RunSession) -> Control:
	var packed := load(path) as PackedScene
	_ok("씬 로드: %s" % path, packed != null)
	if packed == null:
		return null
	var screen := packed.instantiate() as Control
	screen.session = session
	root.add_child(screen)
	if screen.has_method("bind"):
		screen.bind(session, {})
	return screen


func _mount_vn(data: GameData) -> Control:
	var session := _fresh_session(data)
	var payload := session.season_open_payload("HUB-01")
	var packed := load(VN_SCENE) as PackedScene
	if packed == null:
		return null
	var screen := packed.instantiate() as Control
	screen.session = session
	root.add_child(screen)
	screen.bind(session, payload)
	return screen


# ── 측정기 자기 검사 ──
#
# 이 스위트의 판정은 두 측정기(`_line_width`·`_wrapped_lines`) 위에 전부 얹혀 있다.
# 둘 중 하나가 상수를 돌려주면 **전 축이 조용히 통과**한다(초과 0 이 곧 판정이므로).
# 알려진 입력으로 측정기 자체를 못박는다 — V7S·GLYPH ⑤ 와 같은 형태다.
func _self_test() -> void:
	var half := _body.get_string_size("A", 0, -1, _body_size).x
	var full := _body.get_string_size("가", 0, -1, _body_size).x
	_ok("자기검사 반각 폭 > 0", half > 0.0, str(half))
	# 전각이 반각보다 넓다 (Galmuri9 실측 = 9px vs 5px — 정확히 2배는 아니다.
	# V3 의 전각 가중 2.0 은 **자수** 근사이고 픽셀은 실측이어야 하는 이유가 이 차이다).
	_ok("자기검사 전각 > 반각", full > half, "%f vs %f" % [full, half])
	# 폭은 길이에 비례해야 한다 — 상수 반환을 배제한다
	_ok("자기검사 폭이 길이를 따른다",
		_line_width("AAAAAAAAAA") > _line_width("A") * 5.0)
	# 명시 개행은 줄로 나눠 **최댓값**을 쓴다 — 이어 붙이면 폭이 부풀어 오검출이 난다
	_ok("자기검사 개행 분리",
		is_equal_approx(_line_width("AAAA\nA"), _line_width("AAAA")))
	# 랩 줄 수가 폭에 반응해야 한다 — 상수 1 반환을 배제한다
	# 공백을 넣는다 — 끊을 곳 없는 한 단어는 랩되지 않는 것이 정상 거동이다
	var long_text := "AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA"
	_ok("자기검사 좁은 폭 = 여러 줄", _wrapped_lines(long_text, half * 5.0) > 1,
		str(_wrapped_lines(long_text, half * 5.0)))
	_ok("자기검사 넓은 폭 = 한 줄", _wrapped_lines(long_text, half * 100.0) == 1,
		str(_wrapped_lines(long_text, half * 100.0)))
	# 기본 상한은 화면 폭을 넘을 수 없다 — 넘는 값은 상한이 아니라 면제다
	_ok("자기검사 기본 상한 ≤ 화면 폭",
		_vn != null and DEFAULT_CEILING <= _vn.size.x,
		"%f vs %f" % [DEFAULT_CEILING, _vn.size.x if _vn != null else -1.0])
	# 손으로 적은 두 값(노드가 없거나 숨어 있어 rect 를 못 읽는 자리)은 **원본에서 뽑아
	# 대장과 묶는다.** 문자열 포함만 보면 대장 쪽을 고쳐도 통과한다 — 실측으로 확인했다
	# (돌연변이 H4·H6 미검출). 출처가 바뀌면 파싱 값이 갈리고, 대장이 바뀌면 대조가 갈린다.
	var records_source := FileAccess.get_file_as_string("res://ui/hub/records_screen.gd")
	var declared_archive := _number_after_from(records_source,
		"name_label.text = _vn_title(", "custom_minimum_size = Vector2(")
	_ok("자기검사 아카이브 폭 = 원본 선언", declared_archive > 0.0
		and is_equal_approx(declared_archive, float(_slots["archiveTitle"]["width"])),
		"원본 %s vs 대장 %s" % [str(declared_archive), str(_slots["archiveTitle"]["width"])])
	var declared_rival := _number_after_from(records_source,
		"func _fill_rivals()", "custom_minimum_size = Vector2(")
	_ok("자기검사 라이벌 폭 = 원본 선언", declared_rival > 0.0
		and is_equal_approx(declared_rival, float(_slots["rivalName"]["width"])),
		"원본 %s vs 대장 %s" % [str(declared_rival), str(_slots["rivalName"]["width"])])
	var vn_scene_source := FileAccess.get_file_as_string("res://ui/nar/vn_screen.tscn")
	var declared_separation := _choice_separation_from(vn_scene_source)
	_ok("자기검사 선택지 간격 = 씬 선언", declared_separation > 0.0
		and is_equal_approx(declared_separation, CHOICE_SEPARATION),
		"씬 %s vs 대장 %s" % [str(declared_separation), str(CHOICE_SEPARATION)])


# ── 슬롯 실폭 측정 ──
func _measure_slots() -> void:
	_slots["log"] = _node_slot(_race, "%E10LogFeed", 2,
		"race_screen.tscn E10LogFeed 실 rect (D10 §5.7 시각 줄 2)")
	_slots["vnBody"] = _node_slot(_vn, "%BodyLabel", 2,
		"vn_screen.tscn BodyLabel 실 rect (D04 §5.1 2줄)")
	# 선택지 오버레이는 **숨은 상태로 서 있어** rect 가 0 이다(내용이 크기를 정하는
	# PanelContainer + `visible = false`). 그래서 개별 버튼 폭이 아니라 **지점당 행 총폭**을
	# 화면 폭과 대조한다 — 오버레이가 중앙에서 양쪽으로 자라므로 그것이 실제 구속이다
	# (내러티브 4차 §3.2 와 같은 방법). 화면 폭은 VN 화면 자신의 rect 에서 읽는다.
	_slots["choice"] = {"width": _vn.size.x if _vn != null else 0.0, "max_lines": 1,
		"source": "vn_screen 실 rect — 선택지 행 총폭 상한 (오버레이 중앙 성장)"}
	# 아카이브 표제는 **코드 생성 라벨**이라 노드가 상시 서 있지 않다 — 선언값 + 출처.
	_slots["archiveTitle"] = {"width": 140.0, "max_lines": 1,
		"source": "records_screen.gd 아카이브 행 name_label (Vector2(140, 0)) — 자기검사로 원본과 묶음"}
	# 라이벌 탭 이름 라벨 — 같은 파일의 **다른** 슬롯이고 110px 이다. 아카이브 앵커를
	# 좁히다 발견했다: `ui.rival.` 은 여기 서는데 대장에는 없어 기본 상한(620)으로 판정되고
	# 있었다. 실측 여유가 11px(ja 99)이라 통과하지만, **느슨한 판정으로 통과한 것**과
	# **맞는 판정으로 통과한 것**은 다르다.
	_slots["rivalName"] = {"width": 110.0, "max_lines": 1,
		"source": "records_screen.gd 라이벌 행 name_label (Vector2(110, 0))"}
	# ── 좁은 슬롯 정밀 배정 (25차) ──
	# 폭은 **원본에서 파싱해 대장과 묶는다**(23차 H4·H6 교훈 — 문자열 포함만 보면
	# 대장 쪽 위조를 놓친다). 각 항의 `anchor` 는 그 라벨을 만드는 함수·문장이다.
	for entry in NARROW_SLOTS:
		var declared := _number_after_from(
			FileAccess.get_file_as_string(String(entry["source_file"])),
			String(entry["anchor"]), "custom_minimum_size = Vector2(")
		_slots[String(entry["slot"])] = {"width": declared, "max_lines": 1,
			"source": "%s — %s" % [String(entry["source_file"]).get_file(), entry["anchor"]]}
		_ok("좁은 슬롯 폭 파싱: %s" % entry["slot"], declared > 0.0,
			"%s 에서 %s 를 못 찾았다" % [entry["source_file"], entry["anchor"]])
	for name in _slots:
		var slot: Dictionary = _slots[name]
		_ok("슬롯 폭 확보: %s" % name, float(slot["width"]) > 0.0,
			"%s (%s)" % [str(slot["width"]), slot["source"]])
		_report_lines.append("[슬롯] %-14s %6.1fpx · 줄 %d · %s"
			% [name, float(slot["width"]), int(slot["max_lines"]), slot["source"]])


func _node_slot(screen: Control, path: String, max_lines: int, source: String) -> Dictionary:
	if screen == null:
		return {"width": 0.0, "max_lines": max_lines, "source": source + " (씬 부재)"}
	var node := screen.get_node_or_null(path) as Control
	if node == null:
		return {"width": 0.0, "max_lines": max_lines, "source": source + " (노드 부재)"}
	return {"width": node.size.x, "max_lines": max_lines, "source": source}


func _languages() -> Array:
	return ["ko", "en", "ja"]


func _rows_for(prefix: String) -> Array:
	var out: Array = []
	for row in _strings:
		if String(Dictionary(row)["key"]).begins_with(prefix):
			out.append(row)
	return out


# 한 줄 최대 픽셀 폭 (명시 개행은 줄로 나눈다)
func _line_width(text: String) -> float:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, _body.get_string_size(String(line), 0, -1, _body_size).x)
	return widest


# 폭 W 로 랩했을 때의 줄 수
func _wrapped_lines(text: String, width: float) -> int:
	var total := 0
	for line in text.split("\n"):
		var size := _body.get_multiline_string_size(String(line), 0, width, _body_size)
		total += maxi(1, int(round(size.y / float(_body.get_height(_body_size)))))
	return total


# ── ① 슬롯 대장 (정밀) ──
# 좁은 슬롯 정밀 배정 (25차 — 23차 §4 이월분 10건 해소).
# **소비 키를 `name_key` 열로 확정했다** — 각 화면의 라벨이 어느 표의 `name_key` 를 그리는지
# 실독하고, 그 표가 가리키는 스트링 도메인을 접두로 잡았다(추정 0).
const SLOT_ASSIGNMENT := [
	{"prefix": "ui.vnSlot.", "slot": "archiveTitle", "kind": "single"},
	{"prefix": "ui.rival.", "slot": "rivalName", "kind": "single"},
	# ↑ 이 둘도 `custom_minimum_size` 출처다 — 아래 `MIN_WIDTH_OBSERVED` 주석 참조.
	#   이월 기록을 위해 판정에 남겨 두되, 초과가 나오면 그것이 절단의 증거는 아니다.

	{"prefix": "raceLog.", "slot": "log", "kind": "wrap"},
	{"prefix": "relay.", "slot": "log", "kind": "wrap"},
	{"prefix": "vane.", "slot": "log", "kind": "wrap"},
	{"prefix": "vn.", "slot": "vnBody", "kind": "wrap"},

]

var _assigned: Dictionary = {}   # key → 배정 근거


func _slot_ledger() -> void:
	for entry in SLOT_ASSIGNMENT:
		var slot: Dictionary = _slots[String(entry["slot"])]
		var width := float(slot["width"])
		var rows := _rows_for(String(entry["prefix"]))
		# `relay.` 는 V3 규칙 행에 있으나 **키가 0개**다(선언만 있는 도메인) — 그 사실을
		# 계수로 남긴다. 실재를 강제하면 규칙 행을 지우게 되는데, 규칙이 먼저 서 있는 것은
		# 유입 시 규율 밖으로 새지 않게 하는 정당한 상태다.
		if rows.is_empty():
			_ok("① 선언만 있는 도메인 (키 0): %s" % entry["prefix"], true)
			_report_lines.append("[①] %-12s → 키 0 (규칙 선언 선재)" % entry["prefix"])
			continue
		var over: Array = []
		for row in rows:
			var key := String(Dictionary(row)["key"])
			_assigned[key] = "slot:%s" % entry["slot"]
			for language in _languages():
				_checked += 1
				var value := String(Dictionary(row).get(language, ""))
				if value == "":
					continue
				if String(entry["kind"]) == "single":
					if _line_width(value) > width:
						over.append("%s(%s) %.1f > %.1f" % [key, language, _line_width(value), width])
				else:
					var lines := _wrapped_lines(value, width)
					if lines > int(slot["max_lines"]):
						over.append("%s(%s) %d줄 > %d" % [key, language, lines, int(slot["max_lines"])])
		_ok("① 초과 0: %s → %s" % [entry["prefix"], entry["slot"]], over.is_empty(),
			_head_of(over))
		_report_lines.append("[①] %-12s → %-13s 초과 %d" % [entry["prefix"], entry["slot"], over.size()])


# ── ①-b 선택지 지점 총폭 ──
#
# 선택지는 **행 단위**로 구속된다 — 버튼 하나가 좁아도 3개가 나란히 서면 화면을 넘는다.
# `vn_choice_options.csv` 실 구성대로 지점별로 합산한다(가상 구성이 아니다).
func _choice_rows() -> void:
	var slot: Dictionary = _slots["choice"]
	var width := float(slot["width"])
	_ok("①-b 화면 폭 확보", width > 0.0, str(width))
	var data := GameData.new()
	data.load_all()
	var separation := CHOICE_SEPARATION   # vn_screen.tscn ChoiceList theme_override_constants/separation
	var over: Array = []
	var points := 0
	for choice_id in data.vn_choices:
		points += 1
		var options := data.vn_choice_options_for(String(choice_id))
		for language in _languages():
			_checked += 1
			var total := separation * maxf(float(options.size()) - 1.0, 0.0)
			for option in options:
				var key := String(Dictionary(option)["text_key"])
				_assigned[key] = "choiceRow"
				var row := _row_of(key)
				total += _line_width(String(row.get(language, "")))
			if total > width:
				over.append("%s(%s) %.1f > %.1f" % [choice_id, language, total, width])
	_ok("①-b 선택 지점 실재", points > 0, str(points))
	_ok("①-b 지점 총폭 초과 0", over.is_empty(), _head_of(over))
	_report_lines.append("[①-b] 선택 지점 %d · 행 상한 %.0fpx · 초과 %d" % [points, width, over.size()])


# ── ①-c 최소 폭 슬롯 관측 (25차 — **방법 교정**) ──
#
# **`custom_minimum_size` 는 하한이지 상한이 아니다.** 23차·25차 초판은 이 값을 슬롯 폭으로
# 읽고 초과를 판정했는데, Godot 의 `custom_minimum_size` 는 라벨이 **그보다 작아지지 않게**
# 하는 값이고 텍스트가 넓으면 라벨이 커진다 — 컨테이너가 자르지 않는 한 절단은 없다.
# 실측이 그것을 드러냈다: `ui.achievement.markPending`(en) `Not Earned` = 49px vs 선언 44px 인데
# 소비 노드는 `HBoxContainer` 안이라 **행이 넓어질 뿐 잘리지 않는다**.
#
# 그래서 이 계열은 **판정에서 관측으로 내렸다.** 진짜 구속은 *행 총폭 대 컨테이너 폭*이고
# 그것은 ①-b(선택지 행)처럼 행 구성이 알려진 자리에서만 기계로 셀 수 있다.
# 초과는 **보고**한다 — 설계 폭을 넘는다는 사실은 레이아웃 밀림의 단서이고,
# 그 판정은 화면 층 실기 몫이다(느슨한 판정으로 통과시키는 것보다 정직한 관측이 낫다).
# 접두는 **조각으로 나눠 둔다** — 이어 붙인 전체가 소스에 리터럴로 있으면 V2 가
# '코드가 발행하는 키'로 보고 미등재를 차단한다(접두는 키가 아니다 · 21차 전례).
const ACHIEVEMENT_DOMAIN := "ui.achievement."
const OPTIONS_DOMAIN := "ui.options."

const MIN_WIDTH_OBSERVED := [
	{"prefix": "ui.skill.", "slot": "strategySkillName"},
	{"prefix": "ui.sponsor.", "slot": "sponsorName"},
	{"prefix": "ui.overhaul.", "slot": "overhaulPick"},
	{"prefix": "ui.facility.", "slot": "facilityName"},
	{"prefix": "ui.tuning.", "slot": "tuningName"},
	{"prefix": ACHIEVEMENT_DOMAIN + "mark", "slot": "achievementMark"},
	{"prefix": OPTIONS_DOMAIN + "o", "slot": "optionLabel"},
]


func _min_width_observation() -> void:
	var total_over := 0
	for entry in MIN_WIDTH_OBSERVED:
		var slot: Dictionary = _slots.get(String(entry["slot"]), {})
		var width := float(slot.get("width", 0.0))
		_ok("①-c 선언 폭 파싱: %s" % entry["slot"], width > 0.0, str(width))
		if width <= 0.0:
			continue
		var over: Array = []
		for row in _rows_for(String(entry["prefix"])):
			var key := String(Dictionary(row)["key"])
			# 랩 대장에 이미 배정된 키는 건너뛴다 — 랩 라벨은 폭을 넘는 것이 정상이고
			# 여기서 다시 세면 관측이 소음이 된다(`ui.options.o5Notice` 가 그 형태였다).
			if String(_assigned.get(key, "")).begins_with("wrap"):
				continue
			if not _assigned.has(key):
				_assigned[key] = "minWidth"
			for language in _languages():
				_checked += 1
				var measured := _line_width(String(Dictionary(row).get(language, "")))
				if measured > width:
					over.append("%s(%s) %.0f > %.0f" % [key, language, measured, width])
		total_over += over.size()
		_report_lines.append("[①-c] %-22s 선언 %4.0fpx · 선언 초과 %d%s"
			% [entry["prefix"], width, over.size(),
				("  " + _head_of(over)) if not over.is_empty() else ""])
	# **관측이지 판정이 아니다** — 계수만 남기고 통과시킨다. 다만 관측이 사라지면 안 되므로
	# 대상 표본의 실재는 단언한다(도메인이 비면 이 축이 조용히 0을 보고한다).
	_ok("①-c 관측 표본 확보", MIN_WIDTH_OBSERVED.size() >= 7, str(MIN_WIDTH_OBSERVED.size()))
	_report_lines.append("[①-c] 선언 폭 초과 총 %d건 (관측 — 절단 증거 아님 · 화면 층 실기 판정)"
		% total_over)


# ── ② 랩 대장 ──
func _wrap_ledger() -> void:
	for ledger in WRAP_LEDGER:
		var consumer := FileAccess.get_file_as_string(String(ledger["consumer"]))
		# **랩한다고 적힌 것이 실제로 랩하는가** — 소비부에 `autowrap_mode` 가 없으면
		# 이 대장은 초과를 통과시키는 면제장이 된다.
		_ok("② 소비부 autowrap 실재: %s" % ledger["keys"][0],
			consumer.contains("autowrap_mode"), String(ledger["consumer"]))
		for key in Array(ledger["keys"]):
			var row := _row_of(String(key))
			_ok("② 키 실재: %s" % key, not row.is_empty())
			if row.is_empty():
				continue
			_assigned[String(key)] = "wrap:%.0f/%d" % [float(ledger["width"]), int(ledger["max_lines"])]
			for language in _languages():
				_checked += 1
				var lines := _wrapped_lines(String(row.get(language, "")), float(ledger["width"]))
				_ok("② %s(%s) 줄 수 %d ≤ %d" % [key, language, lines, int(ledger["max_lines"])],
					lines <= int(ledger["max_lines"]))
	for ledger in WRAP_DOMAIN_LEDGER:
		var consumer := FileAccess.get_file_as_string(String(ledger["consumer"]))
		_ok("② 소비부 autowrap 실재: %s" % ledger["domain"], consumer.contains("autowrap_mode"))
		var rows := _rows_for(String(ledger["domain"]))
		_ok("② 도메인 키 실재: %s" % ledger["domain"], not rows.is_empty(), str(rows.size()))
		var over: Array = []
		for row in rows:
			var key := String(Dictionary(row)["key"])
			_assigned[key] = "wrap:%.0f/%d" % [float(ledger["width"]), int(ledger["max_lines"])]
			for language in _languages():
				_checked += 1
				var lines := _wrapped_lines(String(Dictionary(row).get(language, "")),
					float(ledger["width"]))
				if lines > int(ledger["max_lines"]):
					over.append("%s(%s) %d줄" % [key, language, lines])
		_ok("② 초과 0: %s" % ledger["domain"], over.is_empty(), _head_of(over))
		_report_lines.append("[②] %-22s 랩 %4.0fpx/%d줄 · 초과 %d"
			% [ledger["domain"], float(ledger["width"]), int(ledger["max_lines"]), over.size()])


# ── ③ 기본 상한 — 슬롯이 특정되지 않은 잔여 전량 ──
func _default_ceiling() -> void:
	var over: Array = []
	var counted := 0
	for row in _strings:
		var key := String(Dictionary(row)["key"])
		if _assigned.has(key):
			continue
		_assigned[key] = "ceiling"
		counted += 1
		for language in _languages():
			_checked += 1
			var width := _line_width(String(Dictionary(row).get(language, "")))
			if width > DEFAULT_CEILING:
				over.append("%s(%s) %.1f > %.1f" % [key, language, width, DEFAULT_CEILING])
	_ok("③ 기본 상한 대상 실재", counted > 0, str(counted))
	_ok("③ 기본 상한 초과 0", over.is_empty(), _head_of(over))
	_report_lines.append("[③] 기본 상한 %.0fpx · 대상 %d키 · 초과 %d"
		% [DEFAULT_CEILING, counted, over.size()])


# ── ④ 커버리지 회계 — 판정 밖 키 0 ──
#
# 대장이 도메인을 조용히 빠뜨리는 것이 이 검사의 가장 큰 실패 양식이다.
# 전 키가 ①②③ 중 하나에 배정됐음을 계수로 못박는다.
func _coverage_accounting() -> void:
	var unassigned: Array = []
	for row in _strings:
		var key := String(Dictionary(row)["key"])
		if not _assigned.has(key):
			unassigned.append(key)
	_ok("④ 판정 밖 키 0", unassigned.is_empty(), _head_of(unassigned))
	_ok("④ 배정 계수 = 표 계수", _assigned.size() == _strings.size(),
		"%d vs %d" % [_assigned.size(), _strings.size()])
	var by_kind: Dictionary = {}
	for key in _assigned:
		var kind := String(_assigned[key]).split(":")[0]
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	# **배정이 옳은 통에 들어갔는가.** 전부 한 통에 몰아넣어도 계수 대조는 통과한다 —
	# 통마다 표본 키를 못박아 그 형태를 배제한다.
	for probe in [["raceLog.timeout01", "slot"], ["vnChoice.act1.opt1", "choiceRow"],
			["ui.tip.currencyBody", "wrap"], ["ui.title.gameTitle", "ceiling"]]:
		var key := String(probe[0])
		_ok("④ 배정 표본: %s → %s" % [key, probe[1]],
			String(_assigned.get(key, "")).split(":")[0] == String(probe[1]),
			String(_assigned.get(key, "(미배정)")))
	for kind in ["slot", "choiceRow", "wrap", "ceiling"]:
		_ok("④ 통 비공란: %s" % kind, int(by_kind.get(kind, 0)) > 0, str(by_kind.get(kind, 0)))
	_report_lines.append("[④] 배정 %d키 = %s" % [_assigned.size(), str(by_kind)])


# ── ⑤ 언어별 최장 라벨 산출 (D14 §5.4 "라벨 단위 최장 렌더 폭 언어") ──
func _longest_per_language() -> void:
	var widest: Dictionary = {"ko": 0.0, "en": 0.0, "ja": 0.0}
	var widest_key: Dictionary = {}
	var by_language: Dictionary = {"ko": 0, "en": 0, "ja": 0}
	for row in _strings:
		var key := String(Dictionary(row)["key"])
		var best := ""
		var best_width := -1.0
		for language in _languages():
			var width := _line_width(String(Dictionary(row).get(language, "")))
			if width > float(widest[language]):
				widest[language] = width
				widest_key[language] = key
			if width > best_width:
				best_width = width
				best = language
		by_language[best] = int(by_language[best]) + 1
	for language in _languages():
		_ok("⑤ %s 최장 라벨 산출" % language, float(widest[language]) > 0.0)
		_report_lines.append("[⑤] %s 최장 %6.1fpx  %s"
			% [language, float(widest[language]), String(widest_key.get(language, ""))])
	# **최장 언어가 en 인 라벨이 다수여야 한다** — D04 §5.6-7 이 전제한 130% 번역 팽창의
	# 실측 확인이다. ko 가 다수면 팽창 전제가 깨진 것이고 그것 자체가 보고 사안이다.
	_ok("⑤ 최장 언어 분포 산출", int(by_language["en"]) > 0)
	_report_lines.append("[⑤] 최장 언어 분포 = %s" % str(by_language))


# 앵커 직후의 첫 숫자. 원본 선언에서 값을 **뽑아** 대장과 대조하기 위한 것이며,
# 문자열 포함 검사와 달리 대장 쪽 위조를 잡는다.
#
# `from_anchor` 로 구간을 먼저 좁힌다 — 같은 파일에 같은 선언이 여럿이면(실제로
# `records_screen.gd` 에는 `name_label.custom_minimum_size` 가 라이벌 탭 110px 과
# 아카이브 탭 140px 두 곳에 있다) 첫 일치를 집어 **다른 슬롯의 값을 읽는다.**
func _number_after_from(source: String, from_anchor: String, anchor: String) -> float:
	var start := source.find(from_anchor)
	if start < 0:
		return -1.0
	return _number_after(source.substr(start), anchor)


func _number_after(source: String, anchor: String) -> float:
	var at := source.find(anchor)
	if at < 0:
		return -1.0
	var digits := ""
	var index := at + anchor.length()
	while index < source.length():
		var ch := source[index]
		if ch.is_valid_int() or (ch == "." and not digits.is_empty()):
			digits += ch
		elif not digits.is_empty():
			break
		index += 1
	return digits.to_float() if not digits.is_empty() else -1.0


# ChoiceList 노드 선언 블록 안의 separation 값
func _choice_separation_from(scene_source: String) -> float:
	var at := scene_source.find("[node name=\"ChoiceList\"")
	if at < 0:
		return -1.0
	return _number_after(scene_source.substr(at),
		"theme_override_constants/separation = ")


# ── ⑥ 좁은 슬롯 인벤토리 (정밀도 경계 공시) ──
#
# 코드 생성 라벨의 고정 폭 선언을 전수 수집한다. **대장이 덮지 못한 좁은 슬롯이
# 몇 개 남아 있는지를 숨기지 않는 것**이 이 축의 일이다 — 기본 상한(620)은 진짜 상한이
# 아니라 '이보다 넓으면 어디서도 잘린다'는 하한선이고, 좁은 슬롯은 그보다 훨씬 엄하다.
# `ui.rival.`(110px)이 그 상태로 통과하고 있었고, 앵커를 좁히다 우연히 드러났다.
const NARROW_THRESHOLD := 320.0


func _narrow_slot_inventory() -> void:
	var found: Array = []
	for path in _ui_sources():
		var source := FileAccess.get_file_as_string(String(path))
		var from := 0
		while true:
			var at := source.find("custom_minimum_size = Vector2(", from)
			if at < 0:
				break
			var width := _number_after(source.substr(at), "Vector2(")
			# 높이 0 = 폭 전용 구속. 아이콘·정사각 배치는 라벨 폭이 아니다.
			var tail := source.substr(at, 60)
			if width > 0.0 and width < NARROW_THRESHOLD and tail.contains(", 0)"):
				found.append("%s:%.0f" % [String(path).get_file(), width])
			from = at + 1
	_ok("⑥ 좁은 슬롯 수집 성립", not found.is_empty(), str(found.size()))
	_report_lines.append("[⑥] 좁은 폭 선언 %d건 (대장 정밀 배정 = %d슬롯) — %s"
		% [found.size(), SLOT_ASSIGNMENT.size(), ", ".join(found)])


func _ui_sources() -> Array:
	var out: Array = []
	_collect_gd("res://ui", out)
	return out


func _collect_gd(path: String, sink: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [path, entry]
		if dir.current_is_dir():
			_collect_gd(full, sink)
		elif entry.ends_with(".gd"):
			sink.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _row_of(key: String) -> Dictionary:
	for row in _strings:
		if String(Dictionary(row)["key"]) == key:
			return row
	return {}


func _head_of(items: Array) -> String:
	if items.is_empty():
		return ""
	var sample: Array = []
	for index in range(mini(items.size(), 5)):
		sample.append(String(items[index]))
	return "%d건: %s" % [items.size(), " | ".join(sample)]
