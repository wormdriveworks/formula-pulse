# RACE-01 레이스 화면 — D09 §3 / 별첨A §A-6의 실화면.
#
# 4존 골격(D09 §3.1): A 레이스 스트립 / B0 레이스 씬 패널 / B 릴·개입 존 / C 로그 피드 / D 자원 바.
# 좌 = 조작·베인(릴 국면) · 우 = 서사·중계(전개 국면) — D04 §8.1 국면 분리의 화면 번역이다.
#
# **국면 분리 이행 (D09 §3.1 — MS-1 디버그 UI가 어긴 지점):** 베인 발화(`vane.*`)는 릴 존
# 콜아웃 전속이며 로그 피드에 흐르지 않는다. 중계(`raceLog.*`)만 C존으로 간다.
# 개입 창 중 시선이 릴 존을 떠나지 않게 하는 10초 성립 원칙(D09 §1.4)의 장치다.
#
# **봉인 (불변규칙 5 · D12 §6.3):** 스핀 결과는 릴 정지 연출이 끝나기 전 어떤 표시 경로에도
# 나오지 않는다. 리스핀도 같다 — 재정지분은 순차 정지를 다시 재생한다(IMPL-019 이월분 해소).
#
# **세이브는 SaveManager 경유** (IMPL-037 · ARCH 정적 규칙). SaveService 직접 호출은 빌드가 막는다.
# **표시 문자열은 전량 스트링 키** (V4 — 서식 문자열 포함).
extends FlowScreen

const REEL_COUNT := 3
# 라이벌 id — 데이터 행 키 참조이며 표시 문자열이 아니다(불변규칙 6의 테이블 ID 체계).
# CG-02 판정 상수 — '대면' = 관계 단계 1 (총괄 판정 IMPL-249 Q1 확정)
const KAI_ID := "ai_sherwood"
const REUNION_MEETING_STAGE := 1
const JUDE_ID := "ai_jude"
# TUT-01 이 기다릴 수 있는 행동 전량 — **이 화면이 실제로 발화하는 것만** 여기 든다.
# 단계 표(`tutorial_steps.csv`)가 이 집합 밖의 행동을 지목하면 그 단계는 영원히 넘어가지 않고
# 튜토리얼이 잠긴다. 검사가 두 쪽을 대조하므로 한쪽만 고치면 통과하지 못한다.
const TUTORIAL_ACTIONS := ["spin", "hold", "respin", "charge", "confirm"]
const HOLD_KEYS := [KEY_1, KEY_2, KEY_3]
# 스킬 슬롯 1~5 = F1~F5 (D09 §1.3 확정 기준값)
const SKILL_KEYS := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5]
# E13 소모품 슬롯 1~2 = 4·5 (개선 2026-09-02 — 종전 마우스·포커스 전용이던 슬롯의 키 결선.
# 홀드 1~3 의 숫자열 연장이라 배우기 비용이 낮다. 패드 열은 조합 공간이 소진돼 이번 결선 밖 —
# 패드는 종전대로 포커스 경유. D09 §1.3 두 번째 표의 개정 사안으로 기록).
const CONSUMABLE_KEYS := [KEY_4, KEY_5]

# ── 레이스 컨텍스트 층 패드 (D09 v1.3 §1.3 두 번째 표 · 총괄 판정 IMPL-200 ③) ──
# 버튼 인덱스는 엔진 실측 확정(IMPL-186): A=0 · X=2 · Y=3 · LB=9 · RB=10 · D패드 좌13/우14.
const PAD_A := 0
const PAD_X := 2
const PAD_Y := 3
const PAD_LB := 9
const PAD_RB := 10
const PAD_DPAD_LEFT := 13
const PAD_DPAD_RIGHT := 14
const ICON_DIR := "res://assets/ui/icons/"
# 컷인 노드 이름 — 검사가 실물을 찾는 지점이다(존재를 이름으로 세지 않으면 거동을 못 잰다).
const CG_CUTIN_NAME := "CgCutIn"
# E15 씬 패널 — 컷 합성 노드 이름 (검사가 실물을 찾는 지점)
const SCENE_PANEL_NAME := "ScenePanel"

# 엔진 로그 키 → 사운드 이벤트 id (D11 §1.4 이벤트 결속 · §2.4 SE-E 계열 정의).
# **화면은 SFX id 를 들지 않는다** — 무엇이 울릴지는 `sound_map` 이 정한다. 여기 있는 것은
# "엔진이 무슨 일이 일어났다고 말했는가"와 "그것이 D11 의 어느 결과 범주인가"의 대조뿐이다.
# 결과 6종은 전부 `seal_gated` 라 릴 정지 연출 전에는 디스패처가 막는다(호출 순서 무관).
#
# `defendFail01` 은 `duelLoseDefense01` 과 같은 턴에 함께 발행되므로 등재하지 않는다 —
# 등재하면 한 결판에 두 번 울린다. `aiRetire01` 은 플레이어의 사건이 아니라 제외.
const SOUND_BY_KEY := {
	"raceLog.gpStart01": "gp_start",
	"raceLog.overtakeSuccess01": "result_advance",   # SE-E01 전진 (추월·순위 상승)
	"raceLog.defendSuccess01": "result_defend",      # SE-E02 방어 (피추월 방어)
	"raceLog.stableSector01": "result_stable",       # SE-E03 안정 (무사 통과)
	"raceLog.troubleHit01": "result_trouble",        # SE-E04 트러블 (소)
	"raceLog.chanceProc01": "result_chance",         # SE-E06 찬스 개화
	"raceLog.chanceDuel01": "result_chance",
	"raceLog.momentum01": "momentum_bonus",
	"raceLog.timeout01": "timeout",
	"raceLog.duelWin01": "duel_win",
	"raceLog.duelLoseOvertake01": "duel_lose",
	"raceLog.duelLoseDefense01": "duel_lose",
	"raceLog.playerRetire01": "retire",
	"raceLog.resonanceEnter01": "resonance_announce",
}

# **SE-E05 중립은 결선하지 않았다.** "무사건·혼합 상쇄"(D11 §2.4)에 해당하는 확정 턴이
# 현 엔진에 없다 — 정산 ②자원 단계가 트러블이 없으면 반드시 `stableSector01`(안정)을
# 발행하므로 섹터 턴은 전부 안정 또는 트러블이다(40 GP·섹터 턴 480건 전수 실측: 결과 없음 0건).
# 결과 계열이 비는 것은 듀얼 패배 턴뿐인데 그것은 무사건이 아니라 듀얼 결판이다 —
# 그 자리에 중립음을 넣으면 패배에 통과음이 겹친다. 총괄 보고분(D05·D11 정합).

# O9 색각 대체 도상 대상 — 팔레트 정본 §6 교체 4행 중 **심볼 2종**이 도상에 색이 구워진다.
# 게이지 위험·주의는 런타임 색이라 `UiPalette` 조회 창구가 바로 처리한다.
const ALT_ICON_IDS := ["symbol_line", "symbol_trouble"]

# 섹터 속성(A존)의 치수 접미. **릴 심볼에는 붙이지 않는다** — 릴은 `KEEP_CENTERED` 무배율로
# 32 를 그대로 쓰는 것이 계약이고(D10 §2.2 · 대장 §4.1.1 경고), A존 속성은 슬롯이 16 이라
# 32 원도를 넣으면 1/2 축소가 되어 원도의 절반이 버려진다(8차 §5-③ 실측).
const ATTR_VARIANT := "_16"

var _icon_cache: Dictionary = {}

var data: GameData
var rng: RngService
var engine: RaceEngine

var _timer_active := false
var _timer_remaining := 0.0
var _timer_base := 10.0
var _timer_effective_base := 10.0
var _timer_disabled := false
var _revealing := false
var _confirm_lockout := 0.0
var _lockout_base := 0.3

# 사운드 상태 — 전이 시점을 잡기 위한 직전 상태 기억(상태 자체는 전부 엔진·데이터가 갖는다).
var _timer_band := 0        # 0 여유 · 1 경고 · 2 임박 (D05 §7.2 구간 = 링과 같은 경계값)
var _tick_left := 0.0       # 임박 틱 잔여 — 주기는 링의 점멸과 동기 (D11 §2.3 SE-T03)
var _chassis_warned := false
var _charge_shown := 0

var _reel_icons: Array[TextureRect] = []
var _reel_panels: Array[PanelContainer] = []
var _reel_frame_styles: Array[StyleBoxFlat] = []

# 릴 선택 커서 표시 (IMPL-207 · 원격 7차 §3-라 보고분).
#
# **D09 는 커서의 시각 표시에 침묵한다** — §1.3 은 입력만("X + D패드 좌우 → A"), §3.2 는
# *홀드 상태*의 이중 표시(프레임 잠금 + 토글 점등)만 규정한다. 선택 위치는 별개 축이라
# 규격이 없다. 그래서 [가안]이고, 색은 신규가 아니라 기확정 슬롯이다(`ACCENT_ACTIVE` = C3).
#
# **표시 조건을 X 홀드 중으로 좁혔다.** 상시 표시하면 키보드·마우스 사용자에게는 릴 1에
# 영구 강조가 붙는데 그 강조가 아무 뜻도 없다 — 홀드는 1·2·3 키로 직접 찍기 때문이다.
# 조합을 쥐고 있는 동안만 뜨면 "지금 어디를 고르는 중인가"만 답하고 사라진다.
#
# **봉인(불변규칙 5):** 커서는 선택 위치 전속이다. 심볼·결과·매치와 상관하는 어떤 값도
# 읽지 않으며, 릴 정지 연출 중(`_revealing`)에는 아예 뜨지 않는다.
var _cursor_active := false
var _hold_boxes: Array[CheckBox] = []
var _skill_buttons: Array[Button] = []
var _snapshot_icons: Array[TextureRect] = []   # SH3 이전 후보 줄의 도상 3기

@onready var _e01_position: Label = %E01Position
@onready var _e02_lap_sector: Label = %E02LapSector
@onready var _e02_corner: Label = %E02Corner
@onready var _e02_attr: TextureRect = %E02SectorAttr
@onready var _e02_resonance: Label = %E02Resonance
@onready var _e03_front: ProgressBar = %E03FrontGauge
@onready var _e03_rear: ProgressBar = %E03RearGauge
@onready var _e04_timer_ring: Control = %E04TimerRing
@onready var _e04_timer_value: Label = %E04TimerValue
@onready var _e05_reels: HBoxContainer = %E05Reels
@onready var _e07_wave: Control = %E07VaneWave
@onready var _e07_text: Label = %E07VaneText
@onready var _e08_respin: Button = %E08Respin
@onready var _e08_skills: HBoxContainer = %E08Skills
@onready var _e05_snapshot: Button = %E05Snapshot
@onready var _e05_snapshot_new: Button = %E05SnapshotNew
@onready var _reject_notice: Label = %RejectNotice
@onready var _e08_charge: Button = %E08ChargeIntervene
@onready var _e08_confirm: Button = %E08Confirm
@onready var _e10_log: LogFeed = %E10LogFeed
@onready var _e11_chassis_bar: ProgressBar = %E11ChassisBar
@onready var _e11_chassis_value: Label = %E11ChassisValue
@onready var _e12_charge: Label = %E12Charge
@onready var _duel_overlay: Control = %DuelOverlay
@onready var _pause_overlay: Control = %PauseOverlay
@onready var _tutorial: Control = %TutorialOverlay

var _paused := false

# 패드 모디파이어 장부 — 어떤 버튼이 지금 눌려 있는가 / 그 홀드가 조합으로 소비됐는가.
# **[가안] 조합 판별 = 릴리스 시점 판정** (D09 는 조합의 구현 방식에 침묵 — 인계 §3 재량분).
# `X` 는 단독이면 리스핀이고 홀드면 릴 선택 모디파이어다. 누르는 순간에는 어느 쪽인지 알 수
# 없으므로 **뗄 때** 판정한다: 홀드 중 조합이 한 번이라도 성립했으면 그 X 는 모디파이어였고,
# 아니면 단독 입력이었다. 같은 형식을 `LB + Y`(상세 정보) 대 `Y`(차지 개입)에도 쓰되,
# 그쪽은 모디파이어가 LB 라서 Y 를 누르는 시점에 이미 판별이 선다(릴리스 대기 불요).
var _pad_held: Dictionary = {}         # button_index -> true
var _pad_combo_used: Dictionary = {}   # button_index -> 이 홀드가 조합으로 소비됐는가
# X 홀드 중 D패드 좌우가 고르는 릴. **선택 표시는 아직 없다** — 입력 판독 층만 결선했다.
var _hold_cursor := 0
var _skill_cursor := 0        # RB 조합 중 고른 스킬 슬롯 (포커스로 표시)

# 통상 턴의 릴 표시 배열 — 듀얼 중에는 오버레이의 릴로 스왑된다 (아래 _enter_duel 참조)
var _base_reel_icons: Array[TextureRect] = []

# E13 소모품 2슬롯 (별첨A §A-4). 슬롯 수 = 반입 상한(param_consumable_carry_cap = 2)과
# 1:1이므로 인벤토리가 슬롯을 넘치지 않는다 — 상한이 바뀌면 슬롯 수는 별첨A 개정 사안이다.
var _e13_slots: Array[Button] = []
var _e13_slot_ids: Array[String] = []   # 슬롯 index → 소모품 id (빈 슬롯은 목록 밖)


# 세션 주입 없이 단독 인스턴스화되는 경로(검사 하네스)를 위해 자체 세션을 연다.
# 폴백이 아니라 **동등한 개시 경로**다 — 라우터가 하는 일을 그대로 한다.
func _on_bound(_payload: Dictionary) -> void:
	_boot()


func _ready() -> void:
	if session == null:
		_boot()


