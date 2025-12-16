# PatchMon Setup Instructions

> [!IMPORTANT]
> Because of system environment restrictions, I could not execute the code myself. Please follow these steps to run the application.

## Prerequisites
- Node.js (LTS) installed (e.g. v20)
- PostgreSQL running or a valid connection string

## Backend Setup
1. Navigate to backend:
   ```bash
   cd backend
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Configure Environment:
   Create a `.env` file in `backend/` with your database URL:
   ```
   DATABASE_URL="postgresql://user:password@localhost:5432/patchmon?schema=public"
   PORT=3000
   ```
4. Run Database Migrations:
   ```bash
   npx prisma generate
   npx prisma migrate dev --name add_commands
   ```
5. Start Server:
   ```bash
   npm start
   ```

## Frontend Setup
1. Navigate to frontend:
   ```bash
   cd frontend
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Start Dev Server:
   ```bash
   npm run dev
   ```
   Access at `http://localhost:5173`.

## Agent Setup
1. Run the agent script on a Linux host (or simulating one):
   ```bash
   bash agent/patchmon-agent.sh
   ```
   *Note: Ensure the agent script points to your backend URL.*

## Using Remote Execution
1. Go to the Dashboard.
2. In the "Managed Hosts" table, use the **Update**, **Upgrade**, or **Remove Repo** buttons.
3. The Agent will pick up the command on its next poll (in the script loop) and execute it.
4. Output will be sent back to the server (visible in DB, UI for details not yet implemented).

## Troubleshooting
If `npm` or `node` are not found, ensure they are added to your System PATH manually.
