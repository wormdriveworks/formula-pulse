# TL-2 기능 체크리스트 — 화면 23종 × 5축 (기계 생성)

> 생성기: `godot/tests/gen_tl2_checklist.gd` (재생성 = 같은 명령 — 수기 편집 금지)
> 생성 규칙 정본: D14 §2.2 · 화면 목록 정본: D09 별첨A v1.2 · 범위: IMPL-077 (25종 − SYS-04·TUT-01)
> 기계가 채운 것 = 실측 증거 / 체크박스 = 실행 단계에서 별첨A 명세와 눈 대조 (TL-2 실행 시)

## SYS-01 타이틀 화면 (§A-1)
- 구현: res://ui/sys/title_screen.gd
- [ ] ①진입/이탈 — 진입: 앱 기동(ENTRY_SCREEN)·SYS-02·RACE-01 / 이탈: SYS-03·SYS-02 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (8개 실측): TitleLabel(Label)·SubtitleLabel(Label)·ContinueButton(Button)·NewCareerButton(Button)·ArchiveButton(Button)·OptionsButton(Button)·QuitButton(Button)·VersionLabel(Label)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 8종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## SYS-02 세이브 슬롯 (§A-2)
- 구현: res://ui/sys/save_slot_screen.gd
- [ ] ①진입/이탈 — 진입: SYS-01 / 이탈: SYS-01·NAR-01·RACE-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (3개 실측): HeaderLabel(Label)·HintLabel(Label)·BackButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 8종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## SYS-03 옵션 화면 (§A-3)
- 구현: res://ui/sys/options_screen.gd
- [ ] ①진입/이탈 — 진입: SYS-01 / 이탈: (go 호출 없음 — 전이 주체 확인) (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (3개 실측): HeaderLabel(Label)·ResetButton(Button)·CloseButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 7종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## SYS-04 업적 화면 — **생성 제외** (MS-2 범위 외 — 업적 데이터 테이블 부재 (IMPL-077))

## SYS-05 일시정지 메뉴 (오버레이) (§A-5)
- 구현: res://ui/race/pause_overlay.gd
- [ ] ①진입/이탈 — 진입: RACE-01 일시정지 (ESC — 개입 창 중 전면 가림막) / 이탈: 재개(3-2-1 카운트인) / 옵션 오버레이 / 타이틀
- [ ] ②표시 요소 전수 (5개 실측): ResumeButton(Button)·OptionsButton(Button)·TitleButton(Button)·TitleWarning(Label)·CountLabel(Label)
- [ ] ③옵션 반영 — 소비 실측: param_pause_countin_sec
- [ ] ④T-1 완칭 — 사용 키 5종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## RACE-01 레이스 화면 (§A-6)
- 구현: res://ui/race/race_screen.gd
- [ ] ①진입/이탈 — 진입: SYS-02·RUN-01·HUB-01 / 이탈: SYS-01·RACE-03 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (30개 실측): E01Position(Label)·E02LapSector(Label)·E02SectorAttr(TextureRect)·E02Corner(Label)·E02Resonance(Label)·FrontLabel(Label)·E03FrontGauge(ProgressBar)·RearLabel(Label)·E03RearGauge(ProgressBar)·Symbol(TextureRect)·Symbol(TextureRect)·Symbol(TextureRect)·E07VaneText(Label)·E04TimerValue(Label)·E08Respin(Button)·Skill1(Button)·Skill2(Button)·Skill3(Button)·Skill4(Button)·Skill5(Button)·E08ChargeIntervene(Button)·E08Confirm(Button)·ChassisLabel(Label)·E11ChassisBar(ProgressBar)·E11ChassisValue(Label)·ChargeLabel(Label)·E12Charge(Label)·Label(Label)·Label(Label)·E14Menu(Button)
- [ ] ③옵션 반영 — 소비 실측: param_fx_duel_result_hold_sec·O4·param_opt_reel_fast_mult·O5·param_opt_timer_mult_1·param_opt_timer_mult_2·O6·param_fx_shake_weak_px·param_fx_shake_strong_px·param_fx_gauge_pulse_sec·param_fx_shake_sec·param_fx_flash_alpha·param_fx_flash_sec·param_fx_reduced_mult
- [ ] ④T-1 완칭 — 사용 키 28종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## RACE-02 듀얼 오버레이 (§A-7)
- 구현: res://ui/race/duel_overlay.gd
- [ ] ①진입/이탈 — 진입: RACE-01 듀얼 삽입 (D05 §3 상태 머신 1:1 — 라우터 비경유) / 이탈: 듀얼 결판 → RACE-01 복귀 (결과 프레임 내 표기 후 해제)
- [ ] ②표시 요소 전수 (9개 실측): PlayerLabel(Label)·KindLabel(Label)·OpponentLabel(Label)·DuelReel0(TextureRect)·DuelReel1(TextureRect)·DuelReel2(TextureRect)·BoostStack(Label)·BoostButton(Button)·ResultLabel(Label)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 7종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## RACE-03 그랑프리 결산 (§A-8)
- 구현: res://ui/race/gp_result_screen.gd
- [ ] ①진입/이탈 — 진입: RACE-01 / 이탈: SET-01·RUN-02·RUN-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (14개 실측): HeaderLabel(Label)·RetireBadge(Label)·SaveBadge(Label)·RankLabel(Label)·RankValue(Label)·PointsLabel(Label)·PointsValue(Label)·PrizeLabel(Label)·PrizeValue(Label)·BonusLabel(Label)·BonusValue(Label)·CarryLabel(Label)·CarryValue(Label)·NextButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 14종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## RUN-01 간이 정산 화면 (§A-9)
- 구현: res://ui/run/run_recap_screen.gd
- [ ] ①진입/이탈 — 진입: RACE-03·RUN-02 / 이탈: RACE-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (9개 실측): HeaderLabel(Label)·SummaryRank(Label)·CreditsValue(Label)·RepairButton(Button)·RepairCostValue(Label)·ChassisValue(Label)·ConsumableButton(Button)·DeckButton(Button)·NextButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 10종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## RUN-02 이벤트 노드 화면 (§A-10)
- 구현: res://ui/run/event_node_screen.gd
- [ ] ①진입/이탈 — 진입: RACE-03 / 이탈: RUN-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (6개 실측): TitleLabel(Label)·BodyLabel(Label)·RewardIcon(TextureRect)·RewardValue(Label)·RareBadge(Label)·ProceedButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 4종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-01 개러지 (허브) (§A-11)
- 구현: res://ui/hub/garage_screen.gd
- [ ] ①진입/이탈 — 진입: SET-01·HUB-02·HUB-03·HUB-04·HUB-05·HUB-06·HUB-07·HUB-08 / 이탈: RACE-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (16개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)·StRepair(Button)·StTuning(Button)·StStrategy(Button)·StRecords(Button)·StSponsor(Button)·StFacility(Button)·StOverhaul(Button)·StRecruit(Button)·DepartButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 14종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-02 정비 베이 (§A-12)
- 구현: res://ui/hub/repair_bay_screen.gd
- [ ] ①진입/이탈 — 진입: (역참조 없음 — 세션 전이 확인) / 이탈: HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (13개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)·CardLabel(Label)·CostLabel(Label)·TotalCostValue(Label)·ChassisValue(Label)·FreeLineNote(Label)·RunButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 8종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-03 튜닝 벤치 (§A-13)
- 구현: res://ui/hub/tuning_bench_screen.gd
- [ ] ①진입/이탈 — 진입: (역참조 없음 — 세션 전이 확인) / 이탈: HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (8개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)·RedistributeButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 8종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-04 전략실 (§A-14)
- 구현: res://ui/hub/strategy_screen.gd
- [ ] ①진입/이탈 — 진입: (역참조 없음 — 세션 전이 확인) / 이탈: HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (9개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)·DeckHeader(Label)·ExpandButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 13종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-05 기록실 (§A-15)
- 구현: res://ui/hub/records_screen.gd
- [ ] ①진입/이탈 — 진입: (역참조 없음 — 세션 전이 확인) / 이탈: NAR-01·HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (10개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)·TabRivals(Button)·TabCareer(Button)·TabArchive(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 11종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-06 스폰서 데스크 (§A-16)
- 구현: res://ui/hub/sponsor_desk_screen.gd
- [ ] ①진입/이탈 — 진입: (역참조 없음 — 세션 전이 확인) / 이탈: HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (8개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)·SlotLabel(Label)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 6종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-07 시설 확장 패널 (§A-17)
- 구현: res://ui/hub/facility_screen.gd
- [ ] ①진입/이탈 — 진입: (역참조 없음 — 세션 전이 확인) / 이탈: HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (7개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 6종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## HUB-08 시즌 오버홀 (§A-18)
- 구현: res://ui/hub/overhaul_screen.gd
- [ ] ①진입/이탈 — 진입: SET-02 / 이탈: HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (9개 실측): CreditIcon(TextureRect)·CreditValue(Label)·DataIcon(TextureRect)·DataValue(Label)·ProgressLabel(Label)·BackButton(Button)·HeaderLabel(Label)·GradeLabel(Label)·ConfirmButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 5종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## NAR-01 VN 이벤트 화면 (§A-19)
- 구현: res://ui/nar/vn_screen.gd
- [ ] ①진입/이탈 — 진입: SYS-02·HUB-05 / 이탈: (go 호출 없음 — 전이 주체 확인) (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (4개 실측): SkipButton(Button)·SpeakerLabel(Label)·BodyLabel(Label)·AdvanceButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 6종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## NAR-02 캘린더 공개 비트 (§A-20)
- 구현: res://ui/nar/vn_screen.gd
- [ ] ①진입/이탈 — 진입: NAR-01 내부 오버레이 (시즌 오프닝 캘린더 공개 — 신규 슬롯 불신설) / 이탈: 확인 → NAR-01 진행 재개
- [ ] ②표시 요소 전수 (1개 실측): CalendarTitle(Label)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 6종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## SET-01 투어 결산 리포트 (§A-21)
- 구현: res://ui/settle/tour_report_screen.gd
- [ ] ①진입/이탈 — 진입: RACE-03 / 이탈: SET-02·HUB-01 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (15개 실측): HeaderLabel(Label)·Block1Label(Label)·Block1Value(Label)·Block2Label(Label)·Block2Value(Label)·Block3Label(Label)·Block3Value(Label)·Block3Note(Label)·Block4Label(Label)·Block4Value(Label)·Block5Label(Label)·Block5Value(Label)·Block6Label(Label)·Block6Value(Label)·NextButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 14종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## SET-02 시즌 결산 화면 (§A-22)
- 구현: res://ui/settle/season_result_screen.gd
- [ ] ①진입/이탈 — 진입: SET-01 / 이탈: HUB-08 (실측 — 별첨A 플로우와 대조)
- [ ] ②표시 요소 전수 (5개 실측): HeaderLabel(Label)·VerdictLabel(Label)·EpilogueLabel(Label)·SummaryLabel(Label)·NextButton(Button)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 8종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## COM-01 공통 확인 다이얼로그 (§A-23)
- 구현: res://ui/com/confirm_dialog.gd
- [ ] ①진입/이탈 — 진입: 코드 생성 다이얼로그 — 유상·비가역 확정 전속 (호출 화면 위) / 이탈: 확정/취소 → 호출 화면 복귀 (초기 포커스 = 취소, §A-23)
- [ ] ②표시 요소 전수 — 코드 생성 노드 (스크립트에서 New 되는 Label·Button 확인)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 3종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## COM-02 툴팁 규격 (§A-24)
- 구현: project.godot 전역 설정
- [ ] ①진입/이탈 — 진입: 전역 툴팁 규격 (gui/timers/tooltip_delay_sec — project.godot) / 이탈: 포인터 이탈 시 소멸
- [ ] ②표시 요소 전수 — 전역 규격 (툴팁 지연·1회성 온보딩 기록)
- [ ] ③옵션 반영 — 소비 실측: (직접 소비 없음 — 공통 채널 경유 여부 확인)
- [ ] ④T-1 완칭 — 사용 키 0종 · '티어' 단독 표기 기계 검사 통과 (문면 눈 대조는 실행 시)
- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 통과)

## TUT-01 튜토리얼 오버레이 — **생성 제외** (MS-2 범위 외 — D04 텍스트 풀 트랙 의존 (IMPL-077))

