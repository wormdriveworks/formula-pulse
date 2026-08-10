# IPresence 데스크탑 최소 구현 — MS-1은 무동작 스텁 (Steamworks 연동은 후속 마일스톤).
class_name DesktopPresence
extends IPresence

var _current_key: String = ""


func set_presence(presence_key: String) -> void:
	_current_key = presence_key


func clear_presence() -> void:
	_current_key = ""
