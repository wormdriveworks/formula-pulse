# D12 §2.2 / §2.4 — ILifecycle: 백그라운드/복귀 훅 계약.
# 백그라운드 진입 = 일시정지 + 서스펜드 스냅샷(D12 §7.2) + 오디오 뮤트.
# 복귀 시 개입 창 타이머 처리(모바일 = 전량 리셋 / 데스크탑 = 카운트인)는 상위 층 소관.
class_name ILifecycle
extends RefCounted

signal background_entered
signal foreground_resumed


func notify_background() -> void:
	push_error("ILifecycle.notify_background is abstract")


func notify_foreground() -> void:
	push_error("ILifecycle.notify_foreground is abstract")