func _boot() -> void:
	if engine != null:
		return
	if session == null:
		var standalone := GameData.new()
		standalone.load_all()
		session = RunSession.new()
		session.setup(standalone)
		session.begin_career(1)
	data = session.data
	# O9 색각 대체 적용 — **라우터가 하는 일을 그대로 한다** (총괄 판정 IMPL-176 ③).
	# 팔레트는 정적 클래스라 세션을 쥘 수 없어 옵션을 밀어 넣는 구조인데, 그 밀어 넣기는
	# `FlowScreen.bind()` 에 있다. 단독 인스턴스화 경로는 `bind()` 를 거치지 않으므로
	# 여기서 같은 일을 하지 않으면 **이 경로에서만** 화면이 옛 색으로 뜬다.
	UiPalette.apply_options(session.options)
	_timer_base = data.param("param_timer_base_sec")
	_lockout_base = data.param("param_confirm_lockout_sec")
	_collect_reels()
	_e04_timer_ring.configure(
		data.param("param_timer_leeway_ratio"), data.param("param_timer_warning_ratio")
	)
	# 성장 단계 진폭 계수 — D13 별첨A §8.2. 1단계 고정(성장 상태는 아웃게임 층 소관).
	_e07_wave.configure(data.param("param_vane_amp_stage1"))
	_e10_log.configure(int(data.param("param_log_slot_cap")), int(data.param("param_font_size_body")))
	_setup_scene_panel()
	_duel_overlay.boost_pressed_signal().connect(_on_boost)
	_pause_overlay.setup(session)
	_pause_overlay.resumed.connect(func():
		_paused = false
		session.audio.set_paused(false))
	_pause_overlay.quit_to_title.connect(func(): go("SYS-01", {}))
	(%E14Menu as Button).pressed.connect(_open_pause)
	# ── E08 행동 버튼의 클릭 경로 (IMPL-301 — 사용자 실기 발견) ──
	#
	# **버튼이 화면에 있는데 눌리지 않았다.** 이 셋은 `text` 와 `disabled` 만 관리되고
	# `pressed` 연결이 0건이어서, 키보드·패드(액션 경유 `_unhandled_input`)로만 동작하고
	# **마우스로는 죽어 있었다.** D09 §1.3 은 세 입력을 같은 조작 집합으로 두므로 한 경로만
	# 사는 것은 규격 위반이다. 다른 18화면은 전건 결선돼 있었고 이 화면만 빠져 있었다
	# (전수 감사 — UISCR ⑳ 가 그 감사를 상시화한다).
	#
	# **이중 발화는 생기지 않는다** — 포커스를 가진 Button 이 `ui_accept` 를 처리하면
	# 뷰포트가 그 이벤트를 소비 처리하므로 `_unhandled_input` 까지 내려오지 않는다(실측 확인).
	_e08_confirm.pressed.connect(_on_primary_action)
	_e08_respin.pressed.connect(_on_respin)
	_e08_charge.pressed.connect(_on_charge_intervene)
	# ── E08 스킬 슬롯 5개 (원격 20차 계약 §1.1·§1.2 · IMPL-308~310) ──
	# 세 입력이 **같은 핸들러**를 탄다 — 클릭은 여기, F1~F5 는 `_unhandled_key_input`,
	# 패드 RB 조합은 `_handle_pad_context` 가 같은 `_on_skill_slot(i)` 를 부른다.
	# 12차에 마우스 경로만 죽어 있던 결함(IMPL-301)이 슬롯에서 재발하지 않게 결선을
	# 세우는 자리에서 세 경로를 한꺼번에 못박는다 — UISCR ⑳ 가 면제 없이 그것을 본다.
	for skill_index in range(_skill_buttons.size()):
		_skill_buttons[skill_index].pressed.connect(_on_skill_slot.bind(skill_index))
	_e05_snapshot.pressed.connect(_on_snapshot_revert)
	_e05_snapshot_new.pressed.connect(_on_snapshot_keep_new)
	_collect_consumable_slots()
	_apply_static_strings()
	# TUT-01 — 첫 그랑프리 실주행 위 오버레이(§6 "별도 튜토리얼 스테이지 불신설").
	# 1회성 판정은 온보딩 기록이 쥔다(옵션 초기화로 재활성 — §A-25 확정).
	#
	# 세 번째 인자 = 콜아웃이 덮으면 안 되는 상시 표시 영역(IMPL-258). **Zone A 만 넘긴다** —
	# 순위·랩·게이지는 튜토리얼 중에도 계속 읽어야 하는 상태다. Zone D 는 넘기지 않는다:
	# 5단계 중 3단계가 Zone D 를 *지목*하므로 예약해 버리면 반대편 배치가 성립하지 않는다
	# (하이라이트 회피는 `_place_callout` 의 겹침 비교가 따로 본다).
	var tut_reserved: Array[Control] = [%ZoneA as Control]
	_tutorial.setup(session, self, tut_reserved)
	# 레이스 HUD 의 버튼은 하나하나가 고유 게임 행동이라 일반 조작음을 붙이지 않는다
	# (핸들러가 자기 이벤트를 울린다 — 키보드 입력도 같은 핸들러를 타므로 경로가 하나다).
	# 정지 오버레이만 메뉴 성격이라 조작음을 결속한다.
	audio_bind_controls(_pause_overlay)
	_start_gp()
	if _tutorial.should_run():
		_tutorial.begin()


func _audio_auto_bind() -> bool:
	return false


func _collect_consumable_slots() -> void:
	_e13_slots.clear()
	for child in (%E13Consumables as Node).get_children():
		var slot := child as Button
		if slot == null:
			continue
		var index := _e13_slots.size()
		slot.pressed.connect(func(): _on_consumable(index))
		_e13_slots.append(slot)


func _open_pause() -> void:
	if _paused:
		return
	_paused = true
	# 일시정지 = BGM 유지·SFX 뮤트 (D11 §4.3 확정 — 레트로 관례).
	# **발화를 막는 것이 아니라 들리지 않게 한다** — 정지 중에도 상태 전이는 사운드를 던지고,
	# 그것을 코어에서 걸면 재개 시점에 무엇이 울렸어야 하는지가 사라진다.
	session.audio.set_paused(true)
	# 개입 창 중이면 가림막 — 정지 중 보드 숙고 차단 (D09 §3.7 · F2 보호)
	_pause_overlay.open(_timer_active)


# 씬에는 표시 문자열을 굳히지 않는다 — 전량 런타임 키 참조 (D09 §6.6 · D12 §8.1).
func _apply_static_strings() -> void:
	var s := data.strings
	(%FrontLabel as Label).text = s.text("ui.race.gaugeFront")
	(%RearLabel as Label).text = s.text("ui.race.gaugeRear")
	(%ChassisLabel as Label).text = s.text("ui.race.chassisLabel")
	(%ChargeLabel as Label).text = s.text("ui.race.chargeLabel")
	_e08_respin.text = s.text("ui.race.respin")
	_e08_charge.text = s.text("ui.race.chargeIntervene")
	(%E14Menu as Button).text = s.text("ui.race.menu")
	# 홀드 토글은 번호를 라벨에 단다 (개선 2026-09-01) — 키 1·2·3 이 코드에만 있고 화면
	# 어디에도 적혀 있지 않아 발견 가능성이 0 이었다. 번호가 곧 키 힌트다. 상세(패드 조합
	# 포함)는 툴팁과 옵션 조작 탭이 진다.
	for hold_index in range(_hold_boxes.size()):
		var box := _hold_boxes[hold_index]
		box.text = s.text("ui.race.holdKeyFormat", {"index": hold_index + 1})
		box.tooltip_text = s.text("ui.race.hintHold")
	# 스킬 슬롯 문면은 **정적이 아니다** — 덱 내용·잔여 횟수·차지에 따라 매 갱신마다
	# 바뀌므로 `_refresh_skill_slots()` 가 진다(여기서 잠금으로 덮어쓰면 첫 프레임이
	# 잠금으로 깜빡인다). 13차에 덱이 결선되며 이 자리의 정적 잠금 표기를 걷었다.
	var respin_label := _with_cost("ui.race.respin", "param_charge_hold_cost")
	var negate_label := _with_cost("ui.race.chargeIntervene", "param_charge_negate_cost")
	_e08_respin.text = respin_label
	_e08_charge.text = negate_label
	# 단축키 힌트는 라벨이 아니라 툴팁에 둔다 — 액션 열 실폭(371px)에 키 표기까지 얹으면
	# ja 최장 문면이 밀린다. 패드 사용자는 옵션 조작 탭이 같은 정보를 진다.
	_e08_respin.tooltip_text = s.text("ui.race.hintRespin")
	_e08_charge.tooltip_text = s.text("ui.race.hintCharge")
	_refresh_consumables()


func _with_cost(label_key: String, cost_param: String) -> String:
	var s := data.strings
	var cost := s.text("ui.race.costFormat", {"cost": int(data.param(cost_param))})
	return s.text("ui.race.actionWithCost", {"label": s.text(label_key), "cost": cost})


func _process(delta: float) -> void:
	if _paused:
		return  # 타이머 정지 (D09 §3.7) — 잔량·링·확정 잠금 전부 동결
	_process_shake(delta)
	if _confirm_lockout > 0.0:
		_confirm_lockout = maxf(0.0, _confirm_lockout - delta)
		_refresh_action_enabled()
	if not _timer_active or _timer_disabled:
		return  # 비활성 = 잔량이 흐르지 않는다 — 타임아웃도 자연 부재 (D09 §6.2)
	_timer_remaining = maxf(0.0, _timer_remaining - delta)
	_e04_timer_ring.set_ratio(_timer_remaining / _timer_effective_base)
	_update_timer_value()
	_process_timer_sound(delta)
	if _timer_remaining <= 0.0:
		_timer_active = false
		_e04_timer_ring.set_active(false)
		var timeout_events := engine.timeout()
		_push_events(timeout_events)
		_run_presentation(timeout_events)  # 타임아웃 자동 확정도 확정이다 — 채널 동일
		_next_turn()


# 패드 눌림/뗌 장부. **소비하지 않는다** — `_input` 은 전 입력을 가장 먼저 보므로 여기서만
# 기록해 두면 이후 어느 층(`_shortcut_input`·`_unhandled_input`)에서 판정하든 상태가 최신이다.
func _input(event: InputEvent) -> void:
	var pad := event as InputEventJoypadButton
	if pad == null:
		return
	if pad.pressed:
		_pad_held[pad.button_index] = true
		_pad_combo_used[pad.button_index] = false
	else:
		_pad_held.erase(pad.button_index)


func _pad_is_held(button_index: int) -> bool:
	return _pad_held.has(button_index)


# ── 층위 우선 (D09 v1.3 §1.3 명문): 컨텍스트 층이 이 화면에서 공통 층에 우선한다 ──
# 패드 `Y` 는 공통 층에서 상세 정보지만 이 화면에서는 **차지 개입**이고, 상세 정보는
# v1.3 에서 `LB 홀드 + Y` 로 **재배치**됐다. 키보드 열(T)은 공통 층 그대로다 — 그래서
# 가로채는 것은 패드 Y 하나뿐이고 나머지는 `super` 로 넘긴다(무언의 소실 금지).
func _shortcut_input(event: InputEvent) -> void:
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed and pad.button_index == PAD_Y:
		get_viewport().set_input_as_handled()
		if _pad_is_held(PAD_LB):
			_pad_combo_used[PAD_LB] = true
			_toggle_detail()
		else:
			_on_charge_intervene()
		return
	super._shortcut_input(event)


# 입력 매핑은 D09 §1.3 — 확정과 스핀이 같은 키인 것이 원칙이다
# ("결과를 불러온다 → 결과를 받아들인다"가 같은 물리 동작으로 순환).
#
# **공통 층 조작은 액션 경유다** (매핑표 공통 층 · 총괄 판정 IMPL-190 ①).
# 원시 키코드 직독은 `InputEventKey` 만 보기 때문에 **패드 이벤트가 아예 도달하지 않는다** —
# 실제로 스핀·확정·일시정지가 패드에 무반응이었다(5차 발견). 액션에는 매핑표의 키보드 열이
# 이미 담겨 있으므로(IMPL-186) 이 전환은 동작 집합을 **보존하면서 넓힌다**:
# Space·Enter·KpEnter 는 `ui_accept` 안에, Esc 는 `pause_menu` 안에 그대로 있다.
#
# 바뀌는 것은 **입력 판독 층뿐**이다 — 위 순환 설계(확정 = 스핀과 같은 물리 동작)는 불변이며,
# 오히려 패드에서도 A 하나로 같은 순환이 성립하게 된다.
#
# **소비 표시는 분기의 첫 줄이다 (IMPL-299 — 실기 크래시 교정).** 처리 여부는 분기 조건이
# 정하지, 동작의 결과가 정하지 않는다. 순서를 뒤집으면 **동작이 화면을 이탈시킨 뒤**
# `get_viewport()` 를 부르게 되고 그 값은 null 이다 — `_on_primary_action()` 이 GP 를 끝내
# RACE-03 으로 라우팅한 프레임에 사용자 실기에서 그대로 터졌다
# (`Cannot call method 'set_input_as_handled' on a null value` · `race_screen.gd:364`).
# 같은 형태를 VN 에서 먼저 고쳤는데(IMPL-292) 그때 **한 지점만 고치고 훑지 않은 것**이
# 이 재발의 원인이다. 지금은 이 파일의 전 분기를 같은 규칙으로 맞췄고 UISCR ⑲가
# `godot/ui` 전역을 훑는다.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		_open_pause()
		return
	if _paused:
		return  # 정지 중 레이스 입력 차단 — 오버레이가 자체 포커스를 갖는다
	if _handle_pad_context(event):
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_primary_action()


