# UIOPT — 화면 층 옵션 소비부 검사 (D09 §6.1 "전 옵션 즉시 반영·재시작 불요").
#
# 현재 축 = **O9 색각 대체 팔레트**(A-팔레트-02). 옵션 항목만 있고 소비부가 없으면
# 설정은 켜지는데 화면은 그대로다 — 그 상태가 "구현됨"으로 계상되는 것을 막는다.
#
# 검사 축 4종:
#   ① 전사 대조 — 대체 4색이 실물 `colorblind_alt.gpl` 의 CB 항목과 일치하는가
#   ② 토글 — O9 인덱스가 팔레트 상태를 실제로 뒤집는가
#   ③ **비교체 슬롯 불변** — hex 가 같다는 이유로 함께 바뀌지 않는가 (정본 §6 = 4행이 전부)
#   ④ 소비부 경유 — 교체 대상 색을 화면이 **상수로 직접 읽는 지점이 남아 있지 않은가**
extends SceneTree

const PALETTE_PATH := "res://assets/palettes/colorblind_alt.gpl"
const UI_DIR := "res://ui/"
# 조회 창구를 거쳐야 하는 상수 → 거치는 함수. 상수를 직접 읽으면 O9 가 그 지점만 안 먹는다.
const MUST_ROUTE := {
	"TIMER_IMMINENT": "gauge_danger()",
	"TIMER_WARNING": "gauge_caution()",
	"CHASSIS_WARN": "gauge_danger()",
	"SYMBOL_LINE": "symbol_line()",
	"SYMBOL_TROUBLE": "symbol_trouble()",
}
# 팔레트 정의 파일 자신과 도상 생성기는 기본색을 직접 다루는 것이 일이다.
const ROUTE_EXEMPT := ["ui_palette.gd"]

var _checked := 0
var _failures := 0


