import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertCircle, CheckCircle, Save, Server, Shield } from "lucide-react";
import { useEffect, useId, useState } from "react";
import { settingsAPI } from "../../utils/api";

const ProtocolUrlTab = () => {
	const protocolId = useId();
	const hostId = useId();
	const portId = useId();
	const [formData, setFormData] = useState({
		serverProtocol: "http",
		serverHost: "localhost",
		serverPort: 3001,
	});
	const [errors, setErrors] = useState({});
	const [isDirty, setIsDirty] = useState(false);

	const queryClient = useQueryClient();

	// Fetch current settings
	const {
		data: settings,
		isLoading,
		error,
	} = useQuery({
		queryKey: ["settings"],
		queryFn: () => settingsAPI.get().then((res) => res.data),
	});

	// Update form data when settings are loaded
	useEffect(() => {
		if (settings) {
			const newFormData = {
				serverProtocol: settings.server_protocol || "http",
				serverHost: settings.server_host || "localhost",
				serverPort: settings.server_port || 3001,
			};
			setFormData(newFormData);
			setIsDirty(false);
		}
	}, [settings]);

	// Update settings mutation
	const updateSettingsMutation = useMutation({
		mutationFn: (data) => {
			return settingsAPI.update(data).then((res) => res.data);
		},
		onSuccess: () => {
			queryClient.invalidateQueries(["settings"]);
			setIsDirty(false);
			setErrors({});
		},
		onError: (error) => {
			if (error.response?.data?.errors) {
				setErrors(
					error.response.data.errors.reduce((acc, err) => {
						acc[err.path] = err.msg;
						return acc;
					}, {}),
				);
			} else {
				setErrors({
					general: error.response?.data?.error || "Failed to update settings",
				});
			}
		},
	});

	const handleInputChange = (field, value) => {
		setFormData((prev) => ({
			...prev,
			[field]: value,
		}));
		setIsDirty(true);
		if (errors[field]) {
			setErrors((prev) => ({ ...prev, [field]: null }));
		}
	};

	const validateForm = () => {
		const newErrors = {};

		if (!formData.serverHost.trim()) {
			newErrors.serverHost = "Server host is required";
		}

		if (
			!formData.serverPort ||
			formData.serverPort < 1 ||
			formData.serverPort > 65535
		) {
			newErrors.serverPort = "Port must be between 1 and 65535";
		}

		setErrors(newErrors);
		return Object.keys(newErrors).length === 0;
	};

	const handleSave = () => {
		if (validateForm()) {
			updateSettingsMutation.mutate(formData);
		}
	};

	if (isLoading) {
		return (
			<div className="flex items-center justify-center h-64">
				<div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
			</div>
		);
	}

	if (error) {
		return (
			<div className="bg-red-50 dark:bg-red-900 border border-red-200 dark:border-red-700 rounded-md p-4">
				<div className="flex">
					<AlertCircle className="h-5 w-5 text-red-400 dark:text-red-300" />
					<div className="ml-3">
						<h3 className="text-sm font-medium text-red-800 dark:text-red-200">
							Error loading settings
						</h3>
						<p className="mt-1 text-sm text-red-700 dark:text-red-300">
							{error.response?.data?.error || "Failed to load settings"}
						</p>
					</div>
				</div>
			</div>
		);
	}

	return (
		<div className="space-y-6">
			{errors.general && (
				<div className="bg-red-50 dark:bg-red-900 border border-red-200 dark:border-red-700 rounded-md p-4">
					<div className="flex">
						<AlertCircle className="h-5 w-5 text-red-400 dark:text-red-300" />
						<div className="ml-3">
							<p className="text-sm text-red-700 dark:text-red-300">
								{errors.general}
							</p>
						</div>
					</div>
				</div>
			)}

			<form className="space-y-6">
				<div className="flex items-center mb-6">
					<Server className="h-6 w-6 text-primary-600 mr-3" />
					<h2 className="text-xl font-semibold text-secondary-900 dark:text-white">
						Server Configuration
					</h2>
				</div>

				<div className="grid grid-cols-1 md:grid-cols-3 gap-6">
					<div>
						<label
							htmlFor={protocolId}
							className="block text-sm font-medium text-secondary-700 dark:text-secondary-200 mb-2"
						>
							Protocol
						</label>
						<select
							id={protocolId}
							value={formData.serverProtocol}
							onChange={(e) =>
								handleInputChange("serverProtocol", e.target.value)
							}
							className="w-full border-secondary-300 dark:border-secondary-600 rounded-md shadow-sm focus:ring-primary-500 focus:border-primary-500 bg-white dark:bg-secondary-700 text-secondary-900 dark:text-white"
						>
							<option value="http">HTTP</option>
							<option value="https">HTTPS</option>
						</select>
					</div>

					<div>
						<label
							htmlFor={hostId}
							className="block text-sm font-medium text-secondary-700 dark:text-secondary-200 mb-2"
						>
							Host *
						</label>
						<input
							id={hostId}
							type="text"
							value={formData.serverHost}
							onChange={(e) => handleInputChange("serverHost", e.target.value)}
							className={`w-full border rounded-md shadow-sm focus:ring-primary-500 focus:border-primary-500 bg-white dark:bg-secondary-700 text-secondary-900 dark:text-white ${
								errors.serverHost
									? "border-red-300 dark:border-red-500"
									: "border-secondary-300 dark:border-secondary-600"
							}`}
							placeholder="example.com"
						/>
						{errors.serverHost && (
							<p className="mt-1 text-sm text-red-600 dark:text-red-400">
								{errors.serverHost}
							</p>
						)}
					</div>

					<div>
						<label
							htmlFor={portId}
							className="block text-sm font-medium text-secondary-700 dark:text-secondary-200 mb-2"
						>
							Port *
						</label>
						<input
							id={portId}
							type="number"
							value={formData.serverPort}
							onChange={(e) =>
								handleInputChange("serverPort", parseInt(e.target.value, 10))
							}
							className={`w-full border rounded-md shadow-sm focus:ring-primary-500 focus:border-primary-500 bg-white dark:bg-secondary-700 text-secondary-900 dark:text-white ${
								errors.serverPort
									? "border-red-300 dark:border-red-500"
									: "border-secondary-300 dark:border-secondary-600"
							}`}
							min="1"
							max="65535"
						/>
						{errors.serverPort && (
							<p className="mt-1 text-sm text-red-600 dark:text-red-400">
								{errors.serverPort}
							</p>
						)}
					</div>
				</div>

				<div className="mt-4 p-4 bg-secondary-50 dark:bg-secondary-700 rounded-md">
					<h4 className="text-sm font-medium text-secondary-900 dark:text-white mb-2">
						Server URL
					</h4>
					<p className="text-sm text-secondary-600 dark:text-secondary-300 font-mono">
						{formData.serverProtocol}://{formData.serverHost}:
						{formData.serverPort}
					</p>
					<p className="text-xs text-secondary-500 dark:text-secondary-400 mt-1">
						This URL will be used in installation scripts and agent
						communications.
					</p>
				</div>

				{/* Security Notice */}
				<div className="bg-blue-50 dark:bg-blue-900 border border-blue-200 dark:border-blue-700 rounded-md p-4">
					<div className="flex">
						<Shield className="h-5 w-5 text-blue-400 dark:text-blue-300" />
						<div className="ml-3">
							<h3 className="text-sm font-medium text-blue-800 dark:text-blue-200">
								Security Notice
							</h3>
							<p className="mt-1 text-sm text-blue-700 dark:text-blue-300">
								Changing these settings will affect all installation scripts and
								agent communications. Make sure the server URL is accessible
								from your client networks.
							</p>
						</div>
					</div>
				</div>

				{/* Save Button */}
				<div className="flex justify-end">
					<button
						type="button"
						onClick={handleSave}
						disabled={!isDirty || updateSettingsMutation.isPending}
						className={`inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white ${
							!isDirty || updateSettingsMutation.isPending
								? "bg-secondary-400 cursor-not-allowed"
								: "bg-primary-600 hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500"
						}`}
					>
						{updateSettingsMutation.isPending ? (
							<>
								<div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
								Saving...
							</>
						) : (
							<>
								<Save className="h-4 w-4 mr-2" />
								Save Settings
							</>
						)}
					</button>
				</div>

				{updateSettingsMutation.isSuccess && (
					<div className="bg-green-50 dark:bg-green-900 border border-green-200 dark:border-green-700 rounded-md p-4">
						<div className="flex">
							<CheckCircle className="h-5 w-5 text-green-400 dark:text-green-300" />
							<div className="ml-3">
								<p className="text-sm text-green-700 dark:text-green-300">
									Settings saved successfully!
								</p>
							</div>
						</div>
					</div>
				)}
			</form>
		</div>
	);
};

export default ProtocolUrlTab;
