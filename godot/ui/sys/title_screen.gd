# SYS-01 타이틀 화면 (D09 별첨A §A-1).
#
# 메뉴 열: 계속하기 / 새 커리어 / 기록실 / 옵션 / 종료.
# **세이브 부재 시 '계속하기' 비표출 · '새 커리어' 승격** (§A-1 E01).
#
# 업적(SYS-04)은 MS-3 에서 서면서 항목이 들어왔다 (§A-1 이탈 대상 = SYS-02·SYS-03·SYS-04).
# 기록실(HUB-05)은 커리어 세이브 문맥이 필요해 아직 잠금 표기로 자리만 잡는다 —
# 도달 불가 요소를 남기면 패드 순회 폐쇄 루프(D09 §1.3)가 깨지므로 비활성으로 순회에서 뺀다.
extends FlowScreen

# ── 타이틀 키 비주얼 (개선 2026-09-01) ──
#
# 타이틀이 검정 바탕 + 문면뿐이라 화면 우측 2/3 가 비어 있었다. 실물은 부트 스플래시와
# 같은 키 비주얼 리프레임(640×360 — 캔버스 동치·정수 배율 유지)을 재사용한다: 새 에셋 0.
# 스크림은 좌→우 감쇠 그라디언트 — 메뉴·표제가 서는 좌측 대역의 판독 대비를 지키고
# 우측은 원화가 드러난다. 색은 기확정 바탕색(BG_DEEP 슬롯)에서 알파만 움직인다: 신규 색 0.
# 상표 규율(주표장 우위 조판)과도 정합 — 로고 문면이 원화 위 최상층에 그대로 선다.
const KEY_ART_PATH := "res://assets/platform/boot_splash.png"
const KEY_ART_NAME := "KeyArt"
const KEY_ART_SCRIM_NAME := "KeyArtScrim"

@onready var _title: Label = %TitleLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _new_button: Button = %NewCareerButton
@onready var _archive_button: Button = %ArchiveButton
@onready var _achievements_button: Button = %AchievementsButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _version: Label = %VersionLabel


# 타이틀 BGM (BGM-01) — 앱 진입 최초의 사운드다.
func _audio_enter_events() -> Array:
	return ["title_enter"]


func _on_bound(_payload: Dictionary) -> void:
	_mount_key_art()
	var s := session.data.strings
	_title.text = s.text("ui.title.gameTitle")
	(%SubtitleLabel as Label).text = s.text("ui.title.subtitle")
	_continue_button.text = s.text("ui.title.continueRun")
	_new_button.text = s.text("ui.title.newCareer")
	_archive_button.text = s.text("ui.title.archive")
	_achievements_button.text = s.text("ui.title.achievements")
	_options_button.text = s.text("ui.title.options")
	_quit_button.text = s.text("ui.title.quit")
	var version_text := s.text("ui.title.versionFormat", {
		"version": String(ProjectSettings.get_setting("application/config/version", "")),
	})
	_version.text = version_text

	_continue_button.pressed.connect(_on_continue)
	_new_button.pressed.connect(_on_new_career)
	_quit_button.pressed.connect(_on_quit)
	_achievements_button.pressed.connect(func(): go("SYS-04", {"return": "SYS-01"}))
	_options_button.pressed.connect(func(): go("SYS-03", {"return": "SYS-01"}))
	# 기록실 열람 모드(커리어 세이브 문맥)는 세이브 선택 경유가 규격(§A-1 E02) — 미결선 잠금
	_archive_button.disabled = true
	_archive_button.focus_mode = Control.FOCUS_NONE

	var has_save := _any_profile_has_save()
	_continue_button.visible = has_save
	# 초기 포커스: 계속하기 (부재 시 새 커리어) — §A-1
	if has_save:
		_continue_button.grab_focus()
	else:
		_new_button.grab_focus()


# 바탕(1) → 원화(2) → 스크림(3) → 메뉴 열(Pad) — 층 순서가 판독 대비의 계약이다.
# VN 바탕 마운트(`vn_screen._mount_backdrop`)와 같은 규약: 씬 무접촉·부재 시 보고 후 생략.
func _mount_key_art() -> void:
	if get_node_or_null(KEY_ART_NAME) != null:
		return
	var texture := load(KEY_ART_PATH) as Texture2D
	if texture == null:
		push_error("TitleScreen: key art '%s' not found" % KEY_ART_PATH)
		return
	var art := TextureRect.new()
	art.name = KEY_ART_NAME
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 원도 640×360 = 캔버스 동치 — 무배율 배치 (KEEP: 비정수 확대·믹셀 원천 차단)
	art.stretch_mode = TextureRect.STRETCH_KEEP
	art.texture = texture
	add_child(art)
	move_child(art, 1)
	var scrim := TextureRect.new()
	scrim.name = KEY_ART_SCRIM_NAME
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gradient := Gradient.new()
	var base: Color = UiPalette.BG_DEEP
	gradient.set_color(0, Color(base.r, base.g, base.b, 0.96))
	gradient.set_color(1, Color(base.r, base.g, base.b, 0.08))
	gradient.add_point(0.42, Color(base.r, base.g, base.b, 0.82))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.0, 0.0)
	gradient_texture.fill_to = Vector2(1.0, 0.0)
	scrim.texture = gradient_texture
	add_child(scrim)
	move_child(scrim, 2)


func _any_profile_has_save() -> bool:
	var count := int(session.data.param("param_save_profile_count"))
	for profile in range(1, count + 1):
		if FileAccess.file_exists(SaveManager.progress_path(profile)):
			return true
	return false


func _on_continue() -> void:
	go("SYS-02", {"mode": "continue"})


func _on_new_career() -> void:
	go("SYS-02", {"mode": "new"})


func _on_quit() -> void:
	get_tree().quit()
