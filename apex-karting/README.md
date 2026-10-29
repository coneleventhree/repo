# A1 Kart Racing

리얼 물리 기반 Roblox 고카트 레이싱 게임이에요. 플레이어끼리만 레이스하고, 아이템은 없어요. 트랙은 9개예요. 접속하면 로딩 화면 → 메인 메뉴(로비)에서 **RACE**(다른 플레이어와 빠른 매칭), **PRACTICE**(맵을 골라 혼자 연습), **PRIVATE ROOM**(친구와 4자리 방 코드)을 골라요. 레이스 한 라운드는 트랙·길이 투표 → 1랩 고스트 퀄리파잉(예선) → 그리드 → 레이스 → 짧은 포디움 순서로 돌아가요.

| 트랙 | 길이 | 랩 | 성격 |
|---|---|---|---|
| Tampines Ring | 2,484 studs (약 0.7 km) | 짧게 2 / 보통 3 / 길게 5 | 카트 전용 서킷, 타이트하고 테크니컬 |
| Silverstone | 5,858 studs (약 1.6 km) | 짧게 1 / 보통 2 / 길게 3 | 실제 F1 실버스톤 GP 레이아웃, 고속 코너 위주 |
| Lakeside International | 3,665 studs (약 1.03 km) | 2 / 3 / 5 | 국제 대회형 카트 서킷, 빠르고 흐르는 코너, 서킷 옆 호수 |
| Hillside Raceway | 3,776 studs (약 1.06 km) | 2 / 3 / 5 | 언덕 서킷: 오르막·내리막(높이차 약 8.8 m), 오르막 끝 고속 킹크(Sling), 뱅크 코너 3개, 핸들을 계속 잡고 도는 긴 고속 코너, 소나무 |
| Harbour Circuit | 3,110 studs (약 0.87 km) | 2 / 3 / 5 | 아침 항구, 부두를 따라 선 가로등, 긴 대각선 직선과 깊은 헤어핀 |
| Suzuka | 4,645 studs (약 1.3 km) | 1 / 2 / 3 | 실제 스즈카 GP 레이아웃을 3D로: 8자 입체교차(다리), 높이차 약 9 m, S자·데그너·헤어핀·스푼·130R·시케인 |
| Catalunya | 3,161 studs (약 0.89 km) | 2 / 3 / 5 | 스페인 GP(바르셀로나): 긴 오른쪽 Turn 3, 언덕을 오르내리는 레이아웃, 빠른 마지막 코너 |
| Zandvoort | 3,114 studs (약 0.87 km) | 2 / 3 / 5 | 네덜란드 GP: 모래언덕 위아래, 뱅크 코너 2개(Hugenholtz 헤어핀, 마지막 Arie Luyendyk) |
| Yas Marina | 3,341 studs (약 0.94 km) | 2 / 3 / 5 | 아부다비 GP(2021 레이아웃): 해 질 녘 레이스, 헤어핀 뒤 긴 직선, 살짝 뱅크된 긴 Turn 9, 호텔 구간 |

Hillside, Suzuka와 GP 서킷 3개(Catalunya, Zandvoort, Yas Marina)에는 언덕이 있고 나머지는 평평한 전용 서킷이에요. 공통 시설: 아스팔트, 빨강·흰색 연석, 파랑·빨강으로 칠한 run-off(런오프, 코너 바깥 포장 탈출로), 느린 코너의 자갈 트랩, 인조 잔디 갓길, 타이어 방호벽과 펜스, 피트 레인·개러지·레이스 컨트롤 타워, 관중석, 스폰서 브리지, 마셜 포스트, 조명탑, 외곽 담장과 주차장.

### 카트 서킷 (Lakeside · Harbour, 그리고 언덕 서킷 Hillside)

실제 카트 서킷 기준(FIA 카팅 서킷 라이선스 기준)에 맞춰 직접 설계했어요. 카트와 같은 비율(1 stud = 0.28 m)로 재면:
- 도로 폭 8.7~10 m (기준: 최소 6~8 m), 출발 직선 134~183 m (기준: 120~200 m), 가장 긴 직선 200 m 이하.
- 출발선에서 첫 코너까지 50 m 이상, 마지막 코너에서 출발선까지 대부분 55~70 m.
- 트랙끼리 가장 가까운 곳도 10 m 이상 떨어져 있어요(기준: 6 m).
- 헤어핀 반지름 약 11~12 m라서, 대부분의 코너를 45~70 km/h로 돌아요. 그래서 이번에 바꾼 렌탈 카트 가속이랑 잘 맞고, 코너 탈출이 랩타임을 좌우해요.

| 트랙 | 자동 주행 랩(가운데 라인) | 특징 |
|---|---|---|
| Lakeside International | 약 55초 | 183 m 출발 직선 → 빠른 오른쪽 Boathouse, 양 끝의 헤어핀(Pier, Reed), 180도 Carousel, Esses, 빠른 더블 라이트 Willow. 펜스 안쪽에서 가장 넓은 빈 땅에 호수가 생겨요(들어가면 거의 멈출 만큼 느려져요). |
| Harbour Circuit | 약 49초 | 맑은 아침의 항구. 트랙 옆에 약 55 studs마다 가로등이 서 있어요(예전엔 밤 레이스였는데 눈이 피곤해서 아침으로 바꿨어요). 긴 대각선 직선 끝의 깊은 Harbour 헤어핀, 풀 스로틀로 지나는 Breakwater 더블 킹크(슬립스트림 추월 포인트), 구불구불한 인필드. |

세 트랙 모두 코너마다 이름 보드가 있어요.

### 언덕 서킷: Hillside Raceway

트랙에 높이(y)와 뱅크(bank, 코너 안쪽으로 기울인 노면)가 들어간 첫 서킷이에요. 출발선·그리드·피트는 평지이고, 나머지는 언덕 위로 올라갔다 내려와요.

- 한 바퀴: 출발 → Turn 1 → 오르막 S자(Uphill esses) → 긴 오르막(Hill climb) → **Sling**(오르막 끝 좌-우 고속 킹크: 반지름 85, ±28°, 라인을 잘 타면 거의 풀스로틀, 자동 주행은 76 km/h에서 살짝만 뗌) → 바로 브레이킹해서 앞이 안 보이는 꼭대기 코너(Crest, 해발 약 9 m) → 고원 위 Corkscrew → **12° 뱅크 헤어핀 Karussell** → **12° 뱅크 Bowl** → 긴 내리막(Downhill) → 골짜기 바닥에서 바로 치고 올라가는 Eau Rouge / Raidillon → Top hairpin → Hairpin → **Long sweeper**(반지름 72, 180°를 한 번에, 6° 뱅크: 65~69 km/h로 3초 넘게 핸들을 일정하게 잡고 도는 고속 코너) → 출발선.
- 가장 가파른 곳 약 10%. 자동 주행 랩 약 59초.
- **뱅크 코너가 빨라지는 이유**: 노면이 코너 안쪽으로 기울어 있으면, 노면이 카트를 받쳐 주는 힘(normal force, 수직항력)의 일부가 코너 안쪽을 향해서 구심력(centripetal force)을 도와줘요. 물리 테스트에서 반지름 12.6 m 헤어핀을 평평하면 54 km/h, 12° 뱅크면 65 km/h로 돌아요(`luau tests/tools/bank.luau`).
- 언덕 아래 땅: 높아진 도로의 갓길 끝에서 1:2.5 경사(약 22°)의 잔디 둑이 잔디밭까지 내려가요. 다른 도로의 둑과 만나면 골짜기가 되고, 다른 도로의 갓길에 닿으면 그 높이에 맞춰 이어지고, 급한 코너 안쪽은 한 점으로 모이는 부채꼴 경사로 채워서 구멍이나 낭떠러지가 없어요. 높아진 도로의 연석·런오프·자갈 아래에는 인조 잔디 바닥을 한 겹 더 깔아서 띠 사이 틈도 막았어요. 잔디 둑도 달릴 수 있는(잔디 그립) 바닥이에요.
- 언덕 위 코너(Crest, Karussell, Bowl) 바깥 관중석은 둑 높이에 맞춘 콘크리트 받침대 위에 있어요.
- **경사에서 덜덜거림 수정**: 오르막·내리막 코너에서 도로 조각이 비틀려 있어서(twisted quad, 꼬인 사각형) 삼각형 두 개 사이에 최대 0.65 studs의 접힌 자국이 생겼고, 카트가 그 위를 계속 넘으면서 떨렸어요. 비틀린 곳은 도로를 더 잘게 나눠서 접힘을 0.05 studs 아래로 줄였고, 언덕 서킷은 트랙 샘플 간격을 6 → 5 studs로 촘촘하게 했어요. 프레임이 낮을 때(20~30 fps)는 바퀴마다 프레임 끝 위치에도 레이를 쏴서 바닥 사이를 부드럽게 이어요. 떨림(피치 흔들림)이 Hillside 4.6 → 0.8, Suzuka 2.0 → 0.7 deg/s로 평지 서킷과 같은 수준이 됐어요.
- 뱅크가 바뀌는 구간(`BankSmoothing = 40`)을 길게 잡았어요. 서스펜션이 없는 카트는 노면이 빨리 비틀리면 대각선 바퀴가 들려서, 20 fps 같은 낮은 프레임에서 불안정해졌거든요. 같은 이유로 Karussell은 15°가 아니라 12°예요.

