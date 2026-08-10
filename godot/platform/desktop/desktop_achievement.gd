# IAchievement 데스크탑 최소 구현 — MS-1은 로컬 기록 스텁 (Steamworks 연동은 후속 마일스톤).
class_name DesktopAchievement
extends IAchievement

var _unlocked: Dictionary = {}


func unlock(achievement_id: String) -> void:
	_unlocked[achievement_id] = true


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.get(achievement_id, false)
