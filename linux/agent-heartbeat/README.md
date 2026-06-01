# agent-heartbeat

Linux에서 `crontab`으로 Claude, Codex, 기타 터미널 에이전트에 주기적인 메시지를 보내는 작은 유틸입니다.

기본 스케줄은 오전 8시부터 5시간 간격입니다.

```cron
0 8,13,18,23 * * *
```

## 구성 파일

```txt
agent-heartbeat.sh
agent-heartbeat.ini.example
smoke-test.sh
```

## 빠른 시작

```bash
cd linux/agent-heartbeat
./agent-heartbeat.sh init-config
```

생성된 설정 파일은 기본적으로 여기에 저장됩니다.

```txt
~/.config/agent-heartbeat/agent-heartbeat.ini
```

## Claude CLI로 5시간마다 hello 보내기

현재 PC에 `claude`가 설치되어 있고 아래 명령이 동작한다면:

```bash
claude -p "hello"
```

설정 파일을 엽니다.

```bash
nano ~/.config/agent-heartbeat/agent-heartbeat.ini
```

기본 파일 로그 target은 끄고, `claude-cli` target을 켭니다.

```ini
[target.local-log]
enabled=false
type=file
path=~/.local/state/agent-heartbeat/messages.log

[target.claude-cli]
enabled=true
type=command
command=claude -p "$AGENT_MESSAGE"
message=hello
```

Cron에서 `claude` 경로를 못 찾을 수 있으니, 현재 셸에서 실제 경로를 확인합니다.

```bash
command -v claude
```

예를 들어 `/home/pado/.local/bin/claude`가 나오면 설정을 이렇게 바꾸면 됩니다.

```ini
command=/home/pado/.local/bin/claude -p "$AGENT_MESSAGE"
```

먼저 수동 실행으로 확인합니다.

```bash
./agent-heartbeat.sh run --target claude-cli --dry-run
./agent-heartbeat.sh run --target claude-cli
```

문제가 없으면 cron을 설치합니다.

```bash
./agent-heartbeat.sh install
crontab -l
```

설치 후 매일 `08:00`, `13:00`, `18:00`, `23:00`에 `claude -p "hello"`가 실행됩니다. 로그는 기본적으로 여기에 남습니다.

```txt
~/.local/state/agent-heartbeat/agent-heartbeat.log
```

## tmux로 이미 떠 있는 세션에 보내기

tmux에서 이미 떠 있는 에이전트 pane에 직접 타이핑하고 싶다면 pane 이름을 확인합니다.

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'
```

그 다음 설정 파일에서 tmux target을 켭니다.

```ini
[target.claude-tmux]
enabled=true
type=tmux
pane=claude:0.0
submit=true
message=5-hour Claude heartbeat ping. Please acknowledge and keep the active session warm.
```

먼저 dry-run으로 확인합니다.

```bash
./agent-heartbeat.sh run --dry-run
```

문제가 없으면 cron을 설치합니다.

```bash
./agent-heartbeat.sh install
```

설치된 cron은 아래 명령으로 확인할 수 있습니다.

```bash
crontab -l
```

## 명령

설정 파일 생성:

```bash
./agent-heartbeat.sh init-config
```

메시지 전송:

```bash
./agent-heartbeat.sh run
```

특정 target만 전송:

```bash
./agent-heartbeat.sh run --target claude-cli
```

일회성 메시지로 전송:

```bash
./agent-heartbeat.sh run --target claude-cli --message "hello"
```

cron 블록 미리보기:

```bash
./agent-heartbeat.sh cron
```

cron 설치:

```bash
./agent-heartbeat.sh install
```

cron 제거:

```bash
./agent-heartbeat.sh remove
```

## Target 타입

`tmux`는 터미널 에이전트 pane에 문자를 입력합니다. `submit=true`이면 Enter까지 보냅니다.

```ini
[target.claude-tmux]
enabled=true
type=tmux
pane=claude:0.0
submit=true
```

`command`는 `AGENT_TARGET`, `AGENT_MESSAGE` 환경 변수를 넣고 셸 명령을 실행합니다.

```ini
[target.claude-cli]
enabled=true
type=command
command=claude -p "$AGENT_MESSAGE"
message=hello
```

```ini
[target.custom-command]
enabled=true
type=command
command=printf '%s\n' "$AGENT_MESSAGE" >> ~/agent-pings.log
```

`file`은 메시지를 파일에 append합니다. 설치 직후 안전한 기본값과 스모크 테스트에 사용합니다.

```ini
[target.local-log]
enabled=true
type=file
path=~/.local/state/agent-heartbeat/messages.log
```

## 스모크 테스트

실제 crontab이나 tmux pane을 건드리지 않고 파서, 전송, cron 출력만 검증합니다.

```bash
./smoke-test.sh
```

## 제거

이 스크립트가 관리하는 cron 블록만 제거합니다.

```bash
./agent-heartbeat.sh remove
```