func _init() -> void:
	_transcription()
	_toggle()
	_untouched_slots()
	_applied_on_screen_bind()
	_consumers_route()
	print("")
	if _checked < 20:
		print("UI_OPTIONS_FAIL checks=%d < 하한 20 (스위트 축소 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("UI_OPTIONS_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("UI_OPTIONS_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


# ── ① 실물 전사 대조 ──
func _transcription() -> void:
	var swatches := _load_gpl(PALETTE_PATH)
	_ok("색각 대체 팔레트 실물 적재", not swatches.is_empty(), PALETTE_PATH)
	var expected := {
		"CB-라인": UiPalette.ALT_SYMBOL_LINE,
		"CB-트러블": UiPalette.ALT_SYMBOL_TROUBLE,
		"CB-게이지위험": UiPalette.ALT_GAUGE_DANGER,
		"CB-게이지주의": UiPalette.ALT_GAUGE_CAUTION,
	}
	for name in expected:
		var actual: Variant = swatches.get(name)
		_ok("정본 §6 전사 — %s" % name, actual != null and Color(actual) == Color(expected[name]),
			"실물=%s 코드=%s" % [str(actual), String(Color(expected[name]).to_html(false))])
	# 실물에 CB 항목이 4개뿐인지도 본다 — 정본이 "교체는 최소로"라고 못 박았다.
	var cb_count := 0
	for name in swatches:
		if String(name).begins_with("CB-"):
			cb_count += 1
	_ok("대체 항목이 정확히 4종", cb_count == 4, "실물 CB 항목 %d종" % cb_count)


# ── ② 토글 ──
func _toggle() -> void:
	var data := GameData.new()
	data.load_all()
	var options := OptionsStore.new()
	options.setup(data)
	options.set_index("o9", 0)
	UiPalette.apply_options(options)
	_ok("O9 기본 = 기본 팔레트", not UiPalette.colorblind)
	_ok("기본에서 라인색 = 기본값", UiPalette.symbol_line() == UiPalette.SYMBOL_LINE)
	_ok("기본에서 게이지 위험 = 기본값", UiPalette.gauge_danger() == UiPalette.TIMER_IMMINENT)
	options.set_index("o9", 1)
	UiPalette.apply_options(options)
	_ok("O9 대체 선택 = 대체 팔레트", UiPalette.colorblind)
	_ok("대체에서 라인색 교체", UiPalette.symbol_line() == UiPalette.ALT_SYMBOL_LINE)
	_ok("대체에서 트러블색 교체", UiPalette.symbol_trouble() == UiPalette.ALT_SYMBOL_TROUBLE)
	_ok("대체에서 게이지 위험 교체", UiPalette.gauge_danger() == UiPalette.ALT_GAUGE_DANGER)
	_ok("대체에서 게이지 주의 교체", UiPalette.gauge_caution() == UiPalette.ALT_GAUGE_CAUTION)
	options.set_index("o9", 0)
	UiPalette.apply_options(options)
	_ok("되돌리면 기본으로 복귀", not UiPalette.colorblind)


# ── ③ 비교체 슬롯 불변 ──
# `VANE_ALERT` 는 게이지 위험과, `SYMBOL_BRAKING` 은 게이지 주의와 hex 가 같다.
# **정본 §6 표에 없으므로 바뀌지 않는다** — hex 기준으로 일괄 치환하면 정본에 없는 교체를
# 구현이 만든 것이 된다. 이 검사가 그 유혹을 막는다.
func _untouched_slots() -> void:
	var options := OptionsStore.new()
	var data := GameData.new()
	data.load_all()
	options.setup(data)
	options.set_index("o9", 1)
	UiPalette.apply_options(options)
	_ok("베인 경고는 교체 대상이 아니다",
		UiPalette.VANE_ALERT == UiPalette.TIMER_IMMINENT and UiPalette.VANE_ALERT != UiPalette.gauge_danger(),
		"베인=%s 대체 게이지위험=%s" % [UiPalette.VANE_ALERT.to_html(false),
			UiPalette.gauge_danger().to_html(false)])
	_ok("심볼 브레이킹은 교체 대상이 아니다",
		UiPalette.SYMBOL_BRAKING == UiPalette.TIMER_WARNING
			and UiPalette.SYMBOL_BRAKING != UiPalette.gauge_caution())
	options.set_index("o9", 0)
	UiPalette.apply_options(options)


# 팔레트가 세션을 못 쥐므로 옵션은 **밀어 넣는** 구조다. 그 밀어 넣기가 빠지면 화면은
# 옛 색으로 남는데 위 검사들은 전부 통과한다(직접 `apply_options` 를 부르기 때문 —
# 돌연변이 ⑧ 미검출로 실측). 화면 결속이 실제로 적용하는지를 베이스 화면으로 확인한다.
#
# **사각 1건 해소 (IMPL-180).** 이 검사는 `bind()` 경로만 본다. `race_screen` 은 세션이
# 없으면 **스스로 세션을 세우는 단독 경로**를 갖는데(`_boot()`), 그 경로는 `bind()` 를
# 거치지 않아 O9 가 적용되지 않았다 — 그 축은 UISCR(`test_ui_screens.gd`)이 본다.
# 실화면 인스턴스화가 필요해 프레임을 도는 스위트로 보냈다(이 스위트는 `_init` 동기 실행).
func _applied_on_screen_bind() -> void:
	var data := GameData.new()
	data.load_all()
	var session := RunSession.new()
	session.setup(data)
	session.options.set_index("o9", 1)
	UiPalette.colorblind = false          # 결속이 바꾸는 것인지 보려면 먼저 되돌려 둔다
	var screen := FlowScreen.new()        # 씬 없이 베이스만 — `bind()` 계약만 본다
	screen.bind(session, {})
	_ok("화면 결속이 O9 를 팔레트에 적용한다", UiPalette.colorblind)
	session.options.set_index("o9", 0)
	UiPalette.colorblind = true
	screen.bind(session, {})
	_ok("화면 결속이 O9 해제도 적용한다", not UiPalette.colorblind)
	screen.free()


# ── ④ 소비부가 조회 창구를 거치는가 ──
func _consumers_route() -> void:
	for constant_name in MUST_ROUTE:
		var direct: Array[String] = []
		_scan(UI_DIR, "UiPalette.%s" % String(constant_name), direct)
		_ok("%s 직접 참조 없음 (→ %s)" % [String(constant_name), String(MUST_ROUTE[constant_name])],
			direct.is_empty(), "직접 참조: %s" % ", ".join(direct))


func _scan(dir_path: String, needle: String, hits: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + entry
		if dir.current_is_dir():
			_scan(full + "/", needle, hits)
		elif entry.ends_with(".gd") and not ROUTE_EXEMPT.has(entry):
			var file := FileAccess.open(full, FileAccess.READ)
			if file != null and file.get_as_text().contains(needle):
				hits.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()


# GIMP 팔레트 = `R G B\t이름` 행. 이름으로 뽑는다 — 순서에 기대지 않는다.
func _load_gpl(path: String) -> Dictionary:
	var swatches: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return swatches
	for raw_line in file.get_as_text().split("\n"):
		var line := String(raw_line)
		if line.is_empty() or line.begins_with("#") or not line.contains("\t"):
			continue
		var parts := line.split("\t", false, 1)
		if parts.size() < 2:
			continue
		var channels := String(parts[0]).split(" ", false)
		if channels.size() < 3:
			continue
		swatches[String(parts[1]).split(" ")[0]] = Color8(
			int(channels[0]), int(channels[1]), int(channels[2]))
	return swatches


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])
