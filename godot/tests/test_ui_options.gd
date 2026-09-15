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
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	_transcription()
	_toggle()
	_untouched_slots()
	_applied_on_screen_bind()
	_consumers_route()
	_language_consumption()
	_auto_advance_and_removed_scale()
	print("")
	if _checked < 54:
		print("UI_OPTIONS_FAIL checks=%d < 하한 54 (스위트 축소 의심)" % _checked)
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


# ── O10 VN 자동 진행 · 걷어낸 O7·O8 (개선 회차 22 → 25 → 28) ──
#
# 세 항목 다 종전에는 **저장만 되고 소비부가 0** 이었다(매뉴얼 9절 5항). 회차 22 가 O8·O10 을
# 결선하고, 회차 25 가 O7 을 원도에 맞춘 2단으로 결선했으며, **회차 28 이 O7 의 확대 단
# (Galmuri11 @ 11px = 종전 122%)을 기본값으로 승격하고 O7·O8 을 항목·소비부 함께 걷었다**
# (사용자 결정 2026-09-16). 이 축은 O10 소비부와 함께 **걷어낸 것이 되살아나지 않는가**를 본다 —
# 항목만 돌아오고 소비부가 없으면 회차 22 이전의 상태(설정은 켜지는데 화면은 그대로)가 재현된다.
func _auto_advance_and_removed_scale() -> void:
	var data := GameData.new()
	if not data.load_all():
		_ok("데이터 적재", false)
		return
	var session := RunSession.new()
	session.setup(data)   # 창 없음

	# O10 — 단계 → 대기 시간(초). 값은 D13 창구 경유이며 느릴수록 길다.
	var waits: Array = []
	for step in range(3):
		session.options.set_index("o10", step)
		waits.append(session.vn_auto_advance_sec())
	_ok("O10 느림 = param_vn_auto_slow_sec",
		is_equal_approx(float(waits[0]), data.param("param_vn_auto_slow_sec")), str(waits))
	_ok("O10 보통 = param_vn_auto_normal_sec",
		is_equal_approx(float(waits[1]), data.param("param_vn_auto_normal_sec")), str(waits))
	_ok("O10 빠름 = param_vn_auto_fast_sec",
		is_equal_approx(float(waits[2]), data.param("param_vn_auto_fast_sec")), str(waits))
	_ok("느림 > 보통 > 빠름", float(waits[0]) > float(waits[1]) and float(waits[1]) > float(waits[2]),
		str(waits))

	# VN 화면이 그 값을 실제로 쓴다 — 창구만 있고 화면이 안 읽으면 종전과 같은 상태다.
	var vn_src := FileAccess.get_file_as_string("res://ui/nar/vn_screen.gd")
	_ok("VN 화면이 자동 진행 창구를 읽는다", vn_src.contains("session.vn_auto_advance_sec()"))
	_ok("VN 화면에 자동 토글이 있다", vn_src.contains("ui.vn.auto"))
	_ok("라인마다 다시 잰다", vn_src.contains("_restart_auto_timer()"))

	_ok("O10 은 목록에 있다", _listed("o10"))

	# ── 걷어낸 O7·O8 — 항목·소비부·값·문면 네 층이 함께 없어야 한다 (개선 회차 28) ──
	# 한 층만 남으면 그 층이 다음 회차에 "이미 있는 것"으로 읽혀 되살아난다(회차 22 이전의
	# O7·O8 이 정확히 그 형태였다 — 항목·문면은 있고 소비부만 0).
	for option_id in ["o7", "o8"]:
		_ok("%s 는 옵션 목록에 없다" % option_id, not _listed(String(option_id)))
		_ok("%s 정의가 없다" % option_id, not OptionsStore.OPTIONS.has(option_id))
	_ok("세션에 UI 스케일 창구가 없다", not session.has_method("ui_scale_factor")
		and not session.has_method("apply_display_options"))
	_ok("세션에 텍스트 크기 창구가 없다", not session.has_method("text_body_font_size")
		and not session.has_method("text_body_font"))
	var flow_src := FileAccess.get_file_as_string("res://ui/flow/flow_screen.gd")
	_ok("화면 베이스가 본문 크기를 D13 창구에서 직접 받는다",
		flow_src.contains('_body_font_size = session.data.param_int("param_font_size_body")'))
	_ok("대형 계열은 기준값 그대로", flow_src.contains('_head_font_size = session.data.param_int("param_font_size_head")'))
	_ok("씬 크기 따라잡기 경로가 없다 (씬이 곧 기본값이다)", not flow_src.contains("_rescale_body_labels"))
	var theme_src := FileAccess.get_file_as_string("res://ui/theme/ui_theme.gd")
	_ok("테마 창구에 원도 교체 경로가 없다", not theme_src.contains("apply_text_size"))
	var options_src := FileAccess.get_file_as_string("res://ui/sys/options_screen.gd")
	_ok("옵션 화면이 표시 배율 적용을 부르지 않는다", not options_src.contains("apply_display_options"))
	for param_id in ["param_opt_ui_scale_1", "param_opt_ui_scale_2", "param_opt_text_size_body_1"]:
		_ok("걷어낸 값 행이 없다: %s" % param_id, not data.params.has(param_id))
	# 접두와 항목을 갈라 둔다 — 이어 붙인 전체가 리터럴로 있으면 V2 가 '코드가 발행하는 키'로 보고
	# 미등재를 차단한다(G4W 대장 `OPTIONS_DOMAIN` 과 같은 회피 · 21차 전례). 여기서 묻는 것은 **부재**라 조립이 맞다.
	var removed_prefix := "ui.options."
	for item in ["o7", "o8", "stepScale100", "stepScale110", "stepScale122", "stepScale125"]:
		var key := removed_prefix + String(item)
		_ok("걷어낸 문면이 없다: %s" % key, not data.strings.has_key(key))

	# ── 기본값 = 종전 122% — 전역 기본과 D13 창구가 같은 원도·같은 크기를 쥔다 ──
	# 크기는 표(param_font_size_body)가, 원도는 project.godot 이 댄다. 둘이 갈리면 코드 생성
	# 라벨(창구)과 씬(전역)이 다른 격자로 그려진다.
	var body := data.param_int("param_font_size_body")
	_ok("본문 창구 = 11 (종전 확대 단이 기본값)", body == 11, str(body))
	var global_size := int(ProjectSettings.get_setting("gui/theme/default_font_size", 0))
	_ok("전역 기본 크기 = 본문 창구", global_size == body, "global=%d param=%d" % [global_size, body])
	var global_font := String(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	_ok("전역 기본 원도 = Galmuri11 (11px 원도)", global_font.ends_with("Galmuri11.ttf"), global_font)
	var loaded := load(global_font) as FontFile
	_ok("전역 기본 원도 실물 적재", loaded != null, global_font)


func _listed(option_id: String) -> bool:
	for tab in OptionsStore.TABS:
		if Array(tab["options"]).has(option_id):
			return true
	return false


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


# ── ⑤ O11 언어 소비부 (21차 신설 — 발주 ②) ──
#
# **데이터는 있는데 도달할 수 없었다** (내러티브 4차 §6-B 실독): 3중 절단 —
# `load_file` 언어 인자 없음 · O11 단계 1개 · 저장·재적재 경로 부재.
# O9 팔레트와 같은 형태의 결함이다("설정은 켜지는데 화면은 그대로")이므로 같은 스위트에 둔다.
func _language_consumption() -> void:
	var data := GameData.new()
	if not data.load_all():
		_ok("⑤ 데이터 적재", false)
		return
	# 선택 가능한 언어 = 표 헤더. 손으로 적은 목록이 아니라는 것이 요건이다.
	var languages: Array = data.languages()
	_ok("⑤ 언어 = 표 헤더에서 온다", languages == ["ko", "en", "ja"], str(languages))
	_ok("⑤ 개시 언어 = 원문", data.language == GameData.DEFAULT_LANGUAGE, data.language)
	# 전환이 **문면을 실제로 바꾸는가.** 인자가 통과했다는 것으로는 부족하다 —
	# `load_file` 은 언어 인자를 무시해도 true 를 돌려준다(초판 상태가 정확히 그랬다).
	var probe_key := "ui.options.o11"
	var ko_text := data.strings.text(probe_key)
	_ok("⑤ 전환 성립: en", data.set_language("en"))
	var en_text := data.strings.text(probe_key)
	_ok("⑤ en 문면이 갈린다", en_text != ko_text, "%s vs %s" % [en_text, ko_text])
	_ok("⑤ 전환 성립: ja", data.set_language("ja"))
	var ja_text := data.strings.text(probe_key)
	_ok("⑤ ja 문면이 갈린다", ja_text != ko_text and ja_text != en_text, ja_text)
	_ok("⑤ 전환 후 언어 상태 갱신", data.language == "ja", data.language)
	# 미등재 언어는 거부하고 **현행을 유지한다** — 무문면 화면보다 낫다.
	_ok("⑤ 미등재 언어 거부", not data.set_language("zh"))
	_ok("⑤ 거부 후 현행 유지", data.language == "ja" and data.strings.text(probe_key) == ja_text)
	_ok("⑤ 원문 복귀", data.set_language("ko") and data.strings.text(probe_key) == ko_text)
	# 미등재 언어로 **개시**하는 경로는 `GameData.set_language` 의 사전 검사를 타지 않는다 —
	# `load_all(초기언어)` 가 곧바로 `StringTable.load_file` 로 간다. 두 관문이 겹쳐 있어
	# 한쪽을 지워도 다른 쪽이 가려 주는 상태였고(돌연변이 F8 미검출), 이 축이 그 경로를 직접 본다.
	var bogus := GameData.new()
	_ok("⑤ 미등재 초기 언어 적재 거부", not bogus.load_all("zh"))
	_ok("⑤ 거부가 침묵 통과로 새지 않는다", not bogus.is_ok())
	# 옵션 저장소 — 단계 수가 헤더에서 오고, 인덱스가 코드로 번역된다.
	# **디스크를 건드리는 축이다** (`set_index` 가 즉시 저장한다) — 원래 값을 떠 두고
	# 끝에서 되돌린다. 검사가 기기 설정을 남기면 다음 스위트가 그 상태에서 출발한다.
	var store := OptionsStore.new()
	store.setup(data)
	var saved_index := store.index_of("o11")
	_ok("⑤ O11 단계 수 = 언어 수", store.step_count("o11") == languages.size(),
		"%d" % store.step_count("o11"))
	for index in range(languages.size()):
		store.set_index("o11", index)
		_ok("⑤ 인덱스 %d → 코드 %s" % [index, languages[index]],
			store.language_code() == String(languages[index]), store.language_code())
		var label := store.step_label("o11", index)
		_ok("⑤ 단계 라벨 비공란: %s" % languages[index], label != "", label)
	# 범위 밖 인덱스(열 순서가 바뀐 구설정) → 원문. 엉뚱한 언어보다 원문이 낫다.
	# **값을 여럿 쓴다** — 하나만 보면 `index % size` 같은 잘못된 구현이 우연히 0(=ko)으로
	# 접혀 통과한다(돌연변이 F6 이 정확히 그 형태였다). 음수도 함께 본다.
	for bad_index in [99, 100, 101, -1, -4]:
		store.set_index("o11", bad_index)
		_ok("⑤ 범위 밖 인덱스 %d → 원문" % bad_index,
			store.language_code() == GameData.DEFAULT_LANGUAGE, store.language_code())
	store.set_index("o11", 0)
	# 세션 창구 — 코어는 옵션 저장소를 읽을 수 없으므로 세션이 옮긴다.
	# `setup()` 에서 부르지 않으면 저장된 선택이 재시작마다 원문으로 돌아간다.
	var session := RunSession.new()
	session.setup(data)
	session.options.set_index("o11", languages.find("ja"))
	_ok("⑤ 세션 경유 전환", session.apply_language())
	_ok("⑤ 세션 전환이 표에 도달", session.data.language == "ja", session.data.language)
	# 재개시 모사 — 저장된 인덱스를 그대로 둔 채 새 세션을 세우면 그 언어로 서야 한다.
	# **새 `GameData` 를 준다.** 위에서 이미 "ja" 로 바뀐 인스턴스를 재사용하면
	# `setup()` 이 언어를 옮기지 않아도 검사가 통과한다 — 자기 충족 단언이었고
	# 돌연변이 F5(`setup` 에서 `apply_language()` 제거)가 그것을 드러냈다.
	var fresh := GameData.new()
	_ok("⑤ 재개시용 데이터 적재", fresh.load_all())
	_ok("⑤ 새 인스턴스는 원문에서 출발", fresh.language == GameData.DEFAULT_LANGUAGE)
	var reopened := RunSession.new()
	reopened.setup(fresh)
	_ok("⑤ 재개시가 저장된 언어로 선다", reopened.data.language == "ja", reopened.data.language)
	# 기기 설정·표 상태 원복 — 저장소는 디스크를, `data` 는 자기 표 상태를 되돌린다.
	# (`reopened` 는 `fresh` 를 쥐고 있으므로 `data` 는 따로 되돌려야 한다.)
	reopened.options.set_index("o11", saved_index)
	reopened.apply_language()
	data.set_language(String(data.languages()[saved_index]))
	_ok("⑤ 검사 전 상태로 원복", reopened.options.index_of("o11") == saved_index
		and data.language == String(data.languages()[saved_index])
		and fresh.language == String(fresh.languages()[saved_index]),
		"index=%d data=%s fresh=%s" % [reopened.options.index_of("o11"), data.language, fresh.language])