### Silverstone

- 실제 실버스톤 GP 레이아웃(2011년~, 시계 방향, 18개 코너)을 실제 중심선 데이터에 맞춰 그렸어요. 1 stud = 실제 1 m 비율(실물의 28% 크기)이라 코너 각도·순서·간격이 실제와 같고, 코너 경계가 실제 선에서 평균 4 studs 안에 들어와요.
- 카트 도로 폭(32~36 studs)에 맞추려고 아주 느린 코너(The Loop, Vale)만 반지름을 최소 30 studs로 넓혔어요.
- 좋은 라인으로 달릴 때 속도 예상치(km/h): Abbey 78 · Farm 82 · Village 37 · The Loop 32 · Aintree 54 · Brooklands 54 · Luffield 44 · Woodcote 62~72 · **Copse 85 (코너 한계와 거의 같음) · Maggotts 91 (풀 스로틀) · Becketts 92 → 64 · Chapel 70 · Stowe 66** · Vale 50 · Club 50~60. 이상적인 랩 약 79초, 가운데로만 달리면 약 84초예요. 어느 직선에서도 최고 속도 제한(100 km/h)에 닿지 않아서, 코너 탈출 속도가 다음 코너까지 그대로 이어져요.
- Hamilton Straight에 그리드·피트, 피트 위에 날개 모양 지붕(The Wing), Hangar Straight 위에 스폰서 브리지, 코너마다 이름 보드(COPSE, BECKETTS, STOWE…), 구름 낀 영국 날씨.
- 이름은 실제 서킷 이름이에요. 퍼블리시할 때 상표 문제가 걱정되면 `Shared/TrackData`의 `Name`만 바꾸면 돼요.

### Suzuka

- 실제 스즈카 GP 레이아웃(8자 모양)을 실제 중심선 데이터에 맞춰 그렸어요. 실버스톤보다 작은 0.8 비율(실제 1 m = 0.8 stud)이라 랩이 짧고(4,645 studs), 코너 경계가 실제 선에서 평균 4 studs 안에 들어와요. 도로 폭은 28 studs(출발 직선 30)로 다른 트랙보다 좁아서 스즈카답게 테크니컬해요.
- **고저차(2D 아님)**: 실제 레이저 측량 고도를 수평과 같은 0.8 비율로 썼어요. T1~T2 골짜기(가장 낮음) → S자 오르막 → 던롭 꼭대기 → 데그너 내리막 → 다리 밑 → 헤어핀 오르막 → 스푼(가장 높음, 32 studs) → 백스트레이트 골짜기 → 다리 위 → 130R → 시케인 → 라스트 커브 내리막. 가장 가파른 곳 약 10%.
- **입체교차(figure-eight crossover, 8자 교차)**: 백스트레이트가 데그너에서 헤어핀으로 가는 길 위를 69° 각도로 지나가요. 다리는 콘크리트 거더(girder, 다리 상판 아래 보)와 난간이 있고, 아래 도로는 옹벽(retaining wall, 흙막이 벽) 사이로 지나가요. 다리 밑 높이는 거더까지 11.6 studs예요. 위아래 층에 있는 카트끼리는 부딪히지도 않고 슬립스트림도 받지 않아요.
- 게임에 맞게 바꾼 곳: 피트와 그리드 때문에 출발 직선은 평평하게(실제는 내리막) 하고 라스트 커브가 고르게 내려와요. 다리 밑은 카트·카메라가 지나가게 실제보다 깊게 팠어요. 130R은 거의 풀 스로틀로 지나게 반지름을 넓혔어요. 스푼 진입로와 백스트레이트 사이는 방호벽 자리를 만들려고 넓혔어요. 헤어핀·데그너 2는 최소 반지름 32로 넓혔어요. 역뱅크(Gyaku Bank, 실제는 바깥으로 기운 노면)는 −1.5°만 줘도 카트가 튕겨 나가서 평평하게 했어요.
- 자동 주행 랩 약 70초(실버스톤 약 84초, 힐사이드 약 59초). 코너 속도(자동 주행): 헤어핀 42, 카시오 시케인 48, 라스트 커브 52, S자·데그너 60~65, 스푼 59, 130R 80 km/h.
- 언덕 위 코너(Gyaku Bank, 헤어핀, 스푼)의 관중석은 콘크리트 받침대 위에 올라가 있어요. 빈 땅에는 소나무가 있어요.

### GP 서킷: Catalunya · Zandvoort · Yas Marina

실제 F1 서킷 3개를 실제 중심선 데이터와 실제 고도로 만들었어요(Suzuka와 같은 방식). 크기는 실제 1 m = 0.8 stud라서 카트 속도에 맞는 크기예요: 자동 주행 랩 52~56초(Lakeside·Hillside와 비슷), 최고 속도 84~88 km/h.

- **긴 직선은 줄였어요**: 카트로 긴 직선을 달리면 지루해서, 그 직선과 반대 방향으로 달리는 직선들을 같은 만큼 줄여서 나머지 코너 배치는 거의 그대로 두었어요.
  - Catalunya: 메인 직선 811 → 약 650 studs, 백 스트레이트 375 → 291 studs (대신 Turn 3 → 4 사이 직선 등이 짧아짐)
  - Yas Marina: 헤어핀 뒤 긴 직선 800 → 580 studs, 두 번째 직선 343 → 260 studs (대신 Turn 1~5 쪽 직선과 호텔 구간 직선이 짧아짐)
  - Zandvoort: 메인 직선 524 → 452 studs
- **고저차**: 위성 고도 데이터(Copernicus 30 m DEM)를 서킷 중심선을 따라 읽고, 나무·관중석 같은 구조물이 높게 잡힌 부분은 걸러낸 뒤(낮은 쪽 백분위수 + 평활화), 경사가 7.5%를 넘지 않게 다듬었어요. 높이도 가로 크기와 같은 비율로 줄였어요.
  - Catalunya: 실제 높이차 약 30 m → 게임 21 studs. Turn 1 근처가 가장 낮고, Turn 3로 올라갔다가 Turn 5로 내려가고, Turn 9 · Turn 12 쪽이 가장 높아요. 출발 직선과 그리드는 평평해요.
  - Zandvoort: 모래언덕(실제 약 9 m)을 잘 느끼도록 높이만 가로 비율의 1.6배로 키웠어요(최대 8.6 studs). Hugenholtz(12° 뱅크 헤어핀)와 Arie Luyendyk(9° 뱅크 마지막 코너)는 실제처럼 뱅크가 있어요(실제는 19° / 18°지만 서스펜션 없는 카트가 낮은 fps에서도 안정적인 각도로 줄였어요).
  - Yas Marina: 실제로 거의 평지라 높이차가 작아요(최대 약 8 studs). 긴 왼쪽 Turn 9는 2021년 개편처럼 살짝(6°) 뱅크가 있어요.
- **Yas Marina는 반시계 방향**이라 피트·개러지·패독이 출발 직선의 오른쪽(트랙 바깥)에 있고, 메인 관중석은 반대쪽이에요. 다른 서킷은 모두 왼쪽이에요.
- Yas Marina는 해 질 녘(실제 아부다비 GP처럼 저녁 출발), Zandvoort는 흐린 날씨, Catalunya는 맑은 날씨에 소나무가 있어요. 밤 서킷은 없어요(눈이 피곤해서 없앴어요).
- 코너 이름 보드: Zandvoort는 실제 코너 이름(Tarzan, Hugenholtz, Scheivlak, Arie Luyendyk 등), Catalunya와 Yas Marina는 실제 코너 이름에 스폰서 이름이 많아서 Turn 번호로 했어요.
- 실제 서킷 이름을 그대로 썼어요. 퍼블리시할 때 상표 문제가 걱정되면 `Shared/TrackData`의 `Name`만 바꾸면 돼요.
- 만드는 법(코너 맞추기, 직선 줄이기, 고도)은 `tools/design/gp/`에 있어요(`tools/design/README.md`).

## 메뉴와 모드 (로비 + 서버 이동)

