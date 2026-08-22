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


# 일시정지 — **BGM 유지 · SFX 뮤트** (D11 §4.3 확정 · 레트로 관례).
# 정책이 아니라 버스 조작이므로 표현 층 소관이다: 발화 자체를 막는 것이 아니라 들리지 않게 한다.
func set_paused(_on: bool) -> void:
	pass


# 볼륨 옵션 O13~O15 → 버스 감쇠 (D12 §10.1 — 0 = 뮤트 · 100 = 0dB · 지각 선형 로그 커브).
# 값은 0~100 정수(`options_store` 저장 형식) 그대로 받는다 — 변환은 표현 층 소관이다.
func apply_volumes(_master: int, _bgm: int, _sfx: int) -> void:
	pass


# 페이드 진행 — 시간 축을 가진 것(트랙 크로스페이드·레이어 전환·덕킹 복귀)의 유일한 진행 지점.
# 계약에 두는 이유: 이것을 두지 않으면 구현이 엔진 `Tween` 에 숨고 검사가 벽시계에 묶인다.
func advance_fades(_delta: float) -> void:
	pass
