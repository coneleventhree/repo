--!strict
-- 게임 전체가 공유하는 튜닝 값.
-- 월드 좌표는 대략 미터 단위이며, x는 오른쪽, y는 위쪽이 + 방향이다. 바닥은 y = 0.

local Config = {}

-- 화면에 보이는 월드 영역 (16:9)
Config.VIEW_WIDTH = 16
Config.VIEW_HEIGHT = 9
Config.VIEW_BOTTOM = -0.9 -- 화면 아래 끝의 월드 y

-- 코트
Config.NET_X = 8
Config.NET_HEIGHT = 1.55
Config.COURT_HALF_LENGTH = 6.7 -- 네트 ~ 엔드라인 (실제 규격 13.4m / 2)
Config.SHORT_SERVICE_DIST = 1.98 -- 네트 ~ 숏 서비스 라인
Config.WALL_MARGIN = 0.45 -- 선수가 움직일 수 있는 화면 끝 여백

-- 선수
Config.PLAYER_SPEED = 7
Config.GROUND_ACCEL = 70
Config.AIR_ACCEL = 35
Config.PLAYER_GRAVITY = 28
Config.JUMP_VELOCITY = 8.2
Config.PLAYER_HALF_WIDTH = 0.35

-- 스윙과 타격 판정 (선수 발 위치 기준, x는 선수가 바라보는 방향이 +)
Config.SWING_DURATION = 0.3 -- 애니메이션 길이
Config.SWING_ACTIVE = 0.18 -- 스윙 시작 후 타격이 가능한 시간
Config.SWING_COOLDOWN = 0.1
Config.HIT_ZONE_BACK = -0.55
Config.HIT_ZONE_FRONT = 1.45
Config.HIT_ZONE_LOW = 0.25
Config.HIT_ZONE_HIGH = 2.75
-- 스윗 스팟은 몸 앞쪽의 세로 선분 (허리 ~ 머리 위). 여기서 멀어질수록 샷 품질이 떨어진다.
Config.SWEET_SPOT_X = 0.6
Config.SWEET_SPOT_LOW = 1.0
Config.SWEET_SPOT_HIGH = 2.3
Config.SWEET_RADIUS = 1.4 -- 이 거리만큼 스윗 스팟에서 벗어나면 품질 0
Config.FAST_SHOT_SPEED = 12 -- 이보다 빠르게 날아오는 셔틀은 받아치기 어려워 품질이 떨어진다
Config.NET_REACH = 0.2 -- 네트 너머로 라켓이 닿는 거리

-- 셔틀콕 (중력 + 속도 제곱에 비례하는 공기 저항)
Config.GRAVITY = 12
Config.TERMINAL_VELOCITY = 9
Config.DRAG = Config.GRAVITY / (Config.TERMINAL_VELOCITY * Config.TERMINAL_VELOCITY)
Config.SHUTTLE_SUBSTEPS = 4

-- 샷
Config.SMASH_MIN_HEIGHT = 2.55 -- 이 높이 이상에서 점프 중 강타하면 스매시
Config.LOW_CONTACT_HEIGHT = 1.0 -- 이 높이 아래에서 치면 언더핸드 샷
Config.SMASH_SPEED = 33
Config.SERVE_CONTACT_HEIGHT = 1.0

-- 경기 규칙 (랠리 포인트제)
Config.POINTS_TO_WIN = 11
Config.WIN_BY = 2
Config.MAX_POINTS = 15 -- 듀스가 길어지면 이 점수에서 끝
Config.POINT_PAUSE = 1.6 -- 득점 후 다음 서브까지 대기 시간
Config.SERVE_TIMEOUT = 7 -- 서브를 안 하면 자동으로 하이 서브

-- 시뮬레이션 / 네트워크
Config.TICK = 1 / 60
Config.SNAPSHOT_RATE = 30
Config.INTERP_DELAY = 0.1
Config.MAX_LOOKBACK = 0.3 -- 온라인 지연 보정으로 과거를 되돌아보는 최대 시간
Config.REMOTES_FOLDER = "BadmintonRemotes"

return Config
