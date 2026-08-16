# CLAUDE.md — Formula Pulse: Spin the Grid (구현 리포지토리)

> AI 에이전트 운영 계약서. 이 프로젝트는 **두 종류의 머신에서 교대로 작업**된다.
> 무엇을 하기 전에 **STEP 0(환경 감지)을 반드시 먼저 실행**하고, 감지 결과에 맞는 규칙만 따른다.

## STEP 0 — 지금 어느 환경인가? (매 세션 시작 시 확인)

```bash
if [ "$OS" = "Windows_NT" ]; then echo "ENV=주력GUI(Windows)"
elif [ -n "${DISPLAY}${WAYLAND_DISPLAY}" ]; then echo "ENV=주력GUI(X11/Wayland)"
else echo "ENV=원격헤드리스"; fi
```

| 결과 | 환경 | 역할 |
|------|------|------|
| `ENV=주력GUI(...)` | **주력 GUI 머신** | 씬 구성·시각/런타임 검증 (눈이 필요한 일) |
| `ENV=원격헤드리스` | **원격 헤드리스 서버** | 로직·스크립트·검증 (눈이 필요 없는 일) |

> **⚠️ 판정식 주의 (2026-08-10 교정):** 구 판정식은 `DISPLAY`·`WAYLAND_DISPLAY`만 봤다. 이 둘은 X11/Wayland 전용이라 **Windows에서는 항상 비어 있고**, 주력 GUI 머신이 Windows인 본 프로젝트에서 주력 머신을 "원격 헤드리스"로 오판했다. 오판 시 에이전트가 GDAI·`run_project`·스크린샷을 스스로 금지해 눈이 필요한 작업이 전부 막힌다. **OS 판정을 먼저 둘 것.**

사용할 수 있는 MCP도 다르다: 원격=`godot`(godot-mcp-runtime, 편집·검증), 주력=`gdai`(GDAI, 에디터 매개 전체).

---

## 공통 불변 규칙 (양쪽 머신 모두)

