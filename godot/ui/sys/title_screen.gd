# SYS-01 타이틀 화면 (D09 별첨A §A-1).
#
# 메뉴 열: 계속하기 / 새 커리어 / 기록실 / 옵션 / 종료.
# **세이브 부재 시 '계속하기' 비표출 · '새 커리어' 승격** (§A-1 E01).
#
# 업적(SYS-04)은 MS-2 범위 밖이라 항목 자체를 두지 않는다 (사용자 확정 23종 — IMPL-077).
# 기록실(HUB-05)·옵션(SYS-03)은 범위 안이지만 아직 서지 않아 잠금 표기로 자리만 잡는다 —
# 도달 불가 요소를 남기면 패드 순회 폐쇄 루프(D09 §1.3)가 깨지므로 비활성으로 순회에서 뺀다.
extends FlowScreen

@onready var _title: Label = %TitleLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _new_button: Button = %NewCareerButton
@onready var _archive_button: Button = %ArchiveButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _version: Label = %VersionLabel


func _on_bound(_payload: Dictionary) -> void:
	var s := session.data.strings
	_title.text = s.text("ui.title.gameTitle")
	(%SubtitleLabel as Label).text = s.text("ui.title.subtitle")
	_continue_button.text = s.text("ui.title.continueRun")
	_new_button.text = s.text("ui.title.newCareer")
	_archive_button.text = s.text("ui.title.archive")
	_options_button.text = s.text("ui.title.options")
	_quit_button.text = s.text("ui.title.quit")
	var version_text := s.text("ui.title.versionFormat", {
		"version": String(ProjectSettings.get_setting("application/config/version", "")),
	})
	_version.text = version_text

	_continue_button.pressed.connect(_on_continue)
	_new_button.pressed.connect(_on_new_career)
	_quit_button.pressed.connect(_on_quit)
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
