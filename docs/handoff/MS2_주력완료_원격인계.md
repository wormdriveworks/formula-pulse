# MS-2 인계 — 원격 헤드리스 레인 몫 (주력 GUI 머신 레인 종료 시점)

> 작성: 2026-08-15 · 주력 GUI 머신 레인
> 근거: `prompts/MS2_주력머신_kickoff.md` §6(머신 분담) · CLAUDE.md(씬 소유권·CLI 규칙)
> 대칭 문서: `MS2_주력머신_인계.md`(원격→주력, 2026-08-11) — 본 문서는 그 역방향이다.

---

## 0. 시작 절차 (매번)

```bash
git pull
godot --headless --import          # pull 후 1회 — 신규 에셋(아이콘 16종·폰트 5종)·씬 재임포트
bash tools/validators/validate.sh   # 기대: VALIDATORS_PASS warnings=0
bash tools/validators/run_tests.sh  # 기대: COMPILE_GATE_PASS scripts=76 · TESTS_PASS suites=10
git config core.hooksPath tools/hooks   # 1회 — 커밋 차단 훅 (아래 §1-훅)
```

- 스위트가 **10종**이 됐다 — `tests/test_seal_ui.gd`(SEAL-E, 하한 84) 신설분 포함.
- 두 명령은 **종료코드로** 판정한다. 파이프를 걸면 종료코드가 가려진다.

---

## 1. 주력 레인이 세운 것 (덮어쓰지 말고 확장)

| 영역 | 위치 | 상태 |
|---|---|---|
| D09 실화면 **23종** (사용자 확정 범위 — SYS-04·TUT-01 제외) | `godot/ui/` (race/ sys/ run/ hub/ nar/ settle/ com/ flow/) | 전량 성립 · 관통 19컷 실측 |
| 플로우 층 | `ui/flow/app_root.gd`(라우터) · `run_session.gd`(세션) · `flow_screen.gd`(화면 계약) | **전이 폐쇄성**: 화면은 `go()` 요청만, 경로 표에 없는 대상은 라우터가 거부 |
| 옵션 층 | `ui/flow/options_store.gd` + `ui/sys/options_screen.gd` | O1~O15+O12 값 체계·기기별 저장(`user://options.json` — 프로필 밖) · O4/O5/O6 실효 결선 |
| 듀얼 오버레이 (RACE-02) | `ui/race/duel_overlay.gd` — RACE-01 내부, 라우터 비경유 | 릴 표시 배열 스왑 방식 — 봉인·SEAL-E가 같은 경로를 본다 |
| 일시정지 (SYS-05) | `ui/race/pause_overlay.gd` | 개입 창 중 전면 가림막 + 타이머 정지 + 3-2-1 카운트인 (F2 보호) |
| 연출 채널 | `race_screen.gd` `_run_presentation` 계열 | L1 섬광+약셰이크 / L2·L3 강셰이크+플래시 · O1/O2 출력 마스킹 · 트리거는 확정 후 이벤트 전속 |
| 아트 플레이스홀더 | `assets/ui/icons/` 16종 (생성기 `tests/gen_placeholder_icons.gd`) | D10 도상 어휘·32px 셀·이중 부호화 준수 — 실물 유입 시 같은 경로·파일명 교체 |
| 폰트 | `assets/fonts/` Galmuri 5종 (본문 Galmuri9 9px · 대형 Galmuri14 14px) | 실측: 전각 22자 198px ⊂ 로그 슬롯 226px (D10 검증 ① 성립) |
| **SEAL-E 검사** | `tests/test_seal_ui.gd` (run_tests.sh 등재) | 실화면 인스턴스화 — 릴 조기 공개·UI 표면 변경·부분 공개 누출 3축. 돌연변이 실측 완료 |
| **커밋 차단 훅** | `tools/hooks/pre-commit` | `project.godot`의 도구 플러그인 등록(autoload·editor_plugins·등록 줄·addons 참조) 차단 |
| 캡처 하네스 | `tests/capture_screen.gd` · `capture_race_flow.gd` · `capture_flow_walk.gd` · `capture_hub_shots.gd` | **비헤드리스 전용** (뷰포트 렌더 필요) — 원격에서 실행 금지. 참고용 |
| export preset | `godot/export_presets.cfg` (Windows·Android 골격) | 자격증명 분리 A안 **종단 실측 확정** (IMPL-088) — 카나리 검증 완료 |

- **결정·[가안]·보고 전량은 `docs/decisions/impl_log.md` IMPL-070~089.**
  특히 070(GDAI 격리)·073(SEAL-E)·077(23종 범위)·081(게이트 최후순위)·084(듀얼 오버레이 구조)를 먼저 읽어라.
