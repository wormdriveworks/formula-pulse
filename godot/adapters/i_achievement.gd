# D12 §2.2 / §7.4 — IAchievement: 업적·히든 플래그 계약.
# 매핑 테이블(업적 id → 플랫폼 id)은 데이터 층 — 본 계약은 발행 API만 규정.
class_name IAchievement
extends RefCounted


func unlock(_achievement_id: String) -> void:
	push_error("IAchievement.unlock is abstract")


func is_unlocked(_achievement_id: String) -> bool:
	push_error("IAchievement.is_unlocked is abstract")
	return false
