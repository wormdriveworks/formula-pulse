# 화면 베이스 — D09 §8.1 대장의 각 화면이 공유하는 계약.
#
# 화면은 **전이를 스스로 수행하지 않고 요청만 한다**(`navigate`). 실제 교체는 라우터가 하며,
# 그래야 D09 §2.3 플로우맵에 없는 전이가 화면 안에서 몰래 생기지 않는다
# ("상태 머신에 없는 화면 전이를 추가하지 않는다" — D09 §2.3 전이 폐쇄성).
class_name FlowScreen
extends Control

signal navigate(target: String, payload: Dictionary)

var session: RunSession

# 폰트 계열 (D10 §5.7 확정단 — 값 창구 D13 `param_font_size_body`·`param_font_size_head`).
#
# **코드로 만든 Control 은 프로젝트 기본 폰트 크기를 상속하지 않는다** — 엔진 기본 테마의 16 으로
# 해석된다(실측). 640×360 캔버스에서 16 은 레이아웃을 깨뜨리는데, `.tscn` 노드는 멀쩡하고
# 코드 생성분만 새기 때문에 화면을 눈으로 훑어서는 잡히지 않는다(12화면 34지점 실측 — IMPL-147).
# 그래서 ①값을 베이스가 한 번만 조달하고 ②FONT 정적 검사가 누락을 기계로 잡는다.
var _body_font_size := 9
var _head_font_size := 14


func bind(run_session: RunSession, payload: Dictionary) -> void:
	session = run_session
	# **`_on_bound()` 보다 먼저 채운다** — 화면 초기화가 이 값으로 Control 을 만든다.
	if session != null and session.data != null:
		_body_font_size = session.data.param_int("param_font_size_body")
		_head_font_size = session.data.param_int("param_font_size_head")
	_on_bound(payload)


# 화면별 초기화 지점 — 라우터가 세션을 넣어 준 뒤 불린다.
func _on_bound(_payload: Dictionary) -> void:
	pass


func go(target: String, payload: Dictionary = {}) -> void:
	navigate.emit(target, payload)