공개 서버는 전부 **로비**예요. 메뉴 뒤에서 카메라가 서킷 하나를 천천히 따라 날아가요(fly-by). 버튼을 누르면 그 모드 전용 서버(reserved server, 예약 서버)를 만들어서 그쪽으로 텔레포트(teleport, 서버 이동)해요.

| 버튼 | 하는 일 |
|---|---|
| **RACE** | 빠른 매칭. 모든 로비 서버가 같은 대기열(MemoryStore)을 봐요. **2명이 모이면 7초 뒤** 출발하고, 12명이 차면 바로 출발해요. 혼자면 계속 기다려요(CANCEL로 취소). 같이 매칭된 사람들이 한 레이스 서버로 함께 이동해서 투표 → 퀄리 → 레이스를 하고, 끝나면 같은 사람들끼리 다음 라운드가 이어져요. |
| **PRACTICE** | 트랙 카드(모양, 길이, 내 최고 랩, 트랙 레코드)에서 고르고 DRIVE → 나 혼자 쓰는 연습 서버. 거기서도 트랙 패널(M)로 맵을 바꿀 수 있어요. |
| **PRIVATE ROOM** | CREATE A ROOM → 방 서버의 **대기실**로 가고 4자리 코드가 생겨요. 친구는 메뉴에서 코드를 넣고 JOIN. 대기실은 오버워치 사설방처럼: 12칸 슬롯에 이름과 HOST / READY / NOT READY / OPEN, 방장만 트랙(CHANGE TRACK → 연습 메뉴처럼 트랙 레이아웃 카드에서 고르기)과 길이(SHORT/NORMAL/LONG)를 바꾸고, 손님은 READY를 눌러요. **모두 READY여야** 방장의 START RACE가 켜져요(혼자면 바로 시작 가능). 대기실에서 트랙을 골라도 서킷은 바로 바뀌지 않고, START RACE를 누를 때 한 번만 바뀌어요(서킷 교체는 파트 수만 개를 모두에게 보내는 일이라 고를 때마다 바꾸면 느려졌어요). 시작하면 퀄리 → 레이스 → 포디움 → 다시 대기실(모두 NOT READY로 초기화). 방장은 KICK(두 번 눌러야 함)으로 내보낼 수 있고, 내보낸 사람은 로비에서 "The host removed you from the room" 안내를 보고, 그 방에는 다시 못 들어와요. LEAVE로 로비로. 방장이 나가면 다음 사람이 방장이 돼요. 레이스 중에 들어온 사람은 그 판은 관전하고 다음 판부터 같이 해요. |
| **RECORDS** | 트랙별 내 최고 랩과 트랙 레코드 |
| **SETTINGS** | 설정 메뉴 (게임 중에는 화면의 SETTINGS 버튼) |

- **LOBBY 버튼**: 로비가 아닌 서버에서는 화면 아래(폰은 왼쪽 위, 랩 타임 위)에 있어요. 실수로 나가지 않게 **두 번** 눌러야 해요(3초 안에).
- **폰 화면**: 메뉴는 폰에서 화면 높이에 맞춰 키워요(844×390 폰에서 약 0.67배, HUD는 0.55배). 폰에서는 트랙·투표·방 패널이 화면 위 가운데(배너 아래)에 열려서 왼쪽 조향 버튼을 가리지 않아요.
- **로딩 화면**: 처음 접속할 때와 서버를 옮길 때 같은 화면이에요. A1 로고, 진행 바(위에 작은 카트), 어디로 가는지(예: "Practice - Lakeside International"), 4.5초마다 바뀌는 팁. 이동할 때는 떠나는 서버에서 띄운 화면이 다음 서버 로딩까지 그대로 이어져서(SetTeleportGui) 중간에 빈 화면이 없어요. 최소 2초, 게임과 서킷이 다 준비되면 사라져요. 이미지 없이 UI만으로 만들어서 따로 받을 파일이 없어요.
- **Studio에서는** 텔레포트가 안 돼요. 그래서 Studio에서는 메뉴 버튼을 누르면 **지금 서버가 그 모드로 바뀌어요**(서버 안의 모두가 같이). RACE는 Studio에서만 1명이어도 출발해요(`Config.Lobby.StudioSolo`).
- 실패하면(서버를 못 만들거나 이동 실패) 메뉴에 빨간 글씨로 알려주고 다시 누를 수 있어요.

## 열고 테스트하기

1. Roblox Studio → File → Open from File → [`build/A1KartRacing.rbxlx`](build/A1KartRacing.rbxlx)
2. **혼자 테스트**: Play(F5) → 메인 메뉴. PRACTICE → 트랙 고르고 DRIVE → 이 서버가 연습 모드로 바뀌고 카트에 앉아요. 랩 타임이 기록돼요.
   연습 중에 **M**(또는 화면의 TRACK 버튼)을 누르고 트랙 카드를 클릭하거나 숫자 **1~9**를 누르면 바로 그 트랙으로 바뀌어요(패널 카드 오른쪽 위 숫자, 지금 트랙이 1번). LOBBY 두 번 → 메뉴로.
   PRIVATE ROOM → CREATE A ROOM → 대기실에서 START RACE로 혼자 퀄리·레이스까지 해볼 수 있어요. (Studio에서 KICK은 그 플레이어 창을 끊어요: 서버가 하나뿐이라 로비로 보낼 곳이 없어서요.)
3. **2인 레이스 테스트**: Test 탭 → Clients and Servers → Players를 2로 → Start. 한 명이 RACE를 누르면(Studio라 7초 뒤) 서버가 레이스 모드로 바뀌고 둘 다 들어가요.
   2명이 되면 20초 대기(트랙·길이 투표, 모두 READY를 누르면 3초로 줄어듦) → 1랩 고스트 퀄리파잉 → 그리드 → 빨간 불 5개 → 소등(GO) → 랩 → 포디움 8초 → 다음 라운드 순서로 진행돼요.
   진짜 매칭·방 코드·서버 이동은 **퍼블리시한 게임에서만** 돼요(아래 "퍼블리시 전에 할 일").
4. 서버가 시작할 때 서킷을 파트로 만들어요 (지형 terrain 없음, Hillside의 언덕도 wedge 파트로 만든 잔디 둑). 고른 서킷을 먼저 만들어서 바로 달릴 수 있게 하고, 나머지는 그 뒤에 만들어요. 쓰는 서킷은 `Workspace.Circuit`, 나머지는 `ServerStorage.Circuits`에 대기하고, 트랙을 바꾸면 폴더를 옮겨요. 퍼블리시한 게임의 로비 서버는 메뉴 뒤 배경용으로 서킷 하나만 만들어요(로딩이 빨라요). 플레이스 파일에는 미리 만든 파트가 없어요.

### 트랙 고르기

- **연습 중(혼자)**: 트랙 패널에서 고르면 바로 바뀌어요. 바뀌는 동안 로딩 화면이 뜨고 캐릭터는 새 패독에 고정돼 있어요. 내 화면에 새 서킷(패독 바닥과 그리드 도로)이 다 도착하면 로딩 화면이 사라지고 카트가 나와요. 예전에는 3초만 기다려서, 서킷이 늦게 오면 캐릭터가 바닥 아래로 떨어졌어요. 트랙이 바뀌는 다른 경우(레이스 투표, 방의 START)도 같아요.
- **레이스 전 대기 시간**: 트랙 패널이 저절로 열리고, 카드를 눌러 투표해요(다시 누르면 바꿀 수 있어요). 카운트다운이 끝나면 가장 많이 받은 트랙으로 레이스해요. 동점이면 추첨, 아무도 투표 안 하면 지금 트랙 그대로예요.
- 개인 최고 랩과 트랙 레코드는 트랙마다 따로 저장돼요.

## 레이스 진행

1. **대기 시간(20초)**: 트랙 카드 아래에 **SHORT / NORMAL / LONG** 버튼(트랙별 랩 수와 표 수가 보여요)과 **READY** 버튼이 있어요. 길이는 가장 많은 표, 동점이면 NORMAL이에요. 모두 READY를 누르면 남은 시간이 3초로 줄어요(다시 누르면 취소). 이 시간엔 계속 연습 주행할 수 있어요.
2. **퀄리파잉 (1랩 원샷, 고스트)**: 모두 출발선 70 studs 뒤 같은 자리에서 동시에 출발해요. 가속해서 출발선을 지나는 순간부터 **딱 한 바퀴**를 재요(롤링 스타트). **고스트 모드**라서 서로 통과하고(범퍼 충돌 없음, 슬립스트림 없음), 다른 카트와 드라이버는 반투명(60%)으로 보여요. 트랙 리밋을 넘으면 그 랩은 삭제되고 맨 뒤에서 출발해요. 랩을 마치면 "QUALIFYING LAP 0:40.141 - P1 SO FAR"처럼 지금 순위가 나오고, 모두 마치면 바로 그리드로 가요. 트랙마다 제한 시간(Tampines 2분, Silverstone·Suzuka 3분, 나머지 2분 30초)이 끝나면 **체커기**: 달리던 랩만 마치면 돼요. 화면 오른쪽에 순위와 1등과의 차이가 나와요.
3. **그리드**: 퀄리파잉 최고 랩 순서대로 서요. 기록이 없거나 늦게 들어온 사람은 뒤쪽이에요. 폴 포지션은 화면에 크게 알려줘요.
4. **레이스**: 빨간 불 5개(불마다 삑) → 소등. 1등이 들어오면 나머지는 30초 안에 들어와야 해요.
5. **포디움(8초)**: 1~3등 카트가 패독의 시상대에 올라가고, 모든 사람 화면이 시상대를 비추고, 꽃가루가 날려요. 왼쪽에 결과표. 끝나면 바로 다음 라운드 대기 시간이에요.

