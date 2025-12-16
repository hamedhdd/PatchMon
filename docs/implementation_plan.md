# PatchMon Scaffolding Plan

## Goal Description
Recreate the PatchMon architecture: A Linux Patch Monitoring Automation Platform.
Stack: Node.js/Express + Prisma + PostgreSQL (Backend), Vite + React (Frontend).

## User Review Required
> [!IMPORTANT]
> **Node.js is not detected on your system.**
> I tried running `node -v` and `npm -v` but they failed. This project requires Node.js.
> Please install Node.js (LTS version recommended) and ensure it's in your PATH.

## Proposed Changes

### Backend
Directory: `backend/`
- `package.json`: Dependencies: express, prisma, @prisma/client, cors, dotenv, etc.
- `prisma/schema.prisma`: Define schema for Users, Hosts, Packages, **and Commands**.
- `src/index.js`: Main server file.
- `src/routes/api.js`: API routes (Check-in, Hosts, **Command Queue**).

### Frontend
Directory: `frontend/`
- Vite + React setup.
- `index.css`: Basic styling (Vanilla CSS as per guidelines).
- `App.jsx`: Main dashboard **+ Host Details & Actions**.

### Agent
Directory: `agent/`
- `patchmon-agent.sh`: Bash script to collect package info, **poll for commands, and execute them**.

## Verification Plan
### Automated Tests
- None for now.

### Manual Verification
1. [User Action] Install Node.js.
2. Start backend `npm start`.
3. Start frontend `npm run dev`.
4. Run agent script and verify data appears in backend logs/DB (mocked if necessary).
