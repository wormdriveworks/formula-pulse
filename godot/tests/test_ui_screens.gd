# UISCR — 화면 단독 인스턴스화 검사 (실화면을 실제로 세워 결속 계약을 본다).
#
# **왜 필요한가.** 화면 층 결함 중에는 데이터·코어 검사가 원리적으로 닿지 못하는 계열이 있다.
# 이번 축은 **문맥 결손**이다: 화면이 `session.outgame` 같은 "있을 때도 없을 때도 있는" 것을
# 무가드로 읽으면, 커리어를 연 경로에서는 멀쩡하고 **타이틀 직행 경로에서만** 죽는다.
# 실제로 SYS-04 가 그렇게 샜다(총괄 판정 IMPL-176 ① — 타이틀 첫 진입 100% 재현).
#
# 검사 축 18종:
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
#   ⑱ 막 VN 소비부 — 발화→페이로드→실화면→도달 · 정조 BGM 분기 (IMPL-263 ①②)
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
const APP_ROOT_SCENE_SCRIPT := "res://ui/flow/app_root.gd"
# 패드 버튼 인덱스 — 엔진 실측분(IMPL-186). 검사도 화면과 같은 상수를 짐작하지 않는다.
const PAD_A_INDEX := 0
const PAD_X_INDEX := 2
const PAD_Y_INDEX := 3
const PAD_LB_INDEX := 9
const PAD_DPAD_LEFT_INDEX := 13
const PAD_DPAD_RIGHT_INDEX := 14
const LOG_FEED_SCRIPT := "res://ui/race/log_feed.gd"
const VN_SCREEN_SCRIPT := "res://ui/nar/vn_screen.gd"

var _checked := 0
var _failures := 0


# **컨테이너 정렬은 다음 프레임에 선다.** 배치 축(⑫)은 부모의 실 크기를 재는 검사이므로
# 첫 프레임에 재면 부모도 자식도 0 이라 "여백 0 = 부모를 채운다"가 **0 == 0 으로 성립**한다
# (돌연변이 M6 미검출로 드러난 공회전). 그래서 그 축만 정렬이 끝난 프레임으로 미룬다.
const LAYOUT_SETTLE_FRAMES := 4

var _frame := 0
var _settle_probe: Control
var _settle_race: Control
var _settle_choice: Control


func _process(_delta: float) -> bool:
	_frame += 1
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차 · 멱등)
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
			# 선택 오버레이 배치 축(⑰-ⓓ)도 정렬이 끝난 뒤에 재야 한다 — 오버레이는
			# **내용이 크기를 정하는 PanelContainer** 라 지점을 연 그 프레임에는 크기가 0이고,
			# 0 크기에서는 "스킵을 안 가린다"가 0==0 으로 성립한다.
			_settle_choice = _mount_vn(data, CHOICE_LINES, true)
			if _settle_choice != null:
				_settle_choice._advance()
				_settle_choice._advance()
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
	_vn_choice_geometry(data)
	_vn_last_line_input(data)
	_input_handled_ordering()
	_mouse_click_paths(data)
	_act_vn_consumption(data)
	_skill_session_channel(data)
	_season_open_wiring(data)
	_archive_replay_wiring(data)
	_tutorial_callout_placement()
	_skill_slots(data)
	_skill_snapshot_pairing(data)
	_cg_cutin_channel(data)
	_vn_cg_layer(data)
	_skill_label_and_notice(data)
	_intervention_gate(data)
	_reject_notice_slot(data)
	_snapshot_keep_new_button(data)
	_options_relabel(data)
	_focus_ring_theme(data)
	_danger_frame_colorblind(data)
	_semantic_frame_consumers(data)
	_action_row_budget(data)
	_scene_panel_layers(data)
	_scene_panel_phase(data)
	print("")
	# 검사 수 하한 — 씬 로드 실패로 스위트가 쪼그라들면 "통과"가 아니다.
	if _checked < 812:
		print("UI_SCREENS_FAIL checks=%d < 하한 812 (스위트 축소·씬 로드 실패 의심)" % _checked)
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
	# **도는 도상은 회전 대칭이어야 한다** (주력 11차 IMPL-291). 상수 선언이 아니라
	# **실제로 물린 텍스처의 파일명**을 본다 — 선언은 결선의 증거가 아니다.
	# 방향성 글리프로 되돌리면 180° 마다 의미가 '불러오기'로 반전한다(10차 §5 판독).
	_ok("회전 도상 = 회전 대칭 변형",
		indicator.texture != null
			and indicator.texture.resource_path.get_file() == "sys_save_spin.png",
		"" if indicator.texture == null else indicator.texture.resource_path.get_file())
	# 대칭은 파일명이 아니라 픽셀의 성질이다 — 알파 형상을 90°·180° 회전과 대조한다.
	if indicator.texture != null:
		var img := indicator.texture.get_image()
		var w := img.get_width()
		var h := img.get_height()
		var sym90 := w == h
		var sym180 := true
		for y in range(h):
			for x in range(w):
				var on: bool = img.get_pixel(x, y).a >= 0.5
				if sym90 and on != (img.get_pixel(y, h - 1 - x).a >= 0.5):
					sym90 = false
				if on != (img.get_pixel(w - 1 - x, h - 1 - y).a >= 0.5):
					sym180 = false
		_ok("회전 도상 — 90° 대칭", sym90)
		_ok("회전 도상 — 180° 대칭", sym180)

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
	# ⓓ-2 **그려지는가 — 형제 순서** (12차 실기 발견 · IMPL-312).
	# 위 ⓓ 의 `visible and is_inside_tree()` 는 "보인다"의 증거가 아니다. 형제 순서가 곧
	# 그리기 순서이고, 표시는 `_ready()` 에서 한 번 붙고 화면은 전이마다 **그 뒤에** 붙는다.
	# 저장 지점 3곳(D09 §2.4)의 화면은 전부 전면 불투명 `Background` 를 깔기 때문에
	# 표시는 **한 번도 보인 적이 없었다** — 그런데 ⓓ 는 그 상태에서도 통과했다.
	# 그래서 축을 "가시 플래그"에서 **"덮이지 않는 자리"** 로 옮긴다.
	var last_child: Node = app.get_child(app.get_child_count() - 1)
	_ok("전환 후 표시가 라우터의 마지막 형제 (= 최상단 그리기)",
		last_child == indicator, "last=%s" % last_child.name)
	_ok("전환 후 표시 인덱스 > 현 화면 인덱스",
		app._current != null and indicator.get_index() > app._current.get_index(),
		"indicator=%d current=%d" % [indicator.get_index(),
			-1 if app._current == null else app._current.get_index()])
	# ⓔ **90° 계단 양자화** (총괄 판정 IMPL-294 ② · 19차 집행).
	# 등속이면 서브픽셀 각도가 나오고, 그것은 도트 세계에서 이질적이다(D10 §2.2 귀결).
	# 축은 **각도 집합**으로 본다 — "회전한다"만 보면 등속과 계단이 구분되지 않는다.
	var spin: float = data.param("param_fx_save_spin_sec")
	var steps: int = indicator.ROTATION_STEPS
	_ok("회전 스텝 = 4 (90°)", steps == 4, str(steps))
	var angles: Dictionary = {}
	var samples := 40
	for index in range(samples):
		# 주기 1바퀴를 촘촘히 훑는다 — 계단이면 값이 4종뿐이다.
		var degrees := snappedf(rad_to_deg(indicator._quantized_rotation(
			spin * float(index) / float(samples))), 0.001)
		angles[degrees] = true
	_ok("한 주기 각도 = 4종뿐(계단)", angles.size() == steps, str(angles.keys()))
	var expected: Array = [0.0, 90.0, 180.0, 270.0]
	var off := 0
	for degrees in angles:
		if not expected.has(float(degrees)):
			off += 1
	_ok("각도 = 90° 격자 전건", off == 0, str(angles.keys()))
	# 주기 경계에서 되돌아온다 — 누적 오차가 쌓이면 여기서 어긋난다.
	_eq_deg("주기 경계 = 0°", indicator._quantized_rotation(spin), 0.0)
	_eq_deg("2주기 경계 = 0°", indicator._quantized_rotation(spin * 2.0), 0.0)
	_eq_deg("주기 절반 = 180°", indicator._quantized_rotation(spin * 0.5), 180.0)
	# **스텝 순서**가 규격이다 — 각도 집합만 보면 뒤섞인 매핑도 통과한다(0→270→90→180).
	var quarter := spin / float(steps)
	for index in range(steps):
		_eq_deg("스텝 %d = %d°" % [index, index * 90],
			indicator._quantized_rotation(quarter * float(index) + quarter * 0.5),
			float(index) * 90.0)
	root.remove_child(app)
	app.queue_free()


func _eq_deg(label: String, actual_rad: float, expected_deg: float) -> void:
	_ok(label, absf(rad_to_deg(actual_rad) - expected_deg) <= 0.001,
		"actual=%.3f expected=%.3f" % [rad_to_deg(actual_rad), expected_deg])


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
	# **저장 루트가 실기로 되돌아가지 않는가 (25차 · 거동 축).** 원본 검사는 "앱 부팅이
	# 실기 루트를 세운다"까지만 보고 **언제 효과가 나는지**는 보지 못한다 — 이 축이
	# `app_root` 를 실제로 세우므로 그 `_ready()` 가 격리 루트를 덮으면 이후 스위트의
	# 저장이 실 프로필로 간다(게이트 밖 바이트 대조가 그것을 잡았다).
	_ok("㉑ 앱 부팅이 격리 루트를 덮지 않는다", SaveManager.is_test_root(),
		"use_live_root() 는 이미 잡힌 루트에 양보해야 한다")
	_ok("전제: 캔버스 규격", app._current.get_parent_area_size() == CANVAS,
		str(app._current.get_parent_area_size()))
	_ok_fills_parent("라우터 화면 FULL_RECT", app._current)
	root.remove_child(app)
	app.queue_free()

	# ⓔ 온보딩 팁 — CENTER_TOP. 트리 밖 호출 + 성장 BOTH 라 이미 옳다(대조군).
	#
	# **전제를 기계가 직접 세운다.** 팁은 1회성이고 그 기록은 `user://options.json` 이라
	# **테스트 밖의 실플레이가 전제를 소모한다** — 12차 실기 회차 직후 이 축이 FAIL 했다
	# (마운트 자체가 `mark_onboarding()` 을 타서 디스크까지 쓴다). 검사가 머신 상태에
	# 의존하면 회귀가 아니라 날씨가 된다. 기록을 비우고 들어가 끝나고 되돌린다.
	var seen_backup: Dictionary = session.options.onboarding_seen.duplicate(true)
	session.options.onboarding_seen.clear()
	var garage := _mount(GARAGE_SCENE, session)
	if garage != null:
		var tip := garage.get_node_or_null("OnboardingTip") as Control
		_ok("전제: 온보딩 팁 표출", tip != null)
		if tip != null:
			_ok_centered_h("온보딩 팁", tip)
		_unmount(garage)
	else:
		_ok("전제: 온보딩 팁 표출", false, "개러지 씬 로드 실패")
		_ok("온보딩 팁 — 수평 중앙", false, "개러지 씬 로드 실패")
	# 세션 밖 전역이라 디스크까지 돌려놓는다.
	session.options.onboarding_seen = seen_backup
	session.options.save_to_disk()

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
const SLOT_DOMAIN := "ui.vnSlot."
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


# 등재 언어 = D15 §4.1 EA 세트(한국어 원문·영어·일본어)의 물리적 실체.
# 순서가 계약이다 — O11 선택 인덱스가 표 헤더 순서를 탄다 (options_store.language_code()).
const LANGUAGE_COLUMNS_EXPECTED := ["ko", "en", "ja"]

const G4W_SOURCE := "res://tests/test_label_width.gd"
const UISCR_SOURCE := "res://tests/test_ui_screens.gd"


# a 에 있고 b 에 없는 항목 (미훅 목록 산출)
func _missing_from(a: Array, b: Array) -> Array:
	var out: Array = []
	for item in a:
		if not b.has(item):
			out.append(item)
	return out