# 컨텍스트 층 조합 판독. **`ui_accept` 보다 먼저 본다** — 층위 우선 규칙상 X·RB 홀드 중의
# A 는 스핀이 아니라 조합의 일부다. 처리했으면 true 를 돌려 공통 층으로 내려가지 않게 한다.
func _handle_pad_context(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null:
		return false
	# ── X 눌림/뗌 = 커서 표시 개폐 (IMPL-207) ──
	# 조합을 쥐는 순간 어디를 고르는 중인지 보여야 한다. **리스핀 판정과 무관하다** —
	# 여기서는 `_pad_combo_used` 를 건드리지 않으므로 X 단독 뗌의 리스핀 경로가 그대로다.
	if pad.button_index == PAD_X:
		_cursor_active = pad.pressed
		_refresh_reel_frames()
	# ── X 홀드 + D패드 좌우 → A : 릴 홀드 토글 ──
	if pad.pressed and _pad_is_held(PAD_X):
		if pad.button_index == PAD_DPAD_LEFT or pad.button_index == PAD_DPAD_RIGHT:
			get_viewport().set_input_as_handled()
			var step := -1 if pad.button_index == PAD_DPAD_LEFT else 1
			_hold_cursor = wrapi(_hold_cursor + step, 0, REEL_COUNT)
			_refresh_reel_frames()
			_pad_combo_used[PAD_X] = true
			return true
		if pad.button_index == PAD_A:
			get_viewport().set_input_as_handled()
			_toggle_hold(_hold_cursor)
			_pad_combo_used[PAD_X] = true
			return true
	# ── RB 홀드 + D패드 좌우 → A : 스킬 슬롯 (D09 §1.3 확정 기준값) ──
	#
	# 13차에 소비부가 서면서 **가로채기가 활성화로 바뀌었다.** 종전 주석의 "활성화 경로가
	# 아직 없다"는 해소됐다 — 놓아두면 RB 홀드 중의 A 가 공통 층으로 흘러 스핀으로
	# 오발화하던 이유는 그대로이므로 소비 처리는 유지한다.
	#
	# 커서는 **포커스로 보인다** — 스킬 버튼에 `grab_focus()` 를 걸면 기존 포커스 링이
	# 그대로 어디를 고르는 중인지 말한다(릴 커서가 프레임 색으로 말하는 것과 같은 축).
	# 새 시각 어휘를 만들지 않는다.
	if pad.pressed and _pad_is_held(PAD_RB):
		if pad.button_index == PAD_DPAD_LEFT or pad.button_index == PAD_DPAD_RIGHT:
			get_viewport().set_input_as_handled()
			var skill_step := -1 if pad.button_index == PAD_DPAD_LEFT else 1
			_skill_cursor = wrapi(_skill_cursor + skill_step, 0, _skill_buttons.size())
			_skill_buttons[_skill_cursor].grab_focus()
			_pad_combo_used[PAD_RB] = true
			return true
		if pad.button_index == PAD_A:
			get_viewport().set_input_as_handled()
			_on_skill_slot(_skill_cursor)
			_pad_combo_used[PAD_RB] = true
			return true
	# RB 를 놓으면 포커스를 기본 자리(확정)로 돌린다 — 별첨A §A-6 "초기 포커스: 스핀(=확정)".
	# 스킬 버튼에 포커스가 남으면 그 다음 A 가 조합 없이 스킬을 쏜다.
	if not pad.pressed and pad.button_index == PAD_RB:
		if bool(_pad_combo_used.get(PAD_RB, false)):
			_pad_combo_used[PAD_RB] = false
			_e08_confirm.grab_focus()
			get_viewport().set_input_as_handled()
			return true
	# ── X 단독(뗌 시점 판정) : 리스핀 ──
	if not pad.pressed and pad.button_index == PAD_X:
		var used: bool = bool(_pad_combo_used.get(PAD_X, false))
		_pad_combo_used[PAD_X] = false
		if not used:
			get_viewport().set_input_as_handled()
			_on_respin()
			return true
	return false


# 레이스 컨텍스트 층 전속 조작 (D09 §1.3 두 번째 표) — 아직 키보드 열만 결선돼 있다.
# 패드 열(리스핀·차지 개입·홀드 토글)은 조합 입력이라 별도 배정 대상이다.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _paused:
		return
	if key.keycode == KEY_R:
		get_viewport().set_input_as_handled()
		_on_respin()
		return
	if key.keycode == KEY_C:
		get_viewport().set_input_as_handled()
		_on_charge_intervene()
		return
	# E13 소모품 4·5 — 같은 핸들러(_on_consumable)를 탄다: 클릭·포커스 확정과 경로가 하나다.
	# T1 밖·듀얼·빈 슬롯 거부는 핸들러와 엔진(use_consumable 전건 재검)이 이미 쥐고 있다.
	var consumable_index := CONSUMABLE_KEYS.find(key.keycode)
	if consumable_index >= 0:
		get_viewport().set_input_as_handled()
		_on_consumable(consumable_index)
		return
	# 스킬 슬롯 F1~F5. **소비 표시가 분기의 첫 줄이다** (IMPL-299) — 동작이 화면을
	# 이탈시킨 뒤 뷰포트를 만지면 null 참조로 죽는다.
	var skill_index := SKILL_KEYS.find(key.keycode)
	if skill_index >= 0:
		get_viewport().set_input_as_handled()
		_on_skill_slot(skill_index)
		return
	var hold_index := HOLD_KEYS.find(key.keycode)
	if hold_index >= 0:
		get_viewport().set_input_as_handled()
		_toggle_hold(hold_index)


# ── 노드 수집 ──
func _collect_reels() -> void:
	for i in range(REEL_COUNT):
		var column := _e05_reels.get_child(i)
		var frame: PanelContainer = column.get_node("Frame")
		_reel_panels.append(frame)
		# 커서가 테두리 색을 바꾸므로 **스타일박스를 릴별로 복제해 둔다.** 씬 리소스를 그대로
		# 만지면 그 변경이 리소스에 남아 다음 인스턴스·에디터까지 따라간다(섀시바 전례 :788).
		var style := frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		frame.add_theme_stylebox_override("panel", style)
		_reel_frame_styles.append(style)
		_base_reel_icons.append(column.get_node("Frame/Symbol"))
		var box: CheckBox = column.get_node("Hold")
		box.toggled.connect(_on_hold_toggled)
		_hold_boxes.append(box)
	_reel_icons = _base_reel_icons
	for child in _e08_skills.get_children():
		_skill_buttons.append(child)
	for child in _e05_snapshot.get_node("SnapshotRow").get_children():
		_snapshot_icons.append(child)


# ── GP 수명 주기 ──
# 서킷 선택·슬롯 보정 주입은 시즌 층이 한다 (D08 §2.4 — 화면은 규칙을 갖지 않는다).
func _start_gp() -> void:
	if not session.begin_gp():
		push_error("RaceScreen: season layer produced no circuit for this slot")
		return
	rng = session.rng
	engine = session.engine
	_e10_log.clear_feed()
	# 무대 BGM(§4.1 5종 1:1) + 관중 베드(AMB-01). **이벤트 id 를 무대 id 에서 파생**하므로
	# 무대가 늘면 `sound_map` 에 행만 추가하면 붙는다 — 화면에 무대 목록을 적지 않는다.
	sfx("%s_enter" % String(data.stage_of_active_circuit().get("id", "")))
	sfx("race_stage_enter")
	_charge_shown = engine.charge   # 이월 차지를 획득으로 오인하지 않게 기준선을 먼저 잡는다
	_chassis_warned = _chassis_critical()
	_push_events(engine.start_gp())
	_next_turn()


func _next_turn() -> void:
	_timer_active = false
	_revealing = false
	# 고지는 **턴 경계에서 걷힌다** — 거부는 그 턴의 사실이고, 넘어간 턴에 남으면
	# 아직 유효한 규칙처럼 읽힌다(`limit_hold` 는 실제로 새 턴에서 거짓이 된다).
	_reject_notice.text = ""
	_e04_timer_ring.set_active(false)
	var info := engine.begin_turn()
	if String(info.get("type", "")) == "finished":
		_on_gp_finished()
		return
	# 듀얼 삽입·복귀 (D05 §3 DUEL) — 오버레이 표시는 화면 전환이 아니다 (D09 §3.5).
	# 릴 은닉은 **배열 스왑이 끝난 뒤**여야 한다 — 스왑 전에 지우면 복귀 쪽 릴에
	# 직전 턴 심볼이 남는다 (SEAL-E가 실제로 잡았다: T1 대기 중 비공개 실패 15건).
	if String(info.get("type", "")) == "duel":
		sfx("duel_enter")   # SE-D02 — 감광 + 프레임 인에 동기 (D11 §2.7 · D09 §3.5)
		_enter_duel(info)
	else:
		_exit_duel()
	_hide_reels()
	_show_reel_phase_cut()   # 릴 국면 복귀 — 기본 주행 고정 (D09 §3.1.1)
	_push_events(info.get("events", []))
	_refresh_strip()
	_refresh_resources()
	_refresh_action_enabled()
	_update_timer_value()


# 릴 표시 배열을 오버레이로 스왑한다 — 공개·은닉·봉인 검사(SEAL-E)가 전부 같은 경로로
# 오버레이 릴을 보게 하는 장치다. 이중 구현이 없으므로 봉인 규칙이 갈라지지 않는다.
func _enter_duel(info: Dictionary) -> void:
	var opponent_id := String(info.get("opponent", ""))
	var opponent: Dictionary = engine.entrants.get(opponent_id, {})
	if opponent.is_empty():
		push_error("RaceScreen: duel opponent missing - %s" % opponent_id)
		return
	_duel_overlay.show_duel(data.strings, opponent, int(info.get("duel_type", 0)))
	_reel_icons = _duel_overlay.reel_icons()
	_hide_reels()
	_refresh_boost()


func _exit_duel() -> void:
	if not _duel_overlay.visible:
		return
	_duel_overlay.dismiss()
	_reel_icons = _base_reel_icons


func _refresh_boost() -> void:
	var cap := int(data.param("param_charge_boost_max"))
	var can_add := _intervention_open() and engine.charge >= 1 and engine.duel_boost < cap
	_duel_overlay.set_boost(engine.duel_boost, cap, can_add)


func _on_boost() -> void:
	if not _intervention_open() or not engine.current_turn_is_duel:
		return
	# **거부에 확인음을 내지 않는다 (26차 재검 부수).** 상한에 걸린 투입에도
	# `boost_spend` 가 울려 "썼다"는 거짓 확인을 주고 있었다 — 소리는 결과를 말해야 한다.
	var boost := engine.add_duel_boost()
	if not bool(boost.get("ok", false)):
		# 부스트를 **고지 원천으로 새로 넣은 것이 아니다** — 사인 창구가 하나가 되니
		# 등재된 사유(`charge`)는 자연히 문면을 얻고 미등재(`limit_boost`)는 침묵한다.
		# 규칙은 한 줄뿐이다: 표에 있으면 말하고 없으면 침묵한다.
		_report_outcome(false, String(boost.get("error", "")))
		return
	_report_outcome(true)
	sfx("boost_spend")
	_refresh_boost()
	_refresh_resources()


func _on_gp_finished() -> void:
	sfx("gp_finish")   # SE-U19 피니시 + AMB-03 함성 (D11 SC-09)
	_show_result_cut([], false, true)   # SC-09 피니시 (D13 §8.2 우선순위)
	_push_events([{
		"phase": "T5", "key": "raceLog.gpFinish01",
		"params": {"rank": engine.result.get("player_rank", 0)},
	}])
	_refresh_strip()
	_refresh_resources()
	_refresh_action_enabled()
	# 결산 화면이 저장 지점이다 (D09 §2.4 RESULT) — 전이는 라우터가 수행한다.
	# 단독 실행(검사 하네스)에서는 라우터가 없으므로 요청만 남는다.
	session.close_gp()
	go("RACE-03", {})


# ── 개입 창 (T2~T4) ──
# ── 개입 창 관문 · 거부 귀결 — 액션 경로 전수의 구조적 귀결 (14차 ⑦) ──
#
# 27차 ③ 이 `_on_respin` 하나에서 발견한 형태를 화면 층 전건에 걸쳐 훑었고, 결함이
# **두 계열**로 갈렸다.
#
# **계열 A — 화면만 아는 조건.** `_timer_active`·`_revealing`·SH3 택1 대기는 엔진이 모른다.
# 이것을 버튼 `disabled` 에만 적고 핸들러에 적지 않으면 키·패드 경로가 그대로 통과한다.
# 실측된 구멍: **SH3 택1 대기 중 리스핀·차지 개입·홀드 토글이 열려 있었다** —
# 슬롯 행만 `_snapshot_pending()` 을 물었고 나머지 세 줄은 묻지 않았다. 대기 중에 릴을
# 다시 굴리면 위에 뜬 '이전 후보' 줄이 두 걸음 낡은 후보를 가리키고, 그것을 누르면
# 방금 지불한 차지가 조용히 되돌려진다. 이 계열은 **핸들러가 버튼과 같은 술어를 부른다**
# 로 닫는다 — 조건을 두 곳에 적으면 언젠가 갈라지므로 술어를 하나만 둔다.
#
# **계열 B — 엔진이 아는 규칙.** 차지 부족·턴당 1회·합산 상한·횟수 소진은 엔진이 최종
# 판정자다(거부 시 비용·상태 전부 무변경 — 20차 계약 §1.1). 화면이 이것을 재구현하면
# 판정이 두 곳에 살고, 그것이 곧 "버튼은 켜지는데 눌리지 않는" 상태의 씨앗이다.
# 그래서 **핸들러는 계열 B 를 보지 않는다.** 버튼 `disabled` 는 마우스에게 사전 표식으로
# 남기고, 키·패드 경로는 엔진에 닿아 **거부를 소리와 문면으로 되받는다.** 두 경로가
# 같은 사실을 각자 가진 채널로 배운다 — 어느 쪽도 오해하지 않는다.
func _intervention_open() -> bool:
	return _timer_active and not _revealing and not _snapshot_pending()


# 거부 귀결의 유일 창구. **소리와 문면이 갈리지 않게 한 곳에 둔다** — 26차에 부스트가
# 상한 거부에도 `boost_spend` 를 울려 "썼다"는 거짓 확인을 준 것이 소리를 각 지점에서
# 따로 울리던 탓이었다. 성공은 지난 고지를 걷는다: 남겨 두면 방금 성립한 조작 옆에
# 직전의 야단이 남는다.
#
# 문면은 `SKILL_REJECT_KEYS` 등재분만 낸다 — 미등재 사유는 침묵이 최종형이다
# (봉인 3종 = 결과 누출 · 조작 오류 계열 = 화면 결함이지 문면 사안이 아니다 · `limit_boost`
# = 문면 미유입. 회신에 올린다).
func _report_outcome(ok: bool, error: String = "") -> void:
	if ok:
		_reject_notice.text = ""
		return
	sfx("input_rejected")   # SE-I14 (D11 §2.2)
	_notify_skill_rejected(error)


func _on_primary_action() -> void:
	# **완급 비트는 확정 입력으로 즉시 통과한다** (D09 §3.1.1 "스킵 가능"). 비트는 표현이지
	# 요구가 아니므로, 넘기려는 입력이 비트에 먹히고 사라지면 그 자체가 지연이 된다.
	if _pacing_beat_left > 0.0:
		_pacing_beat_left = 0.0
		if _pacing_beat_timer != null:
			_pacing_beat_timer.time_left = 0.0   # 즉시 통과 — 타이머가 이번 프레임에 발화한다
		return
	if _revealing or engine == null or engine.finished:
		return
	# SH3 택1 대기 중이면 확정은 **새 후보 채택**이고 턴은 넘기지 않는다 — 한 입력이
	# 택1과 확정을 겸하면 되돌릴 기회가 사라진다(신구 병치의 의미가 없어진다).
	if _resolve_snapshot_keep_new():
		return
	if _timer_active:
		_on_confirm()
		return
	if engine.turn_phase == RaceTypes.TurnPhase.T1_SECTOR_OPEN:
		_on_spin()


func _on_spin() -> void:
	# **봉인은 스핀 커밋(T2)에서 연다** (D12 §6.3 — reel 스트림 소비 시점). 여는 것이 먼저다:
	# 커밋 뒤 여는 순서면 그 사이에 결과 상관 사운드가 지나갈 창이 생긴다.
	_seal(true)
	sfx("reel_spin_start")
	sfx("reel_spin_loop")
	engine.spin()  # T2 커밋 — reel 스트림 소비. 결과는 아직 어떤 경로에도 없다
	_refresh_action_enabled()
	# **튜토리얼 단계 진행은 여기서 알리지 않는다** — 스핀 커밋 직후에 콜아웃이 바뀌면
	# 릴 정지 연출이 끝나기 전에 릴 외 표면이 움직인다(봉인·불변규칙 5. SEAL-E 실측 검출).
	# 정지 연출이 끝나는 지점에서 흘린다.
	_tutorial_pending = "spin"
	_reveal_reels([0, 1, 2], true)


func _on_confirm() -> void:
	if not _timer_active or _confirm_lockout > 0.0:
		return
	_timer_active = false
	_e04_timer_ring.set_active(false)
	# 비활성 시 모멘텀 = 조건 불성립 (여유 구간 자체가 없다 — D09 §6.2 채택 구조)
	var ratio := 0.0 if _timer_disabled else _timer_remaining / _timer_effective_base
	sfx("confirm")
	# 결판 상대를 정산 **전에** 떠 둔다 — `_resolve_duel` 이 `duel_opponent` 를 비운다.
	_last_duel_opponent = engine.duel_opponent if engine.current_turn_is_duel else ""
	var events := engine.confirm(ratio)
	_tutorial.notify_action("confirm")
	# 기원 단서 3 — 결판이 실제로 났을 때만(무산된 듀얼은 결판이 아니다)
	if not _last_duel_opponent.is_empty() and not _duel_result_event(events).is_empty():
		_emit_clue_axion(_last_duel_opponent)
	_push_events(events)
	_run_presentation(events)  # 확정 후 이벤트에서만 — 봉인 (불변규칙 5)
	# 전개 국면(T5) 컷 — 로그와 **병행**이라 추가 대기가 0이다 (D09 §3.1.1)
	_show_result_cut(events, not _last_duel_opponent.is_empty(), engine.finished)
	# 듀얼 결과는 프레임 내 표기 후 해제한다 (D09 §3.5). 표기 유지 0.6초 = D13 별첨A
	# §8.1(v1.4) 확정 기준값(총괄 회신 C항) — 다른 연출 시간(fx_*)과 같은 데이터 창구 경유.
	if _duel_overlay.visible:
		var result_event := _duel_result_event(events)
		if not result_event.is_empty():
			# 결과 문면의 매개({amount} 등)는 이벤트 params 로 치환한다 — 로그 번역과 동일 경로
			var result_text := data.strings.text(
				String(result_event["key"]), result_event.get("params", {})
			)
			_duel_overlay.show_result(result_text)
			await get_tree().create_timer(data.param("param_fx_duel_result_hold_sec")).timeout
	await _play_pacing_beat()
	_next_turn()


# 듀얼 결판 로그 키 대장 — 엔진이 발행하는 결과 키 전량 (접두 비교 대신 열거:
# 새 결과 키가 생기면 여기 등재해야 프레임 표기가 붙는다 — 의도적 변경만 통과)
const DUEL_RESULT_KEYS := [
	"raceLog.duelWin01", "raceLog.duelLoseOvertake01", "raceLog.duelLoseDefense01",
]


func _duel_result_event(events: Array) -> Dictionary:
	for event in events:
		if DUEL_RESULT_KEYS.has(String(event.get("key", ""))):
			return event
	return {}


func _on_respin() -> void:
	if not _intervention_open():
		return
	var keep: Array = []
	for i in range(REEL_COUNT):
		if _hold_boxes[i].button_pressed:
			keep.append(i)
	var outcome := engine.hold_respin(keep)
	if not outcome.get("ok", false):
		# **`limit_hold` 의 유일한 산지가 여기다** (`hold_respin` — 엔진 전수 확인).
		# 26·28차가 문면을 유입해 `SKILL_REJECT_KEYS` 에 행을 세웠는데 그 행을 읽는
		# 호출부는 스킬 경로뿐이었다 → **고지가 실기에 한 번도 뜬 적이 없다.**
		# 27차가 "버튼 disabled 를 우회한다"고 적은 그 경로가 정확히 이 줄이다.
		_report_outcome(false, String(outcome.get("error", "")))
		return
	_report_outcome(true)
	_seal(true)   # 재정지도 정지 연출이다 — 그 사이의 결과 상관 사운드를 다시 막는다
	sfx("respin")
	_push_events(outcome.get("events", []))
	var changed: Array = []
	for i in range(REEL_COUNT):
		if not keep.has(i):
			changed.append(i)
	# 재정지분도 정지 연출을 다시 재생한다 — 개입 창 내라 정보 누출은 아니지만
	# 즉시 갱신은 정지 연출 규격이 아니다(IMPL-019 이월 3번 해소).
	# 홀드와 리스핀은 같은 엔진 호출(hold_respin)의 두 얼굴이다 — 릴을 고정한 채 눌렀으면
	# '홀드'를 배운 것이고, 고정 없이 눌렀으면 '리스핀'을 배운 것이다.
	# 스핀과 같은 이유로 통지는 재정지 연출이 끝난 뒤로 미룬다.
	_tutorial_pending = "hold" if not keep.is_empty() else "respin"
	_reveal_reels(changed, false)
	_refresh_resources()


func _on_charge_intervene() -> void:
	if not _intervention_open():
		return
	var outcome := engine.negate_trouble()
	if outcome.get("ok", false):
		sfx("charge_intervene")
		_report_outcome(true)
		_push_events(outcome.get("events", []))
		_tutorial.notify_action("charge")   # 거부된 개입은 배운 것이 아니다
	else:
		# `no_trouble` 은 봉인 침묵 3종이다 — 소리만 나고 문면은 없다. 있으면 그것이 곧
		# "지금 트러블이 없다"는 결과 누출이다(불변규칙 5).
		_report_outcome(false, String(outcome.get("error", "")))
	_refresh_resources()
	_refresh_action_enabled()




# ── E08 스킬 슬롯 (D09 §3.2 액션 열 · §1.3 "F1~F5 / 클릭 / RB 홀드 + D패드·A") ──
#
# 화면은 **`engine.skill_slots()` 하나만 읽는다** — `data.skills` 도 `outgame.deck` 도 보지
# 않는다(원격 20차 계약 §1.2). 가용 판정을 화면이 재구현하면 "버튼은 켜지는데 눌리지 않는"
# 상태가 생기므로 판정은 엔진 한 곳뿐이다.
#
# 라벨은 **`S{n}` + 비용 ◆n** 이다 — 별첨A §A-6 의 배치도 자체가 `[리스핀R][S1~S5][차지C]`
# 로 슬롯을 번호로 적고, 액션 열 실폭이 371px 이라 스킬명 5개(최장 8자)가 물리적으로 들어가지
# 않는다. 이름·효과·잔여 횟수는 툴팁이 진다(툴팁 고정 = `detail_info` T·Y).
func _refresh_skill_slots() -> void:
	var s := data.strings
	var slots: Array = engine.skill_slots() if engine != null else []
	# 개입 창 밖·정지 연출 중에는 전 슬롯이 닫힌다. `usable` 에도 국면 관문이 들어 있지만
	# `_revealing` 은 화면 층 상태라 엔진이 모른다 — 두 겹 다 본다.
	var open := _intervention_open()
	for i in range(_skill_buttons.size()):
		var button := _skill_buttons[i]
		var slot_label := s.text("ui.race.skillSlotFormat", {"index": i + 1})
		if i >= slots.size():
			# 미확장 슬롯 = 잠금 표기 (D09 §3.2). 덱 상한은 아웃게임이 늘린다.
			button.text = s.text("ui.race.locked")
			button.tooltip_text = slot_label
			button.disabled = true
			continue
		var slot: Dictionary = slots[i]
		var cost_text := s.text("ui.race.costFormat", {"cost": int(slot["charge_cost"])})
		button.text = _action_label(slot_label, cost_text, slot)
		# 툴팁 꼬리에 키 힌트(F1~F5·패드 조합)를 단다 — 라벨은 S{n} 폭 계약이라 못 싣는다
		button.tooltip_text = s.text("ui.race.skillHintFormat", {
			"body": _action_label(s.text(String(slot["name_key"])), cost_text, slot),
			"index": i + 1,
		})
		button.disabled = not open or not bool(slot["usable"])


# 액션 라벨 — **잔여 횟수가 있으면 확장형 키를 쓴다** (조립 키 유입 IMPL-425).
#
# 26차에 붙이지 못했던 배지다. 버튼 문면이 `actionWithCost` 로 이미 조립돼 있어 배지를 이어
# 붙이려면 코드가 문자열을 합성해야 했고 V4 가 그것을 막았다 — **막는 것이 옳았다.**
# 답은 우회가 아니라 확장형 키 1건이었고, 그것이 들어왔다.
#
# **무제한(`uses_left = -1`)에는 이 키를 쓰지 않는다.** 20차 계약("0 = 소진"과 같은 값을
# 쓸 수 없다)의 표시 층 귀결이다 — 무제한을 숫자로 그리면 어떤 숫자든 거짓말이 된다.
func _action_label(label: String, cost_text: String, slot: Dictionary) -> String:
	var s := data.strings
	var uses_left := int(slot.get("uses_left", -1))
	if uses_left < 0:
		return s.text("ui.race.actionWithCost", {"label": label, "cost": cost_text})
	return s.text("ui.race.actionWithUses", {
		"label": label,
		"cost": cost_text,
		"left": s.text("ui.race.skillUsesFormat", {
			"remaining": uses_left, "limit": int(slot.get("uses_per_tour", 0)),
		}),
	})


# 릴 인자는 **홀드 선택을 그대로 읽는다** — 이 화면의 릴 지정 어포던스는 E05 클릭·E06 토글·
# 패드 커서 하나뿐이고(별첨A §A-6 "클릭 = 홀드 토글"), 스킬용 선택 어휘를 새로 만들면
# 같은 릴에 두 가지 선택 상태가 생긴다.
#
# `[가안]` **SC3(심볼 복제)의 target/donor 배정** — 선택 2개 중 **낮은 인덱스 = donor ·
# 높은 인덱스 = target** 으로 둔다. 엔진은 `provisional[target] = provisional[donor]` 이므로
# 배정이 뒤집히면 플레이어 의도와 반대로 덮인다. 릴이 좌→우 순차 정지라 좌측이 먼저 확정된
# 값이라는 것이 유일한 방향 근거인데, **정본이 대상 지정 흐름을 정하지 않았다** —
# 진짜 답은 대상 지정 UI 이고 그것은 판정 사안이다(회신 판정 요청).
func _skill_args(family: String) -> Dictionary:
	var picked: Array = []
	for i in range(REEL_COUNT):
		if _hold_boxes[i].button_pressed:
			picked.append(i)
	match family:
		"hold":
			return {"keep": picked}
		# ── SC3 대상·공여 배정 = **[가안]** (판정 요청 ㉕ · 15차 ⑤ 폐문 조건 부여) ──
		#
		# 낮은 인덱스 = 공여(donor) · 높은 인덱스 = 대상(target). **정본이 방향을 말하지
		# 않는다** — 별첨A §4.2 는 *"인접 릴 심볼 복제"* 까지만이고 어느 쪽이 원본인지는
		# 비어 있다.
		#
		# **이 [가안]은 규칙으로 닫히지 않는다.** 홀드 체크박스는 *"이 릴을 고정한다"* 는
		# 뜻인데 변환 계열에서 두 개를 켜면 **켠 릴 하나가 덮인다** — 체크박스의 뜻과
		# 반대로 움직인다. 하나만 켜서 공여로 삼으면 대상이 두 인접 중 어느 쪽인지가 다시
		# 비고, 순서로 정하려 해도 체크박스는 **순서를 기억하지 않는다.**
		# 즉 **한 줄의 체크박스로는 방향 있는 짝을 표현할 수 없다** — 표현 수단이 없는 것이지
		# 규칙이 없는 것이 아니다.
		#
		# **폐문 조건 (IMPL-424 원칙):** 대상 지정 UI 가 서는 회차. 그때 이 분기는 통째로
		# 그 UI 의 산출을 받는 한 줄이 된다. 그때까지 현행 배정을 유지한다 —
		# 임의로 뒤집으면 이미 익힌 거동만 바뀌고 모호함은 그대로다.
		"convert":
			if picked.is_empty():
				return {}   # 엔진이 "target" 으로 거부한다 — 화면이 대신 판정하지 않는다
			if picked.size() >= 2:
				return {"target": int(picked[picked.size() - 1]), "donor": int(picked[0])}
			return {"target": int(picked[0])}
		_:
			return {}


func _on_skill_slot(index: int) -> void:
	if not _intervention_open():
		return
	if engine == null:
		return
	var slots: Array = engine.skill_slots()
	if index >= slots.size():
		return
	var slot: Dictionary = slots[index]
	var family := String(slot["family"])
	var outcome := engine.use_skill(String(slot["id"]), _skill_args(family))
	if not bool(outcome.get("ok", false)):
		_report_outcome(false, String(outcome.get("error", "")))   # 거부 = 비용·횟수 무변경 (계약 §1.1)
		_refresh_action_enabled()
		return
	_report_outcome(true)
	# 계열음 4종 = SE-I05~I08. `family` 를 그대로 쓴다 — 표에 이미 서 있다(계약 §1.5).
	sfx("skill_%s" % String(outcome["family"]))
	_push_events(outcome.get("events", []))
	# 홀드 계열은 릴을 다시 굴린다 → **재정지 연출을 다시 재생한다**(리스핀 전례).
	# 변환 계열은 잠정 결과를 제자리에서 바꾸므로 즉시 갱신이 맞다(정지가 아니다).
	if family == "hold":
		_seal(true)
		var keep: Array = _skill_args("hold").get("keep", [])
		var changed: Array = []
		for i in range(REEL_COUNT):
			if not keep.has(i):
				changed.append(i)
		_reveal_reels(changed, false)
	else:
		_repaint_provisional()
	_refresh_snapshot_row()
	_refresh_resources()
	_refresh_action_enabled()


# ── 스킬 거부 고지 (26차) ──
#
# **19분기가 5키로 접힌다.** `use_skill` 의 `error` 는 리터럴 15종 + `_skill_precondition`
# 경유 4종인데, 문면은 그보다 적다 — 같은 말을 할 사유끼리 묶이기 때문이다.
#
# **셋은 문면을 두지 않는다** (`RaceEngine.SEAL_SILENT_ERRORS` — 총괄 판정):
# `no_trouble`·`symbol`·`same` 은 사유가 **잠정 결과의 내용에 의존**하므로 문면이 곧
# 결과 누출이다(불변규칙 5). 소리 거부만 남긴다 — 침묵이 이 셋의 최종형이다.
#
# 나머지 — `phase`·`deck`·`unknown`·`effect`·`no_provisional`·`keep`·`target`·`adjacent` 는
# **조작 오류이지 규칙 거부가 아니다**(창이 닫혔거나 인자가 안 모였다). 화면이 애초에
# 그 상태의 버튼을 비활성으로 두므로(`_refresh_action_enabled`) 사용자에게 도달하지 않는다 —
# 도달한다면 그것은 문면 사안이 아니라 화면 결함이다. 그래서 고지하지 않는다.
const SKILL_REJECT_KEYS := {
	"charge": "ui.race.skillRejectedCharge",
	"uses": "ui.race.skillRejectedUses",
	"respin_cap": "ui.race.skillRejectedHoldCap",
	# 도달 가능 실측(26차 재검): `_on_respin` 이 `hold_used` 를 보지 않고 키·패드 액션
	# 경로가 버튼 `disabled` 를 우회한다 — 버튼 비활성은 마우스만 막는다. 규칙 거부이므로
	# `respin_cap` 과 같은 성격이고, 문면 유입(내러티브 10차)으로 고지에 편입됐다.
	"limit_hold": "ui.race.skillRejectedLimitHold",
	# 부스트 상한 거부 — 27차 `limit` 2분할의 나머지 반쪽. 28차에 `limit_hold` 만 문면을
	# 얻고 이쪽은 미유입이었는데, 주력 14차의 `_report_outcome` 창구 통일이 그 공백을
	# 드러냈고(㉞) 내러티브 11차가 채웠다(IMPL-434).
	"limit_boost": "ui.race.skillRejectedLimitBoost",
	"already_hold": "ui.race.skillRejectedAlreadyHold",
	"already_mod": "ui.race.skillRejectedAlreadyMod",
	"duel_turn": "ui.race.skillRejectedDuelTurn",
	"sector_turn": "ui.race.skillRejectedSectorTurn",
}


# 고지 자리 = **전용 슬롯** (14차 ①). 26차의 로그 존 얹기는 잠정이었고 그 잠정이 두 값을
# 치르고 있었다: ⓐ거부가 경기 기록과 같은 줄에 섞여 **정산 로그를 밀어낸다**(슬롯 4)
# ⓑ`E10LogFeed` 는 우측 열이라 방금 누른 액션 행에서 **눈이 가장 먼 자리**다.
#
# 슬롯은 액션 행 **바로 아래**에 선다 — 누른 자리에서 답이 온다. 항상 존재하고 문면만
# 비운다: `visible` 로 개폐하면 고지가 뜰 때마다 릴·액션 행이 한 줄만큼 튄다(스페이서가
# 흡수하는 것은 높이이고 튀는 것은 그 위의 전부다). 예약 자리 = 튜토리얼 콜아웃이
# Zone A 를 예약하는 것과 같은 축이다.
#
# **자수 상한을 두지 않는다.** 총괄 인계 ① 은 최소 100px(ja 실측 최장 112px)을 요구했고
# 이 슬롯의 실폭은 액션 행과 같은 열(ReelZone 안쪽 = 371.6px)이므로 **최장 문면의 3.3배**다.
# 상한이 없으면 규칙도 필요 없다 — 대신 *열 폭이 최장 문면보다 넓다*를 UISCR 이 재고,
# 문면이 자라면 그 축이 먼저 깨진다(상한을 숫자로 적어 두면 열이 좁아질 때 침묵한다).
func _notify_skill_rejected(error: String) -> void:
	if not SKILL_REJECT_KEYS.has(error):
		_reject_notice.text = ""   # 침묵 계열 — 직전 고지를 남겨 두면 엉뚱한 사유를 가리킨다
		return
	_reject_notice.text = data.strings.text(String(SKILL_REJECT_KEYS[error]))


# 변환 계열이 바꾼 잠정 결과를 릴에 다시 그린다. **정지 연출이 아니다** — 심볼이 제자리에서
# 바뀌는 것이고 개입 창 내부이므로 봉인 대상이 아니다(결과는 이미 공개돼 있다).
func _repaint_provisional() -> void:
	var provisional := engine.get_provisional()
	for i in range(mini(REEL_COUNT, provisional.size())):
		_reel_icons[i].texture = _icon_texture(String(provisional[i]))


# ── SH3 스냅샷 택1 — 신구 병치 ──
#
# `snapshot_previous` 가 비지 않은 동안이 택1 대기다. 살아 있는 릴이 **새 후보**이고
# 그 위에 뜨는 줄이 **이전 후보**다 — 새 문면을 만들지 않고 배치와 조작으로 가른다:
# 이전 후보 줄을 누르면 되돌아가고, 확정을 누르면 새 후보로 간다.
#
# 문면 2건(새/이전 라벨)이 있으면 더 분명하겠지만 `strings.csv` 는 내러티브 레인 배타
# 창구다 — 키 이름을 회신에 올리고 여기서는 만들지 않는다(없는 키를 참조하면 화면에
# 키 문자열이 그대로 뜬다: `StringTable.text()` 가 미등재 키를 그대로 돌려준다).
func _snapshot_pending() -> bool:
	return engine != null and not engine.snapshot_previous.is_empty()


func _refresh_snapshot_row() -> void:
	var pending := _snapshot_pending()
	_e05_snapshot.visible = pending
	# ── 신 후보 전용 버튼 (14차 ④ · `ui.race.snapshotKeepNew` 소비) ──
	#
	# 종전에는 한쪽만 버튼이었다. 그러면 화면이 **택1로 보이지 않는다** — 보이는 것은
	# 버튼 하나와, "확정을 누르면 새 것으로 간다"는 **어디에도 적혀 있지 않은 사실**이다.
	# SH3 의 효과 자체가 *택1* 이므로 두 갈래가 같은 모양으로 서야 성립한다.
	#
	# 자리는 **릴 위**다: 위 버튼 = 새 후보(바로 아래 살아 있는 릴이 그 내용) · 아래 버튼 =
	# 이전 후보(자기 안에 도상 3기를 담는다). 새 후보 쪽에 도상을 다시 그리지 않는 이유는
	# 릴이 이미 그것이기 때문이고, 같은 것을 두 번 그리면 어느 쪽이 실물인지 흐려진다.
	#
	# **병치 구조는 유지된다** — 이 버튼은 확정과 같은 함수를 부른다(§`_on_snapshot_keep_new`).
	# 새 경로가 아니라 이름 없이 있던 경로에 이름이 붙은 것이다.
	_e05_snapshot_new.visible = pending
	if not pending:
		return
	_e05_snapshot_new.text = data.strings.text("ui.race.snapshotKeepNew")
	_e05_snapshot_new.tooltip_text = data.strings.text("ui.skill.sh3")
	var previous: Array = engine.snapshot_previous
	for i in range(mini(_snapshot_icons.size(), previous.size())):
		_snapshot_icons[i].texture = _icon_texture(String(previous[i]))
	# **신·구 어느 쪽인지 말이 붙는다 (26차).** 도상만으로는 "이 줄이 구 후보"라는 것이
	# 드러나지 않는다 — SH3 의 효과는 *택1* 이고 무엇과 무엇 중 고르는지가 보여야 성립한다.
	# **이 줄이 '구 후보'임을 말이 밝힌다 (26차).** 도상만으로는 신·구가 갈리지 않고,
	# SH3 의 효과는 *택1* 이라 무엇과 무엇 중 고르는지가 보여야 성립한다.
	# `snapshotKeepNew` 는 붙이지 못했다 — 신 후보 유지는 **버튼이 아니라 '그냥 확정'** 이라
	# 라벨을 걸 노드가 없다(전용 버튼 = 씬 층 · 주력 몫). 회신 §키 계약으로 올린다.
	_e05_snapshot.text = data.strings.text("ui.race.snapshotKeepOld")
	_e05_snapshot.tooltip_text = data.strings.text("ui.skill.sh3")


# **택1 두 갈래는 관문이 뒤집힌다** — 대기 *중에만* 열린다. `_intervention_open()` 은
# 대기를 닫힌 조건으로 세므로 여기서 부르면 두 갈래가 영원히 닫힌다. 전수(14차 ⑦)에서
# 이 반전을 명기해 둔다: 다음 훑기가 "가드가 다르다"를 결함으로 오독하지 않게.
func _on_snapshot_revert() -> void:
	if not _snapshot_pending() or _revealing:
		return
	var outcome := engine.choose_snapshot(false)
	if not bool(outcome.get("ok", false)):
		_report_outcome(false, String(outcome.get("error", "")))
		return
	_report_outcome(true)
	sfx("skill_hold")   # 되돌림도 홀드 계열의 귀결이다 (SH3 = hold)
	_repaint_provisional()
	_refresh_snapshot_row()
	_refresh_resources()
	_refresh_action_enabled()


# 택1 대기 중의 확정 = **새 후보 채택**이다. 턴을 넘기지 않는다 — 그러면 한 입력이
# 두 결정(택1 + 확정)을 겸해 되돌릴 기회가 사라진다.
func _resolve_snapshot_keep_new() -> bool:
	if not _snapshot_pending():
		return false
	var outcome := engine.choose_snapshot(true)
	if bool(outcome.get("ok", false)):
		_report_outcome(true)
		sfx("skill_hold")
	else:
		_report_outcome(false, String(outcome.get("error", "")))
	_refresh_snapshot_row()
	_refresh_resources()
	_refresh_action_enabled()
	return true


# 전용 버튼 경로 (14차 ④). `_resolve_snapshot_keep_new()` 는 확정 경로와 **같은 함수**다 —
# "신 후보 유지 = 그냥 확정"의 병치 구조를 버튼이 밀지 않는다. 시그널은 반환값을 쓰지
# 않으므로 void 로 감싸는 한 줄만 둔다(두 번째 구현을 만들면 두 경로가 갈린다).
func _on_snapshot_keep_new() -> void:
	_resolve_snapshot_keep_new()

func _toggle_hold(index: int) -> void:
	if not _intervention_open():
		return
	_hold_boxes[index].button_pressed = not _hold_boxes[index].button_pressed


func _on_hold_toggled(pressed: bool) -> void:
	# SE-I02/I03 = 토글 쌍 (D11 §2.2 — 온이 상향·오프가 하향 음정). 홀드 '적용'이 아니라
	# 토글 자체의 피드백이므로 릴을 실제로 돌리는 리스핀(SE-I04)과 별개 지점이다.
	sfx("hold_on" if pressed else "hold_off")
	_refresh_reel_frames()


# 순차 정지 공개 (D09 §3.2 — 간격은 D13 릴 정지 간격).
# **연출 중 타이머 정지 [가안]:** 정본은 정지 연출 시간이 개입 창에 포함되는지 말하지 않는다.
# 흐르게 두면 리스핀을 쓸수록 모멘텀 잔여 비율(D05 §7.3)이 구조적으로 깎여 개입 선택에
# 이중 페널티가 붙는다 — D09 §3.2가 타임아웃에 대해 명문화한 "이중 처벌 아님"과 같은 방향으로 잡았다.
func _reveal_reels(indices: Array, start_window: bool) -> void:
	_revealing = true
	var was_running := _timer_active
	_timer_active = false
	_refresh_action_enabled()
	# O4 릴 정지 속도 — 표준 / 고속(배율 D13 창구) / 일괄 정지 (D09 §6.1 · D05 §5.1 예약 이행).
	# 일괄 정지도 정지 이벤트 자체는 유지한다 — 연출 압축이지 결과 선표시가 아니다 (간격 0).
	var interval := data.param("param_reel_stop_interval_sec")
	match session.options.index_of("o4"):
		1:
			interval *= data.param("param_opt_reel_fast_mult")
		2:
			interval = 0.0
	var provisional := engine.get_provisional()
	for i in indices:
		if interval > 0.0:
			await get_tree().create_timer(interval).timeout
		if engine == null:
			return
		_reel_icons[i].texture = _icon_texture(String(provisional[i]))
		# SE-R03 — **실제 정지하는 릴** 순서 기준 (D11 규칙 R-b: 홀드 릴은 정지음 없음).
		# 일괄 정지(O4)도 정지 이벤트 자체는 유지된다(규칙 R-c) — 간격만 0 이다.
		sfx("reel_stop")
	_revealing = false
	# **봉인 해제 지점.** 릴 정지 연출이 여기서 끝난다 — 이 줄보다 앞에서 결과 상관 사운드를
	# 부르면 디스패처가 막고, 뒤로 옮기면 매치 고지음(R-a)이 막힌다. 순서가 규격이다.
	_seal(false)
	_announce_matches(provisional)
	# O5 개입 창 타이머 — 기본 / ×1.5 / ×2 / 비활성 (D09 §6.1·§6.2 — 배율은 D13 창구 전사값).
	# 비활성 = 타이머·구간 자체가 부재. 개입 창은 열리되(가드 재사용) 잔량이 흐르지 않고
	# 링은 소등, 모멘텀은 조건 불성립으로 자연 미발생(_on_confirm 이 ratio 0 을 넘긴다).
	# **튜토리얼 중 타이머 비활성 고정** (D09 §6 · 별첨A §A-25 확정 — D08 튜토리얼 GP 정합).
	# 배우는 동안 시간 압박을 걸지 않는다. O5 설정과 무관하게 강제된다.
	_timer_disabled = session.options.index_of("o5") == 3 or _tutorial.visible
	var effective_base := _timer_base
	match session.options.index_of("o5"):
		1:
			effective_base *= data.param("param_opt_timer_mult_1")
		2:
			effective_base *= data.param("param_opt_timer_mult_2")
	# 릴을 움직인 행동의 튜토리얼 통지는 **정지 연출이 끝난 지금** 흘린다 (봉인 — 불변규칙 5).
	if _tutorial_pending != "":
		var pending := _tutorial_pending
		_tutorial_pending = ""
		_tutorial.notify_action(pending)
	if start_window:
		_push_events([{"phase": "T3", "key": "vane.brief.provisional01", "params": {}}])
		_timer_effective_base = effective_base
		_timer_remaining = effective_base
		_confirm_lockout = _lockout_base  # T3 진입 후 확정 오입력 방어 (D09 §1.3)
		sfx("intervention_open")   # SE-I01 — T4 진입·타이머 링 점등 동기
		_timer_band = 0            # 구간 전환음의 기준선 — 창이 열릴 때마다 여유부터 시작한다
		_tick_left = 0.0
	_timer_active = true if start_window else was_running
	if _timer_active and not _timer_disabled:
		_e04_timer_ring.set_active(true)
		_e04_timer_ring.set_ratio(_timer_remaining / _timer_effective_base)
	if engine.current_turn_is_duel:
		_refresh_boost()
	_refresh_strip()
	_refresh_action_enabled()
	_update_timer_value()


# 도상 경로 규약: 셀 파일명 = 테이블 id (심볼 `symbol_*` · 속성 `attr_*`).
# D10 §8.1 에셋 대장의 요소 매핑 열이 아직 없어 파일명 규약으로 잇는다 —
# [가안]이며 대장 도입 시 교체한다. 없는 도상은 침묵하지 않고 보고한다(IMPL-019 계열).
#
# **O9 색각 대체는 도상이 아니라 색만 바꾼다**(정본 §6). 심볼 도상은 색이 구워진 PNG 라
# 런타임 틴트로는 정본 색을 재현할 수 없다 — 같은 도상의 대체색 파일(`<id>_alt.png`)을
# 우선 찾고, **없으면 조용히 기본 도상으로 돌아간다.** 대체 도상 실물은 에셋 트랙 몫이며
# (교체 대상 = 라인·트러블 2종) 부재는 결함이 아니라 미유입이므로 여기서 보고하지 않는다.
#
# **치수 축은 소비 지점이 정한다** (IMPL-226 — 이 창구를 릴 심볼과 섹터 속성이 함께 쓴다).
# 릴은 32 고정(무배율 계약)이고 섹터 속성만 `_16` 이므로, 창구 안에서 치수를 판단하면
# 두 소비부가 서로의 규격을 밟는다. 그래서 `variant` 를 인자로 받고 기본값은 32(빈 접미)다.
#
# **두 축의 이름 순서를 고정한다: `<id>[_alt][_16]`.** 색각 대체는 도상 축, 치수는 치수 축이라
# 서로 독립인데, 순서를 정하지 않으면 같은 파일을 두 이름으로 찾게 된다.
#
# **`_16` 부재는 32 로 되돌리지 않는다** — 되돌리면 비정수 축소가 조용히 되살아난다
# (Zone A 가 정확히 그 상태였다 — 8차 §5-③ 실측 `RENDER_SCALE=0.5`). 없으면 보고한다.
func _icon_texture(asset_id: String, variant: String = "") -> Texture2D:
	if asset_id.is_empty():
		return null
	var base := asset_id
	if UiPalette.colorblind and ALT_ICON_IDS.has(asset_id):
		base = "%s_alt" % asset_id
	var cache_key := base + variant
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key]
	var path := "%s%s.png" % [ICON_DIR, cache_key]
	if ResourceLoader.exists(path):
		_icon_cache[cache_key] = load(path) as Texture2D
		return _icon_cache[cache_key]
	# 대체 도상 부재 = 미유입이므로 조용히 기본 도상으로. **치수는 유지한다.**
	if base != asset_id:
		return _icon_texture(asset_id, variant)
	# 진단 문자열은 영문 — 표시 문자열이 아니지만 V4는 한글 리터럴을 경로 불문 차단한다
	# (코어의 push_error 관행과 동일하게 맞춘다)
	push_error("RaceScreen: icon asset missing - %s" % path)
	_icon_cache[cache_key] = null
	return null


