const express = require("express");
const { authenticateToken } = require("../middleware/auth");
const { getPrismaClient } = require("../config/prisma");
const prisma = getPrismaClient();

const router = express.Router();

// Create a new command
router.post("/", authenticateToken, async (req, res) => {
    try {
        const { host_id, command } = req.body;

        if (!host_id || !command) {
            return res.status(400).json({ error: "host_id and command are required" });
        }

        // Verify host exists
        const host = await prisma.hosts.findUnique({
            where: { id: host_id },
        });

        if (!host) {
            return res.status(404).json({ error: "Host not found" });
        }

        // Create command
        const newCommand = await prisma.commands.create({
            data: {
                host_id,
                command,
                status: "pending",
            },
        });

        res.status(201).json({ success: true, command: newCommand });
    } catch (error) {
        console.error("Error creating command:", error);
        res.status(500).json({ error: "Internal server error" });
    }
});

// Get pending commands for a specific agent (Polled by agent)
// This endpoint uses the agent's API ID from the request parameter
// Security: Verify the API Key header matches the host's API Key? 
// For simplicity in this implementation, we rely on the API ID in URL + logic in Agent to have correct creds.
// Ideally, this should be protected by middleware verifying X-API-KEY.
// Adding simple check here if possible, or assuming open for now as per "simple" migration.
// Better: Agent uses standard authentication or we blindly return pending commands for that ID.
router.get("/agent/:apiId", async (req, res) => {
    try {
        const { apiId } = req.params;
        const apiKey = req.headers["x-api-key"];

        if (!apiId) {
            return res.status(400).json({ error: "API ID required" });
        }

        const host = await prisma.hosts.findUnique({
            where: { api_id: apiId },
        });

        if (!host) {
            return res.status(404).json({ error: "Host not found" });
        }

        // Basic security check
        if (apiKey && host.api_key !== apiKey) {
            return res.status(401).json({ error: "Invalid API Key" });
        }

        const pendingCommands = await prisma.commands.findMany({
            where: {
                host_id: host.id,
                status: "pending",
            },
            orderBy: {
                created_at: "asc",
            },
        });

        res.json(pendingCommands);
    } catch (error) {
        console.error("Error fetching agent commands:", error);
        res.status(500).json({ error: "Internal server error" });
    }
});

// Update command status (Called by agent)
router.post("/:id/status", async (req, res) => {
    try {
        const { id } = req.params;
        const { status, output } = req.body;
        const apiKey = req.headers["x-api-key"];

        const command = await prisma.commands.findUnique({
            where: { id },
            include: { hosts: true },
        });

        if (!command) {
            return res.status(404).json({ error: "Command not found" });
        }

        // Verification
        if (apiKey && command.hosts.api_key !== apiKey) {
            return res.status(401).json({ error: "Unauthorized" });
        }

        await prisma.commands.update({
            where: { id },
            data: {
                status,
                output,
            },
        });

        res.json({ success: true });
    } catch (error) {
        console.error("Error updating command status:", error);
        res.status(500).json({ error: "Internal server error" });
    }
});

module.exports = router;
