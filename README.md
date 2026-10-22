# php-hardening

Opinionated PHP hardening configs — drop-in php.ini, php-fpm pool,
nginx / Apache snippets, systemd sandbox, and a self-auditing script.

**Scope:** reduce the blast radius of the usual PHP attack surface
(RCE via `exec`/`shell_exec`, LFI via `allow_url_include`, info leak via
`expose_php`/`display_errors`, session hijacking, unsafe uploads).

**Not in scope:** application-level bugs. Pair this with SAST, WAF,
and per-project code review.

## Quick start

```bash
# 1. audit the running config against the baseline
./scripts/audit.sh

# 2. deploy on Debian/Ubuntu (writes *.hardened files, never overwrites)
sudo ./scripts/install.sh

# 3. review, then promote
sudo diff /etc/php/8.4/fpm/php.ini.d/99-hardening.ini /etc/php/8.4/fpm/conf.d/99-hardening.ini
sudo systemctl restart php8.4-fpm
tree
php.ini.d/     production & dev php.ini overrides (scan-dir style)
fpm/           php-fpm pool config with isolation + admin overrides
nginx/         security headers, hidden-file deny, fastcgi block
apache/        mod_headers + <FilesMatch> deny + proxy_fcgi
scripts/       audit.sh (checks running config), install.sh (deploy)
tests/         probe.php — single-page runtime report
docker/        hardened Dockerfile.fpm + docker-compose.yml
systemd/       php-fpm-hardening.conf drop-in (sandboxing)
docs/          SECURITY-CHECKLIST.md

Compatibility

Tested on Debian 12 / Ubuntu 24.04 / Alpine 3.20 / Termux (aarch64).
RHEL/Rocky users: apply the ini and pool manually — paths differ.

License

MIT — see LICENSE.
