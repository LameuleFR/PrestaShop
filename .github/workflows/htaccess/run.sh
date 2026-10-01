#!/usr/bin/env bash
# Usage: run.sh <apache|openlitespeed|litespeed> [classes/Tools.php]
# For every scenario x friendly URLs on/off x cache control on/off x install layout (docroot, subfolder),
# generates the .htaccess, serves it from a container and runs check.sh. Exits 1 on any FAIL.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
server="$1"
tools="$(realpath "${2:-$here/../../../classes/Tools.php}")"
port=8080

case "$server" in
  apache)
    image=htaccess-apache; docroot=/var/www/html; owner=www-data:www-data
    docker build -q -t "$image" - >/dev/null <<'EOF'
FROM php:8.3-apache
RUN a2enmod rewrite headers expires deflate \
 && sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
EOF
    reload() { docker exec "$cid" apache2ctl -k graceful; }
    logs() { docker logs "$cid" 2>&1 | tail -20; } ;;
  openlitespeed|litespeed)
    image="litespeedtech/$server:latest"; docroot=/var/www/vhosts/localhost/html; owner=1000:1000
    reload() { docker exec "$cid" /usr/local/lsws/bin/lswsctrl restart >/dev/null; }
    logs() { docker exec "$cid" tail -20 /usr/local/lsws/logs/error.log; } ;;
  *) echo "Unknown server: $server" >&2; exit 2 ;;
esac

wait_up() {
  for _ in $(seq 60); do
    curl -s -o /dev/null "http://127.0.0.1:$port/" && return 0
    sleep 1
  done
  echo "::error::$server did not answer on port $port"
  logs
  return 1
}

# Servers cache .htaccess files: waits until the combination's own marker rule is served
wait_rules() { # combination number, physical URI
  for _ in $(seq 60); do
    [[ $(curl -s -H 'Host: shop.test' "http://127.0.0.1:$port${2}bench-combo") == "COMBO_$1" ]] && return 0
    sleep 1
  done
  echo "::error::$server did not load the .htaccess of combination $1"
  logs
  return 1
}

cid=$(docker run -d -p "$port:80" "$image") || exit 1
trap 'docker rm -f "$cid" >/dev/null' EXIT
if ! wait_up; then
  # LiteSpeed Enterprise runs on a trial license downloaded at startup, which may be refused
  if [[ $server == litespeed ]] && docker logs "$cid" 2>&1 | grep -qiE 'licen[cs]e.*(invalid|expired|fail|error|denied)|(invalid|expired|fail|error|denied).*licen[cs]e'; then
    echo "::warning::LiteSpeed Enterprise did not get its trial license, checks skipped"
    exit 0
  fi
  exit 1
fi

results="$(mktemp)"
n=0
for scenario in single virtual domains manydomains physicals; do
  for friendly in 1 0; do
    for cache in 1 0; do
      for layout in "docroot:/" "subfolder:/ps/"; do
        name="${layout%%:*}"; phys="${layout#*:}"
        combo="$scenario, friendly URLs=$friendly, cache=$cache, $name install"
        work="$(mktemp -d)"; site="$work/www${phys%/}"
        bash "$here/build-docroot.sh" "$site"
        n=$((n + 1))
        echo "RewriteRule ^bench-combo$ bench-combo-$n.txt [L]" >> "$site/.htaccess"
        echo "COMBO_$n" > "$site/bench-combo-$n.txt"
        if ! php "$here/generate.php" "$tools" "$site/.htaccess" "$scenario" "$phys" "$friendly" "$cache"; then
          echo "::error::$combo: .htaccess generation failed"
          exit 1
        fi
        docker exec "$cid" sh -c "rm -rf $docroot/* $docroot/.[!.]*"
        docker cp "$work/www/." "$cid:$docroot/"
        [[ $scenario == physicals ]] && docker exec "$cid" ln -s . "$docroot${phys}alt"
        docker exec "$cid" chown -R "$owner" "$docroot"
        reload
        wait_rules "$n" "$phys" || exit 1

        echo "::group::$combo"
        bash "$here/check.sh" "http://127.0.0.1:$port" "$scenario" "$phys" "$friendly" "$cache" "$server" | tee "$work/result.txt"
        echo "::endgroup::"
        grep -E '^(FAIL|WARN)' "$work/result.txt" | sed "s|^|$combo: |" >> "$results"
        rm -rf "$work"
      done
    done
  done
done

# Distinct failing requests, in a single annotation per level
summarize() { # FAIL|WARN error|warning
  local lines
  lines=$(grep -E "^[^:]+: $1 " "$results" | sed -E "s/^[^:]+: $1 +//; s/ +got / got /" | cut -c1-160 \
    | sort | uniq -c | sort -rn | sed -E 's/^ *([0-9]+) /[\1 combinations] /')
  [[ -n $lines ]] && echo "::$2 title=$server $1::${lines//$'\n'/%0A}"
}
summarize FAIL error
summarize WARN warning
echo "$(grep -c ': FAIL ' "$results") FAIL, $(grep -c ': WARN ' "$results") WARN"
! grep -q ': FAIL ' "$results"
