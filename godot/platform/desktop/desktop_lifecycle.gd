# ILifecycle 데스크탑 최소 구현 — 포커스 상실 = 일시정지 옵션 연동 (D12 §2.2, D09 §3.7 승계).
# 옵션 연동 실배치는 옵션 화면 구현 시(범위 외) — MS-1은 신호 중계만.
class_name DesktopLifecycle
extends ILifecycle


func notify_background() -> void:
	background_entered.emit()


func notify_foreground() -> void:
	foreground_resumed.emit()
