# D12 §2.2 / §7.5 — IPresence: Rich Presence 키 계약.
# 상태 갱신 지점 = 상위 상태 전이 3상태(HUB/레이스 중/결산 — D12 §7.5).
# 키는 §8.1 체계의 presence 도메인.
class_name IPresence
extends RefCounted


func set_presence(_presence_key: String) -> void:
	push_error("IPresence.set_presence is abstract")


func clear_presence() -> void:
	push_error("IPresence.clear_presence is abstract")
