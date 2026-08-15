# 공용 고스트 게이지 — 현재 채움 + 실행 시 도달값(고스트 채움) 병기.
# 소비처: RUN-01 필드 정비 카드(§A-9 E02) · HUB-02 전면 정비 카드(§A-12).
#
# 봉인 잎 노드: 데이터 층 접근 없음 — 값은 화면이 코어 조회로 받아 주입한다
# (IMPL-093 구조 판단 승계 — 위젯에 주입 배관을 두지 않는다).
# 무상 복원선 눈금은 그리지 않는다 — §A-12 확정 "적용 시점 표기는 자동 처리 고지행으로만".
class_name GhostGauge
extends Control

var _current_ratio := 0.0
var _ghost_ratio := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# 값 주입 — current 이상 ghost 이하 구간이 고스트(반투명)로 채워진다.
func set_values(current: float, ghost: float, maximum: float) -> void:
	var span := maxf(maximum, 0.001)
	_current_ratio = clampf(current / span, 0.0, 1.0)
	_ghost_ratio = clampf(ghost / span, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, UiPalette.GAUGE_TRACK)
	if _ghost_ratio > _current_ratio:
		var ghost_color := UiPalette.CHASSIS_OK
		ghost_color.a = 0.35
		draw_rect(Rect2(0.0, 0.0, size.x * _ghost_ratio, size.y), ghost_color)
	if _current_ratio > 0.0:
		draw_rect(Rect2(0.0, 0.0, size.x * _current_ratio, size.y), UiPalette.CHASSIS_OK)
	draw_rect(rect, UiPalette.FRAME_LINE, false, 1.0)
