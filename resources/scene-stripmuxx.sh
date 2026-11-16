#!/bin/sh
# Scene → StripMuxX: sets StripMuxX's root accent-color to the accent of the Scene theme on screen.
# Register it in Scene → Settings → Scripts. On the first apply it records your own accent-color
# (or that you had none); Scene's Restore puts that back.
#
# StripMuxX draws focus in this accent: the focused border (while borders.active-color is 'accent',
# the default), the minimap's focused tile and viewport, and the shortcut cheat sheet.
CONFIG="${STRIPMUXX_CONFIG:-$HOME/.config/stripmuxx/stripmuxx.toml}"
CLI="${STRIPMUXX_CLI:-/Applications/StripMuxX.app/Contents/MacOS/stripmuxx-cli}"
SAVED="$CONFIG.before-scene"
[ -f "$CONFIG" ] || exit 0

# The root accent-color value, empty when unset. Only keys before the first [table] are root keys.
get_accent() {
  /usr/bin/awk 'BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34) }
    /^[[:space:]]*\[/ { exit }
    /^[[:space:]]*accent-color[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      quote = substr(value, 1, 1)
      if (quote == sq || quote == dq) {
        value = substr(value, 2)
        end = index(value, quote)
        if (end > 0) value = substr(value, 1, end - 1)
      }
      print value
      exit
    }' "$CONFIG"
}

# Rewrites CONFIG through a temporary file so a failure never leaves it half written.
replace_config() {
  tmp="$CONFIG.scene.$$"
  if "$@" > "$tmp"; then /bin/cat "$tmp" > "$CONFIG"; fi
  /bin/rm -f "$tmp"
}

# Sets the root accent-color to $1, adding the key at the top of the file when there is none.
set_accent() {
  if [ -n "$(get_accent)" ]; then
    replace_config /usr/bin/awk -v value="$1" 'BEGIN { root = 1 }
      /^[[:space:]]*\[/ { root = 0 }
      root && /^[[:space:]]*accent-color[[:space:]]*=/ { print "accent-color = \047" value "\047"; next }
      { print }' "$CONFIG"
  else
    replace_config sh -c 'printf "accent-color = \047%s\047\n" "$1"; /bin/cat "$2"' sh "$1" "$CONFIG"
  fi
}

remove_accent() {
  replace_config /usr/bin/awk 'BEGIN { root = 1 }
    /^[[:space:]]*\[/ { root = 0 }
    root && /^[[:space:]]*accent-color[[:space:]]*=/ { next }
    { print }' "$CONFIG"
}

if [ "$SCENE_EVENT" = "restore" ]; then
  [ -f "$SAVED" ] || exit 0
  previous=$(/usr/bin/sed -n 's/^accent-color=//p' "$SAVED" | /usr/bin/head -1)
  if [ -z "$previous" ]; then remove_accent; else set_accent "$previous"; fi
  /bin/rm -f "$SAVED"
else
  # Only a plain #RRGGBB is accepted, the one form StripMuxX reads.
  case "$SCENE_ACCENT" in
    \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
    *) exit 0 ;;
  esac
  [ -f "$SAVED" ] || echo "accent-color=$(get_accent)" > "$SAVED"
  set_accent "$SCENE_ACCENT"
fi
"$CLI" reload-config >/dev/null 2>&1 || true
