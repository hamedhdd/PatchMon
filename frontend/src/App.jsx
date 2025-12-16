import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import HostDetails from './pages/HostDetails';
import './App.css';

const ProtectedRoute = ({ children }) => {
    const { token } = useAuth();
    if (!token) return <Navigate to="/login" replace />;
    return children;
};

function App() {
    return (
        <AuthProvider>
            <BrowserRouter>
                <Routes>
                    <Route path="/login" element={<Login />} />
                    <Route path="/hosts/:id" element={
                        <ProtectedRoute>
                            <HostDetails />
                        </ProtectedRoute>
                    } />
                    <Route path="/" element={
                        <ProtectedRoute>
                            <Dashboard />
                        </ProtectedRoute>
                    } />
                </Routes>
            </BrowserRouter>
        </AuthProvider>
    );
}

export default App;
