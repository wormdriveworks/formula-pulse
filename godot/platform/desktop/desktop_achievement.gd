# IAchievement 데스크탑 구현 — **Steam 널 배선** (D12 §2.2 · 총괄 판정 IMPL-128 ③).
#
# 현 단계는 로컬 기록 스텁이다. Steamworks 실 연동은 MS-3 스토어 준비물·G-7 트랙 소관이며,
# 그때 이 클래스의 내부만 바뀌고 **코어·화면은 무접촉**이다 — 어댑터를 두는 이유가 그것이다.
#
# `is_linked()` 가 false 인 동안 SYS-04 는 '미연동'으로 표기한다. 스텁이 true 를 반환하면
# 연동되지 않은 상태를 연동됐다고 표기하게 되므로, 실 SDK 결선 전까지 false 는 구속이다.
class_name DesktopAchievement
extends IAchievement

var _unlocked: Dictionary = {}
# 발행 이력 — 실 SDK 결선 시 재발행 대상 판별용(연동 이전 달성분의 소급 발행).
var published: Array = []


func unlock(achievement_id: String) -> void:
	if _unlocked.has(achievement_id):
		return
	_unlocked[achievement_id] = true
	published.append(achievement_id)


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.get(achievement_id, false)