### 섹터 타임과 델타

- 한 바퀴를 3구간(섹터)으로 나눠서 구간마다 시간을 보여줘요. 색은 F1처럼 **보라**(이번 세션 전체 최고), **초록**(내 최고), **노랑**(그보다 느림), **회색**(무효 랩)이에요.
- **라이브 델타**: 이번 세션 내 최고 랩과 같은 지점에서 비교해서 `-0.42`(빠름, 초록) / `+0.31`(느림, 빨강)으로 계속 보여줘요. 설정에서 끌 수 있어요.

### 트랙 리밋

- **네 바퀴가 모두** 연석 바깥으로 완전히 나가면 트랙 리밋 위반이에요. 연석은 트랙으로 쳐요. 0.2초 이상 나가 있어야 하고, 스핀해서 천천히 굴러 나간 건(초속 8 studs 미만) 안 쳐요.
- **연습·퀄리파잉**: 그 랩이 삭제돼요(기록·섹터 색 회색, "LAP DELETED").
- **레이스**: 처음 3번은 경고(WARNING 1/3…), 4번째부터 한 번에 **+2초** 페널티가 결과 시간에 더해져요. 짧은 카트 레이스라서 5초 대신 2초로 했고, `Config.Race.TrackLimitPenalty`, `TrackLimitWarnings`로 바꿀 수 있어요.

### 슬립스트림

앞 카트 바로 뒤(7~34 studs, 좌우 4.5 studs 안)를 따라가면 공기 저항이 최대 45% 줄고 최고 속도가 약 +5 km/h 올라가요. 속도계 위에 SLIPSTREAM이 떠요. 직선에서 추월하기 좋게 하려는 거예요.

## 화면(HUD) 크기

HUD는 글자가 선명하게 보이도록 픽셀 단위로 딱 맞는 배율만 써요: 보통 화면(약 1100×620 이상)은 1배, 2560×1440 이상은 2배, 그보다 작은 화면(폰·작은 창)만 줄여요. 시간 숫자는 굵은 고정폭 글꼴(Roboto Mono Bold)을 고정 크기로 써서 숫자가 바뀌어도 흔들리거나 흐려지지 않아요.

## 설정 메뉴

화면 왼쪽 아래 **SETTINGS** 버튼(모바일은 왼쪽 위 버튼 줄)으로 열어요. `<` `>`로 바꾸면 바로 적용되고, 계정에 저장돼서 다음에 들어와도 그대로예요.

| 항목 | 값 | 기본 |
|---|---|---|
| Master / Engine / Effects volume | 0~100% | 100 / 80 / 80% |
| Steering speed (keys) | 키보드·터치 핸들이 도는 빠르기 60~160% | 100% |
| Steering assist | 조향 보조 켬/끔 | 켬 |
| Starting camera | Cockpit / Near / Far | Near |
| Speed units | KMH / MPH | KMH |
| Minimap | Off / Small / Normal / Large | Normal |
| Live lap delta | 켬/끔 | 켬 |

## 소리

`sounds/` 폴더에 이 게임용으로 직접 합성한 소리 20개가 있어요(엔진 루프 4개 추가)(녹음·샘플 없이 `sounds/make_sounds.py`로 만든 거라 저작권 걱정 없어요). ★ = 이번에 새로 만들었거나 바뀐 파일이에요(예전 9개를 이미 올렸다면 ★만 올리면 돼요).

| 파일 | 넣을 곳 (`Shared/Config` → `Config.Audio`) | 용도 |
|---|---|---|
| engine_loop.ogg | `EngineSoundId` | 예전 엔진(하나의 3000 rpm 루프를 rpm에 따라 늘였다 줄임). 아래 새 엔진 4개를 올리기 전까지만 쓰여요 |
| ★ engine_1700.ogg | `EngineLayers[1].id` | 새 엔진: 공회전(액셀 뗀 저rpm) |
| ★ engine_2800.ogg | `EngineLayers[2].id` | 새 엔진: 풀 스로틀 2800 rpm (출발, 저속) |
| ★ engine_4000.ogg | `EngineLayers[3].id` | 새 엔진: 풀 스로틀 4000 rpm (고속) |
| ★ engine_off.ogg | `EngineOffSoundId` | 새 엔진: 액셀 뗀 고rpm(엔진 브레이크, 부글거림·팝) |
| skid_loop.ogg | `SkidSoundId` | 타이어 미끄러지는 소리 |
| ★ offroad_loop.ogg | `OffroadSoundId` | 바퀴가 자갈·잔디·물에 들어갔을 때 덜컹거림 + 자갈 튀는 소리 (속도에 따라 커짐) |
| ★ kerb_loop.ogg | `KerbSoundId` | 연석 밟을 때 드르르 (속도에 맞춰 빨라짐) |
| bump.ogg | `BumpSoundId` | 카트끼리 범퍼 부딪힘 |
| beep.ogg | `BeepSoundId` | 출발 신호 빨간 불 하나마다 |
| go.ogg | `GoSoundId` | 소등(출발) |
| lap.ogg | `LapSoundId` | 랩 완료 |
| ★ best.ogg | `BestSoundId` | 개인 최고 기록 / 세션 최고 랩 / 트랙 레코드 (없으면 lap 소리) |
| ★ warning.ogg | `WarningSoundId` | 트랙 리밋 경고 (없으면 beep) |
| ★ penalty.ogg | `PenaltySoundId` | 랩 삭제 / 시간 페널티 (없으면 beep) |
| ★ flag.ogg | `FlagSoundId` | 퀄리파잉 시작 / 체커기 (에어혼) |
| finish.ogg | `FinishSoundId` | 레이스에서 내가 체커기 받을 때 짧은 팡파르 |
| ★ podium.ogg | `PodiumSoundId` | 결과·포디움 나올 때 환호와 박수 |
| click.ogg | `ClickSoundId` | 버튼 |
| crowd_loop.ogg | `CrowdSoundId` | 관중석마다 웅성거림 |

**지금 상태**: 16개 모두 올려서 ID를 `Config.Audio`에 넣어 뒀어요(2026-10-27 업로드). 그 뒤 휴대폰 스피커에서 엔진이 거의 안 들려서 engine_loop / kerb_loop / offroad_loop / bump 4개를 다시 만들었어요(저음 위주였던 소리를 휴대폰 스피커가 낼 수 있는 대역으로). 이 4개도 다시 올려서 새 ID로 바꿔 뒀어요. 지금 16개 ID 모두 최신 파일이에요.

**음량**: `python3 sounds/mix_levels.py`가 플레이어가 듣는 대로(Roblox 볼륨 모델, 카메라 거리, 휴대폰·노트북·헤드폰 스피커, A-가중치) 소리마다 엔진 대비 몇 dB인지 계산해요. 지금 값: 풀 스로틀 엔진이 가장 큰 지속음, 미끄러짐 −6 dB, 연석·자갈 −4~5 dB, 가까운 관중석 −15 dB, 레이스 알림음 0~+3 dB.

**새 엔진 소리 (2026-10-29)**: 예전 엔진은 3000 rpm 루프 하나를 0.53~1.4배로 늘였다 줄여서, 배기관·머플러 울림까지 같이 오르내리는 장난감 같은 소리였고 액셀을 떼도 같은 소리였어요. 새 엔진은 단기통 4행정의 배기 펄스 → 배기관 반사 → 머플러 → 배기구 방사를 흉내 내서 합성한 루프 4개를 rpm과 액셀에 따라 섞어요(`Shared/EngineAudio`): 액셀을 밟으면 2800/4000 rpm 풀 스로틀 루프, 떼면 저rpm은 공회전, 고rpm은 overrun(약하고 들쭉날쭉한 폭발, 가끔 "팝"). 각 루프는 조금만 늘이고 줄여서 울림은 제자리에 있고 폭발 간격만 바뀌어요. **새 루프 4개의 ID를 모두 넣기 전까지는 예전 엔진이 그대로 나와요.** 올리기 전에 `python3 sounds/engine_preview.py 폴더`로 예전/새 엔진으로 한 바퀴 달리는 소리를 mp3로 들어볼 수 있어요.

