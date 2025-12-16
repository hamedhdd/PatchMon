import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';

export default function HostDetails() {
    const { id } = useParams();
    const [host, setHost] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // In a real app, you'd fetch /api/v1/hosts/:id
        // For now we'll simulate or fetch all and filter
        const fetchHost = async () => {
            try {
                const response = await fetch('http://localhost:3000/api/v1/hosts');
                const data = await response.json();
                const found = data.find(h => h.id === parseInt(id));
                setHost(found);
            } catch (error) {
                console.error(error);
            } finally {
                setLoading(false);
            }
        };
        fetchHost();
    }, [id]);

    if (loading) return <div>Loading...</div>;
    if (!host) return <div>Host not found</div>;

    return (
        <div className="container">
            <Link to="/" className="btn-sm">Back to Dashboard</Link>
            <div className="card" style={{ marginTop: '20px' }}>
                <h2>{host.hostname}</h2>
                <div className="grid-details">
                    <p><strong>OS:</strong> {host.os}</p>
                    <p><strong>IP:</strong> {host.ipAddress}</p>
                    <p><strong>Status:</strong> {host.status}</p>
                    <p><strong>Last Seen:</strong> {new Date(host.lastSeen).toLocaleString()}</p>
                </div>

                <h3>Installed Packages</h3>
                <table className="hosts-table">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Version</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        {host.packages && host.packages.map(pkg => (
                            <tr key={pkg.id}>
                                <td>{pkg.name}</td>
                                <td>{pkg.version}</td>
                                <td>{pkg.status}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );
}