- **Godot 버전은 4.7 계열 고정** (D12 v1.1 §1.1 확정 핀 — 정본 정합). 다르면 `.tscn`/기능 차이로 디프가 오염된다. 설치 실물 = 4.7.1-stable.
- **커밋한다**: `.gd`, `.tscn`, `.tres`, `project.godot`, **`*.uid`**(← uid:// 참조 안정성, 절대 빼먹지 말 것), 에셋과 `.import`.
- **커밋 안 한다**: `.godot/`(캐시), `.mcp/`, `.omc/`. (`.gitignore`에 포함)
- **작업 시작 전 `git pull`, 끝나면 커밋/푸시.** 두 머신이 같은 브랜치를 오간다 — 반드시 최신화 후 시작.
- **git-lfs 필수** (에셋 `*.png`·`*.ttf`·오디오 = LFS — `.gitattributes`). 미설치 머신에서는 에셋이 포인터 텍스트로 체크아웃되어 **헤드리스 테스트가 행이 되고 `--import`가 `.import`를 오염**시킨다(IMPL-091 실측). pull 후 에셋 파일이 수백 바이트면 `git lfs pull`부터.
- **씬(`.tscn`) 구조의 소유권은 주력 GUI 머신**에 둔다. 이유: 원격 MCP가 만든 `.tscn`은 비표준 최소 포맷이라 에디터가 열면 재정규화되어 디프가 튄다. 원격에서는 스크립트/로직 위주로, 씬 구성은 최소화.
- **autoload가 깨지면 원격의 헤드리스 작업 전체가 실패한다**(헤드리스 Godot은 모든 autoload를 초기화하므로). autoload 추가/수정 후에는 양쪽에서 `validate`로 반드시 확인.

---

## 원격 헤드리스 서버에서 (`ENV=원격헤드리스` — Linux 전제, `godot`이 PATH에 있음)

### 워크플로: 편집 → 검증 → 실행 → 자가수정
```bash
# pull 먼저
git pull

# (필요시) 캐시 재생성 — .godot 는 커밋 안 되므로 pull 후 한 번
godot --headless --import

# 로직 실행 (SceneTree 스크립트)
godot --headless --path . --script test/logic_test.gd

# 컴파일 검증 (통과=exit 0)
godot --headless --path . --check-only --script <파일.gd>
```

### 쓸 수 있는 MCP `godot` 도구 (편집·검증만)
`create_scene` · `add_node` · `set_node_properties` · `attach_script` · `get_scene_tree` ·
`duplicate_node` · `delete_nodes` · `connect_signal` · `*_autoload` · `validate` · 조회 도구 전부.
> mutation 도구는 **자동 저장**된다. `save_scene`은 save-as(newPath)일 때만.

### ❌ 원격에서 쓰지 마라 (디스플레이 필요 → 실패)
`run_project` · `take_screenshot` · `simulate_input` · `get_ui_elements` · `run_script` ·
`get_debug_output` · `stop_project` · `attach_project` · `launch_editor`
→ 로직 실행이 필요하면 위의 **Bash `--headless --script`**를 써라.

### 스크립트 형식 주의
- Bash `--script` 실행용: `extends SceneTree` + `func _init()` + `quit()`
- (참고) MCP `run_script`는 주력 머신 전용이며 `extends RefCounted` + `func execute(scene_tree)` 형식 — 원격에선 안 쓴다.

---

## 주력 GUI 머신에서 (Windows)

### 엔진 바이너리 — **CLI는 반드시 `_console.exe`를 쓴다**

```
C:\SDKs\godot\Godot_v4.7.1-stable_win64.exe          ← 에디터 실행 전용 (GUI)
C:\SDKs\godot\Godot_v4.7.1-stable_win64_console.exe  ← CLI 전용 (실측 검증 완료)
```

- Godot은 인스톨러 없는 포터블 exe다 — **PATH·레지스트리·파일 연결에 등록되지 않는다.** `godot` 명령은 존재하지 않으므로 항상 절대 경로로 호출한다.
- **GUI 바이너리는 stdout을 셸에 돌려주지 않는다**(Windows GUI 서브시스템 — 실측: `--version`이 공란 반환). 이걸로 CLI를 돌리면 `--check-only` 컴파일 에러·`validate` 결과·테스트 PASS/FAIL이 **전부 소실되고 종료코드만 남아** 자가 수정 루프가 성립하지 않는다. CLI는 예외 없이 `_console.exe`.

```powershell
# 로직 실행 (검증 완료 — 종료코드 0 · "LOGIC_TEST_PASS sum=4")
& "C:\SDKs\godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script test/logic_test.gd

# 컴파일 검증 (통과 = exit 0)
& "C:\SDKs\godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --check-only --script <파일.gd>

# 캐시 재생성 (pull 후 1회)
& "C:\SDKs\godot\Godot_v4.7.1-stable_win64_console.exe" --headless --import
```

### 작업 배분

- **씬 구성·노드/UI 레이아웃·리소스 배치**를 여기서 한다(소유권).
- **GDAI MCP + 에디터**로 실행·스크린샷·디버거·런타임 값 확인·플레이 테스트.
- "느낌/재미/밸런스" 판단은 사람 + 여기서.
- 원격에서 작성된 로직을 실제 씬에 통합하고 시각적으로 검증.

---

## 자가 수정 루프 (환경 공통 개념)
```
편집 → validate(통과?) → 실행(원격:Bash headless / 주력:GDAI runtime) → 에러 읽고 수정 → 반복
```
사람 개입은 "눈으로만 알 수 있는 것"에서만. 나머지는 에이전트가 루프를 닫는다.

---

## 프로젝트 정체
내러티브 턴제 레이싱 로그라이트. 슬롯 릴로 섹터를 주파하고, 자원으로 무작위성을 통제한다.
설계 문서 **D01~D16 전량 확정** 상태이며, 본 리포지토리는 **구현 단계** 전용이다.

- **단일 진실 원천:** `docs/master_plan_v2_34.md`
- **설계 정본:** `docs/design/` (21개 파일 — **읽기 전용. 수정 금지**)
- **구현 결정 로그:** `docs/decisions/impl_log.md`
- **현재 마일스톤:** MS-3 Steam EA (D15 §1.1) — 착수 프롬프트 = `prompts/MS3_kickoff.md` (양 레인 공용)
- **MS-1 = 완료 (2026-08-11) · MS-2 = 완료 (2026-08-15).** D15 §1.1 실일자 기입 완료 — 총괄 집행 종결 (`docs/handoff/MS2_마감_총괄회신.md`)

## 기술 스택 (D12 v1.1 §1 확정 — 변경 금지)
- **Godot 4.7 계열 핀** (v1.1 결정 #11 — v1.0 핀 4.4에서 갱신) · **GDScript 주 언어** (성능 임계 지점 한정 C#/GDExtension 보조 — 남용 금지) · **Compatibility 렌더러 단일**
- 빌드 산출 3종: Steam(Windows) / Android(AAB) / iOS — 데스크탑 빌드에 광고 모듈 컴파일 자체 제외
- 데이터 포맷: 수치 = CSV/TSV · 구조 = JSON · 스트링 = CSV(키 행×언어 열) — 전량 UTF-8·NFC

## 디렉토리 계약 (D12 §2.1 계층 구조의 물리적 대응)
```
godot/core/      공통 코어 — 플랫폼 규칙 0 (state/data/rng/save/render/audio)
godot/adapters/  플랫폼 어댑터 인터페이스 (추상 계약 — D12 §2.2 대장 7종)
godot/platform/  desktop(Steam·IAdService 널 구현) / mobile(광고·수명주기)
godot/ui/        화면 층 (D09/D09-2)
godot/data/      콘텐츠 데이터 (tables=CSV·structures=JSON·strings=CSV)
godot/assets/    아트·사운드 실물 — D10 §8.2 카테고리별 하위 (characters/vane/machines/
                 scenecuts/ui/{icons,frames}/glyphs/fonts/palettes/backgrounds/illustrations)
                 에셋 ID = `A-<분류>-##` (D10 §8.1) · `.import` 커밋 필수 (IMPL-003·IMPL-021)
tools/validators/ 빌드 기계 검증기 V1~V8 + 혼입 0 스캔 (CI = TL-1)
```

## 불변 규칙 — 위반 발견 시 작업 중단 후 보고
1. **혼입 0 (D12 §2.1)** — `godot/core/` 안에 플랫폼 조건 분기(`if platform == ...`), 플랫폼 API 호출, 광고·수익 모델 코드가 진입할 수 없다. 플랫폼 차이는 전부 `adapters/` 인터페이스 뒤로 격리한다. 광고 SDK·모바일 서비스는 모바일 빌드에만 포함(export preset·피처 플래그 분리 — D12 §2.3).
2. **데이터 드리븐 (D12 §4)** — 콘텐츠·수치는 전량 데이터 정의. 코드는 타입·규칙만 보유한다. **수치를 코드에 임의 기입하지 않는다. 필요한 값이 D13에 없으면 작업을 중단하고 보고한다** (값의 유일 창구 = D13 확정 기준값 대장 92항).
3. **정산 파이프라인 8단계 코드 상수 고정 (D12 §3.4 · C-2)** — ①위험 → ②자원 → ③방어 → ④전진·공략 → ⑤게이지 만충 판정 → ⑥듀얼 발동 → ⑦순위 갱신 → ⑧백그라운드 AI. 단계 신설·순서 변경·단계의 데이터화 금지.
4. **RNG 스트림 분리 (D12 §6)** — `reel / shuffle / resonance / event / ai / reserve` 6스트림, 마스터 시드에서 파생. 전 스트림 시드+내부 상태를 세이브에 직렬화(재로드 리롤 무효). reel 소비 시점 = 스핀 커밋(T2).
5. **봉인 (D12 §6.3 · D02 §4)** — 릴 정지 연출 완료 전, 결과·결과 상관 신호를 **어떤 출력 경로에도 노출하지 않는다** (UI·로그·사운드·햅틱·디버그 오버레이 포함).
6. **텍스트 하드코딩 금지 (D12 §8.1 · V4)** — 전 표시 문자열 = 키 참조. 스트링 키 = `{domain}.{feature}.{item}`(2~3단), 세그먼트 camelCase, `.` 구분자 전속. 테이블 ID = `snake_case`+도메인 접두(`skill_`, `event_` …) — **스트링 키와 별개 체계**. '티어' 부분 문자열 일괄 치환 금지(T-1 — 치환은 키 단위만, D12 §8.3).
7. **검증기 = 빌드 게이트 (D12 §4.2 · D14 §2.1 TL-1)** — V1~V8 + 혼입 0 스캔은 빌드 전 단계 고정 실행. **V1~V6·V8 + 혼입 0 스캔 = 위반 1건이면 빌드 실패.** 단 **V7(금칙 어휘 검사)은 경고 전용이며 빌드를 차단하지 않는다** — 작법 판단은 D04 트랙 소관이고 기계는 보조라는 D12 §4.2 V7 행·D14 TL-1의 명문이다. 검증기를 우회·완화·비활성화하지 않으며, **V7을 차단형으로 구현하지도 않는다.**
8. **프레임 의존 로직 금지 (D12 §3.2)** — 실시간 처리·물리 판정 부재. 전 판정은 턴 이벤트 구동.
9. **문서 충돌 (마스터플랜 §0.6)** — 설계 문서 간 충돌, 또는 문서와 구현 사이의 충돌을 발견하면 **임의 해석·임의 수정 금지.** 중단하고 사용자에게 보고한다. `docs/design/` 파일은 절대 수정하지 않는다.

## 문서 라우팅 — 무엇을 구현할 때 어느 문서가 정본인가
| 구현 대상 | 정본 |
|---|---|
| 코어 루프 · 턴 시퀀스 T1~T6 · 릴/개입/듀얼 규칙 | D05 (+구현 골격 D12 §3) |
| 재화·성장·Source/Sink·환전 | D06 |
| 스킬 16종·덱·크루·스폰서·기록실·아웃게임 시설 | D07 |
| 서킷 20종·이벤트·시즌 캘린더·라이벌 배치·그리드 레벨 | D08 + 별첨A |
| 화면·플로우·입력·옵션 (데스크탑) | D09 + 별첨A (화면 명칭 정본 = D09 §8.1 대장) |
| 화면·플로우·인터럽트 (모바일) | D09-2 + 별첨A |
| 아트 규격·캔버스·팔레트·에셋 목록 | D10 |
| SFX 68식·BGM 13+1·햅틱·오디오 층위 | D11 |
| 아키텍처·상태 머신·스키마 12종·검증기·RNG·세이브·로컬라이제이션 구조 | D12 |
| **전 수치 값** (루트 앵커 A1~A5 · 확정 기준값 대장 92항) | D13 + 별첨A |
| 테스트 레벨 TL·시나리오 TC·게이트 G-1~G-7 실행 규격 | D14 |
| 마일스톤 MS-1~MS-6 · EA · 스토어 · 언어 세트 | D15 |
| 광고 규칙 (모바일 전속 — 소비 = 테이블 D12 §5.11 + 모바일 레이어) | D16 |
| **용어의 유일 기준** | D02 용어집 |

## 작업 방식
- **마일스톤 단위 직렬 진행** (D15 §1.1: MS-1 → MS-6). 현 단계 범위 밖 선행 구현 금지 — 단, 어댑터 인터페이스 등 구조 골격은 처음부터 배치한다.
- 구현 중 내린 해석·결정은 `docs/decisions/impl_log.md`에 기록한다 (날짜·ID·결정·근거·영향 문서).
- 설계가 답하지 않는 세부는 임의 확정하지 않는다: 사소한 것은 코드 주석 `# [가안]` 표기 후 impl_log에 등재, 설계 층위 판단이 필요한 것은 질문한다.
- 커밋 전 검증기 통과를 확인한다.
