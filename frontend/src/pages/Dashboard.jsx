import { useState, useEffect } from 'react'
import { useAuth } from '../context/AuthContext'
import '../App.css'
import { Link } from 'react-router-dom';
import PieChart from '../components/PieChart';

export default function Dashboard() {
    const [hosts, setHosts] = useState([])
    const [stats, setStats] = useState({ totalHosts: 0, onlineHosts: 0, offlineHosts: 0, pendingUpdates: 0 })
    const [loading, setLoading] = useState(false)
    const { logout, user } = useAuth();

    const handleCommand = async (hostId, type, payload = null) => {
        try {
            const response = await fetch(`http://localhost:3000/api/v1/hosts/${hostId}/commands`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type, payload })
            });
            if (response.ok) {
                alert(`Command ${type} sent successfully!`);
            } else {
                alert('Failed to send command');
            }
        } catch (error) {
            console.error('Error sending command:', error);
            alert('Error sending command');
        }
    };

    useEffect(() => {
        const fetchData = async () => {
            try {
                const [hostsRes, statsRes] = await Promise.all([
                    fetch('http://localhost:3000/api/v1/hosts'),
                    fetch('http://localhost:3000/api/v1/stats')
                ]);

                if (hostsRes.ok) setHosts(await hostsRes.json());
                if (statsRes.ok) setStats(await statsRes.json());

            } catch (error) {
                console.error('Error connecting to backend:', error);
            } finally {
                setLoading(false);
            }
        };

        fetchData();
        const interval = setInterval(fetchData, 10000);
        return () => clearInterval(interval);
    }, [])

    return (
        <div className="container">
            <header className="header">
                <h1>PatchMon</h1>
                <div className="user-profile">
                    <span>{user?.email}</span>
                    <button className="btn-sm" onClick={logout} style={{ marginLeft: '10px' }}>Logout</button>
                </div>
            </header>

            <main className="dashboard">
                <div className="stats-grid">
                    <div className="card stat-card" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div>
                            <h3>Host Status</h3>
                            <div style={{ fontSize: '0.9rem', color: '#666', marginTop: '5px' }}>
                                <span style={{ color: '#22c55e' }}>● {stats.onlineHosts} Online</span><br />
                                <span style={{ color: '#ef4444' }}>● {stats.offlineHosts} Offline</span>
                            </div>
                        </div>
                        <PieChart data={[
                            { value: stats.onlineHosts, color: '#22c55e', label: 'Online' },
                            { value: stats.offlineHosts, color: '#ef4444', label: 'Offline' }
                        ]} size={80} />
                    </div>

                    <div className="card stat-card">
                        <h3>Total Hosts</h3>
                        <p className="stat-value">{stats.totalHosts}</p>
                    </div>

                    <div className="card stat-card">
                        <h3>Pending Updates</h3>
                        <p className="stat-value">{stats.pendingUpdates || 0}</p>
                    </div>
                </div>

                <section className="hosts-section">
                    <h2>Managed Hosts</h2>
                    <div className="card">
                        <table className="hosts-table">
                            <thead>
                                <tr>
                                    <th>Hostname</th>
                                    <th>OS</th>
                                    <th>Last Seen</th>
                                    <th>Status</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {hosts.map(host => (
                                    <tr key={host.id}>
                                        <td>
                                            <Link to={`/hosts/${host.id}`} style={{ color: '#6366f1', fontWeight: 'bold' }}>
                                                {host.hostname}
                                            </Link>
                                        </td>
                                        <td>{host.os}</td>
                                        <td>{new Date(host.lastSeen).toLocaleTimeString()}</td>
                                        <td>
                                            <span className={`status-badge ${host.status.toLowerCase()}`}>
                                                {host.status}
                                            </span>
                                        </td>
                                        <td>
                                            <div className="action-buttons">
                                                <button className="btn-sm" onClick={() => handleCommand(host.id, 'update')}>Update</button>
                                                <button className="btn-sm" onClick={() => handleCommand(host.id, 'upgrade')}>Upgrade</button>
                                                <button className="btn-sm text-red" onClick={() => {
                                                    const repo = prompt("Enter repo to remove:");
                                                    if (repo) handleCommand(host.id, 'remove_repo', repo);
                                                }}>Remove Repo</button>
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </section>
            </main>
        </div>
    )
}
