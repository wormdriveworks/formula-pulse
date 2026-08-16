# 오디오 출력 싱크 — 디스패처(정책 층)와 실제 재생(표현 층)의 경계.
#
# **기본 구현이 곧 무음 폴백이다.** 전 메서드가 no-op이므로, 사운드 실물이 하나도 없는
# 현 단계에서도 디스패처·호출부·검사가 전부 성립한다(D12 §10 플레이스홀더 경로 요구).
# 실물이 유입되면 이 계약을 구현한 재생기(AudioStreamPlayer 풀·버스 조작)를 주입하면 되고,
# **디스패처와 호출부는 손대지 않는다** — 그 무접촉이 이 경계를 두는 이유다.
#
# 버스 3계 = Master / BGM / SFX (D12 §10.1 · D11 §2.1 — 앰비언스는 SFX 버스 귀속).
# 플랫폼 분기는 여기에 들어오지 않는다(불변규칙 1) — 백그라운드·광고 뮤트는 모바일 레이어가
# 이 계약의 구현체를 통해 버스를 조작한다.
class_name AudioOutput
extends RefCounted


# 단발 SFX 발화. priority 는 표현 층의 보이스 관리용 힌트이며 컬링 판정 자체는 디스패처가 한다.
func play_sfx(_sfx_id: String, _priority: String) -> void:
	pass


# 보이스 컬링 통지 — 채널 상한 초과로 디스패처가 걷어낸 발음.
func cull_sfx(_sfx_id: String) -> void:
	pass


# BGM 트랙 교체. crossfade_sec = D13 별첨A §8.3 크로스페이드.
func play_bgm(_track_id: String, _crossfade_sec: float) -> void:
	pass


func stop_bgm() -> void:
	pass


# 긴장 레이어 온/오프 (D11 §4.3 K2-B — 2레이어 봉인. 트랙 교체가 아니라 레이어 볼륨이다).
func set_bgm_tension(_on: bool) -> void:
	pass


func play_jingle(_jingle_id: String) -> void:
	pass


# 덕킹 (D11 §6.3 — L2·L3 스팅·징글 재생 중 BGM 감쇠, 값 D13 별첨A §8.3).
func duck_bgm(_db: float, _return_sec: float) -> void:
	pass
