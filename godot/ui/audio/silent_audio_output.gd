# 무음 재생기 — `AudioOutput` 계약의 표현 층 구현 (사운드 실물 미유입 단계).
#
# **왜 코어가 아니라 화면 층인가.** `core/audio/audio_output.gd` 는 계약이고, 실제 재생은
# `AudioStreamPlayer` 풀·버스 조작이라 SceneTree 를 타는 표현 층 소관이다. 실물이 유입되면
# 이 자리를 같은 계약의 재생기가 대신하고 디스패처·호출부는 손대지 않는다(D12 §10 경계).
#
# **이 클래스가 하는 유일한 일 = 스트림 종료 통지다.** 디스패처의 보이스 점유(`_voices`)는
# 표현 층이 `release_voice()` 로 비우는 구조인데, 계약 기본 구현은 전 메서드가 no-op 이라
# 그 통지 주체가 없다. 결과는 **점유가 영구 누적**된다 — 실측(IMPL-149 프로브):
#   · P1 정보음 1발 → 이후 P3 장식음 전량 영구 억제 (P1 보호가 풀리지 않는다)
#   · P2 12발 → 가상 채널 상한 포화 · 걷어낼 P3 가 없어 **섀시 경고(P1)까지 거부**
# 무음 스트림의 길이는 0 이므로 **즉시 종료를 알리는 것이 정확한 거동**이다. 코드가 SFX
# 길이를 추정하지 않는다는 디스패처 규약(지속 시간 = 에셋의 성질)도 그대로 지켜진다.
#
# 순환 참조 회피 — 디스패처가 output 을 쥐므로 역참조는 약참조로 둔다(양쪽 RefCounted).
class_name SilentAudioOutput
extends AudioOutput

var _dispatcher_ref: WeakRef


func bind_dispatcher(target: AudioDispatcher) -> void:
	_dispatcher_ref = weakref(target)


func play_sfx(sfx_id: String, _priority: String) -> void:
	_report_finished(sfx_id)


func play_jingle(jingle_id: String) -> void:
	_report_finished(jingle_id)


# BGM·덕킹·긴장 레이어는 보이스 점유 대상이 아니다(디스패처가 `_voices` 에 넣지 않는다) —
# 무음 단계에서 통지할 것이 없으므로 계약 기본 no-op 을 그대로 쓴다.
func _report_finished(sfx_id: String) -> void:
	if _dispatcher_ref == null:
		return
	var dispatcher := _dispatcher_ref.get_ref() as AudioDispatcher
	if dispatcher != null:
		dispatcher.release_voice(sfx_id)
