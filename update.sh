#!/bin/bash

echo "PatchMon Update Script"
echo "----------------------"

# Pull latest code
echo "Pulling latest changes from git..."
git pull

# Update Backend
echo "Updating Backend..."
cd backend
npm install
npx prisma migrate deploy
cd ..

# Update Frontend
echo "Updating Frontend..."
cd frontend
npm install
npm run build
cd ..

echo "----------------------"
echo "Update Complete."
echo "If running with PM2, remember to restart: pm2 restart patchmon"
