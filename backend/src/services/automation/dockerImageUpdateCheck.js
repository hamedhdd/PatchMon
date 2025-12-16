const { prisma } = require("./shared/prisma");
const https = require("node:https");
const http = require("node:http");
const { v4: uuidv4 } = require("uuid");

/**
 * Docker Image Update Check Automation
 * Checks for Docker image updates by comparing local digests with remote registry digests
 */
class DockerImageUpdateCheck {
	constructor(queueManager) {
		this.queueManager = queueManager;
		this.queueName = "docker-image-update-check";
	}

	/**
	 * Get remote digest from Docker registry using HEAD request
	 * Supports Docker Hub, GHCR, and other OCI-compliant registries
	 */
	async getRemoteDigest(imageName, tag = "latest") {
		return new Promise((resolve, reject) => {
			// Parse image name to determine registry
			const registryInfo = this.parseImageName(imageName);

			// Construct manifest URL
			const manifestPath = `/v2/${registryInfo.repository}/manifests/${tag}`;
			const options = {
				hostname: registryInfo.registry,
				path: manifestPath,
				method: "HEAD",
				headers: {
					Accept:
						"application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json",
					"User-Agent": "PatchMon/1.0",
				},
			};

			// Add authentication token for Docker Hub if needed
			if (
				registryInfo.registry === "registry-1.docker.io" &&
				registryInfo.isPublic
			) {
				// For anonymous public images, we may need to get an auth token first
				// For now, try without auth (works for public images)
			}

			// Choose HTTP or HTTPS
			const client = registryInfo.isSecure ? https : http;

			const req = client.request(options, (res) => {
				if (res.statusCode === 401 || res.statusCode === 403) {
					// Authentication required - skip for now (would need to implement auth)
					return reject(
						new Error(`Authentication required for ${imageName}:${tag}`),
					);
				}

				if (res.statusCode !== 200) {
					return reject(
						new Error(
							`Registry returned status ${res.statusCode} for ${imageName}:${tag}`,
						),
					);
				}

				// Get digest from Docker-Content-Digest header
				const digest = res.headers["docker-content-digest"];
				if (!digest) {
					return reject(
						new Error(
							`No Docker-Content-Digest header for ${imageName}:${tag}`,
						),
					);
				}

				// Clean up digest (remove sha256: prefix if present)
				const cleanDigest = digest.startsWith("sha256:")
					? digest.substring(7)
					: digest;
				resolve(cleanDigest);
			});

			req.on("error", (error) => {
				reject(error);
			});

			req.setTimeout(10000, () => {
				req.destroy();
				reject(new Error(`Timeout getting digest for ${imageName}:${tag}`));
			});

			req.end();
		});
	}

	/**
	 * Parse image name to extract registry, repository, and determine if secure
	 */
	parseImageName(imageName) {
		let registry = "registry-1.docker.io";
		let repository = imageName;
		const isSecure = true;
		let isPublic = true;

		// Handle explicit registries (ghcr.io, quay.io, etc.)
		if (imageName.includes("/")) {
			const parts = imageName.split("/");
			const firstPart = parts[0];

			// Check for known registries
			if (firstPart.includes(".") || firstPart === "localhost") {
				registry = firstPart;
				repository = parts.slice(1).join("/");
				isPublic = false; // Assume private registries need auth for now
			} else {
				// Docker Hub - registry-1.docker.io
				repository = imageName;
			}
		}

		// Docker Hub official images (no namespace)
		if (!repository.includes("/")) {
			repository = `library/${repository}`;
		}

		return {
			registry,
			repository,
			isSecure,
			isPublic,
		};
	}