# ── 표시 갱신 ──
# 비공개 상태 = 도상 부재. 회전 중 심볼을 흘리는 연출은 두지 않는다 —
# 표시되는 것이 결과와 상관되면 그 자체가 봉인 누출 경로이고, 상관 없는 심볼을 흘리려면
# 난수가 필요한데 RNG 6스트림은 게임 로직 전속이다(D12 §6). 연출 결선은 아트 유입 시.
func _hide_reels() -> void:
	for icon in _reel_icons:
		icon.texture = null
	for box in _hold_boxes:
		box.button_pressed = false
	_refresh_reel_frames()
	# 턴 경계에서 엔진이 `snapshot_previous` 를 비운다(`begin_turn`) — 표시를 맞춰 둔다.
	_refresh_snapshot_row()


# 홀드 상태 = 프레임 잠금 표시 + 토글 점등의 이중 표시 (D09 §3.2)
#
# 비홀드 프레임은 **등채널 감광**이다 — 밝기만 낮추고 색상은 건드리지 않는다.
# 구 값 `Color(0.75, 0.78, 0.82)` 은 채널이 불균등해 비홀드 릴에 **한색 편이**를 넣었는데,
# 설계 근거가 없었다(D09 §3.2 는 감광 자체를 규정하지 않고, git 이력상 RACE-01 초판에서
# 근거 없이 들어왔다 — 총괄 판정 IMPL-190 ④ "근거 없으면 비의도"). 감광은 상태 표시이지
# 색 정보가 아니므로 색상 이동은 심볼 판독(D10 §5.1 색+도상 이중 부호화)에 잡음이 된다.
# 감광률은 구 값의 중앙 채널을 취해 실화면 인상을 보존했다.
func _refresh_reel_frames() -> void:
	# 커서는 홀드 토글이 실제로 가능한 국면에서만 뜬다 — `_toggle_hold()` 의 가드와 같은 조건이다.
	# 조건이 갈리면 "커서는 보이는데 A 가 안 먹는" 상태가 생긴다.
	var cursor_on := _cursor_active and _intervention_open()
	for i in range(REEL_COUNT):
		var held: bool = _hold_boxes[i].button_pressed
		_reel_panels[i].modulate = Color(1.0, 1.0, 1.0) if held else Color(0.78, 0.78, 0.78)
		if i < _reel_frame_styles.size():
			# 감광(modulate)과 테두리 색은 **다른 채널**이다 — 홀드와 커서가 서로를 지우지 않는다.
			_reel_frame_styles[i].border_color = UiPalette.ACCENT_ACTIVE \
				if cursor_on and i == _hold_cursor else UiPalette.FRAME_LINE