**올리는 법**: Studio → View → Asset Manager → Bulk Import(또는 Import) → `sounds/*.ogg` 선택 → 올라간 오디오를 오른쪽 클릭 → Copy Asset ID → `Config.Audio`의 해당 칸에 `"rbxassetid://숫자"` 형태로 붙여넣기. 비어 있는 칸은 무음이에요. 오디오 업로드는 Roblox 계정 인증(전화번호 등)이 필요할 수 있어요.

## 조작

| 동작 | 키보드 | 게임패드 | 모바일 |
|---|---|---|---|
| 가속 / 브레이크 | W / S (정지 상태에서 S 유지 = 후진) | RT / LT | GAS / BRK 버튼 |
| 조향 | A / D | 왼쪽 스틱 | ◀ ▶ 버튼 |
| 트랙 복귀 | R | Y | R 버튼 |
| 카메라 줌 (멀리 ↔ 1인칭 콕핏) | 마우스 휠 | D-pad 위 / 아래 | 두 손가락 핀치 |
| 카메라 프리셋 (콕핏 / 가까이 / 멀리) | C | X | CAM 버튼 |
| 카메라 돌리기 (3인칭: 놓아도 그 자리 유지 / 1인칭: 놓으면 정면 복귀) | 마우스 오른쪽 버튼 누른 채 드래그 | 오른쪽 스틱 | 빈 화면을 한 손가락으로 드래그 |
| 카메라 다시 뒤로 | V | R3 (오른쪽 스틱 누르기) | |
| 카트 타기 / 내리기 (연습 중) | K | Select | 화면 버튼 |
| 관전 대상 바꾸기 | Q / E | D-pad | 화면 버튼 |
| 트랙 패널 열기 / 닫기 (대기 시간: 투표·길이·READY) | M | | TRACK / VOTE 버튼 |
| 설정 | | | SETTINGS 버튼 |
| 트랙 고르기 (연습: 바로 변경, 대기 시간: 투표) | 카드 클릭 또는 1~9 | B (다음 트랙) | 카드 터치 |

뒤집히거나 맵 밖으로 떨어지면 2초 뒤 자동으로 트랙에 복귀해요. 복귀 지점에 다른 카트가 있으면 옆이나 조금 뒤의 빈자리에 놓여요. 그래도 겹치면(둘이 동시에 복귀하는 등) 겹침이 풀릴 때까지 그 카트는 반투명 고스트가 돼서 부딪히지 않아요(`Config.Race.ResetClear`, `ResetGhostTime`).

### 1인칭 콕핏 시점

휠을 계속 당기면 가장 가까운 추격 거리(6 studs) 다음에 운전석 시점으로 바뀌어요. 레이싱 심처럼:

- 카메라가 카트에 고정돼서 운전자 눈 위치에 있어요. 아래쪽에 스티어링 휠 윗부분과 장갑 낀 손(10시 10분)이 보이고, 손이 휠과 같이 돌아가요.
- 코너에서는 머리가 바깥쪽으로, 브레이크 땐 앞으로 살짝 쏠려요(g-force, 가속도에 따른 쏠림). 모든 움직임은 critically damped spring(임계 감쇠 스프링, 튕기지 않고 딱 멈추는 스프링)으로 부드럽게 해서, 핸들을 풀 때 화면이 반대로 튕기지 않아요.
- 화면 기울기는 카트 롤·피치의 30%만 보여줘요(수평 안정화). `TiltFollow`를 0으로 하면 수평선이 완전히 고정돼요.
- 코너 안쪽을 미리 보는 look to apex는 기본으로 꺼져 있어요(핸들을 풀 때 시선이 되돌아오는 게 반동처럼 느껴져서). `LookIntoTurn = 0.1`로 켤 수 있어요.
- 내 아바타의 머리·팔·액세서리는 나한테만 숨겨지고, 다른 사람 화면에서는 그대로 보여요.
- 시점 위치, 아래로 숙인 각도, 시야각(FOV), 쏠림 정도는 `Config.Camera.Cockpit`에서 바꿀 수 있어요.

## 물리 (리얼 쪽으로)

- 스케일: 1 stud = 0.28 m, 그래서 studs/s ≈ km/h. 카트에만 실제 중력(9.81 m/s²)이 걸리도록 Roblox 기본 중력과의 차이를 상쇄해요. 캐릭터는 원래 중력 그대로예요.
- Raycast suspension(레이캐스트 서스펜션, 바퀴마다 아래로 광선을 쏴서 스프링·댐퍼 힘을 계산) + anti-roll bar(안티롤 바, 좌우 기울어짐 억제)
- Tyre model(타이어 모델): slip angle(슬립 각, 바퀴 방향과 실제 진행 방향의 차이)에 Pacejka magic formula(파세이카 공식) 적용, friction circle(마찰원, 가속·제동과 코너링이 같은 접지력을 나눠 씀), load sensitivity(하중 민감도)
- 노면별 접지력: 각 파트의 `Surface` 속성으로 정해요. 아스팔트 > 연석 > 런오프 > 인조 잔디 > 잔디·자갈. 잔디·자갈은 구름 저항이 커서 확 느려져요.
- 질량은 작은 코어 블록 하나에만 있고(실제 카트+드라이버 수준의 관성), 충돌은 무게 없는 hitbox(히트박스)가 맡아요. 그래서 방향 전환이 가벼워요.
- 바퀴마다 광선 2개를 쏴서 가까운 쪽을 써요. 도로 조각 사이 이음매로 광선이 빠져서 덜컹거리는 걸 막아요.
- Rear-wheel drive(후륜 구동), 엔진 브레이크, 앞뒤 브레이크 배분 75:25, 공기 저항
- 가속은 야외용 렌탈 카트 기준이에요: 약 15마력 단기통 4행정 엔진(Honda GX390급), 기어 하나, 카트+드라이버 약 250 kg.
  - 저속에서는 엔진 토크(torque, 회전력)가 한계라서 약 0.24 g로 밀어줘요(토크 26~30 Nm × 기어비 약 3.1 ÷ 바퀴 반지름 0.14 m).
  - 약 60 km/h부터는 출력(power, 일률)이 한계라서 속도가 오를수록 가속이 줄고(바퀴에서 약 10 kW), 고속에서는 공기 저항이 그 대부분을 먹어요.
  - 0→50 km/h 6.8초, 0→80 km/h 13.4초, 혼자서는 약 95 km/h까지만 올라가요. 앞 카트 뒤에 붙으면(슬립스트림) 공기 저항이 줄어서 100 km/h를 넘을 수 있어요.
  - 그래서 코너를 5 km/h 더 빨리 빠져나오면 700 studs 직선 끝에서도 0.3초 앞서요(예전 값에서는 0.15초, 최고 속도 제한에서 차이가 사라졌어요).
  - 예전 값(19 / 860)은 약 23마력짜리 카트 수준이라 직선마다 금방 최고 속도에 닿았어요.
