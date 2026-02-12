import json
import os
import subprocess
import fcntl
from pathlib import Path

import stripe
from flask import Flask, request, jsonify, render_template, redirect, url_for

app = Flask(__name__)

# Configuration
stripe.api_key = os.environ["STRIPE_SECRET_KEY"]
WEBHOOK_SECRET = os.environ["STRIPE_WEBHOOK_SECRET"]
STRIPE_PRICE_ID = os.environ["STRIPE_PRICE_ID"]
BASE_DOMAIN = os.environ.get("BASE_DOMAIN", "reptar.ai")
ADMIN_API_KEY = os.environ.get("ADMIN_API_KEY", "")
DATA_DIR = Path(os.environ.get("CLAWBOT_DATA_DIR", "/data"))
DB_FILE = DATA_DIR / "customers.json"
SCRIPTS_DIR = Path("/app/scripts")


def _read_db():
    """Read the customer database."""
    if not DB_FILE.exists():
        return []
    with open(DB_FILE) as f:
        return json.load(f)


def _write_db(data):
    """Write the customer database with file locking."""
    DB_FILE.parent.mkdir(parents=True, exist_ok=True)
    lock_path = DB_FILE.with_suffix(".json.lock")
    with open(lock_path, "w") as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        with open(DB_FILE, "w") as f:
            json.dump(data, f, indent=2)
        fcntl.flock(lock_f, fcntl.LOCK_UN)


def _find_customer_by_email(email):
    """Find a customer by email."""
    for c in _read_db():
        if c.get("email") == email:
            return c
    return None


def _find_customer(subdomain):
    """Find a customer by subdomain."""
    for c in _read_db():
        if c["subdomain"] == subdomain:
            return c
    return None


def _find_customer_by_subscription(subscription_id):
    """Find a customer by Stripe subscription ID."""
    for c in _read_db():
        if c.get("stripe_subscription_id") == subscription_id:
            return c
    return None


def _provision(email, stripe_customer_id="", stripe_subscription_id=""):
    """Run the provisioning script (subdomain auto-generated) and return (success, output)."""
    cmd = [str(SCRIPTS_DIR / "provision_customer.sh"), "--email", email]
    if stripe_customer_id:
        cmd += ["--stripe-customer-id", stripe_customer_id]
    if stripe_subscription_id:
        cmd += ["--stripe-subscription-id", stripe_subscription_id]

    env = {**os.environ}
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        app.logger.error("Provisioning failed for %s: %s", email, result.stderr)
        return False, result.stderr
    app.logger.info("Provisioned for %s: %s", email, result.stdout.strip())
    return True, result.stdout.strip()


def _deprovision(subdomain):
    """Run the deprovisioning script and return (success, output)."""
    cmd = [str(SCRIPTS_DIR / "deprovision_customer.sh"), subdomain]
    result = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ})
    if result.returncode != 0:
        app.logger.error("Deprovisioning failed for %s: %s", subdomain, result.stderr)
        return False, result.stderr
    app.logger.info("Deprovisioned %s", subdomain)
    return True, result.stdout.strip()


def _require_admin(f):
    """Decorator to require admin API key."""
    from functools import wraps

    @wraps(f)
    def decorated(*args, **kwargs):
        if not ADMIN_API_KEY:
            return jsonify({"error": "admin API key not configured"}), 500
        auth = request.headers.get("Authorization", "")
        if auth != f"Bearer {ADMIN_API_KEY}":
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)

    return decorated


# ── Landing Page ──────────────────────────────────────────────────────────────


@app.route("/")
def index():
    return render_template("index.html", base_domain=BASE_DOMAIN, price_id=STRIPE_PRICE_ID)


# ── Checkout Flow ─────────────────────────────────────────────────────────────


@app.route("/api/create-checkout-session", methods=["POST"])
def create_checkout_session():
    session = stripe.checkout.Session.create(
        mode="subscription",
        line_items=[{"price": STRIPE_PRICE_ID, "quantity": 1}],
        success_url=f"https://admin.{BASE_DOMAIN}/success?session_id={{CHECKOUT_SESSION_ID}}",
        cancel_url=f"https://admin.{BASE_DOMAIN}/?cancelled=true",
    )
    return redirect(session.url)


