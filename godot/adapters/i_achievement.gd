# D12 §2.2 / §7.4 — IAchievement: 업적·히든 플래그 계약.
# 매핑 테이블(업적 id → 플랫폼 id)은 데이터 층 — 본 계약은 발행 API만 규정.
class_name IAchievement
extends RefCounted


func unlock(_achievement_id: String) -> void:
	push_error("IAchievement.unlock is abstract")


func is_unlocked(_achievement_id: String) -> bool:
	push_error("IAchievement.is_unlocked is abstract")
	return false


# 플랫폼 업적 서비스와 실제로 연결돼 있는가 — SYS-04 '미연동' 표기의 유일 판정 창구.
# **추상이 아니라 기본값 false 다.** 널 구현이 곧 현 단계의 정상 상태이고(실 SDK 연동은
# MS-3 스토어 준비물·G-7 트랙), 화면은 이 값만 보면 되므로 플랫폼을 알 필요가 없다
# (혼입 0 — 화면이 어댑터 구현체나 플랫폼 조건을 직접 묻는 경로를 두지 않는다).
func is_linked() -> bool:
	return false
