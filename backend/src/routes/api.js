const express = require('express');
const router = express.Router();

const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// Get all hosts
router.get('/hosts', async (req, res) => {
    try {
        const hosts = await prisma.host.findMany({
            include: {
                packages: true,
            },
            orderBy: {
                lastSeen: 'desc',
            }
        });

        // Add computed status
        const hostsWithStatus = hosts.map(host => {
            const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
            const isOnline = host.lastSeen > fiveMinutesAgo;
            return {
                ...host,
                status: isOnline ? 'Online' : 'Offline'
            };
        });

        res.json(hostsWithStatus);
    } catch (error) {
        console.error('Error fetching hosts:', error);
        res.status(500).json({ error: 'Internal Server Error' });
    }
});

// Agent Check-in
router.post('/agent/checkin', async (req, res) => {
    try {
        const { hostname, os, packages } = req.body;

        if (!hostname) {
            return res.status(400).json({ error: 'Hostname is required' });
        }

        console.log(`Received checkin from ${hostname}`);

        // 1. Upsert Host
        const host = await prisma.host.upsert({
            where: { hostname },
            update: {
                lastSeen: new Date(),
                os: os,
                ipAddress: req.ip
            },
            create: {
                hostname,
                os,
                ipAddress: req.ip,
                lastSeen: new Date()
            }
        });

        // 2. Process Packages
        if (packages && Array.isArray(packages)) {
            for (const pkg of packages) {
                await prisma.package.upsert({
                    where: {
                        hostId_name: {
                            hostId: host.id,
                            name: pkg.name
                        }
                    },
                    update: {
                        version: pkg.version,
                        status: pkg.status || 'installed',
                        updatedAt: new Date()
                    },
                    create: {
                        hostId: host.id,
                        name: pkg.name,
                        version: pkg.version,
                        status: pkg.status || 'installed'
                    }
                });
            }
        }

        res.json({ success: true, hostId: host.id });
    } catch (error) {
        console.error('Check-in error:', error);
        res.status(500).json({ error: 'Failed to process check-in' });
    }
});

// --- Command Queue Endpoints ---

// 1. Create Command (Frontend calls this)
router.post('/hosts/:id/commands', async (req, res) => {
    try {
        const { type, payload } = req.body;
        const hostId = parseInt(req.params.id);

        const command = await prisma.command.create({
            data: {
                type,
                payload,
                hostId,
                status: 'pending'
            }
        });
        res.json(command);
    } catch (error) {
        console.error('Error creating command:', error);
        res.status(500).json({ error: 'Failed to allow command' });
    }
});

// 2. Poll for Commands (Agent calls this)
router.get('/agent/commands', async (req, res) => {
    try {
        const hostname = req.query.hostname;
        if (!hostname) return res.status(400).json({ error: 'Hostname required' });

        const host = await prisma.host.findUnique({ where: { hostname } });
        if (!host) return res.status(404).json({ error: 'Host not found' });

        // Get the oldest pending command
        const command = await prisma.command.findFirst({
            where: {
                hostId: host.id,
                status: 'pending'
            },
            orderBy: { createdAt: 'asc' }
        });

        if (command) {
            // Mark as sent so it's not picked up again immediately
            await prisma.command.update({
                where: { id: command.id },
                data: { status: 'sent' }
            });
            res.json({ command });
        } else {
            res.json({ command: null });
        }
    } catch (error) {
        console.error('Polling error:', error);
        res.status(500).json({ error: 'Internal Error' });
    }
});

// 3. Update Command Status (Agent calls this after execution)
router.post('/agent/commands/:id', async (req, res) => {
    try {
        const commandId = parseInt(req.params.id);
        const { status, output } = req.body;

        await prisma.command.update({
            where: { id: commandId },
            data: {
                status,
                output,
                updatedAt: new Date()
            }
        });
        res.json({ success: true });
    } catch (error) {
        console.error('Error updating command:', error);
        res.status(500).json({ error: 'Internal Error' });
    }
});

module.exports = router;