- 감속: 가속 페달만 떼면(coasting, 타력 주행) 90 km/h에서 약 0.17 g라서 90→50 km/h에 약 10초 걸려요. 키보드 S는 페달처럼 약 0.25초에 걸쳐 밟혀서(`Config.Pedals`), 살짝 톡 치면 80→72 km/h 정도만 줄고, 끝까지 밟으면 최대 약 1.3 g로 90→0 km/h 2.2초예요. W도 약 0.14초에 걸쳐 밟혀요. 게임패드 트리거는 그대로 전달돼요.
- 최대 횡가속도 약 1.7 g, 최소 회전 반경 30 km/h에서 약 15 studs
- 키보드 조향 부드럽게 하기(input smoothing, 입력 다듬기): 방향키를 누르면 핸들이 한 번에 꺾이지 않고 서서히 돌아가요. 저속에서는 약 0.2초, 70 km/h 이상에서는 약 0.33초 만에 끝까지 돌아가요. 키를 떼면 약 0.2초 만에 가운데로 돌아오고, 좌↔우로 바꿀 때는 0.1초 만에 가운데를 지나가서 카운터 스티어(역조향)는 빨라요. 게임패드 스틱은 아날로그라서 거의 그대로 전달하고, 가운데 근처만 더 섬세해요. 설정은 `Config.Steering`.
- 뒤 타이어는 폭이 넓어서 cornering stiffness(코너링 강성, 작은 슬립 각에서 그립이 올라오는 빠르기)가 앞보다 1.6배 커요(`Wheels[].stiffness`). 그래서 핸들을 빨리 꺾어도 뒤가 휘청이지 않고 바로 자리를 잡아요.
- 조향 보조는 뒷바퀴가 그립 한계를 넘어 미끄러지기 시작하면 앞바퀴를 그만큼 덜 꺾어서 슬라이드를 잡아줘요(`Kart.AssistCatch`). 트레일 브레이킹(코너 진입하며 브레이크)에서 스핀하지 않게 해요.
- 조향 보조는 타이어 그립 곡선을 거꾸로 계산해서, 입력 50%면 그립의 약 50%를 쓰게 해요. 그래서 키를 누를 때 회전이 입력에 비례해 늘고, 놓을 때도 비례해서 줄어요. 예전에는 처음 절반에 회전이 몰리고 마지막에 확 펴졌어요.
- 타이어 그립은 슬립 각 약 7°에서 최대이고, 그 이상 꺾으면 오히려 줄어요(20°에서 약 84%). 그래서 앞바퀴를 과하게 꺾으면 실제처럼 언더스티어(앞이 바깥으로 밀림)가 나요. 예: 조향 보조를 끈 상태에서 50 km/h로 풀락을 하면 1.24 g, 적당히(40%) 꺾으면 1.76 g.
- Steering assist(조향 보조): 속도가 붙으면 입력이 앞바퀴 슬립 각을 정하고, 손을 떼면 바퀴가 진행 방향을 따라가서 뒤가 미끄러질 때 자동 counter-steer(카운터 스티어, 역조향)가 돼요. 물리 자체는 그대로고 핸들만 도와줘요. `Config.Kart.SteerAssist = false`면 순수 조향이에요.
- 프레임마다 240 Hz로 내부 예측을 돌려서 평균 힘을 넘겨요. 그래서 폰처럼 20~30 fps에서도 안정적이에요.

### 카트끼리 부딪히기 (범퍼)

카트는 렌탈 카트처럼 검은 플라스틱 범퍼가 네 바퀴 바깥을 한 바퀴 감싸고 있어서, 바퀴끼리는 절대 닿지 않고 범퍼끼리만 부딪혀요.

- Roblox 기본 충돌은 카트끼리 꺼 두었어요. 온라인에서는 상대 카트가 늦게 보여서, 기본 충돌을 쓰면 카트가 튀어 오르거나 엉뚱하게 튕겨요.
- 대신 각자의 컴퓨터가 범퍼 모양(둥근 직사각형, `Config.Kart.Bumper`)끼리 얼마나 겹쳤는지 계산해서, 스프링처럼 밀어내는 힘과 문질러지는 마찰을 줘요. 이 계산은 240 Hz 물리 예측 안에서 해요. 힘은 수평으로만 줘서 카트가 뜨거나 뒤집히지 않아요.
- 겹친 만큼 밀어내는 힘(spring, 스프링)에는 상한이 있어요. 그래서 리셋이나 렉 때문에 깊이 겹쳐도 천천히 떨어져요. 세게 부딪힐 때는 다가오는 속도에 비례하는 힘(damping, 감쇠)이 충격을 받아줘요.
- 상대 카트는 (상대 핑 + 내 핑)의 절반 + 0.05초만큼 앞으로 당겨서 계산해요(extrapolation, 외삽). 서버가 2초마다 각 플레이어의 핑을 알려줘요. 이걸 안 하면 0.15초 지연에서 4 studs나 떨어져 있는데 "유령 충돌"이 생겨요.
- **contact echo(충돌 메아리 보정)**: 내 화면의 상대 카트는 지연 때문에 "아직 안 밀린" 상태로 보여요. 그래서 예전에는 부딪히는 동안 양쪽 컴퓨터가 계속 밀어내서, 0.1초 지연이면 반발 계수가 1을 넘었어요(부딪히기 전보다 더 빨리 튕겨 나가는 범퍼카). 카트 질량이 모두 같으니 상대는 내가 받은 힘의 정반대를 받았을 거예요. 그래서 최근 지연 시간 동안 내가 받은 범퍼 속도 변화를 상대 카트 속도·위치에서 빼서 계산해요(`KartPhysics.echoApply`). 0.1초 지연 추돌 반발 1.17 → 0.27(지연 없을 때와 같음). `luau tests/tools/lagbumps.luau`로 지연별로 비교해요(`-a off` = 보정 없이).
- 테스트로 확인한 결과:
  - 55 km/h로 30 km/h 카트를 뒤에서 박으면: 앞 카트는 44 km/h로 밀려나고, 뒤 카트는 38 km/h로 느려져요. 범퍼는 0.7 studs(약 20 cm) 눌리고 살짝 튕겨요(반발 계수 0.26).
  - 30 km/h끼리 정면충돌하면: 둘 다 7 km/h로 튕겨 나가요.
  - 나란히 달리다 밀면: 옆 카트가 밀려나지만 스핀은 안 해요.
  - 뒤 모서리를 치면: 맞은 카트가 돌아요(초당 약 230°).
  - 어떤 경우에도 카트가 뜨지 않아요.
- **세게 부딪혀도 안 붙어요**: 예전엔 범퍼 힘에 상한이 있어서 90 km/h로 옆을 들이받으면 범퍼가 3 studs나 파고들어 두 카트가 한 몸처럼 붙어 버렸어요. 이제 범퍼가 0.8 studs 넘게 눌리면 프레임에 닿은 것처럼 훨씬 단단해져서(파고드는 동안만, 그래서 더 튕기지는 않아요) 1.3 studs 안에서 멈추고 바로 떨어져요(`luau tests/tools/hardhits.luau`).

## 퍼블리시 전에 할 일

1. Game Settings → Security → **Enable Studio Access to API Services** 켜기 (승수, 개인 최고 랩, 트랙 레코드 저장). 꺼져 있어도 게임은 돌아가고 저장만 안 돼요.
2. Game Settings → Places → **Max Players**: 12 추천 (그리드 12칸, 빠른 매칭도 최대 12명).
3. 소리: 위의 "소리" 순서대로 `sounds/` 폴더 파일을 올리고 ID를 `Config.Audio`에 넣어요. 안 넣으면 무음으로 돌아가요.
4. **매칭·방·서버 이동은 퍼블리시한 게임에서만 돼요.** 예약 서버(ReserveServer)로 텔레포트하는 건 Studio에서 테스트할 수 없어요(Roblox 제한). 같은 플레이스 안에서만 이동하니까 따로 켤 설정은 없어요. 퍼블리시 후 친구와(또는 계정 두 개로) 들어가서 RACE / PRIVATE ROOM을 확인해 보세요. MemoryStore(대기열·방 코드)도 따로 설정할 건 없어요.
5. 서버 이동을 하면 새 서버에서 저장된 데이터를 다시 읽어요. 그래서 떠나기 직전에 그 플레이어의 기록을 저장해요(`Stats.saveNow`).

## 튜닝 포인트 (`ReplicatedStorage/Shared/Config`)

