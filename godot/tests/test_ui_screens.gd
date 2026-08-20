# UISCR — 화면 단독 인스턴스화 검사 (실화면을 실제로 세워 결속 계약을 본다).
#
# **왜 필요한가.** 화면 층 결함 중에는 데이터·코어 검사가 원리적으로 닿지 못하는 계열이 있다.
# 이번 축은 **문맥 결손**이다: 화면이 `session.outgame` 같은 "있을 때도 없을 때도 있는" 것을
# 무가드로 읽으면, 커리어를 연 경로에서는 멀쩡하고 **타이틀 직행 경로에서만** 죽는다.
# 실제로 SYS-04 가 그렇게 샜다(총괄 판정 IMPL-176 ① — 타이틀 첫 진입 100% 재현).
#
# 검사 축 17종:
#   ① 무커리어 문맥 성립 — SYS-01 → SYS-04 직행(D09 본문 145행·§A-1 규격 진입)
#   ② 패드 순회 폐쇄 — 초기 포커스 보유 (D09 §1.3 · 총괄 판정 IMPL-176 ②)
#   ③ 단독 경로 옵션 정합 — 라우터를 안 거치는 경로가 O9 를 적용하는가 (동 ③)
#   ④ 미구성 상태 차단 — 값 창구를 안 거친 폰트 크기가 렌더될 여지가 없는가 (동 ④)
#   ⑤ 입력맵 계약 — D09 §1.3 매핑표의 액션·기본 바인딩이 실재하는가 (IMPL-184 ①)
#   ⑥ 액션 경유 청취 — 같은 조작이 키보드·패드·액션 3경로에서 같은 결과인가 (IMPL-190 ①②)
#   ⑦ 표시 기구 — 툴팁 고정·감광 등채널 (동 ③④)
#   ⑧ 컨텍스트 층 패드 — X 단독/X 홀드 판별·Y 재배치 (D09 v1.3 · IMPL-200 ③)
#   ⑨ 검사 설정 정합 — PAL 조달 소스 경로가 실재하는가 (동 ①)
#   ⑩ 필러 대상 로그 문면 — 발행 층이 표기 매개를 짝으로 넘기는가 (IMPL-209 ⑧)
#   ⑪ 저장 표시 — 라우터 결선·값 창구·성공/실패 분기·전환 생존 (IMPL-219 ②)
#   ⑫ 코드 생성 Control 배치 — `set_anchors_preset` 순서 함정 전수 (IMPL-229 ⑥)
#   ⑬ ANCH·STRF 검사 실재 — 검사가 조용히 사라지지 않는가 (IMPL-233 ② · IMPL-249 ③)
#   ⑭ VN 라인 단위 화자 — 큐음이 화자를 따라가는가 (IMPL-249 ②)
#   ⑮ 도상 치수 2규격 공존 — 릴 32 무배율 ↔ 섹터 속성 16 (IMPL-226)
#   ⑯ 튜토리얼 콜아웃 배치 — 지목 요소·상시 표시 스트립 양쪽 불침범 (IMPL-258)
#   ⑰ VN 선택 지점 — 노드 부재 생략 ↔ 실재 발동·합류·스킵 생존 (IMPL-257)
#
# **첫 프레임(`_process`)에서 돈다.** `_init()` 시점에는 `root` 가 없어 `add_child` 자체가
# 불가능하고, `_initialize()` 시점에는 `root` 가 있어도 **아직 트리 안이 아니다** — 그래서
# 화면이 `grab_focus()` 를 부르면 `!is_inside_tree()` 로 튕긴다(실측). 라우터가 화면을 세우는
# 실제 문맥은 "트리에 이미 들어와 있는 노드가 자식을 붙이는" 상황이므로, 첫 프레임이
# 그 문맥의 재현이다.
extends SceneTree

const ACHIEVEMENT_SCENE := "res://ui/sys/achievement_screen.tscn"
const OPTIONS_SCENE := "res://ui/sys/options_screen.tscn"
const RACE_SCENE := "res://ui/race/race_screen.tscn"
const APP_ROOT_SCENE := "res://ui/flow/app_root.tscn"
# 패드 버튼 인덱스 — 엔진 실측분(IMPL-186). 검사도 화면과 같은 상수를 짐작하지 않는다.
const PAD_A_INDEX := 0
const PAD_X_INDEX := 2
const PAD_Y_INDEX := 3
const PAD_LB_INDEX := 9
const PAD_DPAD_LEFT_INDEX := 13
const PAD_DPAD_RIGHT_INDEX := 14
const LOG_FEED_SCRIPT := "res://ui/race/log_feed.gd"

var _checked := 0
var _failures := 0


# **컨테이너 정렬은 다음 프레임에 선다.** 배치 축(⑫)은 부모의 실 크기를 재는 검사이므로
# 첫 프레임에 재면 부모도 자식도 0 이라 "여백 0 = 부모를 채운다"가 **0 == 0 으로 성립**한다
# (돌연변이 M6 미검출로 드러난 공회전). 그래서 그 축만 정렬이 끝난 프레임으로 미룬다.
const LAYOUT_SETTLE_FRAMES := 4

var _frame := 0
var _settle_probe: Control
var _settle_race: Control


func _process(_delta: float) -> bool:
	_frame += 1
	var data := GameData.new()
	if not data.load_all():
		print("UI_SCREENS_FAIL data load")
		quit(1)
		return true
	if _frame < LAYOUT_SETTLE_FRAMES:
		if _frame == 1:
			_settle_probe = _mount(ACHIEVEMENT_SCENE, _fresh_session(data))
			# 튜토리얼 콜아웃 축(⑯)도 정렬이 끝난 부모를 요구한다 — 예약 영역(Zone A)의
			# 실 rect 를 읽어 배치하므로, 스트립이 0 크기면 "불침범"이 0==0 으로 성립한다.
			_settle_race = _mount(RACE_SCENE, _fresh_session(data))
		return false
	_achievement_without_career(data)
	_achievement_with_career(data)
	_achievement_icons(data)
	_log_feed_speaker_marks(data)
	_reel_cursor(data)
	_initial_focus(data)
	_standalone_boot_applies_o9()
	_log_feed_requires_configure()
	_input_map_contract()
	_race_input_via_actions()
	_tab_cycle_actions(data)
	_detail_info_pin(data)
	_hold_dim_is_neutral()
	_race_pad_context()
	_race_detail_relocation(data)
	_palette_sources_exist()
	_filler_log_substitution(data)
	_save_indicator_wiring(data)
	_anchor_preset_placement(data)
	_icon_size_regimes(data)
	_anch_check_present()
	_vn_line_speakers(data)
	_vn_choice_point(data)
	_tutorial_callout_placement()
	print("")
	# 검사 수 하한 — 씬 로드 실패로 스위트가 쪼그라들면 "통과"가 아니다.
	if _checked < 218:
		print("UI_SCREENS_FAIL checks=%d < 하한 218 (스위트 축소·씬 로드 실패 의심)" % _checked)
		quit(1)
		return true
	if _failures == 0:
		print("UI_SCREENS_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("UI_SCREENS_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)
	return true


func _fresh_session(data: GameData) -> RunSession:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	return session


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


# 씬을 세워 세션을 물린다. 라우터가 하는 순서 그대로다 —
# `session` 주입 → `add_child`(여기서 `_ready()`) → `bind()`.
func _mount(scene_path: String, session: RunSession) -> Control:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_ok("씬 로드: %s" % scene_path, false)
		return null
	var screen := packed.instantiate() as Control
	screen.session = session
	root.add_child(screen)
	screen.bind(session, {})
	return screen


func _unmount(screen: Control) -> void:
	if screen == null:
		return
	root.remove_child(screen)
	screen.queue_free()


# 표시된 업적 행 수 — 탭 패널을 전부 훑는다. 탭 하나가 통째로 비어도 잡히게 합계로 센다.
func _row_count(screen: Control) -> int:
	var total := 0
	var body := screen.get_node("%TabBody") as Control
	for scroll in body.get_children():
		for panel in scroll.get_children():
			total += panel.get_child_count()
	return total


