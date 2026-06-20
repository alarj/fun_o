# HTTPS Setup (Let's Encrypt)

This setup uses `nginx` + `certbot` with webroot challenge.

## 1) Set your domain values

Edit:
- `.env`: `DOMAIN`, `LETSENCRYPT_EMAIL`
- `nginx/default.conf`: replace `example.com` with your real domain in:
  - `server_name`
  - `ssl_certificate`
  - `ssl_certificate_key`

## 2) Start HTTP stack first

```bash
cd ~/fun_o
docker compose up -d nginx fastapi
```

## 3) Issue initial certificate

```bash
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
  -d your-domain.tld -d www.your-domain.tld \
  --email your-email@example.com --agree-tos --no-eff-email
```

## 4) Start full stack (including renew loop)

```bash
docker compose up -d
```

## 5) Reload nginx after cert issuance

```bash
docker compose exec nginx nginx -s reload
```

## Notes

- Port `80` and `443` must be open in OCI Security List / NSG.
- DNS must already point to this server.
- Renewal runs every 12h in the `certbot` service.
- Reverse proxy must overwrite client IP headers for FastAPI. Current nginx config forwards `X-Real-IP` and overwrites `X-Forwarded-For` with `$remote_addr` so competitor join anti-bot does not trust client-supplied spoofed header chains.