| 값 | 의미 | 기본 |
|---|---|---|
| `Kart.DriveAccel`, `PowerPerMass` | 저속 가속(토크 한계, studs/s²) / 출력(가속 = 이 값 ÷ 속도) | 8.5 / 520 |
| `Kart.TopSpeed` | 최고 속도 제한(rev limit, 엔진 회전 한계). 혼자서는 공기 저항 때문에 약 95에서 멈춰요 | 100 |
| `Kart.Mu` | 아스팔트 최대 마찰 계수 | 2.0 |
| `Kart.BrakeAccel`, `BrakeRearBias` | 제동력 / 뒤 배분 | 42 / 0.25 |
| `Kart.EngineBraking`, `DragCoef` | 페달 뗐을 때 엔진 브레이크 / 공기 저항 (클수록 빨리 느려짐) | 0.9 / 0.00055 |
| `Pedals.ThrottleRise`, `BrakeRise` | 키보드 W / S가 끝까지 밟히는 속도 (1/초, 작을수록 부드러움) | 7 / 4 |
| `Steering.RiseLow`, `RiseHigh` | 키를 누를 때 핸들 도는 속도 (저속 / 고속, 풀락/초) | 6.5 / 3.2 |
| `Steering.ReturnLow`, `ReturnHigh`, `Counter` | 놓을 때 / 좌우 전환 때 속도 | 8 / 4.5 / 10 |
| `Kart.AssistCatch` | 뒤가 미끄러질 때 조향 보조가 잡아주는 정도 (0 = 끔) | 1.5 |
| `Kart.PacejkaB`, `PacejkaC` | 타이어 그립 곡선 (최대점·떨어지는 정도) | 12.3 / 1.6 |
| `Kart.SteerLock`, `SteerRate` | 최대 조향각 / 앞바퀴가 실제로 따라가는 최대 속도 (도/초) | 28° / 240 |
| `Kart.SteerAssist`, `SteerAssistSlip` | 조향 보조 / 최대 앞 슬립 각 | true / 8° |
| `Kart.CoreSize`, `Density` | 관성을 정하는 코어 블록 크기 / 밀도 | 2.8×0.6×4.0 / 8 |
| `Kart.Wheels` | 바퀴 위치·크기(radius, width)·접지 | |
| `Surfaces` | 노면별 grip(접지)·roll(구름 저항) 배수 | |
| `Camera.Cockpit.Eye`, `Pitch`, `Fov` | 콕핏 눈 위치 / 숙인 각도 / 시야각 | (0, 3.25, -0.2) / -9° / 72° |
| `Camera.Cockpit.HeadG`, `TiltFollow`, `LookIntoTurn` | g-force 머리 쏠림 / 기울기 반영 비율 / 코너 시선 | 0.045 / 0.3 / 0 |
| `Camera.OrbitPitchMin`, `OrbitPitchMax`, `AutoRecenter` | 3인칭 카메라 높이 범위 / 자동 복귀(초, 0=안 함) | -8° / 80° / 0 |
| `Kart.SteeringWheel` | 스티어링 휠 높이·위치·기울기·크기·조향비 | |
| `Kart.Bumper` | 범퍼 모양(HalfWidth, Front, Rear, Corner)과 충돌 반응: Stiffness·SpringMax(밀어내는 힘과 상한), Damping(충격 흡수), Friction(문질러짐), MaxAccel(최대 힘) | 3.3 / 3.75 / 3.0 / 0.7, 160 / 160, 10, 0.25, 500 |
| `Collision.Lead`, `PingShare`, `LeadMax`, `Range` | 상대 카트를 앞당겨 계산하는 시간(기본 + 핑 비율, 최대) / 검사 거리 | 0.05 s, 0.5, 0.25 s, 40 studs (슬립스트림도 이 거리까지 봐요) |
| `Race.MinPlayers` | 레이스 시작 인원 | 2 |
| `Race.TrackChangeCooldown`, `TrackLoadTimeout` | 연습 중 트랙 변경 간격 / 새 서킷 로딩을 기다리는 최대 시간 | 3 / 20 초 |
| `Race.IntermissionTime`, `ReadyCountdown`, `FinishGrace` | 대기 시간 / 모두 READY일 때 남는 시간 / 1등 뒤 남은 시간 | 20 / 3 / 30 초 |
| `Race.QualiOvertime`, `ResultsTime` | 체커기 뒤 마지막 랩 최대 시간 / 포디움 시간 | 90 / 8 초 |
| `Race.QualiRunUp`, `GhostTransparency` | 1랩 퀄리 출발 위치(출발선 뒤 studs) / 고스트 카트 투명도 | 70 / 0.6 |
| `Lobby.QueueMin`, `QueueWait`, `QueueMax` | 빠른 매칭: 최소 인원 / 그 인원이 모인 뒤 출발까지 / 바로 출발하는 인원 | 2 / 7 초 / 12 |
| `Lobby.RoomDigits` | 방 코드 자릿수 | 4 |
| `Lobby.StudioSolo` | Studio에서는 RACE를 혼자서도 출발 | true |
| `Lobby.FlybySpeed`, `FlybyHeight`, `FlybySide` | 메뉴 뒤 카메라 속도 / 높이 / 옆 거리 | 24 / 16 / 26 |
| `Lobby.LobbyConfirm` | LOBBY 버튼 두 번째 누를 때까지 기다리는 시간 | 3 초 |
| `Race.TrackLimitWarnings`, `TrackLimitPenalty` | 레이스에서 경고 횟수 / 그다음부터 한 번에 더하는 초 | 3 / 2 |
| `Kart.Slipstream` | 슬립스트림 거리(Gap, Length, Width), 공기 저항 감소(DragCut), 최고 속도 추가(TopGain) | 7, 34, 4.5, 0.45, 5 |
| `Settings` | 설정 메뉴 항목과 기본값 | |
| `Audio` | 소리 ID와 볼륨 | |

트랙마다 `Shared/TrackData`에 있는 값:

| 값 | 의미 | Tampines / Silverstone (카트 서킷 3개) |
|---|---|---|
| `Laps` | 기본 랩 수 | 3 / 2 (3) |
| `Lengths` | SHORT / NORMAL / LONG 랩 수 | 2,3,5 / 1,2,3 (2,3,5) |
| `Qualifying` | 퀄리파잉 시간(초) | 120 / 180 (150) |
| `Sectors` | 섹터 경계(랩 길이 비율, 생략하면 3등분) | - |
| `Name`, `Blurb` | 게임에 보이는 이름 / 투표 카드 설명 | |
| `Sky` | 날씨 (`"Sunny"` 낮, `"Morning"` 아침, `"Cloudy"`, `"Sunset"` 해 질 녘, `"Night"` 밤: 지금은 안 씀) | Sunny / Cloudy (Sunny, Morning, Sunset) |
| `Lake` | 펜스 안쪽, 가장 넓은 빈 땅에 호수 | Lakeside |
| `Trees` | 빈 땅(언덕 경사 포함)에 소나무 | Hillside, Suzuka |
| 코너·직선의 `y`, 코너의 `bank` | 그 구간 끝의 도로 높이 / 코너 안쪽으로 기울인 각도(도). 높아진 곳 아래엔 잔디 둑이 자동으로 생겨요. 한 도로가 다른 도로 위를 지나가면(8자) 다리와 옹벽이 자동으로 생기고, 코너 각도 합이 0°여도 돼요 | Hillside, Suzuka |
| `BankSmoothing` | 뱅크가 바뀌는 구간 길이 | 22 (Hillside 40) |
| `TrackLights` | 트랙 옆 가로등 (밤일 때만 켜짐) | Harbour, Yas Marina |
| `PitStyle` | `"Wing"`이면 피트 위 날개 지붕 | - / Wing |
| `CornerBoards` | 코너 이름 보드 | - / 켬 (켬) |
| `Bridge` | 스폰서 브리지를 놓을 직선 이름 | 가장 긴 직선 / Hangar Straight |
| `TrackData.Default`, `Order` | 처음 트랙 / 투표 카드 순서 | Tampines |

트랙 모양은 직선(S)과 코너(A: 반지름·각도)로 그려요. 직선 두 개가 "free"라서 길이가 자동으로 맞춰져 트랙이 닫혀요. 이름이 같은 코너 조각이 연달아 있으면 한 코너로 쳐요(Silverstone의 긴 코너들). 연석·런오프·자갈·방호벽·관중석 위치는 `Shared/TrackLayout`이 코너 모양에서 자동으로 정해요. 새 트랙은 `Tracks`에 하나 더 넣고 `Order`에 id를 추가하면 투표에 나와요.

## 파일 구조

```
src/shared/   (ReplicatedStorage.Shared)
  Config        모든 튜닝 값
  TrackData     트랙 목록과 설계도 (직선/코너), 트랙별 설정
  TrackMath     스플라인, 샘플링, 가장 가까운 지점
  TrackLayout   연석·런오프·자갈·잔디 띠, 방호벽, 피트, 관중석, 마셜, 그리드 위치, 언덕 둑, 입체교차(다리·옹벽)
  KartPhysics   카트 물리 (서버/클라/테스트가 같은 코드)
  RaceProgress  랩·순위·지름길 방지·역주행·섹터·무효 랩·체커기
  TrackLimits   트랙 리밋 판정 (네 바퀴 모두 연석 밖) + 위반 카운터
  SteerFilter   키보드/터치 조향 입력을 속도에 따라 부드럽게
  CockpitRig    1인칭 카메라 (수평 안정화, 머리 쏠림, 스프링)
src/server/   (ServerScriptService.Server)
  init.server   부팅: 서버 역할 확인(로비/연습/레이스/방), 원격 이벤트, 충돌 그룹, 월드 생성, 레이스 시작
  Session       서버 역할 읽기, 예약 서버 만들기, 텔레포트(로딩 화면 문구 포함), Studio에서는 제자리 전환
  Lobby         메뉴 요청 처리: PRACTICE / RACE 대기열 / 방 만들기·들어가기 / LOBBY
  Matchmaker    서버들끼리 같이 쓰는 빠른 매칭 대기열 (2명 + 7초)
  Rooms         방 코드 ↔ 방 서버
  SharedStore   MemoryStore 맵 래퍼 (Studio에서는 메모리 테이블)
  TrackBuilder  도로(삼각형 wedge), 연석, 런오프, 자갈, 잔디, 차선, 결승선, 그리드, 바닥, 둑, 다리 거더·난간·옹벽
  Scenery       트랙별 날씨, 게이트·신호등, 피트·개러지·타워(·Wing 지붕), 관중석, 브리지, 방호벽, 마셜, 코너 보드, 담장
  KartFactory   카트 모델(렌탈 카트: 네 바퀴를 감싸는 범퍼 링, 번호가 달린 높은 노즈, 사이드 포드, 뒷바퀴 가드, 버킷 시트와 패드 달린 롤바, 반투명 연료 탱크, 4행정 엔진·머플러), 탑승, 소유권
  RaceManager   서버 모드별 진행: Lobby / Practice → Intermission(투표·길이·READY) → Qualifying(1랩 고스트) → Grid → Racing → Results(포디움), 방장 선택·START, 섹터 색, 트랙 리밋·페널티, 트랙 전환
  Stats         승수·트랙별 최고 랩·트랙별 레코드·설정 (DataStore)
src/client/   (StarterPlayerScripts.Client)
  Input / KartController / KartVisuals (바퀴·핸들·콕핏 팔) / ChaseCamera (줌·콕핏·둘러보기·포디움) / Hud
  Settings (설정 값) / SettingsMenu (설정 화면) / Sfx (효과음·관중·볼륨 그룹)
  Menu (메인 메뉴·트랙 카드·매칭 대기·방 코드·기록·fly-by 카메라·LOBBY 버튼) / TrackOutline (트랙 모양 그림)
src/first/    (ReplicatedFirst.Loading)
  init.client   로딩 화면 띄우기·진행 바·팁 / LoadingGui (로딩 화면 모양, 메뉴도 서버 이동 때 같이 씀)
sounds/       직접 합성한 효과음 .ogg 20개 + 만드는 스크립트 + 엔진 미리 듣기(engine_preview.py)
tests/        헤드리스 테스트 (Luau CLI)
tools/design/ 서킷 설계·미리보기·홍보 이미지용 파이썬 스크립트 (게임에는 안 들어감, tools/design/README.md)
```