# ── ① 무커리어 문맥 (SYS-01 → SYS-04 직행) ──
# `setup()` 만 하고 `begin_career()` 를 부르지 않는다 = 타이틀 화면의 세션 상태 그대로.
func _achievement_without_career(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	_ok("전제: 무커리어 세션은 outgame 을 갖지 않는다", session.outgame == null)
	var screen := _mount(ACHIEVEMENT_SCENE, session)
	if screen == null:
		return
	# 널 역참조가 나면 `_on_bound()` 가 중간에 끊긴다 — 아래 세 축이 그 중단을 잡는다.
	# (요약 문면은 `_build_tabs()` 앞이고 행 생성은 뒤라, 어디서 끊겼는지도 갈린다.)
	_ok("헤더 문면 세팅", not (screen.get_node("%HeaderLabel") as Label).text.is_empty())
	_ok("요약 문면 세팅", not (screen.get_node("%SummaryLabel") as Label).text.is_empty(),
		(screen.get_node("%SummaryLabel") as Label).text)
	_ok("탭 5개 생성", (screen.get_node("%TabRow") as Control).get_child_count() == 5,
		"actual=%d" % (screen.get_node("%TabRow") as Control).get_child_count())
	# **행 전수 생성** — 무커리어라고 목록이 줄면 안 된다. 총수 가늠 허용이 §5.5 명문이다.
	_ok("업적 행 전수 생성", _row_count(screen) == data.achievements.size(),
		"actual=%d expected=%d" % [_row_count(screen), data.achievements.size()])
	# [가안] 무커리어 = 달성 0. 요약 문면에 달성 수가 들어가므로 0 이 실제로 실렸는지 본다.
	_ok("무커리어 달성 표시 0",
		(screen.get_node("%SummaryLabel") as Label).text.contains("0"),
		(screen.get_node("%SummaryLabel") as Label).text)
	_unmount(screen)


# ── 커리어 적재 후 거동 무변경 ──
# 가드를 넣느라 정상 경로가 상해 있으면 여기서 갈린다 (달성분이 사라지는 반대 결함).
func _achievement_with_career(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	var first_id := String(data.achievements.keys()[0])
	session.outgame.achievements[first_id] = 1
	var screen := _mount(ACHIEVEMENT_SCENE, session)
	if screen == null:
		return
	_ok("커리어 적재 시에도 행 전수 생성", _row_count(screen) == data.achievements.size(),
		"actual=%d expected=%d" % [_row_count(screen), data.achievements.size()])
	# 달성 1건이 요약에 반영되는가 — 무커리어(0)와 **다른 문면**이어야 한다.
	var summary := (screen.get_node("%SummaryLabel") as Label).text
	_ok("커리어 달성분이 요약에 반영", summary.contains("1"), summary)
	_unmount(screen)


# ── ②-1 아이콘 결선 (IMPL-207) ──
#
# **텍스처가 실제로 실렸는지만 증거로 인정한다.** 상수 표(`ICON_BY_CATEGORY`)가 있다는
# 것도, `_build_icon()` 을 직접 부르는 것도 결선의 증거가 아니다 — 행 생성 경로가 그 함수를
# 지나지 않으면 표는 그대로 남고 화면만 빈다(돌연변이 3건 미검출 전례).
# 그래서 **실배치된 행 노드를 훑어** 도상 파일까지 대조한다.
func _achievement_icons(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	var screen := _mount(ACHIEVEMENT_SCENE, session)
	if screen == null:
		return
	var body := screen.get_node("%TabBody") as Control
	var missing := 0
	var wrong_category := 0
	var hidden_rows := 0
	var hidden_wrong := 0
	var visible_rows := 0
	var tab_index := 0
	for scroll in body.get_children():
		var category := String(AchievementScreen.TABS[tab_index]["category"])
		var expected := String(AchievementScreen.ICON_BY_CATEGORY[category])
		tab_index += 1
		for panel in scroll.get_children():
			for row in panel.get_children():
				var icon := row.get_node_or_null("Icon") as TextureRect
				if icon == null or icon.texture == null:
					missing += 1
					continue
				var path := (icon.texture as Texture2D).resource_path.get_file().get_basename()
				# 히든 미달성 행은 "Masked" 라벨을 갖는다 — 그것으로 두 갈래를 가른다.
				if row.get_node_or_null("Masked") != null:
					hidden_rows += 1
					if path != AchievementScreen.ICON_HIDDEN:
						hidden_wrong += 1
					continue
				visible_rows += 1
				if path != expected:
					wrong_category += 1
	_ok("전 행에 도상이 실렸다", missing == 0, "missing=%d" % missing)
	_ok("공개 행 도상 = 소속 카테고리", wrong_category == 0, "wrong=%d" % wrong_category)
	_ok("공개 행이 존재한다", visible_rows > 0, "visible=%d" % visible_rows)
	# 히든 9종(발견형 4 + 관계 도달형 5 — 전건 rival) 은 공용 도상을 진다.
	_ok("히든 미달성 행 검출", hidden_rows == 9, "hidden=%d" % hidden_rows)
	_ok("히든 행 도상 = 공용 히든", hidden_wrong == 0, "wrong=%d" % hidden_wrong)
	# 카테고리 도상이 히든 행으로 새면 탭 위치와 합쳐 정체가 좁혀진다(§5.5 은닉 취지).
	_ok("히든 행에 카테고리 도상 누출 0", hidden_rows + visible_rows == data.achievements.size(),
		"rows=%d expected=%d" % [hidden_rows + visible_rows, data.achievements.size()])
	_unmount(screen)


# ── ②-1 화자 도상 결선 (IMPL-207) ──
#
# 로그 피드는 화자별로 도상/텍스트가 갈린다. **도상이 있는 화자는 TextureRect, 없는 화자는
# Label** 이어야 하고 둘의 표지 폭이 같아야 한다(폭이 갈리면 본문 시작 x 가 어긋난다).
func _log_feed_speaker_marks(data: GameData) -> void:
	var feed := LogFeed.new()
	feed.configure(4, data.param_int("param_font_size_body"))
	feed.push_line("MARK", "body", LogFeed.Speaker.RELAY)
	feed.push_line("MARK", "body", LogFeed.Speaker.CREW)
	feed.push_line("MARK", "body")
	var relay_mark := feed.get_child(0).get_node("Mark")
	var crew_mark := feed.get_child(1).get_node("Mark")
	var none_mark := feed.get_child(2).get_node("Mark")
	_ok("중계 화자 = 도상", relay_mark is TextureRect, relay_mark.get_class())
	_ok("중계 도상 실적재",
		relay_mark is TextureRect and (relay_mark as TextureRect).texture != null)
	# 크루는 D09 §3.3 이 '미니 초상'으로 규정한 축이라 아이콘 27종에 없다 — 텍스트로 되돌아간다.
	_ok("도상 없는 화자 = 텍스트 되돌림", crew_mark is Label, crew_mark.get_class())
	_ok("화자 미지정도 텍스트 되돌림", none_mark is Label, none_mark.get_class())
	_ok("표지 폭 = 도상·텍스트 공통",
		(relay_mark as Control).custom_minimum_size.x
			== (crew_mark as Control).custom_minimum_size.x)
	feed.free()


# ── ②-2 릴 선택 커서 (IMPL-207) ──
#
# **실물 패드가 없는 환경에서도 조합 판독을 검증한다** — `InputEventJoypadButton` 을 실제로
# 만들어 화면의 조합 판독기에 넣는다. 액션 시뮬레이션(`InputEventAction`)으로는 이 경로가
# 열리지 않는다(판독기가 이벤트 **형**을 본다) — 그래서 형까지 같은 이벤트를 쓴다.
# OS→엔진 전달 구간만 검사 밖이고, 그 위 전부가 여기 든다.
func _reel_cursor(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	var screen := _mount(RACE_SCENE, session)
	if screen == null:
		return
	var frames := (screen.get_node("%E05Reels") as Control).get_children()
	var borders := func() -> Array:
		var out: Array = []
		for column in frames:
			var style := (column.get_node("Frame") as Control).get_theme_stylebox("panel")
			out.append((style as StyleBoxFlat).border_color)
		return out
	# 커서 이전 = 전 프레임이 중립 크롬선
	var neutral: Array = borders.call()
	var all_neutral := neutral.all(func(c): return c == UiPalette.FRAME_LINE)
	_ok("커서 전: 전 프레임 = FRAME_LINE", all_neutral, str(neutral))

	# 커서는 **개입 창(T4)이 열려 있는 동안**만 뜬다 — 홀드 토글이 가능한 국면이 그것뿐이다.
	# 창은 스핀 → 정지 연출 완료 후에 열리고 그 완료는 프레임 진행에 달려 있으므로,
	# 헤드리스에서는 국면만 세우고 **조합 판독 → 표시**의 결선을 본다.
	# (창을 여는 경로 자체는 봉인 검사가 프레임을 돌려 가며 따로 검증한다.)
	_ok("전제: 마운트 직후엔 개입 창이 닫혀 있다", not screen._timer_active)
	screen._timer_active = true
	_feed_pad(screen, _pad_event(2, true))     # PAD_X press
	var lit: Array = borders.call()
	_ok("X 홀드 중: 선택 릴만 ACCENT_ACTIVE",
		lit[0] == UiPalette.ACCENT_ACTIVE and lit[1] == UiPalette.FRAME_LINE
			and lit[2] == UiPalette.FRAME_LINE, str(lit))

	# D패드 오른쪽 → 커서 이동. 강조가 따라와야 한다(상태만 바뀌고 표시가 안 따라오면 실사용 불가).
	_feed_pad(screen, _pad_event(14, true))    # PAD_DPAD_RIGHT press
	var moved: Array = borders.call()
	_ok("D패드 우 → 강조가 릴 2 로 이동",
		moved[1] == UiPalette.ACCENT_ACTIVE and moved[0] == UiPalette.FRAME_LINE, str(moved))

	# 경계 감김 [가안] — 릴 3 에서 한 번 더 누르면 릴 1 로 돌아온다.
	_feed_pad(screen, _pad_event(14, true))
	_feed_pad(screen, _pad_event(14, true))
	var wrapped: Array = borders.call()
	_ok("경계 감김: 릴 1 로 복귀", wrapped[0] == UiPalette.ACCENT_ACTIVE, str(wrapped))

	# X 뗌 → 소등. 커서가 남으면 키보드 사용자에게 뜻 없는 영구 강조가 된다.
	_feed_pad(screen, _pad_event(2, false))
	var off: Array = borders.call()
	_ok("X 뗌: 전 프레임 = FRAME_LINE",
		off.all(func(c): return c == UiPalette.FRAME_LINE), str(off))

	# **봉인(불변규칙 5):** 릴 정지 연출 중에는 커서가 뜨지 않는다.
	_feed_pad(screen, _pad_event(2, true))
	screen._revealing = true
	screen._refresh_reel_frames()
	var sealed: Array = borders.call()
	_ok("정지 연출 중 커서 소등 (봉인)",
		sealed.all(func(c): return c == UiPalette.FRAME_LINE), str(sealed))
	_unmount(screen)


# ── ② 초기 포커스 (D09 §1.3 패드 순회 폐쇄) ──
# 포커스를 가진 노드가 없으면 패드로는 아무것도 고를 수 없다 — 화면이 잠긴다.
func _initial_focus(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	for entry in [["SYS-04 업적", ACHIEVEMENT_SCENE], ["SYS-03 옵션", OPTIONS_SCENE]]:
		var screen := _mount(String(entry[1]), session)
		if screen == null:
			continue
		var focused := root.gui_get_focus_owner()
		_ok("%s — 초기 포커스 보유" % String(entry[0]), focused != null)
		_ok("%s — 포커스가 화면 안에 있다" % String(entry[0]),
			focused != null and screen.is_ancestor_of(focused),
			str(focused))
		_unmount(screen)


# ── ③ 단독 인스턴스화 경로도 O9 를 적용하는가 (총괄 판정 IMPL-176 ③) ──
#
# `race_screen` 은 세션이 없으면 **스스로 세션을 세우는 단독 경로**(`_boot()`)를 갖는다
# (디버그 씬·캡처 하네스가 그 경로로 뜬다). 팔레트는 정적 클래스라 옵션을 밀어 넣는 구조인데
# 그 밀어 넣기가 `FlowScreen.bind()` 에만 있으면, 단독 경로에서만 화면이 옛 색으로 뜬다.
# UIOPT 는 `bind()` 경로만 보므로 이 축은 원리적으로 그쪽 사각이다.
func _standalone_boot_applies_o9() -> void:
	var packed := load(RACE_SCENE) as PackedScene
	_ok("레이스 씬 로드", packed != null)
	if packed == null:
		return
	var screen := packed.instantiate() as Control
	# **세션을 주지 않는다** = 단독 경로. 반대 상태에서 출발해야 `_boot()` 이 덮는지 갈린다.
	UiPalette.colorblind = true
	root.add_child(screen)
	_ok("단독 경로가 세션을 세운다", screen.session != null)
	var expects_alt: bool = screen.session != null \
		and screen.session.options.index_of("o9") == 1
	_ok("단독 경로가 O9 를 팔레트에 적용한다", UiPalette.colorblind == expects_alt,
		"palette=%s session_o9=%s" % [str(UiPalette.colorblind), str(expects_alt)])
	UiPalette.colorblind = false
	_unmount(screen)


# ── ④ 미구성 상태가 유효한 폰트 크기를 갖지 않는가 (총괄 판정 IMPL-176 ④) ──
#
# `configure()` 미호출 경로가 생기면 D13 창구 밖의 수치가 **조용히 실렌더된다** — 화면은 뜨고
# 글자만 미묘하게 다르므로 눈으로는 잡히지 않고, FONT-B 도 못 잡는다(리터럴이 오버라이드
# 인자가 아니라 멤버 초기값이라 정적 검사의 사정거리 밖이다). 그래서 검사를 여기 둔다.
func _log_feed_requires_configure() -> void:
	var feed := load(LOG_FEED_SCRIPT).new() as VBoxContainer
	_ok("미구성 폰트 크기 = 센티넬 (리터럴 기본값 부재)",
		feed._font_size == feed.UNCONFIGURED, "actual=%d" % feed._font_size)
	# 센티넬이 실제 폰트 크기 범위 밖인지도 본다 — 8 같은 값이 센티넬로 둔갑하면 무의미하다.
	_ok("센티넬은 렌더 가능한 크기가 아니다", feed.UNCONFIGURED <= 0,
		"sentinel=%d" % feed.UNCONFIGURED)
	feed.configure(4, 9)
	_ok("구성 후에는 D13 값을 보유", feed._font_size == 9, "actual=%d" % feed._font_size)
	feed.free()


# ── ⑤ 입력맵 계약 (D09 §1.3 공통 층 매핑표 · 총괄 판정 IMPL-184 ①) ──
#
# **액션의 존재와 기본 바인딩은 리매핑 탭(§6.4)의 전제 골격이다** — 재바인딩 UI 는 액션이
# 이미 있을 때만 성립한다. 그래서 "나중에 기본값이 바뀌어도 액션 자체는 있다"를 계약으로 고정한다.
#
# 패드 바인딩은 **버튼 인덱스로 단언한다**(as_text 는 표기 문구라 엔진 판올림에 흔들린다).
# 인덱스는 엔진에서 실측한 값이다 — A=0 · B=1 · Y=3 · Start=6 · LB=9 · RB=10 · D패드 11~14.
const INPUT_CONTRACT := {
	"ui_accept": 0,     # 확인 / 선택 = A
	"ui_cancel": 1,     # 취소 / 뒤로 = B
	"tab_prev": 9,      # 탭 전환 = LB
	"tab_next": 10,     # 탭 전환 = RB
	"pause_menu": 6,    # 일시정지 메뉴 = Start
	"detail_info": 3,   # 상세 정보 = Y
}
# 포커스 이동 — D패드. 좌스틱 축은 별도로 본다(버튼이 아니라 모션 이벤트다).
const FOCUS_CONTRACT := {"ui_up": 11, "ui_down": 12, "ui_left": 13, "ui_right": 14}


func _input_map_contract() -> void:
	for action in INPUT_CONTRACT:
		_assert_pad_button(String(action), int(INPUT_CONTRACT[action]))
	for action in FOCUS_CONTRACT:
		_assert_pad_button(String(action), int(FOCUS_CONTRACT[action]))
		_assert_stick_axis(String(action))
	# **키보드 열이 살아 있는가.** `[input]` 에 액션을 적으면 엔진 기본 이벤트를 대체하므로,
	# 패드만 적고 키보드를 빠뜨리면 조용히 키보드 조작이 죽는다 — 실제 위험이라 축을 둔다.
	for action in ["ui_accept", "ui_cancel", "tab_prev", "tab_next", "pause_menu", "detail_info"]:
		var has_key := false
		for event in InputMap.action_get_events(String(action)):
			if event is InputEventKey:
				has_key = true
		_ok("%s — 키보드 바인딩 보존" % String(action), has_key)


func _assert_pad_button(action: String, button_index: int) -> void:
	if not InputMap.has_action(action):
		_ok("액션 실재: %s" % action, false)
		return
	var found := false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == button_index:
			found = true
	_ok("%s — 패드 버튼 %d 바인딩" % [action, button_index], found)


func _assert_stick_axis(action: String) -> void:
	var found := false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			found = true
	_ok("%s — 좌스틱 축 바인딩" % action, found)


# 액션 이벤트 1건을 만들어 준다. `InputEventAction` 은 `is_action_pressed()` 에 그대로 걸리므로
# 키맵·뷰포트 배관을 타지 않고 **청취 층만** 검사할 수 있다.
func _action_event(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


# 뗌 이벤트도 필요하다 — 커서 소등·X 단독 리스핀은 **릴리스 시점 판정**이라
# 누름만으로는 그 절반이 검사 밖에 남는다 (IMPL-207).
func _pad_event(button_index: int, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = pressed
	return event


# ── ⑥ RACE-01 액션 경유 전환 (총괄 판정 IMPL-190 ①) ──
#
# 원시 키코드 직독은 `InputEventKey` 만 보므로 **패드가 아예 도달하지 못한다**.
# 세 입력(키보드·패드·액션)이 같은 결과를 내는지를 본다 — 키보드 거동 보존이 전환의 계약이다.
func _race_input_via_actions() -> void:
	for entry in [["액션", "ui_accept"], ["키보드 Space", ""], ["패드 A", ""]]:
		var packed := load(RACE_SCENE) as PackedScene
		if packed == null:
			_ok("레이스 씬 로드", false)
			return
		var screen := packed.instantiate() as Control
		root.add_child(screen)
		var label := String(entry[0])
		var before: int = screen.engine.turn_phase
		_ok("%s — 전제: T1 대기" % label, before == RaceTypes.TurnPhase.T1_SECTOR_OPEN,
			"phase=%d" % before)
		var event: InputEvent
		match label:
			"액션": event = _action_event("ui_accept")
			"키보드 Space": event = _key_event(KEY_SPACE)
			_: event = _pad_event(0)
		screen._unhandled_input(event)
		# 스핀 커밋 = 봉인 개시. 국면이 T1 을 벗어났는지로 본다 (결과는 보지 않는다 — 불변규칙 5).
		_ok("%s — 스핀 커밋 도달" % label,
			screen.engine.turn_phase != RaceTypes.TurnPhase.T1_SECTOR_OPEN,
			"phase=%d" % screen.engine.turn_phase)
		_unmount(screen)
	# 일시정지도 같은 축 — 액션·키보드·패드 3경로
	for entry2 in [["액션", "pause_menu"], ["키보드 Esc", ""], ["패드 Start", ""]]:
		var packed2 := load(RACE_SCENE) as PackedScene
		var screen2 := packed2.instantiate() as Control
		root.add_child(screen2)
		var label2 := String(entry2[0])
		_ok("%s — 전제: 정지 아님" % label2, not screen2._paused)
		var event2: InputEvent
		match label2:
			"액션": event2 = _action_event("pause_menu")
			"키보드 Esc": event2 = _key_event(KEY_ESCAPE)
			_: event2 = _pad_event(6)
		screen2._unhandled_input(event2)
		_ok("%s — 일시정지 열림" % label2, screen2._paused)
		_unmount(screen2)


# ── ⑦ 탭 순회 액션 (총괄 판정 IMPL-190 ②) ──
func _tab_cycle_actions(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	for entry in [["SYS-03 옵션", OPTIONS_SCENE, 5], ["SYS-04 업적", ACHIEVEMENT_SCENE, 5]]:
		var screen := _mount(String(entry[1]), session)
		if screen == null:
			continue
		var label := String(entry[0])
		_ok("%s — 전제: 탭 %d개·첫 탭 활성" % [label, int(entry[2])],
			screen._tab_panels.size() == int(entry[2]) and screen._active_tab == 0,
			"tabs=%d active=%d" % [screen._tab_panels.size(), screen._active_tab])
		screen._unhandled_input(_action_event("tab_next"))
		_ok("%s — tab_next 로 다음 탭" % label, screen._active_tab == 1,
			"active=%d" % screen._active_tab)
		_ok("%s — 패널 가시성이 따라온다" % label,
			(screen._tab_panels[1] as Control).visible
				and not (screen._tab_panels[0] as Control).visible)
		screen._unhandled_input(_action_event("tab_prev"))
		_ok("%s — tab_prev 로 되돌아온다" % label, screen._active_tab == 0)
		# [가안] 경계 감김 — 첫 탭에서 prev 는 마지막으로
		screen._unhandled_input(_action_event("tab_prev"))
		_ok("%s — 경계에서 감긴다(wrap)" % label,
			screen._active_tab == int(entry[2]) - 1, "active=%d" % screen._active_tab)
		_unmount(screen)


# ── ⑧ 상세 정보 고정 (총괄 판정 IMPL-190 ③) ──
func _detail_info_pin(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	var screen := _mount(ACHIEVEMENT_SCENE, session)
	if screen == null:
		return
	var focused := root.gui_get_focus_owner()
	_ok("전제: 포커스 대상 존재", focused != null)
	if focused == null:
		_unmount(screen)
		return
	# 툴팁이 비어 있으면 아무것도 띄우지 않는다 — 빈 상자 금지
	focused.tooltip_text = ""
	screen._shortcut_input(_action_event("detail_info"))
	_ok("툴팁 없음 → 미표출", screen.detail_text().is_empty(), screen.detail_text())
	focused.tooltip_text = "detail probe"
	screen._shortcut_input(_action_event("detail_info"))
	_ok("툴팁 고정 표출", screen.detail_text() == "detail probe", screen.detail_text())
	# 코드 생성 Control 이므로 폰트 창구를 거쳐야 한다 (FONT · 불변규칙 2)
	var pinned := screen.get_node("%s/DetailText" % FlowScreen.DETAIL_PANEL_NAME) as Label
	_ok("고정 라벨이 D13 폰트 크기 보유",
		pinned.get_theme_font_size("font_size") == data.param_int("param_font_size_body"),
		"actual=%d" % pinned.get_theme_font_size("font_size"))
	# 같은 액션 재입력 = 해제
	screen._shortcut_input(_action_event("detail_info"))
	_ok("재입력으로 해제", screen.detail_text().is_empty())
	_unmount(screen)


# ── ⑨ 홀드 감광 등채널 (총괄 판정 IMPL-190 ④) ──
# 감광은 상태 표시이지 색 정보가 아니다 — 채널이 갈리면 비홀드 릴에 색상 편이가 생기고,
# 그것은 심볼 판독(색+도상 이중 부호화)에 잡음이 된다.
func _hold_dim_is_neutral() -> void:
	var packed := load(RACE_SCENE) as PackedScene
	if packed == null:
		_ok("레이스 씬 로드", false)
		return
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	var dim: Color = (screen._reel_panels[0] as Control).modulate
	_ok("전제: 비홀드 릴은 감광 상태", dim.r < 1.0, str(dim))
	_ok("감광이 등채널 (색상 편이 0)",
		is_equal_approx(dim.r, dim.g) and is_equal_approx(dim.g, dim.b), str(dim))
	_unmount(screen)


func _pad_release(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = false
	return event


# 패드 입력 1건을 화면에 흘린다. **`_input` 먼저** — 모디파이어 장부가 그 층에서 갱신되므로
# 실제 엔진 순서(`_input` → `_shortcut_input` → `_unhandled_input`)를 그대로 재현해야
# 조합 판정이 실기와 같은 조건에서 검사된다.
func _feed_pad(screen: Control, event: InputEventJoypadButton) -> void:
	screen._input(event)
	screen._shortcut_input(event)
	screen._unhandled_input(event)


func _new_race_screen() -> Control:
	var packed := load(RACE_SCENE) as PackedScene
	if packed == null:
		_ok("레이스 씬 로드", false)
		return null
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	return screen


# ── ⑩ 레이스 컨텍스트 층 패드 (D09 v1.3 §1.3 · 총괄 판정 IMPL-200 ③) ──
#
# 핵심 축은 **X 단독 대 X 홀드의 판별**이다 — 같은 버튼이 두 조작을 겸하므로, 한쪽이 다른
# 쪽을 삼키면 리스핀이 안 되거나 홀드를 만질 때마다 리스핀이 딸려 나온다.
#
# **관측 지점 = 사운드 발화 기록.** 검사 대상은 리스핀 *규칙*이 아니라 **입력 배선**이므로,
# "리스핀 경로에 도달했는가"만 보면 된다. `_on_respin()` 은 성사(SE-I04)든 거절(SE-I14)이든
# 반드시 한 번 울리므로 그 발화가 도달의 증거다. 개입 창은 프레임을 돌아야 열리므로
# 게이트만 열어 두고 본다(턴 상태를 흉내 내지 않는다 — 규칙은 코어 검사 몫이다).
const RESPIN_SFX := ["SE-I04", "SE-I14"]
# 차지 개입도 같은 성격 — 성사(SE-I09)든 거절(SE-I14)이든 도달하면 한 번 울린다.
const CHARGE_SFX := ["SE-I09", "SE-I14"]


func _respin_sfx_count(screen: Control) -> int:
	var total := 0
	for sfx_id in screen.session.audio.fired:
		if RESPIN_SFX.has(String(sfx_id)):
			total += 1
	return total


func _charge_sfx_count(screen: Control) -> int:
	var total := 0
	for sfx_id in screen.session.audio.fired:
		if CHARGE_SFX.has(String(sfx_id)):
			total += 1
	return total


func _race_pad_context() -> void:
	# ⓐ X 단독(뗌) = 리스핀 — 누름만으로는 발화하지 않는다
	var screen := _new_race_screen()
	if screen == null:
		return
	screen._timer_active = true   # 개입 창 게이트만 연다 (프레임 없이 열리지 않는다)
	var before: int = _respin_sfx_count(screen)
	_feed_pad(screen, _pad_event(PAD_X_INDEX))
	_ok("X 누름만으로는 리스핀하지 않는다 (모디파이어일 수 있다)",
		_respin_sfx_count(screen) == before, "fired=%d" % _respin_sfx_count(screen))
	_feed_pad(screen, _pad_release(PAD_X_INDEX))
	_ok("X 단독(뗌) = 리스핀 경로 도달",
		_respin_sfx_count(screen) == before + 1, "fired=%d" % _respin_sfx_count(screen))
	_unmount(screen)

	# ⓑ X 홀드 + A = 홀드 토글 · 그 X 는 뗄 때 리스핀하지 않는다
	var screen2 := _new_race_screen()
	screen2._timer_active = true
	var before2: int = _respin_sfx_count(screen2)
	var held_before: bool = screen2._hold_boxes[0].button_pressed
	_feed_pad(screen2, _pad_event(PAD_X_INDEX))
	_feed_pad(screen2, _pad_event(PAD_A_INDEX))
	_ok("X 홀드 + A = 릴 홀드 토글",
		screen2._hold_boxes[0].button_pressed != held_before,
		"before=%s after=%s" % [str(held_before), str(screen2._hold_boxes[0].button_pressed)])
	_ok("X 홀드 중 A 는 스핀·리스핀으로 새지 않는다",
		_respin_sfx_count(screen2) == before2)
	_feed_pad(screen2, _pad_release(PAD_X_INDEX))
	_ok("조합으로 쓰인 X 는 뗄 때 리스핀하지 않는다",
		_respin_sfx_count(screen2) == before2, "fired=%d" % _respin_sfx_count(screen2))
	_unmount(screen2)

	# ⓒ X 홀드 + D패드 = 릴 커서 이동
	var screen3 := _new_race_screen()
	_ok("전제: 릴 커서 0", screen3._hold_cursor == 0)
	_feed_pad(screen3, _pad_event(PAD_X_INDEX))
	_feed_pad(screen3, _pad_event(PAD_DPAD_RIGHT_INDEX))
	_ok("X 홀드 + D패드 우 = 커서 이동", screen3._hold_cursor == 1,
		"cursor=%d" % screen3._hold_cursor)
	_feed_pad(screen3, _pad_event(PAD_DPAD_LEFT_INDEX))
	_ok("X 홀드 + D패드 좌 = 되돌아온다", screen3._hold_cursor == 0)
	_unmount(screen3)


# ── ⑪ Y 단독 대 LB 홀드 + Y (v1.3 재배치 행) ──
func _race_detail_relocation(data: GameData) -> void:
	# Y 단독 = 차지 개입 (공통 층 상세 정보를 컨텍스트 층이 가린다).
	# **툴팁 있는 대상에 포커스를 준 상태로 누른다** — 그래야 "상세 정보로 새면 상자가 뜬다"가
	# 성립해 이 축이 실제로 이빨을 갖는다. 포커스 없이 누르면 어느 쪽으로 새든 상자가 안 떠서
	# 검사가 조용히 통과한다(설계 함정 ③ 항진명제 — 실측으로 걸러낸 형태다).
	var screen := _new_race_screen()
	if screen == null:
		return
	screen._timer_active = true
	var bait := screen.get_node("%E08Respin") as Button
	bait.tooltip_text = "must not appear"
	bait.grab_focus()
	var charge_before: int = _charge_sfx_count(screen)
	_feed_pad(screen, _pad_event(PAD_Y_INDEX))
	_ok("Y 단독 → 상세 정보로 새지 않는다", screen.detail_text().is_empty(),
		screen.detail_text())
	_ok("Y 단독 = 차지 개입 경로 도달",
		_charge_sfx_count(screen) == charge_before + 1,
		"fired=%d" % _charge_sfx_count(screen))
	_unmount(screen)
	# LB 홀드 + Y = 상세 정보
	var screen2 := _new_race_screen()
	var target := screen2.get_node("%E08Respin") as Button
	target.tooltip_text = "race detail probe"
	target.grab_focus()
	_feed_pad(screen2, _pad_event(PAD_LB_INDEX))
	_feed_pad(screen2, _pad_event(PAD_Y_INDEX))
	_ok("LB 홀드 + Y = 상세 정보 고정", screen2.detail_text() == "race detail probe",
		screen2.detail_text())
	_unmount(screen2)
	# 키보드 T 는 공통 층 그대로 (거동 보존 계약)
	var screen3 := _new_race_screen()
	var target3 := screen3.get_node("%E08Respin") as Button
	target3.tooltip_text = "keyboard detail probe"
	target3.grab_focus()
	screen3._shortcut_input(_key_event(KEY_T))
	_ok("키보드 T = 상세 정보 보존", screen3.detail_text() == "keyboard detail probe",
		screen3.detail_text())
	_unmount(screen3)


# ── ⑫ PAL 조달 소스 적재 (총괄 판정 IMPL-200 ①) ──
# 소스가 죽으면 **무신호로 통과**한다 — 나머지 소스가 대장을 채워 주기 때문이다.
# 실제로 `master_56` → `master_60` 개명이 그 경로로 지나갔다. 설정의 경로가 실재하는지를
# 검사 층이 아니라 여기서도 본다(검사 자신이 죽었을 때 검사가 자기를 신고할 수는 없다).
func _palette_sources_exist() -> void:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://../tools/validators/config.json"))
	if typeof(config) != TYPE_DICTIONARY:
		_ok("검사 설정 적재", false)
		return
	var paths: Array = (config as Dictionary).get("palette_sources", [])
	_ok("조달 소스 선언 ≥ 1", not paths.is_empty())
	for path in paths:
		var text := FileAccess.get_file_as_string("res://../%s" % String(path))
		_ok("조달 소스 실재·비어 있지 않음: %s" % String(path), not text.is_empty())


# ── ⑬ 필러 대상 로그 문면 실치환 (총괄 판정 IMPL-209 ⑧) ──
#
# 필러의 `name_key` 는 이름이 아니라 **문면**(`No.{number} 머신`)이다. 표기 층이 그것을
# 번역할 때 `number` 를 **같은 params 에서** 찾으므로, 발행 층이 짝을 안 넘기면 화면에
# `No.{number} 머신 리타이어.` 가 그대로 뜬다(주력 실기 관측 · IMPL-210).
#
# **관측 지점 = 실제로 렌더된 로그 줄의 문자열.** 엔진이 넘긴 params 만 보면 표기 층이
# 치환을 건너뛰어도 통과한다(죽은 쪽 단언). 그래서 엔진이 발행한 이벤트를 실화면의
# `_push_events()` 에 흘려 넣고 `LogFeed` 슬롯의 본문 라벨을 읽는다.
#
# **네임드로는 이 결함이 드러나지 않는다** — 네임드 문면에는 `{number}` 자리가 아예 없다.
# 그래서 대상을 필러로 고정하고, 필러가 없으면 전제 단언으로 먼저 멈춘다(빈 통과 차단).
func _filler_log_substitution(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	var screen := _mount(RACE_SCENE, session)
	if screen == null:
		return
	var engine: RaceEngine = screen.engine
	var filler_id := ""
	for entrant_id in engine.entrants:
		if bool(engine.entrants[entrant_id]["is_filler"]):
			filler_id = String(entrant_id)
			break
	_ok("전제: 그리드에 필러가 있다", filler_id != "", filler_id)
	if filler_id == "":
		_unmount(screen)
		return
	var number := int(engine.entrants[filler_id]["number"])
	# 전제 2 — 필러 문면에 치환 자리가 실재해야 이 축이 성립한다.
	_ok("전제: 필러 name_key 에 {number} 자리가 있다",
		data.strings.text("ui.race.fillerName").contains("{number}"))

	# 듀얼 3분기 — 대상 매개를 싣는 문면 전부. 승패는 `judgment >= threshold` 이고
	# 레조넌스 보너스가 판정에 직접 가산되는 외부 레버라 그것으로 가른다
	# (릴 결과를 흉내 내지 않는다 — 규칙은 코어 검사 몫이다).
	var cases := [
		{"type": RaceTypes.DuelType.OVERTAKE, "win": true, "label": "추월 성공"},
		{"type": RaceTypes.DuelType.DEFENSE, "win": true, "label": "방어 성공"},
		{"type": RaceTypes.DuelType.DEFENSE, "win": false, "label": "방어 실패"},
	]
	for duel_case in cases:
		var events := _force_filler_duel(engine, filler_id, int(duel_case["type"]), bool(duel_case["win"]))
		_assert_filler_line(screen, events, String(duel_case["label"]), number)

	# AI 리타이어 — 주력이 실기에서 실제로 본 문면이 이 경로다.
	_assert_filler_line(screen, _force_filler_retire(engine, filler_id), "AI 리타이어", number)
	_unmount(screen)


# 듀얼 성립 조건(인접·미소멸)을 세우고 승패를 강제해 대상 문면을 뽑는다.
func _force_filler_duel(engine: RaceEngine, opponent_id: String, duel_type: int, win: bool) -> Array:
	engine.entrants[opponent_id]["retired"] = false
	engine.positions.erase(opponent_id)
	var player_index: int = engine.positions.find(RaceEngine.PLAYER_ID)
	engine.positions.insert(player_index + 1, opponent_id)
	engine.pending_duel = duel_type
	engine.duel_opponent = opponent_id
	engine.resonance_duel_bonus = 9999.0 if win else -9999.0
	return engine._resolve_duel()


# 리타이어는 확률 분기다. RNG 는 마스터 시드 파생이라 회차 간 재현되지만, 시행을 한정하고
# **못 뽑았으면 빈 배열로 돌려보낸다** — 안 뽑힌 것을 통과로 적지 않기 위해서다.
func _force_filler_retire(engine: RaceEngine, filler_id: String) -> Array:
	# 그리드를 플레이어 + 그 필러로 좁힌다 — 다른 필러가 먼저 뽑히면 같은 `name_key` 라
	# 문면만으로는 구분되지 않아 엉뚱한 카 넘버를 검사하게 된다(첫 시행 실측).
	for _attempt in range(4000):
		engine.ai_retire_count = 0
		engine.entrants[filler_id]["retired"] = false
		engine.positions = [RaceEngine.PLAYER_ID, filler_id]
		var events: Array = engine._ai_retire_check()
		if not events.is_empty():
			return events
	return []


# 발행 → 실화면 표기 → 렌더된 문자열까지 한 줄로 본다.
func _assert_filler_line(screen: Control, events: Array, label: String, number: int) -> void:
	var target_events: Array = []
	for event in events:
		if (event["params"] as Dictionary).has("target"):
			target_events.append(event)
	_ok("%s — 대상 문면 발행" % label, target_events.size() == 1,
		"발행 %d건" % target_events.size())
	if target_events.is_empty():
		return
	screen._e10_log.clear_feed()
	screen._push_events(target_events)
	var lines := _rendered_log_lines(screen)
	_ok("%s — 로그 줄 1개 렌더" % label, lines.size() == 1, "줄 %d개" % lines.size())
	if lines.is_empty():
		return
	var line := String(lines[0])
	_ok("%s — 필러 카 넘버 실치환" % label, line.contains("No.%d" % number), line)
	_ok("%s — 미치환 자리 잔존 0" % label, not line.contains("{"), line)


func _rendered_log_lines(screen: Control) -> Array:
	var lines: Array = []
	for slot in screen._e10_log.get_children():
		var body := slot.get_child(1) as Label
		if body != null:
			lines.append(body.text)
	return lines


# ── ⑪ 저장 표시 (D09 본문 §181 · D13 v1.8 별첨A §8.1 — 총괄 판정 IMPL-219 ②) ──
#
# **라우터 층 검사다.** 표시는 화면이 아니라 `app_root` 가 들고 있고, 저장 지점(D09 §2.4 3곳)의
# 화면이 무엇인지는 정해져 있지 않다. 그래서 실화면 하나가 아니라 **라우터를 세워** 본다.
#
# 축 4종:
#   ⓐ 값 창구 — 표시 시간·회전 주기가 D13(`core_params`) 에서 오는가
#   ⓑ 성공 저장 = 표시 · ⓒ 실패 저장 = 미표시 (§181 용도 = 저장 중 종료 경고의 근거)
#   ⓓ 화면 전환 생존 — `_show()` 가 갈아치우는 것은 `_current` 뿐이다
#
# **미구성이면 ⓑ 가 먼저 죽는다** — `flash()` 는 값이 없으면 보고 후 반환하므로, 이 축은
# `configure()` 결선이 실제로 서 있는지를 표시 여부로 되읽는다(상수 표가 아니라 거동).
func _save_indicator_wiring(data: GameData) -> void:
	var packed := load(APP_ROOT_SCENE) as PackedScene
	if packed == null:
		_ok("라우터 씬 로드", false)
		return
	var app := packed.instantiate() as Control
	root.add_child(app)
	var indicator: SaveIndicator = app._save_indicator
	_ok("라우터가 저장 표시를 든다", indicator != null)
	if indicator == null:
		root.remove_child(app)
		app.queue_free()
		return

	# ⓐ-2 **위치 = 우상단** (D09 §181 명문). 앵커만 보면 통과하지만 오프셋이 어긋나면
	# 화면에서는 좌상단에 뜬다 — 실제로 그랬다(9차 실측: rect P=(0,0) · 우측 여백 608).
	# 그래서 앵커가 아니라 **부모 폭 기준 실 rect** 로 본다.
	app.size = Vector2(640, 360)
	var r := indicator.get_rect()
	_ok("저장 표시 = 우상단 (우측 여백 0)",
		is_equal_approx(r.position.x + r.size.x, 640.0),
		"rect=%s 우측여백=%.1f" % [str(r), 640.0 - (r.position.x + r.size.x)])
	_ok("저장 표시 = 상단 (상단 여백 0)", is_equal_approx(r.position.y, 0.0),
		"y=%.1f" % r.position.y)
	# 회전이 중심을 돌아야 한다 — 피벗이 0 이면 아이콘이 좌상단 축으로 휘돈다.
	_ok("회전 피벗 = 도상 중심",
		indicator.pivot_offset.is_equal_approx(r.size * 0.5), str(indicator.pivot_offset))

	# ⓐ 값 창구. **표 행 실재를 먼저 본다** — 행이 없으면 `GameData.param()` 은 양쪽에서
	# 똑같이 0.0 을 돌려주므로, 비교만으로는 `0.0 == 0.0` 이 되어 조용히 통과한다
	# (돌연변이 M5 실측 — 항진명제). 행의 존재는 비교와 독립된 사실이라 먼저 세운다.
	_ok("D13 표 행 실재 — 표시 시간", data.params.has("param_fx_save_hold_sec"))
	_ok("D13 표 행 실재 — 회전 주기", data.params.has("param_fx_save_spin_sec"))
	_ok("표시 시간 = D13 창구 경유",
		indicator._hold_sec == data.param("param_fx_save_hold_sec"),
		"actual=%.3f" % indicator._hold_sec)
	_ok("회전 주기 = D13 창구 경유",
		indicator._spin_sec == data.param("param_fx_save_spin_sec"),
		"actual=%.3f" % indicator._spin_sec)
	_ok("미구성 센티넬 해소",
		indicator._hold_sec != SaveIndicator.UNCONFIGURED
			and indicator._spin_sec != SaveIndicator.UNCONFIGURED)
	_ok("저장 전에는 표시되지 않는다", not indicator.visible)

	# ⓑ 성공 저장 = 표시
	app.session.progress_saved.emit(true)
	_ok("성공 저장 = 표시", indicator.visible)
	# 회전은 **초로 도는 것이 규격**이다 — 주기가 실제로 소비되는지 1프레임분으로 본다.
	var before_rotation: float = indicator.rotation
	indicator._process(indicator._spin_sec * 0.25)
	_ok("표시 중 회전 진행", indicator.rotation > before_rotation,
		"rotation=%.3f" % indicator.rotation)

	# ⓒ 실패 저장 = 미표시. 앞선 표시가 남아 있으면 판정이 흐려지므로 먼저 닫는다.
	indicator._process(indicator._hold_sec)
	_ok("표시 시간 경과 후 소등", not indicator.visible)
	app.session.progress_saved.emit(false)
	_ok("실패 저장 = 미표시", not indicator.visible)

	# ⓓ 화면 전환 생존 — 저장이 전환과 겹치는 회차에 표시가 함께 사라지면 안 된다.
	app.session.progress_saved.emit(true)
	app._show("SYS-02", {})
	_ok("화면 전환 후에도 표시 생존", indicator.visible and indicator.is_inside_tree())
	root.remove_child(app)
	app.queue_free()


# ── ⑫ 도상 치수 2규격 공존 (IMPL-226) ──
#
# `_icon_texture()` 를 **릴 심볼(32 무배율)과 섹터 속성(16)이 함께 쓴다.** 창구가 하나이므로
# 한쪽 규격을 창구 안에서 판단하면 다른 쪽을 밟는다 — 그 밟힘을 여기서 고정한다.
#
# **파일명까지 대조한다.** 슬롯 크기만 보면 두 규격이 우연히 맞는 경우를 통과시키고,
# 상수(`ATTR_VARIANT`)만 보면 창구가 그것을 쓰는지 알 수 없다(돌연변이 전례).
func _icon_size_regimes(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	var screen := _mount(RACE_SCENE, session)
	if screen == null:
		return

	# ── 섹터 속성 = `_16` ──
	# 표에 있는 6종 전부를 창구에 통과시킨다. 데이터가 실제로 쓰는 id 로만 보면
	# 그 회차에 안 뜬 속성의 결선 누락이 검사를 빠져나간다.
	var attr_ids := ["attr_straight", "attr_technical", "attr_sweeper",
		"attr_hazard", "attr_battle_zone", "attr_pulse_section"]
	var attr_missing := 0
	var attr_wrong := 0
	for id in attr_ids:
		var tex: Texture2D = screen._icon_texture(id, screen.ATTR_VARIANT)
		if tex == null:
			attr_missing += 1
			continue
		if tex.resource_path.get_file().get_basename() != id + "_16":
			attr_wrong += 1
		if tex.get_size() != Vector2(16, 16):
			attr_wrong += 1
	_ok("섹터 속성 6종 _16 적재", attr_missing == 0, "missing=%d" % attr_missing)
	_ok("섹터 속성 = _16 파일 · 16×16", attr_wrong == 0, "wrong=%d" % attr_wrong)

	# ── 릴 심볼 = 32 무배율 (접미 없음) ──
	# **여기가 창구 공유의 위험 지점이다** — 창구가 치수를 스스로 정하면 릴도 16 이 된다.
	var reel_ids := ["symbol_slipstream", "symbol_braking", "symbol_line",
		"symbol_trouble", "symbol_chance", "symbol_pulse"]
	var reel_wrong := 0
	for id in reel_ids:
		var tex: Texture2D = screen._icon_texture(id)
		if tex == null or tex.resource_path.get_file().get_basename() != id \
			or tex.get_size() != Vector2(32, 32):
			reel_wrong += 1
	_ok("릴 심볼 6종 = 32 무배율 유지", reel_wrong == 0, "wrong=%d" % reel_wrong)

	# ── 실배치 슬롯이 등배인가 ──
	# 파일이 맞아도 슬롯이 어긋나면 화면에서 다시 축소된다(Zone A 가 그랬다).
	var attr_rect := screen.get_node("%E02SectorAttr") as TextureRect
	if attr_rect.texture != null:
		var box := attr_rect.size
		var tex_size := attr_rect.texture.get_size()
		var scale: float = minf(box.x / tex_size.x, box.y / tex_size.y)
		_ok("A존 속성 실배치 등배(축소 0)", is_equal_approx(scale, 1.0),
			"scale=%.4f box=%s tex=%s" % [scale, str(box), str(tex_size)])

	# ── 캐시가 두 규격을 섞지 않는가 ──
	# 같은 id 를 두 치수로 부르면 키가 갈려야 한다 — 안 갈리면 먼저 부른 쪽이 이긴다.
	var big: Texture2D = screen._icon_texture("attr_hazard")
	var small: Texture2D = screen._icon_texture("attr_hazard", screen.ATTR_VARIANT)
	_ok("캐시 키가 치수로 갈린다", big != null and small != null and big != small,
		"big=%s small=%s" % [
			big.resource_path.get_file() if big else "-",
			small.resource_path.get_file() if small else "-"])
	_unmount(screen)


# ── ⑫ 코드 생성 Control 배치 — `set_anchors_preset` 순서 함정 전수 (총괄 배정 IMPL-229 ⑥) ──
#
# **앵커가 아니라 부모 폭 기준 실 rect 로 본다** (주력 9차 검사 방식 준용 — IMPL-228).
# 저장 표시 결함은 **앵커가 정상인데 오프셋이 어긋난** 형태였고, 앵커만 보는 검사는 그것을
# 통과시킨다. 그래서 "무엇을 지정했는가"가 아니라 **부모 안에서 실제로 어디에 놓였는가**를
# 여백으로 잰다.
#
# 함정은 두 갈래이며 **둘 다 `set_anchors_preset()` 이 배치를 완성하지 않는다는 같은 뿌리**다:
#   ⓐ 트리 안·크기 미정 상태 호출 → 오프셋을 rect(0,0,0,0) 보존으로 **역산** → 좌상단 고정
#   ⓑ 트리 밖 호출 → 오프셋 0 → 배치가 **성장 방향**에 맡겨진다(기본 END = 앵커에서 우하향)
# FULL_RECT 계열은 ⓑ 경로에서 오프셋 0 이 곧 정답이라 무해하다 — 추정이 아니라 실측으로 건다.
const CANVAS := Vector2(640.0, 360.0)
const GARAGE_SCENE := "res://ui/hub/garage_screen.tscn"


func _margins(c: Control) -> Dictionary:
	var box := c.get_parent_area_size()
	return {
		"left": c.position.x,
		"right": box.x - c.position.x - c.size.x,
		"top": c.position.y,
		"bottom": box.y - c.position.y - c.size.y,
		"parent": box,
	}


func _ok_centered_h(label: String, c: Control) -> void:
	var m := _margins(c)
	_ok("%s — 가로 중앙 (좌여백 = 우여백)" % label,
		absf(float(m["left"]) - float(m["right"])) <= 1.0,
		"좌=%.1f 우=%.1f 부모=%s" % [m["left"], m["right"], str(m["parent"])])


func _ok_fills_parent(label: String, c: Control) -> void:
	var m := _margins(c)
	_ok("%s — 부모를 채운다 (여백 4면 0)" % label,
		absf(float(m["left"])) <= 1.0 and absf(float(m["right"])) <= 1.0
			and absf(float(m["top"])) <= 1.0 and absf(float(m["bottom"])) <= 1.0,
		"L=%.1f R=%.1f T=%.1f B=%.1f 부모=%s"
			% [m["left"], m["right"], m["top"], m["bottom"], str(m["parent"])])


func _anchor_preset_placement(data: GameData) -> void:
	var session := _fresh_session(data)

	# ⓐ 툴팁 패널 — CENTER_BOTTOM. 제1 후보였고 실제로 결함이었다.
	# **화면은 첫 프레임에 세워 둔 것을 쓴다** — 컨테이너 정렬이 끝나야 부모가 실 크기를
	# 갖고, 그래야 여백 단언이 공회전하지 않는다(§ LAYOUT_SETTLE_FRAMES).
	var achv := _settle_probe
	if achv == null:
		_ok("전제: 배치 측정용 화면 실재", false)
		return
	_ok("전제: 측정 대상 부모가 실 크기를 가진다",
		(achv.get_node("%TabBody") as Control).size.x > 0.0
			and (achv.get_node("%TabBody") as Control).size.y > 0.0,
		str((achv.get_node("%TabBody") as Control).size))
	var tab := (achv.get_node("%TabRow") as Control).get_child(0) as Control
	tab.tooltip_text = "TIP"
	tab.grab_focus()
	achv._show_detail()
	var panel: Control = achv._detail_panel
	_ok("전제: 툴팁 패널 표출", panel != null)
	if panel != null:
		# **크기가 0 이면 여백 단언이 전부 공회전한다** — 놓인 자리를 재기 전에 실재를 세운다.
		_ok("전제: 툴팁 패널이 크기를 가진다", panel.size.x > 0.0 and panel.size.y > 0.0,
			str(panel.size))
		_ok_centered_h("툴팁 패널", panel)
		var m := _margins(panel)
		_ok("툴팁 패널 — 하단 접지 (하여백 0)", absf(float(m["bottom"])) <= 1.0,
			"하여백=%.1f" % m["bottom"])
		# 역산 함정의 서명은 **좌상단 고정**이다 — 그 형태를 직접 부인한다.
		_ok("툴팁 패널 — 좌상단 고정이 아니다",
			panel.position.x > 1.0 or panel.position.y > 1.0, str(panel.position))

	# ⓑ 확인 대화상자 패널 — CENTER. 오프셋 0 + 성장 END 로 우하단에 놓여 있었다.
	var dialog := ConfirmDialog.new(data.strings, "summary", "cost", false,
		data.param_int("param_font_size_body"))
	achv.add_child(dialog)
	var dialog_panel := dialog.get_node("Panel") as Control
	_ok_centered_h("확인 대화상자 패널", dialog_panel)
	var dm := _margins(dialog_panel)
	_ok("확인 대화상자 패널 — 세로 중앙 (상여백 = 하여백)",
		absf(float(dm["top"]) - float(dm["bottom"])) <= 1.0,
		"상=%.1f 하=%.1f" % [dm["top"], dm["bottom"]])

	# ⓒ FULL_RECT 계열 무해 — **추정이 아니라 실측으로 명기한다** (인계 명문).
	_ok_fills_parent("모달 루트 FULL_RECT", dialog)
	_ok_fills_parent("모달 감광판 FULL_RECT", dialog.get_node("Dim") as Control)
	_ok_fills_parent("업적 탭 스크롤 FULL_RECT",
		(achv.get_node("%TabBody") as Control).get_child(0) as Control)
	# 모달은 초기 포커스를 **지연 호출**로 잡는다(`confirm_dialog.gd` — 오입력 방어). 화면을
	# 먼저 내리면 그 호출이 트리 밖 노드에 떨어져 검사가 자기 뒤처리로 진단을 만든다.
	# 그래서 지연분이 도는 프레임이 오기 전에 즉시 해제한다.
	achv.remove_child(dialog)
	dialog.free()
	# 툴팁도 같은 이유 — 띄운 채 내리면 뷰포트에 남은 포커스 구독이 사라진 화면을 부른다.
	achv._hide_detail()
	_unmount(achv)

	# ⓓ 라우터가 세운 화면 — 캔버스 전면을 덮는가 (FULL_RECT · add_child 이전 호출)
	var app := (load(APP_ROOT_SCENE) as PackedScene).instantiate() as Control
	root.add_child(app)
	_ok("전제: 캔버스 규격", app._current.get_parent_area_size() == CANVAS,
		str(app._current.get_parent_area_size()))
	_ok_fills_parent("라우터 화면 FULL_RECT", app._current)
	root.remove_child(app)
	app.queue_free()

	# ⓔ 온보딩 팁 — CENTER_TOP. 트리 밖 호출 + 성장 BOTH 라 이미 옳다(대조군).
	var garage := _mount(GARAGE_SCENE, session)
	if garage == null:
		return
	var tip := garage.get_node_or_null("OnboardingTip") as Control
	_ok("전제: 온보딩 팁 표출", tip != null)
	if tip != null:
		_ok_centered_h("온보딩 팁", tip)
	_unmount(garage)


# ── ⑬ ANCH 검사 실재 (총괄 판정 IMPL-233 ② 부대) ──
#
# **검사는 스스로 죽어도 자기를 신고하지 못한다.** 경고형이던 시절 실측: 결함을 재주입해
# 관측 가능한 바닥을 만든 뒤 ⓐ면제 목록에 그 프리셋을 더하거나 ⓑ등록 한 줄을 지우면
# **둘 다 무신호로 통과**했다. ANCH 는 차단형이 됐지만(IMPL-237) **그 둘 중 어느 쪽도
# 차단형이 막지 못한다** — 위반이 없는 것과 검사가 없는 것을 종료코드는 구분하지 않는다.
# PAL 이 죽은 조달로 대장 절반이 빈 채 통과했던 것과 같은 형태다(IMPL-198·201).
const VALIDATOR_SOURCE := "res://../tools/validators/run_validators.gd"
const VALIDATOR_CONFIG := "res://../tools/validators/config.json"
const CHOICE_DOMAIN := "vnChoice."
# 면제 목록은 **조용히 넓어지는 상수**다 — 넓히려면 이 단언을 함께 고쳐야 한다
# (검사 수 하한과 같은 축: 의도적 완화만 통과시킨다).
const ANCH_EXEMPT_EXPECTED := 'const ANCH_EXEMPT_PRESETS := ["PRESET_FULL_RECT"]'
# 규칙의 **적용 범위**를 정하는 상수들. 비우거나 좁히면 검사는 살아 있는 채로 아무것도
# 보지 않는다 — 실측: `ANCH_ANCHOR_PROPERTIES` 를 비우면 B1 경로가 통째로 죽고도
# `ANCH ... PASS (5 checks)` 로 통과했다(돌연변이 M5). 면제 목록과 같은 축으로 고정한다.
const ANCH_ANCHORS_EXPECTED := 'const ANCH_ANCHOR_PROPERTIES := ["anchor_left", "anchor_right", "anchor_top", "anchor_bottom"]'
# 짝 목록은 **넓어지는 쪽**이 위험하다 — `position` 을 도로 넣으면 한 축만 고정한 코드가
# 짝을 갖춘 것으로 통과한다(신설 시 판정 ②로 배제한 형태).
# **부분 일치로는 추가를 못 본다** — 목록 뒤에 한 항목을 덧붙이면 기존 조각은 그대로
# 남아 `contains()` 가 통과한다(돌연변이 M6 실측). 그래서 목록을 통째로 떼어내 대조한다.
const ANCH_PAIR_HEAD := 'const ANCH_PAIR_PROPERTIES := ['
const ANCH_PAIR_EXACT := '"grow_horizontal","grow_vertical","offset_left","offset_right","offset_top","offset_bottom",'


func _anch_check_present() -> void:
	var source := FileAccess.get_file_as_string(VALIDATOR_SOURCE)
	_ok("검증기 원본 적재", not source.is_empty())
	if source.is_empty():
		return
	_ok("ANCH 검사 정의 실재", source.contains("func _run_anchor_scan("))
	# 정의만 있고 부르지 않으면 검사는 없는 것과 같다 — 등록까지 본다.
	_ok("ANCH 검사 등록(호출) 실재", source.contains("\t_run_anchor_scan()"))
	_ok("ANCH 면제 목록 = FULL_RECT 전속", source.contains(ANCH_EXEMPT_EXPECTED))
	_ok("ANCH 앵커 속성 4종 전량 감시", source.contains(ANCH_ANCHORS_EXPECTED))
	_ok("ANCH 짝 목록 = grow 2 + 오프셋 4 (추가·삭제 0)",
		_anch_pair_list(source) == ANCH_PAIR_EXACT, _anch_pair_list(source))
	# 차단형 전환분(IMPL-237) — 경고로 되돌리면 위반이 빌드를 멈추지 않는다.
	_ok("ANCH = 차단형 (경고 호출 잔존 0)", not source.contains('_warn("ANCH"'))
	# ── STRF (총괄 판정 IMPL-249 ③ — 차단형 즉시 신설) ──
	# ANCH 와 같은 이유로 실재를 건다: **위반이 없는 것과 검사가 없는 것을 종료코드는
	# 구분하지 않는다.** STRF 는 위반 0 인 상태로 상주하는 검사라 특히 그렇다.
	_ok("STRF 검사 정의 실재", source.contains("func _run_string_field_scan("))
	_ok("STRF 검사 등록(호출) 실재", source.contains("\t_run_string_field_scan()"))
	_ok("STRF = 차단형 (경고 호출 잔존 0)", not source.contains('_warn("STRF"'))
	# 인용 인식이 규칙의 본체다 — 산술 비교로 되돌리면 정상 데이터 2건이 오검출된다(실측).
	_ok("STRF 인용 인식 보유", source.contains("func _strf_records("))
	# ── 선택지 자수 규칙 (총괄 판정 IMPL-257 ②) ──
	# **검사가 아니라 규칙 행이다.** V3·V7 은 그대로 살아 있으므로 행이 지워져도 검사는 죽지
	# 않고 **그 도메인만 조용히 규율 밖으로 나간다** — 종료코드가 구분하지 못하는 자리가
	# ANCH·STRF 와 같아 같은 방식으로 실재를 건다(1차 `resonance03` 이 그 상태에서 샜다).
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(VALIDATOR_CONFIG))
	_ok("검사 설정 적재", typeof(config) == TYPE_DICTIONARY)
	if typeof(config) != TYPE_DICTIONARY:
		return
	var choice_rule: Dictionary = {}
	for rule in Array(Dictionary(config).get("string_write_rules", [])):
		if Array(Dictionary(rule).get("domain_prefixes", [])).has(CHOICE_DOMAIN):
			choice_rule = rule
	_ok("vnChoice. 자수 규칙 행 실재", not choice_rule.is_empty())
	_ok("vnChoice. = 1줄", int(choice_rule.get("max_lines", -1)) == 1, str(choice_rule))
	_ok("vnChoice. = 전각 14", int(choice_rule.get("max_chars_full", -1)) == 14, str(choice_rule))
	_ok("vnChoice. V7 도메인 편입",
		Array(Dictionary(config).get("v7_domains", [])).has(CHOICE_DOMAIN))
	# ── `act_vn.json` 배열 스펙 (총괄 판정 IMPL-257 ① 부속) ──
	# 스펙을 지우면 V1 은 **그대로 통과한다** — 검사가 죽는 게 아니라 볼 것이 없어질 뿐이다
	# (돌연변이 M18 미검출로 실측). 같은 값 도메인이 표에서는 차단되고 구조에서는 새던
	# 비대칭을 닫은 것이 이 스펙이므로, 스펙의 실재를 검사가 대신 지킨다.
	var act_spec: Dictionary = Dictionary(Dictionary(config).get("structures", {})) \
		.get("act_vn.json", {}).get("arrays", {}).get("entries", {}).get("required", {})
	_ok("act_vn entries 스펙 실재", not act_spec.is_empty())
	_ok("act_vn act 범위 강제", String(act_spec.get("act", "")) == "int:1,4", str(act_spec))
	_ok("act_vn tone 도메인 강제", String(act_spec.get("tone", "")) == "enum:calm,tense", str(act_spec))
	_ok("act_vn order 범위 강제", String(act_spec.get("order", "")) == "int:1,9", str(act_spec))


# `ANCH_PAIR_PROPERTIES` 목록 본문만 떼어 공백을 지운 형태. 항목이 하나라도 늘거나
# 줄면 문자열이 달라진다 — `position` 재편입 같은 **완화**를 잡는 것이 목적이다.
func _anch_pair_list(source: String) -> String:
	var at := source.find(ANCH_PAIR_HEAD)
	if at < 0:
		return ""
	var rest := source.substr(at + ANCH_PAIR_HEAD.length())
	var close_at := rest.find("]")
	if close_at < 0:
		return ""
	return rest.substr(0, close_at).replace("\n", "").replace("\t", "").replace(" ", "")


# ── ⑭ VN 라인 단위 화자 (총괄 판정 IMPL-249 ② — 신설안 C) ──
#
# **관측 지점 = 큐음 발화 기록.** 화자가 라인마다 갈리는지는 라벨만 봐서는 절반만 보는 것이다 —
# D11 §2.10 이 규정한 것은 **음색이 화자를 따라간다**는 쪽이고, 실제 결함(마르타 대사에 베인
# 3단계 큐음)이 거기서 났다. 그래서 실화면을 세워 라인을 넘기며 무엇이 울렸는지 센다.
const VN_SCENE := "res://ui/nar/vn_screen.tscn"


func _vn_line_speakers(data: GameData) -> void:
	var session := _fresh_session(data)
	var packed := load(VN_SCENE) as PackedScene
	if packed == null:
		_ok("VN 씬 로드", false)
		return
	var screen := packed.instantiate() as Control
	screen.session = session
	root.add_child(screen)
	# 베인 → 마르타 → 지문 순으로 화자가 갈리는 3라인. 납품 문안의 실제 형태다.
	screen.bind(session, {
		"vn_id": "", "slot_id": "",
		"line_keys": [
			{"speaker_key": "ui.vn.speakerVane", "text_key": "vn.act1.beat07"},
			{"speaker_key": "ui.vn.speakerMarta", "text_key": "vn.act1.beat02"},
			{"speaker_key": "ui.vn.speakerNarration", "text_key": "vn.act1.beat01"},
		],
	})
	var vane_first := _cue_count(session, "SE-V01")
	var common_first := _cue_count(session, "SE-V02")
	_ok("1라인(베인) = 베인 큐음", vane_first == 1, "vane=%d" % vane_first)
	_ok("1라인(베인) = 공용음 미발화", common_first == 0, "common=%d" % common_first)
	_ok("1라인 화자 라벨 = 베인",
		(screen.get_node("%SpeakerLabel") as Label).text == data.strings.text("ui.vn.speakerVane"))
	screen._advance()
	_ok("2라인(마르타) = 공용음", _cue_count(session, "SE-V02") == 1)
	_ok("2라인(마르타) = 베인 큐음 불추가",
		_cue_count(session, "SE-V01") == vane_first,
		"vane=%d" % _cue_count(session, "SE-V01"))
	_ok("2라인 화자 라벨 = 마르타",
		(screen.get_node("%SpeakerLabel") as Label).text == data.strings.text("ui.vn.speakerMarta"))
	screen._advance()
	# 지문은 값이 공란이라 라벨이 빈다 — 그것이 지문 표기다(별도 분기 없음).
	_ok("3라인(지문) 라벨 공란",
		(screen.get_node("%SpeakerLabel") as Label).text == "")
	# **연속 동일 큐음은 재트리거 게이트가 막는다**(D11 §6.3 0.05초 — 같은 프레임 2발 실측).
	# 그래서 공용음 '추가'가 아니라 **베인 큐음이 안 늘었는가**로 본다 — 계약은 그쪽이다.
	_ok("3라인(지문) = 베인 큐음 불추가", _cue_count(session, "SE-V01") == vane_first,
		"vane=%d" % _cue_count(session, "SE-V01"))
	root.remove_child(screen)
	screen.free()


# ── ⑰ VN 선택 지점 (D04 §5.3 · 총괄 판정 IMPL-257) ──
#
# 축이 **두 상태 모두**인 것이 요점이다. 오버레이 씬 노드는 주력 몫이라 지금은 없고,
# 없는 상태에서 지점에 닿으면 화면이 멈추면 안 된다(생략). 노드가 선 뒤에는 지점이 실제로
# 떠야 한다. 한쪽만 검사하면 **다른 쪽이 조용히 죽는다** — 특히 "지금 없다"는 이유로 부재
# 경로만 보면, 주력이 노드를 세운 날 결선이 끊긴 것을 아무도 모른다.
const CHOICE_VN_ID := "vn_act3"
const CHOICE_ID := "vnchoice_act3_corner"


func _vn_choice_point(data: GameData) -> void:
	var lines: Array = [
		{"speaker_key": "ui.vn.speakerMarta", "text_key": "vn.act3.beat10"},
		{"speaker_key": "ui.vn.speakerMarta", "text_key": "vn.act3.beat11"},
		{"speaker_key": "ui.vn.speakerVane", "text_key": "vn.act3.beat12"},
	]
	# ── ⓐ 노드 부재 = 지점 생략 · 진행 계속 (현행 씬 실물) ──
	var absent := _mount_vn(data, lines, false)
	if absent == null:
		return
	absent._advance()
	absent._advance()
	_ok("노드 부재 = 지점 생략 관측", Array(absent.choice_omissions) == [CHOICE_ID],
		str(absent.choice_omissions))
	_ok("노드 부재 = 진행 잠기지 않음",
		(absent.get_node("%BodyLabel") as Label).text == data.strings.text("vn.act3.beat12"),
		(absent.get_node("%BodyLabel") as Label).text)
	_release_vn(absent)

	# ── ⓑ 노드 실재 = 지점 발동 · 반응 삽입 · 합류 ──
	var screen := _mount_vn(data, lines, true)
	if screen == null:
		return
	var overlay := screen.find_child("ChoiceOverlay", true, false) as Control
	var list := screen.find_child("ChoiceList", true, false) as Container
	_ok("지점 전에는 오버레이 비표시", not overlay.visible)
	screen._advance()
	screen._advance()
	_ok("앵커 라인 뒤에서 지점 발동", overlay.visible)
	_ok("생략 0", Array(screen.choice_omissions).is_empty(), str(screen.choice_omissions))
	# 버튼 수는 데이터가 정한다 — `option_count` 는 V1 이 2~3 으로 강제하는 열이다.
	var declared := CsvTable.to_int(String(data.vn_choices[CHOICE_ID]["option_count"]))
	_ok("선택지 수 = option_count", list.get_child_count() == declared,
		"%d vs %d" % [list.get_child_count(), declared])
	var options := data.vn_choice_options_for(CHOICE_ID)
	var text_ok := true
	for index in range(options.size()):
		var expected := data.strings.text(String(options[index]["text_key"]))
		if (list.get_child(index) as Button).text != expected:
			text_ok = false
	_ok("버튼 문면 = 데이터 값(대괄호 포함)", text_ok)
	_ok("대괄호가 데이터에 있다 — 화면 조립 아님",
		(list.get_child(0) as Button).text.begins_with("["))
	# 선택 대기 중 진행 입력은 소비되지 않는다 — 임의 선택도, 건너뜀도 아니다.
	var body_before := (screen.get_node("%BodyLabel") as Label).text
	screen._advance()
	_ok("선택 대기 = 진행 입력 무소비", overlay.visible
		and (screen.get_node("%BodyLabel") as Label).text == body_before)
	# 스킵은 지점 위에서도 살아 있어야 한다(G2 조건 2) — 막다른 길이 되지 않는 근거다.
	_ok("지점 위 스킵 생존", (screen.get_node("%SkipButton") as Button).visible
		and not (screen.get_node("%SkipButton") as Button).disabled)
	(list.get_child(1) as Button).pressed.emit()
	var picked: Dictionary = options[1]
	_ok("선택 후 오버레이 닫힘", not overlay.visible)
	_ok("선택 후 버튼 잔존 0", list.get_child_count() == 0)
	_ok("반응 라인 재생",
		(screen.get_node("%BodyLabel") as Label).text
			== data.strings.text(String(picked["reaction_text_key"])),
		(screen.get_node("%BodyLabel") as Label).text)
	_ok("반응 화자 = 데이터 지정",
		(screen.get_node("%SpeakerLabel") as Label).text
			== data.strings.text(String(picked["reaction_speaker_key"])))
	screen._advance()
	_ok("반응 뒤 합류 라인 복귀",
		(screen.get_node("%BodyLabel") as Label).text == data.strings.text("vn.act3.beat12"),
		(screen.get_node("%BodyLabel") as Label).text)
	_release_vn(screen)

	# ── ⓒ 지점 위 스킵 = 선택 없이 종료 · 반응 미재생 ──
	var skipped := _mount_vn(data, lines, true)
	if skipped == null:
		return
	var routed: Array = []
	skipped.navigate.connect(func(target: String, _payload: Dictionary): routed.append(target))
	var skip_overlay := skipped.find_child("ChoiceOverlay", true, false) as Control
	skipped._advance()
	skipped._advance()
	_ok("스킵 전 지점 표시", skip_overlay.visible)
	var before_skip := (skipped.get_node("%BodyLabel") as Label).text
	(skipped.get_node("%SkipButton") as Button).pressed.emit()
	_ok("지점 위 스킵 = 화면 이탈", routed.size() == 1, str(routed))
	_ok("지점 위 스킵 = 오버레이 닫힘", not skip_overlay.visible)
	_ok("지점 위 스킵 = 반응 미재생",
		(skipped.get_node("%BodyLabel") as Label).text == before_skip)
	_release_vn(skipped)


# 오버레이 노드는 **주력 씬 몫**이라 이 검사가 세운다 — 계약(이름·형)만 재현한다.
func _mount_vn(data: GameData, lines: Array, with_overlay: bool) -> Control:
	var packed := load(VN_SCENE) as PackedScene
	if packed == null:
		_ok("VN 씬 로드", false)
		return null
	var screen := packed.instantiate() as Control
	var session := _fresh_session(data)
	screen.session = session
	root.add_child(screen)
	if with_overlay:
		var overlay := Control.new()
		overlay.name = "ChoiceOverlay"
		overlay.visible = false
		var list := VBoxContainer.new()
		list.name = "ChoiceList"
		overlay.add_child(list)
		screen.add_child(overlay)
	# 재열람 경로로 세운다 — 슬롯 발생 판정을 거치지 않으므로 지점 축만 남는다.
	# (§3.2 — 재열람에서도 지점은 다시 선다: 다른 선택의 반응이 회수 경로다.)
	screen.bind(session, {
		"replay": true, "vn_id": CHOICE_VN_ID, "slot_id": "vnslot_tour_brief",
		"line_keys": lines,
	})
	return screen


func _release_vn(screen: Control) -> void:
	root.remove_child(screen)
	screen.free()


# **발화 기록은 event_id 가 아니라 sfx_id 다** (디스패처가 `sound_map` 을 거쳐 변환한다).
# 베인 큐음은 인격 3단계로 갈리므로 SE-V01a/b/c 를 한 축으로 센다 — 단계는 여기 관심사가 아니다.
func _cue_count(session: RunSession, prefix: String) -> int:
	var total := 0
	for sfx_id in session.audio.fired:
		if String(sfx_id).begins_with(prefix):
			total += 1
	return total


# ── ⑯ 튜토리얼 콜아웃 배치 (총괄 배정 IMPL-253 ① · 교정 IMPL-258) ──
#
# 축은 **두 개를 동시에 만족하는가**다. 콜아웃은 ⓐ지목한 요소를 가리면 안 되고(IMPL-138 이
# 세운 규칙) ⓑ상시 표시 스트립(Zone A)도 가리면 안 된다. 하나만 보면 통과한다 —
# 실측된 결함이 정확히 그 형태였다: 지목 요소는 비켜 갔지만 스트립 30px 중 22px 을 덮었다.
#
# **앵커가 아니라 실 rect 교집합으로 본다.** 예약 영역은 노드 rect 에서 읽어 배치하므로
# 앵커·오프셋 값을 단언하면 배치 규칙이 바뀔 때마다 검사를 고쳐야 하고, 정작 "겹쳤는가"는
# 보지 못한다. 겹침 면적 0 이 계약이다.
func _tutorial_callout_placement() -> void:
	var screen := _settle_race
	if screen == null:
		_ok("전제: 배치 측정용 레이스 화면 실재", false)
		return
	var strip := screen.get_node("Root/ZoneA") as Control
	var panel := screen.get_node("%CalloutPanel") as Control
	var overlay := screen.get_node("%TutorialOverlay") as Control
	# 0 크기 부모에서는 교집합이 늘 0 이라 단언 전체가 공회전한다.
	_ok("전제: 상단 스트립이 실 크기를 가진다", strip.size.x > 0.0 and strip.size.y > 0.0,
		str(strip.size))
	overlay.begin()
	_ok("전제: 콜아웃 패널이 크기를 가진다", panel.size.x > 0.0 and panel.size.y > 0.0,
		str(panel.size))
	var steps: Array = screen.session.data.tutorial_steps
	_ok("전제: 단계 표 실재", steps.size() > 0, "steps=%d" % steps.size())
	for i in range(steps.size()):
		var step: Dictionary = steps[i]
		var anchor := screen.find_child(String(step["anchor_node"]), true, false) as Control
		var p_rect := panel.get_global_rect()
		var strip_hit := p_rect.intersection(strip.get_global_rect()).get_area()
		_ok("%d단계 — 상단 스트립 불침범" % (i + 1), strip_hit <= 0.0,
			"겹침=%.1fpx²" % strip_hit)
		if anchor != null:
			var anchor_hit := p_rect.intersection(anchor.get_global_rect()).get_area()
			_ok("%d단계 — 지목 요소 불가림" % (i + 1), anchor_hit <= 0.0,
				"겹침=%.1fpx² 대상=%s" % [anchor_hit, step["anchor_node"]])
		_ok("%d단계 — 콜아웃이 화면 안" % (i + 1),
			p_rect.position.y >= -0.5 and p_rect.end.y <= CANVAS.y + 0.5,
			str(p_rect))
		overlay.notify_action(String(step["advance_on"]))
	_unmount(screen)
	_settle_race = null
