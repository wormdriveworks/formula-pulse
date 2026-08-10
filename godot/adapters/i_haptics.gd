# D12 §2.2 / §10.4 — IHaptics: 진동 이벤트 단일 규격 계약.
# 진동 이벤트 정의 1원(강도·길이 — 값 D13) → 어댑터 2구현(패드 진동 / 기기 진동).
# 최종 강도 = 이벤트 강도 × 옵션 감쇠 배율 (곱 순서 확정 — D12 §10.4).
class_name IHaptics
extends RefCounted


func vibrate(_strength: float, _duration_sec: float) -> void:
	push_error("IHaptics.vibrate is abstract")