func _refresh_strip() -> void:
	var s := data.strings
	_e01_position.text = s.text("ui.race.positionFormat", {
		"rank": engine.player_position(), "total": engine.positions.size(),
	})
	_e02_lap_sector.text = s.text("ui.race.lapSectorFormat", {
		"lap": engine.lap, "laps": data.circuit_int("laps"),
		"sector": engine.sector, "sectors": data.circuit_int("sectors_per_lap"),
	})
	# GP_START~첫 begin_turn 사이에는 섹터가 아직 0이다 — 조회하면 침묵 기본값 가드가
	# 정당하게 push_error를 낸다(IMPL-019). 진입 전에는 코너명을 비운다.
	if engine.sector > 0:
		var sector_entry := data.sector_entry(engine.sector)
		var corner_key := String(sector_entry.get("name_key", ""))
		_e02_corner.text = s.text(corner_key)
		# 섹터 속성만 `_16` 이다 — 릴 심볼은 32 무배율 계약(`ATTR_VARIANT` 주석 참조).
		_e02_attr.texture = _icon_texture(String(sector_entry.get("main_attr", "")), ATTR_VARIANT)
	else:
		_e02_corner.text = ""
		_e02_attr.texture = null
	# 레조넌스는 **진입 시점에만** 공표한다 — 위치 사전 표시·예고는 어떤 채널로도 하지 않는다
	# (D08 §3.7 R6 · D09 §3.6). 엔진의 announced 플래그를 그대로 따른다.
	_e02_resonance.visible = engine.resonance_announced
	_e02_resonance.text = s.text("ui.race.resonanceBanner")
	_e03_front.value = engine.front_gauge
	_e03_rear.value = engine.rear_gauge
	# 베인 콜아웃(E07)은 여기서 건드리지 않는다 — 발화는 `vane.*` 이벤트가 소유하며,
	# 상태 갱신이 콜아웃을 덮으면 발화가 화면에 남지 못한다(첫 구현에서 실제로 지워졌다).