## 테스트 (개발용)

Luau CLI와 Rojo가 있으면 프로젝트 폴더에서:

```bash
luau tests/physics_test.luau     # 물리 + 아홉 트랙 자동 주행 랩(승차감 포함, 60/20 fps) + 뱅크 헤어핀 190개
luau tests/collision_test.luau   # 카트끼리 추돌·정면·측면·T자·모서리·네트워크 지연·저프레임·슬립스트림·다리 위아래 카트·지연 충돌 보정 40개
luau tests/limits_test.luau      # 트랙 리밋 판정·위치 추적·섹터·무효 랩·체커기 22개
luau tests/tools/bumps.luau      # 범퍼 반응 표 (-a "Stiffness SpringMax Damping MaxAccel"로 다른 값 비교)
luau tests/tools/lagbumps.luau   # 네트워크 지연별 추돌·정면·옆 비비기 반발 (-a off = contact echo 없이)
luau tests/tools/hardhits.luau   # 세게 부딪혔을 때 파고든 깊이·붙어 있는 시간 (정면 90+90, T자 90 등)
luau tests/steering_test.luau    # 키보드 조향 램프·언더스티어·키보드로 한 바퀴 15개
luau tests/camera_test.luau      # 1인칭 화면 반동·수평 흔들림·머리 쏠림 10개
luau tests/tools/turnin.luau     # 키를 눌렀을 때 핸들·요(yaw) 반응 표 (스무딩 켬/끔 비교)
luau tests/race_test.luau        # 랩·순위(페널티 포함)·지름길 18개
luau tests/layout_test.luau      # 아홉 서킷 배치 + 언덕·둑 + 도로 접힘 + Suzuka 다리(높이·옹벽·둑) + 피트 위치(반시계 서킷은 오른쪽) 185개
luau tests/tools/crossing.luau -a Suzuka   # 입체교차: 다리 구간, 다리 밑 높이, 옹벽 위치·높이
luau tests/tools/ride.luau -a "Hillside 60"   # 승차감: 한 바퀴 동안 차체 떨림(피치·롤 흔들림) 측정, plain = 예전 도로와 비교
luau tests/tools/speedmap.luau -a Hillside > hs.csv && python3 tests/tools/speedmap.py hs.csv hs.png   # 자동 주행 속도 지도(코너별 최저 속도, 높이, 스로틀·핸들) — 코너 설계용
python3 tests/mock/gen.py globalTypes.d.luau && luau tests/sound_test.luau # 엔진 rpm(공회전·클러치·속도), 잔디 덜컹거림, 연석 드르르 14개
python3 tests/mock/gen.py globalTypes.d.luau && luau tests/touch_test.luau # 모바일 터치: 손가락이 버튼 밖에서 떼져도 버튼이 풀리는지, 카메라가 혼자 돌지 않는지 13개
python3 tests/mock/gen.py globalTypes.d.luau && luau tests/e2e_test.luau   # 실제 스크립트로 연습(섹터·델타·트랙 리밋) + 설정 메뉴·소리 + 카메라 + 범퍼 + 트랙 변경 + 길이 투표·READY·1랩 고스트 퀄리파잉·그리드·레이스(경고·페널티)·포디움 + 트랙 변경 로딩(캐릭터 고정·로딩 화면) + Silverstone 레이스 + 아침 서킷·밤 서킷 없음 + 언덕 서킷(둑·구멍 검사, 언덕 주행) + 새 효과음(개인 최고·경고·페널티·깃발·포디움) + HUD 글자 선명도 + 같이 리셋한 카트 겹침 방지·리셋 고스트 297개 (약 4분)
python3 tests/mock/gen.py globalTypes.d.luau && luau tests/lobby_test.luau # 로비 메뉴·fly-by, 로딩 화면, PRACTICE 서버 이동, RACE 대기열(2명+7초, 다른 서버 대기자), 방 코드, 실패 처리, 연습 서버, 방 대기실(슬롯·READY·방장 트랙/길이·START 조건·KICK·재입장 막기·레이스 후 대기실 복귀·LEAVE), Studio 제자리 전환·KICK 166개 (약 4분)
luau tests/tools/dump_gui.luau > gui.txt && python3 tests/tools/render_gui.py gui.txt out/  # 메뉴·트랙 카드·방 코드·매칭·기록·로딩 화면·방장 HUD를 PC(1280×720)와 폰(844×390) 크기로 그림 (gen.py 먼저)
python3 sounds/mix_levels.py     # 소리별 들리는 크기(휴대폰·노트북·헤드폰, 엔진 대비 dB)
python3 sounds/make_sounds.py    # 효과음 다시 만들기 (numpy, scipy, ffmpeg; 이름을 주면 그것만: engine flag ...)
luau tests/tools/agility.luau    # 속도별 회전 반경·횡가속도 표
luau tests/tools/decel.luau      # 페달 뗐을 때 / 키보드 브레이크 / 코너 감속 표
luau tests/tools/accel.luau      # 0-50/80 km/h, 속도별 가속, 코너 탈출 5 km/h 차이가 직선 끝까지 남는 정도, 슬립스트림 (-a "DriveAccel PowerPerMass [DragCut]"로 비교)
luau tests/tools/laps.luau       # 모든 트랙 자동 주행 랩타임·최고 속도·풀 스로틀 비율 (-a로 엔진 값 비교)
luau tests/tools/bank.luau       # 반지름 12.6 m 헤어핀을 평평할 때와 뱅크 8/12/15°일 때 몇 km/h로 도는지
luau tests/tools/dump_world.luau -a Silverstone > world.txt && python3 tests/tools/render.py world.txt previews   # 미리보기 그림 (-a 생략 = 첫 트랙, PODIUM_ONLY=1 = 시상대만)
luau tests/tools/dump_track.luau -a Silverstone    # 트랙 샘플 CSV
rojo build default.project.json -o build/A1KartRacing.rbxlx
```

`e2e_test`는 Roblox API 정의로 검증하는 mock 런타임에서 실제 서버·클라이언트 스크립트를 돌려요. Studio에서 직접 돌려본 건 아니라서, Output 창에 빨간 에러가 뜨면 그 줄을 알려주세요.

## 데이터 출처

Silverstone과 Suzuka 레이아웃은 [TUMFTM racetrack-database](https://github.com/TUMFTM/racetrack-database)(LGPL-3.0, OpenStreetMap 기반)의 중심선에 직선·원호를 맞춰서 만들었어요. Suzuka의 높이는 일본 국토지리원(GSI)의 5 m 레이저 측량 수치표고모델 값을 랩 50 m 간격으로 모은 고도 프로필을 썼어요.

Catalunya, Zandvoort, Yas Marina 레이아웃은 [bacinger/f1-circuits](https://github.com/bacinger/f1-circuits)(MIT, OpenStreetMap 기반 GeoJSON)의 중심선을 썼어요. 높이는 Copernicus DEM GLO-30을 썼어요: © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.