- **총괄 발신 대기 통합 = `docs/handoff/MS2_총괄발신문.md`** — 발신 지연은 작업을 막지 않는다.
- **autoload는 여전히 0개다.** GDAI 플러그인이 에디터 실행마다 등록을 되살리지만(이번 레인에서 4회 실측)
  훅이 커밋을 차단한다. 원격에서 pull 후 `project.godot`에 `[autoload]`가 보이면 그 커밋은 훅 미설치
  상태에서 나온 것이니 보고하라.

## 2. 원격 레인 주의 — 새로 생긴 규율

1. **씬 소유권 불변** — `godot/ui/**/*.tscn`은 주력 머신 전속. 원격은 `.gd`·데이터만.
   씬 생성이 필요하면 주력 레인의 방식(엔진 `pack()`+`ResourceSaver.save()` 빌더)을 따르되 주력에 넘겨라.
2. **화면 계약** — 화면은 `FlowScreen` 상속·`_on_bound(payload)` 초기화·`go(route)` 요청.
   **세션 주입은 `add_child` 이전** — `_ready()`가 `bind()`보다 먼저 돌아 화면이 자체 세션을 연다(실측 결함 — IMPL-077).
3. **V4 표시 싱크 규율** — `.text` 계열에 닿는 식은 **미리 만든 지역 변수로만** 대입한다.
   `label.text = s.text(key, {"k": v})` 같은 인라인 식은 V4가 딕셔너리 키·서식 지정자를 오탐한다.
   지역 변수 경유 시 비한글 리터럴이 추적되지 않는 선재 구멍은 **V4 확대 과제**(아래 §3-3).
4. **도상 경로 규약 [가안]** — 아이콘 파일명 = 테이블 id (`symbol_*`·`attr_*`). D10 §8.1 에셋 대장 도입 시 교체.
5. **표시 문자열은 씬에 굳히지 않는다** — 전량 런타임 키 주입. `.tscn`에 `text=`가 남으면 안 된다.

## 3. 원격이 이어받을 작업 (우선순위 순)

| # | 작업 | 근거 | 세부 |
|---|---|---|---|
| 1 | **TL-2 기능 체크리스트 기계 생성** | D14 §2.2 · 킥오프 §3.6 | 화면 23종 × 5축(진입/이탈 경로·표시 요소 전수·옵션 반영·T-1 완칭·금지 구역 0). 정본 목록 = D09 별첨A. 플로우맵 대조 기반은 `app_root.gd` ROUTES + 각 화면 `go()` 호출부 |
| 2 | **섀시 GP 간 이월 확인** | IMPL-078 | `RaceEngine.start_gp()`가 매 GP `param_chassis_max` 리셋 — D05 §8 대조로 설계 의도인지 MS-1 단순화 잔존인지 판정. 이월이 맞으면 필드 정비·전면 정비·소모품 실행 결선(화면 훅은 잠금 상태로 준비돼 있다 — `run_recap_screen.gd`·`repair_bay_screen.gd`) |
| 3 | **V4 지역 변수 추적 확대** | IMPL-074 | 표시 싱크에 대입되는 지역 변수의 값까지 추적 (상수는 IMPL-027이 이미 추적). 비한글 표시 문자열 한정 구멍 |
| 4 | **네임드 카 넘버 데이터 충전** | IMPL-084 · 발신문 §E | 총괄 회신(D03 값 확인) 후 `ai_rivals.csv`에 number 열 + 엔진 `_build_entrants` 결선. 화면(듀얼 대치·로그 배지)은 값만 오면 붙는다 |
| 5 | **픽스처 미적용 20표 소비부 검증 확대** | 검증 프로토콜 §5 (기존 이월) | 신규 소비부(옵션 파라미터·fx 파라미터·`field_repair_cost_next`)도 대상 |
| 6 | **세이브 직렬화 검증 확대** | IMPL-086 | `RunSession.serialize()`에 events·narrative 편입 — TC-P 왕복 검사에 두 층 추가 검토 |
| 7 | **무대 2~5 콘텐츠** | MS-3 | 캘린더 셔플 풀 충전 시 NAR-02 타임라인·wall_rival 트리거가 코드 무변경으로 붙는다 |

## 4. 주력 레인 잔여 (원격 소관 아님 — 참고)

아트 실물(도트 원도) · 사운드 실물(+햅틱 D13 전사 대기) · L3 컷인 · G-1·G-2·G-5(최후순위 — D15 시점 조정 발신 대기).

## 5. 커밋 규칙 (재확인)

- 커밋한다: `.gd` `.tscn` `.tres` `project.godot` `*.uid` 에셋과 `.import` `export_presets.cfg`
- 커밋 안 한다: `.godot/` `.mcp/` `.omc/` **`godot/addons/`**(신규 — IMPL-070)
- 커밋 전 `VALIDATORS_PASS warnings=0` + `TESTS_PASS suites=10`을 **종료코드로** 확인.
- 훅 설치(`git config core.hooksPath tools/hooks`)를 잊지 마라 — project.godot 오염 차단.