	/**
	 * Process Docker image update check job
	 */
	async process(_job) {
		const startTime = Date.now();
		console.log("🐳 Starting Docker image update check...");

		try {
			// Get all Docker images that have a digest
			// Note: repository is required (non-nullable) in schema, so we don't need to check it
			const images = await prisma.docker_images.findMany({
				where: {
					digest: {
						not: null,
					},
				},
				include: {
					docker_image_updates: true,
				},
			});

			console.log(`📦 Found ${images.length} images to check for updates`);

			let checkedCount = 0;
			let updateCount = 0;
			let errorCount = 0;
			const errors = [];

			// Process images in batches to avoid overwhelming the API
			const batchSize = 10;
			for (let i = 0; i < images.length; i += batchSize) {
				const batch = images.slice(i, i + batchSize);

				// Process batch concurrently with Promise.allSettled for error tolerance
				const _results = await Promise.allSettled(
					batch.map(async (image) => {
						try {
							checkedCount++;

							// Skip local images (no digest means they're local)
							if (!image.digest || image.digest.trim() === "") {
								return { image, skipped: true, reason: "No digest" };
							}

							// Get clean digest (remove sha256: prefix if present)
							const localDigest = image.digest.startsWith("sha256:")
								? image.digest.substring(7)
								: image.digest;

							// Get remote digest from registry
							const remoteDigest = await this.getRemoteDigest(
								image.repository,
								image.tag || "latest",
							);

							// Compare digests
							if (localDigest !== remoteDigest) {
								console.log(
									`🔄 Update found: ${image.repository}:${image.tag} (local: ${localDigest.substring(0, 12)}..., remote: ${remoteDigest.substring(0, 12)}...)`,
								);

								// Store digest info in changelog_url field as JSON
								const digestInfo = JSON.stringify({
									method: "digest_comparison",
									current_digest: localDigest,
									available_digest: remoteDigest,
									checked_at: new Date().toISOString(),
								});

								// Upsert the update record
								await prisma.docker_image_updates.upsert({
									where: {
										image_id_available_tag: {
											image_id: image.id,
											available_tag: image.tag || "latest",
										},
									},
									update: {
										updated_at: new Date(),
										changelog_url: digestInfo,
										severity: "digest_changed",
									},
									create: {
										id: uuidv4(),
										image_id: image.id,
										current_tag: image.tag || "latest",
										available_tag: image.tag || "latest",
										severity: "digest_changed",
										changelog_url: digestInfo,
										updated_at: new Date(),
									},
								});

								// Update last_checked timestamp on image
								await prisma.docker_images.update({
									where: { id: image.id },
									data: { last_checked: new Date() },
								});

								updateCount++;
								return { image, updated: true };
							} else {
								// No update - still update last_checked
								await prisma.docker_images.update({
									where: { id: image.id },
									data: { last_checked: new Date() },
								});

								// Remove existing update record if digest matches now
								const existingUpdate = image.docker_image_updates?.find(
									(u) => u.available_tag === (image.tag || "latest"),
								);
								if (existingUpdate) {
									await prisma.docker_image_updates.delete({
										where: { id: existingUpdate.id },
									});
								}

								return { image, updated: false };
							}
						} catch (error) {
							errorCount++;
							const errorMsg = `Error checking ${image.repository}:${image.tag}: ${error.message}`;
							errors.push(errorMsg);
							console.error(`❌ ${errorMsg}`);

							// Still update last_checked even on error
							try {
								await prisma.docker_images.update({
									where: { id: image.id },
									data: { last_checked: new Date() },
								});
							} catch (_updateError) {
								// Ignore update errors
							}

							return { image, error: error.message };
						}
					}),
				);

				// Log batch progress
				if (i + batchSize < images.length) {
					console.log(
						`⏳ Processed ${Math.min(i + batchSize, images.length)}/${images.length} images...`,
					);
				}

				// Small delay between batches to be respectful to registries
				if (i + batchSize < images.length) {
					await new Promise((resolve) => setTimeout(resolve, 500));
				}
			}

			const executionTime = Date.now() - startTime;
			console.log(
				`✅ Docker image update check completed in ${executionTime}ms - Checked: ${checkedCount}, Updates: ${updateCount}, Errors: ${errorCount}`,
			);

			return {
				success: true,
				checked: checkedCount,
				updates: updateCount,
				errors: errorCount,
				executionTime,
				errorDetails: errors,
			};
		} catch (error) {
			const executionTime = Date.now() - startTime;
			console.error(
				`❌ Docker image update check failed after ${executionTime}ms:`,
				error.message,
			);
			throw error;
		}
	}

	/**
	 * Schedule recurring Docker image update check (daily at 2 AM)
	 */
	async schedule() {
		const job = await this.queueManager.queues[this.queueName].add(
			"docker-image-update-check",
			{},
			{
				repeat: { cron: "0 2 * * *" }, // Daily at 2 AM
				jobId: "docker-image-update-check-recurring",
			},
		);
		console.log("✅ Docker image update check scheduled");
		return job;
	}

	/**
	 * Trigger manual Docker image update check
	 */
	async triggerManual() {
		const job = await this.queueManager.queues[this.queueName].add(
			"docker-image-update-check-manual",
			{},
			{ priority: 1 },
		);
		console.log("✅ Manual Docker image update check triggered");
		return job;
	}
}

module.exports = DockerImageUpdateCheck;
