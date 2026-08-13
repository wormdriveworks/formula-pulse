# 화면 베이스 — D09 §8.1 대장의 각 화면이 공유하는 계약.
#
# 화면은 **전이를 스스로 수행하지 않고 요청만 한다**(`navigate`). 실제 교체는 라우터가 하며,
# 그래야 D09 §2.3 플로우맵에 없는 전이가 화면 안에서 몰래 생기지 않는다
# ("상태 머신에 없는 화면 전이를 추가하지 않는다" — D09 §2.3 전이 폐쇄성).
class_name FlowScreen
extends Control

signal navigate(target: String, payload: Dictionary)

var session: RunSession


func bind(run_session: RunSession, payload: Dictionary) -> void:
	session = run_session
	_on_bound(payload)


# 화면별 초기화 지점 — 라우터가 세션을 넣어 준 뒤 불린다.
func _on_bound(_payload: Dictionary) -> void:
	pass


func go(target: String, payload: Dictionary = {}) -> void:
	navigate.emit(target, payload)
