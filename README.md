# 배드민턴 2D (Roblox)

옆에서 바라보는 시점(side view)의 2D 배드민턴 게임입니다. 화면 전체를 ScreenGui로 그리고,
셔틀콕 물리·점수 규칙·AI가 모두 Luau로 작성되어 있습니다.

- **AI와 대결**: 쉬움 / 보통 / 어려움 3단계
- **온라인 1:1**: 같은 서버에 있는 다른 플레이어와 매칭. 서버가 경기를 직접 계산하는 서버 권위(server-authoritative) 방식
- **셔틀콕 물리**: 중력과 quadratic drag(속도 제곱에 비례하는 공기 저항)를 적용해서, 빠르게 날아가다 급격히 느려지며 거의 수직으로 떨어지는 셔틀콕 특유의 궤적이 나옵니다
- **샷 종류**: 클리어, 드롭, 스매시(점프해서 강타), 언더핸드 리프트, 네트 샷, 하이 서브, 숏 서브
- **규칙**: 랠리 포인트제로 11점 선승, 2점 차이(듀스), 최대 15점. 아웃, 네트, 숏 서브 폴트를 판정합니다
- PC(키보드·마우스), 게임패드, 모바일(터치 버튼)을 지원합니다

## 바로 플레이하기

### 방법 1: place 파일 열기 (가장 간단)

1. Roblox Studio에서 **File → Open from File**로 [`build/Badminton2D.rbxlx`](build/Badminton2D.rbxlx)를 엽니다.
2. **Play**(F5)를 누릅니다.
3. 온라인 1:1을 시험하려면 **Test** 탭에서 **Clients and Servers**를 플레이어 2명으로 설정한 뒤 **Start**를 누르고, 두 창 모두에서 `온라인 1:1`을 누릅니다.
4. 게임을 공개하려면 **File → Publish to Roblox**를 사용합니다.

> `build/Badminton2D.rbxlx`는 `src/`에서 생성한 파일입니다. 코드를 수정했다면 아래 Rojo 명령으로 다시 만들어 주세요.

### 방법 2: Rojo로 실시간 동기화 (개발용)

```bash
rokit install                         # rokit.toml에 적힌 도구 설치 (rojo, lune 등)
rojo serve                            # Studio의 Rojo 플러그인에서 Connect
rojo build -o build/Badminton2D.rbxlx # place 파일 다시 만들기
```

## 조작법

| 동작 | 키보드 / 마우스 | 게임패드 | 모바일 |
| --- | --- | --- | --- |
| 이동 | `A` `D` / `←` `→` | 왼쪽 스틱, 방향 패드 | ◀ ▶ |
| 점프 | `W` / `↑` / `Space` | A | 점프 |
| 강타 (클리어, 스매시, 리프트) | `J` / 마우스 왼쪽 | X, R2 | 강타 |
| 드롭 (드롭, 네트 샷) | `K` / 마우스 오른쪽 | B, L2 | 드롭 |

- 셔틀이 몸 앞쪽 타격 범위에 들어왔을 때 스윙해야 맞습니다. 너무 일찍 휘두르면 헛스윙입니다.
- 머리 위 스윗 스팟에 가깝게 맞힐수록 정확한 샷이 나가고, 멀수록 아웃이나 네트가 나기 쉽습니다.
- **점프 중에 높은 셔틀(높이 2.55 이상)을 강타하면 스매시**가 됩니다.
- 허리보다 낮은 셔틀은 언더핸드로 칩니다 (강타 = 리프트, 드롭 = 네트 샷).
- 서브할 때 강타 = 하이 서브, 드롭 = 숏 서브. 7초 동안 서브하지 않으면 자동으로 하이 서브가 나갑니다.
- 셔틀 아래 바닥의 그림자로 낙하 지점을 가늠할 수 있습니다. 화면 위로 벗어난 셔틀은 ▲로 표시됩니다.

## 구조

