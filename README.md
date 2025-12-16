# PatchMon - Linux Patch Monitoring Automation Platform

PatchMon provides centralized patch management across diverse server environments. Agents communicate outbound-only to the PatchMon server, eliminating inbound ports on monitored hosts while delivering comprehensive visibility and safe automation.

## Features
- **Dashboard**: Real-time overview of your server fleet.
- **Agent Check-in**: Secure, outbound-only communication from agents.
- **Remote Execution**: Trigger `apt-get update`, `upgrade`, or remove repositories directly from the UI.
- **Host Status**: Auto-detection of Offline/Online hosts.

## Getting Started

### Prerequisites
- Node.js (LTS)
- PostgreSQL

### Installation

#### 1. Backend
```bash
cd backend
npm install
# Configure .env with DATABASE_URL
npx prisma migrate dev --name init
npm start
```

#### 2. Frontend
```bash
cd frontend
npm install
npm run dev
```

#### 3. Agent (Linux Host)
```bash
# Edit server URL in script first
bash agent/patchmon-agent.sh
```

## Documentation
See the `docs/` folder for development plans and walkthroughs.