func _refresh_resources() -> void:
	var s := data.strings
	var chassis_max := data.param("param_chassis_max")
	_e11_chassis_bar.max_value = chassis_max
	_e11_chassis_bar.value = engine.chassis
	var chassis_text := s.text("ui.race.chassisFormat", {"value": int(engine.chassis)})
	_e11_chassis_value.text = chassis_text
	var fill: StyleBoxFlat = _e11_chassis_bar.get_theme_stylebox("fill").duplicate()
	# 경고색과 경고음이 **같은 판정**을 본다 (표시값은 판정값에서 파생 — IMPL-100 계열).
	var critical := _chassis_critical()
	fill.bg_color = UiPalette.gauge_danger() if critical else UiPalette.CHASSIS_OK
	_e11_chassis_bar.add_theme_stylebox_override("fill", fill)
	# SE-D06 = **진입 시 1회** (D11 §2.7 — 반복 경보 아님). 회복해 임계를 벗어나면 재무장한다.
	# 로그 한 줄도 같은 판정·같은 1회 규약을 탄다 (개선 2026-09-01) — 게이지 색과 소리만으로는
	# 임계 진입 순간이 중계 기록에 남지 않아, 로그를 되짚어도 위기가 언제 시작됐는지 안 보였다.
	# 값 전이는 확정 정산 뒤에만 일어나므로 봉인(불변규칙 5)과 무접촉이다.
	if critical and not _chassis_warned:
		sfx("chassis_warning")
		_e10_log.push_line(
			s.text("ui.race.speakerRelay"), s.text("raceLog.chassisCritical01"),
			LogFeed.Speaker.RELAY
		)
	_chassis_warned = critical
	# SE-I13 = ◆ 스택 +1 동기. 획득원(심볼·안정 완주·듀얼 승리 보너스)이 여럿이라
	# 발생원마다 걸지 않고 **표시 수치의 증가**를 본다 — 소비(감소)는 대상이 아니다.
	if engine.charge > _charge_shown:
		sfx("charge_gain")
	_charge_shown = engine.charge
	_e12_charge.text = s.text("ui.race.chargeFormat", {
		"value": engine.charge, "cap": int(data.param("param_charge_cap")),
	})
	_refresh_consumables()


# 섀시 위험 임계 — D13 v1.6 §8.1 원천 확정(최대치의 25% · 결정 #16). 경고색·SE-D06·점멸이
# **이 한 식만** 본다. 값은 데이터 창구 경유다 — 종전 리터럴은 정본에 값이 없던 시절의
# 임시 명명이었고, D13 확정과 함께 `core_params` 로 옮겼다(총괄 판정 IMPL-157 §2-②).
func _chassis_critical() -> bool:
	if engine == null:
		return false
	return engine.chassis <= data.param("param_chassis_max") * data.param("param_chassis_warn_ratio")


# 재고 → 슬롯. 데이터 정의 순서로 펼치므로 같은 인벤토리는 항상 같은 슬롯에 앉는다
# (엔진이 딕셔너리를 돌려주므로 표시 순서를 화면이 고정해야 한다).
# 슬롯 문면은 도상 없이 채움/빔 2상태 — 소모품 아이콘은 D10 리소스 목록에 없다.
# 품목명은 툴팁으로 준다 (COM-02 — 슬롯 16×12 에 이름이 들어가지 않는다).
func _refresh_consumables() -> void:
	if _e13_slots.is_empty():
		return
	var s := data.strings
	_e13_slot_ids.clear()
	if engine != null:
		for id in data.consumables:
			for _n in range(int(engine.consumables_held.get(id, 0))):
				_e13_slot_ids.append(String(id))
	var empty_text := s.text("ui.race.consumableEmpty")
	var filled_text := s.text("ui.race.consumableFilled")
	for i in range(_e13_slots.size()):
		var slot := _e13_slots[i]
		if i < _e13_slot_ids.size():
			slot.text = filled_text
			slot.tooltip_text = s.text(String(data.consumables[_e13_slot_ids[i]]["name_key"]))
		else:
			slot.text = empty_text
			slot.tooltip_text = ""


# T1 섹터 개시 전속 (별첨A §A-4 E13 "T1에만 활성" · D06 §3.5 R-B).
#
# **`_intervention_open()` 을 쓰지 않는다 — 다른 창이다.** 소모품은 T1 에서 열리고 개입
# 3종은 T4 에서 열린다. 전수(14차 ⑦) 결과: 이 경로는 ⓐ키·패드 바인딩이 없어 마우스
# 전용이고 ⓑ`use_consumable` 이 `finished`·듀얼·T1·SECTOR_TURN·보유 수를 **전건 재검**한다.
# 그래서 버튼보다 약한 가드가 우회로가 되지 않는다 — 그 사실을 확인한 것이 전수의 몫이고,
# 확인 없이 "엔진이 다시 본다"고 적어 두는 것은 근거가 아니다(그 문장이 종전 주석이었다).
func _on_consumable(index: int) -> void:
	# 정지 중 차단 (실기 결함 교정 — 2026-09-01). 종전 전수(14차 ⑦)는 "키·패드 바인딩이
	# 없어 마우스 전용"이라 적었지만 **포커스 경로가 남아 있었다** — 정지 중 Tab 으로 이
	# 슬롯에 포커스가 넘어가고 확정 입력이 눌렸다(정지 상태에서 리페어 키트 실소비 실측).
	# 오버레이 쪽 포커스 트랩과 겹으로 막는다 — 가드 하나는 언젠가 우회된다.
	if _paused:
		return
	if engine == null or index >= _e13_slot_ids.size():
		return
	var events := engine.use_consumable(_e13_slot_ids[index])
	if events.is_empty():
		# 사유 코드가 없다 — `use_consumable` 은 빈 배열로만 거부한다. 문면 없이 소리만.
		_report_outcome(false, "")
		return  # 거부 = 상태 무변경 (엔진 계약) — 화면도 아무것도 하지 않는다
	_report_outcome(true)
	_push_events(events)
	_refresh_resources()
	_refresh_action_enabled()


func _refresh_action_enabled() -> void:
	# **버튼과 핸들러가 같은 술어를 부른다** (14차 ⑦). 종전에는 여기의 `open` 과 각 핸들러의
	# 가드가 각기 쓰여 있었고, SH3 택1 대기가 슬롯 행에만 들어가 있어 리스핀·차지·홀드
	# 세 줄이 대기 중에 열려 있었다. 술어를 하나로 만들면 그 갈라짐이 구조적으로 불가능해진다.
	var open := _intervention_open()
	_e08_respin.disabled = not open or engine == null or engine.hold_used
	_e08_charge.disabled = not open
	_refresh_skill_slots()
	for box in _hold_boxes:
		box.disabled = not open
	var can_spin := (
		engine != null and not engine.finished and not _revealing and not _timer_active
		and engine.turn_phase == RaceTypes.TurnPhase.T1_SECTOR_OPEN
	)
	_e08_confirm.disabled = not (can_spin or (open and _confirm_lockout <= 0.0))
	_e08_confirm.text = data.strings.text("ui.race.confirm" if _timer_active else "ui.race.spin")
	# E13 — 개입 창(T4)이 아니라 **섹터 개시(T1)** 에서 열린다. 듀얼 턴의 T1 은 제외
	# (듀얼 = 전용 스핀이라 '섹터 개시'가 아니다 — R-B 문면, IMPL-111).
	var can_use_item := (
		engine != null and not engine.finished and not _revealing and not _timer_active
		and engine.turn_phase == RaceTypes.TurnPhase.T1_SECTOR_OPEN
		and engine.gp_state == RaceTypes.GpState.SECTOR_TURN
		and not engine.current_turn_is_duel
	)
	for i in range(_e13_slots.size()):
		_e13_slots[i].disabled = not (can_use_item and i < _e13_slot_ids.size())


