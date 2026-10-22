# PHP Hardening Checklist

Run `./scripts/audit.sh` — it should exit 0 with no fails. Use the items
below to decide *what* to tighten further.

## Version & patching
- [ ] Track the latest security release of your PHP branch (8.1 / 8.2 / 8.3 / 8.4)
- [ ] Patch cadence: at least quarterly, and within 7 days of a CVE fix
- [ ] Pin the image tag (e.g. `php:8.4.27-fpm`), not `php:8-fpm`
- [ ] `composer audit` in CI (application dependencies)

## Information disclosure
- [ ] `expose_php = Off` (no `X-Powered-By`)
- [ ] `display_errors = Off`
- [ ] `display_startup_errors = Off`
- [ ] Web server banner hidden (`ServerTokens Prod`, nginx `server_tokens off;`)

## Remote code / file fetch
- [ ] `allow_url_fopen = Off`
- [ ] `allow_url_include = Off`
- [ ] `disable_functions` covers exec/shell_exec/system/passthru/proc_open/popen
- [ ] `open_basedir` set per pool
- [ ] FPM `security.limit_extensions = .php`
- [ ] Upload dir cannot execute PHP (`try_files $uri =404` + deny)

## Sessions
- [ ] `session.use_strict_mode = 1`
- [ ] `session.use_only_cookies = 1`
- [ ] `session.cookie_httponly = 1`
- [ ] `session.cookie_secure = 1` (or a custom `__Host-` prefix name)
- [ ] `session.cookie_samesite = Strict` (or `Lax` if a flow requires it)

## Transport
- [ ] TLS 1.2+ only
- [ ] HSTS `max-age=31536000; includeSubDomains; preload`
- [ ] HTTP → HTTPS redirect at the edge

## Headers
- [ ] `X-Content-Type-Options: nosniff`
- [ ] `X-Frame-Options: SAMEORIGIN` (or CSP `frame-ancestors`)
- [ ] `Referrer-Policy: strict-origin-when-cross-origin`
- [ ] `Content-Security-Policy` (start in report-only, then enforce)
- [ ] `Permissions-Policy` disables unused features

## php-fpm
- [ ] `clear_env = yes`
- [ ] `chdir` set
- [ ] `request_terminate_timeout` bounded
- [ ] `pm.max_requests` set (mitigates memory leaks)
- [ ] Runs as an unprivileged user (`www-data`), never root

## Container (if applicable)
- [ ] Non-root in `USER` (or FPM workers drop privileges)
- [ ] `read_only: true` rootfs
- [ ] `cap_drop: [ALL]`
- [ ] `no-new-privileges:true`
- [ ] Healthcheck present
- [ ] Secrets via env / mount, never baked into layers

## Application
- [ ] `display_errors` off in prod, `error_reporting` logged not printed
- [ ] Debug mode off (`APP_DEBUG=false`)
- [ ] `APP_KEY` / DB passwords rotated and stored in a secret manager

## Known limitations: Termux

- `php-fpm -y fpm/www.conf -t` fails with `Cannot create lock - Permission denied (13)`
  on Android/Termux (SELinux restriction on php-fpm's shared-memory scoreboard).
  Not a config error. Validate pool configs in CI instead — see `.github/workflows/ci.yml`.
