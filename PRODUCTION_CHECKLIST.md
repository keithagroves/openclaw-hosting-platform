# Production Checklist

## 1. Accounts & API Keys

- [ ] **Hetzner Cloud** — Create account, generate API token at https://console.hetzner.cloud
- [ ] **Cloudflare** — Add your domain, note Zone ID and Account ID from the dashboard
- [ ] **Cloudflare API Token** — Create at https://dash.cloudflare.com/profile/api-tokens with permissions:
  - Zone → DNS → Edit
  - Account → Access: Apps and Policies → Edit
- [ ] **Stripe** — Create account, get Secret Key from https://dashboard.stripe.com/apikeys
- [ ] **Stripe Product** — Create a $20/month recurring product, copy the Price ID (`price_xxx`)
- [ ] **Stripe Webhook** — Add endpoint `https://admin.<your-domain>/webhook` with events:
  - `checkout.session.completed`
  - `customer.subscription.deleted`
  - `invoice.payment_failed`
- [ ] Copy the Webhook Signing Secret (`whsec_xxx`)

## 2. DNS & Domain

- [ ] Domain registered and nameservers pointed to Cloudflare
- [ ] Verify domain is active in Cloudflare dashboard (status: Active)
- [ ] Terraform will create A records automatically (root, admin, wildcard)

## 3. SSH Key

- [ ] Generate a deploy key if you don't have one:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/openclaw_deploy -C "openclaw-deploy"
  ```
- [ ] Note the path — you'll use it in `terraform.tfvars`

## 4. Deploy Infrastructure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Fill in all values in terraform.tfvars

terraform init
terraform plan        # Review what will be created
terraform apply       # Create server + DNS records
```

- [ ] `terraform apply` completes without errors
- [ ] Note the outputs:
  ```bash
  terraform output server_ip
  terraform output -raw admin_api_key
  terraform output ssh_command
  ```

## 5. Wait for Bootstrap

Cloud-init runs automatically on first boot (~5-10 minutes). Monitor progress:

```bash
ssh root@<server-ip>
tail -f /var/log/cloud-init-output.log
```

- [ ] Cloud-init finishes (check `/var/log/openclaw-setup.log`)
- [ ] Docker is running: `docker ps`
- [ ] openclaw-desktop image is built: `docker images | grep openclaw`
- [ ] Caddy is running: `docker ps | grep caddy`
- [ ] Webhook service is running: `docker ps | grep webhook`

## 6. Configure Stripe (on server)

Cloud-init doesn't have your Stripe keys (they aren't in Terraform). SSH in and add them:

```bash
ssh root@<server-ip>
vi /opt/openclaw/.env
# Add: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PRICE_ID

cd /opt/openclaw
docker compose -f docker-compose.webhook.yml --env-file .env up -d
```

- [ ] Stripe env vars are set in `/opt/openclaw/.env`
- [ ] Webhook service restarted with Stripe keys

## 7. Verify Services

- [ ] Landing page loads: `https://admin.<your-domain>`
- [ ] HTTPS certificate is valid (Caddy auto-provisions via Let's Encrypt)
- [ ] Admin API responds:
  ```bash
  curl -H "Authorization: Bearer <admin-api-key>" \
    https://admin.<your-domain>/admin/customers
  ```

## 8. Test Stripe Integration

Use Stripe test mode first:

- [ ] Click "Subscribe" on the landing page
- [ ] Complete checkout with test card `4242 4242 4242 4242`
- [ ] Webhook receives `checkout.session.completed`
- [ ] Container is provisioned (check `docker ps`)
- [ ] DNS record is created in Cloudflare
- [ ] Cloudflare Access policy is created
- [ ] Success page shows the desktop URL
- [ ] Desktop is accessible at `https://<subdomain>.<your-domain>`
- [ ] Google login prompt appears (Cloudflare Access)

## 9. Test Deprovisioning

- [ ] Cancel the test subscription in Stripe dashboard
- [ ] Webhook receives `customer.subscription.deleted`
- [ ] Container is removed
- [ ] DNS record is deleted
- [ ] Access policy is removed

## 10. Go Live

- [ ] Switch Stripe to live mode — update keys in `/opt/openclaw/.env`
- [ ] Create live webhook endpoint in Stripe (same URL, same events)
- [ ] Update `STRIPE_WEBHOOK_SECRET` with the live signing secret
- [ ] Restart webhook service:
  ```bash
  cd /opt/openclaw && docker compose -f docker-compose.webhook.yml --env-file .env up -d
  ```
- [ ] Do one real purchase to verify end-to-end

## 11. Ongoing Operations

- [ ] Backups are running nightly (check `/var/log/openclaw-backup.log`)
- [ ] Set up monitoring/alerting (uptime check on `https://admin.<your-domain>`)
- [ ] To update the platform:
  ```bash
  ssh root@<server-ip>
  cd /opt/openclaw/repo && git pull
  docker build -t openclaw-desktop:latest .
  /opt/openclaw/scripts/rolling_update.sh
  ```
