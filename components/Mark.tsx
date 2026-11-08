/** The serdab door: an arch with a lamp-lit doorway and three steps down. */
export function Mark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="180 160 664 660" aria-hidden="true">
      <defs>
        <linearGradient id="mark-glow" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#F2B65A" stopOpacity="0" />
          <stop offset="55%" stopColor="#F2B65A" stopOpacity="0.18" />
          <stop offset="100%" stopColor="#F2B65A" stopOpacity="0.85" />
        </linearGradient>
        <clipPath id="mark-door">
          <path d="M 295.9 800 L 295.9 548.7 A 230 230 0 1 1 728.1 548.7 L 728.1 800 Z" />
        </clipPath>
      </defs>
      <g clipPath="url(#mark-door)">
        <rect x="200" y="200" width="624" height="600" fill="url(#mark-glow)" />
      </g>
      <rect x="362" y="598" width="300" height="22" rx="11" fill="var(--c-sand)" fillOpacity="0.45" />
      <rect x="392" y="658" width="240" height="22" rx="11" fill="var(--c-sand)" fillOpacity="0.7" />
      <rect x="422" y="718" width="180" height="22" rx="11" fill="var(--c-sand)" />
      <path
        d="M 295.9 800 L 295.9 548.7 A 230 230 0 1 1 728.1 548.7 L 728.1 800"
        fill="none"
        stroke="var(--c-sand)"
        strokeWidth="36"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M 190 800 H 834" stroke="var(--c-sand)" strokeWidth="36" strokeLinecap="round" />
    </svg>
  );
}
