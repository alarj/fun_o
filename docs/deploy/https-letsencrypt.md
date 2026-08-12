# HTTPS Setup (Let's Encrypt)

This project uses `nginx` in Docker Compose and `certbot` on the host machine with the `webroot` challenge.

Important:
- Do not use `certbot --standalone` on this server during normal operation.
- `standalone` tries to bind TCP port `80`, but that port is already used by `nginx`.
- The supported setup is host-side `certbot` + nginx `webroot` challenge + cron-based `certbot renew`.

## 1) Prerequisites

Make sure these conditions are true before issuing or renewing a certificate:
- DNS already points `fun-o.eu` and `www.fun-o.eu` to this server.
- Ports `80` and `443` are open in OCI Security List / NSG.
- Host machine has `certbot` installed.
- Host machine has directory `/var/www/certbot`.
- Docker Compose mounts `/var/www/certbot` into the `nginx` container.

The current repo configuration expects:
- host path `/var/www/certbot`
- container path `/var/www/certbot`
- ACME challenge location in `nginx/default.conf`:

```nginx
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
```

## 2) Start nginx and FastAPI

```bash
cd ~/fun_o
docker compose up -d nginx fastapi
```

## 3) Prepare the webroot on the host

```bash
sudo mkdir -p /var/www/certbot/.well-known/acme-challenge
sudo chown -R ubuntu:ubuntu /var/www/certbot
sudo chmod -R 755 /var/www/certbot
```

## 4) Verify that nginx can serve ACME challenge files

Create a temporary test file on the host:

```bash
echo test > /var/www/certbot/.well-known/acme-challenge/test-file
```

Verify that it is reachable over HTTP:

```bash
curl http://fun-o.eu/.well-known/acme-challenge/test-file
```

Expected result:

```text
test
```

If this returns `404`, do not continue before fixing nginx mount or file permissions.

## 5) Issue the initial certificate or replace an existing one with the webroot method

```bash
sudo certbot certonly --webroot -w /var/www/certbot \
  -d fun-o.eu -d www.fun-o.eu
```

If Certbot says an existing certificate is not yet due for renewal and asks whether to keep it or replace it, choose:
- `2: Renew & replace the certificate`

This is required when migrating from an older renewal configuration such as `standalone` to `webroot`.

## 6) Reload nginx after certificate issuance

```bash
docker compose exec -T nginx nginx -s reload
```

## 7) Verify the renewal configuration

Check that Certbot saved the certificate with the `webroot` authenticator:

```bash
sudo cat /etc/letsencrypt/renewal/fun-o.eu.conf
```

Expected key lines:

```text
authenticator = webroot
webroot_path = /var/www/certbot,
```

If the file still uses `standalone`, automatic renewal will fail later.

## 8) Automatic renewal

Automatic renewal is done by host cron, not by a Docker `certbot` service.

Current recommended root crontab entry:

```cron
0 3 * * * certbot renew --quiet && docker compose -f /home/ubuntu/fun_o/docker-compose.yml exec -T nginx nginx -s reload
```

Meaning:
- every day at `03:00`
- run `certbot renew --quiet`
- if renewal succeeds, reload nginx so the new certificate is picked up without a full container restart

## 9) Test automatic renewal safely

Use Certbot dry-run:

```bash
sudo certbot renew --dry-run
```

This must succeed before considering the setup complete.

## 10) Troubleshooting

### Error: `Could not bind TCP port 80`

Cause:
- renewal configuration is still using `standalone`
- or someone manually ran `certbot renew` / `certbot certonly` with `standalone`

Fix:
1. make sure `/var/www/certbot` is mounted into nginx
2. make sure ACME challenge file is reachable via `http://fun-o.eu/.well-known/acme-challenge/...`
3. re-issue the certificate with:

```bash
sudo certbot certonly --webroot -w /var/www/certbot \
  -d fun-o.eu -d www.fun-o.eu
```

4. verify `/etc/letsencrypt/renewal/fun-o.eu.conf` now uses `authenticator = webroot`

### Error: ACME test file returns `404`

Possible causes:
- `docker compose up -d nginx` was not run after changing mounts
- `/var/www/certbot` permissions are wrong on the host
- nginx config no longer points `/.well-known/acme-challenge/` to `/var/www/certbot`

### Error: new certificate exists on disk but site still serves the old one

Reload nginx:

```bash
docker compose exec -T nginx nginx -s reload
```

## Notes

- Reverse proxy must overwrite client IP headers for FastAPI. Current nginx config forwards `X-Real-IP` and overwrites `X-Forwarded-For` with `$remote_addr` so competitor join anti-bot does not trust client-supplied spoofed header chains.
- As of August 12, 2026, this project uses host-side Certbot renewal with `webroot`; documentation or muscle memory referring to a Compose-managed `certbot` renew loop is outdated.
