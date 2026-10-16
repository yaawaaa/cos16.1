#!/system/bin/sh

PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin
export PATH
umask 077

STATE_DIR=/data/adb/bk-kernel
PID_FILE=$STATE_DIR/bk-keyboard-ime.pid
LOG_FILE=$STATE_DIR/bk-keyboard-ime.log
NODE=/sys/devices/platform/soc/soc:xiaomi_keyboard/xiaomi_keyboard_connected

ime_log()
{
	printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

put_show_ime()
{
	settings put secure show_ime_with_hard_keyboard "$1" >/dev/null 2>&1
}

apply_state()
{
	if [ "$1" = 1 ]; then
		put_show_ime 0 || return 1
		ime_log "keyboard attached; hardware keyboard mode"
		return 0
	fi
	put_show_ime 0 || return 1
	put_show_ime 1 || return 1
	ime_log "keyboard absent; touch keyboard"
}

daemon_running()
{
	case "$1" in ''|*[!0-9]*) return 1 ;; esac
	[ -r "/proc/$1/cmdline" ] || return 1
	case "$(tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null)" in
		*bk-keyboard-ime.sh*--daemon*) return 0 ;;
	esac
	return 1
}

mkdir -p "$STATE_DIR" || exit 0

if [ "${1:-}" != --daemon ]; then
	BK_OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
	daemon_running "$BK_OLD_PID" && exit 0
	rm -f "$PID_FILE"
	nohup "$0" --daemon </dev/null >> "$LOG_FILE" 2>&1 &
	exit 0
fi

printf '%s\n' "$$" > "$PID_FILE"
trap 'rm -f "$PID_FILE"; exit 0' EXIT HUP INT TERM
ime_log "started"
BK_LAST=

while :; do
	BK_VALUE=$(cat "$NODE" 2>/dev/null) || BK_VALUE=0
	case "$BK_VALUE" in
		1*) BK_CUR=1 ;;
		*) BK_CUR=0 ;;
	esac

	if [ "$BK_CUR" != "$BK_LAST" ]; then
		if apply_state "$BK_CUR"; then
			BK_LAST=$BK_CUR
		fi
	fi
	sleep 1
done
