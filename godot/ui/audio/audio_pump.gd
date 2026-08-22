# 오디오 페이드 펌프 — 재생기에 프레임을 먹이는 유일한 목적의 노드.
#
# **왜 갈랐는가.** 크로스페이드·덕킹 복귀는 시간 축이라 누군가 델타를 줘야 하는데,
# `AudioOutput` 은 계약상 `RefCounted` 다(코어 층 — SceneTree 를 모른다). 그렇다고 엔진 `Tween`
# 에 맡기면 **검사가 벽시계에 묶인다** — 0.8초 크로스페이드를 확인하려고 48프레임을 기다리는
# 검사는 느리고, 중간 상태를 정확히 집을 수도 없다.
#
# 펌프를 갈라 두면 production 은 엔진이 돌리고 **검사는 `advance_fades()` 에 델타를 손으로
# 준다** — 디스패처의 `clock_override_msec` 와 같은 성격의 이음매다(시간 축 정책은 주입 없이
# 결정적으로 검사할 수 없다).
extends Node

var output: AudioOutput


func _process(delta: float) -> void:
	if output != null:
		output.advance_fades(delta)
