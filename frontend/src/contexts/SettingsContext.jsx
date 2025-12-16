import { useQuery } from "@tanstack/react-query";
import { createContext, useContext } from "react";
import { isAuthReady } from "../constants/authPhases";
import { settingsAPI } from "../utils/api";
import { useAuth } from "./AuthContext";

const SettingsContext = createContext();

export const useSettings = () => {
	const context = useContext(SettingsContext);
	if (!context) {
		throw new Error("useSettings must be used within a SettingsProvider");
	}
	return context;
};

export const SettingsProvider = ({ children }) => {
	const { authPhase, isAuthenticated } = useAuth();

	const {
		data: settings,
		isLoading,
		error,
		refetch,
	} = useQuery({
		queryKey: ["settings"],
		queryFn: () => settingsAPI.get().then((res) => res.data),
		staleTime: 5 * 60 * 1000, // Settings stay fresh for 5 minutes
		refetchOnWindowFocus: false,
		enabled: isAuthReady(authPhase, isAuthenticated()),
	});

	const value = {
		settings,
		isLoading,
		error,
		refetch,
	};

	return (
		<SettingsContext.Provider value={value}>
			{children}
		</SettingsContext.Provider>
	);
};