# 개입 창 구간음 (D11 §2.3 SE-T01~T03).
#
# 구간 경계는 **링이 쓰는 것과 같은 데이터 값**이다 — 색·두께·점멸과 소리가 갈라지면
# 삼중 부호화(D09 §3.2)에 네 번째 어긋난 축이 생긴다. O5 비활성이면 `_process` 가
# 여기 오기 전에 돌아가므로 SE-T01~T03 은 자연 미발생이다(D11 구간 문법 정합 · D09 §6.2).
func _process_timer_sound(delta: float) -> void:
	var ratio := _timer_remaining / _timer_effective_base
	var band := 0
	if ratio <= data.param("param_timer_warning_ratio"):
		band = 2
	elif ratio <= data.param("param_timer_leeway_ratio"):
		band = 1
	if band > _timer_band:
		# 되돌아가는 경계(잔량 증가)는 없다 — 전진 전이만 울린다.
		if band == 1:
			sfx("timer_enter_warning")
		else:
			sfx("timer_enter_imminent")
		_timer_band = band
		_tick_left = 0.0
	if band < 2:
		return
	# 임박 틱은 **링의 고속 점멸과 동기**다(D11 SE-T03 정의). 주기를 따로 두지 않고
	# 링이 실제로 쓰는 점멸 주파수를 받아 쓴다 — 두 축이 어긋날 여지를 없앤다.
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	var hz: float = _e04_timer_ring.imminent_blink_hz()
	_tick_left = 1.0 / hz if hz > 0.0 else 1.0
	sfx("timer_imminent_tick")


func _update_timer_value() -> void:
	# 수치 표시는 O6 옵션 (기본 켬 — 2026-09-01 개선·소수 서식은 스트링 키, IMPL-027 전례).
	# `_timer_active` 를 함께 본다 — 창이 닫힌 국면(프리스핀·정산)에 직전 잔량이 굳은 채
	# 남아 있었다(기본 끔이던 시절에는 아무도 못 본 잠복 결함 — 기본 켬 전환이 드러냈다).
	_e04_timer_value.visible = (
		session.options.index_of("o6") == 1 and not _timer_disabled and _timer_active
	)
	var seconds := snappedf(_timer_remaining, 0.1)
	var timer_text := data.strings.text("ui.race.timerFormat", {"value": seconds})
	_e04_timer_value.text = timer_text


# ── 연출 등급 채널 실행 (§3.4 몫 — D09 §3.6 · D12 §5.8) ──
# 등급 판정·상한·우선순위는 코어(PresentationGrade)가 갖고, 여기서는 **확정된 등급의
# 표현 채널만** 실행한다. 접근성 옵션(O1~O3)은 출력 단계 마스킹이며 판정에 관여하지 않는다.
#
# 트리거 후보는 확정 후(T5) 이벤트에서만 뽑는다 — 릴 정지 연출 전에 발화하면
# 그 자체가 결과 상관 신호다 (봉인 — 불변규칙 5).
const TRIGGER_BY_KEY := {
	"raceLog.duelWin01": "trigger_duel_decision",
	"raceLog.duelLoseOvertake01": "trigger_duel_decision",
	"raceLog.duelLoseDefense01": "trigger_duel_decision",
	"raceLog.chanceDuel01": "trigger_chance_three_match",
}

var _scene_panel: ScenePanel
# 완급 비트 대기 — T6→차기 T1 전이에 삽입한다(D09 §3.1.1 · 표현 층 전속·상태 머신 무개정).
var _pacing_beat_left := 0.0
var _pacing_beat_timer: SceneTreeTimer

var _shake_left := 0.0
var _shake_strength := 0.0
# 릴을 움직인 행동의 튜토리얼 통지 대기분 — 정지 연출이 끝날 때까지 들고 있는다(봉인).
var _tutorial_pending := ""


# 결판 직후의 상대 — `_resolve_duel` 이 `duel_opponent` 를 비우므로 정산 **전에** 떠 둔다.
var _last_duel_opponent := ""


func _collect_triggers(events: Array) -> Array:
	var triggers: Array = []
	for event in events:
		var key := String(event.get("key", ""))
		if TRIGGER_BY_KEY.has(key):
			var trigger := String(TRIGGER_BY_KEY[key])
			if not triggers.has(trigger):
				triggers.append(trigger)
			# 벽 라이벌 격파 = 듀얼 승리 + 상대가 무대 벽 라이벌 (D08 §8.5 — 무대 1은 부재라
			# 자연 미발동. 매핑만 결선해 두면 무대 2+ 데이터 유입 시 그대로 붙는다)
			if key == "raceLog.duelWin01":
				var wall := String(data.stage_of_active_circuit().get("wall_rival", ""))
				if not wall.is_empty() and engine.duel_opponent == wall:
					triggers.append("trigger_wall_rival_beat")
	return triggers


# ── 기원 단서 3 — 결판 직후 라이벌 발화 1줄 (사용자 판정 2026-08-24) ──
#
# **VN 이 아니다.** 운반체가 로그 존 한 줄이고 신설 UI 가 없다(D08 §8.6 — 마일스톤 슬롯 밖).
# 그래서 아카이브에도 넣지 않는다: `vn_seen` 을 쓰면 VN 이 아닌 것이 VN 목록에 선다.
# 1회성 보장은 **발견 대장**(`discoveries`)이 진다 — 세이브에 직렬화되고 되돌아가지 않는
# 플래그라 재개·재대결 어느 경로에서도 두 번 흘리지 않는다.
#
# 변형 택1 = **결판 상대**가 고른다(로렌츠 / 마로). 상대가 곧 화자이므로 문면과 화자가
# 한 데이터에서 나오고, 조립할 것이 없다.
const CLUE_AXION_BY_RIVAL := {
	"ai_lorentz": {"text": "vn.clueAxion.lorentz01", "speaker": "ui.vn.speakerLorentz"},
	"ai_maro": {"text": "vn.clueAxion.maro01", "speaker": "ui.vn.speakerMaro"},
}
const CLUE_AXION_DISCOVERY := "clue_axion_hint"


func _emit_clue_axion(opponent_id: String) -> void:
	if not CLUE_AXION_BY_RIVAL.has(opponent_id):
		return
	if session.outgame.discoveries.has(CLUE_AXION_DISCOVERY):
		return   # 1회성 — 단서는 두 번 흘리지 않는다
	session.outgame.record_discovery(CLUE_AXION_DISCOVERY)
	var line: Dictionary = CLUE_AXION_BY_RIVAL[opponent_id]
	var s := data.strings
	_e10_log.push_line(s.text(String(line["speaker"])), s.text(String(line["text"])))


# L3 조우 판정 (D10 §7 결정 #6 — CG-01~03은 D08 §8.11 발견형 히든 업적과 1:1).
# 세 행이 같은 문형(**[상대] ([조건] 듀얼)**)이라 판정도 같은 구조다: 조건 성립 + 그 상대와의 듀얼.
# **CG-02(재회 — 카이) 결선분** — T7 서사 유입으로 `relation_reunion` 축이 서면서
# 닫혔다(총괄 판정 IMPL-249 Q1: '대면' = 관계 단계 1 · D04 §4.2 4단계 "회피→대면→응어리→
# 화해/결착" 의 양단 고정 + `achievements.csv` threshold=3 실독으로 도출).
#
# 조건 판정은 화면 상태를 타지 않는 순수 함수로 둔다 — 화면을 세우지 않고 검사할 수 있어야
# 조건이 조용히 어긋나는 일을 막는다(무대 5·시즌 중반은 실기로 밟기 어려운 경로다).
static func l3_encounter_for(stage: Dictionary, final_stage_id: String, opponent: String,
		duel_decided: bool) -> String:
	if not duel_decided:
		return ""
	if final_stage_id.is_empty() or String(stage.get("id", "")) != final_stage_id:
		return ""
	var wall := String(stage.get("wall_rival", ""))
	if wall.is_empty() or opponent != wall:
		return ""
	return "cg_01_throne"


# CG-03(동기 — 주드): **역전 성립 후 최초의 주드 인접 듀얼** (총괄 판정 IMPL-128 B-2).
# 역전 자체는 GP 결과로 확정되므로 래치는 세션이 GP 종료에서 세운다 — 여기서는 그 결과만 읽는다.
# 인접 임계는 D13 별첨A §6.5 확정값의 데이터 전사(`param_jude_adjacent_max`)를 받는다.
static func l3_kinship_for(opponent: String, overtaken: bool, rank_delta: int,
		adjacent_max: int) -> String:
	if not overtaken or opponent != JUDE_ID or rank_delta > adjacent_max:
		return ""
	return "cg_03_kinship"


# CG-02(재회 — 카이): **'대면' 도달 후의 카이 듀얼 결판**.
# 세 CG 가 같은 문형(**[상대] ([조건] 듀얼)**)이라 판정도 같은 구조다 — 조건 성립 + 그 상대.
# 여기서 조건은 관계 단계이며, 단계는 **투어 경계에서 공표된 값**을 읽는다(D07 §5.5) —
# 주행 중 카운터가 올라도 그 GP 안에서 조건이 켜지지 않는다. 그것이 스냅의 취지다.
static func l3_reunion_for(opponent: String, reunion_stage: int, duel_decided: bool) -> String:
	if not duel_decided or opponent != KAI_ID or reunion_stage < REUNION_MEETING_STAGE:
		return ""
	return "cg_02_reunion"


func _l3_encounter_id(events: Array) -> String:
	var decided := false
	for event in events:
		if String(TRIGGER_BY_KEY.get(String(event.get("key", "")), "")) == "trigger_duel_decision":
			decided = true
			break
	if not decided:
		return ""
	var throne := l3_encounter_for(
		data.stage_of_active_circuit(),
		String(data.season_calendar.get("fixed_final_stage", "")),
		engine.duel_opponent,
		true)
	if not throne.is_empty():
		return throne
	var kinship := l3_kinship_for(
		engine.duel_opponent,
		session.outgame.jude_overtaken,
		session.jude_rank_delta(),
		int(data.param("param_jude_adjacent_max")))
	if not kinship.is_empty():
		return kinship
	return l3_reunion_for(
		engine.duel_opponent,
		session.outgame.relation_stage("relation_reunion"),
		true)


func _run_presentation(events: Array) -> void:
	var triggers := _collect_triggers(events)
	# 조우 기록은 연출(CG)과 별개 채널이다 — 조우 자체는 CG 와 무관하게 성립하므로
	# 정보·기록 축을 먼저 닫는다. 업적 판정은 GP·투어·시즌 경계의 evaluate_achievements() 몫.
	var encounter := _l3_encounter_id(events)
	if not encounter.is_empty():
		session.outgame.record_discovery(encounter)
		if not triggers.has("trigger_signature_event"):
			triggers.append("trigger_signature_event")
	if triggers.is_empty():
		return
	# 한 턴의 후보를 배치로 넘긴다 — 개별 호출은 우선순위 역전을 만든다 (IMPL-034)
	for resolved in session.presentation.resolve(triggers):
		var channels: Dictionary = session.presentation.channels(String(resolved["grade"]))
		_fire_channels(channels)
		apply_illustration_channel(channels, encounter)


func _fire_channels(channels: Dictionary) -> void:
	if channels.is_empty():
		return
	var code := String(channels.get("code", "L0"))
	# 로그 채널은 이벤트 자체가 이미 발화했다 (전 등급 공통).
	# **등급 스팅 (SE-L1~L3)** — 등급 판정은 코어가 끝냈고 여기서는 확정된 등급을 이벤트 id 로
	# 옮길 뿐이다. L2·L3 의 BGM 덕킹은 디스패처가 표를 보고 건다(호출부가 알 필요 없다).
	# L0 은 채널 자체가 없다 — 표에도 행이 없으므로 디스패처가 빈 배열을 돌려준다.
	sfx("grade_%s" % code.to_lower())
	if code == "L1":
		_pulse_gauge()
		_start_shake(data.param("param_fx_shake_weak_px"))
	elif code == "L2" or code == "L3":
		_start_shake(data.param("param_fx_shake_strong_px"))
		if bool(channels.get("flash_slow", false)):
			_fire_flash()
	# L3 전용 일러스트 컷인은 **여기서 뜨지 않는다** — 등급만으로는 어느 장인지 모른다.
	# 발화는 `_run_presentation()` 이 조우 id 와 함께 건다(바로 위 호출부 주석).


# 완급 비트 — T6→차기 T1 전이 (D09 §3.1.1 · D13 별첨A §8.1 2.5초 · 40%).
#
# **표현 층 전속이다**(D05 §3 상태 머신 무개정) — 엔진은 비트가 있었는지 모른다. 삽입되는
# 것은 기본 주행 컷 한 비트이고, 확정 입력이 오면 그 자리에서 통과한다.
# 예산 = 턴당 평균 +1.0초(2.5 × 0.40)로 D09 의 턴당 +2초 이내를 지킨다.
func _play_pacing_beat() -> void:
	if _scene_panel == null or engine == null or engine.finished:
		return
	if not session.pacing_beat_due():
		return
	# **프레임 루프가 아니라 트리 타이머다.** 직접 세는 형태(`await process_frame` +
	# `get_process_delta_time()`)를 먼저 썼다가 SEAL-E 가 180초 예산을 터뜨렸다 —
	# 코루틴이 재개되지 못하는 프레임이 생기면 턴이 영영 넘어가지 않는다. 대기는
	# 듀얼 결과 표기(`param_fx_duel_result_hold_sec`)가 이미 쓰는 경로와 같은 것을 쓴다.
	_pacing_beat_timer = get_tree().create_timer(data.param("param_pacing_beat_max_sec"))
	_pacing_beat_left = data.param("param_pacing_beat_max_sec")
	_show_reel_phase_cut()
	await _pacing_beat_timer.timeout
	_pacing_beat_timer = null
	_pacing_beat_left = 0.0


# ── E15 레이스 씬 패널 (D09 §3.1.1 · 별첨A §127) ──
#
# **국면이 컷을 고르는 방식이 두 갈래다.**
#   · 릴 국면(T1~T4) = 기본 주행 고정 — **매핑을 부르지 않는다.** 결과를 보는 경로가 없는
#     것이 봉인의 구조적 형태다(불변규칙 5). 부르고 나서 버리는 형태로 두면 그 사이에
#     결과 상관 값이 화면 층에 존재하게 된다.
#   · 전개 국면(T5) = 확정 이벤트로 매핑 평가 — 로그와 **병행**이라 추가 대기가 0이다.
#
# **저강조(감광) = 0.70** (D13 별첨A §8.1 v1.12 · 결정 #21 — 34차 종결). 29차에 값이 없어
# 비워 둔 자리이며 그때 `param_fx_reduced_mult` 를 빌리지 않은 판단을 정본이 확인했다
# (신설 행에 *"접근성 감쇠 축과 별개 축"* 명기). **기다린 자리가 정본으로 닫혔다.**
func _setup_scene_panel() -> void:
	var host := %E15ScenePanel as Control
	_scene_panel = ScenePanel.new()
	_scene_panel.name = SCENE_PANEL_NAME
	_scene_panel.setup(data)
	host.add_child(_scene_panel)
	# O12 '씬 패널 모션: 표준 / 정지 컷' — 접근성 폴백 (D09 §6.1)
	_scene_panel.set_motion_enabled(session.options.index_of("o12") == 0)
	# **여기서 첫 컷을 세우지 않는다.** `_boot()` 는 `_start_gp()` **전에** 돌아 엔진이 아직
	# 없으므로, 세우려는 호출은 조기 반환으로 아무 일도 하지 않는다 — 29차 반증(N7)이
	# 그 무동작을 드러냈다. 죽은 한 줄을 남겨 두면 다음 사람이 그것을 결선의 증거로 읽는다
	# (주력 14차가 이름 붙인 형태 — **"직접 호출은 결선의 증거가 아니다"**).
	# 첫 컷은 `_start_gp() → _next_turn()` 이 세운다.


