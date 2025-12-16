import { useState, useEffect } from 'react'
import './App.css'

function App() {
    const [hosts, setHosts] = useState([])
    const [loading, setLoading] = useState(false)

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
        const fetchHosts = async () => {
            try {
                const response = await fetch('http://localhost:3000/api/v1/hosts');
                if (response.ok) {
                    const data = await response.json();
                    setHosts(data);
                } else {
                    console.error('Failed to fetch hosts');
                }
            } catch (error) {
                console.error('Error connecting to backend:', error);
            } finally {
                setLoading(false);
            }
        };

        fetchHosts();
        const interval = setInterval(fetchHosts, 10000); // Poll every 10s
        return () => clearInterval(interval);
    }, [])

    return (
        <div className="container">
            <header className="header">
                <h1>PatchMon</h1>
                <div className="user-profile">Admin</div>
            </header>

            <main className="dashboard">
                <div className="stats-grid">
                    <div className="card stat-card">
                        <h3>Total Hosts</h3>
                        <p className="stat-value">{hosts.length}</p>
                    </div>
                    <div className="card stat-card">
                        <h3>Updates Pending</h3>
                        <p className="stat-value">12</p>
                    </div>
                    <div className="card stat-card">
                        <h3>Offline Agents</h3>
                        <p className="stat-value text-red">1</p>
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
                                        <td>{host.hostname}</td>
                                        <td>{host.os}</td>
                                        <td>{host.lastSeen}</td>
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

export default App