func _test_sources() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".gd"):
			out.append("res://tests/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# 주석 행(`#` 로 시작)을 제외한 계수 — 문서 주석의 같은 이름을 세지 않는다.
func _count_of_code(source: String, needle: String) -> int:
	var count := 0
	for line in source.split("\n"):
		if String(line).strip_edges().begins_with("#"):
			continue
		count += _count_of(String(line), needle)
	return count


func _count_of(source: String, needle: String) -> int:
	var count := 0
	var from := 0
	while true:
		var at := source.find(needle, from)
		if at < 0:
			return count
		count += 1
		from = at + 1
	return count


func _strings_header() -> Array:
	var rows := CsvTable.load_rows(GameData.STRINGS_PATH)
	if rows.is_empty():
		return []
	return Dictionary(rows[0]).keys()


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
	# ── FXPL (신설 29차 경고형 → **차단형** 전환 · 총괄 판정 ㊱ IMPL-440) ──
	# 실재를 받치는 이유는 ANCH·STRF 와 같고, 여기에 **성격까지** 못박는다 —
	# 경고로 되돌리면 위반이 빌드를 멈추지 않는데 종료코드는 그것을 말해 주지 않는다.
	_ok("FXPL 검사 정의 실재", source.contains("func _run_fx_placement_scan("))
	_ok("FXPL 검사 등록(호출) 실재", source.contains("\t_run_fx_placement_scan()"))
	# 지형 소재를 잃으면 검사가 조용히 무대상이 된다 — 소재 경로까지 본다.
	_ok("FXPL 지형 소재 = bg_spec", source.contains("tools/assets/bg_spec.json"))
	_ok("FXPL = 차단형 (경고 호출 잔존 0)", not source.contains('_warn("FXPL"'))
	# ── CUTM (신설 31차 경고형 → **차단형** 전환 · 총괄 판정 ㊳ IMPL-450) ──
	# 실재를 받치는 이유는 ANCH·STRF·FXPL 과 같고, 전환됐으므로 **성격까지** 못박는다.
	_ok("CUTM 검사 정의 실재", source.contains("func _run_cut_layout_scan("))
	_ok("CUTM 검사 등록(호출) 실재", source.contains("\t_run_cut_layout_scan()"))
	_ok("CUTM 전사 소재 = cut_layout", source.contains("tools/assets/cut_layout.json"))
	_ok("CUTM = 차단형 (경고 호출 잔존 0)", not source.contains('_warn("CUTM"'))
	# ── FXJ (신설 33차 경고형 → **차단형** 전환 · 총괄 판정 ㊴ IMPL-459) ──
	# **양 정규화가 이 검사의 본체다** — `pick` 을 빼면 거짓 결함이 상시로 나온다.
	_ok("FXJ 검사 정의 실재", source.contains("func _run_fx_join_scan("))
	_ok("FXJ 검사 등록(호출) 실재", source.contains("\t_run_fx_join_scan()"))
	_ok("FXJ 접합 소재 = fx_spec", source.contains("tools/assets/fx_spec.json"))
	_ok("FXJ 양 정규화 보유 (pick)", source.contains('entry.has("pick")'))
	_ok("FXJ = 차단형 (경고 호출 잔존 0)", not source.contains('_warn("FXJ"'))
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
	# ── 아카이브 표제 자수 규칙 (총괄 판정 IMPL-284 ①) ──
	# `vnChoice.` 와 같은 성격 — 행이 지워지면 검사는 죽지 않고 **그 도메인만 규율 밖으로** 나간다.
	# 값 13 의 출처는 D13 대장이 아니라 라벨 폭 140px 실기 역산이라(라벨 폭 = 씬 소관)
	# 규칙 행의 `source` 필드가 그 사실을 이고 있다 — 그것까지 실재를 건다.
	var slot_rule: Dictionary = {}
	for rule in Array(Dictionary(config).get("string_write_rules", [])):
		if Array(Dictionary(rule).get("domain_prefixes", [])).has(SLOT_DOMAIN):
			slot_rule = rule
	_ok("ui.vnSlot. 자수 규칙 행 실재", not slot_rule.is_empty())
	_ok("ui.vnSlot. = 1줄", int(slot_rule.get("max_lines", -1)) == 1, str(slot_rule))
	_ok("ui.vnSlot. = 전각 13", int(slot_rule.get("max_chars_full", -1)) == 13, str(slot_rule))
	_ok("ui.vnSlot. 값 출처 명기(대장 밖)",
		String(slot_rule.get("source", "")).contains("140px"), String(slot_rule.get("source", "")))
	_ok("ui.vnSlot. V7 도메인 편입",
		Array(Dictionary(config).get("v7_domains", [])).has(SLOT_DOMAIN))
	# ── `act_vn.json` 배열 스펙 (총괄 판정 IMPL-257 ① 부속) ──
	# 스펙을 지우면 V1 은 **그대로 통과한다** — 검사가 죽는 게 아니라 볼 것이 없어질 뿐이다
	# (돌연변이 M18 미검출로 실측). 같은 값 도메인이 표에서는 차단되고 구조에서는 새던
	# 비대칭을 닫은 것이 이 스펙이므로, 스펙의 실재를 검사가 대신 지킨다.
	var act_spec: Dictionary = Dictionary(Dictionary(config).get("structures", {})) \
		.get("act_vn.json", {}).get("arrays", {}).get("entries", {}).get("required", {})
	_ok("act_vn entries 스펙 실재", not act_spec.is_empty())
	_ok("act_vn act 범위 강제", String(act_spec.get("act", "")) == "int:1,4", str(act_spec))
	# **`enum_optional` 이 정본의 이행이다** — D12 v1.4 §5.4 가 "미지정 = calm"과 폴백 사슬을
	# 명문하므로 인스턴스 공란은 빌드 실패가 아니라 폴백 개시다(총괄 판정 IMPL-269 ①).
	# `enum` 으로 되돌리면 기계가 정본보다 엄해진다.
	_ok("act_vn tone 도메인 강제(공란 허용)",
		String(act_spec.get("tone", "")) == "enum_optional:calm,tense", str(act_spec))
	_ok("act_vn order 범위 강제", String(act_spec.get("order", "")) == "int:1,9", str(act_spec))
	# ── 언어 열 등재 + V7 어휘 대장 (총괄 판정 ④ · 21차) ──
	#
	# **여기가 "등재만 하면 통과만 찍는다"의 방어 자리다.** 열 등재는 V3·V7 을 죽이지 않고
	# **보는 범위만** 넓히므로, 되돌려도 두 검사는 녹색으로 계속 돈다 — 종료코드가
	# 구분하지 못하는 자리가 `vnChoice.` 규칙 행과 같다.
	var language_columns: Array = Array(Dictionary(config).get("string_language_columns", []))
	_ok("언어 열 등재 = 표 헤더 (ko·en·ja)", language_columns == LANGUAGE_COLUMNS_EXPECTED,
		str(language_columns))
	# 설정과 실물 표의 **양방향** 대조 — 열을 늘리고 등재를 잊거나 그 반대가 조용히 성립한다.
	var header: Array = _strings_header()
	_ok("표 헤더 = key + 등재 언어", header == ([StringTable.KEY_COLUMN] + language_columns),
		"header=%s config=%s" % [str(header), str(language_columns)])
	# 어휘 목록은 **언어별**이다. 국문 목록 하나로는 일문 발화 도메인에서 통과만 찍는다
	# (내러티브 4차 §6-E — `リール`·`スピン`·`ホールド` 가 가타카나형 금칙 후보다).
	var terms: Dictionary = Dictionary(config).get("v7_terms", {})
	_ok("v7 어휘 = 언어별 대장", terms.size() == language_columns.size(), str(terms.keys()))
	var korean_terms: Array = Array(terms.get("ko", []))
	_ok("v7 국문 어휘 비공란", korean_terms.size() >= 6, str(korean_terms.size()))
	for language in language_columns:
		var list: Array = Array(terms.get(language, []))
		_ok("v7 어휘 등재: %s" % language, terms.has(language))
		# 계수를 묶어 둔다 — 한 언어만 비면 그 언어에서 검사가 사실상 꺼진다.
		_ok("v7 어휘 계수 일치: %s" % language, list.size() == korean_terms.size(),
			"%d vs %d" % [list.size(), korean_terms.size()])
	# 라틴 어휘의 단어 경계 판정 — 부분 문자열로 되돌리면 `threshold` 가 `hold` 로 걸려
	# 경고가 소음이 되고, 읽히지 않는 경고는 없는 것과 같다.
	_ok("V7 단어 경계 판정 실재", source.contains("func _contains_term("))
	_ok("V7 단어 문자 판정 실재", source.contains("func _is_word_char("))
	_ok("V7 = 경고형 유지 (불변규칙 7)", not source.contains('_warn("V7") and _fail("V7"'))
	# V7S = **검사기 자신의 판정 논리** 자기 검사(차단형). 내용 판정은 경고형이라
	# 소음이 늘어도 종료코드가 녹색인데(돌연변이 F3 실측), 판정 논리의 고장은 기계 사안이다.
	_ok("V7S 자기 검사 정의 실재", source.contains("func _run_v7_self_test("))
	_ok("V7S 자기 검사 등록(호출) 실재", source.contains("\t_run_v7_self_test()"))
	_ok("V7S = 차단형 (경고 호출 잔존 0)", not source.contains('_warn("V7S"'))
	# ── `structure_ref_optional` 신설 (총괄 승인 · 22차 ⓔ) ──
	#
	# **선택화는 검사를 끄는 일과 한 걸음 차이다.** 공란을 통과시키는 분기를 넣었으므로
	# ⓐ필수형(`structure_ref`)이 여전히 살아 있고 ⓑ선택형도 **오타는 잡는지**를 함께 건다.
	# 둘 중 하나만 보면 "공란도 통과, 오타도 통과"가 조용히 성립한다.
	_ok("structure_ref 필수형 판정 잔존", source.contains('if type_spec == "structure_ref":'))
	_ok("structure_ref_optional 판정 실재",
		source.contains('if type_spec == "structure_ref_optional":'))
	_ok("structure_ref_optional 도 미등재 참조는 차단",
		source.contains('if type_spec == "structure_ref_optional":')
		and source.split('if type_spec == "structure_ref_optional":')[1] \
			.split("return 1")[0].contains('_fail("V2"'),
		"공란만 통과해야 하고 오타는 걸려야 한다")
	_ok("V1 타입 열거에 선택형 등재", source.contains('"structure_ref_optional"'))
	# 선택화한 두 열이 실제로 선택형인가 (설정 쪽) — 한 열만 풀려도 개막 비트가 서지 않는다
	var beat_columns: Dictionary = Dictionary(Dictionary(config).get("tables", {})) \
		.get("vn_beats.csv", {}).get("columns", {})
	_ok("vn_beats.axis_id = 선택형 FK",
		String(beat_columns.get("axis_id", "")) == "fk_optional:relation_axes.csv",
		str(beat_columns.get("axis_id", "")))
	_ok("vn_beats.stage_id = 선택형 구조 참조",
		String(beat_columns.get("stage_id", "")) == "structure_ref_optional",
		str(beat_columns.get("stage_id", "")))
	# 슬롯은 **필수로 남는다** — 슬롯 없는 비트는 어디에도 서지 않으므로 공란이 정당할 수 없다.
	_ok("vn_beats.slot_id = 필수 FK 유지",
		String(beat_columns.get("slot_id", "")) == "fk:vn_slots.csv",
		str(beat_columns.get("slot_id", "")))
	# ── 저장 루트 훅 전수 (25차 · 차단급) ──
	#
	# **실피해가 먼저 있었다** — 게이트가 실 프로필의 진행 세이브를 지우고 백업을 덮었다.
	# 훅을 만든 것만으로는 재발이 막히지 않는다: **한 하네스가 부르지 않으면 그 하네스가
	# 실 프로필을 다시 지운다.** 그러므로 "세이브·옵션·세션을 만지는 하네스는 전부 훅을
	# 탄다"를 계수로 못박는다. 새 스위트를 추가하는 사람이 이 축에서 먼저 걸린다.
	var save_touching: Array = []
	var hooked: Array = []
	for path in _test_sources():
		var harness := FileAccess.get_file_as_string(String(path))
		# 세이브 루트에 닿는 형태 — 세션 생성도 포함한다(`setup()` 이 옵션을 적재한다).
		var touches := harness.contains("SaveManager.") or harness.contains("RunSession.new()") \
			or harness.contains("OptionsStore.new()") or harness.contains("save_progress(")
		if not touches:
			continue
		save_touching.append(String(path).get_file())
		if harness.contains("SaveManager.use_test_root()"):
			hooked.append(String(path).get_file())
	_ok("㉑ 세이브 접촉 하네스 수집", save_touching.size() >= 10, str(save_touching.size()))
	_ok("㉑ 전 하네스가 격리 훅을 탄다", hooked.size() == save_touching.size(),
		"미훅 = %s" % str(_missing_from(save_touching, hooked)))
	# 실기 루트를 세우는 곳은 **앱 부팅 한 곳뿐**이어야 한다 — 하네스가 실기 루트를
	# 부르면 훅이 있으나 마나다.
	for path in _test_sources():
		# **이 검사기 자신은 제외한다** — 금지 문자열을 대장에 적어야 하므로 필연적으로
		# 그것을 담고 있고, 자기를 세면 항상 자기가 걸린다(GLYPH 잠재 원도 대장 전례).
		if String(path) == UISCR_SOURCE:
			continue
		var harness := FileAccess.get_file_as_string(String(path))
		_ok("㉑ 하네스가 실기 루트를 부르지 않는다: %s" % String(path).get_file(),
			not harness.contains("use_live_root()"))
	# **복구 경로까지 함께 사라지는 형태를 못박는다 (총괄 증보 · 내러티브 7차 실측).**
	# 재발화가 `progress.json` 과 `progress.bak.json` 을 **함께** 덮었다 — 1차와 복구가
	# 동시에 소진되면 가드는 탐지만 하고 되돌릴 것이 없다. 그래서 격리가 프로필 파일
	# **전부**를 덮는지, 백업 경로도 같은 루트를 타는지 값으로 확인한다.
	var isolated := SaveManager.progress_path(2)
	var isolated_backup := SaveManager.backup_path(2)
	var isolated_snapshot := SaveManager.snapshot_path(2)
	for pair in [["진행", isolated], ["백업", isolated_backup], ["스냅숏", isolated_snapshot]]:
		_ok("㉑ %s 경로가 격리 루트 안" % pair[0],
			String(pair[1]).begins_with(SaveManager.TEST_ROOT), String(pair[1]))
	# 세 파일이 서로 달라야 한다 — 겹치면 한 번의 저장이 복구본을 덮는다(정본 규약).
	_ok("㉑ 진행·백업·스냅숏 경로 상이", SaveManager.paths_are_distinct()
		and isolated != isolated_backup and isolated != isolated_snapshot)
	var boot := FileAccess.get_file_as_string("res://ui/flow/app_root.gd")
	_ok("㉑ 앱 부팅이 실기 루트를 세운다", boot.contains("SaveManager.use_live_root()"))
	# 기본값 부재가 방어의 핵이다 — 상수 기본값이 생기면 미호출이 조용해진다.
	var manager := FileAccess.get_file_as_string("res://core/save/save_manager.gd")
	_ok("㉑ 저장 루트 기본값 부재", manager.contains('static var _root: String = ""'),
		"기본값이 서면 훅 미호출이 소리를 잃는다")
	_ok("㉑ 미설정 시 경고", manager.contains('push_error("SaveManager: save root unset'))
	# 옵션 파일도 같은 루트를 탄다 — 21차에 실 옵션 파일을 쓴 축이 있었다
	var store := FileAccess.get_file_as_string("res://ui/flow/options_store.gd")
	# **계수로 본다** — 호출이 3곳(존재 확인·읽기·쓰기)이라 한 곳만 훅 밖으로 빼도
	# 문자열은 남는다(돌연변이 J4 초판 미검출 · H7 과 같은 형태).
	# 주석 행은 세지 않는다 — 문서 주석에도 같은 이름이 나온다(23차 상용한자 파서와 같은 함정:
	# **주석은 데이터가 아니다**. 그때는 내 계수기가 헤더 산문의 한자를 셌다).
	_ok("㉑ 옵션 경로 훅 경유 = 3곳",
		_count_of_code(store, "SaveManager.options_path()") == 3,
		str(_count_of_code(store, "SaveManager.options_path()")))
	_ok("㉑ 옵션 경로 상수 직참조 잔존 0", not store.contains("SaveManager.OPTIONS_PATH"))
	_ok("㉑ 옵션 경로 리터럴 우회 잔존 0", not store.contains('"user://options.json"'),
		"훅 밖 리터럴은 실 옵션 파일을 쓴다")

	# ── G4W 검사 실재 (게이트 G-4 · 23차) ──
	#
	# **스위트는 자기 단언의 삭제를 스스로 잡지 못한다** — 단언을 `true` 로 바꾸면 그 스위트는
	# 그대로 녹색이다(돌연변이 H7 미검출로 실측). 검증기 검사에 대해 이미 하고 있는 일을
	# 스위트에도 한다: 핵심 단언의 실재를 **다른 스위트**가 본다.
	var g4w_source := FileAccess.get_file_as_string(G4W_SOURCE)
	_ok("G4W 원본 적재", not g4w_source.is_empty(), G4W_SOURCE)
	# **계수로 본다.** 문자열 실재만 보면 두 대장(키 대장·도메인 대장) 중 한쪽의 단언을
	# 지워도 다른 쪽이 남아 통과한다 — 실측으로 확인했다(돌연변이 H7 초판 미검출).
	# ANCH 짝 목록을 정확 계수로 못박은 것과 같은 이유다.
	_ok("G4W 랩 대장 autowrap 단언 = 2건 (키 대장 + 도메인 대장)",
		_count_of(g4w_source, "consumer.contains(\"autowrap_mode\")") == 2,
		str(_count_of(g4w_source, "consumer.contains(\"autowrap_mode\")")))
	for assertion in [
			"func _self_test(",                        # 측정기 자기 검사
			"func _coverage_accounting(",              # 판정 밖 키 0
			"func _narrow_slot_inventory(",            # 정밀도 경계 공시
			"_number_after_from(",                     # 대장 값 ↔ 원본 선언 묶음
		]:
		_ok("G4W 단언 실재: %s" % assertion, g4w_source.contains(assertion))


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
const RECORDS_SCENE := "res://ui/hub/records_screen.tscn"


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
	# **공란 슬롯 가드** (총괄 판정 IMPL-263 ⑤). 슬롯 없이 세우는 경로가 정상인데
	# `vn_slot("")` 은 미상 슬롯으로 보고 `_load_ok` 를 내린다 — 데이터가 멀쩡한데 적재 실패로
	# 표시되는 것이 그 결함의 모습이다. **깨끗한 대장으로 따로 잰다**(앞선 축의 오염 배제).
	var fresh := GameData.new()
	_ok("가드 전제: 깨끗한 적재", fresh.load_all())
	var guard_screen := packed.instantiate() as Control
	var guard_session := _fresh_session(fresh)
	guard_screen.session = guard_session
	root.add_child(guard_screen)
	guard_screen.bind(guard_session, {
		"vn_id": "", "slot_id": "", "line_keys": ["vn.act1.beat01"],
	})
	_ok("공란 슬롯으로 세워도 적재 상태 불변", fresh.is_ok())
	root.remove_child(guard_screen)
	guard_screen.free()


# ── ⑱ 막 VN 표시 소비부 (총괄 판정 IMPL-263 ① — 차단급 결선) ──
#
# **결함의 성격이 축의 형태를 정한다.** 데이터는 완전하고 화면도 멀쩡했는데 **아무도 넘기지
# 않아서** 75라인이 게임에서 도달 불가였다. 그런 결함은 데이터 검사·화면 검사가 각자 통과하는
# 사이로 빠져나가므로, 축은 **발화 → 페이로드 → 실화면 → 도달**을 한 줄로 꿰어야 한다.
#
# 그리고 `tone` 미전달은 **조용하다** — 화면이 죽는 게 아니라 tense 3건이 BGM-09(일상)로
# 떨어질 뿐이다. 그래서 관측 지점을 라벨이 아니라 **BGM 발화 기록**에 둔다.
func _act_vn_consumption(data: GameData) -> void:
	# ── ⓐ 커리어 개시 = 1막 발화 · 페이로드 실체 ──
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	_ok("커리어 개시 = 1막 표시 대기", Array(session.outgame.act_vn_pending) == ["vn_act1"],
		str(session.outgame.act_vn_pending))
	var payload := session.take_brief_payload("RACE-01")
	_ok("페이로드 발행", not payload.is_empty())
	_ok("발행 슬롯 = 투어 브리핑", String(payload.get("slot_id", "")) == "vnslot_tour_brief")
	var lines: Array = payload.get("line_keys", [])
	_ok("1막 12라인 동반", lines.size() == 12, str(lines.size()))
	# 라인별 화자 사전이어야 한다 — 문자열 배열로 넘기면 화자가 전건 기본값으로 접힌다.
	var dict_lines := 0
	for line in lines:
		if typeof(line) == TYPE_DICTIONARY and Dictionary(line).has("speaker_key"):
			dict_lines += 1
	_ok("전 라인 = 화자 사전", dict_lines == lines.size(), "%d/%d" % [dict_lines, lines.size()])
	_ok("정조 동반", String(payload.get("tone", "")) == "calm", str(payload.get("tone", "")))
	_ok("소비 후 대기 0", Array(session.outgame.act_vn_pending).is_empty())
	_ok("재호출 = 빈 사전", session.take_brief_payload("RACE-01").is_empty())

	# ── ⓑ 실화면 도달 — 75라인 중 1막 12라인이 실제로 그려지는가 ──
	var screen := _mount_payload(data, session, payload)
	_ok("실화면 1라인 = 데이터 문면",
		(screen.get_node("%BodyLabel") as Label).text == data.strings.text("vn.act1.beat01"),
		(screen.get_node("%BodyLabel") as Label).text)
	_ok("calm = BGM-09", _cue_count(session, "BGM-09") == 1, str(session.audio.fired))
	_ok("calm ≠ BGM-10", _cue_count(session, "BGM-10") == 0)
	var drawn := 1
	for step in range(11):
		screen._advance()
		if (screen.get_node("%BodyLabel") as Label).text != "":
			drawn += 1
	_ok("12라인 전건 문면 실재", drawn == 12, str(drawn))
	_ok("마지막 라인 = beat12",
		(screen.get_node("%BodyLabel") as Label).text == data.strings.text("vn.act1.beat12"))
	# 선택 4지점은 페이로드가 vn_id·라인 열을 넘기는 순간 자동 도달한다 — 그 자동성을 본다.
	# **관측 지점이 바뀌었다**: 씬 실물이 서기 전에는 '생략 기록'이 도달의 증거였고, 선 뒤에는
	# **오버레이가 실제로 떴는가**가 증거다(생략은 이제 0이어야 한다 — 주력 11차 IMPL-290).
	screen._advance()
	var auto_overlay := screen.find_child(VN_CHOICE_OVERLAY, true, false) as Control
	_ok("선택 지점 자동 도달", auto_overlay != null and auto_overlay.visible)
	_ok("자동 도달 = 생략 0", Array(screen.choice_omissions).is_empty(),
		str(screen.choice_omissions))
	_ok("아카이브 등재", session.narrative.vn_seen.has("vn_act1"))
	# **표제 표가 낡으면 기계가 잡는다.** 리터럴 표를 쓴 것은 V6 가 조립 키를 보지 못해서이고,
	# 그 대가(7번째 막이 조용히 폴백으로 떨어짐)를 이 축이 받는다(IMPL-278 회수분 결선).
	var titles: Dictionary = load("res://ui/hub/records_screen.gd").ACT_VN_TITLES
	var missing_title := 0
	var missing_key := 0
	for entry in data.act_vn_entries():
		var vn_id := String(Dictionary(entry).get("id", ""))
		if not titles.has(vn_id):
			missing_title += 1
			continue
		if not data.strings.has_key(String(titles[vn_id])):
			missing_key += 1
	_ok("막 VN 전건 표제 표 등재", missing_title == 0, "missing=%d" % missing_title)
	_ok("표제 키 전건 실재", missing_key == 0, "missing=%d" % missing_key)
	_ok("표제 = 슬롯 유형 표기 아님",
		data.strings.text(String(titles["vn_act1"])) != data.strings.text("ui.vnSlot.tourBrief"))
	_release_vn(screen)

	# ── ⓒ tense 막 = BGM-10 (정조 미전달의 조용한 실패를 잡는 자리) ──
	var tense_session := RunSession.new()
	tense_session.setup(data)
	tense_session.begin_career(2)
	tense_session.outgame.act_vn_pending.clear()
	tense_session.outgame.milestones["milestone_first_tour_win"] = true
	tense_session.outgame.latch_narrative_act()
	var tense_payload := tense_session.take_brief_payload("RACE-01")
	_ok("3막 정조 = tense", String(tense_payload.get("tone", "")) == "tense")
	var tense_screen := _mount_payload(data, tense_session, tense_payload)
	_ok("tense = BGM-10", _cue_count(tense_session, "BGM-10") == 1, str(tense_session.audio.fired))
	_ok("tense ≠ BGM-09", _cue_count(tense_session, "BGM-09") == 0)
	_release_vn(tense_screen)

	# ── ⓓ 정조 공란 = 폴백 사슬 (enum_optional 전환의 실동작) ──
	var blank_session := RunSession.new()
	blank_session.setup(data)
	blank_session.begin_career(2)
	var blank_payload := blank_session.take_brief_payload("RACE-01")
	blank_payload["tone"] = ""
	var blank_screen := _mount_payload(data, blank_session, blank_payload)
	# `vnslot_tour_brief` 행의 tone = calm 이므로 폴백이 거기서 잡힌다.
	_ok("공란 = 슬롯 폴백(BGM-09)", _cue_count(blank_session, "BGM-09") == 1,
		str(blank_session.audio.fired))
	_release_vn(blank_screen)

	# ── ⓔ 2건 동시 래치 = 사슬 (앞 VN 의 next 가 뒤 VN) ──
	var chain_session := RunSession.new()
	chain_session.setup(data)
	chain_session.begin_career(2)
	chain_session.outgame.act_vn_pending.clear()
	chain_session.outgame.milestones["milestone_first_podium"] = true
	chain_session.outgame.milestones["milestone_first_tour_win"] = true
	chain_session.outgame.latch_narrative_act()
	var chain := chain_session.take_brief_payload("RACE-01")
	_ok("사슬 첫 VN = 2막", String(chain.get("vn_id", "")) == "vn_act2", str(chain.get("vn_id", "")))
	_ok("사슬 첫 VN 의 next = NAR-01", String(chain.get("next", "")) == "NAR-01")
	var tail: Dictionary = chain.get("next_payload", {})
	_ok("사슬 둘째 VN = 3막", String(tail.get("vn_id", "")) == "vn_act3", str(tail.get("vn_id", "")))
	_ok("사슬 끝 = 원래 목적지", String(tail.get("next", "")) == "RACE-01")

	# ── ⓕ 실 라우팅 — 개러지 출발이 막 VN 을 경유하는가 ──
	SaveManager.configure(data)
	var depart_session := RunSession.new()
	depart_session.setup(data)
	depart_session.begin_career(2)
	# **개막을 먼저 소진시킨다 — 실 흐름과 같게.** 커리어 개시 경로(SYS-02)가 시즌 1 개막을
	# 띄우므로 첫 개러지 이탈 시점에는 이미 발생 대장에 있다. 이 축의 대상은 막 VN 경유이고,
	# 개막이 앞에 서 있으면 그 사슬의 첫 칸이 개막이 되어 다른 것을 재게 된다(24차 순서 변경분).
	var seed_open := depart_session.season_open_payload("RACE-01")
	if not seed_open.is_empty():
		depart_session.narrative.trigger_vn(String(seed_open["vn_id"]),
			String(seed_open["slot_id"]), false)
	var garage := _mount(GARAGE_SCENE, depart_session)
	var routed: Array = []
	garage.navigate.connect(func(target: String, route_payload: Dictionary): routed.append([target, route_payload]))
	garage._on_depart()
	_ok("대기 有 → NAR-01 경유", routed.size() == 1 and String(routed[0][0]) == "NAR-01", str(routed))
	_ok("경유 페이로드 = 막 VN",
		routed.size() == 1 and String(Dictionary(routed[0][1]).get("vn_id", "")) == "vn_act1")
	# 대기가 없으면 사슬이 접혀 그대로 출발한다 — 분기를 두지 않은 것이 계약이다.
	routed.clear()
	garage._on_depart()
	_ok("대기 無 → RACE-01 직행", routed.size() == 1 and String(routed[0][0]) == "RACE-01", str(routed))
	_release_vn(garage)

	# ── ⓗ 브리핑 사슬 = 막 VN → 재회 브리핑 (총괄 판정 IMPL-289 ② 사슬 연속 재생) ──
	var brief := RunSession.new()
	brief.setup(data)
	brief.begin_career(2)
	var alta_slot := Array(brief.season.calendar).find("stage_alta_ridge")
	_ok("알타 리지 캘린더 실재(사슬 축)", alta_slot >= 0, str(brief.season.calendar))
	if alta_slot >= 0:
		brief.season.tour_slot = alta_slot + 1
		brief.outgame.act_vn_pending.clear()
		brief.outgame.milestones["milestone_first_podium"] = true
		brief.outgame.latch_narrative_act()
		var head := brief.take_brief_payload("RACE-01")
		# **순서가 판정이다** — 막 VN 이 먼저다(이월 대신 연속 재생을 택한 판정의 실체).
		_ok("사슬 머리 = 막 VN", String(head.get("vn_id", "")) == "vn_act2",
			String(head.get("vn_id", "")))
		_ok("사슬 머리의 next = NAR-01", String(head.get("next", "")) == "NAR-01")
		var beat: Dictionary = head.get("next_payload", {})
		_ok("사슬 꼬리 = 재회 비트",
			String(beat.get("vn_id", "")) == "vnbeat_reunion_alta", String(beat.get("vn_id", "")))
		_ok("사슬 꼬리의 next = 원래 목적지", String(beat.get("next", "")) == "RACE-01")
		_ok("비트 발행 슬롯 = 투어 브리핑",
			String(beat.get("slot_id", "")) == "vnslot_tour_brief")
		_ok("비트 5라인 동반", Array(beat.get("line_keys", [])).size() == 5,
			str(Array(beat.get("line_keys", [])).size()))
		# 정조 공란 = 슬롯 폴백(브리핑 = calm). 납품 판단을 데이터가 그대로 이고 있다.
		_ok("비트 정조 = 공란(슬롯 폴백)", String(beat.get("tone", "")) == "",
			String(beat.get("tone", "")))
		# 실화면에 세워 문면이 실제로 그려지는지 — 키가 없으면 화면은 키 원문을 그린다.
		var beat_screen := _mount_payload(data, brief, beat)
		_ok("비트 1라인 = 데이터 문면",
			(beat_screen.get_node("%BodyLabel") as Label).text
				== data.strings.text("vn.reunion.beat01"),
			(beat_screen.get_node("%BodyLabel") as Label).text)
		# **비트가 축을 민다** — 판별이 좁혀졌으므로(19차) 표 실재가 계수의 근거다.
		_ok("비트 발생 = 재회 축 +1",
			int(brief.outgame.relation_counters.get("relation_reunion", 0)) == 1,
			str(brief.outgame.relation_counters))
		_release_vn(beat_screen)
		# 단계가 오르면 이 비트는 더 이상 서지 않는다 — 조건 3열이 실제로 무는가.
		brief.outgame.relation_stages["relation_reunion"] = 1
		_ok("단계 1 = 비트 미발동", brief._pending_brief_beats().is_empty(),
			str(brief._pending_brief_beats().size()))
		brief.outgame.relation_stages["relation_reunion"] = 0
		# 무대가 다르면 서지 않는다 — 무대 조건도 실제로 무는가.
		brief.season.tour_slot = 1
		_ok("타 무대 = 비트 미발동", brief._pending_brief_beats().is_empty(),
			brief.season.current_stage_id())
		# **판별의 양성 형태가 실제로 좁히는가** (19차 정밀화 · 총괄 판정 IMPL-289 ③).
		# 16차 형태("`act_vn` 이 아니면 비트")와 현행("`vn_beats` 에 있으면 비트")은 **현행
		# 데이터에서 결과가 같다** — 두 표 어디에도 없는 VN 이 브리핑 슬롯을 타는 경우만 갈린다.
		# 그 경우를 만들어 본다: 갈리지 않으면 정밀화가 이름만 남는다.
		var stray := RunSession.new()
		stray.setup(data)
		stray.begin_career(2)
		stray.season.tour_slot = alta_slot + 1
		var stray_screen := _mount_payload(data, stray, {
			"vn_id": "vn_not_in_any_table", "slot_id": "vnslot_tour_brief",
			"line_keys": ["vn.reunion.beat01"], "tone": "calm",
		})
		_ok("미상 VN 은 브리핑 슬롯을 타도 축을 밀지 못한다",
			int(stray.outgame.relation_counters.get("relation_reunion", 0)) == 0,
			str(stray.outgame.relation_counters))
		_release_vn(stray_screen)

	# ── ⓖ 재회 축 오염 없음 (IMPL-252 자기 결함 교정 실측) ──
	var alta := RunSession.new()
	alta.setup(data)
	alta.begin_career(2)
	var slot := Array(alta.season.calendar).find("stage_alta_ridge")
	_ok("알타 리지 캘린더 실재", slot >= 0, str(alta.season.calendar))
	if slot >= 0:
		alta.season.tour_slot = slot + 1
		_ok("알타 리지 투어 성립", alta._is_alta_ridge_tour())
		var alta_screen := _mount_payload(data, alta, alta.take_brief_payload("RACE-01"))
		_ok("막 VN 은 재회 비트가 아니다",
			int(alta.outgame.relation_counters.get("relation_reunion", 0)) == 0,
			str(alta.outgame.relation_counters))
		_release_vn(alta_screen)


func _mount_payload(data: GameData, session: RunSession, payload: Dictionary) -> Control:
	var packed := load(VN_SCENE) as PackedScene
	var screen := packed.instantiate() as Control
	screen.session = session
	root.add_child(screen)
	screen.bind(session, payload)
	return screen


# ── ⑰ VN 선택 지점 (D04 §5.3 · 총괄 판정 IMPL-257) ──
#
# 축이 **두 상태 모두**인 것이 요점이다. 오버레이 씬 노드는 주력 몫이라 지금은 없고,
# 없는 상태에서 지점에 닿으면 화면이 멈추면 안 된다(생략). 노드가 선 뒤에는 지점이 실제로
# 떠야 한다. 한쪽만 검사하면 **다른 쪽이 조용히 죽는다** — 특히 "지금 없다"는 이유로 부재
# 경로만 보면, 주력이 노드를 세운 날 결선이 끊긴 것을 아무도 모른다.
const CHOICE_VN_ID := "vn_act3"
const CHOICE_ID := "vnchoice_act3_corner"
# 씬 계약의 이름 — 화면 코드와 같은 문자열을 두 곳에 적지 않는다.
const VN_CHOICE_OVERLAY := "ChoiceOverlay"
const VN_CHOICE_LIST := "ChoiceList"
# 앵커 라인(`beat11`) 앞뒤 3라인 — 지점 축과 배치 축이 같은 열을 쓴다.
const CHOICE_LINES: Array = [
	{"speaker_key": "ui.vn.speakerMarta", "text_key": "vn.act3.beat10"},
	{"speaker_key": "ui.vn.speakerMarta", "text_key": "vn.act3.beat11"},
	{"speaker_key": "ui.vn.speakerVane", "text_key": "vn.act3.beat12"},
]


func _vn_choice_point(data: GameData) -> void:
	var lines: Array = CHOICE_LINES
	# ── ⓐ 노드 부재 = 지점 생략 · 진행 계속 (실물을 떼어 만든 상태) ──
	# 씬에 실물이 선 뒤에도 이 축은 살아 있어야 한다 — 노드를 지우거나 이름을 바꾼 회차에
	# 화면이 그 자리에서 멈추지 않는다는 계약은 그대로다.
	var absent := _mount_vn(data, lines, false)
	if absent == null:
		return
	_ok("전제: 부재 축이 실제로 부재다",
		absent.find_child(VN_CHOICE_OVERLAY, true, false) == null)
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
	var overlay := screen.find_child(VN_CHOICE_OVERLAY, true, false) as Control
	var list := screen.find_child(VN_CHOICE_LIST, true, false) as Container
	# **씬 실물 실재를 먼저 세운다** — 없으면 아래 단언이 null 접근으로 죽어 진단이 사라진다.
	_ok("전제: 씬에 실물 오버레이 2노드 실재", overlay != null and list != null)
	if overlay == null or list == null:
		_release_vn(screen)
		return
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
	# **실물 노드가 씬에 섰다**(주력 11차 IMPL-290) — 그래서 축의 방향이 뒤집혔다.
	# 종전은 부재가 실물이고 실재가 스텁이었다. 지금 스텁을 계속 주입하면 `find_child` 가
	# 트리 순서상 **씬 실물을 먼저 집어** 검사가 스텁을 안 보고, 반대로 부재 축은 실물 때문에
	# 성립하지 않는다(실측: 노드를 세운 직후 ⓐ 3검사 FAIL — 전환을 감지했다).
	# 그래서 **부재는 실물을 떼어 만든다.** 두 축 모두 실물 계약을 본다.
	if not with_overlay:
		var real := screen.find_child(VN_CHOICE_OVERLAY, true, false)
		if real != null:
			real.get_parent().remove_child(real)
			real.free()
	root.add_child(screen)
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


# ── ⑰-ⓓ 선택 오버레이 배치 (씬 계약 · 발주 배치 구속 — IMPL-290) ──
#
# **살아 있는 것과 누를 수 있는 것은 다르다.** 지점 위 스킵 생존은 `visible`·`disabled` 로
# 이미 보고 있지만, 오버레이가 스킵 위에 겹치면 시각·입력 양쪽이 막히면서도 그 두 속성은
# 그대로다. 그래서 **실 rect 교집합**으로 본다(주력 10차 콜아웃 축과 같은 형태).
#
# 정렬이 끝난 프레임에서 잰다 — 오버레이는 내용이 크기를 정하는 PanelContainer 라
# 지점을 연 프레임에는 0 크기이고, 그때 재면 "안 가린다"가 0==0 으로 성립한다.
func _vn_choice_geometry(data: GameData) -> void:
	var screen := _settle_choice
	if screen == null:
		_ok("전제: 배치 측정용 VN 화면 실재", false)
		return
	var overlay := screen.find_child(VN_CHOICE_OVERLAY, true, false) as Control
	var list := screen.find_child(VN_CHOICE_LIST, true, false) as Container
	_ok("전제: 씬 실물 2노드", overlay != null and list != null)
	if overlay == null or list == null:
		_unmount(screen)
		_settle_choice = null
		return
	_ok("전제: 지점이 열려 있다", overlay.visible)
	_ok("전제: 오버레이가 실 크기를 가진다", overlay.size.x > 0.0 and overlay.size.y > 0.0,
		str(overlay.size))
	var orect := overlay.get_global_rect()
	var skip_hit := orect.intersection(
		(screen.get_node("%SkipButton") as Control).get_global_rect()).get_area()
	_ok("오버레이 — 스킵 불가림", skip_hit <= 0.0, "겹침=%.1fpx²" % skip_hit)
	var say_hit := orect.intersection(
		(screen.get_node("DialoguePanel") as Control).get_global_rect()).get_area()
	_ok("오버레이 — 대사창 불가림", say_hit <= 0.0, "겹침=%.1fpx²" % say_hit)
	_ok("오버레이 — 화면 내",
		orect.position.x >= -0.5 and orect.position.y >= -0.5
			and orect.end.x <= CANVAS.x + 0.5 and orect.end.y <= CANVAS.y + 0.5, str(orect))
	_ok_centered_h("오버레이", overlay)
	# E05 = **1줄** 14전각. 자수는 데이터 층(V3·STRF)이 보고, 렌더가 1줄인지는 여기서만 보인다.
	var body_font := float(data.param("param_font_size_body"))
	var multiline := 0
	for index in range(list.get_child_count()):
		if (list.get_child(index) as Control).size.y > body_font * 2.5:
			multiline += 1
	_ok("선택지 버튼 = 1줄 높이", multiline == 0, "2줄 이상=%d" % multiline)
	_unmount(screen)
	_settle_choice = null


# ── ⑱ VN 마지막 라인의 진행 키 (실기 발견 결함 — 주력 11차 IMPL-292) ──
#
# **화면을 이탈시키는 입력은 자기 뒤처리를 못 한다.** `_advance()` 가 마지막 라인에서
# `go()` 를 부르면 라우터가 이 노드를 트리에서 내리고, 그 뒤에 `get_viewport()` 를 부르면
# null 이다 — 실기에서 그대로 터졌다(`Cannot call method 'set_input_as_handled' on a null
# value` · `vn_screen.gd` `_unhandled_key_input`). 헤드리스 단위 검사가 못 잡은 이유는
# `_advance()` 를 **직접 부르기** 때문이다: 입력 경로를 타지 않으면 그 줄에 도달하지 않는다.
#
# 관측 지점 = **입력 소비 표시**. 순서가 틀리면 그 호출 자체가 죽으므로 플래그가 서지 않는다.
# "라우팅됐는가"로는 못 본다 — 라우팅은 죽은 줄보다 **앞**에서 이미 일어난다.
func _vn_last_line_input(data: GameData) -> void:
	var session := _fresh_session(data)
	var screen := _mount_payload(data, session, {
		"vn_id": "", "slot_id": "",
		"line_keys": [{"speaker_key": "ui.vn.speakerMarta", "text_key": "vn.act1.beat02"}],
	})
	if screen == null:
		_ok("전제: VN 화면 실재", false)
		return
	# 라우터가 하는 일을 그대로 한다 — 이탈 신호에 화면을 내린다.
	var routed: Array = []
	screen.navigate.connect(func(target: String, _p: Dictionary):
		routed.append(target)
		if screen.get_parent() != null:
			root.remove_child(screen))
	# 진행 버튼이 키를 먼저 먹으면 `_unhandled_key_input` 에 도달하지 않는다 —
	# 실기에서 터진 문맥은 포커스가 그 버튼에 없던 프레임이었다.
	(screen.get_node("%AdvanceButton") as Button).release_focus()
	root.push_input(_key_event(KEY_SPACE))
	_ok("마지막 라인 = 화면 이탈", routed.size() == 1, str(routed))
	# **거동으로는 관측점이 없다.** 엔진 오류는 GDScript 에서 잡히지 않고, 입력 소비 플래그는
	# 리셋 창구가 없어 `is_input_handled()` 가 앞선 검사의 값을 물고 **항진명제**가 된다
	# (실측: 결함을 되돌린 상태에서도 true). 라우팅 여부로도 못 본다 — 라우팅은 죽는 줄보다
	# 앞에서 이미 끝난다. 그래서 **순서를 원문으로 단언한다**(ANCH·STRF 실재 축과 같은 형태).
	# 주석은 걷어내고 본다 — 주석에 같은 낱말이 있으면 순서 비교가 무의미해진다.
	var source := FileAccess.get_file_as_string(VN_SCREEN_SCRIPT)
	var head := source.find("func _unhandled_key_input(")
	_ok("전제: 입력 핸들러 실재", head >= 0)
	if head >= 0:
		var tail := source.find("\nfunc ", head + 1)
		var block := source.substr(head, (tail if tail > head else source.length()) - head)
		var code: Array[String] = []
		for line in block.split("\n"):
			if not String(line).strip_edges().begins_with("#"):
				code.append(String(line))
		var body := "\n".join(code)
		var mark := body.find("set_input_as_handled()")
		var adv := body.find("_advance()")
		_ok("이탈 입력 = 소비 표시가 진행보다 먼저", mark >= 0 and adv >= 0 and mark < adv,
			"mark=%d advance=%d" % [mark, adv])
	if screen.get_parent() != null:
		root.remove_child(screen)
	screen.queue_free()


# ── ⑲ 입력 소비 표시의 위치 — `godot/ui` 전역 (실기 크래시 재발 교정 · IMPL-299) ──
#
# **한 지점만 고치면 재발한다.** 같은 형태를 VN 에서 먼저 잡았는데(IMPL-292) 훑지 않아
# RACE-01 에 남았고, 사용자 실기에서 그대로 터졌다(`race_screen.gd:364` ·
# `Cannot call method 'set_input_as_handled' on a null value`). 그래서 축을 파일 하나가
# 아니라 **입력 핸들러 전역**으로 둔다.
#
# 규칙 = **소비 표시가 분기의 첫 동작이어야 한다.** 처리 여부는 분기 조건이 정하지 동작의
# 결과가 정하지 않는다. 앞에 호출이 오면 그 호출이 화면을 이탈시킨 순간 `get_viewport()` 가
# null 이 되고, 이 함수는 거기서 죽는다(라우팅은 이미 끝난 뒤라 겉으로는 멀쩡해 보인다).
#
# 관측점이 원문인 이유는 IMPL-292 와 같다 — 엔진 오류는 GDScript 에서 잡히지 않고
# `is_input_handled()` 는 리셋 창구가 없어 항진명제다.
const INPUT_HANDLERS := ["_input", "_unhandled_input", "_unhandled_key_input",
	"_shortcut_input", "_gui_input"]
const HANDLE_MARK := "get_viewport().set_input_as_handled()"


func _input_handled_ordering() -> void:
	var files: Array[String] = []
	_collect_gd("res://ui", files)
	_ok("전제: UI 스크립트 수집", files.size() > 10, "files=%d" % files.size())
	var scanned := 0
	var marks := 0
	var offenders: Array[String] = []
	for path in files:
		var source := FileAccess.get_file_as_string(path)
		if not source.contains(HANDLE_MARK):
			continue
		scanned += 1
		var lines := source.split("\n")
		var in_handler := false
		var prev_code := ""
		for raw in lines:
			var line := String(raw)
			var body := line.strip_edges()
			if line.begins_with("func "):
				in_handler = false
				for name in INPUT_HANDLERS:
					if line.begins_with("func %s(" % name):
						in_handler = true
				prev_code = ""
				continue
			if body.is_empty() or body.begins_with("#"):
				continue
			if in_handler and body == HANDLE_MARK:
				marks += 1
				if _is_call_statement(prev_code):
					offenders.append("%s: %s → 소비표시" % [path.get_file(), prev_code])
			prev_code = body
	_ok("전제: 소비 표시 지점 실재", marks > 0, "marks=%d" % marks)
	_ok("전제: 스캔 대상 파일 실재", scanned > 0, "scanned=%d" % scanned)
	_ok("소비 표시가 호출보다 앞선다 (godot/ui 전역)", offenders.is_empty(),
		"위반 %d건: %s" % [offenders.size(), ", ".join(offenders)])


# 호출문인가 — 대입(` = `)·제어문·선언은 아니다. 이 판별이 좁으면 위반을 놓치고,
# 넓으면 대입까지 잡아 규칙이 과해진다.
func _is_call_statement(body: String) -> bool:
	if body.is_empty() or not body.ends_with(")"):
		return false
	for head in ["if ", "elif ", "while ", "for ", "return", "var ", "await ", "assert("]:
		if body.begins_with(head):
			return false
	if body.contains(" = "):
		return false
	return true


func _collect_gd(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_collect_gd(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


# ── ⑳ 마우스 클릭 경로 — 라우팅 전 화면 (사용자 실기 발견 · IMPL-301) ──
#
# **버튼이 화면에 있는 것과 눌리는 것은 다르다.** RACE-01 의 E08 3버튼은 `text` 와
# `disabled` 만 관리되고 `pressed` 연결이 0건이어서 키보드·패드로만 살아 있었다 —
# 마우스로는 죽어 있었고 사용자 실기가 그것을 잡았다. D09 §1.3 은 세 입력을 같은 조작
# 집합으로 두므로 한 경로만 사는 것은 규격 위반이다.
#
# 축을 화면 하나가 아니라 **라우팅 대장 전건**에 둔다 — 전수 감사에서 18화면은 결선돼
# 있었고 이 화면만 빠져 있었다. 다음에 어느 화면이 빠지든 여기서 걸린다.
#
# **면제는 명시 목록으로만.** 13차에 스킬 5슬롯이 결선되면서 **목록이 비었다** — 종전 사유
# ("인게임 소비부가 아직 없는 이월 트랙")는 해소됐고, 사유가 사라진 면제를 남겨 두면 그
# 화면이 다시 빠져도 검사가 통과한다. 상수는 남긴다(다음 면제의 자리이자, 넓히려면 이 줄을
# 함께 고쳐야 한다는 규율의 표지 — ANCH 면제 목록과 같은 축).
const CLICK_EXEMPT: Array[String] = []

func _mouse_click_paths(data: GameData) -> void:
	var routes: Dictionary = load(APP_ROOT_SCENE_SCRIPT).ROUTES
	_ok("전제: 라우팅 대장 실재", routes.size() >= 19, "routes=%d" % routes.size())
	# **화면마다 새 세션을 쓴다.** 하나를 공유하면 앞 화면이 1회성 상태를 소모해 뒤 검사가
	# 무너진다(실측: HUB-01 을 세우자 온보딩 팁 기록이 소모돼 ⑫ⓔ 축이 FAIL 했다).
	#
	# **다만 옵션 저장소는 세션 밖이다** — `OptionsStore` 는 `user://` 에 얹힌 전역이고
	# `mark_onboarding()` 이 즉시 디스크까지 쓴다. 새 세션으로는 격리되지 않으므로
	# 1회성 기록을 떠 두고 감사 뒤에 되돌린다(검사가 남의 검사를 깨뜨리지 않게 한다).
	var options := _fresh_session(data).options
	var onboarding_snapshot: Dictionary = options.onboarding_seen.duplicate()
	var audited := 0
	var buttons_seen := 0
	var dead: Array[String] = []
	for route in routes:
		var packed := load(String(routes[route])) as PackedScene
		if packed == null:
			dead.append("%s: 씬 로드 실패" % route)
			continue
		var session := _fresh_session(data)
		if route == "RACE-03":
			# 결과 화면은 살아 있는 엔진을 읽는다 — GP 를 열지 않으면 바인드가 중간에 끊긴다.
			session.begin_gp()
		var screen := packed.instantiate() as Control
		screen.session = session
		root.add_child(screen)
		screen.bind(session, _audit_payload(String(route), data))
		audited += 1
		var buttons: Array[BaseButton] = []
		_collect_buttons(screen, buttons)
		buttons_seen += buttons.size()
		for button in buttons:
			if CLICK_EXEMPT.has(String(button.name)):
				continue
			var signal_name := "toggled" if button.toggle_mode else "pressed"
			if button.get_signal_connection_list(signal_name).is_empty():
				dead.append("%s/%s(%s)" % [route, button.name, signal_name])
		root.remove_child(screen)
		screen.queue_free()
	options.onboarding_seen = onboarding_snapshot
	options.save_to_disk()
	_ok("전제: 전 화면 바인드 성립", audited == routes.size(),
		"%d/%d" % [audited, routes.size()])
	# 버튼이 0 이면 아래 단언이 공회전한다 — 계수를 먼저 세운다.
	_ok("전제: 감사 대상 버튼 실재", buttons_seen > 100, "buttons=%d" % buttons_seen)
	_ok("클릭 경로 — 전 화면 전 버튼", dead.is_empty(),
		"부재 %d건: %s" % [dead.size(), ", ".join(dead)])

	# ── 경로 등가: 마우스 클릭이 키보드·패드와 같은 결과를 내는가 (D09 §1.3) ──
	# 연결이 있는 것과 같은 일을 하는 것은 다르다 — ⑥축이 액션·키보드·패드 3경로를 보므로
	# 여기서 **네 번째 다리**를 같은 관측점(국면 이탈)으로 잇는다. 결과는 보지 않는다(불변규칙 5).
	var click_session := _fresh_session(data)
	var race := _mount(RACE_SCENE, click_session)
	if race == null:
		return
	var confirm := race.get_node("%E08Confirm") as Button
	_ok("마우스 — 전제: 확정 버튼 클릭 가능",
		not confirm.disabled and not confirm.get_signal_connection_list("pressed").is_empty())
	_ok("마우스 — 전제: T1 대기",
		race.engine.turn_phase == RaceTypes.TurnPhase.T1_SECTOR_OPEN,
		"phase=%d" % race.engine.turn_phase)
	confirm.pressed.emit()
	_ok("마우스 클릭 — 스핀 커밋 도달",
		race.engine.turn_phase != RaceTypes.TurnPhase.T1_SECTOR_OPEN,
		"phase=%d" % race.engine.turn_phase)
	_unmount(race)


# 바인드가 페이로드를 요구하는 화면만 최소분을 넘긴다 — 요구를 우회하는 것이 아니라
# 감사가 진단 대신 남의 push_error 를 뒤집어쓰지 않게 하는 것이다.
# ── ㉑ E08 스킬 슬롯 (D09 §3.2·§1.3 · 원격 20차 계약 §1.2 — 13차 결선) ──
#
# **화면이 표를 다시 읽지 않는다**가 계약의 핵심이므로, 축을 "라벨이 그려졌는가"가 아니라
# **"엔진 행에서 왔는가"** 에 둔다: 툴팁의 스킬명이 `skills.csv` 의 `name_key` 를 거친
# 문면과 일치하는지 본다. 화면이 이름을 자기 리터럴로 갖고 있으면 이 축이 깨진다.
#
# 활성화는 **경로마다 따로** 본다(IMPL-301 의 교훈 — 한 경로만 살아 있어도 화면은 정상처럼
# 보인다). 클릭 경로는 `pressed` 시그널로, 키보드 경로는 실 `InputEventKey` 로 들어간다.
func _skill_slots(data: GameData) -> void:
	var session := _fresh_session(data)
	var screen := _mount(RACE_SCENE, session)
	if screen == null:
		return
	# 전제 — 덱 2슬롯. 아웃게임 반입 경로가 아니라 **엔진 상태를 직접 세운다**:
	# 이 축이 보려는 것은 "화면이 엔진을 읽는가"이므로 반입 경로를 끼우면 관측이 흐려진다.
	screen.engine.deck = ["skill_sa1", "skill_sh1"]
	screen.engine.charge = 10
	screen._refresh_skill_slots()
	var slots: Array = screen.engine.skill_slots()
	_ok("전제: 덱 2슬롯이 창구에 선다", slots.size() == 2, "size=%d" % slots.size())
	var buttons: Array = screen._skill_buttons
	_ok("전제: 슬롯 버튼 5기", buttons.size() == 5, "count=%d" % buttons.size())
	if slots.size() < 2 or buttons.size() < 5:
		_unmount(screen)
		return
	# ⓐ 장착분 = 비용 병기 · 미확장분 = 잠금 (D09 §3.2)
	var cost0 := int(slots[0]["charge_cost"])
	_ok("슬롯 1 라벨에 비용 ◆n 병기",
		buttons[0].text.contains(str(cost0)), buttons[0].text)
	_ok("미확장 슬롯 3~5 = 잠금 표기",
		buttons[2].text == data.strings.text("ui.race.locked")
			and buttons[3].text == data.strings.text("ui.race.locked")
			and buttons[4].text == data.strings.text("ui.race.locked"),
		"%s / %s / %s" % [buttons[2].text, buttons[3].text, buttons[4].text])
	_ok("미확장 슬롯은 상시 비활성", buttons[2].disabled and buttons[3].disabled)
	# ⓑ **툴팁이 엔진 행을 거쳤는가** — 화면 리터럴이면 깨진다
	var expected_name := data.strings.text(String(slots[0]["name_key"]))
	_ok("툴팁 = 표의 스킬명(name_key 경유)",
		buttons[0].tooltip_text.contains(expected_name),
		"tooltip=%s expected=%s" % [buttons[0].tooltip_text, expected_name])
	# ⓒ 개입 창 밖에서는 장착분도 닫힌다 (`_timer_active` false 상태)
	_ok("개입 창 밖 = 장착 슬롯도 비활성", buttons[0].disabled)
	_unmount(screen)

	# ⓔ **행 폭 예산** — 액션 열은 단일 수평 열이고 확정이 최우측 최대다(D09 §3.2).
	# 5슬롯 만재에서 열이 넘치면 확정이 밀려 규격이 깨진다. 라벨을 스킬명이 아니라
	# `S{n}` 으로 둔 판단의 근거가 이 예산이므로 추정이 아니라 잰다.
	#
	# 예산은 **씬이 스스로 선언한 값에서 끌어낸다** — 캔버스 폭과 신축 비율·여백을 읽어
	# 계산하므로, 비율이 바뀌거나 열에 컨트롤이 늘면 이 축이 함께 움직인다(상수 박제 아님).
	# 마운트 직후의 실 rect 는 컨테이너 정렬이 지연돼 최소폭(릴 208)만 나오므로 쓸 수 없다.
	var s5 := _fresh_session(data)
	var wide := _mount(RACE_SCENE, s5)
	if wide != null:
		# **표에서 가장 넓어지는 덱을 고른다** — 잔여 배지(28차)가 라벨을 늘리므로 무제한
		# 5기로 재면 실기 최악을 재지 않는다. `uses_per_tour > 0` 인 전 스킬을 앞에 채우고
		# 나머지를 무제한으로 메운다(표가 바뀌면 이 덱도 함께 바뀐다 — 리터럴 고정 아님).
		wide.engine.deck = _widest_deck(data, 5)
		wide.engine.charge = 10
		wide._refresh_skill_slots()
		# 산정은 `_action_row_metrics()` 하나가 진다 — 14차 ㉚(3언어 축)과 **같은 유도**를
		# 쓴다. 두 축이 각자 계산하면 언젠가 갈리고, 갈린 뒤에는 어느 예산이 참인지 알 수 없다.
		var actions := wide.find_child("E08Actions", true, false) as Control
		var metrics := _action_row_metrics(wide)
		_ok("전제: 폭 산정 노드 전건 실재", not metrics.is_empty())
		if not metrics.is_empty() and actions != null:
			var budget: float = float(metrics["budget"])
			var needed: float = float(metrics["needed"])
			_ok("전제: 폭 예산이 릴 열보다 넓다 (산정 실패 오탐 방지)", budget > 208.0,
				"budget=%.1f" % budget)
			# **언어 권한은 ㉚ 이 진다.** 이 축은 저장된 o11 이 정하는 언어로 재므로 어느
			# 언어를 재는지 스스로 정하지 못한다 — 그 상태로 `<= budget` 을 단언하면
			# 프로필에 남은 선택지가 검사의 판정을 바꾼다(실측으로 그렇게 붉어졌다).
			# 여기서는 발주 대기 상한과만 대조하고, 3언어 실측은 ㉚ 이 명시적으로 한다.
			_ok("5슬롯 만재 액션 열이 예산 안 (초과 0)", needed - budget <= 0.0,
				"needed=%.1f budget=%.1f 초과=%.1f" % [needed, budget, needed - budget])
			# 비공허성 — 배지가 실제로 붙은 덱을 재고 있는가. 무제한만 뽑히면 이 축은
			# 28차 이전과 같은 것을 재면서 최악을 잰다고 말하게 된다.
			_ok("전제: 최광 덱에 잔여 배지가 실제로 붙었다",
				_badged_count(wide.engine.skill_slots()) > 0,
				str(_badged_count(wide.engine.skill_slots())))
			# 라벨을 스킬명으로 바꾸면 넘친다 — `S{n}` 판단의 근거를 대조군으로 못박는다.
			var slots5: Array = wide.engine.skill_slots()
			for i in range(mini(slots5.size(), wide._skill_buttons.size())):
				wide._skill_buttons[i].text = data.strings.text(String(slots5[i]["name_key"]))
			var named: float = actions.get_combined_minimum_size().x
			_ok("스킬명 라벨은 같은 예산을 넘는다 (S{n} 채택 근거)", named > budget,
				"named=%.1f budget=%.1f" % [named, budget])
		_unmount(wide)

	# ⓓ 활성화 — **클릭 경로**(pressed) 와 **키보드 경로**(F1) 를 각자 본다.
	for entry in [["클릭", "signal"], ["키보드 F1", "key"]]:
		var s2 := _fresh_session(data)
		var race := _mount(RACE_SCENE, s2)
		if race == null:
			return
		var label := String(entry[0])
		race.engine.deck = ["skill_sa1"]
		race.engine.charge = 10
		# 개입 창을 손으로 연다 — 릴 정지 연출은 await 라 프레임 구동 검사에서 기다릴 수 없다.
		race.engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
		race.engine.provisional = ["symbol_line", "symbol_line", "symbol_pulse"]
		race._timer_active = true
		race._revealing = false
		race._refresh_action_enabled()
		var before: int = race.engine.charge
		_ok("%s — 전제: 슬롯 1 활성" % label, not race._skill_buttons[0].disabled)
		if String(entry[1]) == "signal":
			race._skill_buttons[0].pressed.emit()
		else:
			race._unhandled_key_input(_key_event(KEY_F1))
		var spent: int = before - race.engine.charge
		var cost: int = CsvTable.to_int(String(data.skill("skill_sa1")["charge_cost"]))
		_ok("%s — 스킬 투입이 차지를 정확히 비용만큼 소모" % label, spent == cost,
			"spent=%d cost=%d" % [spent, cost])
		_unmount(race)


# ── ㉒ SH3 스냅샷 신구 병치 (원격 20차 계약 §1.1 `choose_snapshot`) ──
#
# 택1 대기의 정의는 `snapshot_previous` 가 비지 않은 상태다. 축은 **표시와 상태가 같이
# 움직이는가** 다 — 줄이 떠 있는데 대기가 아니거나, 대기인데 줄이 없으면 플레이어가
# 되돌릴 수 있다는 사실을 알 방법이 없다.
func _skill_snapshot_pairing(data: GameData) -> void:
	var session := _fresh_session(data)
	var screen := _mount(RACE_SCENE, session)
	if screen == null:
		return
	var row: Button = screen._e05_snapshot
	_ok("전제: 스냅샷 줄이 씬에 실재", row != null)
	if row == null:
		_unmount(screen)
		return
	_ok("대기 아님 = 줄 숨김", not row.visible)
	_ok("스냅샷 줄 도상 3기", screen._snapshot_icons.size() == 3,
		"count=%d" % screen._snapshot_icons.size())
	# 택1 대기 상태를 세운다 — 이전 후보가 새 후보와 달라야 되돌림이 관측된다.
	screen.engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
	screen.engine.provisional = ["symbol_pulse", "symbol_pulse", "symbol_pulse"]
	screen.engine.snapshot_previous = ["symbol_line", "symbol_line", "symbol_line"]
	screen._refresh_snapshot_row()
	_ok("대기 = 줄 표출", row.visible)
	_ok("대기 중 스킬 슬롯 닫힘 (한 입력이 두 결정을 겸하지 않는다)",
		screen._skill_buttons[0].disabled)
	# ⓐ 줄을 누르면 **이전 후보로 되돌아간다**
	row.pressed.emit()
	_ok("줄 클릭 = 이전 후보 복귀",
		screen.engine.provisional.size() == 3
			and String(screen.engine.provisional[0]) == "symbol_line",
		str(screen.engine.provisional))
	_ok("복귀 후 대기 종료 = 줄 숨김", not row.visible)
	# ⓑ 확정은 **새 후보 채택**이고 턴을 넘기지 않는다
	screen.engine.provisional = ["symbol_pulse", "symbol_pulse", "symbol_pulse"]
	screen.engine.snapshot_previous = ["symbol_line", "symbol_line", "symbol_line"]
	screen._refresh_snapshot_row()
	# **개입 창을 열어 둔다** — 닫힌 상태면 가로채기를 지워도 `_on_primary_action` 이
	# 아무 갈래도 타지 않아 "턴을 넘기지 않는다"가 공허하게 통과한다(돌연변이 M4 실측).
	screen._timer_active = true
	var phase_before: int = screen.engine.turn_phase
	screen._on_primary_action()
	_ok("확정 = 새 후보 유지",
		screen.engine.provisional.size() == 3
			and String(screen.engine.provisional[0]) == "symbol_pulse",
		str(screen.engine.provisional))
	_ok("확정이 택1만 해소하고 턴은 넘기지 않는다",
		screen.engine.turn_phase == phase_before,
		"before=%d after=%d" % [phase_before, screen.engine.turn_phase])
	_ok("택1 해소 후 줄 숨김", not row.visible)
	_unmount(screen)


func _audit_payload(route: String, data: GameData) -> Dictionary:
	if route != "RUN-02":
		return {}
	for event_id in data.events:
		return {"occurrence": data.events[event_id]}
	return {}


func _collect_buttons(node: Node, out: Array[BaseButton]) -> void:
	for child in node.get_children():
		if child is BaseButton:
			out.append(child)
		_collect_buttons(child, out)


# ── ⑲ 스킬 소비부 세션 창구 (20차 — D05 §5.4 · D07 §4.2) ──
#
# 엔진 검사(TC-C)는 `deck_carry_in` 을 **직접** 세우고 돈다. 그러면 아웃게임 덱이 실제로
# 그 자리에 도달하는지도, 소비한 투어 횟수가 회수되는지도 보지 못한다 —
# 회수가 빠지면 SH4·SI4 의 투어 상한이 GP 마다 되살아나고, 그 결함은
# 엔진 안에서는 완전히 정상으로 보인다(17차 A15·19차 C7 와 같은 형태의 사각).
func _skill_session_channel(data: GameData) -> void:
	var session := _fresh_session(data)
	session.outgame.gain_drive_data(500)
	_ok("⑲ 스킬 해금", session.outgame.unlock_skill("skill_sh4"))
	_ok("⑲ 덱 편성", session.outgame.set_deck(["skill_sh4"]))
	_ok("⑲ GP 개시", session.begin_gp())
	# 덱은 `start_gp()` 에서 스냅숏된다(반입 필드 → 실사용 필드). 화면이 하는 순서 그대로다:
	# `session.begin_gp()` → `engine.start_gp()` (race_screen `_start_gp`).
	_ok("⑲ 아웃게임 덱이 반입 필드에 도달", session.engine.deck_carry_in == ["skill_sh4"],
		str(session.engine.deck_carry_in))
	session.engine.start_gp()
	_ok("⑲ 반입 필드가 GP 덱으로 승계", session.engine.deck == ["skill_sh4"],
		str(session.engine.deck))
	session.engine.begin_turn()
	session.engine.spin()
	session.engine.charge = session.data.param_int("param_charge_cap")
	_ok("⑲ 세션 경유 스킬 투입 성립",
		bool(session.engine.use_skill("skill_sh4").get("ok", false)))
	# GP 를 끝까지 돌려 close_gp 회수 경로를 탄다
	var guard := 0
	while not session.engine.finished and guard < 200:
		guard += 1
		if session.engine.turn_phase != RaceTypes.TurnPhase.T4_INTERVENTION:
			if String(session.engine.begin_turn().get("type", "")) == "finished":
				break
			session.engine.spin()
		session.engine.confirm(0.0)
	session.close_gp()
	_ok("⑲ 투어 사용 횟수가 아웃게임으로 회수된다",
		int(session.outgame.skill_uses_this_tour.get("skill_sh4", 0)) == 1,
		str(session.outgame.skill_uses_this_tour))
	# 다음 GP 는 소진분을 이어받는다 — 이월이 끊기면 상한이 GP 마다 되살아난다
	_ok("⑲ 차기 GP 개시", session.begin_gp())
	_ok("⑲ 소진분이 차기 GP 로 이월",
		int(session.engine.skill_uses_carry_in.get("skill_sh4", 0)) == 1,
		str(session.engine.skill_uses_carry_in))


# ── ⑳ 시즌 개막 VN 결선 (22차 — 발주 ⓖⓗⓘ) ──
#
# **결선 전에는 세 곳이 각각 끊겨 있었다**: 개시 경로가 `line_keys` 를 넘기지 않아
# 폴백 1줄이 떴고(주력 12차 관측 3), 시즌 2+ 진입점이 없어 개막이 시즌 1 한 번만 섰고,
# 아카이브는 비트를 원문 id 로 그렸다. 세 축을 각각 본다 — 하나만 봐도 나머지는 조용하다.
func _season_open_wiring(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	# ⓐ 세션 창구 — 라인이 비트 표에서 온다
	var opening := session.season_open_payload("HUB-01")
	_ok("⑳ 개막 페이로드 발행", not opening.is_empty())
	_ok("⑳ 슬롯 = 시즌 개막", String(opening.get("slot_id", "")) == "vnslot_season_open",
		str(opening.get("slot_id", "")))
	_ok("⑳ 캘린더 공개 동반", bool(opening.get("calendar", false)))
	var lines: Array = opening.get("line_keys", [])
	_ok("⑳ 3라인 동반 (폴백 1줄이 아니다)", lines.size() == 3, str(lines.size()))
	var dict_lines := 0
	for line in lines:
		if typeof(line) == TYPE_DICTIONARY and Dictionary(line).has("speaker_key"):
			dict_lines += 1
	_ok("⑳ 전 라인 = 화자 사전", dict_lines == lines.size(), "%d/%d" % [dict_lines, lines.size()])
	_ok("⑳ 정조 동반", String(opening.get("tone", "")) == "calm", str(opening.get("tone", "")))
	# `vn_id` 는 시즌 단위 인스턴스여야 한다 — 비트 id 로 두면 아카이브가 전 시즌을 한 줄로 접는다
	_ok("⑳ vn_id = 시즌 인스턴스",
		String(opening.get("vn_id", "")) == "vn_season_open_s%d" % session.season.season,
		String(opening.get("vn_id", "")))
	# ⓑ 실화면 도달 — 폴백 문면이 아니라 데이터 문면이 그려지는가
	var screen := _mount_payload(data, session, opening)
	_ok("⑳ 실화면 1라인 = 데이터 문면",
		(screen.get_node("%BodyLabel") as Label).text == data.strings.text("vn.seasonOpen.beat01"),
		(screen.get_node("%BodyLabel") as Label).text)
	_ok("⑳ 폴백 문면 미노출",
		(screen.get_node("%BodyLabel") as Label).text != data.strings.text("ui.vn.placeholderLine01"))
	_unmount(screen)
	# ⓒ 시즌 2+ — 시즌이 넘어가면 개막 페이로드의 인스턴스 id 도 따라간다.
	# 진입점 자체(overhaul_screen)는 원본 텍스트로 확인한다: 씬을 세워 오버홀을
	# 실제로 설치하는 경로는 후보 추첨·랭크 의존이라 이 스위트의 결이 아니다.
	var season_before := session.season.season
	session.begin_next_season()
	var next_opening := session.season_open_payload("HUB-01")
	_ok("⑳ 시즌 전환 후 인스턴스 id 갱신",
		String(next_opening.get("vn_id", "")) != "vn_season_open_s%d" % season_before,
		String(next_opening.get("vn_id", "")))
	_ok("⑳ 시즌 2+ 도 3라인 (문면이 시즌 무관)",
		Array(next_opening.get("line_keys", [])).size() == 3)
	var overhaul_source := FileAccess.get_file_as_string("res://ui/hub/overhaul_screen.gd")
	_ok("⑳ 시즌 전환 진입점 원본 적재", not overhaul_source.is_empty())
	_ok("⑳ 시즌 전환이 NAR-01 로 간다", overhaul_source.contains('go("NAR-01", closing)'))
	# 개시 경로도 같은 창구를 쓴다 — 두 경로가 각자 조립하면 한쪽만 라인을 넘긴다.
	# 개시 경로는 **개막을 유지한다**: D09 §2.3 의 신규 분기는 HUB-01 을 지나지 않으므로
	# 여기서 띄우지 않으면 시즌 1 개막이 어디에서도 서지 않는다(시즌 2+ 는 개러지 이탈이 맡는다).
	var slot_source := FileAccess.get_file_as_string("res://ui/sys/save_slot_screen.gd")
	_ok("⑳ 개시 경로도 같은 창구", slot_source.contains("session.season_open_payload("))
	_ok("⑳ 개시 경로 인라인 조립 잔존 0", not slot_source.contains('"slot_id": "vnslot_season_open"'))
	# ⓔ D09 §2.3 순서 (24차 판정 A안) — `HUB-08 → 엔딩 → HUB-01 → 개막`.
	#
	# **개막이 오버홀 화면에서 사라지고 개러지 이탈로 옮겨졌는가**를 두 원본으로 본다.
	# 두 경계 비트가 연속 발화하면 닫힘과 열림이 같은 호흡에 들어가므로(내러티브 6차 §4.2)
	# "엔딩이 있다"만으로는 부족하다 — **개막이 그 자리에 없어야** 순서가 성립한다.
	var overhaul := FileAccess.get_file_as_string("res://ui/hub/overhaul_screen.gd")
	_ok("⑳ 오버홀이 엔딩 창구를 부른다", overhaul.contains("session.season_close_payload("))
	_ok("⑳ 오버홀에서 개막 발화 제거", not overhaul.contains("season_open_payload("),
		"개막이 여기 남으면 엔딩과 연속 6라인이 된다")
	# 엔딩은 `begin_next_season()` **앞**이어야 한다 — 슬롯 trigger 가 season_end 이고
	# 전환 뒤면 새 시즌의 상한을 잡아먹는다. 소스 위치로 순서를 본다.
	# 호출 순서는 **호출 형태로** 찾는다 — 주석 산문에도 같은 이름이 나오므로
	# 이름만 찾으면 주석 위치를 재게 된다(초판이 그랬다: close=4718 vs advance=4276).
	var close_at := overhaul.find("session.season_close_payload(")
	var advance_at := overhaul.find("session.begin_next_season()")
	_ok("⑳ 엔딩 조립이 시즌 전환보다 앞", close_at > 0 and advance_at > 0 and close_at < advance_at,
		"close=%d advance=%d" % [close_at, advance_at])
	var garage := FileAccess.get_file_as_string("res://ui/hub/garage_screen.gd")
	_ok("⑳ 개러지 이탈이 개막 창구를 부른다", garage.contains("session.season_open_payload("))
	var open_at := garage.find("season_open_payload(")
	var brief_at := garage.find("take_brief_payload(")
	_ok("⑳ 개막이 브리핑 앞에 사슬된다", open_at > brief_at and brief_at > 0,
		"브리핑 조립 후 개막이 그것을 다음 목적지로 받는다")
	# ⓕ 시즌당 1회 가드 — 개러지 이탈은 투어마다 지나간다
	var guard_session := _fresh_session(data)
	var first := guard_session.season_open_payload("RACE-01")
	_ok("⑳ 첫 이탈에서 개막 발행", not first.is_empty())
	guard_session.narrative.trigger_vn(String(first["vn_id"]), String(first["slot_id"]), false)
	_ok("⑳ 발화 후 같은 시즌 재발행 0", guard_session.season_open_payload("RACE-01").is_empty(),
		"가드가 없으면 투어마다 개막이 뜬다")
	# ⓓ 아카이브 표제 — 비트가 원문 id 로 뜨지 않는가
	var records := _mount(RECORDS_SCENE, session)
	if records == null:
		return
	var titled := 0
	var raw := 0
	for beat_id in data.vn_beats:
		var title := String(records._vn_title(String(beat_id)))
		if title == String(beat_id):
			raw += 1
		elif title != "":
			titled += 1
	_ok("⑳ 비트 표제 = 슬롯 표제 (원문 id 노출 0)", raw == 0, "raw=%d titled=%d" % [raw, titled])
	_ok("⑳ 전 비트가 표제를 갖는다", titled == data.vn_beats.size(),
		"%d/%d" % [titled, data.vn_beats.size()])
	_ok("⑳ 개막 비트 표제 = 시즌 개막",
		String(records._vn_title("vnbeat_season_open")) == data.strings.text("ui.vnSlot.seasonOpen"),
		String(records._vn_title("vnbeat_season_open")))
	# **비트가 선언한 표제가 슬롯 표제를 이긴다** (26차 세 번째 형태 · 27차 거동 축).
	# 마일스톤 8건이 한 슬롯을 공유하므로 이 우선이 없으면 전부 같은 표제로 선다.
	# 문면은 아직 미유입이므로 **기존 키로 대입해** 순서만 잰다 — 순서는 문면과 무관하다.
	var slot_title := data.strings.text("ui.vnSlot.tourMilestone")
	var distinct: Dictionary = {}
	for beat_id in data.vn_beats:
		var row: Dictionary = data.vn_beats[beat_id]
		if String(row.get("slot_id", "")) != "vnslot_tour_milestone":
			continue
		var title := String(records._vn_title(String(beat_id)))
		_ok("⑳ 마일스톤 비트 표제 = 선언 키: %s" % beat_id,
			title == data.strings.text(String(row["title_key"])), title)
		_ok("⑳ 슬롯 표제로 접히지 않는다: %s" % beat_id, title != slot_title, title)
		distinct[title] = true
	# **8건이 서로 다른 표제를 갖는다** — 한 슬롯을 공유해도 갈린다는 것이 기제의 목적이다.
	_ok("⑳ 마일스톤 표제 8종이 전부 상이", distinct.size() == 8, str(distinct.size()))
	_ok("⑳ 엔딩 비트 표제 = 시즌 결산",
		String(records._vn_title("vnbeat_season_close")) == data.strings.text("ui.vnSlot.seasonClose"),
		String(records._vn_title("vnbeat_season_close")))
	_ok("⑳ 재회 비트 표제 = 투어 브리핑",
		String(records._vn_title("vnbeat_reunion_alta")) == data.strings.text("ui.vnSlot.tourBrief"),
		String(records._vn_title("vnbeat_reunion_alta")))
	# 표제 도출이 적재 상태를 떨어뜨리지 않는가 — 표시 함수가 `_load_ok` 를 내리면
	# 그 다음 `param()` 부터 조용한 0 이 나온다.
	_ok("⑳ 표제 도출 후 데이터 건전", data.is_ok())
	_unmount(records)


# ── ㉒ L3 컷인 채널 — 플래그 ∧ 상대 (28차 · 유입 계약 IMPL-418) ──
#
# **두 사실이 다 필요하다.** `illustration` 은 *띄우는가*만 말하고 *어느 장인가*는 말하지
# 않는다. 검사도 그 구조를 그대로 밟는다 — 등급을 갈아 끼우고, 조우 id 를 갈아 끼운다.
#
# 등급 사전은 **표에서 받는다**(`channels()`): 손으로 `{"illustration": true}` 를 만들면
# 표의 `illustration` 열이 0 이 되어도 검사가 통과한다.
const CG_CUTIN_NODE := "CgCutIn"
const CG_THRONE_DISCOVERY := "cg_01_throne"
const CG_KINSHIP_DISCOVERY := "cg_03_kinship"


func _cg_cutin_channel(data: GameData) -> void:
	var screen := _new_race_screen()
	if screen == null:
		return
	var grade := PresentationGrade.new()
	grade.setup(data)
	var l2: Dictionary = grade.channels("grade_l2")
	var l3: Dictionary = grade.channels("grade_l3")
	_ok("전제: L2 는 일러스트 채널이 없다", not bool(l2["illustration"]), str(l2))
	_ok("전제: L3 는 일러스트 채널이 있다", bool(l3["illustration"]), str(l3))

	# ⓐ 등급이 L2 면 조우가 있어도 뜨지 않는다
	screen.apply_illustration_channel(l2, CG_THRONE_DISCOVERY)
	_ok("L2 + 조우 = 컷인 없음", screen.get_node_or_null(CG_CUTIN_NODE) == null)
	# ⓑ 등급이 L3 라도 조우가 없으면 뜨지 않는다 — **상대를 모르면 띄울 장이 없다**
	screen.apply_illustration_channel(l3, "")
	_ok("L3 + 조우 없음 = 컷인 없음", screen.get_node_or_null(CG_CUTIN_NODE) == null)
	# ⓒ 둘 다 서면 뜬다
	screen.apply_illustration_channel(l3, CG_THRONE_DISCOVERY)
	var cutin := screen.get_node_or_null(CG_CUTIN_NODE)
	_ok("L3 + 조우 = 컷인 발화", cutin != null)
	if cutin == null:
		_unmount(screen)
		return
	# ⓓ **어느 장인지가 상대로 갈린다.** 짝을 어긋나게 고른다 — 두 조우의 파일이 같으면
	#   식별을 지워도 통과한다(27차 K1 계열: 짝이 우연히 일치하면 축이 우회로를 본다).
	var throne_asset := String(data.cg_cutin_for_discovery(CG_THRONE_DISCOVERY)["asset"])
	var kinship_asset := String(data.cg_cutin_for_discovery(CG_KINSHIP_DISCOVERY)["asset"])
	_ok("전제: 두 조우의 파일이 다르다", throne_asset != kinship_asset, throne_asset)
	_ok("왕좌 조우 = 왕좌 CG", String(cutin.asset_id) == throne_asset, String(cutin.asset_id))
	# ⓔ 지속은 **표의 스팅 길이**다 — 컷인이 값을 스스로 정하면 D11 §6.5 결속이 끊긴다.
	_ok("컷인 지속 = L3 스팅 길이",
		is_equal_approx(cutin.hold_sec, float(l3["sting_length_sec"])),
		"%f vs %f" % [cutin.hold_sec, float(l3["sting_length_sec"])])
	cutin.get_parent().remove_child(cutin)
	cutin.free()
	# ⓕ 인자를 바꾸면 지속도 바뀐다 — 상수 기입(2.5 하드코딩)이면 여기서 갈린다.
	var doctored := l3.duplicate()
	doctored["sting_length_sec"] = float(l2["sting_length_sec"])
	screen.apply_illustration_channel(doctored, CG_KINSHIP_DISCOVERY)
	var second := screen.get_node_or_null(CG_CUTIN_NODE)
	_ok("동기 조우 = 동기 CG", second != null and String(second.asset_id) == kinship_asset,
		"" if second == null else String(second.asset_id))
	_ok("지속은 인자를 따른다 (상수 기입 아님)",
		second != null and is_equal_approx(second.hold_sec, float(l2["sting_length_sec"])),
		"" if second == null else str(second.hold_sec))
	_unmount(screen)


# ── ㉓ VN 장면 CG — 층 순서·재열람·부재 (28차) ──
#
# 조우 컷인과 **성격이 다르다**: 지속 인자가 없고(장면과 함께 산다) 바탕 바로 위에 선다.
# 짝은 어긋나게 고른다 — 기원 공개와 에필로그는 같은 막(4막)이지만 다른 그림이다.
const CG_VN_LAYER := "CgArt"
const CG_VN_WITH := "vn_origin"
const CG_VN_OTHER := "vn_epilogue"
const CG_VN_WITHOUT := "vn_act1"


func _vn_cg_layer(data: GameData) -> void:
	var with_cg := _mount_vn_id(data, CG_VN_WITH)
	if with_cg == null:
		return
	# ── VN 바탕 (34차 ㊵ — 내러티브 12차 스펙) ──
	# **층 순서 = 바탕 → CG → 스탠딩 → 대사창.** 바탕이 CG 위로 가면 CG 가 사라진다.
	var backdrop := with_cg.get_node_or_null("Backdrop") as TextureRect
	_ok("기원 공개 = 바탕 층 실재", backdrop != null)
	if backdrop != null:
		_ok("바탕 = 표가 지정한 파일",
			String(backdrop.get_meta("Backdrop", "")) == data.vn_backdrop(CG_VN_WITH),
			String(backdrop.get_meta("Backdrop", "")))
		_ok("바탕이 CG 아래", backdrop.get_index() < with_cg.get_node_or_null(CG_VN_LAYER).get_index()
			if with_cg.get_node_or_null(CG_VN_LAYER) != null else false)
		_ok("바탕이 바탕색(ColorRect) 위",
			backdrop.get_index() > with_cg.find_child("Background", false, false).get_index())
	var art := with_cg.get_node_or_null(CG_VN_LAYER)
	_ok("기원 공개 = CG 층 실재", art != null)
	if art != null:
		_ok("기원 공개 = 대장이 지정한 파일",
			String(art.asset_id) == String(data.cg_cutin_for_vn(CG_VN_WITH)["asset"]),
			String(art.asset_id))
		# **바탕 바로 위**다 — 34차에 바탕 층이 들어오면서 인덱스가 한 칸 밀렸으므로
		# **관계로 적는다**(리터럴 인덱스는 층이 늘 때마다 거짓이 된다).
		_ok("CG 층 = 바탕 바로 위",
			backdrop != null and art.get_index() == backdrop.get_index() + 1,
			"바탕 %d · CG %d" % [-1 if backdrop == null else backdrop.get_index(),
				art.get_index()])
		# `get_node("%...")` 는 씬 밖에서 부르면 null 이다 — 이름으로 찾는다.
		var dialogue := with_cg.find_child("DialoguePanel", false, false) as Control
		_ok("전제: 대사창 노드 실재", dialogue != null)
		_ok("CG 층이 대사창 아래", dialogue != null and art.get_index() < dialogue.get_index())
		# 장면 CG 는 스스로 사라지지 않는다 — 화면이 내려갈 때 함께 내려간다.
		_ok("장면 CG = 자동 해제 없음", is_equal_approx(art.hold_sec, 0.0), str(art.hold_sec))
	_release_vn(with_cg)

	var other := _mount_vn_id(data, CG_VN_OTHER)
	if other != null:
		var other_art := other.get_node_or_null(CG_VN_LAYER)
		_ok("에필로그 = CG 층 실재", other_art != null)
		if other_art != null:
			_ok("에필로그 = 기원 공개와 다른 파일",
				String(other_art.asset_id) != String(data.cg_cutin_for_vn(CG_VN_WITH)["asset"]),
				String(other_art.asset_id))
		_release_vn(other)

	# ⚠ **접미 붙은 인스턴스로도 바탕이 선다** — `vn_id` 완전 일치 하나로 두면 개막·종막만
	# 조용히 검정이 된다(스펙 §2.1 함정). 재열람 경로는 `scene_id` 가 없으므로 이 축이
	# 실기의 아카이브 경로 그 자체다.
	var seasonal := _mount_vn_id(data, "vn_season_open_s3")
	if seasonal != null:
		var season_bg := seasonal.get_node_or_null("Backdrop") as TextureRect
		_ok("접미 인스턴스 = 바탕 실재 (아카이브 경로)", season_bg != null)
		if season_bg != null:
			_ok("접미 인스턴스 바탕 = 개막 비트 지정",
				String(season_bg.get_meta("Backdrop", ""))
				== data.vn_backdrop("vnbeat_season_open"),
				String(season_bg.get_meta("Backdrop", "")))
		_release_vn(seasonal)
	# **미지정 장면은 층을 세우지 않는다** — ColorRect 폴백이 자동 성립한다(스펙 §4.3).
	var bare := _mount_vn_id(data, "vn_not_a_scene")
	if bare != null:
		_ok("미지정 장면 = 바탕 층 없음 (검정 폴백)",
			bare.get_node_or_null("Backdrop") == null)
		_release_vn(bare)

	# ── 화자 스탠딩 (34차 ㊵ ② — 내러티브 14차 스펙) ──
	#
	# **한 자리는 가장 최근 발화자가 쥔다.** 우측 경합 장면(`clue_silence` — 테오 vs 사샤)을
	# 골라 라인을 넘기며 점유가 실제로 교대하는지 본다 — 짝을 어긋나게 고른 것이다
	# (경합 없는 장면이면 규칙을 지워도 통과한다).
	var standing := _mount_vn_id(data, "vnbeat_clue_silence")
	if standing != null:
		var lines: Array = data.vn_beat_lines_for("vnbeat_clue_silence")
		standing._lines = standing._normalize_lines(lines)
		standing._line_index = 0
		var right_seen: Array = []
		var left_seen: Array = []
		for index in range(lines.size()):
			standing._line_index = index
			standing._show_line()
			var left := standing.find_child("StandingLeft", true, false)
			var right := standing.find_child("StandingRight", true, false)
			var left_art := left.get_node_or_null("Standing") if left != null else null
			var right_art := right.get_node_or_null("Standing") if right != null else null
			if left_art != null and not left_seen.has(String(left_art.get_meta("Standing", ""))):
				left_seen.append(String(left_art.get_meta("Standing", "")))
			if right_art != null and not right_seen.has(String(right_art.get_meta("Standing", ""))):
				right_seen.append(String(right_art.get_meta("Standing", "")))
		# 좌측은 한 인물만 — 마르타 고정이 스펙의 축이다.
		_ok("좌측 점유 = 1인 (마르타 고정)", left_seen.size() == 1, str(left_seen))
		_ok("좌측 = 표가 지정한 인물",
			left_seen.size() == 1
			and String(left_seen[0]) == String(data.vn_speaker("ui.vn.speakerMarta")["char_id"]),
			str(left_seen))
		# **우측은 교대한다** — 한 인물만 보이면 최근 발화자 규칙이 일하지 않은 것이다.
		_ok("우측 점유 교대 (최근 발화자 규칙)", right_seen.size() >= 2, str(right_seen))
		# 지문·베인은 아무것도 바꾸지 않는다 — 지우지도 않는다.
		standing._line_index = 0
		standing._show_line()
		var narration_left := standing.find_child("StandingLeft", true, false)
		var kept := narration_left.get_node_or_null("Standing") if narration_left != null else null
		# **`queue_free()` 는 그 프레임에 노드를 남긴다** — 존재만 보면 지운 것과 안 지운 것이
		# 같은 그림이다(반증 Y3 초판 미검출). 해제 예약까지 본다.
		_ok("지문 라인에서도 좌측이 남는다",
			kept != null and not kept.is_queued_for_deletion(),
			"null" if kept == null else str(kept.is_queued_for_deletion()))
		# **base 전용 시작** (스펙 §3) — 표정 차분을 열면 위계가 거짓이 된다.
		_ok("스탠딩 = base 차분",
			kept != null and (kept as TextureRect).texture != null
			and String((kept as TextureRect).texture.resource_path).ends_with("_base.png"),
			"" if kept == null or (kept as TextureRect).texture == null
			else String((kept as TextureRect).texture.resource_path))
		_release_vn(standing)

	# ── 표정 차분 예외 · 베인 파형 차용 (35차 · 총괄 판정 ①②) ──
	var sasha := _mount_vn_id(data, "vnbeat_crew_sasha")
	if sasha != null:
		sasha._lines = sasha._normalize_lines(data.vn_beat_lines_for("vnbeat_crew_sasha"))
		var sasha_key := "ui.vn.speakerSasha"
		var variant := data.vn_face_variant("vnbeat_crew_sasha", sasha_key)
		_ok("전제: 예외 선언이 실재한다", not variant.is_empty(), variant)
		for index in range(sasha._lines.size()):
			if String(sasha._lines[index]["speaker_key"]) != sasha_key:
				continue
			sasha._line_index = index
			sasha._show_line()
			break
		var right := sasha.find_child("StandingRight", true, false)
		var thawed := right.get_node_or_null("Standing") if right != null else null
		_ok("예외 장면 = 해빙 차분", thawed != null
			and String(thawed.get_meta("standing_suffix", "")) == "_" + variant,
			"" if thawed == null else String(thawed.get_meta("standing_suffix", "")))
		# ── 차분 = **얼굴 영역 레이어**다 (37차 신설 — D10 §3.1 "전신 재작화 금지") ──
		#
		# 위 축은 **접미 문자열만** 본다. 그래서 차분을 통째로 갈아 끼워도 통과했고,
		# 실물 차분은 112×112 얼굴 레이어라 슬롯에 **얼굴만** 떴다(몸 소실·턱에서 잘림).
		# 문자열은 무엇이 그려졌는지 말하지 않는다 — **그린 것을 재는 축**을 함께 둔다.
		var sheet := load("res://assets/characters/crew_sasha_base.png") as Texture2D
		var layer := load("res://assets/characters/crew_sasha_%s.png" % variant) as Texture2D
		_ok("전제: 기본·차분 실물이 갈린 치수다",
			sheet != null and layer != null and sheet.get_size() != layer.get_size(),
			"" if sheet == null or layer == null
			else "%s vs %s" % [str(sheet.get_size()), str(layer.get_size())])
		var drawn: Image = null
		if thawed != null and (thawed as TextureRect).texture != null:
			drawn = (thawed as TextureRect).texture.get_image()
		# ⓐ 합성물은 **기본 시트 치수**다. 교체판은 여기서 얼굴 치수를 돌려준다.
		_ok("합성 결과 = 기본 시트 치수", drawn != null and sheet != null
			and drawn.get_size() == Vector2i(sheet.get_size()),
			"null" if drawn == null else str(drawn.get_size()))
		if drawn != null and sheet != null and layer != null \
				and drawn.get_size() == Vector2i(sheet.get_size()):
			var base_image := sheet.get_image()
			if base_image.get_format() != drawn.get_format():
				base_image = base_image.duplicate() as Image
				base_image.convert(drawn.get_format())
			var origin := Vector2i(
				(base_image.get_width() - layer.get_width()) / 2,
				CsvTable.to_int(String(data.vn_speaker(sasha_key).get("face_offset_y", "-1"))))
			var inside := 0
			var outside := 0
			for y in range(base_image.get_height()):
				for x in range(base_image.get_width()):
					if drawn.get_pixel(x, y) == base_image.get_pixel(x, y):
						continue
					var in_face: bool = x >= origin.x and x < origin.x + layer.get_width() \
						and y >= origin.y and y < origin.y + layer.get_height()
					if in_face:
						inside += 1
					else:
						outside += 1
			# ⓑ **공허하지 않다** — 차분이 얼굴 구획을 실제로 바꾼다.
			_ok("얼굴 구획이 기본과 갈린다", inside > 0, "%d px" % inside)
			# ⓒ **전신 재작화 금지의 기계 확인** — 구획 밖은 기본 그대로다.
			_ok("얼굴 구획 밖 = 기본과 동일", outside == 0, "%d px" % outside)
		_release_vn(sasha)
	# **타 장면의 같은 인물은 base 다** — 예외를 전역 열로 두면 여기서 갈린다(반증 Z1).
	var sasha_other := _mount_vn_id(data, "vnbeat_clue_silence")
	if sasha_other != null:
		sasha_other._lines = sasha_other._normalize_lines(
			data.vn_beat_lines_for("vnbeat_clue_silence"))
		for index in range(sasha_other._lines.size()):
			if String(sasha_other._lines[index]["speaker_key"]) != "ui.vn.speakerSasha":
				continue
			sasha_other._line_index = index
			sasha_other._show_line()
			break
		var other_right := sasha_other.find_child("StandingRight", true, false)
		var other_art := other_right.get_node_or_null("Standing") if other_right != null else null
		_ok("타 장면의 같은 인물 = base", other_art != null
			and String(other_art.get_meta("standing_suffix", "")) == "_base",
			"" if other_art == null else String(other_art.get_meta("standing_suffix", "")))
		_release_vn(sasha_other)
	# 베인은 **인물이 아니라 파형**이고 같은 슬롯을 쓴다 — 자리 계수가 늘지 않는다.
	var vane := _mount_vn_id(data, "vn_act1")
	if vane != null:
		vane._lines = vane._normalize_lines(data.act_vn_entry("vn_act1").get("lines", []))
		# **베인 앞 라인까지 흘린다** — 인물이 먼저 서 있어야 "차용이 비운다"가 잴 것을
		# 갖는다. 베인 라인만 보이면 슬롯이 원래 비어 있어 병치 축이 공허하다(반증 Z4).
		var vane_line := -1
		for index in range(vane._lines.size()):
			vane._line_index = index
			vane._show_line()
			if String(vane._lines[index]["speaker_key"]) == "ui.vn.speakerVane":
				vane_line = index
				break
		_ok("전제: 베인 앞에 인물 발화가 있었다", vane_line > 0, str(vane_line))
		var vslot := vane.find_child("StandingRight", true, false)
		_ok("베인 = 파형 노드", vslot != null and vslot.get_node_or_null("VaneWaveform") != null)
		# **차용이지 병치가 아니다** — 한 슬롯에 인물과 파형이 함께 서지 않는다.
		_ok("베인 슬롯에 인물 스탠딩 없음",
			vslot != null and vslot.get_node_or_null("Standing") == null)
		_ok("자리 계수 불변 (좌·우 둘)",
			vane.find_child("StandingLeft", true, false) != null and vslot != null)
		# **거울상을 함께 잰다 (36차 신설).** 위 축은 *인물 → 파형* 순서만 본 뒤 그 라인에서
		# 멈춘다. 실기 데이터는 반대 순서도 만든다 — 베인이 말한 **뒤에** 그 자리 인물이
		# 돌아온다(`vn_act1` 9행 · `feat_*` 3종). 한 방향만 비우면 차용이 그 순서에서
		# 병치가 되고, 위 축은 이미 지난 라인이라 그것을 보지 못한다.
		var back_line := -1
		for index in range(vane_line + 1, vane._lines.size()):
			vane._line_index = index
			vane._show_line()
			var key := String(vane._lines[index]["speaker_key"])
			if String(data.vn_speaker(key).get("side", "none")) == "right" \
					and not String(data.vn_speaker(key).get("char_id", "")).is_empty():
				back_line = index
				break
		_ok("전제: 베인 뒤에 그 자리 인물이 돌아온다", back_line > vane_line, str(back_line))
		var back_art := vslot.get_node_or_null("Standing") if vslot != null else null
		_ok("복귀 인물 = 스탠딩 실재", back_art != null)
		var back_wave := vslot.get_node_or_null("VaneWaveform") if vslot != null else null
		_ok("복귀 라인에 파형 잔존 없음 (차용의 거울상)", back_wave == null,
			"" if back_wave == null else "VaneWaveform 잔존")
		_release_vn(vane)

	var without := _mount_vn_id(data, CG_VN_WITHOUT)
	if without != null:
		# **없는 것이 정상이다.** 전 VN 이 그림을 얻으면 "희귀 이벤트 한정"(D01 §8-1)이 깨진다.
		_ok("CG 없는 VN = 층 없음", without.get_node_or_null(CG_VN_LAYER) == null)
		_release_vn(without)


# 재열람 경로로 세운다 — 슬롯 발생 판정·상한을 거치지 않으므로 CG 축만 남는다.
# **재열람에서 재는 것 자체가 계약의 일부다**: 아카이브가 그림 없는 장면을 돌려주면
# 회수 경로가 같은 장면이 아니다 (D07 §6.3).
func _mount_vn_id(data: GameData, vn_id: String) -> Control:
	var packed := load(VN_SCENE) as PackedScene
	if packed == null:
		_ok("VN 씬 로드", false)
		return null
	var screen := packed.instantiate() as Control
	var session := _fresh_session(data)
	screen.session = session
	root.add_child(screen)
	screen.bind(session, {"replay": true, "vn_id": vn_id, "line_keys": ["vn.act1.beat01"]})
	return screen


# ── ㉔ 문면 2키 소비 (내러티브 10차 유입 IMPL-425 · 28차) ──
#
# ⓐ 잔여 횟수 배지 — **확장형 키를 쓰는가**, 그리고 **무제한에는 쓰지 않는가.**
# ⓑ `limit_hold` 거부 고지 — 27차에 미고지 대장에 남겨 둔 1건.
#
# 짝은 어긋나게 고른다: 제한 슬롯과 무제한 슬롯의 렌더가 **달라야** 하고, 거부 문면은
# 다른 사유의 문면과 **달라야** 한다. 같으면 키를 갈아도 검사가 통과한다.
const LIMIT_HOLD_ERROR := "limit_hold"
const OTHER_REJECT_ERROR := "charge"


func _skill_label_and_notice(data: GameData) -> void:
	var screen := _new_race_screen()
	if screen == null:
		return
	var s := data.strings
	var cost_text := s.text("ui.race.costFormat", {"cost": 2})
	var limited := String(screen._action_label("A", cost_text, {"uses_left": 1, "uses_per_tour": 3}))
	var endless := String(screen._action_label("A", cost_text, {"uses_left": -1, "uses_per_tour": 0}))
	_ok("제한 슬롯 = 확장형 렌더", limited != endless, limited)
	_ok("제한 슬롯에 잔여/상한이 실린다",
		limited.contains(s.text("ui.race.skillUsesFormat", {"remaining": 1, "limit": 3})), limited)
	# **무제한은 숫자를 그리지 않는다** — 어떤 숫자든 거짓말이 된다 (20차 계약의 표시 층 귀결).
	_ok("무제한 슬롯 = 기존 렌더",
		endless == s.text("ui.race.actionWithCost", {"label": "A", "cost": cost_text}), endless)
	# **대조군을 손으로 만든다** — 확장형 키가 무제한 슬롯에 대해 *무엇을 그릴 것인가*를
	# 그대로 조립해 두고, 실제 렌더가 그것이 아님을 본다. 임의의 숫자("0/0")로 대조하면
	# 실패가 그 숫자를 우연히 피하기만 해도 통과한다(-1/0 이 그랬다 — 초판 미검출분).
	var wrong := s.text("ui.race.actionWithUses", {
		"label": "A", "cost": cost_text,
		"left": s.text("ui.race.skillUsesFormat", {"remaining": -1, "limit": 0}),
	})
	_ok("무제한에 확장형 키를 쓰지 않는다", endless != wrong, endless)
	# ⓑ 거부 고지 — **자리가 로그 존에서 전용 슬롯으로 옮겨졌다 (14차 ①).** 관측 지점도
	# 함께 옮긴다: 옛 축은 로그 행 수를 셌고, 그 축을 그대로 두면 슬롯으로 옮긴 순간
	# 붉어지는 것이 아니라 **옮긴 것을 결함으로 보고**한다. 경로 자체의 못박기는 ㉖ 이
	# 진다(키를 눌러 잰다) — 여기는 표·문면 대응만 본다.
	var slot: Label = screen._reject_notice
	_ok("전제: 전용 고지 슬롯 실재", slot != null)
	if slot != null:
		var log_before := _rendered_log_lines(screen).size()
		screen._notify_skill_rejected(LIMIT_HOLD_ERROR)
		var expected := s.text("ui.race.skillRejectedLimitHold")
		_ok("limit_hold 거부 = 전용 슬롯 문면 일치", slot.text == expected, slot.text)
		_ok("거부 고지가 로그 존에 실리지 않는다",
			_rendered_log_lines(screen).size() == log_before,
			"before=%d after=%d" % [log_before, _rendered_log_lines(screen).size()])
		_ok("전제: 다른 사유와 문면이 다르다",
			expected != s.text("ui.race.skillRejectedCharge"), expected)
		# `limit_boost` — 27차 2분할의 나머지 반쪽 (문면 유입 IMPL-434). **짝을 어긋나게
		# 고른다**: 두 반쪽의 문면이 같으면 분할이 표시 층에서 무의미해진다.
		var boost_expected := s.text("ui.race.skillRejectedLimitBoost")
		_ok("전제: 2분할 두 반쪽의 문면이 다르다", boost_expected != expected, boost_expected)
		slot.text = ""
		screen._notify_skill_rejected("limit_boost")
		_ok("limit_boost 거부 = 전용 슬롯 문면 일치", slot.text == boost_expected, slot.text)
		# 침묵 3종은 여전히 침묵이다 — 고지 편입이 봉인 계약을 밀지 않았는가.
		for code in RaceEngine.SEAL_SILENT_ERRORS:
			slot.text = expected
			screen._notify_skill_rejected(String(code))
			_ok("봉인 침묵 %s = 슬롯 공란" % String(code), slot.text == "", slot.text)
	_unmount(screen)


# 표에서 라벨이 가장 넓어지는 덱 — 잔여 배지가 붙는 스킬(`uses_per_tour > 0`)을 우선 채운다.
# **리터럴 덱을 고정하지 않는다**: 표에 제한 스킬이 늘면 최악도 함께 움직여야 한다.
func _widest_deck(data: GameData, size: int) -> Array:
	var limited: Array = []
	var rest: Array = []
	for skill_id in data.skills:
		if CsvTable.to_int(String(data.skills[skill_id]["uses_per_tour"])) > 0:
			limited.append(String(skill_id))
		else:
			rest.append(String(skill_id))
	limited.sort()
	rest.sort()
	var deck: Array = []
	for pool in [limited, rest]:
		for skill_id in pool:
			if deck.size() >= size:
				break
			deck.append(skill_id)
	return deck


func _badged_count(slots: Array) -> int:
	var total := 0
	for slot in slots:
		if int(Dictionary(slot).get("uses_left", -1)) >= 0:
			total += 1
	return total


# ── 액션 열 폭 산정 (13차 ⓔ 에서 추출 · 14차 ⑧ 이 3언어로 재사용) ──
#
# 예산은 **씬이 스스로 선언한 값에서 끌어낸다**(캔버스 폭 · 신축 비율 · 여백 상수).
# 두 축이 각자 계산하면 언젠가 갈리므로 산지를 하나만 둔다.
func _action_row_metrics(screen: Control) -> Dictionary:
	var actions := screen.find_child("E08Actions", true, false) as Control
	var left := screen.find_child("LeftColumn", true, false) as Control
	var feed := screen.find_child("E10LogFeed", true, false) as Control
	var middle := screen.find_child("Middle", true, false) as Control
	var zone := screen.find_child("ReelZone", true, false) as Control
	if actions == null or left == null or feed == null or middle == null or zone == null:
		return {}
	var ratio_sum: float = left.size_flags_stretch_ratio + feed.size_flags_stretch_ratio
	var column: float = (CANVAS.x - float(middle.get_theme_constant("separation"))) \
		* left.size_flags_stretch_ratio / ratio_sum
	var budget: float = column - float(zone.get_theme_constant("margin_left")) \
		- float(zone.get_theme_constant("margin_right"))
	return {"budget": budget, "needed": actions.get_combined_minimum_size().x, "column": column}


# ── ㉕ 개입 창 관문 단일화 (14차 ⑦ — 원격 27차 ③ 액션 경로 전수) ──
#
# 27차가 `_on_respin` 하나에서 본 형태 — 키·패드 액션이 버튼 `disabled` 를 우회한다 —
# 를 화면 층 전건에 걸쳐 훑은 결과의 못박기.
#
# **축은 "핸들러가 버튼과 같은 술어를 부르는가" 다.** 조건을 두 곳에 적으면 언젠가 갈리고,
# 갈린 순간 마우스와 키보드가 다른 게임을 한다. 관측은 **엔진 상태**로 한다 — 소리나
# 버튼 표시가 아니라 실제로 릴이 굴렀는지·차지가 나갔는지를 본다(우회의 피해가 그것이다).
func _intervention_gate(data: GameData) -> void:
	# ⓐ SH3 택1 대기 중 — 개입 3종이 **키 경로로도** 닫힌다.
	#
	# 종전 실측: 슬롯 행만 `_snapshot_pending()` 을 물었고 리스핀·차지·홀드 세 줄은 열려
	# 있었다. 대기 중에 릴을 다시 굴리면 위에 뜬 이전 후보 줄이 두 걸음 낡은 후보를
	# 가리키고, 그것을 누르면 방금 지불한 차지가 조용히 되돌아간다.
	for entry in [["리스핀 R", "respin"], ["차지 개입 C", "charge"], ["홀드 토글 1", "hold"]]:
		var session := _fresh_session(data)
		var screen := _mount(RACE_SCENE, session)
		if screen == null:
			return
		var label := String(entry[0])
		screen.engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
		screen.engine.provisional = ["symbol_pulse", "symbol_pulse", "symbol_pulse"]
		screen.engine.charge = 10
		screen._timer_active = true
		screen._revealing = false
		# 전제 두 겹: 대기 **밖**에서는 열려 있어야 한다. 이 전제가 없으면 "닫혔다"가
		# 애초에 닫힌 상태를 다시 확인하는 공허한 통과가 된다(M4 계열).
		screen._refresh_action_enabled()
		_ok("%s — 전제: 대기 밖에서는 열린다" % label, screen._intervention_open(),
			"open=%s" % str(screen._intervention_open()))
		screen.engine.snapshot_previous = ["symbol_line", "symbol_line", "symbol_line"]
		screen._refresh_action_enabled()
		_ok("%s — 대기 중 관문 닫힘" % label, not screen._intervention_open())
		var charge_before: int = screen.engine.charge
		var reels_before: Array = screen.engine.provisional.duplicate()
		var hold_before: bool = screen._hold_boxes[0].button_pressed
		match String(entry[1]):
			"respin": screen._unhandled_key_input(_key_event(KEY_R))
			"charge": screen._unhandled_key_input(_key_event(KEY_C))
			_: screen._unhandled_key_input(_key_event(KEY_1))
		_ok("%s — 대기 중 키 경로가 차지를 쓰지 않는다" % label,
			screen.engine.charge == charge_before,
			"before=%d after=%d" % [charge_before, screen.engine.charge])
		_ok("%s — 대기 중 키 경로가 릴을 다시 굴리지 않는다" % label,
			str(screen.engine.provisional) == str(reels_before),
			"before=%s after=%s" % [str(reels_before), str(screen.engine.provisional)])
		_ok("%s — 대기 중 키 경로가 홀드를 토글하지 않는다" % label,
			screen._hold_boxes[0].button_pressed == hold_before)
		_unmount(screen)

	# ⓑ **반전 2건** — 택1 두 갈래는 대기 *중에만* 열린다. `_intervention_open()` 을
	# 여기 걸면 두 갈래가 영원히 닫히므로, 가드가 다른 것이 정상이라는 사실을 못박는다.
	var s2 := _fresh_session(data)
	var rev := _mount(RACE_SCENE, s2)
	if rev != null:
		rev.engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
		rev.engine.provisional = ["symbol_pulse", "symbol_pulse", "symbol_pulse"]
		rev._timer_active = true
		rev.engine.snapshot_previous = []
		_ok("전제: 대기 없음 = 되돌림 무동작", not rev._resolve_snapshot_keep_new())
		rev.engine.snapshot_previous = ["symbol_line", "symbol_line", "symbol_line"]
		_ok("대기 중 = 되돌림이 열린다 (관문 반전)", rev._resolve_snapshot_keep_new())
		_unmount(rev)

	# ⓒ **커서 표시와 조작 가능이 같은 조건인가** — 화면 주석이 그것을 계약으로 적어 뒀다.
	# 갈리면 "커서는 보이는데 A 가 안 먹는" 상태가 된다.
	var s3 := _fresh_session(data)
	var cur := _mount(RACE_SCENE, s3)
	if cur != null:
		cur.engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
		cur.engine.provisional = ["symbol_pulse", "symbol_pulse", "symbol_pulse"]
		cur._timer_active = true
		cur._cursor_active = true
		cur._refresh_reel_frames()
		var lit: bool = cur._reel_frame_styles[cur._hold_cursor].border_color == UiPalette.ACCENT_ACTIVE
		_ok("전제: 관문이 열리면 커서가 뜬다", lit)
		cur.engine.snapshot_previous = ["symbol_line", "symbol_line", "symbol_line"]
		cur._refresh_reel_frames()
		_ok("관문이 닫히면 커서도 꺼진다 (조작 가능과 같은 조건)",
			cur._reel_frame_styles[cur._hold_cursor].border_color != UiPalette.ACCENT_ACTIVE)
		_unmount(cur)


# ── ㉖ 거부 고지 전용 슬롯 (14차 ① — 총괄 인계 최소 100px) ──
#
# 26차의 로그 존 얹기가 전용 슬롯으로 옮겨졌다. **축의 핵은 경로다**: 종전 검사는
# `_notify_skill_rejected()` 를 **직접 불렀고**, 그것은 표가 문면을 가리키는지만 증명한다.
# 실제로는 `limit_hold` 의 유일한 산지가 `hold_respin` 이고 그 화면 호출부(`_on_respin`)가
# 고지를 부르지 않아 **실기에 한 번도 뜬 적이 없었다.** 그래서 이 축은 **키를 눌러** 잰다.
const NOTICE_KEYS := [
	"ui.race.skillRejectedCharge", "ui.race.skillRejectedUses",
	"ui.race.skillRejectedHoldCap", "ui.race.skillRejectedLimitHold",
	"ui.race.skillRejectedAlreadyHold", "ui.race.skillRejectedAlreadyMod",
	"ui.race.skillRejectedDuelTurn", "ui.race.skillRejectedSectorTurn",
]
const BODY_FONT_PATH := "res://assets/fonts/Galmuri9.ttf"
const STRINGS_TABLE := "res://data/strings/strings.csv"


func _reject_notice_slot(data: GameData) -> void:
	var session := _fresh_session(data)
	var screen := _mount(RACE_SCENE, session)
	if screen == null:
		return
	var slot: Label = screen._reject_notice
	_ok("전제: 전용 고지 슬롯이 씬에 실재", slot != null)
	if slot == null:
		_unmount(screen)
		return
	_ok("초기 상태 = 문면 없음", slot.text == "")
	# 슬롯은 **항상 존재한다** — `visible` 개폐면 고지가 뜰 때마다 그 위의 전부가 튄다.
	_ok("슬롯은 상시 표출 (자리를 예약한다)", slot.visible)
	_ok("빈 문면에서도 높이를 차지한다 (예약이 성립한다)",
		slot.get_combined_minimum_size().y > 0.0,
		"h=%.1f" % slot.get_combined_minimum_size().y)

	# ⓐ **실기 경로로 `limit_hold` 를 낸다** — 리스핀 키. 직접 호출이 아니다.
	screen.engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
	screen.engine.provisional = ["symbol_pulse", "symbol_pulse", "symbol_pulse"]
	screen.engine.charge = 10
	screen.engine.hold_used = true          # 턴당 1회 소진 = limit_hold 의 유일 조건
	screen._timer_active = true
	screen._revealing = false
	screen._refresh_action_enabled()
	var log_before: int = _rendered_log_lines(screen).size()
	screen._unhandled_key_input(_key_event(KEY_R))
	var expected := data.strings.text("ui.race.skillRejectedLimitHold")
	_ok("리스핀 키 거부 = 전용 슬롯에 고지", slot.text == expected,
		"slot=%s expected=%s" % [slot.text, expected])
	# ⓑ 로그 존은 오염되지 않는다 — 거부가 경기 기록 슬롯 4를 밀어내지 않는다.
	_ok("거부 고지가 로그 존을 밀어내지 않는다",
		_rendered_log_lines(screen).size() == log_before,
		"before=%d after=%d" % [log_before, _rendered_log_lines(screen).size()])
	# 대조군 — 다른 사유는 다른 문면이다. 같으면 키를 갈아도 검사가 통과한다.
	_ok("전제: 다른 사유와 문면이 다르다",
		expected != data.strings.text("ui.race.skillRejectedCharge"), expected)

	# ⓒ 침묵 계열은 슬롯을 비운다 — 직전 고지가 남으면 엉뚱한 사유를 가리킨다.
	for code in RaceEngine.SEAL_SILENT_ERRORS:
		slot.text = expected
		screen._notify_skill_rejected(String(code))
		_ok("봉인 침묵 %s = 슬롯 공란" % String(code), slot.text == "", slot.text)

	# ⓓ 성공이 고지를 걷는다.
	slot.text = expected
	screen._report_outcome(true)
	_ok("성공하면 직전 고지가 걷힌다", slot.text == "")
	# ⓔ 턴 경계가 고지를 걷는다 — limit_hold 는 새 턴에서 실제로 거짓이 된다.
	slot.text = expected
	screen._next_turn()
	_ok("턴 경계가 고지를 걷는다", slot.text == "")
	_unmount(screen)

	# ⓕ **열 폭이 최장 문면보다 넓은가 — 3언어.** 총괄 인계는 최소 100px(ja 실측 112px)을
	# 요구했다. 자수 상한을 숫자로 적는 대신 열이 최장 문면보다 넓다를 재므로, 문면이
	# 자라거나 열이 좁아지면 이 축이 먼저 깨진다.
	var body := load(BODY_FONT_PATH) as FontFile
	_ok("전제: 본문 원도 적재", body != null)
	if body == null:
		return
	var rows := CsvTable.load_rows(STRINGS_TABLE)
	_ok("전제: 스트링 표 적재", not rows.is_empty())
	var size := data.param_int("param_font_size_body")
	var s6 := _fresh_session(data)
	var probe := _mount(RACE_SCENE, s6)
	if probe == null:
		return
	var metrics := _action_row_metrics(probe)
	_ok("전제: 폭 산정 성립", not metrics.is_empty())
	if not metrics.is_empty():
		var column: float = float(metrics["column"])
		for language in LANGUAGE_COLUMNS_EXPECTED:
			var widest := 0.0
			var widest_key := ""
			for row in rows:
				if not NOTICE_KEYS.has(String(row.get(StringTable.KEY_COLUMN, ""))):
					continue
				var w: float = body.get_string_size(
					String(row.get(String(language), "")), 0, -1, size).x
				if w > widest:
					widest = w
					widest_key = String(row[StringTable.KEY_COLUMN])
			_ok("[%s] 고지 문면 8종이 표에 있다 (비공허)" % String(language), widest > 0.0,
				"widest=%.1f" % widest)
			_ok("[%s] 고지 슬롯 열이 최장 문면보다 넓다" % String(language), column > widest,
				"열=%.1f 최장=%.1f (%s)" % [column, widest, widest_key])
	_unmount(probe)


# ── ㉗ SH3 신 후보 전용 버튼 (14차 ④ — `ui.race.snapshotKeepNew` 소비) ──
#
# 종전에는 한쪽만 버튼이었다. 그러면 화면이 **택1로 보이지 않는다** — 보이는 것은 버튼
# 하나와, "확정을 누르면 새 것으로 간다"는 어디에도 적혀 있지 않은 사실이다.
#
# **축은 두 갈래가 같은 모양으로 서는가, 그리고 새 갈래가 확정과 같은 귀결인가** 다.
# 두 번째가 특히 중요하다 — 새 버튼이 자기 구현을 가지면 병치가 두 경로로 갈린다.
func _snapshot_keep_new_button(data: GameData) -> void:
	var session := _fresh_session(data)
	var screen := _mount(RACE_SCENE, session)
	if screen == null:
		return
	var new_btn: Button = screen._e05_snapshot_new
	var old_btn: Button = screen._e05_snapshot
	_ok("전제: 신 후보 버튼이 씬에 실재", new_btn != null)
	if new_btn == null or old_btn == null:
		_unmount(screen)
		return
	_ok("대기 아님 = 두 갈래 모두 숨김", not new_btn.visible and not old_btn.visible)
	screen.engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
	screen.engine.provisional = ["symbol_pulse", "symbol_pulse", "symbol_pulse"]
	screen.engine.snapshot_previous = ["symbol_line", "symbol_line", "symbol_line"]
	screen._timer_active = true
	screen._refresh_snapshot_row()
	_ok("대기 = 두 갈래 함께 표출 (택1로 보인다)", new_btn.visible and old_btn.visible)
	var keep_new := data.strings.text("ui.race.snapshotKeepNew")
	var keep_old := data.strings.text("ui.race.snapshotKeepOld")
	_ok("전제: 두 문면이 다르다 (같으면 라벨을 갈아도 통과한다)", keep_new != keep_old)
	_ok("신 후보 버튼 라벨 = snapshotKeepNew", new_btn.text == keep_new, new_btn.text)
	_ok("이전 후보 버튼 라벨 = snapshotKeepOld", old_btn.text == keep_old, old_btn.text)
	# 배치 — 신 후보가 릴 **위**, 이전 후보가 릴 **아래**. 살아 있는 릴이 신 후보의 내용이므로
	# 그 바로 위에 서야 무엇을 유지하는지가 배치로 읽힌다.
	var reels := screen.find_child("E05Reels", true, false) as Control
	_ok("전제: 릴 노드 실재", reels != null)
	if reels != null:
		_ok("신 후보 버튼이 릴 위, 이전 후보가 릴 아래",
			new_btn.get_index() < reels.get_index()
				and old_btn.get_index() > reels.get_index(),
			"new=%d reels=%d old=%d" % [new_btn.get_index(), reels.get_index(), old_btn.get_index()])
	# **같은 귀결인가** — 버튼과 확정이 같은 상태로 끝나야 병치가 한 경로다.
	var phase_before: int = screen.engine.turn_phase
	new_btn.pressed.emit()
	_ok("신 후보 버튼 = 새 후보 유지",
		screen.engine.provisional.size() == 3
			and String(screen.engine.provisional[0]) == "symbol_pulse",
		str(screen.engine.provisional))
	_ok("신 후보 버튼도 턴을 넘기지 않는다",
		screen.engine.turn_phase == phase_before,
		"before=%d after=%d" % [phase_before, screen.engine.turn_phase])
	_ok("택1 해소 후 두 갈래 모두 숨김", not new_btn.visible and not old_btn.visible)
	_unmount(screen)


# ── ㉘ 옵션 언어 전환 재문면화 (14차 ③ — 13차 이월) ──
#
# 즉시 반영(§6.3 적용 버튼 없음)이 이 항목에서만 성립하지 않고 있었다: 바뀌는 것은 방금
# 만진 값 하나뿐이고 표제·탭·항목 라벨은 진입 시점 언어로 굳어 있었다.
#
# **대조군을 함께 둔다** — 비언어 항목을 만졌을 때는 재구축이 *일어나지 않아야* 한다.
# 없으면 "무조건 다시 세운다"도 통과하고, 그것은 매 조작마다 포커스를 흔드는 구현이다.
func _options_relabel(data: GameData) -> void:
	var before_language := data.strings.language()
	var session := _fresh_session(data)
	# **저장된 선택지도 되돌린다.** 런타임 언어만 복구하면 프로필에 남은 o11 이 다음
	# `begin_career()` 의 `apply_language()` 를 타고 되살아나 **뒤 축 전부가 다른 언어로**
	# 돌아간다. 실측으로 잡혔다: ㉚ 이 3언어를 재는데 세 번 모두 en 이 나왔고 값이 같아서
	# 통과처럼 보이지 않았을 뿐이다(같은 값 3개가 곧 단서였다).
	var before_index := session.options.index_of("o11")
	var screen := _mount(OPTIONS_SCENE, session)
	if screen == null:
		return
	var header := screen.get_node("%HeaderLabel") as Label
	var tab_row := screen.get_node("%TabRow") as Control
	_ok("전제: 표제·탭 줄 실재", header != null and tab_row != null)
	if header == null or tab_row == null:
		_unmount(screen)
		return
	var entry_header := header.text
	_ok("전제: 진입 문면이 현행 언어",
		entry_header == data.strings.text("ui.options.header"), entry_header)
	# 언어 항목의 탭을 고르고 그 행의 다음 버튼을 실제로 누른다.
	var language_tab := -1
	for index in range(OptionsStore.TABS.size()):
		if Array(OptionsStore.TABS[index]["options"]).has("o11"):
			language_tab = index
	_ok("전제: 언어 항목이 탭 대장에 있다", language_tab >= 0, "tab=%d" % language_tab)
	if language_tab < 0:
		_unmount(screen)
		return
	screen._select_tab(language_tab)
	var panel := screen._tab_panels[language_tab] as Control
	var next_button := panel.find_child("Next", true, false) as Button
	_ok("전제: 언어 행의 다음 버튼 실재", next_button != null)
	if next_button == null:
		_unmount(screen)
		return
	next_button.grab_focus()
	next_button.pressed.emit()
	# ⓐ 화면 전체가 새 언어로 다시 선다.
	_ok("언어 전환이 실제로 일어났다 (비공허)",
		data.strings.language() != before_language,
		"%s -> %s" % [before_language, data.strings.language()])
	var new_header := screen.get_node("%HeaderLabel") as Label
	_ok("표제가 새 언어로 재문면화",
		new_header.text == data.strings.text("ui.options.header"), new_header.text)
	_ok("표제가 진입 시점 문면과 다르다 (대조)", new_header.text != entry_header,
		"%s -> %s" % [entry_header, new_header.text])
	var new_tab_row := screen.get_node("%TabRow") as Control
	_ok("탭 이름이 새 언어로 재문면화",
		(new_tab_row.get_child(0) as Button).text
			== data.strings.text(String(OptionsStore.TABS[0]["key"])),
		(new_tab_row.get_child(0) as Button).text)
	# ⓑ 활성 탭·포커스가 유지된다 — 재구축의 대가를 물지 않는다.
	_ok("활성 탭 유지", screen._active_tab == language_tab,
		"tab=%d expected=%d" % [screen._active_tab, language_tab])
	var focused := screen.get_viewport().gui_get_focus_owner()
	_ok("포커스 유지 (재구축 뒤에도 조작 자리가 남는다)",
		focused != null and screen.is_ancestor_of(focused), str(focused))
	# ⓒ 이름 충돌이 남지 않았다 — queue_free 만 하고 다시 세우면 Tab0@2 가 생긴다.
	_ok("탭 줄에 유령 노드가 없다", new_tab_row.get_child_count() == OptionsStore.TABS.size(),
		"count=%d expected=%d" % [new_tab_row.get_child_count(), OptionsStore.TABS.size()])
	_unmount(screen)

	# ⓓ **대조군** — 비언어 항목은 재구축하지 않는다(노드 동일성이 유지된다).
	var s2 := _fresh_session(data)
	var plain := _mount(OPTIONS_SCENE, s2)
	if plain != null:
		var target := -1
		for index in range(OptionsStore.TABS.size()):
			var ids: Array = Array(OptionsStore.TABS[index]["options"])
			if not ids.is_empty() and not ids.has("o11"):
				target = index
				break
		_ok("전제: 비언어 항목 탭이 있다", target >= 0, "tab=%d" % target)
		if target >= 0:
			plain._select_tab(target)
			var panel2 := plain._tab_panels[target] as Control
			var next2 := panel2.find_child("Next", true, false) as Button
			_ok("전제: 비언어 행의 다음 버튼 실재", next2 != null)
			if next2 != null:
				var identity := plain.get_node("%TabRow").get_child(0)
				next2.pressed.emit()
				_ok("비언어 항목은 화면을 다시 세우지 않는다",
					plain.get_node("%TabRow").get_child(0) == identity)
		_unmount(plain)
	# 언어를 되돌린다 — 뒤 축들이 이 축의 부작용을 상속하면 안 된다. **저장소 먼저다**:
	# 런타임만 되돌리면 다음 세션이 저장분을 다시 적용한다.
	var after := _fresh_session(data)
	after.options.set_index("o11", before_index)
	data.set_language(before_language)
	_ok("언어 원복 (뒤 축 오염 방지)", data.strings.language() == before_language,
		data.strings.language())
	_ok("저장된 언어 선택지 원복 (다음 세션 오염 방지)",
		_fresh_session(data).options.index_of("o11") == before_index,
		"index=%d expected=%d" % [_fresh_session(data).options.index_of("o11"), before_index])


# ── ㉙ 포커스 링 9패치 (14차 ⑤ — 화면 층 결선 제원표 IMPL-405 부분 반영) ──
#
# **마진을 검사에 손으로 적지 않는다.** 값의 산지는 `frame_spec.json` 의 `corner` 이고
# 테마는 그것을 옮겨 적은 사본이므로, 검사는 **원본을 읽어 대조한다**(27차 "대장을 산문에서
# 코드로 옮기고 원본과 기계 대조한다"와 같은 축). 사본이 갈리면 여기서 깨진다.
const FRAME_SPEC := "res://../tools/assets/frame_spec.json"
const FOCUS_FRAME := "focus_ring_9p"
const FOCUS_TEXTURE := "res://assets/ui/frames/focus_ring_9p.png"


func _focus_ring_theme(data: GameData) -> void:
	var main_theme := load(FlowScreen.MAIN_THEME) as Theme
	_ok("전제: 화면 층 테마 적재", main_theme != null)
	if main_theme == null:
		return
	var box := main_theme.get_stylebox("focus", "Button") as StyleBoxTexture
	_ok("Button 포커스 = 9패치 텍스처 박스", box != null)
	if box == null:
		return
	_ok("포커스 링 도상 = focus_ring_9p",
		box.texture != null and String(box.texture.resource_path) == FOCUS_TEXTURE,
		String(box.texture.resource_path) if box.texture != null else "null")
	# 원본 대조 — corner 를 읽어 4면 마진과 맞춘다.
	var raw := FileAccess.get_file_as_string(FRAME_SPEC)
	var spec: Variant = JSON.parse_string(raw)
	var has_frames: bool = spec is Dictionary and Dictionary(spec).has("frames")
	_ok("전제: frame_spec 적재", has_frames, "len=%d" % raw.length())
	if has_frames:
		var frames: Dictionary = Dictionary(spec)["frames"]
		_ok("전제: %s 항목이 원본에 있다" % FOCUS_FRAME, frames.has(FOCUS_FRAME))
		if frames.has(FOCUS_FRAME):
			var corner := float(int(Dictionary(frames[FOCUS_FRAME])["corner"]))
			_ok("texture_margin 4면 = 원본 corner (%d)" % int(corner),
				box.texture_margin_left == corner and box.texture_margin_top == corner
					and box.texture_margin_right == corner
					and box.texture_margin_bottom == corner,
				"L=%.1f T=%.1f R=%.1f B=%.1f corner=%.1f" % [box.texture_margin_left,
					box.texture_margin_top, box.texture_margin_right,
					box.texture_margin_bottom, corner])
	# **14차의 선언 범위 축은 여기서 은퇴한다.** 그 축은 *"테마가 `focus` 밖을 선언하지
	# 않는다"* 였고, 그것이 곧 15차 ① 이 판정에 따라 하는 일이다(IMPL-439 ② ⓓ 채택).
	# 축을 남겨 두면 **결선 자체를 결함으로 보고**한다 — 14차에 로그 존 축을 슬롯으로 함께
	# 옮긴 것과 같은 형태다. 대신 **ⓓ 의 계약**을 못박는다(§`_frame_theme_contract`).
	_frame_theme_contract(main_theme)
	# 테마가 **단독 인스턴스화 경로에도** 붙는가 — 검사가 실기와 다른 화면을 재지 않게.
	var session := _fresh_session(data)
	var screen := _mount(RACE_SCENE, session)
	if screen != null:
		_ok("화면에 테마가 붙는다 (단독 경로 포함)", screen.theme != null, str(screen.theme))
		_ok("버튼이 테마 포커스 박스를 상속한다",
			screen._e08_confirm.get_theme_stylebox("focus", "Button") is StyleBoxTexture)
		_unmount(screen)


# ── ㉚ 액션 열 폭 · 화면 루트 최소 크기 (14차 ⑧ + ② grow 감사) ──
#
# **⑧** 내러티브 10차 관측 4.1 은 영문 여유를 산술로 45px(배지 2 포함 29px)로 내고
# "기본 테마 Button 의 좌우 content margin 이 측당 1.8px 보다 크면 넘친다"로 남겼다.
# 그 산술은 **문면 폭만** 셌다 — 실측 content margin 은 좌우 각 10.0px 이므로 버튼 8개가
# 160px 을 더 먹는다. 그래서 3언어 실측으로 답을 대신한다.
#
# **②** `anchors_preset 0 → 15` 재정규화가 `grow_*` 를 END→BOTH 로 바꾼다. 그 방향은
# **최소 크기가 앵커 rect 를 넘을 때만** 의미를 갖는다 — 넘지 않는다를 산문으로 두지 않고
# 화면 루트 최소 크기를 캔버스와 재서 못박는다.
const UI_SCREENS_SOURCE := "res://tests/test_ui_screens.gd"
# 초과 단언 2개소 — 만재 축과 3언어 축. **둘 다 본다**: 한쪽만 되돌려도 그 언어·그 구성이
# 조용히 천장을 되찾는다.
const ACTION_ROW_ZERO_ASSERTS := [
	"5슬롯 만재 액션 열이 예산 안 (초과 0)",
	"액션 열이 예산 안 (초과 0)\" % code",
]

const ROOT_MIN_SCENES := [
	"res://ui/sys/options_screen.tscn", "res://ui/sys/achievement_screen.tscn",
	"res://ui/hub/garage_screen.tscn", "res://ui/race/race_screen.tscn",
]

# ── 발주 대기 상한 = **철거** (총괄 판정 ③ · 30차 집행) ──
#
# 14차 ⑧ 이 세운 `ROW_OVERFLOW_CEILING := 41.0` 은 *"문면이 오면 이 값을 0 으로 내리는 것이
# 그 회차의 몫"* 이라고 스스로 적어 둔 값이었고, 문면이 왔다(㉝ · `chargeIntervene` en·ja
# 단축 — IMPL-441). **발주 대기 상한은 대기가 끝나면 대기가 아니다.**
#
# 함께 철거한 것이 **"상한이 실측 최악과 5px 안" 축**이다. 그 축은 *상한이 있는 동안*
# 상한이 면제로 굳지 않게 붙들던 보조 축이고, 상한이 사라지면 잴 대상이 없다 —
# 남겨 두면 `41.0 - 0.0 > 5.0` 으로 **없어진 것을 지키느라 붉어진다**(실측: 문면 착지 직후
# 그 상태였다). **가드는 자기가 지키던 것이 사라지면 함께 내려간다.**
#
# 대신 초과를 **상시 0 으로 단언**한다 — 천장이 없으면 초과는 결함이다.


# 원본에서 그 문면이 든 **단언 줄**을 뜬다 — 주석에 같은 말이 있어도 `_ok(` 로 시작하는
# 줄만 본다(문면이 주석에 남아 있고 단언은 사라진 상태를 통과시키지 않는다).
func _suite_line_with(source: String, marker: String) -> String:
	for line in source.split("\n"):
		var text := String(line).strip_edges()
		if text.begins_with("_ok(") and text.contains(marker):
			return text
	return ""


func _action_row_budget(data: GameData) -> void:
	var before_language := data.strings.language()
	var fits := 0
	# **음수까지 담는다** — 0 으로 시작하면 여유가 얼마든 `worst` 가 0 에 붙어 관측이
	# "딱 맞았다"로 읽힌다(철거 직후 실제로 그렇게 찍혔다).
	var worst := -INF
	for language in LANGUAGE_COLUMNS_EXPECTED:
		var code := String(language)
		# **세션을 먼저 세우고 언어를 그 뒤에 바꾼다.** `begin_career()` 가
		# `apply_language()` 를 타고 저장된 o11 로 되돌리므로 순서가 뒤집히면 세 번 모두
		# 같은 언어를 재고, 그때 값이 같은 것은 통과가 아니라 **측정이 안 된 증거**다.
		var session := _fresh_session(data)
		var switched: bool = data.set_language(code)
		var screen := _mount(RACE_SCENE, session)
		if screen == null:
			continue
		# 전제는 **마운트 뒤**에 본다 — 화면이 세워지는 사이에 되돌려질 수 있고,
		# 되돌려진 채로 재면 라벨이 다른 언어다.
		_ok("[%s] 전제: 측정 시점 언어가 그 언어" % code,
			switched and data.strings.language() == code, data.strings.language())
		screen.engine.deck = _widest_deck(data, 5)
		screen.engine.charge = 10
		screen._refresh_skill_slots()
		screen._apply_static_strings()
		var metrics := _action_row_metrics(screen)
		_ok("[%s] 전제: 폭 산정 성립" % code, not metrics.is_empty())
		if not metrics.is_empty():
			var budget: float = float(metrics["budget"])
			var needed: float = float(metrics["needed"])
			var over: float = needed - budget
			# ── ⚠ 덱 구성 전수 관측 (30차 신설 — 내러티브 11차 인계 관측의 실측) ──
			#
			# **판정은 만재 5기가 하고, 관측은 전 구성이 한다.** 잠금 슬롯 문면
			# (`ui.race.locked`)이 장착 슬롯 문면보다 **넓을 수 있고**, 만재만 재면 그
			# 조합이 측정 밖에 남는다. 실측 결과 **en 2슬롯(잠금 3) 조합이 2.4px 넘는다** —
			# `Locked` 가 `S{n} ◆2` 보다 길다.
			#
			# **판정으로 올리지 않은 것은 처분이 내 경로 밖이기 때문이다** — 문면(내러티브)
			# 이거나 배치(주력)다. 여기서 차단으로 세우면 남의 몫이 내 게이트를 붙든다.
			# 대신 **매 주행 숫자를 찍어** 관측이 잊히지 않게 하고, 훑기가 실제로 돌았는지를
			# 비공허성으로 못박는다(관측이 조용히 0회가 되면 그것도 침묵이다).
			var swept := 0
			var deck_worst := -INF
			var deck_worst_size := 0
			for deck_size in range(1, 6):
				screen.engine.deck = _widest_deck(data, deck_size)
				screen._refresh_skill_slots()
				var m := _action_row_metrics(screen)
				if m.is_empty():
					continue
				swept += 1
				if float(m["needed"]) - float(m["budget"]) > deck_worst:
					deck_worst = float(m["needed"]) - float(m["budget"])
					deck_worst_size = deck_size
			_ok("[%s] 전제: 덱 구성 전수 훑기 5회" % code, swept == 5, str(swept))
			print("  [관측] [%s] 덱 전수 최악 = %d슬롯 · 초과 %+.1fpx"
				% [code, deck_worst_size, deck_worst])
			screen.engine.deck = _widest_deck(data, 5)
			screen._refresh_skill_slots()
			worst = maxf(worst, over)
			if over <= 0.0:
				fits += 1
			_ok("[%s] 전제: 예산이 릴 열보다 넓다 (산정 실패 오탐 방지)" % code, budget > 208.0,
				"budget=%.1f" % budget)
			_ok("[%s] 액션 열이 예산 안 (초과 0)" % code, over <= 0.0,
				"needed=%.1f budget=%.1f 초과=%.1f" % [needed, budget, over])
		_unmount(screen)
	# **계수로도 센다** — 언어별 축은 `metrics` 가 비면 건너뛰므로, 세 언어가 **실제로
	# 재였고 전건 들어왔다**는 사실은 따로 세야 한다(건너뛴 것과 통과한 것은 다른 사실이다).
	_ok("3언어 전건 예산 안 (측정 누락 0)", fits == LANGUAGE_COLUMNS_EXPECTED.size(),
		"fits=%d / %d" % [fits, LANGUAGE_COLUMNS_EXPECTED.size()])
	# ── 철거가 되돌려지지 않았는가 (30차 신설) ──
	#
	# **느슨해지는 변경은 거동으로 잡히지 않는다** — `over <= 0` 을 `<= 41` 로 되돌려도
	# 지금 값이 통과하므로 아무 축도 붉어지지 않고 검사 수도 그대로다(반증 P4·P6 실측
	# 미검출). ANCH·STRF·FXPL 의 *"경고 호출 잔존 0"* 과 같은 성격의 원본 대조를 세운다.
	#
	# **이 축의 한계를 적어 둔다**: 상수 이름을 바꾸거나 문면을 고치면 빠져나간다.
	# 거동 축보다 약하지만, *되돌림*은 거동으로 잴 수 없으므로 이것이 남는 도구다.
	var suite_source := FileAccess.get_file_as_string(UI_SCREENS_SOURCE)
	_ok("스위트 원본 적재", not suite_source.is_empty())
	# **문자열을 쪼갠다** — 붙여 두면 이 줄 자체가 원본에 남아 검사가 자기를 잡는다
	# (초판이 그대로 붉어졌다 — V2 접두 리터럴 분할과 같은 형태).
	_ok("발주 대기 상한 상수 잔존 0 (선언)",
		not suite_source.contains("const " + "ROW_OVERFLOW_CEILING"))
	for marker in ACTION_ROW_ZERO_ASSERTS:
		var line := _suite_line_with(suite_source, String(marker))
		_ok("초과 단언이 0 그대로: %s" % String(marker), line.contains("<= 0.0"), line)
	_ok("3언어 계수 축이 전건 단언 그대로",
		_suite_line_with(suite_source, "3언어 전건 예산 안")
			.contains("LANGUAGE_COLUMNS_EXPECTED.size()"))
	# 최악 여유를 **관측으로 남긴다** — 판정하지 않는다(문턱이 없으므로). 철거 시점 실측:
	# ko 가 구속 조건이고 여유가 가장 얇다(내러티브 11차 관측 — en 7.6 · ja 6.6 · ko 2.6).
	print("  [측정] 액션 열 3언어 최악 초과 %+.1fpx (음수 = 여유)" % worst)
	var restored: bool = data.set_language(before_language)
	_ok("언어 원복 (뒤 축 오염 방지)",
		restored and data.strings.language() == before_language, data.strings.language())

	# 화면 루트 최소 크기 ≤ 캔버스 — grow 방향이 무영향임의 근거.
	for path in ROOT_MIN_SCENES:
		var session2 := _fresh_session(data)
		var screen2 := _mount(String(path), session2)
		if screen2 == null:
			continue
		var minimum := screen2.get_combined_minimum_size()
		_ok("루트 최소 크기 <= 캔버스: %s" % String(path).get_file(),
			minimum.x <= CANVAS.x and minimum.y <= CANVAS.y,
			"min=%s canvas=%s" % [str(minimum), str(CANVAS)])
		_unmount(screen2)


# ── ㉕ E15 씬 패널 — 레이어 순서·요소 합성 (29차 · 사양서 v1.11 §5.2.2) ──
#
# **순서가 곧 계약이다**: 원경 → 머신 → 근경 → 요소. 근경이 머신 위인 것이 배경 2레이어
# 분리의 목적이며(§5.1 "컷 합성용"), 뒤집으면 분리가 무의미해진다.
const SCENE_PANEL_NODE := "ScenePanel"
# **fx 가 두 대역으로 갈렸다** (31차 · 총괄 판정 ③) — 오라는 차 뒤, 불꽃은 차 앞.
const SCENE_LAYER_ORDER := ["Far", "FxBehind", "Machines", "Near", "FxFront"]
# 팀이 서로 다른 네임드 상대 2인 — 섀시가 갈려야 배정이 무동작인지 알 수 있다.
const NAMED_RIVALS := ["ai_lorentz", "ai_jude"]


func _scene_panel_layers(data: GameData) -> void:
	var screen := _new_race_screen()
	if screen == null:
		return
	var panel: ScenePanel = screen._scene_panel
	_ok("씬 패널 실물 실재", panel != null)
	if panel == null:
		_unmount(screen)
		return
	_ok("씬 패널 = E15 슬롯 안", panel.get_parent().name == "E15ScenePanel",
		String(panel.get_parent().name))
	_ok("씬 패널 비인터랙티브 (별첨A §127)",
		panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var canvas := panel.get_node_or_null("Canvas") as Control
	_ok("합성 캔버스 실재", canvas != null)
	if canvas == null:
		_unmount(screen)
		return
	var order: Array = []
	for child in canvas.get_children():
		order.append(String(child.name))
	_ok("레이어 순서 = 원경→머신→근경→요소", order == SCENE_LAYER_ORDER, str(order))
	# 원도 그대로여야 한다 — 신축이 들어가면 도트가 뭉갠다.
	_ok("캔버스 폭 = 제작 원도", is_equal_approx(canvas.size.x,
		data.param("param_scene_canvas_width_px")), str(canvas.size.x))
	var far := canvas.get_node("Far") as TextureRect
	var near := canvas.get_node("Near") as TextureRect
	var machines := canvas.get_node("Machines") as Control
	_ok("원경 텍스처 실재", far.texture != null)
	_ok("근경 텍스처 실재", near.texture != null)
	_ok("원경 ≠ 근경 (같은 파일을 두 번 얹지 않는다)", far.texture != near.texture)
	_ok("머신 층 1대 이상", machines.get_child_count() >= 1, str(machines.get_child_count()))

	# ── 머신 자리 = 노면선 앵커 − 섀시 오프셋 (31차 · 총괄 판정 ② ⓑ) ──
	#
	# **32차에 축이 좁아졌다.** 자리 표가 `sprite` 대신 `occupant` 를 이고(에셋 IMPL-452 —
	# 검수 표본은 런타임 데이터가 아니다), `rival`·`grid` 는 팀↔섀시 결속이 없어 아직
	# 그리지 못한다. 그래서 **그려지는 것은 `player` 자리뿐**이고 나머지는 관측에 남는다.
	# 오프셋 축의 "짝 어긋내기"는 결속이 서면 되돌아온다 — 지금은 잴 짝이 없다.
	# **네임드 상대로 세운다** (33차 결선) — 팀↔섀시 결속은 `ai_rivals` 에 등재된 상대에만
	# 선다. 기본 필드는 필러가 대부분이라 화면 배정을 그대로 쓰면 결속이 아니라 **미결속**을
	# 재게 된다(실측: 인접이 `filler_07`). 결속 축과 미결속 축을 **따로** 세운다.
	var assigned := {"rival": [NAMED_RIVALS[0], NAMED_RIVALS[1]]}
	_ok("전제: 두 상대의 팀 섀시가 서로 다르다 (축 비공허)",
		data.rival_chassis(NAMED_RIVALS[0]) != data.rival_chassis(NAMED_RIVALS[1]),
		"%s vs %s" % [data.rival_chassis(NAMED_RIVALS[0]), data.rival_chassis(NAMED_RIVALS[1])])
	panel.show_cut("cut_basic_group", screen._active_stage_id(), assigned)
	# **정렬을 검사가 스스로 한다.** 창구가 돌려준 순서를 그대로 쓰면 창구가 순서를 뒤집어도
	# 노드와 행이 함께 뒤집혀 통과한다(반증 Q10 초판 미검출). `slot_order` 로 여기서 세운다.
	var rows: Array = data.scene_cut_machines_for("cut_basic_group").duplicate()
	rows.sort_custom(func(a, b):
		return CsvTable.to_int(String(a["slot_order"])) < CsvTable.to_int(String(b["slot_order"])))
	_ok("전제: 집단 컷 선언 3대", rows.size() == 3, str(rows.size()))
	# 배정이 서면 **선언 대수 전량**이 그려진다 — 미결속 0 이 결선의 증명이다.
	_ok("머신 노드 = 선언 대수 (결속 완료)", machines.get_child_count() == rows.size(),
		str(machines.get_child_count()))
	_ok("미결속 자리 0 (33차 결선)", panel.unbound_occupants.is_empty(),
		str(panel.unbound_occupants))
	# **팀이 차를 갖는다** — 인접 상대의 팀 섀시가 그려져야 한다. 짝을 어긋나게 고른다:
	# 플레이어 자리와 상대 자리의 섀시가 같으면 배정이 무동작이어도 통과한다.
	var drawn: Array = []
	for node in machines.get_children():
		drawn.append(String(node.get_meta(ScenePanel.MACHINE_SPRITE_META, "")))
	_ok("플레이어 섀시가 정확히 1대", drawn.count(ScenePanel.PLAYER_MACHINE) == 1, str(drawn))
	for rival_id in NAMED_RIVALS:
		_ok("배정 상대 '%s' 의 팀 섀시가 그려졌다" % String(rival_id),
			drawn.has(data.rival_chassis(String(rival_id))), str(drawn))
	for index in range(mini(rows.size(), machines.get_child_count())):
		var row: Dictionary = rows[index]
		var node := machines.get_child(index) as TextureRect
		var sprite := String(node.get_meta(ScenePanel.MACHINE_SPRITE_META, ""))
		var expected_center := Vector2(
			float(CsvTable.to_int(String(row["anchor_x"]))),
			float(CsvTable.to_int(String(row["anchor_road_y"]))
				- data.machine_baseline(sprite)))
		_ok("%s 셀 중심 = 노면선 − 오프셋" % String(row["slot_name"]),
			node.position + node.size * 0.5 == expected_center,
			"%s vs %s" % [str(node.position + node.size * 0.5), str(expected_center)])
		# 오프셋이 실제로 쓰였는가 — 0 이면 노면선이 곧 중심이 되어 차가 뜬다.
		_ok("%s 오프셋 비영 (축 비공허)" % String(row["slot_name"]),
			data.machine_baseline(sprite) != 0, str(data.machine_baseline(sprite)))
	# ── 실 필드 경로 (34차 — 필러 결속 유입 후) ──
	#
	# **33차의 미결속 축은 내려갔다.** 그 축은 *필러에 섀시가 없다*는 사실을 붙들던 가드이고,
	# 에셋 실물(변조 4종 · IMPL-461)과 결속이 들어왔으므로 붙들 것이 없다 —
	# "가드는 자기가 지키던 것이 사라지면 함께 내려간다"의 세 번째 적용이다.
	#
	# 대신 **실기 경로 그 자체**를 잰다: 화면이 배정한 실 인접 참가자로 컷이 서는가.
	# 기본 필드는 필러가 대부분이므로 이 경로가 실물 플레이에서 늘 밟히는 자리다.
	var live: Dictionary = screen._scene_occupants()
	var live_rivals: Array = Array(live.get("rival", []))
	_ok("전제: 실 필드가 인접 참가자를 낸다", not live_rivals.is_empty(), str(live_rivals))
	panel.show_cut("cut_overtake", screen._active_stage_id(), {"rival": live_rivals})
	_ok("실 필드 경로 = 미결속 0", panel.unbound_occupants.is_empty(),
		str(panel.unbound_occupants))
	_ok("실 필드 경로 = 선언 대수 전량",
		machines.get_child_count() == data.scene_cut_machines_for("cut_overtake").size(),
		str(machines.get_child_count()))
	for node in machines.get_children():
		_ok("실 필드 섀시가 대장 안",
			data.machine_baselines.has(
				String(node.get_meta(ScenePanel.MACHINE_SPRITE_META, ""))),
			String(node.get_meta(ScenePanel.MACHINE_SPRITE_META, "")))
	# ── 그리드 자리 = 자리 이름의 `p<n>` 이 순위다 (도구 명문) ──
	# **짝을 어긋나게 고른다**: 순위 순서와 그리는 순서가 다르므로(도열은 2×2 지그재그)
	# 파싱을 지우면 자리마다 다른 차가 온다. 배정도 서로 다른 팀으로 세운다.
	var grid_ids: Array = [NAMED_RIVALS[0], NAMED_RIVALS[1], NAMED_RIVALS[0], NAMED_RIVALS[1]]
	panel.show_cut("cut_start", screen._active_stage_id(), {"grid": grid_ids})
	var start_rows: Array = data.scene_cut_machines_for("cut_start").duplicate()
	start_rows.sort_custom(func(a, b):
		return CsvTable.to_int(String(a["slot_order"])) < CsvTable.to_int(String(b["slot_order"])))
	_ok("전제: 도열 4대", start_rows.size() == 4, str(start_rows.size()))
	_ok("도열 노드 = 선언 대수", machines.get_child_count() == start_rows.size(),
		str(machines.get_child_count()))
	for index in range(mini(start_rows.size(), machines.get_child_count())):
		var slot_name := String(start_rows[index]["slot_name"])
		var rank := panel._grid_rank(slot_name)
		_ok("자리 '%s' 이름이 순위 부호를 갖는다" % slot_name, rank >= 1 and rank <= 4, str(rank))
		var node := machines.get_child(index) as TextureRect
		_ok("자리 '%s' = 그리드 %d번의 섀시" % [slot_name, rank],
			String(node.get_meta(ScenePanel.MACHINE_SPRITE_META, ""))
			== data.rival_chassis(String(grid_ids[rank - 1])),
			String(node.get_meta(ScenePanel.MACHINE_SPRITE_META, "")))

	# **선언이 없는 1대 컷은 표준 자리다** — 폴백이 아니라 제원표 §4 그 자체다.
	panel.show_cut("cut_finish", screen._active_stage_id())
	_ok("전제: 피니시는 자리 선언이 없다",
		data.scene_cut_machines_for("cut_finish").is_empty())
	_ok("자리 미선언 = 1대", machines.get_child_count() == 1,
		str(machines.get_child_count()))
	var standalone := machines.get_child(0) as TextureRect
	_ok("자리 미선언 = 표준 자리 (제원표 §4)",
		is_equal_approx(standalone.position.x, data.param("param_scene_machine_x"))
		and is_equal_approx(standalone.position.y, data.param("param_scene_machine_y")),
		str(standalone.position))
	# 선언이 들어왔으므로 다대 미배치 관측은 **비어야** 한다 (30차 미결의 폐문 증명).
	_ok("다대 미배치 관측 0 (선언 유입 폐문)", panel.multi_machine_omissions.is_empty(),
		str(panel.multi_machine_omissions))

	# ── fx z 대역 — 오라는 뒤, 불꽃은 앞 (총괄 판정 ③) ──
	panel.show_cut("cut_duel_standoff", screen._active_stage_id())
	_ok("오라 = 머신 뒤 대역",
		(canvas.get_node("FxBehind") as Control).get_child_count() == 1
		and (canvas.get_node("FxFront") as Control).get_child_count() == 0,
		"뒤 %d · 앞 %d" % [(canvas.get_node("FxBehind") as Control).get_child_count(),
			(canvas.get_node("FxFront") as Control).get_child_count()])
	panel.show_cut("cut_close_battle", screen._active_stage_id())
	_ok("불꽃 = 머신 앞 대역",
		(canvas.get_node("FxFront") as Control).get_child_count() == 1
		and (canvas.get_node("FxBehind") as Control).get_child_count() == 0,
		"뒤 %d · 앞 %d" % [(canvas.get_node("FxBehind") as Control).get_child_count(),
			(canvas.get_node("FxFront") as Control).get_child_count()])
	_unmount(screen)


# ── ㉖ 국면 거동 — 릴 고정 / 전개 매핑 / O12 / 완급 비트 스킵 ──
#
# **릴 국면이 결과를 모른다는 것을 거동으로 잰다.** 확정 이벤트를 넣어도 릴 국면 컷이
# 바뀌지 않아야 한다 — 봉인의 화면 층 형태다(불변규칙 5).
func _scene_panel_phase(data: GameData) -> void:
	var screen := _new_race_screen()
	if screen == null:
		return
	var panel: ScenePanel = screen._scene_panel
	if panel == null:
		_unmount(screen)
		return
	# ⓐ 진입 = 릴 국면 고정 컷 + 모션 정지
	_ok("진입 = 기본 주행 고정",
		String(panel._cut_id).begins_with("cut_basic_"), String(panel._cut_id))
	_ok("릴 국면 = 모션 정지", not panel._motion_enabled)
	# ── 감광 (34차 종결 — D13 별첨A §8.1 v1.12 = 0.70) ──
	# **값을 검사에 적지 않는다** — 데이터 창구에서 받아 대조한다. 적으면 표를 바꿔도
	# 검사가 옛 값으로 통과하고, 그 순간 "확정 기준값 경유"라는 계약이 거짓이 된다.
	var dim_level := data.param("param_scene_panel_dim")
	_ok("전제: 감광 배율이 1 미만 (축 비공허)", dim_level < 1.0 and dim_level > 0.0,
		str(dim_level))
	_ok("릴 국면 = 감광 적용", is_equal_approx(panel.modulate.r, dim_level),
		str(panel.modulate))
	_ok("감광은 색이 아니라 밝기 (회색 곱연산)",
		is_equal_approx(panel.modulate.r, panel.modulate.g)
		and is_equal_approx(panel.modulate.g, panel.modulate.b), str(panel.modulate))
	# **값을 갈아 끼워 거동이 따라오는지 본다.** 현행 값과 대조만 하면 상수 기입(0.7)이
	# 그대로 통과한다 — 지금 값이 맞아서 통과하는 것과 창구를 거쳐서 통과하는 것을
	# 구분하지 못한다(반증 W4 초판 미검출 · 섀시 임계 픽스처 축과 같은 형태).
	# **패널이 쥔 데이터를 갈아 끼운다** — 검사가 든 `data` 와 화면이 든 것이 다른 인스턴스면
	# 값을 바꿔도 거동이 안 바뀌고, 그 무동작이 "통과"로 보인다(초판 실측).
	var panel_data: GameData = panel.data
	var restore_dim: float = panel_data.params["param_scene_panel_dim"]
	panel_data.params["param_scene_panel_dim"] = restore_dim * 0.5
	panel.set_dim(true)
	_ok("감광이 데이터 창구를 따른다 (상수 기입 아님)",
		is_equal_approx(panel.modulate.r, restore_dim * 0.5), str(panel.modulate))
	panel_data.params["param_scene_panel_dim"] = restore_dim
	panel.set_dim(true)
	# ⓑ 전개 국면 — **짝을 어긋나게 고른다**: 트러블과 추월은 서로 다른 컷이어야 한다.
	screen._show_result_cut([{"key": "raceLog.troubleHit01"}], false, false)
	var trouble_cut := String(panel._cut_id)
	screen._show_result_cut([{"key": "raceLog.overtakeSuccess01"}], false, false)
	var overtake_cut := String(panel._cut_id)
	_ok("트러블 확정 = 트러블 컷", trouble_cut == "cut_trouble", trouble_cut)
	_ok("추월 확정 = 추월 컷", overtake_cut == "cut_overtake", overtake_cut)
	_ok("전제: 두 컷이 다르다", trouble_cut != overtake_cut)
	_ok("전개 국면 = 모션 재개", panel._motion_enabled)
	_ok("전개 국면 = 감광 해제", is_equal_approx(panel.modulate.r, 1.0), str(panel.modulate))
	# ⓒ 요소 층이 실제로 섰는가 — 합성 선언이 노드로 옮겨졌는지
	var fx_root := panel.get_node("Canvas/FxBehind") as Control
	_ok("추월 컷 요소 층 = 선언 수",
		fx_root.get_child_count() == data.scene_cut_layers_for("cut_overtake").size(),
		str(fx_root.get_child_count()))
	# ⓓ 릴 국면 복귀 — 결과를 넣어도 기본 주행으로 돌아온다
	screen._show_reel_phase_cut()
	_ok("릴 국면 복귀 = 기본 주행",
		String(panel._cut_id).begins_with("cut_basic_"), String(panel._cut_id))
	_ok("릴 국면 복귀 = 모션 정지", not panel._motion_enabled)
	_ok("릴 국면 복귀 = 감광 재적용", is_equal_approx(panel.modulate.r, dim_level),
		str(panel.modulate))
	# ⓔ O12 정지 컷 — 접근성 폴백 (D09 §6.1)
	screen.session.options.set_index("o12", 1)
	screen._show_result_cut([{"key": "raceLog.overtakeSuccess01"}], false, false)
	_ok("O12 정지 컷 = 모션 없음", not panel._motion_enabled)
	screen.session.options.set_index("o12", 0)
	# ⓕ 완급 비트 스킵 — 확정 입력이 즉시 통과시킨다 (D09 §3.1.1)
	screen._pacing_beat_left = data.param("param_pacing_beat_max_sec")
	screen._on_primary_action()
	_ok("완급 비트 = 확정 입력으로 즉시 통과",
		is_equal_approx(screen._pacing_beat_left, 0.0), str(screen._pacing_beat_left))
	# ⓖ 비트 예산 — 재생 상한 × 발동 빈도 ≤ 턴당 +2초 (D09 §3.1.1 구속)
	_ok("완급 비트 예산 = 턴당 평균 +2초 이내",
		data.param("param_pacing_beat_max_sec")
		* data.param("param_pacing_beat_probability") <= 2.0,
		str(data.param("param_pacing_beat_max_sec")
			* data.param("param_pacing_beat_probability")))
	# ⓘ **대표 프레임을 실제로 잘라 쓰는가** (E-04 `still_frame: 2` 소비 — 사용자 판정 IMPL-390).
	#    시트를 통째로 얹으면 5칸이 가로로 늘어선 채 뜬다 — 화면에서 "정지"로 보이지 않는다.
	screen._show_result_cut([], false, false)
	panel.show_cut("cut_close_battle", screen._active_stage_id())
	var spark := (panel.get_node("Canvas/FxFront") as Control).get_child(0) as TextureRect
	var atlas := spark.texture as AtlasTexture
	_ok("시트 요소 = AtlasTexture 로 한 칸만", atlas != null)
	if atlas != null:
		var element := data.fx_element("fxe_contact_spark")
		var cell_w := CsvTable.to_int(String(element["cell_w"]))
		var still := CsvTable.to_int(String(element["still_frame"]))
		_ok("잘라낸 칸 = 표의 대표 프레임",
			is_equal_approx(atlas.region.position.x, float(cell_w * still))
			and is_equal_approx(atlas.region.size.x, float(cell_w)),
			str(atlas.region))
		_ok("전제: 대표 프레임이 0 이 아니다 (0 이면 축이 공허하다)", still > 0, str(still))
	# ⓙ **움직임의 진폭이 요소 자신의 치수인가** — 상수를 적으면 여기서 갈린다.
	#    한 바퀴(마지막 프레임)에서 스크롤 오프셋 = 셀 폭 × (frames-1)/frames.
	panel.show_cut("cut_basic_solo", screen._active_stage_id())
	var lines := (panel.get_node("Canvas/FxBehind") as Control).get_child(0) as TextureRect
	var base_x := lines.position.x
	var frames := CsvTable.to_int(String(data.scene_cut("cut_basic_solo")["frames"]))
	var line_cell := CsvTable.to_int(String(data.fx_element("fxe_speed_lines")["cell_w"]))
	panel._apply_frame(frames - 1)
	_ok("스크롤 진폭 = 셀 폭 (루프가 구조적으로 닫힌다)",
		is_equal_approx(lines.position.x - base_x,
			float(line_cell) * float(frames - 1) / float(frames)),
		"%f vs %f" % [lines.position.x - base_x,
			float(line_cell) * float(frames - 1) / float(frames)])
	panel._apply_frame(0)
	_ok("0 프레임 = 원자리 복귀", is_equal_approx(lines.position.x, base_x))
	# ⓗ **미배치 관측 축은 내려갔다** (31차). 29차에 세운 것은 *배치 선언이 없다*는
	#    사실을 붙들던 가드이고, 선언이 들어왔으므로(에셋 IMPL-444) 붙들 것이 없다 —
	#    남기면 *없어진 것을 지키느라* 붉어진다(30차 상한 철거와 같은 자리).
	#    폐문 증명은 ㉕ 이 진다: **관측이 비어 있는가**를 그쪽이 단언한다.
	_unmount(screen)


# ── ㉛ 프레임 결선 ⓓ 계약 (15차 ① · 총괄 판정 IMPL-439 ②) ──
#
# 14차는 *"테마가 `focus` 밖을 선언하지 않는다"* 로 예산 이동을 막았다. 이제 판정이
# 선언을 지시했으므로 **막는 축이 아니라 계약을 재는 축**이 필요하다.
#
# ⓓ 의 계약은 세 줄이다.
#   ① 프레임 텍스처 = **의미 전속** — `normal`·`hover`·`pressed` 가 **같은 텍스처**다.
#      텍스처가 상태를 말하기 시작하면 의미 축이 상태 축으로 바뀐다(주력 14차 §5.2 의 경고).
#   ② `pressed` 의 표현 = `content_margin` **종방향 1px 이동 · 상하 합 불변**.
#      실제로 움직였는가(비공허)와 합이 같은가(예산 0)를 **둘 다** 본다 — 하나만 보면
#      "아무것도 안 하는 pressed" 또는 "예산을 먹는 pressed" 중 하나가 통과한다.
#   ③ 좌우 마진 = `normal` 과 동일 — 폭 예산 0.
const FRAME_SEMANTICS := {
	"Button": "button_default_9p",
	"PrimaryButton": "button_primary_9p",
	"DangerButton": "button_danger_9p",
}
const FRAME_DIR := "res://assets/ui/frames/"
const STATE_STYLES := ["normal", "hover", "pressed"]
# 소비부가 없어 **결선하지 않은** 프레임 4종. 사유를 산문으로 두지 않고 **부재를 기계로**
# 확인한다 — 소비 노드가 생기면 이 축이 먼저 붉어져 결선을 요구한다.
const UNWIRED_BY_ABSENCE := {
	"input_field_9p": "LineEdit",
	"tab_9p": "TabBar",
	"list_row_9p": "ItemList",
	"key_cap_9p": "Tree",
}


func _frame_corner(frames: Dictionary, frame_id: String) -> float:
	if not frames.has(frame_id):
		return -1.0
	return float(int(Dictionary(frames[frame_id])["corner"]))


func _frame_theme_contract(main_theme: Theme) -> void:
	var raw := FileAccess.get_file_as_string(FRAME_SPEC)
	var spec: Variant = JSON.parse_string(raw)
	var has_frames: bool = spec is Dictionary and Dictionary(spec).has("frames")
	_ok("전제: frame_spec 적재 (결선 대조)", has_frames)
	if not has_frames:
		return
	var frames: Dictionary = Dictionary(spec)["frames"]
	for type_name in FRAME_SEMANTICS:
		var frame_id := String(FRAME_SEMANTICS[type_name])
		var boxes: Dictionary = {}
		for style_name in STATE_STYLES:
			boxes[style_name] = main_theme.get_stylebox(String(style_name), String(type_name)) \
				as StyleBoxTexture
		_ok("[%s] 상태 3종이 전부 9패치 텍스처 박스" % String(type_name),
			boxes["normal"] != null and boxes["hover"] != null and boxes["pressed"] != null)
		if boxes["normal"] == null or boxes["hover"] == null or boxes["pressed"] == null:
			continue
		var want := FRAME_DIR + frame_id + ".png"
		# ① 의미 전속 — 세 상태가 **같은 텍스처**.
		var paths: Array = []
		for style_name in STATE_STYLES:
			var tex: Texture2D = boxes[style_name].texture
			paths.append(String(tex.resource_path) if tex != null else "null")
		_ok("[%s] 의미 전속 — 상태 3종이 같은 텍스처" % String(type_name),
			paths[0] == paths[1] and paths[1] == paths[2], str(paths))
		_ok("[%s] 그 텍스처 = %s" % [String(type_name), frame_id], paths[0] == want, str(paths[0]))
		# 원본 대조 — texture_margin 4면 = frame_spec corner.
		var corner := _frame_corner(frames, frame_id)
		_ok("[%s] 전제: %s 가 원본에 있다" % [String(type_name), frame_id], corner >= 0.0)
		if corner >= 0.0:
			var box: StyleBoxTexture = boxes["normal"]
			_ok("[%s] texture_margin 4면 = 원본 corner (%d)" % [String(type_name), int(corner)],
				box.texture_margin_left == corner and box.texture_margin_top == corner
					and box.texture_margin_right == corner and box.texture_margin_bottom == corner,
				"L=%.1f T=%.1f R=%.1f B=%.1f" % [box.texture_margin_left, box.texture_margin_top,
					box.texture_margin_right, box.texture_margin_bottom])
		# ②③ pressed = 종방향 1px 이동 · 상하 합 불변 · 좌우 동일.
		var base: StyleBoxTexture = boxes["normal"]
		var down: StyleBoxTexture = boxes["pressed"]
		_ok("[%s] pressed 좌우 마진 = normal (폭 예산 0)" % String(type_name),
			down.content_margin_left == base.content_margin_left
				and down.content_margin_right == base.content_margin_right,
			"L %.1f→%.1f R %.1f→%.1f" % [base.content_margin_left, down.content_margin_left,
				base.content_margin_right, down.content_margin_right])
		_ok("[%s] pressed 상하 합 불변 (높이 예산 0)" % String(type_name),
			is_equal_approx(down.content_margin_top + down.content_margin_bottom,
				base.content_margin_top + base.content_margin_bottom),
			"합 %.1f → %.1f" % [base.content_margin_top + base.content_margin_bottom,
				down.content_margin_top + down.content_margin_bottom])
		# **비공허성** — 합만 보면 "아무것도 안 하는 pressed" 가 통과한다.
		_ok("[%s] pressed 가 실제로 1px 내려간다 (비공허)" % String(type_name),
			is_equal_approx(down.content_margin_top - base.content_margin_top, 1.0),
			"top %.1f → %.1f" % [base.content_margin_top, down.content_margin_top])
	# ── 레이아웃 불변을 **실측으로** 잰다 ──
	#
	# 14차의 같은 이름 축은 포커스 전속 테마에서 **구조적으로 실패할 수 없었다**(`focus` 는
	# `Button` 최소 크기에 참여하지 않는다 — M16 미검출). 이제 테마가 `normal` 계열을 가지므로
	# **그 축이 살아난다** — 마진을 잘못 잡으면 여기서 즉시 붉어진다(실측: content 8 로 두면
	# 버튼당 +8px · 액션 열 371.0 → 435.0).
	var probe := Button.new()
	root.add_child(probe)
	probe.add_theme_font_size_override("font_size", 9)
	probe.text = "S1"
	var bare := probe.get_combined_minimum_size()
	probe.theme = main_theme
	var themed := probe.get_combined_minimum_size()
	_ok("테마가 버튼 최소 크기를 바꾸지 않는다 (폭·높이 예산 0)", bare == themed,
		"bare=%s themed=%s" % [str(bare), str(themed)])
	root.remove_child(probe)
	probe.queue_free()
	# ── 미결선 4종 = 소비 노드 부재의 기계 확인 ──
	#
	# *"소비부가 없어서 안 걸었다"* 는 산문이면 다음 회차에 조용히 틀린다. 노드 종류가
	# 하나라도 생기면 이 축이 먼저 붉어지고, 그때가 그 프레임을 거는 회차다.
	for frame_id in UNWIRED_BY_ABSENCE:
		var node_type := String(UNWIRED_BY_ABSENCE[frame_id])
		_ok("미결선 %s — 소비 노드(%s) 부재 확인" % [String(frame_id), node_type],
			not _scene_sources_contain('type="%s"' % node_type), node_type)


# 씬 원본에 그 노드 종류가 실재하는가. **씬 파일을 직접 훑는다** — 마운트해서 찾으면
# 그 회차에 마운트한 화면만 보게 되고, 안 세운 화면은 부재로 오독된다.
const SCENE_ROOTS := ["res://ui"]


func _scene_sources_contain(needle: String) -> bool:
	var pending: Array = SCENE_ROOTS.duplicate()
	while not pending.is_empty():
		var dir_path := String(pending.pop_back())
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := dir_path + "/" + entry
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(full)
			elif entry.ends_with(".tscn"):
				if FileAccess.get_file_as_string(full).contains(needle):
					dir.list_dir_end()
					return true
			entry = dir.get_next()
		dir.list_dir_end()
	return false


# ── ㉜ 색각 대체 프레임 결속 (15차 ① · 에셋 IMPL-443) ──
#
# 위험 프레임만 **텍스처 교체**다 — 런타임 틴트로는 정본 §6 색을 재현할 수 없다(색상 회전은
# 곱으로 표현되지 않는다). 그래서 O9 가 색 상수만 갈면 **위험 버튼만 적색으로 남는다.**
# 축은 그 남음을 잡는다: 모드를 실제로 켜고 **테마가 든 텍스처**를 본다.
const DANGER_BASE := "res://assets/ui/frames/button_danger_9p.png"
const DANGER_ALT := "res://assets/ui/frames/button_danger_alt_9p.png"


func _danger_frame_colorblind(data: GameData) -> void:
	var before := UiPalette.colorblind
	var main_theme := UiTheme.main()
	_ok("전제: 테마 적재", main_theme != null)
	if main_theme == null:
		return
	_ok("전제: 대체 원도가 실물로 있다", ResourceLoader.exists(DANGER_ALT), DANGER_ALT)
	_ok("전제: 기본과 대체가 다른 파일 (같으면 교체가 무의미)", DANGER_BASE != DANGER_ALT)
	for mode in [false, true, false]:
		UiPalette.colorblind = mode
		UiTheme.apply_palette(main_theme)
		var want := DANGER_ALT if mode else DANGER_BASE
		var seen: Array = []
		for style_name in UiTheme.STATE_STYLES:
			var box := main_theme.get_stylebox(String(style_name), UiTheme.DANGER_TYPE) \
				as StyleBoxTexture
			seen.append(String(box.texture.resource_path) if box != null and box.texture != null
				else "null")
		_ok("O9=%s — 위험 프레임 상태 3종 전부 %s" % [str(mode), want.get_file()],
			seen.count(want) == UiTheme.STATE_STYLES.size(), str(seen))
	# **옵션 창구를 거쳐도 따라오는가** — 화면이 `UiPalette.apply_options()` 만 부르므로
	# 그 경로가 테마를 끌고 오지 않으면 실기에서만 어긋난다.
	var session := _fresh_session(data)
	var store := session.options
	var o9_before := store.index_of("o9")
	store.set_index("o9", 1)
	UiPalette.apply_options(store)
	var via_options := main_theme.get_stylebox("normal", UiTheme.DANGER_TYPE) as StyleBoxTexture
	_ok("옵션 창구(apply_options)가 테마까지 끌고 온다",
		via_options != null and via_options.texture != null
			and String(via_options.texture.resource_path) == DANGER_ALT,
		String(via_options.texture.resource_path) if via_options != null
			and via_options.texture != null else "null")
	store.set_index("o9", o9_before)
	UiPalette.apply_options(store)
	UiPalette.colorblind = before
	UiTheme.apply_palette(main_theme)
	_ok("원복 (뒤 축 오염 방지)", UiPalette.colorblind == before)


# ── ㉝ 의미 프레임 소비처 (15차 ① — 정본이 이름 붙인 자리에만 건다) ──
#
# **`주 버튼` 은 정본 용어다** (D09 별첨A — RACE-03 `[다음으로]` · RUN-02 E05 · SET-01
# `[개러지로]` · `[다음 대회로]`). 그 넷에만 `PrimaryButton` 을 건다.
#
# **위험은 비가역 확인의 수락 하나뿐이다** [가안] — §A-23 이 비가역 항목에 경고행을 필수로
# 두었고 그 자리에 이미 위험색 문면이 서 있다. **가역 확인에는 붙이지 않는다**(대조군) —
# 붙이면 '위험'이 '확인'의 동의어가 된다.
const PRIMARY_SCREENS := [
	"res://ui/race/gp_result_screen.tscn",
	"res://ui/run/run_recap_screen.tscn",
	"res://ui/settle/season_result_screen.tscn",
	"res://ui/settle/tour_report_screen.tscn",
]


func _semantic_frame_consumers(data: GameData) -> void:
	# ⓐ 주 버튼 4종 — **렌더된 박스**를 본다. 씬 속성만 읽으면 타입 변형이 실제로
	# 해석됐는지는 모른다(선언은 결선의 증거가 아니다).
	var primary_seen := 0
	for path in PRIMARY_SCREENS:
		var session := _fresh_session(data)
		var screen := _mount(String(path), session)
		if screen == null:
			continue
		var button := screen.get_node_or_null("%NextButton") as Button
		_ok("전제: 주 버튼 실재 — %s" % String(path).get_file(), button != null)
		if button != null:
			var box := button.get_theme_stylebox("normal") as StyleBoxTexture
			var seen: String = String(box.texture.resource_path) if box != null \
				and box.texture != null else "null"
			var hit: bool = seen == FRAME_DIR + "button_primary_9p.png"
			if hit:
				primary_seen += 1
			_ok("주 버튼 = 강조 프레임 — %s" % String(path).get_file(), hit, seen)
		_unmount(screen)
	_ok("주 버튼 4종 전건 결선 (누락 0)", primary_seen == PRIMARY_SCREENS.size(),
		"%d / %d" % [primary_seen, PRIMARY_SCREENS.size()])
	# ⓑ **대조군** — 주 버튼이 아닌 버튼은 기본 프레임이다. 없으면 "전부 강조"도 통과한다.
	# 레이스 화면의 확정 버튼을 쓴다: **정본이 주 버튼이라 부르지 않은 자리**이면서
	# 그 화면에서 가장 중요한 버튼이라, 배정이 중요도가 아니라 정본 명명을 따랐음을 보인다.
	var s2 := _fresh_session(data)
	var probe := _mount(RACE_SCENE, s2)
	if probe != null:
		var box := probe._e08_confirm.get_theme_stylebox("normal") as StyleBoxTexture
		var plain: String = String(box.texture.resource_path) if box != null \
			and box.texture != null else "null"
		_ok("대조군: 레이스 확정 버튼 = 기본 프레임 (정본 명명 밖)",
			plain == FRAME_DIR + "button_default_9p.png", plain)
		_unmount(probe)
	# ⓒ 위험 = 비가역 수락 전속. 가역은 기본 프레임이다.
	var s3 := _fresh_session(data)
	var host := _mount(String(PRIMARY_SCREENS[0]), s3)
	if host != null:
		for entry in [["비가역", true, "button_danger_9p.png"], ["가역", false, "button_default_9p.png"]]:
			var dialog := ConfirmDialog.ask(host, data.strings, "x", "", bool(entry[1]), 9)
			var ok_button := dialog.get_node_or_null("Panel/VBoxContainer/HBoxContainer/OkButton") \
				as Button
			if ok_button == null:
				ok_button = dialog.find_child("OkButton", true, false) as Button
			_ok("전제: %s 확인의 수락 버튼 실재" % String(entry[0]), ok_button != null)
			if ok_button != null:
				var box := ok_button.get_theme_stylebox("normal") as StyleBoxTexture
				var seen: String = String(box.texture.resource_path) if box != null \
					and box.texture != null else "null"
				_ok("%s 확인 수락 = %s" % [String(entry[0]), String(entry[2])],
					seen == FRAME_DIR + String(entry[2]), seen)
			# 모달 패널도 함께 본다 — 오버라이드가 남으면 테마가 무엇을 등록하든 옛 박스다.
			var panel := dialog.find_child("Panel", true, false) as PanelContainer
			if panel != null and String(entry[0]) == "비가역":
				var pbox := panel.get_theme_stylebox("panel") as StyleBoxTexture
				_ok("모달 패널 = dialog_modal 프레임",
					pbox != null and pbox.texture != null
						and String(pbox.texture.resource_path) == FRAME_DIR + "dialog_modal_9p.png",
					String(pbox.texture.resource_path) if pbox != null and pbox.texture != null
						else "null")
			dialog.queue_free()
		_unmount(host)


# ── ㊹ 아카이브 재열람 문면 결선 · NAR-01 페이로드 발신처 전수 ──
#
# **문면 없는 회수는 같은 장면이 아니다.** 기록실이 `{vn_id, replay, next}` 만 쥐여 주던
# 동안 바탕·CG 는 떴고(그 둘은 `vn_id` 로도 조회된다) 문면만 골격 폴백 1줄로 떨어졌다.
# 화자를 잃은 라인은 기본값 베인으로 내려가 **파형까지 섰다** — 즉 화면은 죽지 않고
# *다른 장면*을 그렸다. 개막 경로가 정확히 같은 형태로 샜던 것(22차)의 **두 번째 경로**다.
#
# 그래서 축이 셋이다:
#   ⓐ **되찾기** — 아카이브에 실리는 id 계열 3종 전부에서 문면·화자·정조가 돌아오는가
#   ⓑ **구분력** — 옛 형태를 그대로 넣으면 축이 *실패해야* 한다(대조군이 없으면 ⓐ 는
#      "무엇을 넣어도 통과"와 구분되지 않는다)
#   ⓒ **전수** — 같은 결함의 세 번째 경로가 없는가. 화면이 NAR-01 페이로드를 **직접 조립하는
#      자리**가 어디에도 없어야 하고, 창구가 늘면 이 축이 먼저 붉어야 한다
const RUN_SESSION_SRC := "res://ui/flow/run_session.gd"
const NAR_DISPATCH := 'go("NAR-01",'
# 세션이 발행하는 NAR-01 페이로드 창구 — **못박아 둔다.** 새 창구가 생기면 이 축이 먼저
# 붉어지고, 그때 "이 창구도 전수 규칙을 지키는가"를 사람이 한 번 본다.
const PAYLOAD_MAKERS := [
	"take_brief_payload",
	"season_open_payload",
	"milestone_payload",
	"season_close_payload",
	"archive_replay_payload",
]


func _archive_replay_wiring(data: GameData) -> void:
	var session := _fresh_session(data)
	session.begin_career(1)
	# ⓐ 계열 3종 — 막 VN(접미 없음) · 비트 id 직행 · 시즌 경계 인스턴스(접미)
	var families := [
		["막 VN", "vn_act1", "vnslot_tour_brief", 12],
		["비트 직행", "vnbeat_crew_nadia", "vnslot_tour_milestone", 9],
		["시즌 개막 인스턴스", RunSession.season_vn_id(RunSession.SEASON_OPEN_VN_STEM, 1),
			"vnslot_season_open", 3],
		["시즌 엔딩 인스턴스", RunSession.season_vn_id(RunSession.SEASON_CLOSE_VN_STEM, 1),
			"vnslot_season_close", 3],
	]
	for entry in families:
		var label := String(entry[0])
		var vn_id := String(entry[1])
		var payload := session.archive_replay_payload(vn_id, "HUB-05")
		_ok("㊹ %s — 재열람 페이로드 발행" % label, not payload.is_empty())
		if payload.is_empty():
			continue
		_ok("㊹ %s — 재생 플래그" % label, bool(payload.get("replay", false)))
		_ok("㊹ %s — 인스턴스 id 유지" % label, String(payload.get("vn_id", "")) == vn_id,
			String(payload.get("vn_id", "")))
		_ok("㊹ %s — 슬롯 동반" % label, String(payload.get("slot_id", "")) == String(entry[2]),
			String(payload.get("slot_id", "")))
		var lines: Array = payload.get("line_keys", [])
		_ok("㊹ %s — 라인 %d (폴백 1줄이 아니다)" % [label, int(entry[3])],
			lines.size() == int(entry[3]), str(lines.size()))
		var with_speaker := 0
		for line in lines:
			if typeof(line) == TYPE_DICTIONARY and not String(Dictionary(line)
					.get("speaker_key", "")).is_empty():
				with_speaker += 1
		_ok("㊹ %s — 전 라인이 화자를 갖는다" % label, with_speaker == lines.size(),
			"%d/%d" % [with_speaker, lines.size()])
		_ok("㊹ %s — 정조 동반" % label, not String(payload.get("tone", "")).is_empty(),
			String(payload.get("tone", "")))
		# 캘린더는 **개막 진행의 장치**이지 장면의 문면이 아니다. 재열람은 상태를 바꾸지 않는다.
		_ok("㊹ %s — 캘린더 미동반" % label, not bool(payload.get("calendar", false)))
		# 표 실체 id — 바탕 조회의 정상 열쇠. 접미가 붙은 계열에서 이것이 없으면 접두 폴백에
		# 기대게 되고, 그 폴백은 표 행이 늘 때 조용히 어긋난다.
		_ok("㊹ %s — 표 실체 id 동반" % label,
			not String(payload.get("scene_id", "")).is_empty(),
			String(payload.get("scene_id", "")))
	# ⓑ 실화면 — 데이터 문면이 그려지는가. 그리고 **옛 형태는 폴백으로 떨어지는가**.
	var fixed := session.archive_replay_payload(
		RunSession.season_vn_id(RunSession.SEASON_OPEN_VN_STEM, 1), "HUB-05")
	var placeholder := data.strings.text("ui.vn." + "placeholderLine01")
	var vane := data.strings.text("ui.vn." + "speakerVane")
	var screen := _mount_payload(data, session, fixed)
	var body := (screen.get_node("%BodyLabel") as Label).text
	var speaker := (screen.get_node("%SpeakerLabel") as Label).text
	_ok("㊹ 실화면 1라인 = 데이터 문면",
		body == data.strings.text("vn.seasonOpen." + "beat01"), body)
	_ok("㊹ 실화면 폴백 문면 미노출", body != placeholder)
	_ok("㊹ 실화면 화자 = 라인 선언 화자 (기본값 베인이 아니다)",
		speaker == data.strings.text("ui.vn." + "speakerNarration") and speaker != vane, speaker)
	_unmount(screen)
	# **대조군 — 결함 형태를 그대로 재현한다.** 이것이 폴백을 내지 않으면 위 축은 무엇을
	# 넣어도 통과하는 검사다(자기 충족 단언 방지).
	var legacy := _mount_payload(data, session, {
		"vn_id": RunSession.season_vn_id(RunSession.SEASON_OPEN_VN_STEM, 1),
		"replay": true, "next": "HUB-05",
	})
	_ok("㊹ 대조군: 옛 형태는 폴백 1줄",
		(legacy.get_node("%BodyLabel") as Label).text == placeholder,
		(legacy.get_node("%BodyLabel") as Label).text)
	_ok("㊹ 대조군: 옛 형태는 화자를 잃는다 (기본값 베인)",
		(legacy.get_node("%SpeakerLabel") as Label).text == vane)
	_unmount(legacy)
	# ⓒ-1 역방향 규칙 — **되짚기로 판정한다.** `_s` 를 찾아 자르기만 하면 이름 안에 `_s` 를
	# 품은 비트 id 가 걸린다(`vnbeat_clue_silence` 가 그 실물).
	for season_no in [1, 2, 9, 12]:
		var built := RunSession.season_vn_id(RunSession.SEASON_OPEN_VN_STEM, int(season_no))
		var split := RunSession.split_season_vn_id(built)
		_ok("㊹ 왕복 s%d" % int(season_no),
			String(split.get("stem", "")) == RunSession.SEASON_OPEN_VN_STEM
				and int(split.get("season", -1)) == int(season_no), str(split))
	# `vn_season_open_s01` 은 **되짚기만이 잡는다** — 잘라 보면 `_s` 뒤가 정수로 읽히므로
	# 자르기 판정에는 걸리지 않고, 앞면 포맷으로 다시 조립해야 원본과 다름이 드러난다.
	for stray in ["vnbeat_clue_silence", "vn_act1", "vnbeat_season_open", "vn_season_open_sx",
			"vn_season_open_s01"]:
		_ok("㊹ 접미 아님 — %s" % String(stray),
			RunSession.split_season_vn_id(String(stray)).is_empty(),
			str(RunSession.split_season_vn_id(String(stray))))
	# ⓒ-2 기록실 관측 지점 — 아카이브에 실린 것은 전부 되찾을 수 있어야 한다.
	var shelf := _fresh_session(data)
	shelf.begin_career(1)
	for seen in ["vn_act1", "vnbeat_crew_nadia",
			RunSession.season_vn_id(RunSession.SEASON_CLOSE_VN_STEM, 1)]:
		shelf.narrative.vn_seen[String(seen)] = true
	var records := _mount(RECORDS_SCENE, shelf)
	if records != null:
		_ok("㊹ 재열람 누락 관측 0 (실린 것은 전부 되찾는다)",
			records.replay_omissions.is_empty(), str(records.replay_omissions))
		_unmount(records)
	# **대조군 — 관측 지점이 살아 있는가.** 되찾을 수 없는 id 를 하나 심는다. 이것이 안 잡히면
	# 위의 "누락 0"은 가드가 죽어도 같은 값을 낸다.
	var broken := _fresh_session(data)
	broken.begin_career(1)
	broken.narrative.vn_seen["vn_bogus_s9"] = true
	var broken_records := _mount(RECORDS_SCENE, broken)
	if broken_records != null:
		_ok("㊹ 대조군: 되찾지 못한 id 가 관측에 남는다",
			broken_records.replay_omissions.has("vn_bogus_s9"),
			str(broken_records.replay_omissions))
		_unmount(broken_records)
	# ⓒ-3 발신처 전수 — **세 번째 경로가 없는가.**
	var sources := _ui_gd_sources()
	_ok("㊹ 전제: 화면 원본 적재", sources.size() >= 20, str(sources.size()))
	var dispatch_files: Array = []
	var inline_assembly: Array = []
	var dispatches := 0
	for path in sources:
		var text := String(sources[path])
		var at := text.find(NAR_DISPATCH)
		if at < 0:
			continue
		dispatch_files.append(String(path))
		while at >= 0:
			dispatches += 1
			# 인자는 **사전 리터럴이면 안 된다** — 그것이 화면이 직접 조립하는 형태다.
			var arg := text.substr(at + NAR_DISPATCH.length()).strip_edges()
			if arg.begins_with("{"):
				inline_assembly.append("%s: %s" % [String(path).get_file(), arg.substr(0, 40)])
			at = text.find(NAR_DISPATCH, at + 1)
	# 축이 스스로 비면 실패해야 한다 — 발신처를 하나도 못 찾은 상태에서 "위반 0"은 무의미하다.
	_ok("㊹ 발신처 실재 (축의 대상이 있다)", dispatches >= 5, str(dispatches))
	_ok("㊹ 인라인 사전 조립 0", inline_assembly.is_empty(), "; ".join(inline_assembly))
	var without_maker: Array = []
	for path in dispatch_files:
		var text := String(sources[path])
		var uses_maker := false
		for maker in PAYLOAD_MAKERS:
			if text.contains("session." + String(maker) + "("):
				uses_maker = true
				break
		if not uses_maker:
			without_maker.append(String(path).get_file())
	_ok("㊹ 전 발신처가 세션 창구를 경유", without_maker.is_empty(), "; ".join(without_maker))
	# 창구 대장이 낡지 않게 — 원본의 공개 `*_payload` 집합과 못박은 목록을 대조한다.
	var declared: Array = []
	for raw_line in FileAccess.get_file_as_string(RUN_SESSION_SRC).split("\n"):
		var line := String(raw_line)
		if not line.begins_with("func "):
			continue
		var paren := line.find("(")
		if paren < 0:
			continue
		var fn := line.substr(5, paren - 5)
		if not fn.begins_with("_") and fn.ends_with("_payload"):
			declared.append(fn)
	declared.sort()
	var pinned: Array = PAYLOAD_MAKERS.duplicate()
	pinned.sort()
	_ok("㊹ 창구 대장 = 원본 실제 (새 창구가 생기면 축이 먼저 붉는다)",
		declared == pinned, "%s vs %s" % [str(declared), str(pinned)])


# `res://ui` 아래 전 `.gd` 원본 — 경로 → 본문. 마운트한 화면만 보면 안 세운 화면이
# 부재로 오독되므로(`_scene_sources_contain` 과 같은 사유) 원본을 직접 훑는다.
func _ui_gd_sources() -> Dictionary:
	var found: Dictionary = {}
	var pending: Array = SCENE_ROOTS.duplicate()
	while not pending.is_empty():
		var dir_path := String(pending.pop_back())
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := dir_path + "/" + entry
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(full)
			elif entry.ends_with(".gd"):
				found[full] = FileAccess.get_file_as_string(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found
