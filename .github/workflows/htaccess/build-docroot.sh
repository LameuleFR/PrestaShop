#!/usr/bin/env bash
# Usage: build-docroot.sh <dir>
# Minimal shop tree. Each file outputs a marker that check.sh looks for; PHP files also print
# request details, checked only when PHP is executed.
set -e
d="$1"
root="$(cd "$(dirname "$0")/../../.." && pwd)"
mkdir -p "$d/webservice" "$d/modules/foo" "$d/upload" "$d/admin-xyz" "$d/admin-api" "$d/img/c" "$d/img/p/1/2/3/4/5/6/7" \
  "$d/themes/classic/assets/css" "$d/themes/classic/assets/fonts" "$d/js/jquery/plugins/fancybox/images"

echo '<?php echo "INDEX uri=", $_SERVER["REQUEST_URI"] ?? "", " qs=", $_SERVER["QUERY_STRING"] ?? "", " modrw=", $_SERVER["HTTP_MOD_REWRITE"] ?? "none"; // INDEX' > "$d/index.php"
echo '<?php echo "WEBSERVICE ", $_SERVER["QUERY_STRING"] ?? ""; // WEBSERVICE' > "$d/webservice/dispatcher.php"
echo '<?php echo "AUTH ", $_SERVER["HTTP_AUTHORIZATION"] ?? "none"; // AUTH' > "$d/auth.php"
echo '<?php echo "MODULE_AJAX pi=", $_SERVER["PATH_INFO"] ?? ""; // MODULE_AJAX' > "$d/modules/foo/ajax.php"
echo 'UPLOADED_FILE' > "$d/upload/file.txt"
cp "$root/upload/.htaccess" "$d/upload/.htaccess"

# Back office and admin API folders come with their own front controller rules
cp "$root/admin-dev/.htaccess" "$d/admin-xyz/.htaccess"
echo '<?php echo "ADMIN pi=", $_SERVER["PATH_INFO"] ?? ""; // ADMIN' > "$d/admin-xyz/index.php"
cp "$root/admin-api/.htaccess" "$d/admin-api/.htaccess"
echo '<?php echo "ADMIN_API pi=", $_SERVER["PATH_INFO"] ?? ""; // ADMIN_API' > "$d/admin-api/index.php"

echo 'P1_JPG' > "$d/img/p/1/1-home_default.jpg"
for ext in jpg jpeg webp png avif; do echo "P12_${ext^^}" > "$d/img/p/1/2/12-home_default.$ext"; done
echo 'P12_NOTYPE' > "$d/img/p/1/2/12.jpg"
echo 'P1234567_WEBP' > "$d/img/p/1/2/3/4/5/6/7/1234567-large_default.webp"
echo 'C3_JPG' > "$d/img/c/3-category_default.jpg"
echo 'C3_THUMB_WEBP' > "$d/img/c/3_thumb-small_default.webp"
echo 'C_DEFAULT_JPG' > "$d/img/c/en-default-category_default.jpg"
echo 'FANCYBOX_PNG' > "$d/js/jquery/plugins/fancybox/images/fancy_close.png"

{ echo 'THEME_CSS'; for _ in $(seq 64); do echo '/* padding so the file is worth compressing */'; done; } > "$d/themes/classic/assets/css/theme.css"
ln -s theme.css "$d/themes/classic/assets/css/link.css"
echo 'FONT_WOFF2' > "$d/themes/classic/assets/fonts/font.woff2"

# Rules written by the merchant, kept above the generated block when the .htaccess is generated again
printf '%s\n' 'RewriteEngine on' 'RewriteRule ^old-url$ /new-url [R=301,L]' > "$d/.htaccess"

echo 'SECRET' > "$d/composer.lock"
echo 'SECRET' > "$d/.env"
echo 'SECRET' > "$d/.gitignore"
