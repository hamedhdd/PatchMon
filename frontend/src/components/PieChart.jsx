export default function PieChart({ data, size = 100 }) {
    // data: [{ label, value, color }]
    const total = data.reduce((acc, item) => acc + item.value, 0);
    let cumulativeAngle = 0;

    if (total === 0) return <div style={{ width: size, height: size, background: '#eee', borderRadius: '50%' }}></div>;

    return (
        <svg viewBox="-1 -1 2 2" style={{ transform: 'rotate(-90deg)', width: size, height: size }}>
            {data.map((slice, i) => {
                const startAngle = cumulativeAngle;
                const sliceAngle = (slice.value / total) * 2 * Math.PI;
                cumulativeAngle += sliceAngle;

                const x1 = Math.cos(startAngle);
                const y1 = Math.sin(startAngle);
                const x2 = Math.cos(startAngle + sliceAngle);
                const y2 = Math.sin(startAngle + sliceAngle);

                const largeArcFlag = sliceAngle > Math.PI ? 1 : 0;

                const d = [
                    `M 0 0`,
                    `L ${x1} ${y1}`,
                    `A 1 1 0 ${largeArcFlag} 1 ${x2} ${y2}`,
                    `Z`
                ].join(' ');

                return <path d={d} fill={slice.color} key={i} title={`${slice.label}: ${slice.value}`} />;
            })}
        </svg>
    );
}
