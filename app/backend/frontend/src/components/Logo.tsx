// Nedbank mark recreated as a crisp inline SVG (razor-sharp at any size): the
// signature green square tile with the stylised angular "N" in white negative
// space, paired with the Sentinel lockup. Used for a spectacular hero on the
// landing page and a compact mark in the top bar.

export function NedbankMark({ size = 40, color = "#006341" }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" fill="none" aria-hidden>
      {/* Green square tile */}
      <rect x="4" y="4" width="92" height="92" rx="6" fill={color} />
      {/* Stylised angular "N" carved in white — two uprights + diagonal */}
      <path d="M26 74 V26 H38 L62 58 V26 H74 V74 H62 L38 42 V74 Z" fill="#ffffff" />
    </svg>
  );
}

// Large hero lockup for the landing page.
export function HeroLogo() {
  return (
    <div className="hero-logo">
      <div className="hero-glow" />
      <div className="hero-inner">
        <NedbankMark size={48} color="#ffffff" />
        <div className="hero-wordmark">
          <span className="hero-nedbank">NEDBANK</span>
          <span className="hero-divider" />
          <span className="hero-sentinel">Sentinel</span>
        </div>
      </div>
      <div className="hero-tag">CDP &amp; Financial Crime Intelligence Platform</div>
    </div>
  );
}

// Compact mark for the top bar.
export function BrandMark() {
  return (
    <div className="brandmark">
      <NedbankMark size={26} color="#006341" />
      <span className="brandmark-text"><b>NEDBANK</b> Sentinel</span>
    </div>
  );
}