# 릴 국면 고정 컷. 모션도 멈춘다 — 개입 판단을 방해하지 않는 것이 이 국면의 요건이다
# (D09 §3.1.1 "10초 성립 원칙 보호").
func _show_reel_phase_cut() -> void:
	if _scene_panel == null or engine == null:
		return
	_scene_panel.set_motion_enabled(false)
	_scene_panel.set_dim(true)     # 릴 국면 저강조 — 개입 판단 방해 차단 (D09 §3.1.1)
	_scene_panel.show_cut(session.scene_cuts.reel_phase_cut(_field_size()),
		_active_stage_id(), _scene_occupants())


# 전개 국면 컷 — **확정 이벤트에서만** 부른다(호출부 = `_on_confirm` 의 정산 뒤).
func _show_result_cut(events: Array, duel_turn: bool, gp_finished: bool) -> void:
	if _scene_panel == null or engine == null:
		return
	var log_keys: Array = []
	for event in events:
		log_keys.append(String(event.get("key", "")))
	var cut_id := session.scene_cuts.resolve({
		"log_keys": log_keys,
		"duel_turn": duel_turn,
		"front_gauge": engine.front_gauge,
		"rear_gauge": engine.rear_gauge,
		"gp_finished": gp_finished,
		"field_size": _field_size(),
	})
	if cut_id.is_empty():
		return   # 폴백 행이 사라진 경우 — 검사가 잡는다(코드가 기본값을 들지 않는다)
	_scene_panel.show_cut(cut_id, _active_stage_id(), _scene_occupants())
	_scene_panel.set_motion_enabled(session.options.index_of("o12") == 0)
	_scene_panel.set_dim(false)    # 전개 국면 — 감광 해제


# 씬 패널 점유자 배정 — **화면이 안다, 패널이 아니라.**
#
#   · `rival` — **플레이어 앞뒤 인접 상대를 앞에서부터.** 패널이 비추는 것은 플레이어
#     주변이므로 인접이 자연스러운 읽기다(`_field_size()` 의 단독/그룹 판정과 같은 근거).
#     정본은 *어느 상대가 그 자리인가*를 정하지 않으므로 이 배정은 [가안]이었고,
#     **폐문 조건(실물 플레이 검증 눈 판정 — 옆에 달리는 차로 읽히는가)이 충족됐다:**
#     2026-08-28 사용자 실물 검증 전항 적합 — 교정 없음 (총괄 판정 IMPL-481 ②).
#     [가안] 해제분이며 정본 배정이 아니다 — 정본이 자리를 규정하면 그때 이 함수가 답한다.
#   · `grid`  — 순위표 순서 그대로(자리 이름의 `p<n>` 이 순위다 — 도구 명문).
func _scene_occupants() -> Dictionary:
	if engine == null:
		return {}
	var order: Array = engine.positions
	var index := order.find(RaceEngine.PLAYER_ID)
	var neighbours: Array = []
	if index >= 0:
		if index > 0:
			neighbours.append(String(order[index - 1]))
		if index < order.size() - 1:
			neighbours.append(String(order[index + 1]))
	var grid: Array = []
	for entrant in order:
		if String(entrant) != RaceEngine.PLAYER_ID:
			grid.append(String(entrant))
	return {"rival": neighbours, "grid": grid}


func _active_stage_id() -> String:
	return String(data.stage_of_active_circuit().get("id", ""))


# **[가안] 단독 / 그룹 = 자신 + 앞뒤 인접.** 정본(D09 §3.1.1·D10 §6.2)은 두 컷의 존재만
# 정하고 *무엇이 그룹인가*를 정하지 않는다. 패널이 비추는 것은 플레이어 주변이므로
# 앞뒤 인접 순위를 세는 것을 초안으로 둔다 — 전 참가자 수로 세면 초반에 늘 그룹이라
# 단독 컷이 **영원히 서지 않는다**(죽은 컷 — 주력 14차가 이름 붙인 형태다).
# **폐문 조건:** 실물 플레이 검증 회차의 눈 판정 — 단독/그룹 전환이 실기에서 옳게 읽히는가.
func _field_size() -> int:
	var index := engine.positions.find(RaceEngine.PLAYER_ID)
	if index < 0:
		return 1
	var neighbours := 0
	if index > 0:
		neighbours += 1
	if index < engine.positions.size() - 1:
		neighbours += 1
	return 1 + neighbours


# ── L3 전용 일러스트 채널 (D09 §3.6 · D10 §7 · D11 §6.5) ──
#
# **상대 식별은 채널 밖이다** (에셋 결선 경고 — 유입 계약 IMPL-418).
# `illustration` 플래그는 *일러스트를 띄우는가*만 말하고 *어느 장인가*는 말하지 않는다.
# 등급이 띄우라고 했을 때 무엇을 띄울지는 **이 턴의 조우**가 정한다 — 그래서 두 사실이
# 함께 서야 컷인이 뜬다: 플래그(등급 판정 결과) ∧ 조우 id(상대 판정 결과).
#
# **강등된 등급으로는 뜨지 않는다** — `resolve()` 가 상한 초과분을 L1 로 내리면
# `channels.illustration` 이 false 다. GP당 1회 상한(D08 §8.5)이 컷인에도 그대로 걸린다.
#
# **지속은 인자로 받는다** — 여기서 2.5 를 적으면 확정 기준값이 코드로 새고(불변규칙 2),
# 무엇보다 검사가 "표에서 왔다"와 "손으로 적었다"를 구분하지 못한다.
#
# `static` 이 아니라 공개 메서드인 것은 씬(부모)이 있어야 자식을 붙일 수 있기 때문이다.
func apply_illustration_channel(channels: Dictionary, encounter_id: String) -> void:
	if not bool(channels.get("illustration", false)):
		return
	if encounter_id.is_empty():
		return
	_show_cg_cutin(encounter_id, float(channels.get("sting_length_sec", 0.0)))


# 조우 CG 컷인 — 발견 id 로 대장을 조회한다. **여기서 다시 짖지 않는다**: 대장 대조는 CG
# 스위트가 양방향으로 지므로(6행 ↔ 6파일 ↔ 조우 3종) 미등재는 그쪽에서 이미 실패한다.
func _show_cg_cutin(discovery_id: String, hold_sec: float) -> void:
	var row := data.cg_cutin_for_discovery(discovery_id)
	if row.is_empty():
		return
	var cutin := CgCutIn.new(String(row["asset"]), hold_sec)
	cutin.name = CG_CUTIN_NAME
	add_child(cutin)


# 게이지 섬광 (L1 — D09 §3.6). 플래시(O2)와 별개 채널이라 감쇠 대상이 아니다 —
# 게이지 자체가 정보 표시이므로 정보 보존 축에 속한다.
func _pulse_gauge() -> void:
	var duration := data.param("param_fx_gauge_pulse_sec")
	var tween := create_tween()
	tween.tween_property(_e03_front, "modulate", Color(1.6, 1.6, 1.6), duration * 0.3)
	tween.tween_property(_e03_front, "modulate", Color.WHITE, duration * 0.7)


# 셰이크 — O1 감쇠 (표준 1.0 / 감소 0.5 / 끔 0 — 출력 마스킹, D09 §6.3)
func _start_shake(base_px: float) -> void:
	var mask := _fx_mask("o1")
	if mask <= 0.0:
		return
	_shake_strength = base_px * mask
	_shake_left = data.param("param_fx_shake_sec")


# 플래시 — O2 감쇠 (광과민 대응). 끔이어도 로그·게이지의 정보 채널은 남는다 (정보 보존 의무)
func _fire_flash() -> void:
	var mask := _fx_mask("o2")
	if mask <= 0.0:
		return
	var flash := %FxFlash as ColorRect
	flash.color.a = data.param("param_fx_flash_alpha") * mask
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, data.param("param_fx_flash_sec"))


func _fx_mask(option_id: String) -> float:
	match session.options.index_of(option_id):
		1:
			return data.param("param_fx_reduced_mult")
		2:
			return 0.0
	return 1.0


func _process_shake(delta: float) -> void:
	var root_box := get_node("Root") as Control
	if _shake_left <= 0.0:
		if root_box.position != Vector2.ZERO:
			root_box.position = Vector2.ZERO
		return
	_shake_left -= delta
	# 결정적 흔들림 — 난수를 쓰지 않는다 (RNG 스트림은 게임 로직 전속 — D12 §6)
	var phase := _shake_left * 60.0
	root_box.position = Vector2(sin(phase * 1.7), cos(phase * 2.3)) * _shake_strength


# ── 사운드 보조 (D11 §1.3 봉인 정합 · §2.1 릴 계열) ──
func _seal(open: bool) -> void:
	if session == null or session.audio == null:
		return
	if open:
		session.audio.open_seal()
	else:
		session.audio.close_seal()


# SE-R04/R05 매치 고지음 — 매치 **사실**의 고지이며 등급 스팅(§2.5)과 별개다.
# 봉인을 닫은 직후에만 부른다 (규칙 R-a "정지 완료 후 전속").
func _announce_matches(provisional: Array) -> void:
	var counts: Dictionary = {}
	var best := 0
	for symbol in provisional:
		var symbol_id := String(symbol)
		counts[symbol_id] = int(counts.get(symbol_id, 0)) + 1
		best = maxi(best, int(counts[symbol_id]))
	if best >= REEL_COUNT:
		sfx("reel_match_three")
	elif best >= 2:
		sfx("reel_match_two")


# ── 이벤트 → 표시 경로 분기 (D09 §3.1 국면 분리) ──
# ── 로그 문구 변형 대장 (개선 2026-09-01) ──
#
# 같은 사건 키가 매 섹터 같은 문면으로 반복돼 중계가 단조로웠다(타임아웃·트러블·안정이
# 한 GP 에 수 회씩 선다). 변형은 **표시 층 전속**이다: 소리(SOUND_BY_KEY)·연출(TRIGGER_BY_KEY)·
# 듀얼 프레임(DUEL_RESULT_KEYS)은 전부 원 키로 대조하므로 기계 거동이 갈리지 않는다.
# **열거형 대장이다** — 접미 조립(`%02d`)로 탐침하면 V6 가 변형 키를 고아로 읽고 V2 의
# 실재 검사도 비켜 간다. 여기 적힌 리터럴은 두 검사가 전부 물어 준다(등재 = 실재 보증).
# 변형 문면은 원 키와 **같은 매개 집합**을 써야 한다 — params 가 그대로 넘어간다.
const LOG_VARIANT_KEYS := {
	"raceLog.timeout01": ["raceLog.timeout02", "raceLog.timeout03"],
	"raceLog.troubleHit01": ["raceLog.troubleHit02", "raceLog.troubleHit03"],
	"raceLog.stableSector01": ["raceLog.stableSector02", "raceLog.stableSector03"],
	"raceLog.momentum01": ["raceLog.momentum02"],
}


# 선택은 **결정적**이다 — 턴·섹터·랩에서 유도하므로 같은 진행을 다시 밟으면 같은 문면이
# 나오고(재로드 리롤 무효와 같은 방향), RNG 6스트림(D12 §6 — 게임 로직 전속)을 소비하지 않는다.
func _log_display_key(key: String) -> String:
	if not LOG_VARIANT_KEYS.has(key):
		return key
	var variants: Array = [key]
	variants.append_array(LOG_VARIANT_KEYS[key])
	var basis := 0
	if engine != null:
		basis = engine.turn_number * 7 + engine.sector * 3 + engine.lap
	return String(variants[posmod(basis + key.hash(), variants.size())])


func _push_events(events: Array) -> void:
	for event in events:
		var key := String(event.get("key", ""))
		# **사운드는 표시와 같은 깔때기를 탄다** — 엔진이 말한 사건 하나에 로그 한 줄과
		# 소리 하나가 같은 지점에서 나온다. 발화 지점을 따로 두면 둘이 어긋난다.
		if SOUND_BY_KEY.has(key):
			# 리타이어만 순서가 규칙이다: **BGM 즉시 정지 → JG-03** (D11 §4.3 전이 규칙표).
			# 정지를 뒤에 두면 징글이 무대 트랙 위에 겹친다.
			if key == "raceLog.playerRetire01" and session != null and session.audio != null:
				session.audio.stop_bgm()
			sfx(String(SOUND_BY_KEY[key]))
		if key.begins_with("vane."):
			# SE-V01a/b/c — 음색이 베인 인격 3단계에 연동된다(D11 §2.10). 단계는
			# 아웃게임 층이 갖는 값이라 여기서 파생만 한다.
			sfx("vane_cue_stage%d" % session.outgame.vane_stage())
		var params: Dictionary = event.get("params", {}).duplicate()
		for param_name in params:
			var value: Variant = params[param_name]
			if typeof(value) == TYPE_STRING and data.strings.has_key(String(value)):
				# 참조 키의 문면에 매개(필러의 {number} 등)가 있으면 같은 params 로 치환한다
				params[param_name] = data.strings.text(String(value), params)
		var body := data.strings.text(_log_display_key(key), params)
		if key.begins_with("vane."):
			_e07_text.text = body  # 릴 존 콜아웃 전속 — 로그 피드로 흘리지 않는다
		else:
			# 화자 축이 이벤트에 아직 없다 — 발행 층(코어)이 화자를 구분하지 않으므로
			# 전량 중계로 표기한다. [가안] 화자 구분(D09 §3.3 4종)은 이벤트 스키마에
			# 화자 필드가 생긴 뒤 결선한다. — IMPL-071
			#
			# 도상 축은 결선했다 (IMPL-207) — 중계 = 마이크 아이콘(D09 §3.3 공용 1종).
			# 텍스트 표지는 도상 부재·적재 실패 시의 되돌림 경로로 함께 넘긴다.
			# **`speaker_filler` 는 여기서 뜨지 않는다** — 필러 드라이버 발화를 코어가
			# 발행하지 않으므로 결속할 호출 지점이 없다(회신 §2-② 보고분).
			_e10_log.push_line(
				data.strings.text("ui.race.speakerRelay"), body, LogFeed.Speaker.RELAY
			)
	_refresh_strip()
	_refresh_resources()
