#!/bin/bash

echo "PatchMon Setup Information"
echo "-------------------------"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed."
    exit 1
fi

echo "Installing Backend Dependencies..."
cd backend
npm install

if [ ! -f .env ]; then
    echo "Creating .env file..."
    echo "DATABASE_URL=\"postgresql://user:password@localhost:5432/patchmon?schema=public\"" > .env
    echo "JWT_SECRET=\"change_this_to_a_secure_random_string\"" >> .env
    echo "PORT=3000" >> .env
    echo "Please update backend/.env with your database credentials."
fi

echo "Running Database Migrations..."
npx prisma migrate deploy
if [ $? -ne 0 ]; then
    echo "Warning: Database migration failed. Check your connection string."
fi

echo "Seeding Admin User..."
if [ -f create_admin.js ]; then
    node create_admin.js
fi

cd ..

echo "Installing Frontend Dependencies..."
cd frontend
npm install

echo "Building Frontend..."
npm run build

echo "-------------------------"
echo "Setup Complete!"
echo "To start the backend: cd backend && npm start"
echo "To serve frontend: Configure Nginx to serve frontend/dist"
