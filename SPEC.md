Goal: Create a sellable, browser-accessible remote desktop service with ClawBot pre-installed.
Stack:

Base image: KasmVNC Ubuntu desktop Docker image (kasmweb/ubuntu-jammy-desktop)
Application: ClawBot, installed via curl -fsSL https://openclaw.ai/install.sh | bash
Access: Customers connect via browser to a web-based desktop (KasmVNC on port 6901), authenticated with a per-customer password

Requirements:

Custom Dockerfile that extends the Kasm Ubuntu image and pre-installs ClawBot
Per-customer Docker containers with isolated environments
Password authentication set via environment variable (VNC_PW) per customer
Persistent volume mounts for customer data
Reverse proxy (e.g., Nginx/Caddy) with HTTPS in front of each instance
A simple orchestration method (docker-compose or a script) to spin up/tear down customer instances and assign unique ports or subdomains
Hosted on budget-friendly infrastructure (Hetzner, OVH, or similar) to keep costs low

Nice-to-haves:

Customer onboarding script that auto-provisions a container and returns login credentials
Resource limits per container (CPU/RAM) to prevent one customer from impacting others
Monitoring/health checks on running containers