@app.route("/success")
def success():
    session_id = request.args.get("session_id", "")
    if not session_id:
        return redirect(url_for("index"))

    try:
        session = stripe.checkout.Session.retrieve(session_id)
    except stripe.StripeError:
        return redirect(url_for("index"))

    email = session.get("customer_details", {}).get("email", "")
    customer = _find_customer_by_email(email)

    return render_template(
        "success.html",
        subdomain=customer["subdomain"] if customer else "",
        base_domain=BASE_DOMAIN,
        customer=customer,
        email=email,
    )


# ── Status Polling ────────────────────────────────────────────────────────────


@app.route("/api/status/<subdomain>")
def status(subdomain):
    container_name = f"clawbot-{subdomain.replace('.', '-')}"
    result = subprocess.run(
        ["docker", "inspect", "--format", "{{.State.Health.Status}}", container_name],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return jsonify({"ready": False, "status": "not_found"})

    health = result.stdout.strip()
    return jsonify({"ready": health == "healthy", "status": health})


# ── Stripe Webhook ────────────────────────────────────────────────────────────


@app.route("/webhook", methods=["POST"])
def webhook():
    payload = request.get_data()
    sig_header = request.headers.get("Stripe-Signature", "")

    try:
        event = stripe.Webhook.construct_event(payload, sig_header, WEBHOOK_SECRET)
    except (ValueError, stripe.SignatureVerificationError) as e:
        app.logger.warning("Webhook signature verification failed: %s", e)
        return jsonify({"error": "invalid signature"}), 400

    event_type = event["type"]
    app.logger.info("Received Stripe event: %s", event_type)

    if event_type == "checkout.session.completed":
        session = event["data"]["object"]
        email = session.get("customer_details", {}).get("email", "")
        stripe_customer_id = session.get("customer", "")
        stripe_subscription_id = session.get("subscription", "")

        if email:
            _provision(email, stripe_customer_id, stripe_subscription_id)

    elif event_type == "customer.subscription.deleted":
        subscription = event["data"]["object"]
        subscription_id = subscription["id"]
        customer = _find_customer_by_subscription(subscription_id)
        if customer:
            _deprovision(customer["subdomain"])

    elif event_type == "invoice.payment_failed":
        invoice = event["data"]["object"]
        subscription_id = invoice.get("subscription", "")
        if subscription_id:
            customer = _find_customer_by_subscription(subscription_id)
            if customer:
                db = _read_db()
                for c in db:
                    if c["subdomain"] == customer["subdomain"]:
                        c["status"] = "payment_failed"
                _write_db(db)
                app.logger.warning(
                    "Payment failed for customer: %s", customer["subdomain"]
                )

    return jsonify({"received": True}), 200


# ── Admin API ─────────────────────────────────────────────────────────────────


@app.route("/admin/customers")
@_require_admin
def admin_customers():
    return jsonify(_read_db())


@app.route("/admin/provision", methods=["POST"])
@_require_admin
def admin_provision():
    data = request.get_json(force=True)
    email = data.get("email", "").strip().lower()
    if not email:
        return jsonify({"error": "email required"}), 400
    if _find_customer_by_email(email):
        return jsonify({"error": "customer with this email already exists"}), 400
    ok, output = _provision(email)
    if not ok:
        return jsonify({"error": output}), 500
    return jsonify({"message": output})


@app.route("/admin/deprovision", methods=["POST"])
@_require_admin
def admin_deprovision():
    data = request.get_json(force=True)
    subdomain = data.get("subdomain", "").strip().lower()
    if not subdomain:
        return jsonify({"error": "subdomain required"}), 400
    ok, output = _deprovision(subdomain)
    if not ok:
        return jsonify({"error": output}), 500
    return jsonify({"message": output})
