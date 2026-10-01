#!/usr/bin/env bash
# Usage: check.sh <base URL> <scenario> <physical_uri> <friendly URLs: 1|0> <cache control: 1|0> [server]
# Requests every case the generated .htaccess handles (see generate.php for scenarios) and prints
# OK/FAIL per request. Cases tagged "directive" test response headers set by Apache directives, which
# OpenLiteSpeed ignores in .htaccess files and rewrite rules cannot set: they are reported as WARN on
# that server. Exits 1 on any FAIL.
base="$1"; scenario="$2"; phys="$3"; friendly="$4"; cache="$5"; server="${6:-apache}"
tmp="$(mktemp -d)"
fail=0

# request <host> <path> [request header]: sets $code, $location, $body, $headers
request() {
  local out
  out=$(curl -s -D "$tmp/headers" -o "$tmp/body" -w '%{http_code} %{redirect_url}' -H "Host: $1" ${3:+-H "$3"} "$base$2")
  code=${out%% *}; location=${out#* }
  body=$(head -c 200 "$tmp/body" | tr -d '\0' | tr '\n' ' ')
  headers=$(tr -d '\r' < "$tmp/headers")
}

# report <ok: 0|1> <tag> <description> <got>
report() {
  local result=OK
  if [[ $1 != 1 ]]; then
    if [[ $2 == directive && $server == openlitespeed ]]; then result=WARN; else result=FAIL; fail=1; fi
  fi
  printf '%-4s %-80s got %s\n' "$result" "$3" "$4"
}

# body <host> <path> <marker> [detail] [tag] [request header]: 200 and marker in body;
# detail must also be in body when PHP was executed
body() {
  request "$1" "$2" "$6"
  local ok=0
  [[ $code == 200 && $body == *"$3"* ]] && ok=1
  [[ $ok == 1 && -n $4 && $body != *'<?php'* && $body != *"$4"* ]] && ok=0
  report $ok "$5" "$1$2 => $3${4:+ ($4)}" "$code $body"
}

# status <host> <path> <code regex> [tag]
status() {
  request "$1" "$2"
  local ok=0
  [[ $code =~ ^($3)$ ]] && ok=1
  report $ok "$4" "$1$2 => HTTP $3" "$code"
}

# redirect <host> <path> <location suffix>
redirect() {
  request "$1" "$2"
  local ok=0
  [[ $code =~ ^30 && $location == *"$3" ]] && ok=1
  report $ok '' "$1$2 => redirect to *$3" "$code $location"
}

# not_found <host> <path> [tag]: 404 served by the ErrorDocument (index.php)
not_found() {
  request "$1" "$2"
  local ok=0
  [[ $code == 404 && $body == *INDEX* ]] && ok=1
  report $ok "$3" "$1$2 => HTTP 404 from the ErrorDocument" "$code $body"
}

# header <host> <path> <header regex> <present: 1|0> [tag] [request header]
header() {
  request "$1" "$2" "$6"
  local ok=0 found=0
  grep -qiE "$3" <<< "$headers" && found=1
  [[ $found == "$4" ]] && ok=1
  report $ok "$5" "$1$2 => header $([[ $4 == 1 ]] || echo 'absent: ')$3" "$code $(grep -iE "$3" <<< "$headers" | head -1)"
}

# Cases every shop URL must handle; $2 is the shop base path (physical + virtual URI), $3 its physical URI
shop_cases() {
  local host="$1" p="$2" physical="${3:-$phys}"
  [[ $p == "$phys" ]] && body "$host" "$p" INDEX
  body "$host" "${p}index.php?id_category=3&controller=category" INDEX
  body "$host" "${p}themes/classic/assets/css/theme.css" THEME_CSS
  body "$host" "${p}themes/classic/assets/css/link.css" THEME_CSS
  body "$host" "${p}modules/foo/ajax.php" MODULE_AJAX
  body "$host" "${p}modules/foo/ajax.php/extra" MODULE_AJAX "pi=/extra"
  body "$host" "${p}img/p/1/2/12-home_default.jpg" P12_JPG
  body "$host" "${p}admin-xyz/" ADMIN
  body "$host" "${p}admin-xyz/index.php?controller=AdminLogin" ADMIN
  body "$host" "${p}admin-xyz/index.php/sell/catalog/products" ADMIN "pi=/sell/catalog/products"
  body "$host" "${p}admin-api/index.php/products" ADMIN_API "pi=/products"
  body "$host" "${p}admin-xyz/sell/catalog/products" ADMIN
  body "$host" "${p}admin-api/products" ADMIN_API
  body "$host" "${p}api" WEBSERVICE "url="
  body "$host" "${p}api/products?ws_key=KEY" WEBSERVICE "url=products&ws_key=KEY sn=${physical}webservice/dispatcher.php"
  # uploads are served by a controller that checks access rights
  body "$host" "${p}upload/file.txt" INDEX
  status "$host" "${p}composer.lock" 403
  status "$host" "${p}.env" 403
  status "$host" "${p}.gitignore" 403
  # Merchant rules only see the URI without the virtual part on Apache, which starts a new rewriting pass
  if [[ $p == "$phys" || $server == apache ]]; then
    redirect "$host" "${p}old-url" /new-url
  fi
  if [[ $friendly == 1 ]]; then
    body "$host" "${p}men-clothes?page=2" INDEX "uri=${p}men-clothes?page=2 qs=page=2 modrw=On sn=${physical}index.php"
    body "$host" "${p}3-men" INDEX
    body "$host" "${p}1-home_default/hummingbird.jpg" P1_JPG
    for ext in jpg jpeg webp png avif; do body "$host" "${p}12-home_default/hummingbird.$ext" "P12_${ext^^}"; done
    body "$host" "${p}12/hummingbird.jpg" P12_NOTYPE
    body "$host" "${p}1234567-large_default/hummingbird.webp" P1234567_WEBP
    body "$host" "${p}c/3-category_default/men.jpg" C3_JPG
    body "$host" "${p}c/3_thumb-small_default/men.webp" C3_THUMB_WEBP
    body "$host" "${p}c/en-default-category_default/none.jpg" C_DEFAULT_JPG
    body "$host" "${p}images_ie/fancy_close.png" FANCYBOX_PNG
  else
    status "$host" "${p}12-home_default/hummingbird.jpg" 404
    status "$host" "${p}men-clothes" 404
    not_found "$host" "${p}men-clothes" directive
  fi
}

# Server level behaviors, checked once on the main shop
directive_cases() {
  # Tools::modRewriteActive() relies on it
  body shop.test "${phys}index.php" INDEX "modrw=On"
  body shop.test "${phys}auth.php" AUTH "AUTH Bearer abc" '' 'Authorization: Bearer abc'
  status shop.test "${phys}modules/foo/" '403|404'
  header shop.test "${phys}themes/classic/assets/fonts/font.woff2" '^content-type: font/woff2' 1 directive
  header shop.test "${phys}themes/classic/assets/fonts/font.woff2" '^access-control-allow-origin: \*' 1 directive
  if [[ $cache == 1 ]]; then
    header shop.test "${phys}img/p/1/2/12-home_default.jpg" '^expires: ' 1 directive
    header shop.test "${phys}img/p/1/2/12-home_default.jpg" '^cache-control: .*max-age=' 1 directive
    header shop.test "${phys}themes/classic/assets/css/theme.css" '^etag: ' 0 directive
    header shop.test "${phys}themes/classic/assets/css/theme.css" '^content-encoding: gzip' 1 directive 'Accept-Encoding: gzip'
  fi
}

case "$scenario" in
  single)
    shop_cases shop.test "$phys"
    ;;
  virtual)
    shop_cases shop.test "$phys"
    shop_cases shop.test "${phys}shop2/"
    # Some modules build URLs with the virtual URI twice
    body shop.test "${phys}shop2/shop2/themes/classic/assets/css/theme.css" THEME_CSS
    if [[ $friendly == 1 ]]; then
      body shop.test "${phys}shop2/shop2/12-home_default/hummingbird.jpg" P12_JPG
      redirect shop.test "${phys}shop2" "${phys}shop2/"
      body shop.test "${phys}shop2/" INDEX "uri=${phys}shop2/"
    else
      redirect shop.test "${phys}shop2" "${phys}shop2/index.php"
      redirect shop.test "${phys}shop2/" "${phys}shop2/index.php"
    fi
    ;;
  domains)
    for host in shop.test second.test secure.second.test; do shop_cases "$host" "$phys"; done
    if [[ $friendly == 1 ]]; then
      for host in media1.test media2.test media3.test; do body "$host" "${phys}12-home_default/hummingbird.jpg" P12_JPG; done
      # Shop pages are only served on the shop domains. URLs not requested before on another domain: OpenLiteSpeed
      # caches static files by URL whatever the host.
      status media1.test "${phys}men-clothes" 404
      status unknown.test "${phys}women-clothes" 404
      status unknown.test "${phys}12-home_default/unknown-host.jpg" 404
    fi
    ;;
  manydomains)
    shop_cases shop.test "$phys"
    shop_cases shop400.many-domains.test "$phys"
    ;;
  physicals)
    shop_cases shop.test "$phys"
    shop_cases second.test "${phys}alt/" "${phys}alt/"
    ;;
  *) echo "Unknown scenario: $scenario" >&2; exit 2 ;;
esac
directive_cases

rm -rf "$tmp"
exit $fail