```
src/
  shared/      ReplicatedStorage.Shared — Roblox API를 쓰지 않는 순수 게임 로직
    Config.luau    튜닝 값 (코트 크기, 속도, 점수 규칙 등)
    Shuttle.luau   셔틀콕 물리, 궤적 시뮬레이션, 발사 속도·각도 역산(solver)
    Shots.luau     샷 종류별 목표 지점 선택과 오차 모델
    Match.luau     경기 상태, 서브/랠리/득점 규칙, 타격 판정, 네트워크 직렬화
    Bot.luau       AI (낙하 지점 예측, 이동, 스윙 타이밍, 난이도)
    Rng.luau       시드 고정 난수 (테스트 재현용)
  server/      ServerScriptService.Server
    MatchServer.server.luau  온라인 매칭, 서버 권위 시뮬레이션, 스냅샷 전송, 지연 보정
  client/      StarterPlayerScripts.Client
    Main.client.luau  화면 상태 관리 (메뉴 / AI 대결 / 매칭 / 온라인 / 결과)
    Renderer.luau     체육관, 코트, 선수, 셔틀콕, 이펙트 그리기
    Interface.luau    메뉴, 점수판, 안내 문구, 결과 화면
    Controls.luau     키보드·마우스·게임패드·터치 입력
    Strings.luau      화면 문구 (번역하려면 이 파일만 수정)
tests/         Lune으로 실행하는 테스트
build/         Studio에서 바로 여는 place 파일
```

### 동작 방식

- **고정 시간 간격 시뮬레이션**: `Match:step(1/60, inputs)`가 한 틱을 진행합니다. AI 대결은 클라이언트에서, 온라인 대결은 서버에서 같은 코드가 돌아갑니다.
- **샷 계산**: 샷마다 목표 낙하 지점을 정한 뒤, 셔틀콕 물리로 궤적을 시뮬레이션하면서 이분 탐색(binary search)으로 발사 속도·각도를 찾습니다. 드롭과 네트 샷은 네트를 넘는 가장 낮은 궤적을 고릅니다.
- **온라인**: 클라이언트는 입력만 보내고, 서버는 초당 30번 스냅샷을 `UnreliableRemoteEvent`로 보냅니다. 클라이언트는 0.1초 전 시점을 보간(interpolation)해서 부드럽게 그립니다. 그만큼 늦게 보이는 화면을 보정하기 위해, 서버는 스윙 판정 시 그 플레이어의 핑(ping)만큼 과거의 셔틀 위치도 함께 확인합니다(lag compensation).
- 2번 선수(오른쪽 코트)도 화면은 좌우 반전되어 항상 **자기가 왼쪽**에 보입니다.

## 튜닝

대부분의 값은 [`src/shared/Config.luau`](src/shared/Config.luau)에 있습니다.

- `POINTS_TO_WIN`, `WIN_BY`, `MAX_POINTS`: 점수 규칙 (정식 경기는 21 / 2 / 30)
- `PLAYER_SPEED`, `JUMP_VELOCITY`: 선수 움직임
- `GRAVITY`, `TERMINAL_VELOCITY`: 셔틀콕이 뜨는 느낌
- `HIT_ZONE_*`, `SWING_ACTIVE`: 타격 판정의 너그러움

AI 난이도는 [`src/shared/Bot.luau`](src/shared/Bot.luau)의 `Bot.Difficulties`에서 조절합니다.

## 테스트

[Lune](https://github.com/lune-org/lune)으로 Roblox Studio 없이 실행합니다.

```bash
lune run tests/run          # 물리, 샷, 규칙, 타격 판정, 직렬화, AI 끝까지 경기하기
lune run tests/integration  # 실제 서버/클라이언트 스크립트를 가짜 Roblox 런타임에서 실행
lune run tests/selfplay     # AI끼리 경기시켜 랠리 길이, 득점 이유 통계 출력 (밸런스 조정용)
```

`tests/integration`은 서버 1개와 클라이언트 2개를 지연(50ms)과 스냅샷 손실(5%)이 있는 가짜 네트워크로 연결하고,
버튼 클릭과 키 입력으로 메뉴 → AI 대결 → 온라인 매칭 → 경기 종료 → 기권 → 접속 종료까지 진행합니다.
가짜 런타임은 실행 흐름만 확인하므로 실제 화면은 Studio에서 확인해 주세요.

정적 검사:

```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src/
stylua --check src tests
```

`globalTypes.d.luau`는 [luau-lsp 저장소](https://github.com/JohnnyMorganz/luau-lsp/tree/main/scripts)에서 사용하는 luau-lsp 버전에 맞는 것을 받습니다.
